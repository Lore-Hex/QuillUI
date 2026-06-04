//
//  MimeType.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). First of the
//  RSWeb HTTP value types; Foundation-only (pure String logic) so it compiles
//  unchanged on macOS and Linux.
//

import Foundation

nonisolated public struct MimeType: Sendable {

	// This could certainly use expansion.

	public static let png = "image/png"
	public static let jpeg = "image/jpeg"
	public static let jpg = "image/jpg"
	public static let gif = "image/gif"
	public static let tiff = "image/tiff"

	public static let formURLEncoded = "application/x-www-form-urlencoded"
}

nonisolated public extension String {

	func isMimeTypeImage() -> Bool {

		return self.isOfGeneralMimeType("image")
	}

	func isMimeTypeAudio() -> Bool {

		return self.isOfGeneralMimeType("audio")
	}

	func isMimeTypeVideo() -> Bool {

		return self.isOfGeneralMimeType("video")
	}

	func isMimeTypeTimeBasedMedia() -> Bool {

		return self.isMimeTypeAudio() || self.isMimeTypeVideo()
	}

	private func isOfGeneralMimeType(_ type: String) -> Bool {

		let lower = self.lowercased()
		if lower.hasPrefix(type) {
			return true
		}
		if lower.hasPrefix("x-\(type)") {
			return true
		}
		return false
	}
}
