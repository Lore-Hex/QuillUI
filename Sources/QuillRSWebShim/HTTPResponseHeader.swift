//
//  HTTPResponseHeader.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). HTTP response
//  header-name constants — Foundation-only, compiles unchanged on macOS and
//  Linux. Dependency base for the RSWeb header-parsing value types.
//

import Foundation

nonisolated public struct HTTPResponseHeader: Sendable {

	public static let contentType = "Content-Type"
	public static let location = "Location"
	public static let link = "Links"
	public static let date = "Date"

	// Conditional GET. See:
	// http://fishbowl.pastiche.org/2002/10/21/http_conditional_get_for_rss_hackers/

	public static let lastModified = "Last-Modified"
	// Changed to the canonical case for lookups against a case sensitive dictionary
	// https://developer.apple.com/documentation/foundation/httpurlresponse/1417930-allheaderfields
	public static let etag = "Etag"

	public static let cacheControl = "Cache-Control"
	public static let retryAfter = "Retry-After"
}
