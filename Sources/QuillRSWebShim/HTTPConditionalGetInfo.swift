//
//  HTTPConditionalGetInfo.swift
//  RSWeb
//
//  Created by Brent Simmons on 4/11/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). Conditional-GET
//  (Last-Modified / Etag) info. On Linux HTTPURLResponse and URLRequest live in
//  FoundationNetworking (the Foundation networking split), conditionally imported
//  below; otherwise verbatim.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // HTTPURLResponse / URLRequest live here on Linux
#endif

public struct HTTPConditionalGetInfo: Codable, Equatable, Sendable {

	public let lastModified: String?
	public let etag: String?

	public init?(lastModified: String?, etag: String?) {
		if lastModified == nil && etag == nil {
			return nil
		}
		self.lastModified = lastModified
		self.etag = etag
	}

	public init?(urlResponse: HTTPURLResponse) {
		let lastModified = urlResponse.valueForHTTPHeaderField(HTTPResponseHeader.lastModified)
		let etag = urlResponse.valueForHTTPHeaderField(HTTPResponseHeader.etag)
		self.init(lastModified: lastModified, etag: etag)
	}

	public init?(headers: [AnyHashable: Any]) {
		let lastModified = headers[HTTPResponseHeader.lastModified] as? String
		let etag = headers[HTTPResponseHeader.etag] as? String
		self.init(lastModified: lastModified, etag: etag)
	}

	public func addRequestHeadersToURLRequest(_ urlRequest: inout URLRequest) {
		// Bug seen in the wild: lastModified with last possible 32-bit date, which is in 2038. Ignore those.
		// TODO: drop this check in late 2037.
		if let lastModified = lastModified, !lastModified.contains("2038") {
			urlRequest.addValue(lastModified, forHTTPHeaderField: HTTPRequestHeader.ifModifiedSince)
		}
		if let etag = etag {
			urlRequest.addValue(etag, forHTTPHeaderField: HTTPRequestHeader.ifNoneMatch)
		}
	}
}
