import Foundation
import QuillData

/// Thin wrapper over QuillData's ModelContainer + ModelContext
/// for the article persistence layer. Lets RSSReaderModel
/// stash PersistentArticle rows and query them back without
/// touching the SwiftData-shaped surface directly.
///
/// The store is intentionally minimal — it owns one
/// ModelContainer for the lifetime of the wrapper and creates
/// a fresh ModelContext per call. That matches QuillData's
/// usage pattern (ModelContext is the per-call mutation
/// surface; the container holds the SQLite handle). Per-call
/// context avoids cross-call state bleed and keeps the API
/// re-entrant.
public final class ArticleStore: @unchecked Sendable {

    private let container: ModelContainer

    /// Create an article store backed by SQLite on disk under
    /// `directoryURL/articles.sqlite`, or fully in-memory when
    /// directoryURL is nil (tests + ephemeral runs).
    public init(directoryURL: URL? = nil) throws {
        let schema = Schema([PersistentArticle.self])
        let configuration: ModelConfiguration
        if let directoryURL {
            // QuillData's SQLite store creates the file alongside
            // its other persistence; we pass an explicit URL so
            // multiple stores (article, sync, etc.) can sit in
            // the same directory.
            try? FileManager.default.createDirectory(
                at: directoryURL, withIntermediateDirectories: true, attributes: nil
            )
            configuration = ModelConfiguration(
                schema: schema,
                url: directoryURL.appendingPathComponent("articles.sqlite")
            )
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        self.container = try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Upsert a batch of articles. Existing rows with the same
    /// id get overwritten with the new payload; new rows get
    /// inserted. Saves once at the end so the SQLite write
    /// batches as a single transaction.
    public func upsert(_ articles: [PersistentArticle]) throws {
        let context = ModelContext(container)
        for article in articles {
            // QuillData ModelContext.insert is upsert-ish:
            // insert with the same identity replaces. The
            // generated migration writes by id key.
            context.insert(article)
        }
        try context.save()
    }

    /// Fetch every article currently persisted, newest-first
    /// by datePublished (nil dates sort last).
    public func fetchAll() throws -> [PersistentArticle] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>()
        let rows = try context.fetch(descriptor)
        return rows.sorted(by: Self.newestFirst)
    }

    /// Fetch articles for one feedID, newest-first.
    public func fetch(forFeed feedID: String) throws -> [PersistentArticle] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.feedID == feedID }
        )
        let rows = try context.fetch(descriptor)
        return rows.sorted(by: Self.newestFirst)
    }

    /// Fetch every starred article across all feeds. Used by
    /// the Starred smart feed so the count + timeline reflect
    /// the user's full star history, not just what happens to
    /// still be in the per-feed cache (articlesPerFeedLimit caps
    /// at 100, so a year of starring would silently drop
    /// older entries from the in-memory view).
    public func fetchStarred() throws -> [PersistentArticle] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.isStarred == true }
        )
        let rows = try context.fetch(descriptor)
        return rows.sorted(by: Self.newestFirst)
    }

    /// Fetch every unread article across all feeds. Symmetric
    /// to fetchStarred — used by the All Unread smart feed so
    /// it spans full SQLite history rather than just the
    /// articlesPerFeedLimit-bounded cache slice.
    public func fetchUnread() throws -> [PersistentArticle] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.isRead == false }
        )
        let rows = try context.fetch(descriptor)
        return rows.sorted(by: Self.newestFirst)
    }

    /// Cheap row-counts for the sidebar smart-feed badges, used
    /// when the full row list would be wasted (caller only
    /// needs the count, not the data). Skips the in-memory
    /// sort+map that the full fetch* does.
    public func countStarred() throws -> Int {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.isStarred == true }
        )
        return try context.fetch(descriptor).count
    }

    public func countUnread() throws -> Int {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.isRead == false }
        )
        return try context.fetch(descriptor).count
    }

    /// Mark a single article read (idempotent — re-marking is
    /// a no-op write). Bumps the row's existing isRead bit
    /// without losing any other field.
    public func markRead(articleID: String) throws {
        try markRead(articleID: articleID, read: true)
    }

    /// Set a single article's isRead bit explicitly (true /
    /// false). Bool overload added so the model can persist
    /// mark-as-unread mutations — the old API only flipped
    /// to true.
    public func markRead(articleID: String, read: Bool) throws {
        try mutate(articleID: articleID) { row in
            row.isRead = read
        }
    }

    /// Set isRead by uniqueID (the upstream article identifier
    /// the model's readArticleIDs set carries) rather than the
    /// PersistentArticle.id. Used when the model's in-memory
    /// cache doesn't have the article (e.g. row aged out of
    /// articlesPerFeedLimit but is still in SQLite). Without
    /// this, marking SQLite-only stored-unread articles as read
    /// would leave the SQLite isRead bit stale.
    public func markReadByUniqueID(_ uniqueID: String, read: Bool) throws {
        try mutateByUniqueID(uniqueID) { row in
            row.isRead = read
        }
    }

    /// Symmetric to markReadByUniqueID for the starred bit.
    public func markStarredByUniqueID(_ uniqueID: String, starred: Bool) throws {
        try mutateByUniqueID(uniqueID) { row in
            row.isStarred = starred
        }
    }

    /// Same delete-+-reinsert dance as `mutate` but keyed by
    /// uniqueID (the upstream article identifier) instead of
    /// the SwiftData row id.
    private func mutateByUniqueID(_ uniqueID: String, _ apply: (inout PersistentArticle) -> Void) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.uniqueID == uniqueID }
        )
        guard var row = try context.fetch(descriptor).first else { return }
        context.delete(row)
        apply(&row)
        context.insert(row)
        try context.save()
    }

    public func markStarred(articleID: String, starred: Bool) throws {
        try mutate(articleID: articleID) { row in
            row.isStarred = starred
        }
    }

    /// Delete every row belonging to a feed. Called from
    /// RSSReaderModel.removeSubscription so the SQLite store
    /// doesn't carry articles for feeds the user has unsub-
    /// scribed (they'd otherwise re-hydrate into feedCaches on
    /// next launch and resurface in smart-feed / search views).
    public func deleteForFeed(_ feedID: String) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.feedID == feedID }
        )
        let rows = try context.fetch(descriptor)
        for row in rows {
            context.delete(row)
        }
        try context.save()
    }

    /// Generic single-row mutation helper. Fetches the existing
    /// row (if any), applies the closure, persists.
    private func mutate(articleID: String, _ apply: (inout PersistentArticle) -> Void) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<PersistentArticle>(
            filter: { $0.id == articleID }
        )
        let rows = try context.fetch(descriptor)
        guard var row = rows.first else { return }
        // Delete + reinsert so QuillData's value-store layer
        // sees the change (ModelContext doesn't reach into
        // value-type mutations through fetched references).
        // ModelContext.delete is non-throwing on QuillData;
        // upstream SwiftData's is also non-throwing.
        context.delete(row)
        apply(&row)
        context.insert(row)
        try context.save()
    }

    private static func newestFirst(_ lhs: PersistentArticle, _ rhs: PersistentArticle) -> Bool {
        switch (lhs.datePublished, rhs.datePublished) {
        case let (l?, r?) where l != r: return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.id < rhs.id
        }
    }
}
