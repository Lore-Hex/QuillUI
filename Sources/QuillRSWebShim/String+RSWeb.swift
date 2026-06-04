//
//  String+RSWeb.swift
//  RSWeb
//
//  Created by Brent Simmons on 1/13/18.
//  Copyright © 2018 Ranchero Software. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). Pure String
//  HTML-escaping helper — compiles unchanged on macOS and Linux.
//

import Foundation

nonisolated public extension String {

	/// Escapes special HTML characters.
	///
	/// Escaped characters are `&`, `<`, `>`, `"`, and `'`.
	var escapedHTML: String {
		var escaped = String()

		for char in self {
			switch char {
			case "&":
				escaped.append("&amp;")
			case "<":
				escaped.append("&lt;")
			case ">":
				escaped.append("&gt;")
			case "\"":
				escaped.append("&quot;")
			case "'":
				escaped.append("&apos;")
			default:
				escaped.append(char)
			}
		}

		return escaped
	}
}
