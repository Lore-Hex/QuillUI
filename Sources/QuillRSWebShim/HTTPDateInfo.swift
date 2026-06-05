//
//  HTTPDateInfo.swift
//  RSWeb
//
//  Created by Maurice Parker on 5/12/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//
//  Quill bring-up: vendored verbatim from NetNewsWire's RSWeb module into the
//  live RSWeb clone (Sources/QuillRSWebShim, the `RSWeb` module). Parses the HTTP
//  Date header. On Linux HTTPURLResponse lives in FoundationNetworking (the
//  Foundation networking split), conditionally imported below; otherwise verbatim.
//  Note: upstream's DateFormatter sets no locale, so successful parsing is
//  locale-dependent — the tests assert only the locale-independent nil paths.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // HTTPURLResponse lives here on Linux
#endif

nonisolated public struct HTTPDateInfo: Codable, Equatable {

	private static let formatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
		return dateFormatter
	}()

	public let date: Date?

	public init?(urlResponse: HTTPURLResponse) {
		if let headerDate = urlResponse.valueForHTTPHeaderField(HTTPResponseHeader.date) {
			date = HTTPDateInfo.formatter.date(from: headerDate)
		} else {
			date = nil
		}
	}

}
