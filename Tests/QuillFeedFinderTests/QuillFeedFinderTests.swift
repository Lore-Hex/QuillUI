import Foundation
import Testing
import QuillRSParser
@testable import QuillFeedFinder

/// Pins the vendored NetNewsWire FeedFinder HTML feed-detection (network-free
/// path): HTMLFeedFinder finds `<head>` feed links and feed-looking body links
/// from already-fetched HTML, and FeedSpecifier scoring/merging picks the best
/// candidate.
@Suite("QuillFeedFinder — HTML feed detection")
struct QuillFeedFinderTests {

    private func finder(_ html: String, _ url: String = "https://example.com/") -> Set<FeedSpecifier> {
        let parserData = ParserData(url: url, data: Data(html.utf8))
        return HTMLFeedFinder(parserData: parserData).feedSpecifiers
    }

    @Test("a <head> alternate feed link is found as an HTMLHead specifier")
    func findsHeadFeedLink() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="My Feed" href="https://example.com/feed.xml">
        </head><body><p>hi</p></body></html>
        """
        let specs = finder(html)
        let head = specs.first { $0.urlString.contains("feed.xml") }
        #expect(head != nil)
        #expect(head?.source == .HTMLHead)
    }

    @Test("an Atom <head> link is found")
    func findsAtomHeadLink() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/atom+xml" href="https://example.com/atom">
        </head><body></body></html>
        """
        #expect(finder(html).contains { $0.urlString.contains("/atom") && $0.source == .HTMLHead })
    }

    @Test("a feed-looking body link is found as an HTMLLink specifier")
    func findsBodyFeedLink() {
        let html = """
        <html><head></head><body>
        <a href="https://example.com/posts/index.rss">subscribe</a>
        <a href="https://example.com/about">about</a>
        </body></html>
        """
        let specs = finder(html)
        #expect(specs.contains { $0.urlString.contains("index.rss") })
        // A plain non-feed link is not collected.
        #expect(!specs.contains { $0.urlString.hasSuffix("/about") })
    }

    @Test("bestFeed prefers a <head> feed over a feed-looking comments link")
    func bestFeedPrefersHead() {
        let html = """
        <html><head>
        <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml">
        </head><body>
        <a href="https://example.com/comments.rss">comments feed</a>
        </body></html>
        """
        let best = FeedSpecifier.bestFeed(in: finder(html))
        #expect(best?.urlString.contains("feed.xml") == true)
    }
}

/// Pins FeedSpecifier's scoring + merging directly (no HTML).
@Suite("QuillFeedFinder — FeedSpecifier scoring")
struct FeedSpecifierScoringTests {

    @Test("a user-entered feed always scores highest")
    func userEnteredWins() {
        let entered = FeedSpecifier(title: nil, urlString: "https://x.com/feed", source: .userEntered, orderFound: 9)
        let head = FeedSpecifier(title: nil, urlString: "https://x.com/rss", source: .HTMLHead, orderFound: 1)
        #expect(entered.score == 1000)
        #expect(entered.score > head.score)
    }

    @Test("a comments feed scores lower than a plain rss feed")
    func commentsPenalized() {
        let plain = FeedSpecifier(title: nil, urlString: "https://x.com/rss", source: .HTMLHead, orderFound: 1)
        let comments = FeedSpecifier(title: nil, urlString: "https://x.com/comments/rss", source: .HTMLHead, orderFound: 1)
        #expect(plain.score > comments.score)
    }

    @Test("merging keeps a non-nil title and the better source")
    func mergingKeepsBest() {
        let a = FeedSpecifier(title: nil, urlString: "https://x.com/feed", source: .HTMLLink, orderFound: 3)
        let b = FeedSpecifier(title: "Titled", urlString: "https://x.com/feed", source: .HTMLHead, orderFound: 1)
        let merged = a.feedSpecifierByMerging(b)
        #expect(merged.title == "Titled")
        #expect(merged.source == .HTMLHead)   // HTMLHead (rawValue 1) is better than HTMLLink (2)
        #expect(merged.orderFound == 1)
    }

    @Test("bestFeed returns the single feed and nil for empty")
    func bestFeedEdgeCases() {
        #expect(FeedSpecifier.bestFeed(in: []) == nil)
        let only = FeedSpecifier(title: nil, urlString: "https://x.com/feed", source: .HTMLHead, orderFound: 1)
        #expect(FeedSpecifier.bestFeed(in: [only]) == only)
    }
}
