import Foundation
import Testing
@testable import QuillNetNewsWireCore

/// Pins the "Add Feed by URL" subscribe action (NetNewsWire parity): valid
/// http/https URLs are added (deduped), invalid/non-http URLs are rejected, and
/// the display title falls back to the host.
@Suite("QuillNetNewsWireCore — addFeed (subscribe by URL)")
@MainActor
struct AddFeedTests {

    @Test("a valid http(s) feed URL is added and selectable")
    func addsValidFeed() {
        let model = RSSReaderModel(subscribedFeeds: [])
        #expect(model.addFeed(urlString: "https://example.com/feed.xml"))
        #expect(model.subscribedFeeds.contains { $0.url == "https://example.com/feed.xml" })
    }

    @Test("a duplicate URL is not added twice")
    func dedupes() {
        let model = RSSReaderModel(subscribedFeeds: [])
        #expect(model.addFeed(urlString: "https://example.com/feed.xml"))
        #expect(!model.addFeed(urlString: "https://example.com/feed.xml"))
        #expect(model.subscribedFeeds.filter { $0.url == "https://example.com/feed.xml" }.count == 1)
    }

    @Test("invalid, empty, and non-http URLs are rejected")
    func rejectsInvalid() {
        let model = RSSReaderModel(subscribedFeeds: [])
        #expect(!model.addFeed(urlString: "not a url"))
        #expect(!model.addFeed(urlString: ""))
        #expect(!model.addFeed(urlString: "   "))
        #expect(!model.addFeed(urlString: "ftp://example.com/feed.xml"))
        #expect(model.subscribedFeeds.isEmpty)
    }

    @Test("an explicit title is used; otherwise the host is the title")
    func titleFallback() {
        let model = RSSReaderModel(subscribedFeeds: [])
        _ = model.addFeed(urlString: "https://blog.example.com/rss", title: "My Blog")
        #expect(model.subscribedFeeds.first(where: { $0.url == "https://blog.example.com/rss" })?.title == "My Blog")

        _ = model.addFeed(urlString: "https://news.example.org/feed")
        #expect(model.subscribedFeeds.first(where: { $0.url == "https://news.example.org/feed" })?.title == "news.example.org")
    }
}
