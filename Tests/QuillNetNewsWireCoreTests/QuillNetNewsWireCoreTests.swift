import Foundation
import Testing
@testable import QuillNetNewsWireCore

@Suite("QuillNetNewsWireCore RSS / Atom parser")
struct QuillNetNewsWireCoreTests {

    // MARK: - RSS 2.0

    @Test("RSS 2.0 channel title + items decode title / link / pubDate / description")
    func rss2ChannelParses() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Example Feed</title>
            <link>https://example.test/</link>
            <description>Site description</description>
            <item>
              <title>First Article</title>
              <link>https://example.test/1</link>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <description>Hello &amp; welcome.</description>
            </item>
            <item>
              <title>Second Article</title>
              <link>https://example.test/2</link>
              <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
              <description>Another post.</description>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let result = RSSFeedParser.parse(data: xml)
        #expect(result.title == "Example Feed")
        #expect(result.items.count == 2)

        let first = result.items[0]
        #expect(first.title == "First Article")
        #expect(first.link == "https://example.test/1")
        #expect(first.pubDate == "Mon, 01 Jan 2024 12:00:00 GMT")
        #expect(first.descriptionHTML == "Hello & welcome.")
        #expect(first.id == "https://example.test/1")
    }

    @Test("RSS item with CDATA description preserves the HTML payload")
    func rss2ItemCDATADescription() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <title>Feed</title>
            <item>
              <title>Post</title>
              <link>https://example.test/cdata</link>
              <description><![CDATA[<p>Hello <b>world</b></p>]]></description>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let result = RSSFeedParser.parse(data: xml)
        #expect(result.items.count == 1)
        #expect(result.items[0].descriptionHTML == "<p>Hello <b>world</b></p>")
    }

    @Test("RSS item with no title falls back to \"Untitled\"")
    func rss2UntitledFallback() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <title>Feed</title>
            <item>
              <link>https://example.test/x</link>
              <pubDate>Wed, 03 Jan 2024 12:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let result = RSSFeedParser.parse(data: xml)
        #expect(result.items.count == 1)
        #expect(result.items[0].title == "Untitled")
    }

    @Test("RSS item with no link composes id from title + pubDate")
    func rss2IdFallbackToTitleAndDate() throws {
        let xml = """
        <rss version="2.0">
          <channel>
            <title>Feed</title>
            <item>
              <title>Linkless</title>
              <pubDate>2024-01-04</pubDate>
            </item>
          </channel>
        </rss>
        """.data(using: .utf8)!

        let result = RSSFeedParser.parse(data: xml)
        #expect(result.items.count == 1)
        let item = result.items[0]
        #expect(item.link == nil)
        #expect(item.id == "Linkless2024-01-04")
    }

    // MARK: - Atom 1.0

    @Test("Atom feed title + entries decode title / link[@href] / updated / summary")
    func atomFeedParses() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <link href="https://example.test/" />
          <entry>
            <title>Entry One</title>
            <link href="https://example.test/a1" />
            <updated>2024-01-10T12:00:00Z</updated>
            <summary>Entry summary.</summary>
          </entry>
          <entry>
            <title>Entry Two</title>
            <link href="https://example.test/a2" />
            <published>2024-01-11T12:00:00Z</published>
            <summary>Second entry.</summary>
          </entry>
        </feed>
        """.data(using: .utf8)!

        let result = RSSFeedParser.parse(data: xml)
        #expect(result.title == "Atom Feed")
        #expect(result.items.count == 2)

        let first = result.items[0]
        #expect(first.title == "Entry One")
        #expect(first.link == "https://example.test/a1")
        #expect(first.pubDate == "2024-01-10T12:00:00Z")
        #expect(first.descriptionHTML == "Entry summary.")

        // `published` is also accepted as a date.
        let second = result.items[1]
        #expect(second.pubDate == "2024-01-11T12:00:00Z")
    }

    // MARK: - RSSItem derived properties

    @Test("RSSItem.linkURL parses link strings; nil link → nil URL")
    func rssItemLinkURL() {
        let withLink = RSSItem(
            id: "1", title: "T", link: "https://example.test/x",
            pubDate: nil, descriptionHTML: nil
        )
        let withoutLink = RSSItem(
            id: "2", title: "T", link: nil,
            pubDate: nil, descriptionHTML: nil
        )
        #expect(withLink.linkURL?.absoluteString == "https://example.test/x")
        #expect(withoutLink.linkURL == nil)
    }

    @Test("RSSItem.publishedSummary is pubDate or empty string")
    func rssItemPublishedSummary() {
        let dated = RSSItem(id: "1", title: "T", link: nil, pubDate: "2024-01-01", descriptionHTML: nil)
        let undated = RSSItem(id: "2", title: "T", link: nil, pubDate: nil, descriptionHTML: nil)
        #expect(dated.publishedSummary == "2024-01-01")
        #expect(undated.publishedSummary == "")
    }

    @Test("RSSItem.plainTextBody strips tags + decodes common entities")
    func rssItemPlainTextBody() {
        let html = "<p>Hello <b>world</b>! &amp; &nbsp;done.</p>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.plainTextBody == "Hello world! &  done.")
    }

    @Test("RSSItem.plainTextBody handles &#39; and &#x27; apostrophes")
    func rssItemPlainTextBodyApostrophes() {
        let item = RSSItem(
            id: "1", title: "T", link: nil, pubDate: nil,
            descriptionHTML: "don&#39;t and don&#x27;t"
        )
        #expect(item.plainTextBody == "don't and don't")
    }

    @Test("RSSItem.plainTextBody decodes &amp;lt; to the literal &lt;, not the < character")
    func rssItemPlainTextBodyAvoidsDoubleDecode() {
        // The old chain ran `&amp;` → `&` BEFORE `&lt;` → `<`, so
        // `&amp;lt;` (a literal `&lt;` in the original payload)
        // would decode all the way to `<`. The shared
        // QuillFoundation.HTMLEntities.decode helper applies
        // `&amp;` last to avoid that double-decode.
        let item = RSSItem(
            id: "1", title: "T", link: nil, pubDate: nil,
            descriptionHTML: "&amp;lt;script&amp;gt;"
        )
        #expect(item.plainTextBody == "&lt;script&gt;")
    }

    @Test("Empty XML yields an empty parse result, not a crash")
    func emptyXMLEmptyResult() {
        let result = RSSFeedParser.parse(data: Data())
        #expect(result.title == nil)
        #expect(result.items.isEmpty)
    }

    // MARK: - Reader model derived state

    @MainActor
    @Test("RSSReaderModel keeps selected item + status text cached")
    func readerModelDerivedState() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()

        #expect(model.statusText == "2 items")
        #expect(model.rows.map(\.id) == ["1", "2"])
        #expect(model.selectedItem?.id == "1")
        #expect(model.selectedDetail?.id == "1")
        #expect(model.selectedDetail?.plainTextBody == "Body of the first fixture article.")

        model.selectedID = "2"
        #expect(model.selectedItem?.id == "2")
        #expect(model.selectedDetail?.id == "2")

        model.isLoading = true
        #expect(model.statusText == "Fetching feed…")

        model.isLoading = false
        model.error = "offline"
        #expect(model.statusText == "Error: offline")
    }

    @MainActor
    @Test("RSSReaderModel fixture seeding is idempotent")
    func readerModelFixtureSeedingIsIdempotent() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        let rows = model.rows
        let detail = model.selectedDetail
        let statusText = model.statusText

        model.seedProfileFixtures()

        #expect(model.rows == rows)
        #expect(model.selectedDetail == detail)
        #expect(model.statusText == statusText)
    }

    @MainActor
    @Test("RSSReaderModel applies initial feed selection from the shared backend env key")
    func readerModelInitialFeedSelectionReadsEnvironment() {
        let model = RSSReaderModel(environment: ["QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START": "1"])

        model.seedProfileFixtures()

        #expect(QuillNetNewsWireInitialSelection.selectedFeedIndexEnvironmentKey == "QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START")
        #expect(model.selectedItem?.id == "2")
        #expect(model.selectedDetail?.id == "2")
    }
}
