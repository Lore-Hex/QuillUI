import Foundation
import QuillData

/// One subscribed feed, persisted with its list position. Plain
/// `PersistentModel` struct, like `RSSArticleStateRecord`.
private struct RSSFeedRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillNetNewsWireCore.RSSFeedRecord"

    var id: String
    var title: String
    var url: String
    var sortIndex: Int

    init(id: String, title: String, url: String, sortIndex: Int) {
        self.id = id
        self.title = title
        self.url = url
        self.sortIndex = sortIndex
    }
}

/// SQLite-backed store for the reader's subscribed feed list, built on the
/// vendored `QuillData` ORM — the sibling of `RSSReadStateStore`. `DefaultFeedList`
/// is only a first-run seed; once a list is persisted (e.g. after an OPML
/// import), it's the source of truth across launches.
public final class RSSFeedListStore {
    private let context: ModelContext

    /// Default on-disk location: `~/.quillui/netnewswire/feeds.sqlite`,
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
        return baseURL.appendingPathComponent("feeds.sqlite")
    }

    public init(url: URL) throws {
        let schema = Schema([RSSFeedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    /// Load the persisted subscription list in its saved order.
    public func load() throws -> [Feed] {
        try context.fetch(FetchDescriptor<RSSFeedRecord>(sortBy: [SortDescriptor(\.sortIndex)]))
            .map { Feed(id: $0.id, title: $0.title, url: $0.url) }
    }

    /// Replace the whole persisted list, preserving the given order.
    public func replaceAll(_ feeds: [Feed]) throws {
        try context.delete(model: RSSFeedRecord.self)
        for (index, feed) in feeds.enumerated() {
            context.insert(RSSFeedRecord(id: feed.id, title: feed.title, url: feed.url, sortIndex: index))
        }
        try context.save()
    }
}
