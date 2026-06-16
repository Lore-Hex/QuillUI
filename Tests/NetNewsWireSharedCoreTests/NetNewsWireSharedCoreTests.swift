import Foundation
import AppKit
import ActivityLog
import Articles
import Images
import NetNewsWireContext
import Testing
import UserNotifications
@testable import Account
@testable import NetNewsWireSharedCore
@testable import RSCore
@testable import RSTree

@Suite("Upstream NetNewsWire Shared core slice", .serialized)
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

    @Test("Share default container follows saved AppDefaults")
    @MainActor func shareDefaultContainerUsesSavedDefaults() throws {
        let containers = try JSONDecoder().decode(ExtensionContainers.self, from: Data("""
        {
          "accounts": [
            {
              "name": "Local",
              "accountID": "local",
              "type": 1,
              "disallowFeedInRootFolder": true,
              "containerID": { "type": "account", "accountID": "local" },
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
            },
            {
              "name": "Other",
              "accountID": "other",
              "type": 1,
              "disallowFeedInRootFolder": false,
              "containerID": { "type": "account", "accountID": "other" },
              "folders": []
            }
          ]
        }
        """.utf8))
        let defaults = AppDefaults.shared

        defaults.addFeedAccountID = nil
        defaults.addFeedFolderName = nil
        let firstDefault = try #require(ShareDefaultContainer.defaultContainer(containers: containers))
        #expect(firstDefault.name == "Swift")
        #expect(firstDefault.containerID == .folder("local", "Swift"))

        defaults.addFeedAccountID = "other"
        defaults.addFeedFolderName = nil
        let savedAccount = try #require(ShareDefaultContainer.defaultContainer(containers: containers))
        #expect(savedAccount.name == "Other")
        #expect(savedAccount.containerID == .account("other"))

        let folder = try #require(containers.accounts.first?.folders.first)
        ShareDefaultContainer.saveDefaultContainer(folder)
        #expect(defaults.addFeedAccountID == "local")
        #expect(defaults.addFeedFolderName == "Swift")
    }

    @Test("Share extension files read and append app-group property lists")
    @MainActor func shareExtensionFilesRoundTripThroughAppGroupContainer() throws {
        let fileManager = FileManager.default
        let appGroupURL = try #require(
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ranchero.NetNewsWire")
        )
        let containersURL = appGroupURL.appendingPathComponent("extension_containers.plist")
        let feedRequestsURL = appGroupURL.appendingPathComponent("extension_feed_add_request.plist")
        try? fileManager.removeItem(at: containersURL)
        try? fileManager.removeItem(at: feedRequestsURL)
        defer {
            try? fileManager.removeItem(at: containersURL)
            try? fileManager.removeItem(at: feedRequestsURL)
        }

        let containers = try JSONDecoder().decode(ExtensionContainers.self, from: Data("""
        {
          "accounts": [
            {
              "name": "Local",
              "accountID": "local",
              "type": 1,
              "disallowFeedInRootFolder": false,
              "containerID": { "type": "account", "accountID": "local" },
              "folders": []
            }
          ]
        }
        """.utf8))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(containers).write(to: containersURL)

        let readContainers = try #require(ExtensionContainersFile.read())
        #expect(readContainers.accounts.map(\.accountID) == ["local"])

        let first = ExtensionFeedAddRequest(
            name: "One",
            feedURL: URL(string: "https://example.test/one.xml")!,
            destinationContainerID: .account("local")
        )
        let second = ExtensionFeedAddRequest(
            name: "Two",
            feedURL: URL(string: "https://example.test/two.xml")!,
            destinationContainerID: .account("local")
        )

        ExtensionFeedAddRequestFile.save(first)
        ExtensionFeedAddRequestFile.save(second)

        let saved = try PropertyListDecoder().decode(
            [ExtensionFeedAddRequest].self,
            from: Data(contentsOf: feedRequestsURL)
        )
        #expect(saved.map(\.name) == ["One", "Two"])
        #expect(saved.map(\.feedURL.absoluteString) == [
            "https://example.test/one.xml",
            "https://example.test/two.xml",
        ])
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

    @Test("Icon image cache resolves author downloader images and low-memory cleanup")
    @MainActor func iconImageCacheResolvesAuthorImagesAndLowMemoryCleanup() async throws {
        let cache = IconImageCache()
        AuthorAvatarDownloader.shared.emptyCache()
        defer {
            AuthorAvatarDownloader.shared.emptyCache()
        }

        let author = try #require(Author(
            authorID: nil,
            name: "Reporter",
            url: nil,
            avatarURL: "https://example.test/avatar.png",
            emailAddress: nil
        ))
        let authorIcon = IconImage(RSImage())
        let article = makeArticle(uniqueID: "author", title: "Byline", authors: [author])

        AuthorAvatarDownloader.shared.cache(authorIcon, for: author)
        #expect(cache.imageForArticle(article) === authorIcon)

        AuthorAvatarDownloader.shared.emptyCache()
        #expect(cache.imageForArticle(article) === authorIcon)

        NotificationCenter.default.post(name: .lowMemory, object: nil)
        await Task.yield()

        let replacementIcon = IconImage(RSImage())
        AuthorAvatarDownloader.shared.cache(replacementIcon, for: author)
        #expect(cache.imageForArticle(article) === replacementIcon)
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

    @Test("Smart feeds expose upstream identity and icons")
    @MainActor func smartFeedsExposeUpstreamIdentityAndIcons() throws {
        appDelegate = AppDelegate()
        appDelegate.unreadCount = 5

        let controller = SmartFeedsController.shared
        #expect(controller.containerID == .smartFeedController)
        #expect(controller.nameForDisplay == "Smart Feeds")
        #expect(controller.smartFeeds.count == 3)

        let todayID = SidebarItemIdentifier.smartFeed(String(describing: TodayFeedDelegate.self))
        let unreadID = SidebarItemIdentifier.smartFeed(String(describing: UnreadFeed.self))
        let starredID = SidebarItemIdentifier.smartFeed(String(describing: StarredFeedDelegate.self))

        let today = try #require(controller.find(by: todayID) as? SmartFeed)
        let unread = try #require(controller.find(by: unreadID) as? UnreadFeed)
        let starred = try #require(controller.find(by: starredID) as? SmartFeed)

        #expect(today.nameForDisplay == "Today")
        #expect(today.sidebarItemID == todayID)
        #expect(today.defaultReadFilterType == .none)
        #expect(today.smallIcon?.isSymbol == true)

        #expect(unread.nameForDisplay == "All Unread")
        #expect(unread.sidebarItemID == unreadID)
        #expect(unread.defaultReadFilterType == .alwaysRead)
        #expect(unread.unreadCount == 5)
        #expect(unread.smallIcon?.isSymbol == true)

        #expect(starred.nameForDisplay == "Starred")
        #expect(starred.sidebarItemID == starredID)
        #expect(starred.defaultReadFilterType == .none)
        #expect(starred.smallIcon?.isSymbol == true)
        #expect(controller.find(by: .feed("local", "feed")) == nil)
    }

    @Test("Smart feed pasteboard writer exposes display name")
    @MainActor func smartFeedPasteboardWriter() throws {
        let smartFeed = SmartFeed(delegate: SearchFeedDelegate(searchString: "swift"))
        let writer = SmartFeedPasteboardWriter(smartFeed: smartFeed)
        let pasteboard = NSPasteboard(name: .init(rawValue: "nnw-smart-feed-\(UUID().uuidString)"))

        #expect(writer.writableTypes(for: pasteboard) == [.string])
        #expect(writer.pasteboardPropertyList(forType: .string) as? String == "Search: swift")
        #expect(writer.pasteboardPropertyList(forType: .fileURL) == nil)
    }

    @Test("Node sorting extensions preserve display ordering")
    @MainActor func nodeSortingExtensions() {
        let alpha = Node(representedObject: NamedDisplayObject("Alpha"), parent: nil)
        let beta = Node(representedObject: NamedDisplayObject("Beta"), parent: nil)
        let folder = Node(representedObject: NamedDisplayObject("Folder"), parent: nil)
        folder.canHaveChildNodes = true

        #expect([beta, alpha].sortedAlphabetically() == [alpha, beta])
        #expect([folder, alpha, beta].sortedAlphabeticallyWithFoldersAtEnd() == [alpha, beta, folder])
    }

    @Test("Cache cleaner initializes image cache flush date")
    @MainActor func cacheCleanerInitializesFlushDate() {
        let defaults = AppDefaults.shared
        defaults.lastImageCacheFlushDate = nil
        UserDefaults.standard.set(true, forKey: "didPurgeImageCachesForResizing-2026-03-30")

        CacheCleaner.purgeIfNecessary()

        #expect(defaults.lastImageCacheFlushDate != nil)
    }

    @Test("Unread smart feed follows Linux notification lowering")
    @MainActor func unreadSmartFeedFollowsLinuxNotificationLowering() async {
        let delegate = AppDelegate()
        appDelegate = delegate
        delegate.unreadCount = 7
        let unread = UnreadFeed()

        #expect(unread.unreadCount == 7)

        delegate.unreadCount = 11
        NotificationCenter.default.post(name: .UnreadCountDidChange, object: delegate)
        await Task.yield()

        #expect(unread.unreadCount == 11)
    }

    @Test("Search smart feed delegates retain search identity")
    @MainActor func searchSmartFeedDelegatesRetainSearchIdentity() {
        let search = SmartFeed(delegate: SearchFeedDelegate(searchString: "swift"))
        #expect(search.nameForDisplay == "Search: swift")
        #expect(search.sidebarItemID == .smartFeed(String(describing: SearchFeedDelegate.self)))
        #expect(search.smallIcon?.isSymbol == true)

        let timelineSearch = SmartFeed(delegate: SearchTimelineFeedDelegate(searchString: "gtk", articleIDs: ["a", "b"]))
        #expect(timelineSearch.nameForDisplay == "Search: gtk")
        #expect(timelineSearch.sidebarItemID == .smartFeed(String(describing: SearchTimelineFeedDelegate.self)))
        #expect(timelineSearch.smallIcon?.isSymbol == true)
    }

    @Test("Account type helpers compile through SwiftUI and UIKit shadows")
    @MainActor func accountTypeHelpers() {
        _ = AccountType.onMyMac.image()
        _ = AccountType.newsBlur.image()
        _ = AccountType.feedly.logColor
        _ = AccountType.feedbin.logColor
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

    @Test("Activity log view model formats timestamp owner detail and account color")
    @MainActor func activityLogViewModelSegments() throws {
        let activity = Activity(
            id: 42,
            owner: .account(accountID: "local", displayName: "Local"),
            kind: .refreshFeedContent(feedURL: "https://example.test/feed.xml"),
            detail: "Example Feed"
        )

        let segments = ActivityLogViewModel.segments(for: activity)
        let text = segments.map(\.text).joined()

        #expect(text.hasPrefix("["))
        #expect(text.contains("]"))
        #expect(text.contains("Local: "))
        #expect(text.contains("Refreshing feed: Example Feed"))
        #expect(text.contains("https://example.test/feed.xml"))
        #expect(segments.contains { segment in
            if case .account(let accountID) = segment.color {
                return accountID == "local"
            }
            return false
        })
    }

    @Test("Current activity view model exposes upstream display text and symbols")
    @MainActor func currentActivityViewModelDisplayTextAndSymbols() {
        let feed = Activity(
            id: 1,
            owner: .account(accountID: "local", displayName: "Local"),
            kind: .refreshFeedContent(feedURL: "https://example.test/feed.xml"),
            detail: "Example Feed"
        )
        let feedText = CurrentActivityViewModel.displayText(for: feed)
        #expect(feedText.title == "Example Feed")
        #expect(feedText.detail == "https://example.test/feed.xml")

        let finder = Activity(id: 2, owner: .feedFinder, kind: .findFeed(urlString: "https://example.test"))
        let finderText = CurrentActivityViewModel.displayText(for: finder)
        #expect(finderText.title == "Finding feed")
        #expect(finderText.detail == "https://example.test")

        #expect(CurrentActivityViewModel.symbolName(for: .pending) == "circle")
        #expect(CurrentActivityViewModel.symbolName(for: .running) == "circle.fill")
        #expect(CurrentActivityViewModel.symbolName(for: .completed) == "checkmark.circle.fill")
        #expect(CurrentActivityViewModel.symbolName(for: .failed) == "xmark.circle.fill")
        #expect(CurrentActivityViewModel.accessibilityLabel(for: .failed) == "Failed")
    }

    @Test("Account refresh timer schedules, suspends, resumes, and invalidates")
    @MainActor func accountRefreshTimerLifecycle() {
        let defaults = AppDefaults.shared
        defaults.refreshInterval = .every30Minutes

        let timer = AccountRefreshTimer()
        timer.update()
        timer.suspend()
        timer.resume()
        timer.invalidate()

        defaults.refreshInterval = .manually
        timer.update()
        timer.fireOldTimer()
        timer.invalidate()
    }

    @Test("Article status sync timer handles queue notification and lifecycle")
    @MainActor func articleStatusSyncTimerLifecycle() async {
        let timer = ArticleStatusSyncTimer.shared

        timer.start()
        timer.update()
        NotificationCenter.default.post(name: .AccountDidQueueArticleStatuses, object: nil)
        await Task.yield()
        timer.fireOldTimer()
        timer.stop()
    }

    @Test("User notification manager registers article actions through shim")
    @MainActor func userNotificationManagerRegistersArticleActions() async throws {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([])

        UserNotificationManager.shared.start()
        let categories = await center.notificationCategories()
        let category = try #require(categories.first { $0.identifier == "NEW_ARTICLE_NOTIFICATION_CATEGORY" })

        #expect(category.hiddenPreviewsBodyPlaceholder == "")
        #expect(category.actions.map(\.identifier) == [
            UserNotificationManager.ActionIdentifier.openArticle,
            UserNotificationManager.ActionIdentifier.markAsRead,
            UserNotificationManager.ActionIdentifier.markAsStarred,
        ])
    }

    private func makeArticle(
        uniqueID: String,
        title: String?,
        read: Bool = false,
        starred: Bool = false,
        body: String? = nil,
        authors: Set<Author>? = nil
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
            authors: authors,
            status: ArticleStatus(articleID: "article-\(uniqueID)", read: read, starred: starred, dateArrived: Date(timeIntervalSince1970: 0))
        )
    }
}

@MainActor private final class NamedDisplayObject: NSObject, DisplayNameProvider {
    let nameForDisplay: String

    init(_ nameForDisplay: String) {
        self.nameForDisplay = nameForDisplay
        super.init()
    }
}
