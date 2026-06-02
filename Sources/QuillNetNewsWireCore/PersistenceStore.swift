import Foundation

/// JSON-backed persistence for `RSSReaderModel`'s read +
/// starred article ID sets. Today's scope is intentionally
/// small — just the two Set<String> values the model already
/// observes — so launches retain a user's mark-as-read /
/// star history without pulling in the full SQLite +
/// FMDatabase upstream stack. The feedCaches + subscribedFeeds
/// persistence lands once `Article` gets a Codable conformance
/// in a follow-up iteration.
///
/// Files are written to the user's Application Support directory
/// (or a caller-supplied URL for tests) one per state set:
///
///   <AppSupport>/Quill/NetNewsWire/readArticleIDs.json
///   <AppSupport>/Quill/NetNewsWire/starredArticleIDs.json
///
/// Both files hold a JSON array of strings. Missing or
/// unreadable files load to an empty set (first launch). Save
/// failures are silently swallowed so a flaky disk doesn't
/// crash the reader — a future Settings UI can surface them.
public struct PersistenceStore: Sendable {

    /// Override directory for tests.
    public let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Default singleton rooted at `<AppSupport>/Quill/NetNewsWire`.
    /// Under XCTest / swift-testing the directory routes to a
    /// per-process tempdir instead so test runs don't share
    /// (or corrupt) the real reader's persisted state.
    public static var `default`: PersistenceStore {
        let env = ProcessInfo.processInfo.environment
        // Match QuillRSCoreShim.Platform.isRunningUnitTests's
        // multi-path detection: env signal first, then the
        // arguments[0] basename used by `swift test` (which
        // doesn't set either env var on Apple).
        var isTestRunner =
            env["XCTestConfigurationFilePath"] != nil ||
            env["SWIFT_TESTING_ENABLED"] != nil
        if !isTestRunner, let arg0 = CommandLine.arguments.first {
            let base = (arg0 as NSString).lastPathComponent
            if base.contains("xctest") || base.contains("testing-helper") {
                isTestRunner = true
            }
        }
        if isTestRunner {
            // Unique-per-instance tempdir so tests within the
            // same process don't share persisted state. Tests
            // that explicitly want to verify persistence pass
            // their own PersistenceStore(directoryURL:) and
            // use it across multiple inits.
            return PersistenceStore(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "quill-nnw-test-\(UUID().uuidString)",
                        isDirectory: true
                    )
            )
        }
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            base = FileManager.default.temporaryDirectory
        }
        let dir = base.appendingPathComponent("Quill/NetNewsWire", isDirectory: true)
        return PersistenceStore(directoryURL: dir)
    }

    public func loadReadArticleIDs() -> Set<String> {
        loadStringSet(named: "readArticleIDs.json")
    }

    public func saveReadArticleIDs(_ ids: Set<String>) {
        saveStringSet(ids, named: "readArticleIDs.json")
    }

    public func loadStarredArticleIDs() -> Set<String> {
        loadStringSet(named: "starredArticleIDs.json")
    }

    public func saveStarredArticleIDs(_ ids: Set<String>) {
        saveStringSet(ids, named: "starredArticleIDs.json")
    }

    /// Write an OPML 2.0 export to a fixed file under the store
    /// directory. Returns the URL on success, nil if the disk
    /// write failed. Callers should hold the returned URL and
    /// surface it in the UI (open-in-Finder, copy-path, share).
    @discardableResult
    public func saveOPMLExport(_ data: Data) -> URL? {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("subscriptions.opml")
        guard (try? data.write(to: url, options: .atomic)) != nil else {
            return nil
        }
        return url
    }

    /// Load the subscriptions.opml file from the store
    /// directory if it exists. Returns nil when missing or
    /// unreadable — caller falls back to whatever default
    /// subscription seed it wants.
    public func loadOPMLExport() -> Data? {
        let url = directoryURL.appendingPathComponent("subscriptions.opml")
        return try? Data(contentsOf: url)
    }

    /// Per-feed icon URL persistence. Stored as a JSON object
    /// {feedID: iconURL} so the feedsPane can keep showing
    /// the right favicons across launches without re-fetching
    /// every feed first. Missing/unreadable file loads to an
    /// empty dict (first launch).
    public func loadFeedIconURLs() -> [String: String] {
        let url = directoryURL.appendingPathComponent("feedIconURLs.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public func saveFeedIconURLs(_ urls: [String: String]) {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("feedIconURLs.json")
        guard let data = try? JSONEncoder().encode(urls) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Per-feed error message persistence. Same shape as
    /// feedIconURLs — JSON object {feedID: errorMessage}.
    /// Persisting these lets the sidebar warning glyph survive
    /// across launches so users come back to "Feed X has been
    /// failing for a week" without losing the breadcrumb every
    /// restart. Cleared on next successful fetch.
    public func loadFeedErrors() -> [String: String] {
        let url = directoryURL.appendingPathComponent("feedErrors.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    public func saveFeedErrors(_ errors: [String: String]) {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("feedErrors.json")
        guard let data = try? JSONEncoder().encode(errors) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Per-feed consecutive-failure counter — same shape as
    /// feedErrors / feedIconURLs but typed Int. Persisting lets
    /// back-off state survive relaunch so a definitively-dead
    /// feed doesn't get re-tried 5 times on every launch
    /// (which would defeat the back-off entirely for users who
    /// quit and relaunch frequently).
    public func loadFeedFailureCount() -> [String: Int] {
        let url = directoryURL.appendingPathComponent("feedFailureCount.json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    public func saveFeedFailureCount(_ counts: [String: Int]) {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("feedFailureCount.json")
        guard let data = try? JSONEncoder().encode(counts) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Persisted sidebar selection. Upstream NetNewsWire restores
    /// the last-selected feed (or smart feed) on launch so the
    /// reader resumes where the user left off. A pair of optional
    /// strings: one for a smart-feed kind ("today"/"allUnread"/
    /// "starred"), one for a subscribed-feed URL. Exactly one is
    /// non-nil when something is selected; both nil means no
    /// prior selection (first launch). The model applies the
    /// restored selection only when the referenced feed still
    /// exists — feeds removed since last launch fall back to
    /// the first subscription, matching upstream's behavior.
    public struct SelectionState: Codable, Equatable, Sendable {
        public var smartFeed: String?
        public var feedID: String?
        public init(smartFeed: String? = nil, feedID: String? = nil) {
            self.smartFeed = smartFeed
            self.feedID = feedID
        }
    }

    public func loadSelection() -> SelectionState? {
        let url = directoryURL.appendingPathComponent("selection.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SelectionState.self, from: data)
    }

    public func saveSelection(_ state: SelectionState) {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("selection.json")
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Per-user view options for the timeline. Starts small —
    /// just the "Hide Read Articles" toggle — but is a JSON
    /// blob so additional sort-order / density flags can land
    /// without bumping the on-disk format every iteration.
    public struct ViewOptions: Codable, Equatable, Sendable {
        public var hideReadArticles: Bool
        /// Timeline sort order. "newestFirst" (default) puts
        /// recent items at top; "oldestFirst" inverts. Stored as
        /// a string so future additions (date-arrived,
        /// date-modified) extend the enum without bumping the
        /// on-disk format.
        public var sortOrder: String?
        /// Background-refresh cadence in seconds. nil disables
        /// auto-refresh entirely (user can still hit Refresh).
        /// Missing field (old persisted file) decodes to nil so
        /// the model falls back to its built-in 30-minute default.
        public var refreshIntervalSeconds: TimeInterval?
        public init(
            hideReadArticles: Bool = false,
            sortOrder: String? = nil,
            refreshIntervalSeconds: TimeInterval? = nil
        ) {
            self.hideReadArticles = hideReadArticles
            self.sortOrder = sortOrder
            self.refreshIntervalSeconds = refreshIntervalSeconds
        }
    }

    public func loadViewOptions() -> ViewOptions {
        let url = directoryURL.appendingPathComponent("viewOptions.json")
        guard let data = try? Data(contentsOf: url) else { return ViewOptions() }
        return (try? JSONDecoder().decode(ViewOptions.self, from: data)) ?? ViewOptions()
    }

    public func saveViewOptions(_ options: ViewOptions) {
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent("viewOptions.json")
        guard let data = try? JSONEncoder().encode(options) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadStringSet(named filename: String) -> Set<String> {
        let url = directoryURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(array)
    }

    private func saveStringSet(_ set: Set<String>, named filename: String) {
        // Ensure the directory exists (first save on a fresh install).
        try? FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true, attributes: nil
        )
        let url = directoryURL.appendingPathComponent(filename)
        // Deterministic ordering so file diffs stay readable.
        let array = Array(set).sorted()
        guard let data = try? JSONEncoder().encode(array) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
