//
//  Downloader.swift
//  RSWeb
//
//  Created by Brent Simmons on 8/27/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: source-compatible one-shot Downloader surface used by
//  NetNewsWire FeedFinder. This keeps the upstream callback and async API
//  shape, backed by URLSession on Linux/macOS, while deferring the larger
//  DownloadSession/progress subsystem.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public typealias DownloadCallback = @MainActor (Data?, URLResponse?, Error?) -> Swift.Void

@MainActor public final class Downloader {
    public static let shared = Downloader()

    private struct CachedRecord {
        let dateCreated: Date
        let data: Data?
        let response: URLResponse?
    }

    private let urlSession: URLSession
    private let cacheTimeToLive: TimeInterval
    private var callbacks = [URL: [DownloadCallback]]()
    private var cache = [String: CachedRecord]()

    public convenience init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpCookieStorage = nil

        if let userAgent = Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String {
            configuration.httpAdditionalHeaders = [HTTPRequestHeader.userAgent: userAgent]
        }

        self.init(urlSession: URLSession(configuration: configuration), cacheTimeToLive: 60 * 3)
    }

    init(urlSession: URLSession, cacheTimeToLive: TimeInterval) {
        self.urlSession = urlSession
        self.cacheTimeToLive = cacheTimeToLive
    }

    deinit {
        urlSession.invalidateAndCancel()
    }

    public func download(_ url: URL) async throws -> (Data?, URLResponse?) {
        try await withCheckedThrowingContinuation { continuation in
            download(url) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, response))
                }
            }
        }
    }

    public func download(_ url: URL, _ callback: @escaping DownloadCallback) {
        download(URLRequest(url: url), callback)
    }

    public func download(_ urlRequest: URLRequest, _ callback: @escaping DownloadCallback) {
        guard let url = urlRequest.url else {
            callback(nil, nil, nil)
            return
        }

        guard url.isHTTPOrHTTPSURL() else {
            callback(nil, nil, nil)
            return
        }

        let isCacheableRequest = (urlRequest.httpMethod ?? HTTPMethod.get) == HTTPMethod.get
        if isCacheableRequest, let cachedRecord = cachedRecord(for: url.absoluteString) {
            callback(cachedRecord.data, cachedRecord.response, nil)
            return
        }

        if callbacks[url] == nil {
            callbacks[url] = [callback]
        } else {
            callbacks[url]?.append(callback)
            return
        }

        let task = urlSession.dataTask(with: urlRequest) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else {
                    return
                }
                if isCacheableRequest {
                    self.cache[url.absoluteString] = CachedRecord(
                        dateCreated: Date(),
                        data: data,
                        response: response
                    )
                }
                self.callAndReleaseCallbacks(url, data, response, error)
            }
        }
        task.resume()
    }

    private func cachedRecord(for key: String) -> CachedRecord? {
        guard let record = cache[key] else {
            return nil
        }
        guard Date().timeIntervalSince(record.dateCreated) < cacheTimeToLive else {
            cache[key] = nil
            return nil
        }
        return record
    }

    private func callAndReleaseCallbacks(
        _ url: URL,
        _ data: Data? = nil,
        _ response: URLResponse? = nil,
        _ error: Error? = nil
    ) {
        defer {
            callbacks[url] = nil
        }

        guard let callbacksForURL = callbacks[url] else {
            return
        }

        for callback in callbacksForURL {
            callback(data, response, error)
        }
    }
}
