import Foundation
import Testing
@testable import NetNewsWireSharedCore

@Suite("Upstream NetNewsWire Shared core slice")
struct NetNewsWireSharedCoreTests {
    @Test("Refresh intervals preserve upstream raw values and seconds")
    func refreshIntervals() {
        #expect(RefreshInterval.manually.rawValue == 1)
        #expect(RefreshInterval.every30Minutes.inSeconds() == 30 * 60)
        #expect(RefreshInterval.every8Hours.inSeconds() == 8 * 60 * 60)
        #expect(RefreshInterval.everyHour.id == RefreshInterval.everyHour.description())
    }

    @Test("Article text sizes map to stable CSS classes")
    func articleTextSizeCSSClasses() {
        #expect(ArticleTextSize.small.cssClass == "smallText")
        #expect(ArticleTextSize.medium.cssClass == "mediumText")
        #expect(ArticleTextSize.xlarge.cssClass == "xLargeText")
        #expect(ArticleTextSize.xxlarge.id == ArticleTextSize.xxlarge.description())
    }

    @Test("Article specifiers round-trip through plist dictionaries")
    func articleSpecifierDictionaryRoundTrip() {
        let specifier = ArticleSpecifier(accountID: "local", articleID: "article-1")
        #expect(specifier.dictionary == ["accountID": "local", "articleID": "article-1"])
        #expect(ArticleSpecifier(dictionary: specifier.dictionary) == specifier)
        #expect(ArticleSpecifier(dictionary: ["accountID": "local"]) == nil)
    }

    @Test("Widget deep links encode article IDs")
    func widgetDeepLinks() {
        #expect(WidgetDeepLink.unread.url.absoluteString == "nnw://showunread")
        #expect(WidgetDeepLink.today.url.absoluteString == "nnw://showtoday")
        #expect(WidgetDeepLink.starred.url.absoluteString == "nnw://showstarred")
        #expect(WidgetDeepLink.unreadArticle(id: "a b").url.absoluteString == "nnw://showunread?id=a%20b")
        #expect(WidgetDeepLink.starredArticle(id: "x/y").url.absoluteString == "nnw://showstarred?id=x/y")
    }

    @Test("Widget data remains Codable")
    func widgetDataCodableRoundTrip() throws {
        let article = LatestArticle(
            id: "1",
            feedTitle: "Feed",
            articleTitle: "Title",
            articleSummary: "Summary",
            feedIconPath: nil,
            pubDate: "2026-06-09"
        )
        let data = WidgetData(
            totalUnreadCount: 1,
            totalTodayCount: 2,
            totalTodayUnreadCount: 1,
            totalStarredCount: 3,
            unreadArticles: [article],
            starredArticles: [],
            todayArticles: [article],
            lastUpdateTime: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(WidgetData.self, from: encoded)
        #expect(decoded.totalUnreadCount == 1)
        #expect(decoded.unreadArticles == [article])
        #expect(decoded.todayArticles == [article])
        #expect(decoded.lastUpdateTime == data.lastUpdateTime)
    }

    @Test("Extractor and article-theme plists decode upstream keys")
    func codableSharedModelsDecode() throws {
        let extracted = try JSONDecoder().decode(ExtractedArticle.self, from: Data("""
        {
          "title": "T",
          "date_published": "2026-06-09",
          "lead_image_url": "https://example.test/image.png",
          "word_count": 42,
          "total_pages": 2,
          "rendered_pages": 1
        }
        """.utf8))
        #expect(extracted.title == "T")
        #expect(extracted.datePublished == "2026-06-09")
        #expect(extracted.leadImageURL == "https://example.test/image.png")
        #expect(extracted.wordCount == 42)
        #expect(extracted.totalPages == 2)
        #expect(extracted.renderedPages == 1)

        let plist = try PropertyListDecoder().decode(ArticleThemePlist.self, from: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Name</key><string>Theme</string>
            <key>ThemeIdentifier</key><string>com.example.theme</string>
            <key>CreatorHomePage</key><string>https://example.test</string>
            <key>CreatorName</key><string>Example</string>
            <key>Version</key><integer>7</integer>
        </dict>
        </plist>
        """.utf8))
        #expect(plist.name == "Theme")
        #expect(plist.themeIdentifier == "com.example.theme")
        #expect(plist.version == 7)
    }

    @Test("Small shared constants retain their upstream strings")
    func constants() {
        #expect(ActivityType.nextUnread.rawValue == "NextUnread")
        #expect(UserInfoKey.feed == "feed")
        #expect(UserInfoKey.readArticlesFilterStateKeys == "readArticlesFilterStateKey")
        #expect(HelpURL.githubRepo.rawValue == "https://github.com/Ranchero-Software/NetNewsWire")
        #expect(Notification.Name.InspectableObjectsDidChange.rawValue == "TimelineSelectionDidChangeNotification")
        #expect(Notification.Name.UserDidAddFeed.rawValue == "UserDidAddFeedNotification")
        #expect(Notification.Name.WebInspectorEnabledDidChange.rawValue == "WebInspectorEnabledDidChange")
    }

    @Test("Verge mojibake filter is scoped to The Verge")
    func articleRenderingSpecialCases() {
        let html = "A â€™ quote &amp;hellip;"
        #expect(ArticleRenderingSpecialCases.isVergeSpecialCase(URL(string: "https://www.theverge.com/story")!))
        #expect(!ArticleRenderingSpecialCases.isVergeSpecialCase(URL(string: "https://example.test/story")!))
        #expect(ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: "https://example.test", html: html) == html)
        #expect(ArticleRenderingSpecialCases.filterHTMLIfNeeded(baseURL: "https://www.theverge.com", html: html) == "A ’ quote…")
    }
}
