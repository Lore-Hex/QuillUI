//
//  HTTPResponse429.swift
//  NetNewsWire — vendored into the RSWeb clone (QuillRSWebShim)
//
//  Created by Brent Simmons on 11/24/24.
//  Copyright © Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim (upstream file is named File.swift in
//  some checkouts; content unchanged). 429 Too Many Requests bookkeeping —
//  DownloadSession uses it to pause per-host requests until Retry-After
//  elapses. Foundation-only; `URL.host()` exists on Linux via
//  FoundationEssentials.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/RSWeb/Sources/RSWeb/HTTPResponse429.swift
//

import Foundation

// 429 Too Many Requests

struct HTTPResponse429 {

	let url: URL
	let host: String // lowercased
	let dateCreated: Date
	let retryAfter: TimeInterval

	var resumeDate: Date {
		dateCreated + TimeInterval(retryAfter)
	}
	var canResume: Bool {
		Date() >= resumeDate
	}

	init?(url: URL, retryAfter: TimeInterval) {

		guard let host = url.host() else {
			return nil
		}

		self.url = url
		self.host = host.lowercased()
		self.retryAfter = retryAfter
		self.dateCreated = Date()
	}
}
