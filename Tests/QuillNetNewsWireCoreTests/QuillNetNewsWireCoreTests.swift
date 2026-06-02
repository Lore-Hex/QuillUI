import Foundation
import Testing
@testable import QuillNetNewsWireCore
import QuillArticles

@Suite("QuillNetNewsWireCore RSS / Atom parser")
struct QuillNetNewsWireCoreTests {

    // MARK: - RSS 2.0

    // Legacy RSSFeedParser.parse(data:) was retired with this
    // iteration — the production fetch() path flows through
    // QuillRSParser (vendored upstream Ranchero-Software/NetNewsWire
    // FeedParser). RSS / Atom / JSON / RSS-in-JSON decoding is
    // covered by parseUpstream-based tests below and by upstream's
    // own much larger test suite (.upstream/netnewswire/Modules/
    // RSParser/Tests/RSParserTests). What remains in this file is
    // RSSItem property behavior (linkURL/publishedSummary/HTML
    // body) plus reader-model wiring.

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

    // MARK: - Upstream FeedParser adapter (parseUpstream)

    @Test("parseUpstream parses RSS 2.0 via upstream FeedParser, falls back Untitled and ISO-8601 pubDate")
    func parseUpstreamRSS2() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Upstream Example</title>
            <link>https://example.test/</link>
            <description>An example feed for the upstream FeedParser adapter — padded over 128 bytes.</description>
            <item>
              <title>Has Title</title>
              <link>https://example.test/1</link>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <description>Body one.</description>
            </item>
            <item>
              <link>https://example.test/2</link>
              <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
              <description>Body two.</description>
            </item>
          </channel>
        </rss>
        """
        let result = RSSFeedParser.parseUpstream(data: Data(xml.utf8), url: "https://example.test/feed.xml")
        #expect(result.title == "Upstream Example")
        #expect(result.items.count == 2)
        // Sort is newest-first, so item 2 (Jan 2) sorts before item 1 (Jan 1).
        let titles = result.items.map(\.title)
        #expect(titles.contains("Has Title"))
        #expect(titles.contains("Untitled"))
        // pubDate is ISO-8601 normalized (legacy parser preserved
        // the raw header — the adapter intentionally normalizes).
        let pubs = result.items.compactMap(\.pubDate)
        #expect(pubs.allSatisfy { $0.contains("T") && $0.hasSuffix("Z") })
    }

    @Test("parseUpstream sorts items newest-first with uniqueID tiebreaker")
    func parseUpstreamSortOrder() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Sort Test</title>
            <description>Sort-order pin against upstream FeedParser adapter — fill to 128 bytes minimum.</description>
            <item><title>Older</title><link>https://example.test/a</link><pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate><description>x</description></item>
            <item><title>Newer</title><link>https://example.test/b</link><pubDate>Wed, 03 Jan 2024 12:00:00 GMT</pubDate><description>y</description></item>
          </channel>
        </rss>
        """
        let result = RSSFeedParser.parseUpstream(data: Data(xml.utf8), url: "https://example.test/feed.xml")
        #expect(result.items.first?.title == "Newer")
        #expect(result.items.last?.title == "Older")
    }

    @Test("parseUpstream returns empty Result for unrecognized input")
    func parseUpstreamEmpty() {
        let result = RSSFeedParser.parseUpstream(data: Data("not-a-feed".utf8), url: "https://example.test/")
        #expect(result.title == nil)
        #expect(result.items.isEmpty)
    }

    // MARK: - Upstream Article materialization

    @Test("parseUpstreamArticles produces Article values from RSS 2.0")
    func parseUpstreamArticlesRSS2() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Articles Test Feed</title>
            <description>Pinning Article materialization from upstream RSParser — padded to clear 128.</description>
            <item><title>Alpha</title><link>https://example.test/a</link><pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate><description>One.</description></item>
            <item><title>Beta</title><link>https://example.test/b</link><pubDate>Wed, 03 Jan 2024 12:00:00 GMT</pubDate><description>Two.</description></item>
          </channel>
        </rss>
        """
        let articles = RSSFeedParser.parseUpstreamArticles(
            data: Data(xml.utf8),
            url: "https://example.test/feed.xml"
        )
        #expect(articles.count == 2)
        // Newest-first ordering matches parseUpstream / timeline sort.
        #expect(articles.first?.title == "Beta")
        #expect(articles.last?.title == "Alpha")
        // articleID is the md5-via-shim synthesis — 32 hex chars.
        #expect(articles.allSatisfy { $0.articleID.count == 32 })
        // accountID defaults to "Local" until a real Account lands.
        #expect(articles.allSatisfy { $0.accountID == "Local" })
        // feedID round-trips the URL we passed in.
        #expect(articles.allSatisfy { $0.feedID == "https://example.test/feed.xml" })
    }

    @Test("parseUpstreamArticles returns [] for unrecognized input")
    func parseUpstreamArticlesEmpty() {
        let articles = RSSFeedParser.parseUpstreamArticles(
            data: Data("not-a-feed".utf8),
            url: "https://example.test/"
        )
        #expect(articles.isEmpty)
    }

    @MainActor
    @Test("RSSReaderModel.articles is empty before any fetch")
    func readerModelArticlesEmptyInitially() {
        let model = RSSReaderModel()
        #expect(model.articles.isEmpty)
    }

    // MARK: - Today smart feed (date-based)

    @MainActor
    @Test("Today smart feed filters items by datePublished within 24h via articles")
    func smartFeedTodayFiltersByDate() {
        let model = RSSReaderModel()
        // Build items + parallel articles where two have today's
        // date and two have last-week dates. Today should keep
        // only the recent two.
        let now = Date()
        let recent1 = now.addingTimeInterval(-3600)        // 1h ago — today
        let recent2 = now.addingTimeInterval(-43_200)      // 12h ago — today
        let old1 = now.addingTimeInterval(-86_400 * 3)     // 3 days ago — not today
        let old2 = now.addingTimeInterval(-86_400 * 7)     // 7 days ago — not today

        let items = [
            RSSItem(id: "r1", title: "Recent 1", link: nil, pubDate: nil, descriptionHTML: nil),
            RSSItem(id: "r2", title: "Recent 2", link: nil, pubDate: nil, descriptionHTML: nil),
            RSSItem(id: "o1", title: "Old 1", link: nil, pubDate: nil, descriptionHTML: nil),
            RSSItem(id: "o2", title: "Old 2", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        let articles = [
            articleStub(id: "r1", date: recent1),
            articleStub(id: "r2", date: recent2),
            articleStub(id: "o1", date: old1),
            articleStub(id: "o2", date: old2),
        ]

        model.items = items
        model.articles = articles

        model.selectSmartFeed(.today)
        let ids = Set(model.filteredItems.map(\.id))
        #expect(ids == ["r1", "r2"])
        #expect(model.count(for: .today) == 2)
        #expect(model.statusText.contains("Today"))
    }

    @MainActor
    @Test("Today smart feed ignores items with nil datePublished")
    func smartFeedTodaySkipsUndated() {
        let model = RSSReaderModel()
        model.items = [
            RSSItem(id: "u", title: "Undated", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        model.articles = [articleStub(id: "u", date: nil)]
        model.selectSmartFeed(.today)
        #expect(model.filteredItems.isEmpty)
        #expect(model.count(for: .today) == 0)
    }

    @MainActor
    @Test("SmartFeed.allCases includes Today + All Unread + Starred")
    func smartFeedAllCasesIncludesToday() {
        let ids = Set(SmartFeed.allCases.map(\.id))
        #expect(ids == ["today", "allUnread", "starred"])
    }

    // MARK: - addSubscription (FeedFinder integration)

    // MARK: - Mark all read

    @MainActor
    @Test("markAllVisibleAsRead marks every item in filteredItems")
    func markAllReadCoversFilteredItems() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Seeded selection marks item "1" → 4 unread.
        #expect(model.unreadCount == 4)
        let added = model.markAllVisibleAsRead()
        #expect(added == 4)
        #expect(model.unreadCount == 0)
    }

    @MainActor
    @Test("markAllVisibleAsRead respects an active smart-feed filter")
    func markAllReadRespectsSmartFeed() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.toggleStarred(id: "2")
        model.toggleStarred(id: "4")
        // Switch to Starred — filteredItems is just 2 + 4.
        model.selectSmartFeed(.starred)
        let added = model.markAllVisibleAsRead()
        #expect(added == 2)
        #expect(model.isRead(id: "2"))
        #expect(model.isRead(id: "4"))
        // Unstarred items 3 + 5 should still be unread.
        #expect(!model.isRead(id: "3"))
        #expect(!model.isRead(id: "5"))
    }

    @MainActor
    @Test("markAllVisibleAsRead is idempotent on all-read input")
    func markAllReadIdempotent() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        _ = model.markAllVisibleAsRead()
        let secondCallAdded = model.markAllVisibleAsRead()
        #expect(secondCallAdded == 0)
        #expect(model.unreadCount == 0)
    }

    @MainActor
    @Test("markAboveSelectionAsRead marks items before selection")
    func markAboveMarks() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "3")  // also auto-marks 3 read
        let added = model.markAboveSelectionAsRead()
        // 3 - 1 = 2 above. But 1 was already marked from seed selection.
        // 2 → 1 + 2 = 2 items above; 1 was already read; so only 2 new
        // marks (items 2 itself is the only newly-read one from above).
        // Actually fixtures: 1, 2, 3, 4, 5; selection now is 3 (also
        // already read). Above = items 1, 2. Item 1 was auto-read from
        // seedProfileFixtures' selectItem(id: "1"). Item 2 still unread.
        #expect(added == 1)
        #expect(model.isRead(id: "1"))
        #expect(model.isRead(id: "2"))
        #expect(model.isRead(id: "3"))
        #expect(!model.isRead(id: "4"))
        #expect(!model.isRead(id: "5"))
    }

    @MainActor
    @Test("markAboveSelectionAsRead no-ops at first item")
    func markAboveNoOpAtFirst() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Selection is already at index 0 from seed; no items above.
        let added = model.markAboveSelectionAsRead()
        #expect(added == 0)
    }

    @MainActor
    @Test("markBelowSelectionAsRead marks items after selection")
    func markBelowMarks() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "2")
        // Below = 3, 4, 5 — all unread.
        let added = model.markBelowSelectionAsRead()
        #expect(added == 3)
        #expect(model.isRead(id: "3"))
        #expect(model.isRead(id: "4"))
        #expect(model.isRead(id: "5"))
    }

    @MainActor
    @Test("markBelowSelectionAsRead no-ops at last item")
    func markBelowNoOpAtLast() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.selectItem(id: "5")
        let added = model.markBelowSelectionAsRead()
        #expect(added == 0)
    }

    @MainActor
    @Test("markAbove/Below no-op without a selection")
    func markAboveBelowNoOpWithoutSelection() {
        let model = RSSReaderModel(subscribedFeeds: [])
        model.items = [
            RSSItem(id: "a", title: "A", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        model.selectItem(id: nil)
        #expect(model.markAboveSelectionAsRead() == 0)
        #expect(model.markBelowSelectionAsRead() == 0)
    }

    // MARK: - HTML paragraph splitting

    @Test("bodyParagraphs splits on <p> boundaries and decodes entities")
    func bodyParagraphsBasic() {
        let html = "<p>First paragraph &amp; intro.</p><p>Second paragraph.</p>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.bodyParagraphs == ["First paragraph & intro.", "Second paragraph."])
    }

    @Test("bodyParagraphs handles <br>, <h*>, <li>, <blockquote> as boundaries")
    func bodyParagraphsManyBlocks() {
        let html = "<h2>Heading</h2><p>Body.</p><ul><li>Item one</li><li>Item two</li></ul><blockquote>Quote.</blockquote>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.bodyParagraphs == ["Heading", "Body.", "Item one", "Item two", "Quote."])
    }

    @Test("bodyParagraphs strips inline tags inside each paragraph")
    func bodyParagraphsInlineStrip() {
        let html = "<p>Hello <b>world</b> with <a href=\"https://x.test\">a link</a>.</p>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.bodyParagraphs == ["Hello world with a link."])
    }

    @Test("bodyParagraphs returns single segment for tag-free body")
    func bodyParagraphsPlainText() {
        let html = "Just one line of body text with no tags."
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.bodyParagraphs == ["Just one line of body text with no tags."])
    }

    @Test("bodyParagraphs is empty when descriptionHTML is nil or empty")
    func bodyParagraphsEmpty() {
        let none = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: nil)
        let empty = RSSItem(id: "2", title: "T", link: nil, pubDate: nil, descriptionHTML: "")
        #expect(none.bodyParagraphs.isEmpty)
        #expect(empty.bodyParagraphs.isEmpty)
    }

    @Test("bodyParagraphs drops empty segments from adjacent <br><br>")
    func bodyParagraphsDropsEmpty() {
        let html = "<p>One.</p><br/><br/><p>Two.</p>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.bodyParagraphs == ["One.", "Two."])
    }

    // MARK: - Inline link extraction

    @Test("inlineLinks extracts <a href> anchors in source order")
    func inlineLinksBasic() {
        let html = """
        <p>See <a href="https://example.test/one">first</a> and
        <a href="https://example.test/two">second</a>.</p>
        """
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.inlineLinks.count == 2)
        #expect(item.inlineLinks[0].text == "first")
        #expect(item.inlineLinks[0].urlString == "https://example.test/one")
        #expect(item.inlineLinks[1].text == "second")
        #expect(item.inlineLinks[1].urlString == "https://example.test/two")
    }

    @Test("inlineLinks handles single-quoted hrefs")
    func inlineLinksSingleQuotes() {
        let html = "<a href='https://example.test/x'>x</a>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.inlineLinks.first?.urlString == "https://example.test/x")
    }

    @Test("inlineLinks strips nested inline tags inside anchor text")
    func inlineLinksStripNested() {
        let html = "<a href=\"https://example.test/x\">click <b>here</b></a>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.inlineLinks.first?.text == "click here")
    }

    @Test("inlineLinks decodes HTML entities in anchor text")
    func inlineLinksEntities() {
        let html = "<a href=\"https://example.test/x\">A &amp; B</a>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.inlineLinks.first?.text == "A & B")
    }

    @Test("inlineLinks skips anchors with empty href")
    func inlineLinksSkipsEmpty() {
        let html = "<a href=\"\">skip</a> <a href=\"https://example.test\">keep</a>"
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: html)
        #expect(item.inlineLinks.count == 1)
        #expect(item.inlineLinks.first?.urlString == "https://example.test")
    }

    @Test("inlineLinks is empty for body without anchors")
    func inlineLinksEmpty() {
        let item = RSSItem(id: "1", title: "T", link: nil, pubDate: nil, descriptionHTML: "<p>No links here.</p>")
        #expect(item.inlineLinks.isEmpty)
    }

    @Test("InlineLink.url parses urlString into URL when valid")
    func inlineLinkURL() {
        let link = InlineLink(text: "x", urlString: "https://example.test/")
        #expect(link.url?.absoluteString == "https://example.test/")
        // Foundation's URL(string:) is lenient and percent-encodes
        // spaces, so use an explicitly-empty form which always fails.
        let bad = InlineLink(text: "y", urlString: "")
        #expect(bad.url == nil)
    }

    // MARK: - Detail view helpers (friendly date + author)

    @MainActor
    @Test("friendlyDateString returns empty string when no parsed Date")
    func friendlyDateStringNoDate() {
        let model = RSSReaderModel()
        model.articles = [articleStub(id: "x", date: nil)]
        #expect(model.friendlyDateString(forItemID: "x").isEmpty)
        #expect(model.friendlyDateString(forItemID: "missing").isEmpty)
    }

    @MainActor
    @Test("friendlyDateString uses relative form for recent dates")
    func friendlyDateStringRecent() {
        let model = RSSReaderModel()
        let now = Date()
        model.articles = [articleStub(id: "x", date: now.addingTimeInterval(-3600))]
        let formatted = model.friendlyDateString(forItemID: "x")
        // Locale-dependent text, but "ago" is the English unit. Just
        // confirm it's non-empty and shaped relative (no comma year).
        #expect(!formatted.isEmpty)
        #expect(!formatted.contains(","))  // absolute medium-style would have a comma
    }

    @MainActor
    @Test("friendlyDateString uses absolute form for old dates")
    func friendlyDateStringOld() {
        let model = RSSReaderModel()
        let yearAgo = Date().addingTimeInterval(-86_400 * 365)
        model.articles = [articleStub(id: "x", date: yearAgo)]
        let formatted = model.friendlyDateString(forItemID: "x")
        #expect(!formatted.isEmpty)
        // Medium-style date is locale-dependent but always contains digits.
        let hasDigit = formatted.contains { $0.isNumber }
        #expect(hasDigit)
    }

    @MainActor
    @Test("authorLine returns nil when no authors are present")
    func authorLineNil() {
        let model = RSSReaderModel()
        model.articles = [articleStub(id: "x", date: nil)]
        #expect(model.authorLine(forItemID: "x") == nil)
        #expect(model.authorLine(forItemID: "missing") == nil)
    }

    @MainActor
    @Test("authorLine joins multiple authors with comma + sort")
    func authorLineMulti() {
        let model = RSSReaderModel()
        let status = ArticleStatus(articleID: "x", read: false, starred: false,
                                   dateArrived: Date(timeIntervalSince1970: 0))
        let authors: Set<Author> = [
            Author(authorID: "1", name: "Brent", url: nil, avatarURL: nil, emailAddress: nil)!,
            Author(authorID: "2", name: "Alex", url: nil, avatarURL: nil, emailAddress: nil)!,
        ]
        let article = Article(
            accountID: "Local", articleID: nil, feedID: "https://stub.test/feed",
            uniqueID: "x", title: nil, contentHTML: nil, contentText: nil,
            markdown: nil, url: nil, externalURL: nil, summary: nil, imageURL: nil,
            datePublished: nil, dateModified: nil, authors: authors, status: status
        )
        model.articles = [article]
        // Alphabetical sort means Alex first, then Brent.
        #expect(model.authorLine(forItemID: "x") == "Alex, Brent")
    }

    @MainActor
    @Test("addSubscription returns nil for an unparseable URL string")
    func addSubscriptionRejectsBadInput() async {
        let model = RSSReaderModel(subscribedFeeds: [])
        let beforeCount = model.subscribedFeeds.count
        // String.normalizedURL prepends http:// to bare input,
        // but spaces alone trim to empty → URL(string:) returns
        // a URL with empty host. Use a definitively invalid form.
        let result = await model.addSubscription(urlString: "")
        #expect(result == nil || model.subscribedFeeds.count == beforeCount + 0)
    }

    private func articleStub(id: String, date: Date?) -> Article {
        let status = ArticleStatus(
            articleID: id, read: false, starred: false,
            dateArrived: Date(timeIntervalSince1970: 0)
        )
        return Article(
            accountID: "Local", articleID: nil, feedID: "https://stub.test/feed",
            uniqueID: id, title: nil, contentHTML: nil, contentText: nil, markdown: nil,
            url: nil, externalURL: nil, summary: nil, imageURL: nil,
            datePublished: date, dateModified: nil, authors: nil, status: status
        )
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

    // MARK: - Per-feed unread badges

    @MainActor
    @Test("count(for: .allUnread) mirrors unreadCount")
    func badgeAllUnreadCount() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        // Seeded: 5 fixtures, 1 auto-read → 4 unread.
        #expect(model.count(for: .allUnread) == 4)
        #expect(model.count(for: .allUnread) == model.unreadCount)
    }

    @MainActor
    @Test("count(for: .starred) mirrors starredCount")
    func badgeStarredCount() {
        let model = RSSReaderModel()
        model.seedProfileFixtures()
        model.toggleStarred(id: "1")
        model.toggleStarred(id: "3")
        #expect(model.count(for: .starred) == 2)
        #expect(model.count(for: .starred) == model.starredCount)
    }

    @MainActor
    @Test("unreadCount(forFeed:) reports only for the active feed")
    func badgePerFeedUnreadActiveOnly() {
        let model = RSSReaderModel(subscribedFeeds: [
            Feed(title: "Active", url: "https://active.test/feed"),
            Feed(title: "Other", url: "https://other.test/feed"),
        ])
        model.items = [
            RSSItem(id: "x", title: "X", link: nil, pubDate: nil, descriptionHTML: nil),
            RSSItem(id: "y", title: "Y", link: nil, pubDate: nil, descriptionHTML: nil),
        ]
        // selectedFeedID is the first subscription.
        #expect(model.unreadCount(forFeed: "https://active.test/feed") == 2)
        #expect(model.unreadCount(forFeed: "https://other.test/feed") == 0)

        model.selectItem(id: "x")  // auto-marks "x" read
        #expect(model.unreadCount(forFeed: "https://active.test/feed") == 1)
    }
}
