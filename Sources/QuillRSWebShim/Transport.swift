//
//  Transport.swift
//  RSWeb
//
//  Quill bring-up: NetNewsWire RSWeb transport protocol and URLSession-backed
//  implementation, kept source-compatible for service modules such as NewsBlur.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated public protocol Transport: Sendable {
    func cancelAll()

    @discardableResult
    func send(request: URLRequest) async throws -> (HTTPURLResponse, Data)
    func send(request: URLRequest, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void)

    func send(request: URLRequest, method: String) async throws
    func send(request: URLRequest, method: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void)

    func send(request: URLRequest, method: String, payload: Data) async throws -> (HTTPURLResponse, Data)
    func send(request: URLRequest, method: String, payload: Data, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void)
}

nonisolated extension URLSession: Transport {
    public static let webservice: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60.0
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        if let headers = UserAgent.headers() {
            configuration.httpAdditionalHeaders = headers
        }
        return URLSession(configuration: configuration)
    }()

    public func cancelAll() {
        getTasksWithCompletionHandler { dataTasks, uploadTasks, downloadTasks in
            for task in dataTasks {
                task.cancel()
            }
            for task in uploadTasks {
                task.cancel()
            }
            for task in downloadTasks {
                task.cancel()
            }
        }
    }

    public func send(request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let (response, data) = try await withCheckedThrowingContinuation { continuation in
            send(request: request) { result in
                continuation.resume(with: result)
            }
        }
        guard let data else {
            throw TransportError.noData
        }
        return (response, data)
    }

    public func send(request: URLRequest, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void) {
        let task = dataTask(with: request) { data, response, error in
            self.complete(response: response, data: data, error: error, completion: completion)
        }
        task.resume()
    }

    public func send(request: URLRequest, method: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            send(request: request, method: method) { result in
                continuation.resume(with: result)
            }
        }
    }

    public func send(request: URLRequest, method: String, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        var sendRequest = request
        sendRequest.httpMethod = method

        let task = dataTask(with: sendRequest) { _, response, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    completion(.failure(TransportError.noData))
                    return
                }
                guard response.statusIsOK else {
                    completion(.failure(TransportError.httpError(status: response.forcedStatusCode)))
                    return
                }
                completion(.success(()))
            }
        }
        task.resume()
    }

    public func send(request: URLRequest, method: String, payload: Data) async throws -> (HTTPURLResponse, Data) {
        let (response, data) = try await withCheckedThrowingContinuation { continuation in
            send(request: request, method: method, payload: payload) { result in
                continuation.resume(with: result)
            }
        }
        guard let data else {
            throw TransportError.noData
        }
        return (response, data)
    }

    public func send(request: URLRequest, method: String, payload: Data, completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void) {
        var sendRequest = request
        sendRequest.httpMethod = method

        let task = uploadTask(with: sendRequest, from: payload) { data, response, error in
            self.complete(response: response, data: data, error: error, completion: completion)
        }
        task.resume()
    }

    public static func webserviceTransport() -> Transport {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60.0
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    private func complete(
        response: URLResponse?,
        data: Data?,
        error: Error?,
        completion: @escaping @Sendable (Result<(HTTPURLResponse, Data?), Error>) -> Void
    ) {
        DispatchQueue.main.async {
            if let error {
                completion(.failure(error))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(TransportError.noData))
                return
            }
            guard response.statusIsOK else {
                completion(.failure(TransportError.httpError(status: response.forcedStatusCode)))
                return
            }
            completion(.success((response, data)))
        }
    }
}

nonisolated public extension Transport {
    func send<P: Encodable & Sendable>(request: URLRequest, method: String, payload: P) async throws {
        try await withCheckedThrowingContinuation { continuation in
            send(request: request, method: method, payload: payload) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func send<P: Encodable>(
        request: URLRequest,
        method: String,
        payload: P,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        var postRequest = request
        postRequest.addValue("application/json; charset=utf-8", forHTTPHeaderField: HTTPRequestHeader.contentType)

        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        send(request: postRequest, method: method, payload: data) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func send<P: Encodable, R: Decodable>(
        request: URLRequest,
        method: String,
        payload: P,
        resultType: R.Type,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys,
        completion: @escaping @Sendable (Result<(HTTPURLResponse, R?), Error>) -> Void
    ) {
        var postRequest = request
        postRequest.addValue("application/json; charset=utf-8", forHTTPHeaderField: HTTPRequestHeader.contentType)

        let data: Data
        do {
            data = try JSONEncoder().encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        send(request: postRequest, method: method, payload: data) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (response, data)):
                    do {
                        completion(.success(try decode(response: response, data: data, dateDecoding: dateDecoding, keyDecoding: keyDecoding)))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func send<R: Decodable & Sendable>(
        request: URLRequest,
        resultType: R.Type,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) async throws -> (HTTPURLResponse, R?) {
        let (response, data) = try await send(request: request)
        return try decode(response: response, data: data, dateDecoding: dateDecoding, keyDecoding: keyDecoding)
    }

    func send<R: Decodable & Sendable>(
        request: URLRequest,
        method: String,
        data: Data,
        resultType: R.Type,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) async throws -> (HTTPURLResponse, R?) {
        let (response, data) = try await send(request: request, method: method, payload: data)
        return try decode(response: response, data: data, dateDecoding: dateDecoding, keyDecoding: keyDecoding)
    }

    func send<P: Encodable & Sendable, R: Decodable & Sendable>(
        request: URLRequest,
        method: String,
        payload: P,
        resultType: R.Type,
        dateDecoding: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecoding: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) async throws -> (HTTPURLResponse, R?) {
        try await withCheckedThrowingContinuation { continuation in
            send(
                request: request,
                method: method,
                payload: payload,
                resultType: resultType,
                dateDecoding: dateDecoding,
                keyDecoding: keyDecoding
            ) { result in
                continuation.resume(with: result)
            }
        }
    }
}

private func decode<R: Decodable>(
    response: HTTPURLResponse,
    data: Data?,
    dateDecoding: JSONDecoder.DateDecodingStrategy,
    keyDecoding: JSONDecoder.KeyDecodingStrategy
) throws -> (HTTPURLResponse, R?) {
    guard let data, !data.isEmpty else {
        return (response, nil)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = dateDecoding
    decoder.keyDecodingStrategy = keyDecoding
    return (response, try decoder.decode(R.self, from: data))
}
