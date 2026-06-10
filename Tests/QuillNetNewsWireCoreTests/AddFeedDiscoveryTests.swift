import Foundation
import Testing
@testable import QuillNetNewsWireCore

/// Pins the Add-Feed discovery flow: the real vendored FeedFinder classifies
/// the fetched bytes (feed / HTML-with-candidates / neither) and the model
/// subscribes to the right URL with the feed's parsed title — all through the
/// injected fetcher, so no sockets.
@Suite("QuillNetNewsWireCore — Add Feed discovery (real FeedFinder)")
@MainActor
struct AddFeedDiscoveryTests {

    private struct StubFetchError: Error {}

    private static let rss = #"<?xml version="1.0"?><rss version="2.0"><channel><title>Daring Site</title><link>https://site.example.com/</link><item><title>Hello</title><guid>1</guid></item></channel></rss>"#

    private static let html = #"<html><head><link rel="alternate" type="application/rss+xml" href="https://site.example.com/feed.xml"></head><body><p>welcome</p></body></html>"#

    // MARK: outcome() — the pure classification core

    @Test("feed bytes classify as .feed")
    func outcomeFeed() {
        let outcome = AddFeedDiscovery.outcome(
            forResponseData: Data(Self.rss.utf8),
            urlString: "https://site.example.com/feed.xml"
        )
        #expect(outcome == .feed)
    }

    @Test("HTML with a head feed link classifies as .candidates, best first")
    func outcomeCandidates() {
        let outcome = AddFeedDiscovery.outcome(
            forResponseData: Data(Self.html.utf8),
            urlString: "https://site.example.com/"
        )
        guard case .candidates(let urls) = outcome else {
            Issue.record("expected .candidates, got \(outcome)")
            return
        }
        #expect(urls.first == "https://site.example.com/feed.xml")
    }

    @Test("plain text classifies as .none")
    func outcomeNone() {
        let outcome = AddFeedDiscovery.outcome(
            forResponseData: Data("just text, no markup".utf8),
            urlString: "https://site.example.com/"
        )
        #expect(outcome == .none)
    }

    // MARK: addFeedDiscovering() — the model flow over an injected fetcher

    @Test("entering a site URL discovers and subscribes to its feed, titled from the feed")
    func discoversSiteFeed() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let pages = [
            "https://site.example.com/": Self.html,
            "https://site.example.com/feed.xml": Self.rss,
        ]
        let added = await model.addFeedDiscovering(urlString: "https://site.example.com/") { url in
            guard let body = pages[url.absoluteString] else { throw StubFetchError() }
            return Data(body.utf8)
        }
        #expect(added)
        let feed = model.subscribedFeeds.first
        #expect(feed?.url == "https://site.example.com/feed.xml")
        #expect(feed?.title == "Daring Site")
    }

    @Test("entering a feed URL directly subscribes with the parsed title")
    func directFeed() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let added = await model.addFeedDiscovering(urlString: "https://site.example.com/feed.xml") { _ in
            Data(Self.rss.utf8)
        }
        #expect(added)
        #expect(model.subscribedFeeds.first?.url == "https://site.example.com/feed.xml")
        #expect(model.subscribedFeeds.first?.title == "Daring Site")
    }

    @Test("a scheme-less entry is normalized (RSCore normalizedURL) before discovery")
    func normalizesEntry() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let added = await model.addFeedDiscovering(urlString: "site.example.com") { _ in
            Data(Self.rss.utf8)
        }
        #expect(added)
        // normalizedURL adds the scheme and the trailing slash.
        #expect(model.subscribedFeeds.first?.url == "http://site.example.com/")
    }

    @Test("an unfetchable best candidate falls through to the next (index.xml fallback)")
    func fallsThroughCandidates() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        // HTML with no feed links → FeedFinder falls back to /feed/ + /index.xml;
        // /feed/ 404s (fetch throws) so discovery must fall through to /index.xml.
        let bare = "<html><head><title>x</title></head><body><p>no links here</p></body></html>"
        let pages = [
            "https://blog.example.com/": bare,
            "https://blog.example.com/index.xml": Self.rss,
        ]
        let added = await model.addFeedDiscovering(urlString: "https://blog.example.com/") { url in
            guard let body = pages[url.absoluteString] else { throw StubFetchError() }
            return Data(body.utf8)
        }
        #expect(added)
        #expect(model.subscribedFeeds.first?.url == "https://blog.example.com/index.xml")
    }

    @Test("a page with no discoverable feed reports an error and subscribes nothing")
    func noFeedFound() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let added = await model.addFeedDiscovering(urlString: "https://site.example.com/") { _ in
            Data("plain text, no markup at all".utf8)
        }
        #expect(!added)
        #expect(model.subscribedFeeds.isEmpty)
        #expect(model.error?.contains("No feed found") == true)
    }

    @Test("a failing initial fetch surfaces the error")
    func fetchErrorSurfaces() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let added = await model.addFeedDiscovering(urlString: "https://site.example.com/") { _ in
            throw StubFetchError()
        }
        #expect(!added)
        #expect(model.subscribedFeeds.isEmpty)
        #expect(model.error != nil)
    }

    @Test("a garbage entry is rejected and subscribes nothing")
    func rejectsInvalid() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        // Depending on the platform's URL parser strictness this is rejected
        // either by the Invalid-URL guard (Linux) or by the failing fetch
        // (lenient parsers that percent-encode); both must end the same way.
        let added = await model.addFeedDiscovering(urlString: "not a url at all") { _ in
            throw StubFetchError()
        }
        #expect(!added)
        #expect(model.subscribedFeeds.isEmpty)
        #expect(model.error != nil)
    }
}
