//
//  HTTPMethod.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/26/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). HTTP method
//  name constants — Foundation-only, compiles unchanged on macOS and Linux.
//

import Foundation

nonisolated public struct HTTPMethod {
	public static let get = "GET"
	public static let post = "POST"
	public static let put = "PUT"
	public static let patch = "PATCH"
	public static let delete = "DELETE"
}
