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

        // Seeded selection auto-marks item "1" read, so unread is
        // 4 of 5. statusText now surfaces unread count (added in
        // the read/unread parity step).
        #expect(model.statusText == "4 unread · 5 items")
        #expect(model.rows.map(\.id) == ["1", "2", "3", "4", "5"])
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

    @Test("Feed.init(title:url:) uses url as id")
    func feedInitFromTitleAndURLUsesURLAsID() {
        let feed = Feed(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main")

        #expect(feed.id == "https://daringfireball.net/feeds/main")
        #expect(feed.title == "Daring Fireball")
        #expect(feed.url == "https://daringfireball.net/feeds/main")
    }

    @Test("DefaultFeedList.seed contains the canonical bootstrap subscriptions")
    func defaultFeedListSeedShape() {
        let seed = DefaultFeedList.seed
        #expect(seed.count >= 2)
        #expect(seed.allSatisfy { !$0.title.isEmpty })
        #expect(seed.allSatisfy { URL(string: $0.url) != nil })
        // IDs must be unique so sidebar selection round-trips deterministically.
        #expect(Set(seed.map(\.id)).count == seed.count)
    }

    @MainActor
    @Test("RSSReaderModel seeds subscribedFeeds + selectedFeedID from defaults")
    func readerModelSeedsSubscribedFeeds() {
        let model = RSSReaderModel()
        #expect(model.subscribedFeeds == DefaultFeedList.seed)
        #expect(model.selectedFeedID == DefaultFeedList.seed.first?.id)
    }

    @MainActor
    @Test("RSSReaderModel accepts a custom subscribedFeeds list")
    func readerModelAcceptsCustomFeedList() {
        let custom = [
            Feed(title: "A", url: "https://a.test/feed"),
            Feed(title: "B", url: "https://b.test/feed"),
        ]
        let model = RSSReaderModel(subscribedFeeds: custom)
        #expect(model.subscribedFeeds == custom)
        #expect(model.selectedFeedID == "https://a.test/feed")
    }

    @MainActor
    @Test("RSSReaderModel.currentFeedURL resolves the selected feed's URL")
    func readerModelCurrentFeedURLResolvesSelection() {
        let custom = [
            Feed(title: "A", url: "https://a.test/feed"),
            Feed(title: "B", url: "https://b.test/feed"),
        ]
        let model = RSSReaderModel(subscribedFeeds: custom)
        #expect(model.currentFeedURL == "https://a.test/feed")

        model.selectedFeedID = "https://b.test/feed"
        #expect(model.currentFeedURL == "https://b.test/feed")
    }

    @MainActor
    @Test("RSSReaderModel.currentFeedURL falls back to the first feed when selection is missing")
    func readerModelCurrentFeedURLFallsBack() {
        let custom = [Feed(title: "A", url: "https://a.test/feed")]
        let model = RSSReaderModel(subscribedFeeds: custom)
        model.selectedFeedID = "https://bogus.test/feed"
        #expect(model.currentFeedURL == "https://a.test/feed")
    }

    @MainActor
    @Test("RSSReaderModel.currentFeedURL is nil when no feeds are subscribed")
    func readerModelCurrentFeedURLNilWhenEmpty() {
        let model = RSSReaderModel(subscribedFeeds: [])
        #expect(model.currentFeedURL == nil)
        #expect(model.selectedFeedID == nil)
    }

    @MainActor
    @Test("RSSReaderModel selectItem auto-marks the article read")
    func readerModelSelectItemAutoMarksRead() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        #expect(model.isRead(id: "1"))      // seeded selection marks 1 read
        #expect(!model.isRead(id: "2"))

        model.selectItem(id: "2")
        #expect(model.isRead(id: "2"))
        #expect(model.readArticleIDs.contains("1"))
        #expect(model.readArticleIDs.contains("2"))
    }

    @MainActor
    @Test("RSSReaderModel unreadCount reflects items minus read set")
    func readerModelUnreadCount() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // 5 fixtures, 1 auto-read from initial selection → 4 unread.
        #expect(model.items.count == 5)
        #expect(model.unreadCount == 4)

        model.selectItem(id: "2")
        model.selectItem(id: "3")
        #expect(model.unreadCount == 2)
    }

    @MainActor
    @Test("RSSReaderModel statusText surfaces unread count when nonzero")
    func readerModelStatusTextShowsUnread() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        #expect(model.statusText.contains("unread"))
        #expect(model.statusText.contains("5 items"))
    }

    @MainActor
    @Test("RSSReaderModel toggleReadOnSelection flips selected article's read state")
    func readerModelToggleReadOnSelection() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "3")
        #expect(model.isRead(id: "3"))

        model.toggleReadOnSelection()
        #expect(!model.isRead(id: "3"))

        model.toggleReadOnSelection()
        #expect(model.isRead(id: "3"))
    }

    @MainActor
    @Test("RSSReaderModel.markRead is idempotent")
    func readerModelMarkReadIdempotent() {
        let model = RSSReaderModel()
        model.markRead(id: "abc")
        let countAfter1 = model.readArticleIDs.count
        model.markRead(id: "abc")
        #expect(model.readArticleIDs.count == countAfter1)
        #expect(model.isRead(id: "abc"))
    }

    @MainActor
    @Test("RSSReaderModel.toggleStarred flips per-id state")
    func readerModelToggleStarred() {
        let model = RSSReaderModel()
        #expect(!model.isStarred(id: "abc"))
        model.toggleStarred(id: "abc")
        #expect(model.isStarred(id: "abc"))
        model.toggleStarred(id: "abc")
        #expect(!model.isStarred(id: "abc"))
    }

    @MainActor
    @Test("RSSReaderModel.toggleStarredOnSelection requires a selection")
    func readerModelToggleStarredOnSelection() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Initial selection is "1" — toggling stars it.
        model.toggleStarredOnSelection()
        #expect(model.isStarred(id: "1"))

        model.selectItem(id: "3")
        model.toggleStarredOnSelection()
        #expect(model.isStarred(id: "3"))
        #expect(model.starredArticleIDs == ["1", "3"])
    }

    @MainActor
    @Test("RSSReaderModel.starredCount reflects starred items in the loaded timeline")
    func readerModelStarredCount() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        #expect(model.starredCount == 0)
        model.toggleStarred(id: "1")
        model.toggleStarred(id: "2")
        #expect(model.starredCount == 2)
        // Star an article that isn't in the current timeline — count stays at 2.
        model.toggleStarred(id: "not-in-timeline")
        #expect(model.starredCount == 2)
        #expect(model.starredArticleIDs.contains("not-in-timeline"))
    }

    @MainActor
    @Test("RSSReaderModel.toggleStarredOnSelection no-ops without a selection")
    func readerModelToggleStarredOnSelectionNoOps() {
        let model = RSSReaderModel(subscribedFeeds: [])
        // No items, no selection.
        #expect(model.selectedID == nil)
        model.toggleStarredOnSelection()
        #expect(model.starredArticleIDs.isEmpty)
    }

    // MARK: - OPML import

    @Test("OPMLImporter parses flat outline tree into Feed list")
    func opmlImporterFlatTree() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>My Subscriptions</title></head>
          <body>
            <outline type="rss" text="Daring Fireball" xmlUrl="https://daringfireball.net/feeds/main"/>
            <outline type="rss" text="Hacker News" xmlUrl="https://hnrss.org/frontpage"/>
          </body>
        </opml>
        """

        let result = OPMLImporter.parse(xml: xml)
        #expect(result.title == "My Subscriptions")
        #expect(result.feeds.count == 2)
        #expect(result.feeds[0].title == "Daring Fireball")
        #expect(result.feeds[0].url == "https://daringfireball.net/feeds/main")
        #expect(result.feeds[0].id == "https://daringfireball.net/feeds/main")
        #expect(result.feeds[1].title == "Hacker News")
    }

    @Test("OPMLImporter flattens nested folders into a single feed list")
    func opmlImporterNestedFolders() {
        let xml = """
        <opml version="2.0">
          <body>
            <outline text="News">
              <outline type="rss" text="NYT" xmlUrl="https://nyt.test/feed"/>
              <outline text="Tech">
                <outline type="rss" text="ATP" xmlUrl="https://atp.test/feed"/>
              </outline>
            </outline>
            <outline type="rss" text="Standalone" xmlUrl="https://standalone.test/feed"/>
          </body>
        </opml>
        """

        let result = OPMLImporter.parse(xml: xml)
        #expect(result.feeds.count == 3)
        #expect(result.feeds.map(\.title) == ["NYT", "ATP", "Standalone"])
    }

    @Test("OPMLImporter skips outline rows with no xmlUrl")
    func opmlImporterSkipsXMLURLLessOutlines() {
        let xml = """
        <opml version="2.0">
          <body>
            <outline text="Bare Folder"/>
            <outline type="rss" text="Real" xmlUrl="https://real.test/feed"/>
          </body>
        </opml>
        """

        let result = OPMLImporter.parse(xml: xml)
        #expect(result.feeds.count == 1)
        #expect(result.feeds[0].url == "https://real.test/feed")
    }

    @Test("OPMLImporter falls back to title attribute when text is missing")
    func opmlImporterTitleAttributeFallback() {
        let xml = """
        <opml version="2.0">
          <body>
            <outline type="rss" title="Title-Only Feed" xmlUrl="https://t.test/feed"/>
          </body>
        </opml>
        """

        let result = OPMLImporter.parse(xml: xml)
        #expect(result.feeds.count == 1)
        #expect(result.feeds[0].title == "Title-Only Feed")
    }

    @MainActor
    @Test("RSSReaderModel.importOPML appends new feeds and dedupes by URL")
    func readerModelImportOPMLDedupes() {
        let model = RSSReaderModel(subscribedFeeds: [
            Feed(title: "Existing", url: "https://existing.test/feed"),
        ])

        let xml = """
        <opml version="2.0">
          <body>
            <outline type="rss" text="Existing dup" xmlUrl="https://existing.test/feed"/>
            <outline type="rss" text="New" xmlUrl="https://new.test/feed"/>
          </body>
        </opml>
        """

        let added = model.importOPML(xml: xml)
        #expect(added == 1)
        #expect(model.subscribedFeeds.count == 2)
        #expect(model.subscribedFeeds.map(\.url).contains("https://new.test/feed"))
        // Existing entry's title is kept (no overwrite on dup).
        #expect(model.subscribedFeeds.first(where: { $0.url == "https://existing.test/feed" })?.title == "Existing")
    }

    @MainActor
    @Test("RSSReaderModel.importOPML seeds selectedFeedID when starting empty")
    func readerModelImportOPMLSeedsSelection() {
        let model = RSSReaderModel(subscribedFeeds: [])
        #expect(model.selectedFeedID == nil)

        let xml = """
        <opml version="2.0">
          <body>
            <outline type="rss" text="A" xmlUrl="https://a.test/feed"/>
          </body>
        </opml>
        """

        let added = model.importOPML(xml: xml)
        #expect(added == 1)
        #expect(model.selectedFeedID == "https://a.test/feed")
    }

    // MARK: - OPML export

    @Test("OPMLExporter produces well-formed OPML 2.0 with head + outlines")
    func opmlExporterBasicShape() {
        let feeds = [
            Feed(title: "A", url: "https://a.test/feed"),
            Feed(title: "B", url: "https://b.test/feed"),
        ]
        let xml = OPMLExporter.export(feeds: feeds, title: "Mine")
        #expect(xml.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(xml.contains("<opml version=\"2.0\">"))
        #expect(xml.contains("<title>Mine</title>"))
        #expect(xml.contains("<outline type=\"rss\" text=\"A\" title=\"A\" xmlUrl=\"https://a.test/feed\"/>"))
        #expect(xml.contains("<outline type=\"rss\" text=\"B\" title=\"B\" xmlUrl=\"https://b.test/feed\"/>"))
        #expect(xml.contains("</opml>"))
    }

    @Test("OPMLExporter defaults the head title when none is supplied")
    func opmlExporterDefaultTitle() {
        let xml = OPMLExporter.export(feeds: [])
        #expect(xml.contains("<title>\(OPMLExporter.defaultTitle)</title>"))
    }

    @Test("OPMLExporter escapes XML-special characters in titles and URLs")
    func opmlExporterEscapesAttributes() {
        let feeds = [
            Feed(title: "Cheese & Co. <Daily> \"Newsletter\"", url: "https://x.test/feed?a=1&b=2"),
        ]
        let xml = OPMLExporter.export(feeds: feeds)
        #expect(xml.contains("text=\"Cheese &amp; Co. &lt;Daily&gt; &quot;Newsletter&quot;\""))
        #expect(xml.contains("xmlUrl=\"https://x.test/feed?a=1&amp;b=2\""))
    }

    @Test("OPML export → import round-trip preserves feed list")
    func opmlRoundTripPreservesFeeds() {
        let original = [
            Feed(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main"),
            Feed(title: "Headline & Comments", url: "https://x.test/feed?id=1&format=rss"),
            Feed(title: "<Sample>", url: "https://b.test/feed"),
        ]
        let xml = OPMLExporter.export(feeds: original)
        let reimported = OPMLImporter.parse(xml: xml).feeds
        #expect(reimported == original)
    }

    @MainActor
    @Test("RSSReaderModel.exportOPML serializes the live subscription list")
    func readerModelExportOPML() {
        let model = RSSReaderModel(subscribedFeeds: [
            Feed(title: "One", url: "https://one.test/feed"),
            Feed(title: "Two", url: "https://two.test/feed"),
        ])
        let xml = model.exportOPML(title: "Quill Subscriptions")
        #expect(xml.contains("<title>Quill Subscriptions</title>"))
        #expect(xml.contains("xmlUrl=\"https://one.test/feed\""))
        #expect(xml.contains("xmlUrl=\"https://two.test/feed\""))
    }

    @MainActor
    @Test("RSSReaderModel export → import is idempotent (no dup growth)")
    func readerModelOPMLRoundTripIsIdempotent() {
        let model = RSSReaderModel(subscribedFeeds: [
            Feed(title: "One", url: "https://one.test/feed"),
            Feed(title: "Two", url: "https://two.test/feed"),
        ])
        let xml = model.exportOPML()
        let added = model.importOPML(xml: xml)
        #expect(added == 0)
        #expect(model.subscribedFeeds.count == 2)
    }

    // MARK: - Search / filter

    @MainActor
    @Test("RSSReaderModel.filteredRows == rows when searchQuery is empty")
    func searchEmptyQueryReturnsAllRows() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        #expect(model.searchQuery.isEmpty)
        #expect(model.filteredRows.map(\.id) == model.rows.map(\.id))
    }

    @MainActor
    @Test("RSSReaderModel.filteredRows matches case-insensitively on title")
    func searchMatchesTitleCaseInsensitive() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.searchQuery = "SWIFT"
        let ids = model.filteredRows.map(\.id)
        // Fixture "3" is the Swift.org toolchain article.
        #expect(ids == ["3"])
    }

    @MainActor
    @Test("RSSReaderModel.filteredRows matches against article body too")
    func searchMatchesBody() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.searchQuery = "second"
        // Fixture "2" body: 'Body of the second fixture article.'
        #expect(model.filteredRows.map(\.id) == ["2"])
    }

    @MainActor
    @Test("RSSReaderModel.filteredRows returns empty when no match")
    func searchEmptyOnNoMatch() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.searchQuery = "zzz-nothing-matches"
        #expect(model.filteredRows.isEmpty)
        #expect(model.statusText.contains("0 matching"))
    }

    @MainActor
    @Test("RSSReaderModel.searchQuery trims whitespace for both filter + status")
    func searchTrimsWhitespace() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.searchQuery = "   "
        // Whitespace-only is treated as empty: full timeline, unread-flavored status.
        #expect(model.filteredRows.map(\.id) == model.rows.map(\.id))
        #expect(model.statusText.contains("unread"))
    }

    @MainActor
    @Test("RSSReaderModel.statusText surfaces matching count when filter is active")
    func searchStatusTextShowsMatching() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.searchQuery = "Profile"  // matches title prefix of fixtures 1 and 2
        let matching = model.filteredRows.count
        #expect(matching >= 1)
        #expect(model.statusText == "\(matching) matching · \(model.items.count) items")
    }

    // MARK: - Smart feeds

    @Test("SmartFeed exposes a displayName + symbol for every case")
    func smartFeedDisplayNamesCoverAllCases() {
        for kind in SmartFeed.allCases {
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.symbol.isEmpty)
            #expect(kind.id == kind.rawValue)
        }
    }

    @MainActor
    @Test("RSSReaderModel.allUnread smart feed filters to unread items")
    func smartFeedAllUnreadFiltersUnread() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Seeded selection marks "1" read → 4 unread.
        model.selectSmartFeed(.allUnread)
        let ids = model.filteredRows.map(\.id)
        #expect(ids == ["2", "3", "4", "5"])
        #expect(model.statusText.contains("All Unread"))
        #expect(model.statusText.contains("4 of 5"))
    }

    @MainActor
    @Test("RSSReaderModel.starred smart feed filters to starred items")
    func smartFeedStarredFiltersStarred() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.toggleStarred(id: "2")
        model.toggleStarred(id: "4")

        model.selectSmartFeed(.starred)
        let ids = model.filteredRows.map(\.id)
        #expect(ids == ["2", "4"])
        #expect(model.statusText.contains("Starred"))
        #expect(model.statusText.contains("2 of 5"))
    }

    @MainActor
    @Test("Smart-feed + search compose: search narrows the smart-feed view")
    func smartFeedSearchComposes() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Mark all read except 3 + 5.
        model.markRead(id: "2")
        model.markRead(id: "4")
        model.selectSmartFeed(.allUnread)
        model.searchQuery = "Swift"  // only fixture "3"

        let ids = model.filteredRows.map(\.id)
        #expect(ids == ["3"])
        #expect(model.statusText.contains("(search)"))
    }

    @MainActor
    @Test("selectFeed clears the active smart feed")
    func selectFeedClearsSmartFeed() async {
        let model = RSSReaderModel(subscribedFeeds: [
            Feed(title: "A", url: "https://invalid.example/"),
        ])
        model.selectSmartFeed(.starred)
        #expect(model.selectedSmartFeed == .starred)

        // Fetch will fail (invalid URL) but we only care about
        // the smart-feed clear side effect.
        await model.selectFeed(id: "https://invalid.example/")
        #expect(model.selectedSmartFeed == nil)
    }

    @MainActor
    @Test("selectSmartFeed(nil) returns to the regular feed view")
    func selectSmartFeedNilReturnsToFeedView() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectSmartFeed(.starred)
        #expect(model.filteredItems.isEmpty)  // nothing starred yet

        model.selectSmartFeed(nil)
        #expect(model.filteredRows.count == model.rows.count)
    }

    // MARK: - Keyboard navigation

    @MainActor
    @Test("selectNextItem advances through the filtered timeline")
    func keyboardSelectNextItem() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Seeded selection = "1".
        #expect(model.selectedID == "1")
        model.selectNextItem()
        #expect(model.selectedID == "2")
        model.selectNextItem()
        #expect(model.selectedID == "3")
    }

    @MainActor
    @Test("selectNextItem stops at the end (no wraparound)")
    func keyboardSelectNextItemStopsAtEnd() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "5")  // last fixture
        model.selectNextItem()
        #expect(model.selectedID == "5")
    }

    @MainActor
    @Test("selectNextItem selects the first item when nothing is selected")
    func keyboardSelectNextItemSeedsSelection() {
        let model = RSSReaderModel(subscribedFeeds: [])
        model.items = [
            RSSItem(id: "a", title: "A", link: nil, pubDate: nil, descriptionHTML: nil),
            RSSItem(id: "b", title: "B", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        model.selectItem(id: nil)
        model.selectNextItem()
        #expect(model.selectedID == "a")
    }

    @MainActor
    @Test("selectPreviousItem steps back through the timeline")
    func keyboardSelectPreviousItem() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "3")
        model.selectPreviousItem()
        #expect(model.selectedID == "2")
        model.selectPreviousItem()
        #expect(model.selectedID == "1")
        // No-op at the top.
        model.selectPreviousItem()
        #expect(model.selectedID == "1")
    }

    @MainActor
    @Test("markReadAndAdvance marks current read and moves to next")
    func keyboardMarkReadAndAdvance() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Initial: selected "1", auto-marked read.
        #expect(model.isRead(id: "1"))
        model.markReadAndAdvance()
        #expect(model.selectedID == "2")
        #expect(model.isRead(id: "2"))
        model.markReadAndAdvance()
        #expect(model.selectedID == "3")
    }

    @MainActor
    @Test("keyboard navigation respects the active smart-feed filter")
    func keyboardNavRespectsSmartFeed() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Pre-mark items "2" + "4" read so allUnread shows 1, 3, 5
        // (item 1 is unread because selectSmartFeed clears the selection
        // before the auto-mark from seeding sticks via post-seed taps).
        model.toggleReadOnSelection()  // unmark item 1 first
        model.markRead(id: "2")
        model.markRead(id: "4")
        model.selectSmartFeed(.allUnread)
        // filteredItems should be 1, 3, 5
        #expect(model.filteredItems.map(\.id) == ["1", "3", "5"])

        // selectNextItem from no selection picks first of filtered.
        model.selectNextItem()
        #expect(model.selectedID == "1")
        model.selectNextItem()
        #expect(model.selectedID == "3")
        model.selectNextItem()
        #expect(model.selectedID == "5")
    }

    @MainActor
    @Test("markReadAndAdvance with no selection selects first (which auto-marks read)")
    func keyboardMarkReadAndAdvanceNoSelection() {
        let model = RSSReaderModel(subscribedFeeds: [])
        model.items = [
            RSSItem(id: "a", title: "A", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        model.selectItem(id: nil)
        model.markReadAndAdvance()
        // selectItem(id:) auto-marks read, so the spacebar's
        // no-selection branch lands on a read article. This
        // matches upstream NetNewsWire's behavior — pressing
        // space on an empty selection picks up the first
        // article and treats it as read.
        #expect(model.selectedID == "a")
        #expect(model.isRead(id: "a"))
    }

    // MARK: - Background refresh

    @MainActor
    @Test("isAutoRefreshDue is true when no fetch has happened")
    func backgroundRefreshDueWhenNeverFetched() {
        let model = RSSReaderModel()
        #expect(model.lastFetchAt == nil)
        #expect(model.isAutoRefreshDue())
    }

    @MainActor
    @Test("isAutoRefreshDue is false within the interval window")
    func backgroundRefreshNotDueWithinInterval() {
        let model = RSSReaderModel()
        model.refreshIntervalSeconds = 30 * 60
        let now = Date()
        model.lastFetchAt = now.addingTimeInterval(-5 * 60)  // fetched 5 min ago
        #expect(!model.isAutoRefreshDue(now: now))
    }

    @MainActor
    @Test("isAutoRefreshDue becomes true once the interval has elapsed")
    func backgroundRefreshDueAfterInterval() {
        let model = RSSReaderModel()
        model.refreshIntervalSeconds = 60  // 1 min cadence
        let now = Date()
        model.lastFetchAt = now.addingTimeInterval(-120)  // fetched 2 min ago
        #expect(model.isAutoRefreshDue(now: now))
    }

    @MainActor
    @Test("isAutoRefreshDue honors a disabled (nil) interval")
    func backgroundRefreshDisabledWhenNil() {
        let model = RSSReaderModel()
        model.refreshIntervalSeconds = nil
        #expect(!model.isAutoRefreshDue())
    }

    @MainActor
    @Test("backgroundRefreshTick no-ops when no feed URL is available")
    func backgroundRefreshTickNoOpsWithoutFeed() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        await model.backgroundRefreshTick()
        // No crash, no items, no fetchedAt update.
        #expect(model.items.isEmpty)
        #expect(model.lastFetchAt == nil)
    }

    @MainActor
    @Test("startBackgroundRefresh is a no-op when interval is nil")
    func startBackgroundRefreshNoOpsWhenDisabled() {
        let model = RSSReaderModel()
        model.refreshIntervalSeconds = nil
        model.startBackgroundRefresh()
        // No task should be running.
        model.stopBackgroundRefresh()  // idempotent
    }

    @MainActor
    @Test("startBackgroundRefresh + stopBackgroundRefresh are idempotent")
    func startStopBackgroundRefreshIdempotent() {
        let model = RSSReaderModel()
        model.refreshIntervalSeconds = 60
        model.startBackgroundRefresh()
        model.startBackgroundRefresh()  // replaces the prior task safely
        model.stopBackgroundRefresh()
        model.stopBackgroundRefresh()   // double-stop is fine
    }
}
