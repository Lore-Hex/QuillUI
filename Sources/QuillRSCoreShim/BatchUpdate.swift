//
//  BatchUpdates.swift
//  DataModel
//
//  Created by Brent Simmons on 9/12/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Foundation-
//  only main-thread batch-update nesting counter that posts
//  `.BatchUpdateDidPerform` when the outermost batch ends — used by RSCore
//  source to coalesce UI refreshes. Compiles unchanged on macOS and Linux.
//

import Foundation

// Main thread only.

public typealias BatchUpdateBlock = () -> Void

public extension Notification.Name {
	/// A notification posted when a batch update completes.
	static let BatchUpdateDidPerform = Notification.Name(rawValue: "BatchUpdateDidPerform")
}

/// A class for batch updating.
@MainActor public final class BatchUpdate {

	/// The shared batch update object.
	public static let shared = BatchUpdate()

	private var count = 0

	/// Is updating in progress?
	public var isPerforming: Bool {
		precondition(Thread.isMainThread)
		return count > 0
	}

	/// Perform a batch update.
	public func perform(_ batchUpdateBlock: BatchUpdateBlock) {
		precondition(Thread.isMainThread)
		incrementCount()
		batchUpdateBlock()
		decrementCount()
	}

	/// Start batch updates.
	public func start() {
		precondition(Thread.isMainThread)
		incrementCount()
	}

	/// End batch updates.
	public func end() {
		precondition(Thread.isMainThread)
		decrementCount()
	}
}

private extension BatchUpdate {

	func incrementCount() {
		count += 1
	}

	func decrementCount() {
		count -= 1
		if count < 1 {
			assert(count > -1, "Expected batch updates count to be 0 or greater.")
			count = 0
			postBatchUpdateDidPerform()
		}
	}

	func postBatchUpdateDidPerform() {
		if !Thread.isMainThread {
			DispatchQueue.main.sync {
				NotificationCenter.default.post(name: .BatchUpdateDidPerform, object: nil, userInfo: nil)
			}
		} else {
			NotificationCenter.default.post(name: .BatchUpdateDidPerform, object: nil, userInfo: nil)
		}
	}
}
