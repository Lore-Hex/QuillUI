import Foundation
import QuillData

/// One article's persisted read/starred flags, keyed by the stable article ID.
/// A plain `PersistentModel` struct (no `@Model` macro needed) — the same
/// shape Enchanted's QuillData records use.
private struct RSSArticleStateRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillNetNewsWireCore.RSSArticleStateRecord"

    var id: String          // article ID (RSS guid / synthesized)
    var isRead: Bool
    var isStarred: Bool

    init(id: String, isRead: Bool, isStarred: Bool) {
        self.id = id
        self.isRead = isRead
        self.isStarred = isStarred
    }
}

/// SQLite-backed store for the reader's read/starred article state, built on
/// the vendored `QuillData` ORM (the same persistence layer Enchanted uses).
/// This is the on-disk shape behind `RSSReaderModel`'s in-memory read/starred
/// sets so they survive relaunches — the "persistence iteration" the model
/// has been anticipating. (Wiring it into the model is a follow-up; this lands
/// and tests the store in isolation.)
public final class RSSReadStateStore {
    private let context: ModelContext

    /// Default on-disk location: `~/.quillui/netnewswire/read-state.sqlite`,
    /// honoring `QUILLDATA_HOME` / `HOME` overrides like Enchanted's store.
    public static func defaultURL() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let home = env["QUILLDATA_HOME"] ?? env["HOME"]
        let homeURL = home.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let baseURL = homeURL
            .appendingPathComponent(".quillui", isDirectory: true)
            .appendingPathComponent("netnewswire", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("read-state.sqlite")
    }

    public init(url: URL) throws {
        let schema = Schema([RSSArticleStateRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    /// Load all persisted state into read / starred ID sets.
    public func load() throws -> (read: Set<String>, starred: Set<String>) {
        let records = try context.fetch(FetchDescriptor<RSSArticleStateRecord>())
        var read: Set<String> = []
        var starred: Set<String> = []
        for record in records {
            if record.isRead { read.insert(record.id) }
            if record.isStarred { starred.insert(record.id) }
        }
        return (read, starred)
    }

    /// Upsert one article's flags. `insert` is keyed by `id`, so this
    /// overwrites any existing row for the article.
    public func setState(articleID: String, isRead: Bool, isStarred: Bool) throws {
        context.insert(RSSArticleStateRecord(id: articleID, isRead: isRead, isStarred: isStarred))
        try context.save()
    }

    /// Replace the entire persisted state with the given sets in one batch —
    /// for bulk actions like Mark All as Read. Only articles with at least one
    /// set flag are stored.
    public func replaceAll(read: Set<String>, starred: Set<String>) throws {
        try context.delete(model: RSSArticleStateRecord.self)
        for id in read.union(starred) {
            context.insert(RSSArticleStateRecord(id: id, isRead: read.contains(id), isStarred: starred.contains(id)))
        }
        try context.save()
    }
}
