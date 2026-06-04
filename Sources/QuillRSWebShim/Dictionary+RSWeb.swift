//
//  Dictionary+RSWeb.swift
//  RSWeb
//
//  Created by Brent Simmons on 1/13/18.
//  Copyright © 2018 Ranchero Software. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). Builds a URL
//  query string from a [String: String] via URLComponents (Foundation, not
//  FoundationNetworking) — compiles unchanged on macOS and Linux.
//

import Foundation

nonisolated public extension Dictionary where Key == String, Value == String {

	/// Translates a dictionary into a string like `foo=bar&param2=some%20thing`.
	var urlQueryString: String? {

		var components = URLComponents()

		components.queryItems = self.reduce(into: [URLQueryItem]()) {
			$0.append(URLQueryItem(name: $1.key, value: $1.value))
		}

		let s = components.percentEncodedQuery

		return s == nil || s!.isEmpty ? nil : s
	}
}
