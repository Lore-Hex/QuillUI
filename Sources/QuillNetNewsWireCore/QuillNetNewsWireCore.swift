import Foundation
import QuillFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif
import QuillUI

/// Quill NetNewsWire content view — a self-contained RSS reader.
///
/// The upstream `Ranchero-Software/NetNewsWire` modules (`RSParser`,
/// `RSCore`, `Account`, `Articles`, etc.) compile only on macOS
/// (their `Mac/` UI tree imports AppKit while their `Shared/`
/// references `Mac/`-only types like `AppDefaults`, `Browser`,
/// `Node`, `appDelegate`). Wiring them as path-based SwiftPM
/// targets fails with ~1655 unresolved symbols on macOS and
/// Linux refuses to compile the Objective-C `RSDatabaseObjC`
/// /`RSCoreObjC` modules against swift-corelibs-foundation at all.
///
/// Until those pieces are decoupled, render a self-contained
/// reader: `URLSession`-fetched feed bytes parsed by Foundation's
/// built-in `XMLParser` into a minimal `RSSItem` model. Same
/// shape as the live-feed version that targeted upstream
/// `FeedParser.parse(_:)`; future slices can swap the local
/// parser back to upstream once `Shared`/`Mac` is split.
///
/// The type is main-actor isolated, while the `View.body`
/// witness remains nonisolated so SwiftOpenUI can instantiate it
/// from `WindowGroup` on Swift 6.2 Linux without tripping
/// isolated-conformance diagnostics.
@MainActor
public struct QuillNetNewsWireContentView: View {
    @StateObject private var model = RSSReaderModel()

    public init() {}

    /// Feed URL fed into refresh / initial load — derived from the
    /// model's currently-selected subscribed feed, with the historic
    /// Daring Fireball fallback kept so an empty subscription list
    /// still renders something.
    private var activeFeedURL: String {
        model.currentFeedURL ?? "https://daringfireball.net/feeds/main"
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            HStack(spacing: 0) {
                feedsPane
                    .frame(width: 220)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                Divider()
                sidebar
                    .frame(width: 300)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // `QUILLUI_DISABLE_FETCH=1` is a profile-mode escape
            // hatch: it seeds fixture content + skips URLSession,
            // so the Linux profile script can sample CPU on a
            // fetched-content-but-no-network path and isolate
            // whether the NetNewsWire CPU peg lives in the
            // URLSession / XMLParser / @Published path or in the
            // SwiftOpenUI render-loop after the list populates.
            .onAppear {
                let env = ProcessInfo.processInfo.environment
                if env["QUILLUI_DISABLE_FETCH"] == "1" {
                    model.seedProfileFixtures()
                } else {
                    Task { @MainActor in await model.loadIfNeeded(urlString: activeFeedURL) }
                }
            }
        }
    }

    private var feedsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Feeds")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.subscribedFeeds) { feed in
                        feedRow(feed)
                            .onTapGesture {
                                Task { @MainActor in await model.selectFeed(id: feed.id) }
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 18)
            }
        }
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func feedRow(_ feed: Feed) -> some View {
        Text(feed.title)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(model.selectedFeedID == feed.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
            .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
            .contentShape(Rectangle())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quill NetNewsWire").font(.title2).bold()
                Text(model.feedTitle ?? "Loading…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(14)

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(14)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.rows) { item in
                        articleRow(item)
                            .onTapGesture {
                                model.selectItem(id: item.id)
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 18)
            }

            footerStatus
        }
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func articleRow(_ item: RSSArticleRow) -> some View {
        let isUnread = !model.isRead(id: item.id)
        let isStarred = model.isStarred(id: item.id)
        return HStack(alignment: .top, spacing: 6) {
            // Unread indicator: an upstream-NetNewsWire-style filled
            // circle in the leading gutter. Reserves the same width
            // even when read so titles don't shift on mark-as-read.
            Text(isUnread ? "•" : " ")
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(width: 10, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(isUnread ? .bold : .regular)
                        .lineLimit(2)
                        .frame(width: isStarred ? 226 : 244, alignment: .leading)
                    if isStarred {
                        Text("★")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .frame(width: 14, alignment: .trailing)
                    }
                }
                if !item.publishedSummary.isEmpty {
                    Text(item.publishedSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 244, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 74, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedID == item.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    private var footerStatus: some View {
        HStack(spacing: 8) {
            Text(model.statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button(model.isLoading ? "Refreshing…" : "Refresh") {
                Task { @MainActor in await model.refresh(urlString: activeFeedURL) }
            }
            .font(.caption2)
            .disabled(model.isLoading)
        }
        .padding(10)
    }

    private var detail: some View {
        Group {
            if let item = model.selectedDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.title).font(.title).bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // Star toggle in the detail header. A
                            // filled glyph when starred, hollow when
                            // not — same affordance as upstream
                            // NetNewsWire's toolbar star button.
                            Button(model.isStarred(id: item.id) ? "★" : "☆") {
                                model.toggleStarred(id: item.id)
                            }
                            .font(.title2)
                        }
                        if !item.publishedSummary.isEmpty {
                            Text(item.publishedSummary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        Text(item.plainTextBody)
                            .font(.body)
                            .lineSpacing(4)
                        if let url = item.linkURL {
                            Divider()
                            // SwiftOpenUI's `Link` takes `destination: String`;
                            // Apple's SwiftUI takes `destination: URL`. Branch
                            // so the same view body compiles on both backends.
                            #if os(Linux)
                            Link("Open in browser  →", destination: url.absoluteString)
                                .font(.callout)
                            #else
                            Link("Open in browser  →", destination: url)
                                .font(.callout)
                            #endif
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(QuillDesktopChromeStyle.detailBackground)
            } else {
                VStack(spacing: 12) {
                    Text("Select an article")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Self-contained RSS reader is fetching live items from \(activeFeedURL).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(QuillDesktopChromeStyle.detailBackground)
            }
        }
    }
}

// MARK: - Reader model + minimal RSS 2.0 parser

public struct RSSItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let link: String?
    public let pubDate: String?
    public let descriptionHTML: String?
    public let linkURL: URL?
    public let publishedSummary: String
    public let plainTextBody: String

    public init(
        id: String,
        title: String,
        link: String?,
        pubDate: String?,
        descriptionHTML: String?
    ) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.descriptionHTML = descriptionHTML
        self.linkURL = link.flatMap { URL(string: $0) }
        self.publishedSummary = pubDate ?? ""
        self.plainTextBody = (descriptionHTML ?? "").stripBasicHTML()
    }
}

public struct RSSArticleRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let publishedSummary: String

    public init(id: String, title: String, publishedSummary: String) {
        self.id = id
        self.title = title
        self.publishedSummary = publishedSummary
    }

    public init(item: RSSItem) {
        self.init(id: item.id, title: item.title, publishedSummary: item.publishedSummary)
    }
}

public struct RSSArticleDetail: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let publishedSummary: String
    public let plainTextBody: String
    public let linkURL: URL?

    public init(
        id: String,
        title: String,
        publishedSummary: String,
        plainTextBody: String,
        linkURL: URL?
    ) {
        self.id = id
        self.title = title
        self.publishedSummary = publishedSummary
        self.plainTextBody = plainTextBody
        self.linkURL = linkURL
    }

    public init(item: RSSItem) {
        self.init(
            id: item.id,
            title: item.title,
            publishedSummary: item.publishedSummary,
            plainTextBody: item.plainTextBody,
            linkURL: item.linkURL
        )
    }
}

/// A subscribed feed: just enough metadata to drive a sidebar
/// row + an URL the reader can fetch on selection. Upstream
/// NetNewsWire's `Account`/`Feed` model carries far more (sync
/// state, folder hierarchy, favicon, settings, etc.); this
/// type is the minimum slice that lets the Quill reader hold
/// more than one subscription. Future iterations grow the
/// type alongside the sidebar UI and persistence layers.
public struct Feed: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: String

    public init(id: String, title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }

    public init(title: String, url: String) {
        self.init(id: url, title: title, url: url)
    }
}

public enum DefaultFeedList {
    /// Initial subscription list seeded when no persisted list
    /// exists. Mirrors what an upstream NetNewsWire fresh
    /// install used to ship in its bundled OPML: a handful of
    /// widely-followed dev/news feeds so the timeline isn't
    /// empty on first launch.
    public static let seed: [Feed] = [
        Feed(title: "Daring Fireball", url: "https://daringfireball.net/feeds/main"),
        Feed(title: "Swift.org Blog", url: "https://www.swift.org/atom.xml"),
        Feed(title: "Hacker News Front Page", url: "https://hnrss.org/frontpage"),
        Feed(title: "NetNewsWire Blog", url: "https://netnewswire.blog/feed/"),
    ]
}

@MainActor
final class RSSReaderModel: ObservableObject {
    @Published var items: [RSSItem] = [] {
        didSet {
            updateRows()
            updateSelectedItem()
            updateStatusText()
        }
    }
    @Published var feedTitle: String?
    @Published var error: String? {
        didSet { updateStatusText() }
    }
    @Published var isLoading = false {
        didSet { updateStatusText() }
    }
    @Published var selectedID: String? {
        didSet { updateSelectedItem() }
    }
    @Published private(set) var selectedItem: RSSItem?
    @Published private(set) var rows: [RSSArticleRow] = []
    @Published private(set) var selectedDetail: RSSArticleDetail?
    @Published private(set) var statusText = "0 items"

    /// Set of article IDs the user has read. Held in memory only
    /// for now; the persistence iteration will back this with
    /// QuillData/SQLite so reads survive relaunches. Stored as a
    /// flat set rather than per-feed so a re-fetched article keeps
    /// its read state across feed-list refreshes — same shape as
    /// upstream NetNewsWire's `articleIDs` read-status table.
    @Published private(set) var readArticleIDs: Set<String> = [] {
        didSet { updateStatusText() }
    }

    /// Set of starred article IDs. Same flat-set shape as
    /// readArticleIDs; will share its persistence backend in the
    /// SQLite iteration. Upstream NetNewsWire surfaces starred
    /// articles via the Starred smart feed and a per-article
    /// star toggle in the detail header.
    @Published private(set) var starredArticleIDs: Set<String> = []

    /// Multi-feed subscription list. Single-feed callers can
    /// ignore this and keep using `fetch(urlString:)` directly;
    /// the three-pane sidebar iteration will drive selection
    /// through `selectedFeedID`.
    @Published var subscribedFeeds: [Feed]
    @Published var selectedFeedID: Feed.ID?

    private var didStartInitialLoad = false
    private let initialSelectionEnvironment: [String: String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        subscribedFeeds: [Feed] = DefaultFeedList.seed
    ) {
        self.initialSelectionEnvironment = environment
        self.subscribedFeeds = subscribedFeeds
        self.selectedFeedID = subscribedFeeds.first?.id
    }

    /// URL of the currently-selected subscribed feed. `nil` when
    /// the list is empty or the selection has been cleared.
    var currentFeedURL: String? {
        guard let selectedFeedID else { return subscribedFeeds.first?.url }
        return subscribedFeeds.first(where: { $0.id == selectedFeedID })?.url
            ?? subscribedFeeds.first?.url
    }

    /// Switch the active feed and re-fetch. Clears the in-flight
    /// item selection so the timeline doesn't keep a stale article
    /// highlighted across feed switches. No-op when the user taps
    /// the already-selected feed.
    func selectFeed(id: Feed.ID) async {
        guard id != selectedFeedID else { return }
        guard let feed = subscribedFeeds.first(where: { $0.id == id }) else { return }
        selectedFeedID = id
        selectItem(id: nil)
        didStartInitialLoad = true
        await fetch(urlString: feed.url)
    }

    /// Import an OPML subscription list and merge it into
    /// `subscribedFeeds`. Existing subscriptions (matched by
    /// xmlUrl, since `Feed.id` defaults to the URL) are kept;
    /// only feeds whose URL is not already in the list get
    /// appended. Returns the number of newly-added feeds so a UI
    /// can surface "Imported N feeds".
    @discardableResult
    func importOPML(data: Data) -> Int {
        let result = OPMLImporter.parse(data: data)
        return mergeImportedFeeds(result.feeds)
    }

    @discardableResult
    func importOPML(xml: String) -> Int {
        importOPML(data: Data(xml.utf8))
    }

    /// Internal merge step kept separate so future iterations
    /// (folder grouping, sync round-trip) can reuse the dedupe
    /// path without re-parsing.
    @discardableResult
    func mergeImportedFeeds(_ imported: [Feed]) -> Int {
        let existing = Set(subscribedFeeds.map(\.id))
        var added = 0
        for feed in imported where !existing.contains(feed.id) {
            subscribedFeeds.append(feed)
            added += 1
        }
        if selectedFeedID == nil {
            selectedFeedID = subscribedFeeds.first?.id
        }
        return added
    }

    /// Profile-mode bypass: populate `items` + `feedTitle` with
    /// fixture content so the rendered timeline has shape, then
    /// skip the URLSession round-trip entirely. Used by the
    /// `QUILLUI_DISABLE_FETCH=1` path in `onAppear` so the
    /// Linux profile script can isolate URLSession-cost vs
    /// render-loop-cost.
    func seedProfileFixtures() {
        guard !didStartInitialLoad || items.isEmpty else { return }
        didStartInitialLoad = true
        setFeedTitle("Profile Fixture Feed")
        setItems(Self.profileFixtureItems)
        selectItem(id: preferredInitialItemID(in: items))
        setError(nil)
        setLoading(false)
    }

    func loadIfNeeded(urlString: String) async {
        guard !didStartInitialLoad else { return }
        didStartInitialLoad = true
        await fetch(urlString: urlString)
    }

    /// User-triggered refresh. Unlike `loadIfNeeded(urlString:)` this
    /// always re-fetches, even if the initial load has already run.
    /// No-op while a load is already in flight so rapid Refresh clicks
    /// don't pile up overlapping URLSession tasks.
    func refresh(urlString: String) async {
        guard !isLoading else { return }
        didStartInitialLoad = true
        await fetch(urlString: urlString)
    }

    func fetch(urlString: String) async {
        guard let url = URL(string: urlString) else {
            setError("Invalid URL")
            setLoading(false)
            return
        }
        setLoading(true)
        setError(nil)
        do {
            var request = URLRequest(url: url)
            request.setValue("Quill-NetNewsWire/0.1", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let parsed = RSSFeedParser.parse(data: data)
            self.setFeedTitle(parsed.title)
            self.setItems(Array(parsed.items.prefix(50)))
            if self.selectedID == nil {
                self.selectItem(id: self.preferredInitialItemID(in: self.items))
            }
        } catch {
            self.setError("\(error)")
        }
        setLoading(false)
    }

    func selectItem(id: String?) {
        if selectedID != id {
            selectedID = id
        }
        if let id { markRead(id: id) }
    }

    /// Mark an article as read. Idempotent; firing the didSet on
    /// `readArticleIDs` only when the set actually grows so we
    /// don't bounce statusText for every redundant tap.
    func markRead(id: String) {
        if readArticleIDs.insert(id).inserted {
            // didSet on readArticleIDs handles status text refresh.
        }
    }

    /// Toggle read state on the currently-selected article. Wired
    /// to a future keyboard shortcut + a Mark Unread menu item.
    func toggleReadOnSelection() {
        guard let selectedID else { return }
        if readArticleIDs.contains(selectedID) {
            readArticleIDs.remove(selectedID)
        } else {
            readArticleIDs.insert(selectedID)
        }
    }

    func isRead(id: String) -> Bool {
        readArticleIDs.contains(id)
    }

    func isStarred(id: String) -> Bool {
        starredArticleIDs.contains(id)
    }

    /// Toggle starred state for any article ID. Used by the
    /// detail-pane star button and (later) the S keyboard
    /// shortcut. Mirrors readArticleIDs' insert-or-remove shape.
    func toggleStarred(id: String) {
        if starredArticleIDs.contains(id) {
            starredArticleIDs.remove(id)
        } else {
            starredArticleIDs.insert(id)
        }
    }

    /// Toggle starred state on the currently-selected article.
    /// No-op when nothing is selected.
    func toggleStarredOnSelection() {
        guard let selectedID else { return }
        toggleStarred(id: selectedID)
    }

    /// Count of starred items in the currently-loaded timeline.
    /// Doesn't yet aggregate across feeds (the smart-feed iteration
    /// will introduce a separate fetch-all-starred view).
    var starredCount: Int {
        items.reduce(0) { acc, item in
            acc + (starredArticleIDs.contains(item.id) ? 1 : 0)
        }
    }

    /// Number of items currently loaded that the user has not yet
    /// read. Excludes items from feeds not currently fetched (read
    /// status is global, but the count is per loaded timeline).
    var unreadCount: Int {
        items.reduce(0) { acc, item in
            acc + (readArticleIDs.contains(item.id) ? 0 : 1)
        }
    }

    private func updateSelectedItem() {
        let item = selectedID.flatMap { selectedID in items.first(where: { $0.id == selectedID }) }
        if selectedItem != item {
            selectedItem = item
        }
        let detail = item.map(RSSArticleDetail.init(item:))
        if selectedDetail != detail {
            selectedDetail = detail
        }
    }

    private func updateRows() {
        let nextRows = items.map(RSSArticleRow.init(item:))
        if rows != nextRows {
            rows = nextRows
        }
    }

    private func updateStatusText() {
        let nextStatusText: String
        if isLoading {
            nextStatusText = "Fetching feed…"
        } else if let error {
            nextStatusText = "Error: \(error)"
        } else {
            let unread = unreadCount
            if unread == 0 {
                nextStatusText = "\(items.count) items"
            } else {
                nextStatusText = "\(unread) unread · \(items.count) items"
            }
        }
        if statusText != nextStatusText {
            statusText = nextStatusText
        }
    }

    private func preferredInitialItemID(in items: [RSSItem]) -> RSSItem.ID? {
        QuillNetNewsWireInitialSelection.selectedFeedID(
            in: items,
            environment: initialSelectionEnvironment
        ) ?? items.first?.id
    }

    private func setItems(_ newItems: [RSSItem]) {
        if items != newItems {
            items = newItems
        } else {
            updateRows()
            updateSelectedItem()
            updateStatusText()
        }
    }

    private func setFeedTitle(_ newTitle: String?) {
        if feedTitle != newTitle {
            feedTitle = newTitle
        }
    }

    private func setError(_ newError: String?) {
        if error != newError {
            error = newError
        }
    }

    private func setLoading(_ newIsLoading: Bool) {
        if isLoading != newIsLoading {
            isLoading = newIsLoading
        }
    }

    private static let profileFixtureItems: [RSSItem] = [
        RSSItem(
            id: "1",
            title: "Profile fixture article 1",
            link: "https://example.test/1",
            pubDate: "2026-01-01",
            descriptionHTML: "<p>Body of the first fixture article.</p>"
        ),
        RSSItem(
            id: "2",
            title: "Profile fixture article 2",
            link: "https://example.test/2",
            pubDate: "2026-01-02",
            descriptionHTML: "<p>Body of the second fixture article.</p>"
        ),
        RSSItem(
            id: "3",
            title: "Swift.org toolchain update",
            link: "https://example.test/3",
            pubDate: "2026-01-03",
            descriptionHTML: "<p>Compiler and package manager notes for Linux app smoke runs.</p>"
        ),
        RSSItem(
            id: "4",
            title: "Point-Free dependency release",
            link: "https://example.test/4",
            pubDate: "2026-01-04",
            descriptionHTML: "<p>Dependency injection notes and performance guardrails.</p>"
        ),
        RSSItem(
            id: "5",
            title: "Linux backend smoke notes",
            link: "https://example.test/5",
            pubDate: "2026-01-05",
            descriptionHTML: "<p>Fixture article used to keep GTK and Qt row selection checks deterministic.</p>"
        ),
    ]
}

public enum QuillNetNewsWireInitialSelection {
    public static let selectedFeedIndexEnvironmentKey = "QUILLUI_NETNEWSWIRE_SELECTED_FEED_INDEX_ON_START"

    public static func selectedFeedID(
        in items: [RSSItem],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RSSItem.ID? {
        QuillInitialSelection.selectedID(
            in: items,
            environmentKeys: [selectedFeedIndexEnvironmentKey],
            environment: environment
        )
    }
}

/// Minimal RSS 2.0 + Atom parser backed by `Foundation.XMLParser`.
/// Captures `title`, `link`, `pubDate`/`updated`, and
/// `description`/`content` per item — enough to drive the
/// reader's sidebar list and detail pane.
///
/// Internal (not private) so QuillNetNewsWireCoreTests can pin
/// the parse behavior via `@testable import` without going
/// through `URLSession`.
struct RSSFeedParser {
    struct Result: Equatable {
        var title: String?
        var items: [RSSItem] = []
    }

    static func parse(data: Data) -> Result {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return Result(title: delegate.feedTitle, items: delegate.items)
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var feedTitle: String?
        var items: [RSSItem] = []

        private var path: [String] = []
        private var inItem = false
        private var currentTitle = ""
        private var currentLink = ""
        private var currentDate = ""
        private var currentDescription = ""
        private var buffer = ""

        /// The element that contains the one we just finished —
        /// used to scope the feed-level `<title>` lookup (RSS
        /// channels nest title under `<channel>`, Atom feeds
        /// nest it under `<feed>`). On end-element the path
        /// still includes the element we're closing, so the
        /// parent is `path.dropLast().last`.
        private var parentElement: String? {
            path.dropLast().last
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            path.append(elementName)
            buffer = ""
            if elementName == "item" || elementName == "entry" {
                inItem = true
                currentTitle = ""
                currentLink = ""
                currentDate = ""
                currentDescription = ""
            }
            if inItem && elementName == "link" {
                if let href = attributeDict["href"] {
                    currentLink = href
                }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if let text = String(data: CDATABlock, encoding: .utf8) {
                buffer += text
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if inItem {
                switch elementName {
                case "title": currentTitle = trimmed
                case "link" where currentLink.isEmpty: currentLink = trimmed
                case "pubDate", "updated", "published": currentDate = trimmed
                case "description", "summary", "content:encoded": currentDescription = trimmed
                case "item", "entry":
                    let id = !currentLink.isEmpty ? currentLink : (currentTitle + currentDate)
                    items.append(RSSItem(
                        id: id,
                        title: currentTitle.isEmpty ? "Untitled" : currentTitle,
                        link: currentLink.isEmpty ? nil : currentLink,
                        pubDate: currentDate.isEmpty ? nil : currentDate,
                        descriptionHTML: currentDescription.isEmpty ? nil : currentDescription
                    ))
                    inItem = false
                default: break
                }
            } else if elementName == "title", parentElement == "channel" || parentElement == "feed" {
                if feedTitle == nil { feedTitle = trimmed }
            }
            buffer = ""
            if !path.isEmpty { path.removeLast() }
        }
    }
}

private extension String {
    func stripBasicHTML() -> String {
        let withoutTags = self.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return HTMLEntities.decode(withoutTags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
