//
//  DownloadCache.swift
//  NetNewsWire — vendored into the RSWeb clone (QuillRSWebShim)
//
//  Created by Brent Simmons on 10/16/25.
//  Copyright © Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: the in-memory download cache behind real
//  `FeedFinder.find(url:)` / `downloadUsingCache` — the next rung toward the
//  full real download path. Two adaptations from upstream:
//    - `import RSCore` → `import QuillRSCoreShim` (clone module name)
//    - the `@objc` selector-based NotificationCenter observers become
//      block-based: `@objc`/`#selector` need the Objective-C runtime, which
//      Linux Swift doesn't have. Same notifications, same removeAll behavior;
//      the observer tokens are intentionally kept for the singleton's
//      process-long lifetime, matching upstream's never-removed observers.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/RSWeb/Sources/RSWeb/DownloadCache.swift
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
		// Tokens intentionally dropped: the singleton's observers live for the
		// whole process, matching upstream's never-removed selector observers.
		_ = NotificationCenter.default.addObserver(
			forName: .appDidGoToBackground, object: nil, queue: nil
		) { [cache] _ in
			cache.removeAll()
		}
		_ = NotificationCenter.default.addObserver(
			forName: .lowMemory, object: nil, queue: nil
		) { [cache] _ in
			cache.removeAll()
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
