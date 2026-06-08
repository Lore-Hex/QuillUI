import Foundation
import Testing
@testable import QuillFeedFinder

/// Pins the network-free detection core `FeedFinder.feedSpecifiers(forResponseData:url:)`:
/// a feed response is returned as-is, an HTML page yields its `<head>` feed links
/// (or the WordPress/index.xml fallbacks), and anything else yields nothing.
@Suite("QuillFeedFinder — network-free detection")
struct FeedFinderDetectTests {

    private func specs(_ s: String, _ url: String = "https://example.com/") -> Set<FeedSpecifier> {
        FeedFinder.feedSpecifiers(forResponseData: Data(s.utf8), url: url)
    }

    @Test("a response that is itself a feed returns the URL as the feed")
    func directFeed() {
        let rss = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Site</title><link>https://example.com</link></channel></rss>"
        let result = FeedFinder.feedSpecifiers(forResponseData: Data(rss.utf8), url: "https://example.com/feed.xml")
        #expect(result.count == 1)
        #expect(result.first?.urlString == "https://example.com/feed.xml")
        #expect(result.first?.source == .userEntered)
    }

    @Test("an HTML page's <head> feed link is discovered")
    func htmlHeadFeed() {
        let html = "<html><head><link rel=\"alternate\" type=\"application/rss+xml\" href=\"https://example.com/feed.xml\"></head><body><p>hi</p></body></html>"
        let result = specs(html)
        #expect(result.contains { $0.urlString.contains("feed.xml") })
        #expect(FeedSpecifier.bestFeed(in: result)?.urlString.contains("feed.xml") == true)
    }

    @Test("an HTML page with no feed links falls back to /feed/ and /index.xml")
    func htmlFallback() {
        let html = "<html><head><title>x</title></head><body><p>nothing to subscribe to</p></body></html>"
        let result = specs(html, "https://blog.example.com")
        #expect(result.contains { $0.urlString.hasSuffix("/feed/") })
        #expect(result.contains { $0.urlString.contains("/index.xml") })
    }

    @Test("non-feed, non-HTML data yields no specifiers")
    func neither() {
        #expect(specs("just plain text, definitely not markup").isEmpty)
        #expect(specs("").isEmpty)
    }
}
