//
//  Array+RSCore.swift
//  RSCore
//
//  Created by Brent Simmons on 2/17/18.
//  Copyright © 2018 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSCore module into the
//  live RSCore clone (QuillRSCoreShim, module-aliased to `RSCore`). Pure Swift
//  Array helpers (safe subscript + chunking) — compiles unchanged on macOS and
//  Linux.
//

import Foundation

public extension Array {
	subscript(safe index: Index) -> Element? {
		indices.contains(index) ? self[index] : nil
	}

	func chunked(into size: Int) -> [[Element]] {
		return stride(from: 0, to: count, by: size).map {
			Array(self[$0 ..< Swift.min($0 + size, count)])
		}
	}
}
