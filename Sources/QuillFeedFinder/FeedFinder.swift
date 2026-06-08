//
//  FeedFinder.swift
//  NetNewsWire — vendored (network-free subset) into QuillFeedFinder
//
//  Created by Brent Simmons on 8/2/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: the network-free detection core of the real
//  Ranchero-Software/NetNewsWire FeedFinder. Upstream `FeedFinder.find(url:)`
//  downloads the URL (RSWeb `Downloader`) and then classifies the bytes; the
//  download half is `@MainActor` URLSession machinery that isn't brought up on
//  Linux yet, so this exposes the *classification* half as a pure function over
//  already-fetched response data:
//
//    FeedFinder.feedSpecifiers(forResponseData:url:)
//
//  The caller (e.g. the app's Add-Feed flow) fetches the bytes with whatever
//  networking it already has, then asks FeedFinder what feeds they describe.
//  `isFeed` and `possibleFeedsInHTMLPage` are vendored verbatim from upstream
//  FeedFinder.swift; only the download-driven `find`/`downloadFeedSpecifiers`
//  paths are deferred.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/FeedFinder/Sources/FeedFinder/FeedFinder.swift
//

import Foundation
import QuillRSParser
import QuillRSCoreShim

public enum FeedFinder {

	/// Network-free feed detection over an already-downloaded response.
	///
	/// - If the data itself parses as a feed, the URL is returned as the feed.
	/// - Otherwise, if the data looks like HTML, the page's `<head>` feed links
	///   (plus the conventional WordPress `/feed/` and `/index.xml` fallbacks)
	///   are returned as candidates. Use `FeedSpecifier.bestFeed(in:)` to pick.
	/// - Otherwise an empty set is returned.
	///
	/// This mirrors the classification half of upstream `FeedFinder.find(url:)`
	/// (the part after the download), minus the body-link verification that
	/// requires further network round-trips.
	public static func feedSpecifiers(forResponseData data: Data, url: String) -> Set<FeedSpecifier> {
		if isFeed(data, url) {
			return [FeedSpecifier(title: nil, urlString: url, source: .userEntered, orderFound: 1)]
		}

		guard data.isProbablyHTML else {
			return []
		}

		return possibleFeedsInHTMLPage(htmlData: data, urlString: url)
	}

	static func isFeed(_ data: Data, _ urlString: String) -> Bool {
		let parserData = ParserData(url: urlString, data: data)
		return FeedParser.canParse(parserData)
	}

	static func possibleFeedsInHTMLPage(htmlData: Data, urlString: String) -> Set<FeedSpecifier> {
		let parserData = ParserData(url: urlString, data: htmlData)
		var feedSpecifiers = HTMLFeedFinder(parserData: parserData).feedSpecifiers

		if feedSpecifiers.isEmpty {
			// Odds are decent it's a WordPress site, and just adding /feed/ will work.
			// It's also fairly common for /index.xml to work.
			if let url = URL(string: urlString) {
				let feedURL = url.appendingPathComponent("feed", isDirectory: true)
				let wordpressFeedSpecifier = FeedSpecifier(title: nil, urlString: feedURL.absoluteString, source: .HTMLLink, orderFound: 1)
				feedSpecifiers.insert(wordpressFeedSpecifier)

				let indexXMLURL = url.appendingPathComponent("index.xml", isDirectory: false)
				let indexXMLFeedSpecifier = FeedSpecifier(title: nil, urlString: indexXMLURL.absoluteString, source: .HTMLLink, orderFound: 1)
				feedSpecifiers.insert(indexXMLFeedSpecifier)
			}
		}

		return feedSpecifiers
	}
}
