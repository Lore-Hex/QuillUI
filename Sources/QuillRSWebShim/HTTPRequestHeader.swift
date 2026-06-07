//
//  HTTPRequestHeader.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). HTTP request
//  header-name constants — Foundation-only, compiles unchanged on macOS and Linux.
//

import Foundation

nonisolated public struct HTTPRequestHeader {

	public static let userAgent = "User-Agent"
	public static let authorization = "Authorization"
	public static let contentType = "Content-Type"

	// Conditional GET

	public static let ifModifiedSince = "If-Modified-Since"
	public static let ifNoneMatch = "If-None-Match" // Etag
}
