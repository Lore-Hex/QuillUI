//
//  AddFeedDiscovery.swift
//  Quill NetNewsWire — Add-Feed discovery over the real NetNewsWire FeedFinder
//
//  Network-free classification of an Add-Feed fetch. The user types a URL
//  that is either a feed itself or a site whose HTML names its feeds; the
//  real vendored FeedFinder (QuillFeedFinder) decides which, and scores the
//  candidates. `RSSReaderModel.addFeedDiscovering(urlString:fetch:)` drives
//  the network half; this enum is the pure decision core so tests pin the
//  behavior without a socket.
//

import Foundation
import QuillFeedFinder

enum AddFeedDiscovery {

    /// What an Add-Feed fetch turned out to be.
    enum Outcome: Equatable {
        /// The fetched bytes are themselves a feed — subscribe to the URL as entered.
        case feed
        /// The fetched bytes are an HTML page naming candidate feed URLs —
        /// ordered best (highest FeedSpecifier score) first.
        case candidates([String])
        /// Neither a feed nor a page with discoverable feeds.
        case none
    }

    /// Classify already-fetched response data via the real FeedFinder.
    ///
    /// Upstream `FeedFinder.find(url:)` downloads every candidate
    /// concurrently and then picks `bestFeed` among the confirmed ones; here
    /// the candidates are ordered by the same `FeedSpecifier.score` (URL
    /// string as a deterministic tiebreaker) so a caller trying them in
    /// order confirms the best-scored candidate first.
    static func outcome(forResponseData data: Data, urlString: String) -> Outcome {
        let specifiers = FeedFinder.feedSpecifiers(forResponseData: data, url: urlString)
        if specifiers.contains(where: { $0.source == .userEntered }) {
            return .feed
        }
        if specifiers.isEmpty {
            return .none
        }
        let ordered = specifiers.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.urlString < $1.urlString
        }.map(\.urlString)
        return .candidates(ordered)
    }
}
