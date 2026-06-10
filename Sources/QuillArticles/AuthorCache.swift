//
//  AuthorCache.swift
//  Articles
//
//  Created by Brent Simmons on 4/28/26.
//

import Foundation
import os
import QuillRSCoreShim

/// Caches `Author` values by `authorID` so articles by the same author share
/// the same `Author` value (and underlying String storage). Cleared on `.lowMemory`.
public final class AuthorCache: Sendable {

	public static let shared = AuthorCache()

	private let cache = OSAllocatedUnfairLock<[String: Author]>(initialState: [:])

	init() {
		if !Platform.isRunningUnitTests {
			// Block-based observer instead of #selector — Linux's
			// Swift toolchain has no Objective-C runtime, so the
			// upstream #selector path fails to compile there. The
			// block form has identical semantics on Darwin.
			_ = NotificationCenter.default.addObserver(
				forName: .lowMemory,
				object: nil,
				queue: nil
			) { [weak self] _ in
				self?.clear()
			}
		}
	}

	public func add(_ authors: Set<Author>) -> Set<Author> {
		cache.withLock { dict in
			Set(authors.map { author in
				if let existing = dict[author.authorID] {
					return existing
				}
				dict[author.authorID] = author
				return author
			})
		}
	}

	public func clear() {
		cache.withLock { $0.removeAll() }
	}
}

#if DEBUG
extension AuthorCache {

	/// For tests only.
	func count() -> Int {
		cache.withLock { $0.count }
	}
}
#endif
