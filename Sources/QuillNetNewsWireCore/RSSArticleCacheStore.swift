import Foundation
import QuillArticles
import QuillArticlesDatabase

/// Compatibility wrapper for the reader shell's RSSItem cache. The storage is
/// now the reusable NetNewsWire-shaped `ArticlesDatabase` adapter instead of a
/// private app-local QuillData table, keeping the app shell on the same path as
/// future upstream account/database work.
public final class RSSArticleCacheStore {
    private let database: ArticlesDatabase

    /// Default on-disk location: `~/.quillui/netnewswire/articles.sqlite`,
    /// honoring `QUILLDATA_HOME` / `HOME` overrides.
    public static func defaultURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let home = env["QUILLDATA_HOME"] ?? env["HOME"]
        let homeURL = home.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let baseURL = homeURL
            .appendingPathComponent(".quillui", isDirectory: true)
            .appendingPathComponent("netnewswire", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("articles.sqlite")
    }

    public init(url: URL) throws {
        self.database = ArticlesDatabase(
            databaseFilePath: url.path,
            accountID: "Local",
            retentionStyle: .feedBased
        )
    }

    /// Load the cached articles for one feed in timeline order.
    public func load(feedID: Feed.ID) throws -> [RSSItem] {
        try database.fetchArticles(feedID: feedID)
            .sortedForTimeline()
            .map(RSSItem.init(article:))
    }

    /// Load all cached articles, grouped by feed ID and sorted in per-feed
    /// timeline order.
    public func loadAll() throws -> [Feed.ID: [RSSItem]] {
        let articles = try database.fetchAllArticles()
        return Dictionary(grouping: articles, by: \.feedID)
            .mapValues { $0.sortedForTimeline().map(RSSItem.init(article:)) }
    }

    /// Replace one feed's cached timeline while preserving every other feed.
    public func replaceAll(feedID: Feed.ID, items: [RSSItem]) throws {
        let articles = Set(items.map { $0.article(feedID: feedID) })
        try database.replaceArticles(feedID: feedID, articles: articles)
    }

    /// Remove all cached articles for one feed.
    public func remove(feedID: Feed.ID) throws {
        try database.replaceArticles(feedID: feedID, articles: [])
    }
}

private extension RSSItem {
    init(article: Article) {
        self.init(
            id: article.articleID,
            title: article.title ?? "Untitled",
            link: article.rawLink,
            pubDate: RSSFeedParser.formatPubDate(article.datePublished),
            publishedDate: article.datePublished,
            descriptionHTML: article.contentHTML ?? article.contentText ?? article.summary,
            author: article.authors?.compactMap(\.name).sorted().first
        )
    }

    func article(feedID: Feed.ID) -> Article {
        let status = ArticleStatus(articleID: id, read: false, dateArrived: Date())
        return Article(
            accountID: "Local",
            articleID: id,
            feedID: feedID,
            uniqueID: id,
            title: title,
            contentHTML: descriptionHTML,
            contentText: plainTextBody.isEmpty ? nil : plainTextBody,
            markdown: nil,
            url: link,
            externalURL: nil,
            summary: plainTextBody.isEmpty ? nil : plainTextBody,
            imageURL: nil,
            datePublished: publishedDate,
            dateModified: nil,
            authors: author.flatMap {
                Author(authorID: nil, name: $0, url: nil, avatarURL: nil, emailAddress: nil).map { [$0] }
            }.map(Set.init),
            status: status
        )
    }
}

private extension Sequence where Element == Article {
    func sortedForTimeline() -> [Article] {
        sorted { lhs, rhs in
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
}
