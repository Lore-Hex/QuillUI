import Foundation
import QuillData

/// One cached timeline article for one subscribed feed. Kept as a plain
/// JSON-backed QuillData model so the first NetNewsWire cache slice works on
/// every backend QuillData already supports.
private struct RSSCachedArticleRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillNetNewsWireCore.RSSCachedArticleRecord"

    var id: String
    var feedID: String
    var articleID: String
    var title: String
    var link: String?
    var pubDate: String?
    var publishedTimestamp: Double?
    var descriptionHTML: String?
    var author: String?
    var sortIndex: Int

    init(feedID: String, item: RSSItem, sortIndex: Int) {
        self.id = Self.recordID(feedID: feedID, articleID: item.id)
        self.feedID = feedID
        self.articleID = item.id
        self.title = item.title
        self.link = item.link
        self.pubDate = item.pubDate
        self.publishedTimestamp = item.publishedDate?.timeIntervalSince1970
        self.descriptionHTML = item.descriptionHTML
        self.author = item.author
        self.sortIndex = sortIndex
    }

    var item: RSSItem {
        RSSItem(
            id: articleID,
            title: title,
            link: link,
            pubDate: pubDate,
            publishedDate: publishedTimestamp.map(Date.init(timeIntervalSince1970:)),
            descriptionHTML: descriptionHTML,
            author: author
        )
    }

    static func recordID(feedID: String, articleID: String) -> String {
        "\(feedID)\n\(articleID)"
    }
}

/// SQLite-backed cache for fetched article lists. This is intentionally small:
/// it persists the UI-facing `RSSItem` timeline so the Linux NetNewsWire shell
/// can restore feeds immediately, report unread badges for inactive feeds, and
/// back smart-feed counts without requiring the full upstream database stack.
public final class RSSArticleCacheStore {
    private let context: ModelContext

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
        let schema = Schema([RSSCachedArticleRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    /// Load the cached articles for one feed in timeline order.
    public func load(feedID: Feed.ID) throws -> [RSSItem] {
        try context.fetch(FetchDescriptor<RSSCachedArticleRecord>(
            filter: { $0.feedID == feedID },
            sortBy: [SortDescriptor(\.sortIndex)]
        ))
        .map(\.item)
    }

    /// Load all cached articles, grouped by feed ID and sorted in per-feed
    /// timeline order.
    public func loadAll() throws -> [Feed.ID: [RSSItem]] {
        let records = try context.fetch(FetchDescriptor<RSSCachedArticleRecord>(
            sortBy: [
                SortDescriptor(\.feedID),
                SortDescriptor(\.sortIndex)
            ]
        ))
        return Dictionary(grouping: records, by: \.feedID)
            .mapValues { $0.sorted { $0.sortIndex < $1.sortIndex }.map(\.item) }
    }

    /// Replace one feed's cached timeline while preserving every other feed.
    /// QuillData's JSON-backed models don't support SQL predicate deletion, so
    /// this performs a load/filter/rewrite batch. The store is deliberately
    /// small enough for that to be acceptable until the NNW cache graduates to
    /// a columnar QuillData model.
    public func replaceAll(feedID: Feed.ID, items: [RSSItem]) throws {
        let existing = try context.fetch(FetchDescriptor<RSSCachedArticleRecord>())
        let preserved = existing.filter { $0.feedID != feedID }
        try context.delete(model: RSSCachedArticleRecord.self)
        for record in preserved {
            context.insert(record)
        }
        for (index, item) in items.enumerated() {
            context.insert(RSSCachedArticleRecord(feedID: feedID, item: item, sortIndex: index))
        }
        try context.save()
    }

    /// Remove all cached articles for one feed.
    public func remove(feedID: Feed.ID) throws {
        try replaceAll(feedID: feedID, items: [])
    }
}
