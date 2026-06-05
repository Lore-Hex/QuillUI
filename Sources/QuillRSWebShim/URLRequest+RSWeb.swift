//
//  NSMutableURLRequest+RSWeb.swift
//  RSWeb
//
//  Created by Brent Simmons on 12/27/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). Adds a Basic
//  Authorization header. On Linux URLRequest lives in FoundationNetworking (the
//  Foundation networking split), conditionally imported below; otherwise verbatim.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // URLRequest lives here on Linux
#endif

public extension URLRequest {

	@discardableResult mutating func addBasicAuthorization(username: String, password: String) -> Bool {

		// Do this *only* with https. And not even then if you can help it.

		let s = "\(username):\(password)"
		guard let d = s.data(using: .utf8, allowLossyConversion: false) else {
			return false
		}

		let base64EncodedString = d.base64EncodedString()
		let authorization = "Basic \(base64EncodedString)"
		setValue(authorization, forHTTPHeaderField: HTTPRequestHeader.authorization)

		return true
	}
}
