import Foundation
import AppKit
import ActivityLog
import Articles
import CoreSpotlight
import Images
import NetNewsWireContext
import Testing
import UserNotifications
import WebKit
import WidgetKit
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

    @Test("Widget data encoder reloads changed widget timelines through WidgetKit")
    @MainActor func widgetDataEncoderReloadTimelines() throws {
        let encoder = try #require(WidgetDataEncoder())
        let existing = WidgetData(
            totalUnreadCount: 1,
            totalTodayCount: 0,
            totalTodayUnreadCount: 0,
            totalStarredCount: 0,
            unreadArticles: [makeLatestArticle(id: "unread-old")],
            starredArticles: [],
            todayArticles: [],
            lastUpdateTime: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let updated = WidgetData(
            totalUnreadCount: 2,
            totalTodayCount: 1,
            totalTodayUnreadCount: 1,
            totalStarredCount: 1,
            unreadArticles: [makeLatestArticle(id: "unread-new")],
            starredArticles: [makeLatestArticle(id: "starred-new")],
            todayArticles: [makeLatestArticle(id: "today-new")],
            lastUpdateTime: Date(timeIntervalSince1970: 1_800_000_001)
        )

        WidgetCenter.shared.quillResetReloadTracking()
        encoder.reloadTimelines(newData: updated, existingData: existing)

        #expect(WidgetCenter.shared.quillReloadedTimelineKinds == [
            "com.ranchero.NetNewsWire.UnreadWidget",
            "com.ranchero.NetNewsWire.TodayWidget",
            "com.ranchero.NetNewsWire.StarredWidget",
            "com.ranchero.NetNewsWire.LockScreenSummaryWidget",
        ])

        WidgetCenter.shared.quillResetReloadTracking()
        encoder.reloadTimelines(newData: updated, existingData: updated)
        #expect(WidgetCenter.shared.quillReloadedTimelineKinds.isEmpty)
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

    @Test("Article extractor builds a signed Feedbin parser URL without starting network work")
    @MainActor func articleExtractorInitializesAndCancels() throws {
        let delegate = RecordingArticleExtractorDelegate()
        let extractor = try #require(ArticleExtractor("https://example.com/article", delegate: delegate))

        #expect(extractor.articleLink == "https://example.com/article")
        #expect(extractor.state == .ready)
        #expect(extractor.article == nil)

        extractor.cancel()

        #expect(extractor.state == .cancelled)
        #expect(delegate.completedArticles.isEmpty)
        #expect(delegate.errors.isEmpty)
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
        #if os(Linux)
        let appIconImage = RSImage.appIconImage
        #endif

        #expect(starredFeed.isSymbol)
        #expect(starredFeed.isBackgroundSuppressed)
        #expect(starredFeed.preferredColor != nil)
        #expect(unreadFeed.isSymbol)
        #expect(mainFolder.isSymbol)
        #if os(Linux)
        #expect(appIconImage?.data?.isEmpty == false)
        #expect(data(appIconImage, hasPNGSignature: true))
        #expect(IconImage.appIcon?.image.data?.isEmpty == false)
        #endif
        #expect(Assets.Colors.primaryAccent.cgColor.components?.count == 4)
        #expect(color(Assets.Colors.primaryAccent, equals: [0.031, 0.416, 0.933, 1]))
        #expect(color(Assets.Colors.star, equals: [0.976, 0.776, 0.204, 1]))
        #expect(color(Assets.Colors.timelineSeparator, equals: [0.9, 0.9, 0.9, 1]))
        #expect(color(Assets.Colors.sidebarUnreadCountBackground, equals: [0, 0, 0, 0.5]))
        #expect(color(Assets.Colors.sidebarUnreadCountText, equals: [1, 1, 1, 0.9]))
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

    @Test("Activity manager creates and invalidates Linux user activities")
    @MainActor func activityManagerCreatesAndInvalidatesLinuxActivities() throws {
        let manager = ActivityManager()
        let restoration = manager.stateRestorationActivity

        #expect(restoration.activityType == ActivityType.restoration.rawValue)
        #expect(restoration.persistentIdentifier?.isEmpty == false)
        #expect(restoration.isCurrent)
        #expect(!restoration.isInvalidated)
        #expect(Notification.Name.feedIconDidBecomeAvailable.rawValue == "FeedIconDidBecomeAvailable")

        manager.selectingNextUnread()
        let nextUnread = try #require(activity(named: "nextUnreadActivity", in: manager))
        #expect(nextUnread.activityType == ActivityType.nextUnread.rawValue)
        #expect(nextUnread.title == "See first unread article")
        #expect(nextUnread.isCurrent)

        manager.invalidateNextUnread()
        #expect(activity(named: "nextUnreadActivity", in: manager) == nil)
        #expect(!nextUnread.isCurrent)
        #expect(nextUnread.isInvalidated)
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

    @Test("Delete command validates sidebar model nodes")
    @MainActor func deleteCommandValidatesSidebarModelNodes() throws {
        try withFreshAccountManager { manager in
            let account = manager.defaultAccount
            let alpha = try #require(account.ensureFolder(with: "Alpha"))
            let beta = try #require(account.ensureFolder(with: "Beta"))
            let alphaNode = Node(representedObject: alpha, parent: nil)
            let betaNode = Node(representedObject: beta, parent: nil)
            let nonDeletableNode = Node(representedObject: NamedDisplayObject("Not Deletable"), parent: nil)
            let undoManager = UndoManager()

            #expect(!DeleteCommand.canDelete([]))
            #expect(!DeleteCommand.canDelete([nonDeletableNode]))
            #expect(DeleteCommand.canDelete([alphaNode]))
            #expect(DeleteCommand.canDelete([alphaNode, betaNode]))
            #expect(DeleteCommand(nodesToDelete: [nonDeletableNode], undoManager: undoManager) { _ in } == nil)

            let deleteFolder = try #require(DeleteCommand(nodesToDelete: [alphaNode], undoManager: undoManager) { _ in })
            #expect(deleteFolder.undoActionName == "Delete Folder")
            #expect(deleteFolder.redoActionName == "Delete Folder")

            let deleteFolders = try #require(DeleteCommand(nodesToDelete: [alphaNode, betaNode], undoManager: undoManager) { _ in })
            #expect(deleteFolders.undoActionName == "Delete Folders")
            #expect(deleteFolders.redoActionName == "Delete Folders")
        }
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

    @Test("Tree delegates build account, folder, and smart feed nodes")
    @MainActor func treeDelegatesBuildSidebarAndFolderTrees() throws {
        try withFreshAccountManager { manager in
            let account = manager.defaultAccount
            let beta = try #require(account.ensureFolder(with: "Beta"))
            let alpha = try #require(account.ensureFolder(with: "Alpha"))

            let folderDelegate = FolderTreeControllerDelegate()
            let folderTree = TreeController(delegate: folderDelegate)
            let folderAccountNodes = try #require(folderDelegate.treeController(treeController: folderTree, childNodesFor: folderTree.rootNode))
            let folderAccountNode = try #require(firstNode(in: folderAccountNodes, representing: account))
            let folderNodes = try #require(folderDelegate.treeController(treeController: folderTree, childNodesFor: folderAccountNode))

            #expect(folderAccountNodes.compactMap { $0.representedObject as? Account } == [account])
            #expect(folderAccountNode.canHaveChildNodes)
            #expect(folderNames(in: folderNodes) == ["Alpha", "Beta"])
            #expect(Set(folderNodes.compactMap { $0.representedObject as? Folder }) == [alpha, beta])

            let sidebarDelegate = SidebarTreeControllerDelegate()
            let sidebarTree = TreeController(delegate: sidebarDelegate)
            let sidebarRootNodes = try #require(sidebarDelegate.treeController(treeController: sidebarTree, childNodesFor: sidebarTree.rootNode))
            let smartFeedsNode = try #require(firstNode(in: sidebarRootNodes, representing: SmartFeedsController.shared))
            let smartFeedNodes = try #require(sidebarDelegate.treeController(treeController: sidebarTree, childNodesFor: smartFeedsNode))
            let sidebarAccountNode = try #require(firstNode(in: sidebarRootNodes, representing: account))
            let sidebarFolderNodes = try #require(sidebarDelegate.treeController(treeController: sidebarTree, childNodesFor: sidebarAccountNode))

            #expect(smartFeedsNode.representedObject === SmartFeedsController.shared)
            #expect(smartFeedsNode.isGroupItem)
            #expect(smartFeedNodes.count == SmartFeedsController.shared.smartFeeds.count)
            #expect(sidebarAccountNode.isGroupItem)
            #expect(folderNames(in: sidebarFolderNodes) == ["Alpha", "Beta"])
        }
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

    @Test("Simple HTML attributed strings decode entities and safe inline styles")
    @MainActor func simpleHTMLAttributedStringsDecodeEntitiesAndSafeStyles() throws {
        let attributed = NSAttributedString(simpleHTML: """
        Plain <strong>bold &amp; more</strong> <u>under</u> <s>strike</s>
        """)
        let text = attributed.string as NSString

        #expect(attributed.string == "Plain bold & more under strike")

        let boldRange = text.range(of: "bold")
        let underRange = text.range(of: "under")
        let strikeRange = text.range(of: "strike")
        let noEffectiveRange: NSRangePointer? = nil

        let boldFontValue = attributed.attribute(NSAttributedString.Key.font, at: boldRange.location, effectiveRange: noEffectiveRange) as? RSFont
        let boldFont = try #require(boldFontValue)

        #expect(boldFont.fontDescriptor.symbolicTraits.contains(NSFontDescriptor.SymbolicTraits.bold))
        #expect(attributed.attribute(NSAttributedString.Key.underlineStyle, at: underRange.location, effectiveRange: noEffectiveRange) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(attributed.attribute(NSAttributedString.Key.strikethroughStyle, at: strikeRange.location, effectiveRange: noEffectiveRange) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Article renderer loads default theme resources and substitutes desktop macros")
    @MainActor func articleRendererDefaultTheme() throws {
        AppDefaults.shared.articleTextSize = .large
        let author = try #require(Author(authorID: nil, name: "Alice", url: "https://author.example.com/", avatarURL: nil, emailAddress: nil))
        let article = makeArticle(
            uniqueID: "render",
            title: "Render Title",
            body: "<p>Hello renderer.</p>",
            authors: [author],
            url: "https://example.com/article",
            externalURL: "https://original.example.com/story"
        )
        let theme = ArticleTheme.defaultTheme
        let css = try #require(theme.css)
        let template = try #require(theme.template)

        #expect(theme.name == "Default")
        #expect(css.contains("articleBody"))
        #expect(template.contains("[[title]]"))

        let rendering = ArticleRenderer.articleHTML(article: article, theme: theme)
        #expect(rendering.style.contains("articleBody"))
        #expect(rendering.html.contains("Render Title"))
        #expect(rendering.html.contains("<p>Hello renderer.</p>"))
        #expect(rendering.html.contains("largeText"))
        #expect(rendering.html.contains("original.example.com/story"))
        #expect(rendering.html.contains(#"<a href="https://author.example.com/">Alice</a>"#))
        #expect(!rendering.html.contains("[["))
    }

    @Test("Shared resource helper locates bundled keyboard shortcut plists")
    func sharedResourceHelperFindsKeyboardShortcutPlists() throws {
        #expect(try shortcutEntries(named: "DetailKeyboardShortcuts").count == 1)
        #expect(try shortcutEntries(named: "TimelineKeyboardShortcuts").count == 4)
        #expect(try shortcutEntries(named: "SidebarKeyboardShortcuts").count == 12)

        let globalEntries = try shortcutEntries(named: "GlobalKeyboardShortcuts")
        #expect(globalEntries.count == 21)
        #expect(globalEntries.contains { entry in
            entry["action"] as? String == "nextUnread:" && entry["key"] as? String == "n"
        })
    }

    @Test("Default feeds importer loads bundled OPML into provided account")
    @MainActor func defaultFeedsImporterLoadsBundledOPMLIntoProvidedAccount() async throws {
        let account = try makeTemporaryLocalAccount(id: "default-feeds-\(UUID().uuidString)")

        #expect(account.flattenedFeeds().isEmpty)

        DefaultFeedsImporter.importDefaultFeeds(account: account)
        try await waitForMainActorCondition {
            account.flattenedFeeds().count >= 10
        }

        let feedNames = Set(account.flattenedFeeds().map(\.nameForDisplay))
        #expect(feedNames.contains("Daring Fireball"))
        #expect(feedNames.contains("NetNewsWire Blog"))
    }

    @Test("Web view configuration loads bundled scripts and content rules through WebKit shim")
    @MainActor func webViewConfigurationUsesBundledResources() async throws {
        AppDefaults.shared.isArticleContentJavascriptEnabled = false
        await WebViewConfiguration.compileContentBlockingRules()

        let handler = RecordingURLSchemeHandler()
        let configuration = WebViewConfiguration.configuration(with: handler)

        #expect(configuration.mediaTypesRequiringUserActionForPlayback == .all)
        #expect(configuration.preferences.minimumFontSize == 12)
        #expect(!configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(configuration.quillURLSchemeHandlers[ArticleRenderer.imageIconScheme] as? RecordingURLSchemeHandler === handler)

        let scripts = configuration.userContentController.quillUserScripts
        #expect(scripts.count == 2)
        #expect(scripts.allSatisfy { script in
            script.injectionTime == .atDocumentStart && script.isForMainFrameOnly && !script.source.isEmpty
        })
        #expect(configuration.userContentController.quillContentRuleLists.map(\.identifier) == ["ContentBlockingRules"])

        let webView = WKWebView(frame: .zero, configuration: configuration)
        WebViewConfiguration.addContentBlockingRules(to: webView)
        WebViewConfiguration.addContentBlockingRules(to: webView)

        #expect(webView.configuration.userContentController.quillContentRuleLists.count == 1)
    }

    @Test("Activity log view model formats timestamp owner detail and account color")
    @MainActor func activityLogViewModelSegments() throws {
        let activity = Activity(
            id: 42,
            owner: .account(accountID: "local", displayName: "Local"),
            kind: .refreshFeedContent(feedURL: "https://example.test/feed.xml"),
            detail: "Example Feed"
        )

        let segments = NetNewsWireSharedCore.ActivityLogViewModel.segments(for: activity)
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

    @Test("Timeline fetch request operation uses desktop read-filter table on Linux")
    @MainActor func timelineFetchRequestOperationUsesDesktopReadFilterTable() async throws {
        let sidebarItemID = SidebarItemIdentifier.feed("account", "feed")
        let allArticle = makeArticle(uniqueID: "all", title: "All", read: true)
        let unreadArticle = makeArticle(uniqueID: "unread", title: "Unread", read: false)
        let fetcher = RecordingSidebarFetcher(
            sidebarItemID: sidebarItemID,
            defaultReadFilterType: .read,
            allArticles: [allArticle],
            unreadArticles: [unreadArticle]
        )
        var resultIDs: [String] = []

        let operation = FetchRequestOperation(
            id: 1,
            readFilterEnabledTable: [sidebarItemID: false],
            fetchers: [fetcher]
        ) { articles, completedOperation in
            #expect(completedOperation.id == 1)
            resultIDs = articles.map(\.articleID).sorted()
        }

        operation.run { completedOperation in
            #expect(completedOperation === operation)
        }
        try await waitForMainActorCondition { operation.isFinished }

        #expect(fetcher.fetchArticlesAsyncCount == 1)
        #expect(fetcher.fetchUnreadArticlesAsyncCount == 0)
        #expect(resultIDs == [allArticle.articleID])
    }

    @Test("Timeline fetch request queue drops canceled requests")
    @MainActor func timelineFetchRequestQueueDropsCanceledRequests() async throws {
        let article = makeArticle(uniqueID: "queued", title: "Queued")
        let firstFetcher = RecordingSidebarFetcher(allArticles: [article], unreadArticles: [article])
        let canceledFetcher = RecordingSidebarFetcher(allArticles: [article], unreadArticles: [article])
        let queue = FetchRequestQueue()
        var completedIDs: [Int] = []

        let first = FetchRequestOperation(id: 1, readFilterEnabledTable: [:], fetchers: [firstFetcher]) { _, operation in
            completedIDs.append(operation.id)
        }
        let canceled = FetchRequestOperation(id: 2, readFilterEnabledTable: [:], fetchers: [canceledFetcher]) { _, operation in
            completedIDs.append(operation.id)
        }
        canceled.isCanceled = true

        queue.add(first)
        queue.add(canceled)
        try await waitForMainActorCondition { first.isFinished }
        await Task.yield()

        #expect(completedIDs == [1])
        #expect(canceledFetcher.fetchUnreadArticlesAsyncCount == 0)
        #expect(!queue.isAnyCurrentRequest)
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

    private func shortcutEntries(named name: String) throws -> [[String: Any]] {
        let url = try #require(NetNewsWireResource.url(forResource: name, withExtension: "plist"))
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(propertyList as? [[String: Any]])
    }

    @MainActor private func makeTemporaryLocalAccount(id: String) throws -> Account {
        let accountURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NetNewsWireSharedCoreTests", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.removeItem(at: accountURL)
        try FileManager.default.createDirectory(at: accountURL, withIntermediateDirectories: true)

        let emptyOPMLURL = accountURL.appendingPathComponent("Subscriptions.opml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Empty</title></head>
          <body></body>
        </opml>
        """.write(to: emptyOPMLURL, atomically: true, encoding: .utf8)

        return Account(dataFolder: accountURL.path, type: .onMyMac, accountID: id)
    }

    private func makeArticle(
        uniqueID: String,
        title: String?,
        read: Bool = false,
        starred: Bool = false,
        body: String? = nil,
        authors: Set<Author>? = nil,
        url: String? = nil,
        externalURL: String? = nil
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
            url: url,
            externalURL: externalURL,
            summary: nil,
            imageURL: nil,
            datePublished: nil,
            dateModified: nil,
            authors: authors,
            status: ArticleStatus(articleID: "article-\(uniqueID)", read: read, starred: starred, dateArrived: Date(timeIntervalSince1970: 0))
        )
    }

    private func makeLatestArticle(id: String) -> LatestArticle {
        LatestArticle(
            id: id,
            feedTitle: "Feed \(id)",
            articleTitle: "Title \(id)",
            articleSummary: "Summary \(id)",
            feedIconPath: nil,
            pubDate: "2026-06-16T00:00:00Z"
        )
    }

    @MainActor private func activity(named label: String, in manager: ActivityManager) -> NSUserActivity? {
        Mirror(reflecting: manager).children.first { $0.label == label }?.value as? NSUserActivity
    }

    @MainActor private func withFreshAccountManager<T>(_ body: (AccountManager) throws -> T) rethrows -> T {
        let previous = AccountManager.shared
        let manager = AccountManager()
        AccountManager.shared = manager
        defer {
            AccountManager.shared = previous
        }
        return try body(manager)
    }

    @MainActor private func firstNode<T: AnyObject>(in nodes: [Node], representing object: T) -> Node? {
        nodes.first { ($0.representedObject as? T) === object }
    }

    @MainActor private func folderNames(in nodes: [Node]) -> [String] {
        nodes.compactMap { ($0.representedObject as? Folder)?.nameForDisplay }
    }

    @MainActor private func waitForMainActorCondition(_ condition: @MainActor @escaping () -> Bool) async throws {
        for _ in 0..<50 {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(condition())
    }

    private func color(_ color: NSColor?, equals expected: [CGFloat], accuracy: CGFloat = 0.0001) -> Bool {
        guard let components = color?.components, components.count == expected.count else {
            return false
        }
        return zip(components, expected).allSatisfy { abs($0 - $1) <= accuracy }
    }

    private func data(_ image: RSImage?, hasPNGSignature: Bool) -> Bool {
        guard hasPNGSignature, let data = image?.data else { return false }
        return Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]
    }
}

@MainActor private final class NamedDisplayObject: NSObject, DisplayNameProvider {
    let nameForDisplay: String

    init(_ nameForDisplay: String) {
        self.nameForDisplay = nameForDisplay
        super.init()
    }
}

@MainActor private final class RecordingArticleExtractorDelegate: ArticleExtractorDelegate {
    private(set) var completedArticles: [ExtractedArticle] = []
    private(set) var errors: [Error] = []

    func articleExtractionDidFail(with error: Error) {
        errors.append(error)
    }

    func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
        completedArticles.append(extractedArticle)
    }
}

private final class RecordingURLSchemeHandler: WKURLSchemeHandler {}

@MainActor private final class RecordingSidebarFetcher: SidebarItem {
    let account: Account? = nil
    let defaultReadFilterType: ReadFilterType
    let nameForDisplay = "Recording"
    let sidebarItemID: SidebarItemIdentifier?
    let unreadCount: Int

    private let allArticles: Set<Article>
    private let unreadArticles: Set<Article>
    private(set) var fetchArticlesAsyncCount = 0
    private(set) var fetchUnreadArticlesAsyncCount = 0

    init(
        sidebarItemID: SidebarItemIdentifier? = .feed("account", "feed"),
        defaultReadFilterType: ReadFilterType = .read,
        allArticles: Set<Article>,
        unreadArticles: Set<Article>
    ) {
        self.sidebarItemID = sidebarItemID
        self.defaultReadFilterType = defaultReadFilterType
        self.allArticles = allArticles
        self.unreadArticles = unreadArticles
        self.unreadCount = unreadArticles.count
    }

    func fetchArticles() -> Set<Article> {
        allArticles
    }

    func fetchArticlesAsync() async -> Set<Article> {
        fetchArticlesAsyncCount += 1
        return allArticles
    }

    func fetchUnreadArticles() -> Set<Article> {
        unreadArticles
    }

    func fetchUnreadArticlesAsync() async -> Set<Article> {
        fetchUnreadArticlesAsyncCount += 1
        return unreadArticles
    }
}
