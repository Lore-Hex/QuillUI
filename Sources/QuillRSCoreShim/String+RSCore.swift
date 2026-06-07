//
//  String+RSCore.swift
//  NetNewsWire — vendored into QuillRSCoreShim
//
//  Created by Brent Simmons.
//  Copyright © Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: a focused, Foundation-only subset of upstream
//  RSCore's `String+RSCore.swift`, vendored byte-for-byte so the
//  real Ranchero-Software/NetNewsWire FeedFinder (HTMLFeedFinder +
//  FeedSpecifier) compiles on Linux via
//  `moduleAliases: ["RSCore": "QuillRSCoreShim"]`. Upstream RSCore
//  doesn't build on Linux (AppKit/UIKit/os + the RSCoreObjC
//  sibling), so we mirror only the helpers actually reached:
//    - `trimmingWhitespace`, `stripping(prefix:)`/`(suffix:)`,
//      `normalizedURL`  — FeedFinder URL normalization
//    - `caseInsensitiveContains`  — FeedSpecifier scoring
//
//  Refresh: re-copy these methods verbatim from
//  .upstream/netnewswire/Modules/RSCore/Sources/RSCore/String+RSCore.swift
//

import Foundation

public extension String {

	var trimmingWhitespace: String {
		self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}

	/// Normalizes a feed URL string.
	///
	/// Strategy:
	/// 1) Note whether or not this is a feed: or feeds: or other prefix
	/// 2) Strip the feed: or feeds: prefix
	/// 3) If the resulting string is not prefixed with http: or https:, then add http:// as a prefix
	///
	/// - Note: Must handle edge case (like boingboing.net) where the feed URL is
	/// feed:http://boingboing.net/feed
	var normalizedURL: String {

		/// Prefix constants.
		/// - Note: The lack of colon on `http(s)` is intentional.
		enum Prefix {
			static let feed = "feed:"
			static let feeds = "feeds:"
			static let http = "http"
			static let https = "https"
		}

		var s = self.trimmingWhitespace
		var wasFeeds = false

		var lowercaseS = s.lowercased()

		if lowercaseS.hasPrefix(Prefix.feeds) {
			wasFeeds = true
			s = s.stripping(prefix: Prefix.feeds)
		} else if lowercaseS.hasPrefix(Prefix.feed) {
			s = s.stripping(prefix: Prefix.feed)
		}

		if s.hasPrefix("//") {
			s = s.stripping(prefix: "//")
		}

		lowercaseS = s.lowercased()
		if !lowercaseS.hasPrefix(Prefix.http) {
			s = "\(wasFeeds ? Prefix.https : Prefix.http)://\(s)"
		}

		// Handle top-level URLs missing a trailing slash, as in https://ranchero.com — make it http://ranchero.com/
		// We’re sticklers for this kind of thing.
		let componentsCount = s.components(separatedBy: "/").count
		if componentsCount == 3 {
			s = s.appending("/")
		}

		return s
	}

	/// Removes a prefix from the beginning of a string.
	/// - Parameters:
	///   - prefix: The prefix to remove
	///   - caseSensitive: `true` if the prefix should be matched case-sensitively.
	/// - Returns: A new string with the prefix removed.
	func stripping(prefix: String, caseSensitive: Bool = false) -> String {
		let options: String.CompareOptions = caseSensitive ? .anchored : [.anchored, .caseInsensitive]

		if let range = self.range(of: prefix, options: options) {
			return self.replacingCharacters(in: range, with: "")
		}

		return self
	}

	/// Removes a suffix from the end of a string.
	/// - Parameters:
	///   - suffix: The suffix to remove
	///   - caseSensitive: `true` if the suffix should be matched case-sensitively.
	/// - Returns: A new string with the suffix removed.
	func stripping(suffix: String, caseSensitive: Bool = false) -> String {
		let options: String.CompareOptions = caseSensitive ? [.backwards, .anchored] : [.backwards, .anchored, .caseInsensitive]

		if let range = self.range(of: suffix, options: options) {
			return self.replacingCharacters(in: range, with: "")
		}

		return self
	}

	/// Returns a Boolean value indicating whether the string contains another string, case-insensitively.
	///
	/// - Parameter string: The string to search for.
	///
	/// - Returns: `true` if the string contains `string`; `false` otherwise.
	func caseInsensitiveContains(_ string: String) -> Bool {
		self.range(of: string, options: .caseInsensitive) != nil
	}
}
