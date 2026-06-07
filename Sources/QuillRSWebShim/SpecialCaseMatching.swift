//
//  SpecialCases.swift
//  RSWeb — vendored subset into QuillRSWebShim
//
//  Created by Brent Simmons on 12/12/24.
//
//  Quill bring-up: the host-matching subset of RSWeb's SpecialCases.swift —
//  the `SpecialCase` domain table + the `URL.isRachelByTheBayURL` /
//  `isOpenRSSOrgURL` / `isYoutubeURL` helpers reached by the real NetNewsWire
//  FeedFinder (FeedSpecifier.knownFeedSpecifier). `localeForLowercasing` is
//  already vendored in SpecialCasesLocale.swift (same module), so it is not
//  redefined here. The `Set<URL>` / `URLRequest` / `UserAgent.extendedUserAgent`
//  remainder of the upstream file is still deferred (Bundle.main force-unwraps).
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/RSWeb/Sources/RSWeb/SpecialCases.swift
//

import Foundation

nonisolated public struct SpecialCase {
	public static let rachelByTheBayHostName = "rachelbythebay.com"
	public static let openRSSOrgHostName = "openrss.org"
	public static let youtubeHostName = "youtube.com"

	public static func urlStringContainSpecialCase(_ urlString: String, _ specialCases: [String]) -> Bool {
		let lowerURLString = urlString.lowercased(with: localeForLowercasing)
		for specialCase in specialCases {
			if lowerURLString.contains(specialCase) {
				return true
			}
		}
		return false
	}
}

nonisolated extension URL {

	public var isOpenRSSOrgURL: Bool {
		guard let host = host() else {
			return false
		}
		return SpecialCase.urlStringContainSpecialCase(host, [SpecialCase.openRSSOrgHostName])
	}

	public var isRachelByTheBayURL: Bool {
		guard let host = host() else {
			return false
		}
		return SpecialCase.urlStringContainSpecialCase(host, [SpecialCase.rachelByTheBayHostName])
	}

	public var isYoutubeURL: Bool {
		guard let host = host() else {
			return false
		}
		return SpecialCase.urlStringContainSpecialCase(host, [SpecialCase.youtubeHostName])
	}
}
