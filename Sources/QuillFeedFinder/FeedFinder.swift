//
//  FeedFinder.swift
//  NetNewsWire — vendored (network-free subset) into QuillFeedFinder
//
//  Created by Brent Simmons on 8/2/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//
//  Quill bring-up: the real Ranchero-Software/NetNewsWire FeedFinder surface.
//  The network-free classification helper remains public for deterministic
//  tests and app flows that fetch bytes elsewhere, while `find(url:)` now uses
//  the RSWeb Downloader shim and ActivityLog slice.
//
//    FeedFinder.feedSpecifiers(forResponseData:url:)
//
//  `isFeed`, `possibleFeedsInHTMLPage`, and candidate verification mirror the
//  upstream FeedFinder.swift flow with imports retargeted to Quill modules.
//
//  Refresh: re-copy from
//  .upstream/netnewswire/Modules/FeedFinder/Sources/FeedFinder/FeedFinder.swift
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ActivityLog
import QuillRSParser
import QuillRSCoreShim
import RSWeb

public enum FeedFinderError: LocalizedError {
	case feedNotFound

	public var errorDescription: String? {
		switch self {
		case .feedNotFound:
			return NSLocalizedString("The feed couldn't be found and can't be added.", comment: "Not found")
		}
	}
}

public enum FeedFinder {
	enum FindStrategy {
		case specialCase
		case microblogJSON
		case directFeed
		case htmlHead
		case candidates
	}

	@concurrent public static func find(url: URL) async throws -> Set<FeedSpecifier> {
		let activityID = await activityStart(url: url)
		do {
			let (result, strategy) = try await performFind(url: url)
			await activityComplete(id: activityID, result: result, strategy: strategy)
			return result
		} catch {
			await activityFail(id: activityID, error: error)
			throw error
		}
	}

	@concurrent private static func performFind(url: URL) async throws -> (Set<FeedSpecifier>, FindStrategy) {
		if let feedSpecifier = FeedSpecifier.knownFeedSpecifier(url: url) {
			return (Set([feedSpecifier]), .specialCase)
		}

		let (data, response) = try await downloadAndLog(url)

		if response?.forcedStatusCode == 404 {
			if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), urlComponents.host == "micro.blog" {
				urlComponents.path = "\(urlComponents.path).json"
				if let newURLString = urlComponents.url?.absoluteString {
					let microblogFeedSpecifier = FeedSpecifier(title: nil, urlString: newURLString, source: .HTMLLink, orderFound: 1)
					return (Set([microblogFeedSpecifier]), .microblogJSON)
				}
			}
			throw FeedFinderError.feedNotFound
		}

		guard let data, let response else {
			throw FeedFinderError.feedNotFound
		}

		guard response.statusIsOK, !data.isEmpty else {
			throw FeedFinderError.feedNotFound
		}

		if FeedFinder.isFeed(data, url.absoluteString) {
			let feedSpecifier = FeedSpecifier(title: nil, urlString: url.absoluteString, source: .userEntered, orderFound: 1)
			return (Set([feedSpecifier]), .directFeed)
		}

		guard FeedFinder.isHTML(data) else {
			throw FeedFinderError.feedNotFound
		}

		return try await FeedFinder.findFeedsInHTMLPage(htmlData: data, urlString: url.absoluteString)
	}

	public static func downloadAndLog(_ url: URL) async throws -> (Data?, URLResponse?) {
		let id = await activityFetchStart(url: url)
		do {
			let (data, response) = try await Downloader.shared.download(url)
			await activityFetchComplete(id: id, data: data, response: response)
			return (data, response)
		} catch {
			await activityFetchFail(id: id, error: error)
			throw error
		}
	}

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

	static func isHTML(_ data: Data) -> Bool {
		return data.isProbablyHTML
	}

	static func findFeedsInHTMLPage(htmlData: Data, urlString: String) async throws -> (Set<FeedSpecifier>, FindStrategy) {
		let possibleFeedSpecifiers = possibleFeedsInHTMLPage(htmlData: htmlData, urlString: urlString)
		var feedSpecifiers = [String: FeedSpecifier]()
		var feedSpecifiersToDownload = Set<FeedSpecifier>()

		var didFindFeedInHTMLHead = false

		for feedSpecifier in possibleFeedSpecifiers {
			if feedSpecifier.source == .HTMLHead {
				addFeedSpecifier(feedSpecifier, feedSpecifiers: &feedSpecifiers)
				didFindFeedInHTMLHead = true
			} else if feedSpecifiers[feedSpecifier.urlString] == nil {
				feedSpecifiersToDownload.insert(feedSpecifier)
			}
		}

		if didFindFeedInHTMLHead {
			return (Set(feedSpecifiers.values), .htmlHead)
		}

		guard !feedSpecifiersToDownload.isEmpty else {
			throw FeedFinderError.feedNotFound
		}

		let result = await downloadFeedSpecifiers(feedSpecifiersToDownload, feedSpecifiers: feedSpecifiers)
		return (result, .candidates)
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

	static func downloadFeedSpecifiers(_ downloadFeedSpecifiers: Set<FeedSpecifier>, feedSpecifiers: [String: FeedSpecifier]) async -> Set<FeedSpecifier> {
		var resultFeedSpecifiers = feedSpecifiers

		await withTaskGroup(of: FeedSpecifier?.self) { group in
			for downloadFeedSpecifier in downloadFeedSpecifiers {
				guard let url = URL(string: downloadFeedSpecifier.urlString) else {
					continue
				}

				group.addTask {
					do {
						let (data, response) = try await downloadAndLog(url)
						if let data, let response, response.statusIsOK, self.isFeed(data, downloadFeedSpecifier.urlString) {
							return downloadFeedSpecifier
						}
					} catch {
						// The per-URL activity has already recorded this failure.
					}
					return nil
				}
			}

			for await feedSpecifier in group {
				if let feedSpecifier {
					addFeedSpecifier(feedSpecifier, feedSpecifiers: &resultFeedSpecifiers)
				}
			}
		}

		return Set(resultFeedSpecifiers.values)
	}

	static func addFeedSpecifier(_ feedSpecifier: FeedSpecifier, feedSpecifiers: inout [String: FeedSpecifier]) {
		if let existingFeedSpecifier = feedSpecifiers[feedSpecifier.urlString] {
			feedSpecifiers[feedSpecifier.urlString] = existingFeedSpecifier.feedSpecifierByMerging(feedSpecifier)
		} else {
			feedSpecifiers[feedSpecifier.urlString] = feedSpecifier
		}
	}

	@MainActor private static func activityStart(url: URL) -> Int {
		let activityLog = ActivityLog.shared
		let id = activityLog.createActivity(owner: .feedFinder, kind: .findFeed(urlString: url.absoluteString))
		activityLog.didStart(id: id)
		return id
	}

	@MainActor private static func activityComplete(id: Int, result: Set<FeedSpecifier>, strategy: FindStrategy) {
		ActivityLog.shared.didComplete(id: id, message: parentCompletionMessage(result: result, strategy: strategy))
	}

	@MainActor private static func activityFail(id: Int, error: any Error) {
		ActivityLog.shared.didFail(id: id, error: error)
	}

	@MainActor private static func activityFetchStart(url: URL) -> Int {
		let activityLog = ActivityLog.shared
		let id = activityLog.createActivity(owner: .feedFinder, kind: .fetchFeedCandidate(urlString: url.absoluteString))
		activityLog.didStart(id: id)
		return id
	}

	@MainActor private static func activityFetchComplete(id: Int, data: Data?, response: URLResponse?) {
		ActivityLog.shared.didComplete(
			id: id,
			message: fetchCompletionMessage(data: data, response: response),
			durationIsSignificant: false
		)
	}

	@MainActor private static func activityFetchFail(id: Int, error: any Error) {
		ActivityLog.shared.didFail(id: id, error: error)
	}

	static func parentCompletionMessage(result: Set<FeedSpecifier>, strategy: FindStrategy) -> String {
		let count = result.count
		if count == 0 {
			switch strategy {
			case .candidates:
				return "No feeds found in candidate URLs"
			default:
				return "No feeds found"
			}
		}
		let plural = count == 1 ? "feed" : "feeds"
		switch strategy {
		case .specialCase:
			return "\(count) \(plural) (special case match)"
		case .microblogJSON:
			return "\(count) \(plural) via Micro.blog .json fallback"
		case .directFeed:
			return "Direct feed"
		case .htmlHead:
			return "\(count) \(plural) via HTML <head>"
		case .candidates:
			return "\(count) \(plural) via candidate URLs"
		}
	}

	static func fetchCompletionMessage(data: Data?, response: URLResponse?) -> String {
		guard let response else {
			return "No response"
		}
		let statusPart = formattedStatus(response.forcedStatusCode)
		if response.statusIsOK, let data, !data.isEmpty {
			return "\(statusPart) - \(data.count) bytes"
		}
		return statusPart
	}

	static func formattedStatus(_ statusCode: Int) -> String {
		if statusCode == 0 {
			return "No status"
		}
		let phrase: String
		switch statusCode {
		case 200:
			phrase = "OK"
		case 304:
			phrase = "Not Modified"
		default:
			phrase = HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized
		}
		return "\(statusCode) \(phrase)"
	}
}
