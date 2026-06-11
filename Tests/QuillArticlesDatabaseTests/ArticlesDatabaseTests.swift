import Foundation
import Testing
import QuillArticles
@testable import QuillArticlesDatabase
import QuillRSParser

@Suite("QuillArticlesDatabase")
@MainActor
struct ArticlesDatabaseTests {
    private func tempPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-articles-db-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("articles.sqlite").path
    }

    private func database(retentionStyle: ArticlesDatabase.RetentionStyle = .feedBased) -> ArticlesDatabase {
        ArticlesDatabase(databaseFilePath: tempPath(), accountID: "Local", retentionStyle: retentionStyle)
    }

    private func parsedItem(
        _ uniqueID: String,
        feedURL: String = "https://example.test/feed",
        title: String? = nil,
        body: String? = nil,
        date: Date? = nil,
        author: String? = nil
    ) -> ParsedItem {
        ParsedItem(
            syncServiceID: nil,
            uniqueID: uniqueID,
            feedURL: feedURL,
            url: "https://example.test/\(uniqueID)",
            externalURL: nil,
            title: title ?? "Title \(uniqueID)",
            language: nil,
            contentHTML: body,
            contentText: nil,
            markdown: nil,
            summary: body,
            imageURL: nil,
            bannerImageURL: nil,
            datePublished: date,
            dateModified: nil,
            authors: author.map { [ParsedAuthor(name: $0, url: nil, avatarURL: nil, emailAddress: nil)] },
            tags: nil,
            attachments: nil
        )
    }

    private func articleIDs(_ articles: Set<Article>) -> Set<String> {
        Set(articles.map(\.articleID))
    }

    @Test("feed-based update persists parsed articles and survives reopen")
    func updatePersistsParsedArticles() async throws {
        let path = tempPath()
        let feedID = "https://example.test/feed"
        let date = Date()

        do {
            let db = ArticlesDatabase(databaseFilePath: path, accountID: "Local", retentionStyle: .feedBased)
            let changes = try await db.updateAsync(
                parsedItems: [parsedItem("one", title: "One", body: "<p>Hello</p>", date: date, author: "Ada")],
                feedID: feedID,
                deleteOlder: false
            )
            #expect(changes.new?.count == 1)
            #expect(changes.updated == nil)
        }

        let reopened = ArticlesDatabase(databaseFilePath: path, accountID: "Local", retentionStyle: .feedBased)
        let articles = try reopened.fetchArticles(feedID: feedID)
        #expect(articles.count == 1)
        let article = try #require(articles.first)
        #expect(article.title == "One")
        #expect(article.contentHTML == "<p>Hello</p>")
        #expect(article.datePublished == date)
        #expect(article.authors?.first?.name == "Ada")
        #expect(!article.status.read)
    }

    @Test("update reports content updates and feed retention deletes missing unstarred articles")
    func updateReportsUpdatesAndDeletes() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        _ = try await db.updateAsync(
            parsedItems: [
                parsedItem("one", title: "Old"),
                parsedItem("two", title: "Keep"),
                parsedItem("drop", title: "Drop")
            ],
            feedID: feedID,
            deleteOlder: false
        )
        let two = try #require(try db.fetchArticles(feedID: feedID).first { $0.uniqueID == "two" })
        _ = try await db.markAsync(articles: [two], statusKey: .starred, flag: true)

        let changes = try await db.updateAsync(
            parsedItems: [parsedItem("one", title: "New")],
            feedID: feedID,
            deleteOlder: true
        )

        #expect(changes.new == nil)
        #expect(changes.updated?.first?.title == "New")
        #expect(changes.deleted?.map(\.uniqueID) == ["drop"])
        let articles = try db.fetchArticles(feedID: feedID)
        #expect(articles.map(\.uniqueID).sorted() == ["one", "two"])
        #expect(try #require(articles.first { $0.uniqueID == "two" }).status.starred)
    }

    @Test("marking drives unread, starred, and count APIs")
    func markingAndCounts() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        _ = try await db.updateAsync(
            parsedItems: [parsedItem("one"), parsedItem("two")],
            feedID: feedID,
            deleteOlder: false
        )
        let articles = try db.fetchArticles(feedID: feedID)
        let one = try #require(articles.first { $0.uniqueID == "one" })
        _ = try await db.markAsync(articles: [one], statusKey: .read, flag: true)
        _ = try await db.markAsync(articles: [one], statusKey: .starred, flag: true)

        #expect(try await db.fetchUnreadCountAsync(feedID: feedID) == 1)
        #expect(try await db.fetchUnreadCountsAsync(feedIDs: [feedID]) == [feedID: 1])
        #expect(try await db.fetchUnreadArticleIDsAsync().count == 1)
        #expect(try await db.fetchStarredArticleIDsAsync() == [one.articleID])
        #expect(try db.fetchStarredArticlesCount(feedIDs: [feedID]) == 1)

        let counts = try await db.fetchArticleCountsAsync(feedIDs: [feedID])
        #expect(counts.totalCount == 2)
        #expect(counts.unreadCount == 1)
        #expect(counts.starredCount == 1)
        #expect(counts.statusesCount == 2)
    }

    @Test("today, search, and last update APIs use stored article fields")
    func todaySearchAndLastUpdates() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        let recent = Date().addingTimeInterval(-3600)
        let old = Date().addingTimeInterval(-172_800)
        _ = try await db.updateAsync(
            parsedItems: [
                parsedItem("recent", title: "Swift News", body: "<p>compiler database</p>", date: recent),
                parsedItem("old", title: "Archive", body: "<p>old body</p>", date: old)
            ],
            feedID: feedID,
            deleteOlder: false
        )

        #expect(try db.fetchTodayArticles(feedIDs: [feedID]).map(\.uniqueID) == ["recent"])
        #expect(try db.fetchArticlesMatching(searchString: "compiler", feedIDs: [feedID]).map(\.uniqueID) == ["recent"])
        #expect(try await db.fetchLastUpdateDates()[feedID] == recent)
    }

    @Test("sync-system update honors defaultRead and markAndFetchNew creates missing statuses")
    func syncUpdateAndStatusCreation() async throws {
        let db = database(retentionStyle: .syncSystem)
        let feedID = "https://example.test/feed"
        let changes = try await db.updateAsync(
            feedIDsAndItems: [feedID: [parsedItem("one")]],
            defaultRead: true
        )
        #expect(changes.new?.count == 1)
        #expect(try await db.fetchUnreadCountAsync(feedID: feedID) == 0)

        let newIDs = try await db.markAndFetchNewAsync(
            articleIDs: ["missing"],
            statusKey: .starred,
            flag: true
        )
        #expect(newIDs == ["missing"])
        #expect(try await db.fetchStarredArticleIDsAsync().contains("missing"))
        #expect(try await db.fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync() == ["missing"])
    }

    @Test("delete removes articles but leaves status records available for sync repair")
    func deleteLeavesStatuses() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        _ = try await db.updateAsync(parsedItems: [parsedItem("one")], feedID: feedID, deleteOlder: false)
        let article = try #require(try db.fetchArticles(feedID: feedID).first)

        try await db.deleteAsync(articleIDs: [article.articleID])

        #expect(try db.fetchArticles(feedID: feedID).isEmpty)
        #expect(try await db.fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync().contains(article.articleID))
    }

    @Test("batch fetches, limits, and unread-count variants compose across feeds")
    func batchFetchLimitsAndUnreadVariants() async throws {
        let db = database()
        let feedA = "https://example.test/a"
        let feedB = "https://example.test/b"
        let recent = Date().addingTimeInterval(-60)
        let older = Date().addingTimeInterval(-3_600)
        let old = Date().addingTimeInterval(-172_800)
        _ = try await db.updateAsync(
            parsedItems: [
                parsedItem("newest", feedURL: feedA, date: recent),
                parsedItem("older", feedURL: feedA, date: older),
                parsedItem("old", feedURL: feedA, date: old)
            ],
            feedID: feedA,
            deleteOlder: false
        )
        _ = try await db.updateAsync(
            parsedItems: [parsedItem("other", feedURL: feedB, date: recent)],
            feedID: feedB,
            deleteOlder: false
        )
        let newest = try #require(try db.fetchArticles(feedID: feedA).first { $0.uniqueID == "newest" })
        let olderArticle = try #require(try db.fetchArticles(feedID: feedA).first { $0.uniqueID == "older" })
        _ = try await db.markAsync(articles: [newest], statusKey: .read, flag: true)
        _ = try await db.markAsync(articles: [olderArticle], statusKey: .starred, flag: true)

        #expect(try db.fetchArticles(feedIDs: [feedA]).count == 3)
        #expect(try db.fetchArticles(articleIDs: [newest.articleID]).first?.uniqueID == "newest")
        #expect(try db.fetchUnreadArticles(feedIDs: [feedA], limit: 1).count == 1)
        #expect(try await db.fetchUnreadArticlesAsync(feedIDs: [feedA]).count == 2)
        #expect(try await db.fetchTodayArticlesAsync(feedIDs: [feedA]).count == 2)
        #expect(try await db.fetchedStarredArticlesAsync(feedIDs: [feedA]).map(\.uniqueID) == ["older"])
        #expect(try await db.fetchAllUnreadCountsAsync() == [feedA: 2, feedB: 1])
        #expect(try await db.fetchUnreadCountForTodayAsync(feedIDs: [feedA]) == 1)
        #expect(try await db.fetchUnreadCountForStarredArticlesAsync(feedIDs: [feedA]) == 1)
        #expect(try db.fetchUnreadArticles(feedIDs: [feedA], limit: 0).isEmpty)
        #expect(try db.fetchUnreadArticles(feedIDs: [feedA], limit: -1).isEmpty)
    }

    @Test("search by article IDs and status creation preserve existing flags")
    func searchByIDsAndStatusCreation() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        _ = try await db.updateAsync(
            parsedItems: [
                parsedItem("one", title: "SwiftUI", body: "<p>linux reader</p>"),
                parsedItem("two", title: "Database", body: "<p>sqlite article</p>")
            ],
            feedID: feedID,
            deleteOlder: false
        )
        let articles = try db.fetchArticles(feedID: feedID)
        let one = try #require(articles.first { $0.uniqueID == "one" })
        _ = try await db.markAsync(articles: [one], statusKey: .read, flag: true)

        let matches = try db.fetchArticlesMatchingWithArticleIDs(
            searchString: "linux",
            articleIDs: articleIDs(articles)
        )
        #expect(matches.map(\.uniqueID) == ["one"])

        let asyncMatches = try await db.fetchArticlesMatchingWithArticleIDsAsync(
            searchString: "sqlite",
            articleIDs: articleIDs(articles)
        )
        #expect(asyncMatches.map(\.uniqueID) == ["two"])

        try await db.createStatusesIfNeededAsync(articleIDs: [one.articleID, "created"])
        #expect(try await db.fetchUnreadArticleIDsAsync().contains(one.articleID) == false)
        #expect(try await db.fetchUnreadArticleIDsAsync().contains("created") == false)
    }

    @Test("future published dates are normalized out before storage")
    func futureDatesAreNormalized() async throws {
        let db = database()
        let feedID = "https://example.test/feed"
        let future = Date().addingTimeInterval(172_800)
        _ = try await db.updateAsync(
            parsedItems: [parsedItem("future", date: future)],
            feedID: feedID,
            deleteOlder: false
        )

        let article = try #require(try db.fetchArticles(feedID: feedID).first)
        #expect(article.datePublished == nil)
    }

    @Test("startup cleanup drops unsubscribed articles and keeps recent orphan statuses")
    func startupCleanupPrunesUnsubscribedArticles() async throws {
        let db = database()
        let keepFeed = "https://example.test/keep"
        let dropFeed = "https://example.test/drop"
        _ = try await db.updateAsync(parsedItems: [parsedItem("keep")], feedID: keepFeed, deleteOlder: false)
        _ = try await db.updateAsync(parsedItems: [parsedItem("drop")], feedID: dropFeed, deleteOlder: false)

        let drop = try #require(try db.fetchArticles(feedID: dropFeed).first)
        _ = try await db.markAsync(articles: [drop], statusKey: .read, flag: true)
        try await db.deleteAsync(articleIDs: [drop.articleID])
        db.cleanupDatabaseAtStartup(subscribedToFeedIDs: [keepFeed])

        #expect(try db.fetchArticles(feedID: keepFeed).count == 1)
        #expect(try db.fetchArticles(feedID: dropFeed).isEmpty)
        #expect(try await db.fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync().contains(drop.articleID))
    }

    @Test("empty updates and maintenance calls are deterministic no-ops")
    func emptyUpdatesAndMaintenanceNoOps() async throws {
        let feedBased = database()
        let feedChanges = try await feedBased.updateAsync(parsedItems: [], feedID: "feed", deleteOlder: true)
        #expect(feedChanges.new == nil)
        #expect(feedChanges.updated == nil)
        #expect(feedChanges.deleted == nil)

        let sync = database(retentionStyle: .syncSystem)
        let syncChanges = try await sync.updateAsync(feedIDsAndItems: [:], defaultRead: true)
        #expect(syncChanges.new == nil)
        #expect(syncChanges.updated == nil)
        #expect(syncChanges.deleted == nil)

        feedBased.emptyCaches()
        await feedBased.vacuum()
        #expect(try feedBased.fetchAllArticles().isEmpty)
    }
}
