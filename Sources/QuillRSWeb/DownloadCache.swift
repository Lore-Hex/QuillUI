//
//  DownloadCache.swift
//  RSWeb
//
//  Created by Brent Simmons on 10/16/25.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import QuillRSCoreShim

struct DownloadCacheRecord: CacheRecord, Sendable {
	let dateCreated = Date()
	let data: Data?
	let response: URLResponse?

	init(data: Data?, response: URLResponse?) {
		self.data = data
		self.response = response
	}
}

nonisolated final class DownloadCache: Sendable {
	static let shared = DownloadCache()

	private let cache = Cache<DownloadCacheRecord>(timeToLive: 60 * 13, timeBetweenCleanups: 60 * 2)

	init() {
		// Block-form observers instead of #selector — Linux's
		// Swift toolchain has no Objective-C runtime, so the
		// upstream #selector pattern fails to compile there.
		// Closure form has identical semantics on Darwin.
		NotificationCenter.default.addObserver(
			forName: .appDidGoToBackground, object: nil, queue: nil
		) { [weak self] _ in
			self?.cache.removeAll()
		}
		NotificationCenter.default.addObserver(
			forName: .lowMemory, object: nil, queue: nil
		) { [weak self] _ in
			self?.cache.removeAll()
		}
	}

	subscript(_ key: String) -> DownloadCacheRecord? {
		get {
			cache[key]
		}
		set {
			cache[key] = newValue
		}
	}

	func add(_ urlString: String, data: Data?, response: URLResponse?) {
		let cacheRecord = DownloadCacheRecord(data: data, response: response)
		cache[urlString] = cacheRecord
	}
}
