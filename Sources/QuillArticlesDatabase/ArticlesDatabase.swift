import Foundation
import QuillArticles
import QuillData
import QuillRSParser

public typealias UnreadCountDictionary = [String: Int]

public struct ArticleChanges: Sendable {
    public let new: Set<Article>?
    public let updated: Set<Article>?
    public let deleted: Set<Article>?

    public init() {
        self.new = Set<Article>()
        self.updated = Set<Article>()
        self.deleted = Set<Article>()
    }

    public init(new: Set<Article>?, updated: Set<Article>?, deleted: Set<Article>?) {
        self.new = new
        self.updated = updated
        self.deleted = deleted
    }
}

public struct ArticleCounts: Sendable {
    public let totalCount: Int
    public let unreadCount: Int
    public let starredCount: Int
    public let statusesCount: Int

    public init(totalCount: Int, unreadCount: Int, starredCount: Int, statusesCount: Int) {
        self.totalCount = totalCount
        self.unreadCount = unreadCount
        self.starredCount = starredCount
        self.statusesCount = statusesCount
    }
}

private struct ArticleRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillArticlesDatabase.ArticleRecord"

    var id: String
    var accountID: String
    var feedID: String
    var uniqueID: String
    var title: String?
    var contentHTML: String?
    var contentText: String?
    var markdown: String?
    var url: String?
    var externalURL: String?
    var summary: String?
    var imageURL: String?
    var datePublished: Date?
    var dateModified: Date?
    var authors: [Author]?

    init(article: Article) {
        self.id = article.articleID
        self.accountID = article.accountID
        self.feedID = article.feedID
        self.uniqueID = article.uniqueID
        self.title = article.title
        self.contentHTML = article.contentHTML
        self.contentText = article.contentText
        self.markdown = article.markdown
        self.url = article.rawLink
        self.externalURL = article.rawExternalLink
        self.summary = article.summary
        self.imageURL = article.rawImageLink
        self.datePublished = article.datePublished
        self.dateModified = article.dateModified
        self.authors = article.authors.map { Array($0) }
    }

    func article(status: ArticleStatus) -> Article {
        Article(
            accountID: accountID,
            articleID: id,
            feedID: feedID,
            uniqueID: uniqueID,
            title: title,
            contentHTML: contentHTML,
            contentText: contentText,
            markdown: markdown,
            url: url,
            externalURL: externalURL,
            summary: summary,
            imageURL: imageURL,
            datePublished: datePublished,
            dateModified: dateModified,
            authors: authors.map { Set($0) },
            status: status
        )
    }
}

private struct ArticleStatusRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillArticlesDatabase.ArticleStatusRecord"

    var id: String
    var read: Bool
    var starred: Bool
    var dateArrived: Date

    init(articleID: String, read: Bool, starred: Bool = false, dateArrived: Date = Date()) {
        self.id = articleID
        self.read = read
        self.starred = starred
        self.dateArrived = dateArrived
    }

    init(status: ArticleStatus) {
        self.init(
            articleID: status.articleID,
            read: status.read,
            starred: status.starred,
            dateArrived: status.dateArrived
        )
    }

    var status: ArticleStatus {
        ArticleStatus(articleID: id, read: read, starred: starred, dateArrived: dateArrived)
    }
}

public final class ArticlesDatabase {
    public enum RetentionStyle: Sendable {
        case feedBased
        case syncSystem
    }

    public let databasePath: String

    private let accountID: String
    private let retentionStyle: RetentionStyle
    private let context: ModelContext

    public init(databaseFilePath: String, accountID: String, retentionStyle: RetentionStyle) {
        self.databasePath = databaseFilePath
        self.accountID = accountID
        self.retentionStyle = retentionStyle

        let schema = Schema([ArticleRecord.self, ArticleStatusRecord.self])
        let url = URL(fileURLWithPath: databaseFilePath)
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    public func vacuum() async {}

    public func fetchArticles(feedID: String) throws -> Set<Article> {
        try articles(matching: { $0.feedID == feedID })
    }

    public func fetchArticles(feedIDs: Set<String>) throws -> Set<Article> {
        try articles(matching: { feedIDs.contains($0.feedID) })
    }

    public func fetchArticles(articleIDs: Set<String>) throws -> Set<Article> {
        try articles(matching: { articleIDs.contains($0.id) })
    }

    public func fetchAllArticles() throws -> Set<Article> {
        try articles(matching: { _ in true })
    }

    public func fetchUnreadArticles(feedIDs: Set<String>, limit: Int? = nil) throws -> Set<Article> {
        let result = sortedArticles(
            try fetchArticles(feedIDs: feedIDs).filter { !$0.status.read }
        )
        return Set(limited(result, limit: limit))
    }

    public func fetchTodayArticles(feedIDs: Set<String>, limit: Int? = nil) throws -> Set<Article> {
        let cutoff = todayCutoffDate()
        let result = sortedArticles(
            try fetchArticles(feedIDs: feedIDs).filter { ($0.datePublished.map { $0 >= cutoff }) == true }
        )
        return Set(limited(result, limit: limit))
    }

    public func fetchStarredArticles(feedIDs: Set<String>, limit: Int? = nil) throws -> Set<Article> {
        let result = sortedArticles(
            try fetchArticles(feedIDs: feedIDs).filter(\.status.starred)
        )
        return Set(limited(result, limit: limit))
    }

    public func fetchStarredArticlesCount(feedIDs: Set<String>) throws -> Int {
        try fetchStarredArticles(feedIDs: feedIDs).count
    }

    public func fetchArticleCountsAsync(feedIDs: Set<String>) async throws -> ArticleCounts {
        let articles = try fetchArticles(feedIDs: feedIDs)
        let articleIDs = Set(articles.map(\.articleID))
        let statuses = try statusRecords().filter { articleIDs.contains($0.id) }
        return ArticleCounts(
            totalCount: articles.count,
            unreadCount: articles.filter { !$0.status.read }.count,
            starredCount: articles.filter(\.status.starred).count,
            statusesCount: statuses.count
        )
    }

    public func fetchArticlesMatching(searchString: String, feedIDs: Set<String>) throws -> Set<Article> {
        let needle = searchString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try fetchArticles(feedIDs: feedIDs) }
        return try Set(fetchArticles(feedIDs: feedIDs).filter { articleMatches($0, needle: needle) })
    }

    public func fetchArticlesMatchingWithArticleIDs(searchString: String, articleIDs: Set<String>) throws -> Set<Article> {
        let needle = searchString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return try fetchArticles(articleIDs: articleIDs) }
        return try Set(fetchArticles(articleIDs: articleIDs).filter { articleMatches($0, needle: needle) })
    }

    public func fetchLastUpdateDates() async throws -> [String: Date] {
        var result: [String: Date] = [:]
        for article in try articles(matching: { _ in true }) {
            guard let date = article.datePublished else { continue }
            if result[article.feedID].map({ date > $0 }) ?? true {
                result[article.feedID] = date
            }
        }
        return result
    }

    public func fetchArticlesAsync(feedID: String) async throws -> Set<Article> {
        try fetchArticles(feedID: feedID)
    }

    public func fetchArticlesAsync(feedIDs: Set<String>) async throws -> Set<Article> {
        try fetchArticles(feedIDs: feedIDs)
    }

    public func fetchArticlesAsync(articleIDs: Set<String>) async throws -> Set<Article> {
        try fetchArticles(articleIDs: articleIDs)
    }

    public func fetchUnreadArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async throws -> Set<Article> {
        try fetchUnreadArticles(feedIDs: feedIDs, limit: limit)
    }

    public func fetchTodayArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async throws -> Set<Article> {
        try fetchTodayArticles(feedIDs: feedIDs, limit: limit)
    }

    public func fetchedStarredArticlesAsync(feedIDs: Set<String>, limit: Int? = nil) async throws -> Set<Article> {
        try fetchStarredArticles(feedIDs: feedIDs, limit: limit)
    }

    public func fetchArticlesMatchingAsync(searchString: String, feedIDs: Set<String>) async throws -> Set<Article> {
        try fetchArticlesMatching(searchString: searchString, feedIDs: feedIDs)
    }

    public func fetchArticlesMatchingWithArticleIDsAsync(searchString: String, articleIDs: Set<String>) async throws -> Set<Article> {
        try fetchArticlesMatchingWithArticleIDs(searchString: searchString, articleIDs: articleIDs)
    }

    public func fetchAllUnreadCountsAsync() async throws -> UnreadCountDictionary? {
        let articles = try articles(matching: { _ in true })
        return unreadCounts(for: Set(articles.map(\.feedID)), articles: articles)
    }

    public func fetchUnreadCountAsync(feedID: String) async throws -> Int {
        try await fetchUnreadCountsAsync(feedIDs: [feedID])[feedID] ?? 0
    }

    public func fetchUnreadCountsAsync(feedIDs: Set<String>) async throws -> UnreadCountDictionary {
        try unreadCounts(for: feedIDs, articles: fetchArticles(feedIDs: feedIDs))
    }

    public func fetchUnreadCountForTodayAsync(feedIDs: Set<String>) async throws -> Int {
        try fetchTodayArticles(feedIDs: feedIDs).filter { !$0.status.read }.count
    }

    public func fetchUnreadCountForStarredArticlesAsync(feedIDs: Set<String>) async throws -> Int {
        try fetchStarredArticles(feedIDs: feedIDs).filter { !$0.status.read }.count
    }

    public func updateAsync(parsedItems: Set<ParsedItem>, feedID: String, deleteOlder: Bool) async throws -> ArticleChanges {
        precondition(retentionStyle == .feedBased)
        guard !parsedItems.isEmpty else { return ArticleChanges(new: nil, updated: nil, deleted: nil) }
        return try updateFeed(parsedItems: parsedItems, feedID: feedID, defaultRead: nil, deleteMissing: deleteOlder)
    }

    public func updateAsync(feedIDsAndItems: [String: Set<ParsedItem>], defaultRead: Bool) async throws -> ArticleChanges {
        precondition(retentionStyle == .syncSystem)
        guard !feedIDsAndItems.isEmpty else { return ArticleChanges(new: nil, updated: nil, deleted: nil) }

        var newArticles = Set<Article>()
        var updatedArticles = Set<Article>()
        for (feedID, items) in feedIDsAndItems {
            let changes = try updateFeed(parsedItems: items, feedID: feedID, defaultRead: defaultRead, deleteMissing: false)
            newArticles.formUnion(changes.new ?? [])
            updatedArticles.formUnion(changes.updated ?? [])
        }
        return ArticleChanges(
            new: newArticles.isEmpty ? nil : newArticles,
            updated: updatedArticles.isEmpty ? nil : updatedArticles,
            deleted: nil
        )
    }

    public func deleteAsync(articleIDs: Set<String>) async throws {
        try deleteArticles(articleIDs)
    }

    @discardableResult
    public func replaceArticles(feedID: String, articles: Set<Article>) throws -> ArticleChanges {
        let existingArticles = try fetchArticles(feedID: feedID)
        let incomingIDs = Set(articles.map(\.articleID))
        let existingByID = Dictionary(uniqueKeysWithValues: existingArticles.map { ($0.articleID, $0) })

        let newArticles = Set(articles.filter { existingByID[$0.articleID] == nil })
        let updatedArticles = Set(articles.filter { article in
            existingByID[article.articleID].map { articleContentDiffers(article, $0) } ?? false
        })
        let deletedArticles = Set(existingArticles.filter { !incomingIDs.contains($0.articleID) })

        try deleteArticles(Set(deletedArticles.map(\.articleID)), save: false)
        for article in articles {
            context.insert(ArticleRecord(article: article))
            context.insert(ArticleStatusRecord(status: article.status))
        }
        try context.save()

        return ArticleChanges(
            new: newArticles.isEmpty ? nil : newArticles,
            updated: updatedArticles.isEmpty ? nil : updatedArticles,
            deleted: deletedArticles.isEmpty ? nil : deletedArticles
        )
    }

    public func fetchUnreadArticleIDsAsync() async throws -> Set<String> {
        Set(try statusRecords().filter { !$0.read }.map(\.id))
    }

    public func fetchStarredArticleIDsAsync() async throws -> Set<String> {
        Set(try statusRecords().filter(\.starred).map(\.id))
    }

    public func fetchArticleIDsForStatusesWithoutArticlesNewerThanCutoffDateAsync() async throws -> Set<String> {
        let articleIDs = Set(try articleRecords().map(\.id))
        let cutoff = Date(timeIntervalSinceNow: -ArticleStatus.staleIntervalInSeconds)
        return Set(try statusRecords().compactMap { record in
            guard !articleIDs.contains(record.id) else { return nil }
            guard record.starred || record.dateArrived > cutoff else { return nil }
            return record.id
        })
    }

    public func markAsync(articles: Set<Article>, statusKey: ArticleStatus.Key, flag: Bool) async throws -> Set<ArticleStatus> {
        var updated = Set<ArticleStatus>()
        for article in articles {
            if article.status.boolStatus(forKey: statusKey) != flag {
                article.status.setBoolStatus(flag, forKey: statusKey)
                updated.insert(article.status)
            }
            context.insert(ArticleStatusRecord(status: article.status))
        }
        try context.save()
        return updated
    }

    public func markAndFetchNewAsync(articleIDs: Set<String>, statusKey: ArticleStatus.Key, flag: Bool) async throws -> Set<String> {
        let existing = Set(try statusRecords().map(\.id))
        let newIDs = articleIDs.subtracting(existing)
        for articleID in articleIDs {
            var record = try statusRecord(articleID: articleID)
                ?? ArticleStatusRecord(articleID: articleID, read: false)
            switch statusKey {
            case .read:
                record.read = flag
            case .starred:
                record.starred = flag
            }
            context.insert(record)
        }
        try context.save()
        return newIDs
    }

    public func createStatusesIfNeededAsync(articleIDs: Set<String>) async throws {
        let existing = Set(try statusRecords().map(\.id))
        for articleID in articleIDs.subtracting(existing) {
            context.insert(ArticleStatusRecord(articleID: articleID, read: true))
        }
        try context.save()
    }

    public func emptyCaches() {}

    public func cleanupDatabaseAtStartup(subscribedToFeedIDs: Set<String>) {
        let staleCutoff = Date(timeIntervalSinceNow: -ArticleStatus.staleIntervalInSeconds)
        var articleIDs = Set<String>()
        if let records = try? articleRecords() {
            articleIDs = Set(records.map(\.id))
            let idsToDelete = Set(records.compactMap { record in
                subscribedToFeedIDs.contains(record.feedID) ? nil : record.id
            })
            try? deleteArticles(idsToDelete)
            articleIDs.subtract(idsToDelete)
        }
        if let records = try? statusRecords() {
            for record in records
            where !articleIDs.contains(record.id) && !record.starred && record.read && record.dateArrived < staleCutoff {
                context.delete(record)
            }
            try? context.save()
        }
    }
}

private extension ArticlesDatabase {
    func todayCutoffDate() -> Date {
        Date(timeIntervalSinceNow: -86_400)
    }

    func articleRecords() throws -> [ArticleRecord] {
        try context.fetch(FetchDescriptor<ArticleRecord>())
    }

    func statusRecords() throws -> [ArticleStatusRecord] {
        try context.fetch(FetchDescriptor<ArticleStatusRecord>())
    }

    func statusRecord(articleID: String) throws -> ArticleStatusRecord? {
        try statusRecords().first { $0.id == articleID }
    }

    func articles(matching predicate: (ArticleRecord) -> Bool) throws -> Set<Article> {
        let statusesByID = Dictionary(uniqueKeysWithValues: try statusRecords().map { ($0.id, $0) })
        let articles = try articleRecords()
            .filter(predicate)
            .map { record -> Article in
                let status = statusesByID[record.id]?.status
                    ?? ArticleStatus(articleID: record.id, read: false, dateArrived: Date())
                return record.article(status: status)
            }
        return Set(articles)
    }

    func sortedArticles(_ articles: Set<Article>) -> [Article] {
        articles.sorted { lhs, rhs in
            switch (lhs.datePublished, rhs.datePublished) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.articleID < rhs.articleID
            }
        }
    }

    func limited(_ articles: [Article], limit: Int?) -> [Article] {
        guard let limit else { return articles }
        guard limit > 0 else { return [] }
        return Array(articles.prefix(limit))
    }

    func unreadCounts(for feedIDs: Set<String>, articles: Set<Article>) -> UnreadCountDictionary {
        var result: UnreadCountDictionary = [:]
        for article in articles where feedIDs.contains(article.feedID) && !article.status.read {
            result[article.feedID, default: 0] += 1
        }
        return result
    }

    func articleMatches(_ article: Article, needle: String) -> Bool {
        let haystack = [
            article.title,
            article.contentHTML,
            article.contentText,
            article.markdown,
            article.summary,
            article.authors?.compactMap(\.name).joined(separator: " ")
        ]
        return haystack.contains { ($0 ?? "").lowercased().contains(needle) }
    }

    func updateFeed(
        parsedItems: Set<ParsedItem>,
        feedID: String,
        defaultRead: Bool?,
        deleteMissing: Bool
    ) throws -> ArticleChanges {
        let existingArticles = try fetchArticles(feedID: feedID)
        let existingByID = Dictionary(uniqueKeysWithValues: existingArticles.map { ($0.articleID, $0) })
        let incomingArticles = try materializeArticles(parsedItems, feedID: feedID, defaultRead: defaultRead)

        var newArticles = Set<Article>()
        var updatedArticles = Set<Article>()
        for article in incomingArticles {
            if let existing = existingByID[article.articleID] {
                if articleContentDiffers(article, existing) {
                    updatedArticles.insert(article)
                }
            } else {
                newArticles.insert(article)
            }
            context.insert(ArticleRecord(article: article))
            context.insert(ArticleStatusRecord(status: article.status))
        }

        var deletedArticles = Set<Article>()
        if deleteMissing {
            let incomingIDs = Set(incomingArticles.map(\.articleID))
            deletedArticles = Set(existingArticles.filter { article in
                !incomingIDs.contains(article.articleID) && !article.status.starred
            })
            try deleteArticles(Set(deletedArticles.map(\.articleID)), save: false)
        }

        try context.save()
        return ArticleChanges(
            new: newArticles.isEmpty ? nil : newArticles,
            updated: updatedArticles.isEmpty ? nil : updatedArticles,
            deleted: deletedArticles.isEmpty ? nil : deletedArticles
        )
    }

    func materializeArticles(_ parsedItems: Set<ParsedItem>, feedID: String, defaultRead: Bool?) throws -> Set<Article> {
        let staleCutoff = Date(timeIntervalSinceNow: -ArticleStatus.staleIntervalInSeconds)
        let maximumDateAllowed = Date(timeIntervalSinceNow: 86_400)
        let statusByID = Dictionary(uniqueKeysWithValues: try statusRecords().map { ($0.id, $0) })

        return Set(parsedItems.map { item in
            let articleID = item.articleID(feedID: feedID)
            let datePublished = normalizedPublishedDate(item, maximumDateAllowed: maximumDateAllowed)
            let read = defaultRead ?? ((datePublished ?? .distantFuture) < staleCutoff)
            let status = (statusByID[articleID] ?? ArticleStatusRecord(articleID: articleID, read: read)).status
            return Article(
                accountID: accountID,
                articleID: articleID,
                feedID: feedID,
                uniqueID: item.uniqueID,
                title: item.title,
                contentHTML: item.contentHTML,
                contentText: item.contentText,
                markdown: item.markdown,
                url: item.url,
                externalURL: item.externalURL,
                summary: item.summary,
                imageURL: item.imageURL,
                datePublished: datePublished,
                dateModified: normalizedModifiedDate(item, maximumDateAllowed: maximumDateAllowed),
                authors: authors(from: item.authors),
                status: status
            )
        })
    }

    func normalizedPublishedDate(_ item: ParsedItem, maximumDateAllowed: Date) -> Date? {
        var date = item.datePublished ?? item.dateModified
        if date.map({ $0 > maximumDateAllowed }) == true {
            date = nil
        }
        return date
    }

    func normalizedModifiedDate(_ item: ParsedItem, maximumDateAllowed: Date) -> Date? {
        guard let date = item.dateModified, date <= maximumDateAllowed else { return nil }
        return date
    }

    func authors(from parsedAuthors: Set<ParsedAuthor>?) -> Set<Author>? {
        guard let parsedAuthors else { return nil }
        let authors = Set(parsedAuthors.compactMap { parsed in
            Author(
                authorID: nil,
                name: parsed.name,
                url: parsed.url,
                avatarURL: parsed.avatarURL,
                emailAddress: parsed.emailAddress
            )
        })
        return authors.isEmpty ? nil : authors
    }

    func articleContentDiffers(_ lhs: Article, _ rhs: Article) -> Bool {
        lhs.uniqueID != rhs.uniqueID ||
            lhs.title != rhs.title ||
            lhs.contentHTML != rhs.contentHTML ||
            lhs.contentText != rhs.contentText ||
            lhs.markdown != rhs.markdown ||
            lhs.rawLink != rhs.rawLink ||
            lhs.rawExternalLink != rhs.rawExternalLink ||
            lhs.summary != rhs.summary ||
            lhs.rawImageLink != rhs.rawImageLink ||
            lhs.datePublished != rhs.datePublished ||
            lhs.dateModified != rhs.dateModified ||
            lhs.authors != rhs.authors
    }

    func deleteArticles(_ articleIDs: Set<String>, save: Bool = true) throws {
        guard !articleIDs.isEmpty else { return }
        for record in try articleRecords() where articleIDs.contains(record.id) {
            context.delete(record)
        }
        if save {
            try context.save()
        }
    }
}

private extension ParsedItem {
    func articleID(feedID: String) -> String {
        syncServiceID ?? Article.calculatedArticleID(feedID: feedID, uniqueID: uniqueID)
    }
}
