import Foundation
import Testing
@testable import QuillNetNewsWireCore

@Suite("QuillNetNewsWire article-cache persistence")
struct RSSArticleCacheStoreTests {
    private func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nnw-articles-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("articles.sqlite")
    }

    private func item(
        _ id: String,
        title: String? = nil,
        timestamp: TimeInterval? = nil,
        body: String? = "<p>Body</p>",
        author: String? = nil
    ) -> RSSItem {
        RSSItem(
            id: id,
            title: title ?? "Title \(id)",
            link: "https://example.test/\(id)",
            pubDate: timestamp.map { "date-\(Int($0))" },
            publishedDate: timestamp.map(Date.init(timeIntervalSince1970:)),
            descriptionHTML: body,
            author: author
        )
    }

    @Test("feed timelines round-trip through a reopened store")
    func persistsAcrossReopen() throws {
        let url = tempStoreURL()
        do {
            let store = try RSSArticleCacheStore(url: url)
            try store.replaceAll(feedID: "feed-a", items: [
                item("a1", timestamp: 1_700_000_000, author: "Alice"),
                item("a2", body: "<p>First</p><p>Second</p>")
            ])
        }

        let reopened = try RSSArticleCacheStore(url: url)
        let loaded = try reopened.load(feedID: "feed-a")
        #expect(loaded.map(\.id) == ["a1", "a2"])
        #expect(loaded[0].publishedDate == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(loaded[0].author == "Alice")
        #expect(loaded[1].bodyParagraphs == ["First", "Second"])
    }

    @Test("replacing one feed preserves cached articles for other feeds")
    func replaceOneFeedPreservesOthers() throws {
        let store = try RSSArticleCacheStore(url: tempStoreURL())
        try store.replaceAll(feedID: "feed-a", items: [item("a1"), item("a2")])
        try store.replaceAll(feedID: "feed-b", items: [item("b1")])
        try store.replaceAll(feedID: "feed-a", items: [item("a3")])

        #expect(try store.load(feedID: "feed-a").map(\.id) == ["a3"])
        #expect(try store.load(feedID: "feed-b").map(\.id) == ["b1"])
    }

    @Test("loadAll groups by feed in timeline order")
    func loadAllGroupsByFeed() throws {
        let store = try RSSArticleCacheStore(url: tempStoreURL())
        try store.replaceAll(feedID: "feed-b", items: [item("b1"), item("b2")])
        try store.replaceAll(feedID: "feed-a", items: [item("a1")])

        let grouped = try store.loadAll()
        #expect(grouped["feed-a"]?.map(\.id) == ["a1"])
        #expect(grouped["feed-b"]?.map(\.id) == ["b1", "b2"])
    }

    @Test("remove clears one feed without touching the rest")
    func removeFeedCache() throws {
        let store = try RSSArticleCacheStore(url: tempStoreURL())
        try store.replaceAll(feedID: "feed-a", items: [item("a1")])
        try store.replaceAll(feedID: "feed-b", items: [item("b1")])
        try store.remove(feedID: "feed-a")

        #expect(try store.load(feedID: "feed-a").isEmpty)
        #expect(try store.load(feedID: "feed-b").map(\.id) == ["b1"])
    }
}
