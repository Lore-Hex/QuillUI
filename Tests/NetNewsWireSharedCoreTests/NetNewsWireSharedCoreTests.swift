import Foundation
import Articles
import Images
import Testing
@testable import Account
@testable import NetNewsWireSharedCore
@testable import RSCore

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

    @Test("Share extension feed add requests preserve destination containers")
    func extensionFeedAddRequestCodableRoundTrip() throws {
        let request = try JSONDecoder().decode(ExtensionFeedAddRequest.self, from: Data("""
        {
          "name": "Example",
          "feedURL": "https://example.test/feed.xml",
          "destinationContainerID": {
            "type": "folder",
            "accountID": "local",
            "folderName": "Swift"
          }
        }
        """.utf8))

        #expect(request.name == "Example")
        #expect(request.feedURL.absoluteString == "https://example.test/feed.xml")
        #expect(request.destinationContainerID == .folder("local", "Swift"))

        let roundTrip = try JSONDecoder().decode(ExtensionFeedAddRequest.self, from: JSONEncoder().encode(request))
        #expect(roundTrip.name == request.name)
        #expect(roundTrip.feedURL == request.feedURL)
        #expect(roundTrip.destinationContainerID == request.destinationContainerID)
    }

    @Test("Share extension containers flatten accounts and folders")
    func extensionContainersCodableAndLookup() throws {
        let containers = try JSONDecoder().decode(ExtensionContainers.self, from: Data("""
        {
          "accounts": [
            {
              "name": "Local",
              "accountID": "local",
              "type": 1,
              "disallowFeedInRootFolder": true,
              "containerID": {
                "type": "account",
                "accountID": "local"
              },
              "folders": [
                {
                  "accountName": "Local",
                  "accountID": "local",
                  "name": "Swift",
                  "containerID": {
                    "type": "folder",
                    "accountID": "local",
                    "folderName": "Swift"
                  }
                }
              ]
            }
          ]
        }
        """.utf8))

        let account = try #require(containers.findAccount(forName: "Local"))
        #expect(account.accountID == "local")
        #expect(account.type == .onMyMac)
        #expect(account.disallowFeedInRootFolder)
        #expect(account.containerID == .account("local"))

        let folder = try #require(account.findFolder(forName: "Swift"))
        #expect(folder.accountName == "Local")
        #expect(folder.containerID == .folder("local", "Swift"))

        #expect(containers.flattened.map(\.name) == ["Local", "Swift"])
        #expect(containers.findAccount(forName: "Missing") == nil)
        #expect(account.findFolder(forName: "Missing") == nil)

        let decodedAgain = try JSONDecoder().decode(ExtensionContainers.self, from: JSONEncoder().encode(containers))
        #expect(decodedAgain.flattened.map(\.name) == ["Local", "Swift"])
    }

    @Test("OPML exporter compiles and XML escaping preserves upstream behavior")
    func opmlExporterCompileSliceAndEscaping() {
        _ = OPMLExporter.self

        let raw = #"<outline text="Swift & News's" xmlUrl="https://example.test/feed?x=1&y=2"/>"#
        let escaped = #"&lt;outline text=&quot;Swift &amp; News's&quot; xmlUrl=&quot;https://example.test/feed?x=1&amp;y=2&quot;/&gt;"#
        #expect(raw.escapingSpecialXMLCharacters == escaped)
    }

    @Test("Assets expose upstream icon image wrappers")
    @MainActor func assetsExposeIconImageWrappers() {
        let starredFeed = Assets.Images.starredFeed
        let unreadFeed = Assets.Images.unreadFeed
        let mainFolder = Assets.Images.mainFolder

        #expect(starredFeed.isSymbol)
        #expect(starredFeed.isBackgroundSuppressed)
        #expect(starredFeed.preferredColor != nil)
        #expect(unreadFeed.isSymbol)
        #expect(mainFolder.isSymbol)
        #expect(Assets.Colors.primaryAccent.cgColor.components?.count == 4)
    }

    @Test("Images shim exposes upstream favicon API shape")
    @MainActor func imagesShimExposesFaviconAPIShape() {
        _ = SmallIconProvider.self
        #expect(IconSize.small.size == CGSize(width: 24, height: 24))
        #expect(IconSize.medium.size == CGSize(width: 36, height: 36))
        #expect(IconSize.large.size == CGSize(width: 48, height: 48))

        let downloader = FaviconDownloader()
        let icon = IconImage(RSImage())
        downloader.cache(icon, forFaviconURL: "https://example.test/favicon.ico")

        #expect(downloader.favicon(with: "https://example.test/favicon.ico", homePageURL: nil) === icon)
        #expect(downloader.favicon(with: "ftp://example.test/favicon.ico", homePageURL: nil) == nil)
        downloader.emptyCache()
        #expect(downloader.favicon(with: "https://example.test/favicon.ico", homePageURL: nil) == nil)
    }

    @Test("Mark status command filters articles before mutation")
    @MainActor func markStatusCommandFiltersArticlesBeforeMutation() throws {
        let unread = makeArticle(uniqueID: "unread", title: "Unread", read: false)
        let alreadyRead = makeArticle(uniqueID: "read", title: "Read", read: true)
        let starred = makeArticle(uniqueID: "starred", title: "Starred", starred: true)
        let undoManager = UndoManager()

        #expect(MarkStatusCommand(initialArticles: [], markingRead: true, undoManager: undoManager) == nil)
        #expect(MarkStatusCommand(initialArticles: [alreadyRead], markingRead: true, undoManager: undoManager) == nil)

        let markRead = try #require(MarkStatusCommand(initialArticles: [unread, alreadyRead], markingRead: true, undoManager: undoManager))
        #expect(markRead.undoActionName == "Mark Read")
        #expect(markRead.redoActionName == "Mark Read")
        #expect(markRead.articles == [unread])

        let unstar = try #require(MarkStatusCommand(initialArticles: [unread, starred], markingStarred: false, undoManager: undoManager))
        #expect(unstar.undoActionName == "Mark Unstarred")
        #expect(unstar.articles == [starred])
    }

    @Test("Account type helpers compile through SwiftUI and UIKit shadows")
    @MainActor func accountTypeHelpers() {
        #expect(AccountType.feedbin.localizedAccountName() == "Feedbin")
        #expect(AccountType.newsBlur.localizedAccountName() == "NewsBlur")

        _ = AccountType.onMyMac.image()
        _ = AccountType.newsBlur.image()
        _ = AccountType.feedly.logColor
    }

    @Test("CloudKit account helper degrades without iCloud on Linux")
    @MainActor func cloudKitAccountHelper() {
        let error = AddCloudKitAccountError.iCloudDriveMissing

        #expect(error.errorDescription?.contains("Add iCloud Account") == true)
        #expect(error.recoverySuggestion?.contains("Settings") == true)
        #expect(error.recoveryOptions.count == 2)
        #expect(!error.attemptRecovery(optionIndex: 1))
        #expect(!AddCloudKitAccountUtilities.isiCloudDriveEnabled)
    }

    @Test("Account stats totals aggregate row counts")
    func accountStatsTotals() {
        let rows = [
            AccountStatsRowData(
                accountID: "a",
                name: "A",
                typeName: "On My Mac",
                isActive: true,
                feedCount: 1,
                folderCount: 2,
                articleCount: 3,
                statusesCount: 4,
                unreadCount: 5,
                starredCount: 6,
                databaseSizeBytes: 7
            ),
            AccountStatsRowData(
                accountID: "b",
                name: "B",
                typeName: "Feedbin",
                isActive: false,
                feedCount: 10,
                folderCount: 20,
                articleCount: 30,
                statusesCount: 40,
                unreadCount: 50,
                starredCount: 60,
                databaseSizeBytes: 70
            ),
        ]

        let totals = AccountStatsTotals(rows: rows)
        #expect(totals.feedCount == 11)
        #expect(totals.folderCount == 22)
        #expect(totals.articleCount == 33)
        #expect(totals.statusesCount == 44)
        #expect(totals.unreadCount == 55)
        #expect(totals.starredCount == 66)
        #expect(totals.databaseSizeBytes == 77)
    }

    @Test("Article theme notifications retain upstream names")
    func articleThemeNotifications() {
        #expect(Notification.Name.didBeginDownloadingTheme.rawValue == "didBeginDownloadingTheme")
        #expect(Notification.Name.didEndDownloadingTheme.rawValue == "didEndDownloadingTheme")
        #expect(Notification.Name.didFailToImportThemeWithError.rawValue == "didFailToImportThemeWithError")
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

    @Test("Mark command validation handles empty, markable, and unmarkable selections")
    func markCommandValidation() {
        let unread = makeArticle(uniqueID: "unread", title: "Unread", read: false)
        let read = makeArticle(uniqueID: "read", title: "Read", read: true)
        let hasUnreadArticles: (ArticleArray) -> Bool = { articles in
            articles.contains { !$0.status.read }
        }

        #expect(MarkCommandValidationStatus.statusFor([], hasUnreadArticles) == .canDoNothing)
        #expect(MarkCommandValidationStatus.statusFor([unread], hasUnreadArticles) == .canMark)
        #expect(MarkCommandValidationStatus.statusFor([read], hasUnreadArticles) == .canUnmark)
    }

    @Test("Article string formatter sanitizes titles and summaries")
    @MainActor func articleStringFormatter() {
        let article = makeArticle(
            uniqueID: "formatter",
            title: "<b>Hello</b>\nTom &amp; friends",
            body: "<p>First&nbsp;line</p><script>ignore()</script><p>Second &amp; third</p>"
        )

        #expect(ArticleStringFormatter.sanitizedTitle("<b>Hello</b>", forHTML: true) == "<b>Hello</b>")
        #expect(ArticleStringFormatter.sanitizedTitle("<script>bad()</script>", forHTML: true) == "&lt;script&gt;bad()&lt;/script&gt;")
        #expect(ArticleStringFormatter.shared.truncatedTitle(article) == "Hello Tom & friends")
        #expect(ArticleStringFormatter.shared.truncatedSummary(article) == "First\u{00a0}line Second & third")
        #expect(ArticleStringFormatter.shared.attributedTruncatedTitle(article).string == "Hello Tom & friends")
    }

    @Test("Article string formatter switches today dates to time-only output")
    @MainActor func articleStringFormatterDates() {
        let formatter = ArticleStringFormatter.shared
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        #expect(formatter.dateString(today).contains(":"))
        #expect(!formatter.dateString(yesterday).isEmpty)
    }

    private func makeArticle(
        uniqueID: String,
        title: String?,
        read: Bool = false,
        starred: Bool = false,
        body: String? = nil
    ) -> Article {
        Article(
            accountID: "account",
            articleID: "article-\(uniqueID)",
            feedID: "feed",
            uniqueID: uniqueID,
            title: title,
            contentHTML: body,
            contentText: nil,
            markdown: nil,
            url: nil,
            externalURL: nil,
            summary: nil,
            imageURL: nil,
            datePublished: nil,
            dateModified: nil,
            authors: nil,
            status: ArticleStatus(articleID: "article-\(uniqueID)", read: read, starred: starred, dateArrived: Date(timeIntervalSince1970: 0))
        )
    }
}
