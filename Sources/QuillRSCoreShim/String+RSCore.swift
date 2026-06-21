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
//    - `trimmingWhitespace`, `collapsingWhitespace`,
//      `stripping(prefix:)`/`(suffix:)`, `normalizedURL`  —
//      FeedFinder URL normalization and article title formatting
//    - `caseInsensitiveContains`  — FeedSpecifier scoring
//
//  Refresh: re-copy these methods verbatim from
//  .upstream/netnewswire/Modules/RSCore/Sources/RSCore/String+RSCore.swift
//

import Foundation
import CryptoKit

public extension String {

	func hmacUsingSHA1(key: String) -> String {
		let signature = HMAC<Insecure.SHA1>.authenticationCode(
			for: Data(self.utf8),
			using: SymmetricKey(data: Data(key.utf8))
		)
		return MD5.hexString(Array(signature))
	}

	func htmlByAddingLink(_ link: String, className: String? = nil) -> String {
		if let className = className {
			return "<a class=\"\(className)\" href=\"\(link)\">\(self)</a>"
		}
		return "<a href=\"\(link)\">\(self)</a>"
	}

	static func htmlWithLink(_ link: String) -> String {
		link.htmlByAddingLink(link)
	}

	func convertingToPlainText() -> String {
		strippingHTML()
	}

	/// Trims leading and trailing whitespace and collapses other whitespace into a single space.
	///
	/// The original version used `trimmingCharacters` and `replacingOccurrences`
	/// with regex: `"\\s+"`
	///
	/// This faster version loops through UTF-8 bytes. Handles the six
	/// ASCII whitespace characters matched by NSRegularExpression's `\s`
	/// (space, tab, LF, VT, FF, CR). Non-ASCII bytes pass through unchanged —
	/// same as the regex version.
	var collapsingWhitespace: String {
		let spaceByte = UInt8(ascii: " ")
		let tabByte = UInt8(ascii: "\t")
		let crByte = UInt8(ascii: "\r")

		let utf8 = self.utf8
		var out = [UInt8]()
		out.reserveCapacity(utf8.count)

		var sawNonSpace = false
		var pendingSpace = false

		for byte in utf8 {
			if byte == spaceByte || (byte >= tabByte && byte <= crByte) {
				if sawNonSpace {
					pendingSpace = true
				}
				continue
			}
			if pendingSpace {
				out.append(spaceByte)
				pendingSpace = false
			}
			sawNonSpace = true
			out.append(byte)
		}

		return String(decoding: out, as: UTF8.self)
	}

	var trimmingWhitespace: String {
		self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
	}

	private func containsAnyCharacter(from charset: CharacterSet) -> Bool {
		self.rangeOfCharacter(from: charset) != nil
	}

	private var mayBeIPv6URL: Bool {
		self.range(of: "\\[[0-9a-fA-F:]+\\]", options: .regularExpression) != nil
	}

	private var hostMayBeLocalhost: Bool {
		guard let components = URLComponents(string: self) else { return false }

		if let host = components.host {
			return host == "localhost"
		}

		if self == "localhost" || self.hasPrefix("localhost/") || self.hasPrefix("localhost:") {
			return true
		}

		if components.path.split(separator: "/", omittingEmptySubsequences: false).first == "localhost" {
			return true
		}

		return false
	}

	var mayBeURL: Bool {
		let s = self.trimmingWhitespace

		if s.isEmpty || (!s.contains(".") && !s.mayBeIPv6URL && !s.hostMayBeLocalhost) {
			return false
		}

		let banned = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(.illegalCharacters)
		if s.containsAnyCharacter(from: banned) {
			return false
		}

		return true
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

	/// Prepends tabs to a string.
	///
	/// - Parameter tabCount: The number of tabs to prepend. Must be greater than or equal to zero.
	///
	/// - Returns: The string with `numberOfTabs` tabs prepended.
	func prepending(tabCount: Int) -> String {
		let tabs = String(repeating: "\t", count: tabCount)
		return "\(tabs)\(self)"
	}

	/// Returns the string with `http://` or `https://` removed from the beginning.
	var strippingHTTPOrHTTPSScheme: String {
		self.stripping(prefix: "http://").stripping(prefix: "https://")
	}
}
