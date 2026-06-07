//
//  FeedSpecifier.swift
//  NetNewsWire — vendored into QuillFeedFinder
//
//  Created by Brent Simmons on 8/7/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: vendored verbatim from the real Ranchero-Software/NetNewsWire
//  FeedFinder module. Imports are retargeted to the Quill shims: `RSWeb` keeps
//  its name (the QuillRSWebShim target is named `RSWeb`), and `QuillRSCoreShim`
//  is added because the Quill RSWeb shim does not `@_exported import` RSCore the
//  way upstream RSWeb does (so `caseInsensitiveContains` resolves). Body
//  unchanged. `URL.isRachelByTheBayURL` is provided by QuillRSWebShim's
//  SpecialCaseMatching.swift.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/FeedFinder/Sources/FeedFinder/FeedSpecifier.swift
//

import Foundation
import RSWeb
import QuillRSCoreShim

public struct FeedSpecifier: Hashable, Sendable {
	public enum Source: Int, Sendable {
		case userEntered = 0, HTMLHead, HTMLLink

		func equalToOrBetterThan(_ otherSource: Source) -> Bool {
			return self.rawValue <= otherSource.rawValue
		}
	}

	public let title: String?
	public let urlString: String
	public let source: Source
	public let orderFound: Int
	public var score: Int {
		calculatedScore()
	}

	public init(title: String?, urlString: String, source: Source, orderFound: Int) {
		self.title = title
		self.urlString = urlString
		self.source = source
		self.orderFound = orderFound
	}

	/// Some feed URLs are known in advance. Save time/bandwidth by special-casing those.
	static func knownFeedSpecifier(url: URL) -> FeedSpecifier? {
		if url.isRachelByTheBayURL {
			let feedURLString = "https://rachelbythebay.com/w/atom.xml"
			return FeedSpecifier(title: "writing - rachelbythebay", urlString: feedURLString, source: .userEntered, orderFound: 0)
		}

		return nil
	}

	func feedSpecifierByMerging(_ feedSpecifier: FeedSpecifier) -> FeedSpecifier {
		// Take the best data (non-nil title, better source) to create a new feed specifier;

		let mergedTitle = title ?? feedSpecifier.title
		let mergedSource = source.equalToOrBetterThan(feedSpecifier.source) ? source : feedSpecifier.source
		let mergedOrderFound = orderFound < feedSpecifier.orderFound ? orderFound : feedSpecifier.orderFound

		return FeedSpecifier(title: mergedTitle, urlString: urlString, source: mergedSource, orderFound: mergedOrderFound)
	}

	public static func bestFeed(in feedSpecifiers: Set<FeedSpecifier>) -> FeedSpecifier? {
		if feedSpecifiers.isEmpty {
			return nil
		}
		if feedSpecifiers.count == 1 {
			return feedSpecifiers.first
		}

		var currentHighScore = Int.min
		var currentBestFeed: FeedSpecifier?

		for oneFeedSpecifier in feedSpecifiers {
			let oneScore = oneFeedSpecifier.score
			if oneScore > currentHighScore {
				currentHighScore = oneScore
				currentBestFeed = oneFeedSpecifier
			}
		}

		return currentBestFeed
	}
}

private extension FeedSpecifier {

	func calculatedScore() -> Int {
		var score = 0

		if source == .userEntered {
			return 1000
		} else if source == .HTMLHead {
			score += 50
		}

		score -= (orderFound - 1) * 5

		if urlString.caseInsensitiveContains("comments") {
			score -= 10
		}
		if urlString.caseInsensitiveContains("podcast") {
			score -= 10
		}
		if urlString.caseInsensitiveContains("rss") {
			score += 5
		}
		if urlString.hasSuffix("/index.xml") {
			score += 5
		}
		if urlString.hasSuffix("/feed/") {
			score += 5
		}
		if urlString.hasSuffix("/feed") {
			score += 4
		}
		if urlString.caseInsensitiveContains("json") {
			score += 3
		}

		if let title = title {
			if title.caseInsensitiveContains("comments") {
				score -= 10
			}
		}

		return score
	}
}
