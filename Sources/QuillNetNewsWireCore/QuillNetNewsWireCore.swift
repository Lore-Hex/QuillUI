import Foundation
import QuillFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import QuillUI
import QuillRSParser
import QuillArticles

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
            VStack(spacing: 0) {
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
                // Hidden keyboard-shortcut surface. The buttons
                // are not visible but keep their shortcut
                // registrations live so single-key NetNewsWire
                // bindings work without focus management on
                // every row. Same pattern upstream apps use to
                // attach .keyboardShortcut to invisible action
                // buttons in the view tree.
                keyboardShortcutSurface
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
                    // Real-fetch path: persist read/starred + the subscribed
                    // feed list across launches. (Fixture mode above stays
                    // in-memory + deterministic.)
                    model.enablePersistence()
                    model.enableFeedPersistence()
                    Task { @MainActor in await model.loadIfNeeded(urlString: activeFeedURL) }
                    // Kick off the periodic auto-refresh Task.
                    // Skipped in profile/disable-fetch mode so the
                    // Linux profile script doesn't see URLSession
                    // traffic from the background timer.
                    model.startBackgroundRefresh()
                }
            }
        }
    }

    private var keyboardShortcutSurface: some View {
        HStack(spacing: 0) {
            Button("next") { model.selectNextItem() }
                .keyboardShortcut("j", modifiers: [])
            Button("prev") { model.selectPreviousItem() }
                .keyboardShortcut("k", modifiers: [])
            Button("read+next") { model.markReadAndAdvance() }
                .keyboardShortcut(.space, modifiers: [])
            Button("toggle starred") { model.toggleStarredOnSelection() }
                .keyboardShortcut("s", modifiers: [])
            Button("toggle read") { model.toggleReadOnSelection() }
                .keyboardShortcut("r", modifiers: [])
            Button("refresh") {
                Task { @MainActor in await model.refresh(urlString: activeFeedURL) }
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .frame(height: 0)
        .hidden()
    }

    private var feedsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Smart Feeds")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SmartFeed.allCases) { kind in
                    smartFeedRow(kind)
                        .onTapGesture {
                            model.selectSmartFeed(kind)
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            Text("Feeds")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
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

    /// NetNewsWire-style smart-feed icon: an orange calendar for
    /// Today, a blue unread dot for All Unread, a yellow filled
    /// star for Starred. Uses mapped SF Symbols (`calendar`,
    /// `star.fill`) so the GTK backend renders them too; All
    /// Unread is a `Circle` shape because the fork's Material map
    /// has no `circle.fill` glyph — and a blue dot reads as
    /// "unread" anyway.
    @ViewBuilder
    private func smartFeedIcon(_ kind: SmartFeed) -> some View {
        switch kind {
        case .today:
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundColor(.orange)
        case .allUnread:
            Circle()
                .fill(Color.blue)
                .frame(width: 9, height: 9)
        case .starred:
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundColor(.yellow)
        }
    }

    private func smartFeedRow(_ kind: SmartFeed) -> some View {
        let count = model.count(for: kind)
        return HStack(spacing: 8) {
            smartFeedIcon(kind)
                .frame(width: 16, alignment: .center)
            Text(kind.displayName)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedSmartFeed == kind ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    /// Favicon stand-in: a colored rounded tile with the feed's
    /// first initial. SwiftOpenUI has no remote-image view, so a
    /// monogram gives each feed a stable visual identity (like
    /// NetNewsWire's favicons) using only GTK-safe shapes + text.
    private func monogramTile(for feed: Feed) -> some View {
        let initial = feed.title.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.monogramColor(for: feed.title))
            Text(initial)
                .font(.caption2).bold()
                .foregroundColor(.white)
        }
        .frame(width: 18, height: 18)
    }

    /// Deterministic per-feed tint (NOT String.hashValue — that is
    /// randomized per process, so the color would change every
    /// launch). A stable scalar sum keeps a feed's monogram color
    /// constant across runs.
    private static func monogramColor(for title: String) -> Color {
        let palette: [Color] = [.blue, .orange, .green, .red, .purple, .gray]
        let h = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palette[h % palette.count]
    }

    private func feedRow(_ feed: Feed) -> some View {
        let isSelected = (model.selectedSmartFeed == nil) && (model.selectedFeedID == feed.id)
        let unread = model.unreadCount(forFeed: feed.id)
        return HStack(spacing: 8) {
            monogramTile(for: feed)
            Text(feed.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if unread > 0 {
                // Compact NetNewsWire-style unread badge. Only
                // the active feed shows a count today because the
                // model hasn't yet cached items for inactive
                // feeds — persistence iteration enables badges
                // for every subscription.
                Text("\(unread)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
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

            // Live timeline filter. Bound to model.searchQuery via an
            // explicit Binding(get:set:) rather than $model.searchQuery
            // because SwiftOpenUI on Linux does not synthesize the `$`
            // projected-value accessor for @StateObject members. The
            // explicit form compiles on both backends without a
            // platform branch. filteredRows is a computed view that
            // re-evaluates whenever items or searchQuery emit a
            // @Published change.
            TextField("Search articles", text: Binding(
                get: { model.searchQuery },
                set: { model.searchQuery = $0 }
            ))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(14)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.filteredRows) { item in
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
        return HStack(alignment: .top, spacing: 8) {
            // Unread indicator: a filled blue Circle (matches the
            // sidebar's All Unread dot). Always reserves width so
            // titles don't shift on mark-as-read; opacity hides it
            // when the article is read.
            Circle()
                .fill(Color.blue)
                .frame(width: 8, height: 8)
                .opacity(isUnread ? 1 : 0)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.subheadline)
                        .fontWeight(isUnread ? .bold : .regular)
                        .lineLimit(2)
                        .frame(width: isStarred ? 214 : 232, alignment: .leading)
                    if isStarred {
                        Text("★")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .frame(width: 14, alignment: .trailing)
                    }
                }
                // Two-line body preview, like NetNewsWire's timeline.
                if !item.snippet.isEmpty {
                    Text(item.snippet)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(width: 232, alignment: .leading)
                }
                if !item.timelineDateText.isEmpty {
                    Text(item.timelineDateText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 232, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(height: 96, alignment: .leading)
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
            // Mark All as Read (checkmark.circle), like NetNewsWire's toolbar
            // action; tinted blue when the timeline has unread items, gray
            // (a no-op) once everything is read.
            Image(systemName: "checkmark.circle")
                .font(.caption2)
                .foregroundColor(model.hasUnreadInTimeline ? .blue : .secondary)
                .contentShape(Rectangle())
                .onTapGesture { model.markAllRead() }
            // SF-Symbol refresh control (arrow.clockwise), like NetNewsWire's
            // toolbar refresh; grays out + ignores taps while a load is in
            // flight instead of a disabled text button.
            Image(systemName: "arrow.clockwise")
                .font(.caption2)
                .foregroundColor(model.isLoading ? .secondary : .blue)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !model.isLoading else { return }
                    Task { @MainActor in await model.refresh(urlString: activeFeedURL) }
                }
        }
        .padding(10)
    }

    private var detail: some View {
        Group {
            if let item = model.selectedDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Source row: feed name (colored) · author,
                        // with the star toggle pinned right. Mirrors
                        // NetNewsWire's article header.
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(model.feedTitle ?? "")
                                .font(.subheadline).bold()
                                .foregroundColor(.blue)
                                .lineLimit(1)
                            if let author = item.author, !author.isEmpty {
                                Text("·").foregroundColor(.secondary)
                                Text(author)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            // Previous / next article — like NetNewsWire's
                            // article navigation; grayed at the timeline ends.
                            Image(systemName: "chevron.up")
                                .font(.subheadline)
                                .foregroundColor(model.canSelectPrevious ? .blue : .secondary)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectPreviousItem() }
                            Image(systemName: "chevron.down")
                                .font(.subheadline)
                                .foregroundColor(model.canSelectNext ? .blue : .secondary)
                                .contentShape(Rectangle())
                                .onTapGesture { model.selectNextItem() }
                            // Star toggle — same affordance as upstream
                            // NetNewsWire's article-toolbar star button.
                            Image(systemName: model.isStarred(id: item.id) ? "star.fill" : "star")
                                .font(.title3)
                                .foregroundColor(model.isStarred(id: item.id) ? .yellow : .secondary)
                                .contentShape(Rectangle())
                                .onTapGesture { model.toggleStarred(id: item.id) }
                        }
                        // Headline.
                        Text(item.title)
                            .font(.title).bold()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Date in NetNewsWire's small-caps style.
                        if !item.publishedSummary.isEmpty {
                            Text(item.publishedSummary.uppercased())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        // Body — one Text per parsed paragraph so a
                        // multi-paragraph article renders with real
                        // spacing instead of a single run-on blob.
                        if !item.bodyParagraphs.isEmpty {
                            ForEach(Array(item.bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph)
                                    .font(.body)
                                    .lineSpacing(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Text(item.plainTextBody)
                                .font(.body)
                                .lineSpacing(6)
                        }
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
    /// Raw publication `Date` when the feed parser produced one. Drives the
    /// timeline's relative "time ago" display; nil for string-only fixtures
    /// or feeds without a parseable date (the row falls back to `pubDate`).
    public let publishedDate: Date?
    public let descriptionHTML: String?
    /// Byline shown under the title in the detail header. nil when
    /// the feed didn't carry an `<author>` / `<dc:creator>`.
    public let author: String?
    public let linkURL: URL?
    public let publishedSummary: String
    public let plainTextBody: String
    /// Ordered display paragraphs parsed from `descriptionHTML`.
    /// The detail pane renders these so multi-paragraph articles
    /// read like NetNewsWire's article view; `plainTextBody`
    /// remains the flattened form used for timeline snippets +
    /// search.
    public let bodyParagraphs: [String]

    public init(
        id: String,
        title: String,
        link: String?,
        pubDate: String?,
        publishedDate: Date? = nil,
        descriptionHTML: String?,
        author: String? = nil
    ) {
        self.id = id
        self.title = title
        self.link = link
        self.pubDate = pubDate
        self.publishedDate = publishedDate
        self.descriptionHTML = descriptionHTML
        self.author = author
        self.linkURL = link.flatMap { URL(string: $0) }
        self.publishedSummary = pubDate ?? ""
        self.plainTextBody = HTMLText.plainText(fromHTML: descriptionHTML ?? "")
        self.bodyParagraphs = HTMLText.paragraphs(fromHTML: descriptionHTML ?? "")
    }
}

public struct RSSArticleRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let publishedSummary: String
    /// Raw publication `Date` (threaded from `RSSItem`) for the timeline's
    /// relative "time ago" rendering; nil falls back to `publishedSummary`.
    public let publishedDate: Date?
    /// Short plain-text preview shown under the title, like
    /// NetNewsWire's two-line timeline snippet.
    public let snippet: String

    public init(id: String, title: String, publishedSummary: String, publishedDate: Date? = nil, snippet: String = "") {
        self.id = id
        self.title = title
        self.publishedSummary = publishedSummary
        self.publishedDate = publishedDate
        self.snippet = snippet
    }

    public init(item: RSSItem) {
        self.init(
            id: item.id,
            title: item.title,
            publishedSummary: item.publishedSummary,
            publishedDate: item.publishedDate,
            snippet: HTMLText.snippet(fromPlainText: item.plainTextBody)
        )
    }

    /// Timeline date label: a relative "time ago" / short date derived from
    /// `publishedDate` via the shared `QuillFoundation.RelativeTime` (matching
    /// NetNewsWire's compact timeline) when present, else the absolute
    /// `publishedSummary` fallback used by string-only fixtures.
    public var timelineDateText: String {
        publishedDate.map { RelativeTime.string(for: $0, now: Date()) } ?? publishedSummary
    }
}

public struct RSSArticleDetail: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let author: String?
    public let publishedSummary: String
    public let plainTextBody: String
    public let bodyParagraphs: [String]
    public let linkURL: URL?

    public init(
        id: String,
        title: String,
        author: String? = nil,
        publishedSummary: String,
        plainTextBody: String,
        bodyParagraphs: [String] = [],
        linkURL: URL?
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.publishedSummary = publishedSummary
        self.plainTextBody = plainTextBody
        self.bodyParagraphs = bodyParagraphs
        self.linkURL = linkURL
    }

    public init(item: RSSItem) {
        self.init(
            id: item.id,
            title: item.title,
            author: item.author,
            publishedSummary: item.publishedSummary,
            plainTextBody: item.plainTextBody,
            bodyParagraphs: item.bodyParagraphs,
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

/// Virtual feed kinds that aggregate articles by status or age
/// rather than by source. Upstream NetNewsWire pins these to
/// the top of the sidebar above the subscribed-feed list. The
/// active feed's items are filtered through whichever kind is
/// selected; cross-feed aggregation arrives with the
/// persistence iteration.
public enum SmartFeed: String, CaseIterable, Identifiable, Sendable {
    case today
    case allUnread
    case starred

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today:     return "Today"
        case .allUnread: return "All Unread"
        case .starred:   return "Starred"
        }
    }

    public var symbol: String {
        switch self {
        case .today:     return "☀"
        case .allUnread: return "●"
        case .starred:   return "★"
        }
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

    /// Upstream-shaped articles populated in parallel to `items`.
    /// Same source ParsedFeed; same newest-first sort; same set
    /// of records. View code still reads `items` / `rows` today;
    /// the future migration retires `items` in favor of this.
    /// Setter is internal (rather than private) so tests can pin
    /// a synthetic article list without going through fetch();
    /// production code only writes via the fetch() / refresh()
    /// network path.
    @Published var articles: [Article] = []
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

    /// Optional SQLite persistence (RSSReadStateStore) for read/starred state.
    /// Off in fixture/test mode so those stay deterministic; the app turns it
    /// on for the real-fetch path via `enablePersistence()`.
    private var stateStore: RSSReadStateStore?

    /// Optional SQLite persistence (RSSFeedListStore) for the subscribed feed
    /// list, so OPML imports / additions survive relaunch. Same opt-in shape.
    private var feedStore: RSSFeedListStore?

    /// Live search query bound to the timeline filter field.
    /// Empty string → no filter (filteredRows == rows). Matching
    /// is case-insensitive and runs against the article title
    /// and the plain-text body — same coverage as upstream
    /// NetNewsWire's timeline search.
    @Published var searchQuery: String = "" {
        didSet { updateStatusText() }
    }

    /// Active smart feed (All Unread / Starred), or nil when the
    /// timeline is showing a subscribed feed's items directly.
    /// Setting this overrides the feed selection's contribution
    /// to filteredItems — the smart filter runs first, then the
    /// search query narrows further.
    @Published var selectedSmartFeed: SmartFeed? {
        didSet { updateStatusText() }
    }

    /// Auto-refresh cadence in seconds for the active feed.
    /// Matches upstream NetNewsWire's default 30-minute refresh
    /// interval. Setting to nil disables background polling.
    @Published var refreshIntervalSeconds: TimeInterval? = 30 * 60

    /// Wall-clock time of the most recent successful fetch.
    /// Drives `isAutoRefreshDue()`. Exposed as @Published so
    /// future UI (a "last updated 3m ago" footer line) can
    /// observe it directly. Setter is internal so tests can
    /// pin a synthetic last-fetch time without going through
    /// real URLSession; production code only writes via fetch().
    @Published var lastFetchAt: Date?

    private var backgroundRefreshTask: Task<Void, Never>?

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
        guard let feed = subscribedFeeds.first(where: { $0.id == id }) else { return }
        // Always clear an active smart feed when the user taps a
        // real feed row, even if it's the currently-selected feed
        // ID — tapping the feed name is how you exit a smart-feed
        // view back to the per-feed timeline.
        let wasShowingSmartFeed = selectedSmartFeed != nil
        selectedSmartFeed = nil
        guard id != selectedFeedID || wasShowingSmartFeed else { return }
        selectedFeedID = id
        selectItem(id: nil)
        didStartInitialLoad = true
        await fetch(urlString: feed.url)
    }

    /// Pin the timeline to a smart-feed view (All Unread / Starred
    /// for now). Doesn't fetch — operates on whatever items the
    /// current feed already has loaded. Cross-feed aggregation
    /// arrives with the persistence iteration; until then, the
    /// smart feed effectively narrows the active feed's timeline.
    func selectSmartFeed(_ kind: SmartFeed?) {
        selectedSmartFeed = kind
        selectItem(id: nil)
    }

    /// Advance the selection to the next article in the
    /// currently-filtered timeline. Wraps to the first item when
    /// no selection exists yet. No-op when filteredItems is empty.
    /// Powers the J keyboard shortcut.
    func selectNextItem() {
        let pool = filteredItems
        guard !pool.isEmpty else { return }
        guard let current = selectedID,
              let index = pool.firstIndex(where: { $0.id == current })
        else {
            selectItem(id: pool.first?.id)
            return
        }
        let nextIndex = pool.index(after: index)
        if nextIndex < pool.endIndex {
            selectItem(id: pool[nextIndex].id)
        }
    }

    /// Step the selection one article earlier in the filtered
    /// timeline. No-op at the top. Powers the K keyboard shortcut.
    func selectPreviousItem() {
        let pool = filteredItems
        guard !pool.isEmpty else { return }
        guard let current = selectedID,
              let index = pool.firstIndex(where: { $0.id == current }),
              index > 0
        else { return }
        selectItem(id: pool[index - 1].id)
    }

    /// Whether a later article exists to step to — drives the detail view's
    /// next-article button (grayed at the end of the timeline).
    var canSelectNext: Bool {
        let pool = filteredItems
        guard let id = selectedID, let i = pool.firstIndex(where: { $0.id == id }) else {
            return !pool.isEmpty
        }
        return pool.index(after: i) < pool.endIndex
    }

    /// Whether an earlier article exists — drives the previous-article button.
    var canSelectPrevious: Bool {
        let pool = filteredItems
        guard let id = selectedID, let i = pool.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return i > pool.startIndex
    }

    /// Mark the current article read and advance to the next.
    /// Mirrors NetNewsWire's spacebar default: when there's no
    /// selection yet, just select the first item without
    /// advancing. Powers the spacebar shortcut.
    func markReadAndAdvance() {
        if let id = selectedID {
            markRead(id: id)
            selectNextItem()
        } else {
            selectItem(id: filteredItems.first?.id)
        }
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
        if added > 0 { persistFeedList() }
        return added
    }

    /// Subscribe to a single feed by URL — the NetNewsWire "Add Feed" action.
    /// Validates the URL (must be http/https with a host), derives a display
    /// title from `title` or the host, and merges it through the same
    /// dedupe/persist path as OPML import. Returns true if a new feed was added
    /// (false for an invalid URL or a feed already subscribed).
    @discardableResult
    func addFeed(urlString: String, title: String? = nil) -> Bool {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle! : host
        return mergeImportedFeeds([Feed(title: displayTitle, url: trimmedURL)]) > 0
    }

    /// Unsubscribe from a feed by id — the NetNewsWire "Delete Feed" action.
    /// Removes it from the subscribed list; if the removed feed was the current
    /// selection, the selection moves to the first remaining feed (or nil when
    /// the list becomes empty). Persists the new list. Returns true if a feed
    /// was removed (false if no subscribed feed had that id).
    @discardableResult
    func removeFeed(id: Feed.ID) -> Bool {
        guard let index = subscribedFeeds.firstIndex(where: { $0.id == id }) else {
            return false
        }
        subscribedFeeds.remove(at: index)
        if selectedFeedID == id {
            selectedFeedID = subscribedFeeds.first?.id
        }
        persistFeedList()
        return true
    }

    /// Serialize the current subscribed feed list as OPML 2.0.
    /// The result round-trips through `importOPML(xml:)` to the
    /// same feed list (modulo the optional list title).
    func exportOPML(title: String? = nil) -> String {
        OPMLExporter.export(feeds: subscribedFeeds, title: title)
    }

    func exportOPMLData(title: String? = nil) -> Data {
        OPMLExporter.exportData(feeds: subscribedFeeds, title: title)
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
            // Upstream RSParser via QuillRSParser; covers RSS 2.0,
            // Atom, JSON Feed, RSS-in-JSON. Produces both the
            // legacy RSSItem view-shape (consumed by the
            // timeline + filters today) and the upstream
            // Article shape (consumed by the cache / smart-feed
            // aggregation paths the persistence iteration will
            // bring online).
            let parsed = RSSFeedParser.parseUpstream(data: data, url: urlString)
            let upstreamArticles = RSSFeedParser.parseUpstreamArticles(
                data: data, url: urlString
            )
            self.setFeedTitle(parsed.title)
            self.setItems(Array(parsed.items.prefix(50)))
            self.articles = Array(upstreamArticles.prefix(50))
            if self.selectedID == nil {
                self.selectItem(id: self.preferredInitialItemID(in: self.items))
            }
            self.lastFetchAt = Date()
        } catch {
            self.setError("\(error)")
        }
        setLoading(false)
    }

    /// True when the auto-refresh interval has elapsed since the
    /// last successful fetch (or no fetch has ever happened).
    /// Honors `refreshIntervalSeconds == nil` as 'disabled'.
    /// Compares against an injected `now` so unit tests can pin
    /// time without driving a real clock.
    func isAutoRefreshDue(now: Date = Date()) -> Bool {
        guard let interval = refreshIntervalSeconds else { return false }
        guard let last = lastFetchAt else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Single background-refresh tick: if the interval has
    /// elapsed and we have an active feed URL, re-fetch. Pure
    /// async function — the looping Task in
    /// `startBackgroundRefresh()` calls this between sleeps so
    /// tests can exercise the eligibility logic without a timer.
    func backgroundRefreshTick(now: Date = Date()) async {
        guard isAutoRefreshDue(now: now) else { return }
        guard let url = currentFeedURL else { return }
        await refresh(urlString: url)
    }

    /// Start the auto-refresh Task that polls
    /// `backgroundRefreshTick()` on `refreshIntervalSeconds`
    /// cadence. Cancels any prior background task first so this
    /// is safe to call from onAppear or after a settings change.
    /// No-op when refreshIntervalSeconds is nil.
    func startBackgroundRefresh() {
        stopBackgroundRefresh()
        guard let interval = refreshIntervalSeconds else { return }
        let nanos = UInt64(max(1, interval) * 1_000_000_000)
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanos)
                if Task.isCancelled { return }
                await self?.backgroundRefreshTick()
            }
        }
    }

    func stopBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
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
            persistState(for: id)
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
        persistState(for: selectedID)
    }

    /// Mark every article currently shown in the timeline as read —
    /// upstream NetNewsWire's "Mark All as Read" toolbar action. Unions the
    /// visible IDs into `readArticleIDs` in a single assignment so the status
    /// text refreshes once rather than per-article.
    func markAllRead() {
        let union = readArticleIDs.union(filteredRows.map(\.id))
        if union != readArticleIDs {
            readArticleIDs = union
            persistAllState()
        }
    }

    /// True when any article in the current timeline is unread — drives the
    /// Mark All as Read control's tinted/no-op state.
    var hasUnreadInTimeline: Bool {
        filteredRows.contains { !readArticleIDs.contains($0.id) }
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
        persistState(for: id)
    }

    /// Toggle starred state on the currently-selected article.
    /// No-op when nothing is selected.
    func toggleStarredOnSelection() {
        guard let selectedID else { return }
        toggleStarred(id: selectedID)
    }

    // MARK: - Read/starred persistence

    /// Turn on SQLite persistence and merge any previously-saved read/starred
    /// state into the in-memory sets. Best-effort: a store that can't open
    /// (e.g. a read-only home dir) silently leaves state in memory. The app
    /// calls this on the real-fetch path; fixtures/tests leave it off so they
    /// stay deterministic. `store` is injectable for tests.
    func enablePersistence(store: RSSReadStateStore? = nil) {
        guard let store = store ?? (try? RSSReadStateStore(url: RSSReadStateStore.defaultURL())) else { return }
        stateStore = store
        if let loaded = try? store.load() {
            if !loaded.read.isEmpty { readArticleIDs.formUnion(loaded.read) }
            if !loaded.starred.isEmpty { starredArticleIDs.formUnion(loaded.starred) }
        }
    }

    /// Persist one article's current read/starred flags. No-op without a store.
    private func persistState(for id: String) {
        try? stateStore?.setState(
            articleID: id,
            isRead: readArticleIDs.contains(id),
            isStarred: starredArticleIDs.contains(id)
        )
    }

    /// Persist the whole read/starred set in one batch (for bulk actions).
    private func persistAllState() {
        try? stateStore?.replaceAll(read: readArticleIDs, starred: starredArticleIDs)
    }

    /// Turn on feed-list persistence. Loads a previously-saved subscription
    /// list (the source of truth once it exists); on first run, persists the
    /// current seed list so it's there next launch. Best-effort; injectable
    /// for tests. Kept separate from `enablePersistence` so each store can be
    /// exercised in isolation.
    func enableFeedPersistence(store: RSSFeedListStore? = nil) {
        guard let store = store ?? (try? RSSFeedListStore(url: RSSFeedListStore.defaultURL())) else { return }
        feedStore = store
        if let loaded = try? store.load(), !loaded.isEmpty {
            subscribedFeeds = loaded
            if selectedFeedID == nil || !loaded.contains(where: { $0.id == selectedFeedID }) {
                selectedFeedID = loaded.first?.id
            }
        } else {
            try? store.replaceAll(subscribedFeeds)
        }
    }

    /// Persist the current subscription list (no-op without a store).
    private func persistFeedList() {
        try? feedStore?.replaceAll(subscribedFeeds)
    }

    /// Count of starred items in the currently-loaded timeline.
    /// Doesn't yet aggregate across feeds (the smart-feed iteration
    /// will introduce a separate fetch-all-starred view).
    var starredCount: Int {
        items.reduce(0) { acc, item in
            acc + (starredArticleIDs.contains(item.id) ? 1 : 0)
        }
    }

    /// Item count for a given smart feed against the
    /// currently-loaded timeline. Used by the feedsPane badge
    /// next to each Smart Feed row. Persistence iteration will
    /// switch this to a cross-feed aggregation.
    func count(for smart: SmartFeed) -> Int {
        switch smart {
        case .today:
            let cutoff = Date().addingTimeInterval(-86_400)
            return articles.reduce(0) { acc, article in
                acc + ((article.datePublished.map { $0 >= cutoff }) == true ? 1 : 0)
            }
        case .allUnread: return unreadCount
        case .starred:   return starredCount
        }
    }

    /// Unread count for a subscribed feed. Today only the
    /// active feed has loaded items, so the count is exact for
    /// the selected feed and 0 for everything else. When the
    /// persistence iteration lands a per-feed article cache,
    /// this will report accurate counts for every subscription.
    func unreadCount(forFeed feedID: Feed.ID) -> Int {
        guard feedID == selectedFeedID else { return 0 }
        return unreadCount
    }

    /// Items in the current timeline that match the active smart
    /// feed (if any) AND the active search query (if any). When
    /// both filters are empty, returns the full items list. Smart
    /// feed runs first so the search field narrows whatever the
    /// smart-feed view is showing.
    var filteredItems: [RSSItem] {
        var pool = items
        if let smart = selectedSmartFeed {
            switch smart {
            case .today:
                // Use the parallel articles array (real Date from
                // upstream DateParser) to determine which uniqueIDs
                // fall inside the last-24h window, then narrow
                // items to that set so the existing RSSItem render
                // path keeps working unchanged.
                let cutoff = Date().addingTimeInterval(-86_400)
                let todayIDs = Set(articles.compactMap { article -> String? in
                    guard let published = article.datePublished, published >= cutoff else {
                        return nil
                    }
                    return article.uniqueID
                })
                pool = pool.filter { todayIDs.contains($0.id) }
            case .allUnread:
                pool = pool.filter { !readArticleIDs.contains($0.id) }
            case .starred:
                pool = pool.filter { starredArticleIDs.contains($0.id) }
            }
        }
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let needle = trimmed.lowercased()
            pool = pool.filter { item in
                if item.title.lowercased().contains(needle) { return true }
                if item.plainTextBody.lowercased().contains(needle) { return true }
                return false
            }
        }
        return pool
    }

    /// Row projection of `filteredItems` for the timeline view to
    /// render. Kept as a computed (rather than a stored @Published
    /// shadow) so the search filter doesn't require a parallel
    /// invalidation path for every items / searchQuery change.
    var filteredRows: [RSSArticleRow] {
        filteredItems.map(RSSArticleRow.init(item:))
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
        let searchActive = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isLoading {
            nextStatusText = "Fetching feed…"
        } else if let error {
            nextStatusText = "Error: \(error)"
        } else if let smart = selectedSmartFeed {
            // Smart-feed view: count vs total items currently
            // loaded. Search narrowing folds into the same count.
            let matching = filteredItems.count
            let suffix = searchActive ? " (search)" : ""
            nextStatusText = "\(smart.displayName): \(matching) of \(items.count)\(suffix)"
        } else if searchActive {
            let matching = filteredItems.count
            nextStatusText = "\(matching) matching · \(items.count) items"
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

    /// Builds a fixture publication `Date` (all fixtures are 2026) so the
    /// offline demo timeline exercises the same relative-date rendering path
    /// (`RSSArticleRow.timelineDateText` → `RelativeTime`) as live feeds.
    private static func fixtureDate(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        // Fully qualify Foundation's types: on Linux, QuillUI re-exports
        // SwiftOpenUI, which defines its own `DateComponents`/`Calendar` that
        // would otherwise shadow Foundation's here.
        var c = Foundation.DateComponents()
        c.year = 2026; c.month = month; c.day = day; c.hour = hour; c.minute = minute
        return Foundation.Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    private static let profileFixtureItems: [RSSItem] = [
        RSSItem(
            id: "1",
            title: "Painting the Natural World Before Photography",
            link: "https://example.test/1",
            pubDate: "Feb 2, 2026 at 6:58 AM",
            publishedDate: RSSReaderModel.fixtureDate(2, 2, 6, 58),
            descriptionHTML: """
            <p>Decades before the advent of photography, when European scientists and \
            explorers were undertaking grand expeditions, painters documented the natural \
            world in extraordinary detail.</p>\
            <p>Their illustrations — of birds, plants, and animals encountered for the first \
            time — became the visual record that early naturalists relied on to share \
            discoveries across a continent and, eventually, the world.</p>\
            <p>This fixture article exercises the reader's multi-paragraph rendering and \
            comfortable reading typography in the detail pane, standing in for a live feed \
            when the network is disabled.</p>
            """,
            author: "Kate Mothes"
        ),
        RSSItem(
            id: "2",
            title: "A Quiet Update to the Swift Concurrency Model",
            link: "https://example.test/2",
            pubDate: "Feb 1, 2026 at 9:12 AM",
            publishedDate: RSSReaderModel.fixtureDate(2, 1, 9, 12),
            descriptionHTML: """
            <p>The latest toolchain refines how isolated conformances interact with \
            main-actor views, smoothing a rough edge that Linux UI code hit often.</p>\
            <p>Most existing code keeps compiling unchanged; the new diagnostics mainly \
            surface places where a nonisolated witness was quietly doing actor-hopping.</p>
            """,
            author: "Becca Royal-Gordon"
        ),
        RSSItem(
            id: "3",
            title: "Swift.org toolchain update",
            link: "https://example.test/3",
            pubDate: "Jan 30, 2026 at 4:05 PM",
            publishedDate: RSSReaderModel.fixtureDate(1, 30, 16, 5),
            descriptionHTML: "<p>Compiler and package manager notes for Linux app smoke runs.</p>",
            author: "The Swift Team"
        ),
        RSSItem(
            id: "4",
            title: "Point-Free dependency release",
            link: "https://example.test/4",
            pubDate: "Jan 29, 2026 at 11:20 AM",
            publishedDate: RSSReaderModel.fixtureDate(1, 29, 11, 20),
            descriptionHTML: "<p>Dependency injection notes and performance guardrails.</p>",
            author: "Brandon Williams"
        ),
        RSSItem(
            id: "5",
            title: "Linux backend smoke notes",
            link: "https://example.test/5",
            pubDate: "Jan 28, 2026 at 8:00 AM",
            publishedDate: RSSReaderModel.fixtureDate(1, 28, 8, 0),
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

/// Adapter from the upstream Ranchero-Software/NetNewsWire
/// `FeedParser` to the local `RSSItem` shape that the reader
/// model, sidebar, search filter, smart feeds, OPML import,
/// and keyboard navigation already consume. Same Result
/// container is returned regardless of feed format (RSS 2.0,
/// Atom, JSON Feed, RSS-in-JSON) since the upstream parser
/// dispatches by content sniff.
///
/// The historical homegrown Foundation.XMLParser implementation
/// was retired once parseUpstream covered every fetch() call
/// site — see git log for the legacy path. Internal (not
/// private) so QuillNetNewsWireCoreTests can pin the upstream
/// adapter via `@testable import` without going through
/// URLSession.
struct RSSFeedParser {
    struct Result: Equatable {
        var title: String?
        var items: [RSSItem] = []
    }

    /// Upstream Ranchero-Software/NetNewsWire `FeedParser` path.
    /// Same Result shape as the legacy parse(data:), so the model
    /// + view + smart-feed pipeline all keep working unchanged.
    ///
    /// Differences from the legacy XMLParser path:
    ///   - Covers RSS 2.0, Atom, JSON Feed, RSS-in-JSON (legacy
    ///     only handled the RSS 2.0/Atom subset)
    ///   - DateParser converts pubDate strings to Date and we
    ///     re-emit ISO 8601 (legacy preserved the raw header)
    ///   - Items arrive as Set<ParsedItem>; we sort newest-first
    ///     with a uniqueID tiebreaker so timeline ordering is
    ///     deterministic
    ///   - uniqueIDs are content-addressed MD5 hashes via
    ///     QuillRSCoreShim when upstream falls back from guid
    static func parseUpstream(data: Data, url: String) -> Result {
        let parserData = ParserData(url: url, data: data)
        // FeedParser.parse(_:) signature is `throws -> ParsedFeed?`,
        // so `try?` would yield ParsedFeed?? — handle both axes
        // (parse error and unidentified-feed) with do/catch so the
        // empty Result fallback is reachable from either path.
        let parsed: ParsedFeed?
        do {
            parsed = try FeedParser.parse(parserData)
        } catch {
            parsed = nil
        }
        guard let parsed else { return Result() }
        let sortedItems = parsed.items.sorted { lhs, rhs in
            // Newest first; nil dates sort last; deterministic
            // uniqueID tiebreaker so repeated parses don't churn.
            switch (lhs.datePublished, rhs.datePublished) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.uniqueID < rhs.uniqueID
            }
        }
        let rssItems = sortedItems.map(adaptParsedItem(_:))
        return Result(title: parsed.title, items: rssItems)
    }

    /// Translate one upstream ParsedItem into our local RSSItem
    /// shape. Body falls back through contentHTML → contentText
    /// → summary → nil. Title falls back to "Untitled" so the
    /// timeline always renders something. pubDate gets ISO 8601
    /// formatted when the upstream DateParser produced a Date.
    static func adaptParsedItem(_ item: ParsedItem) -> RSSItem {
        let title = (item.title?.isEmpty == false) ? item.title! : "Untitled"
        let body = item.contentHTML ?? item.contentText ?? item.summary
        // Byline: first non-empty author name (sorted for a stable
        // pick across repeated parses). Most feeds carry one author.
        let author = item.authors?
            .compactMap(\.name)
            .filter { !$0.isEmpty }
            .sorted()
            .first
        return RSSItem(
            id: item.uniqueID,
            title: title,
            link: item.url,
            pubDate: formatPubDate(item.datePublished),
            publishedDate: item.datePublished,
            descriptionHTML: body,
            author: author
        )
    }

    /// Friendly display date for the header + timeline, e.g.
    /// "Feb 2, 2026 at 6:58 AM". `publishedSummary` is display-only
    /// (sorting uses the real `Date`), so a human format is safe.
    static func formatPubDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.displayDateFormatter.string(from: date)
    }

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f
    }()

    /// Materialize upstream `[Article]` values from the same
    /// `ParsedFeed` that drives the existing RSSItem timeline.
    /// Quill's reader has no real Account today — accountID
    /// defaults to the singleton "Local" identity so per-article
    /// IDs are stable across launches once persistence lands.
    ///
    /// Order mirrors parseUpstream: newest-first, uniqueID
    /// tiebreaker. Returned via array (not Set) so the call site
    /// can pin the same sort the timeline uses.
    static func parseUpstreamArticles(
        data: Data,
        url: String,
        accountID: String = "Local"
    ) -> [Article] {
        let parserData = ParserData(url: url, data: data)
        let parsed: ParsedFeed?
        do {
            parsed = try FeedParser.parse(parserData)
        } catch {
            parsed = nil
        }
        guard let parsed else { return [] }
        return toArticles(parsed: parsed, feedID: url, accountID: accountID)
    }

    /// Convert ParsedFeed.items → [Article] with the sort the
    /// QuillNetNewsWireCore reader uses (newest first, tiebreak
    /// by uniqueID for deterministic timeline ordering). The
    /// articleID gets synthesized by upstream when nil — md5
    /// over accountID+feedID+uniqueID via QuillRSCoreShim.
    static func toArticles(
        parsed: ParsedFeed,
        feedID: String,
        accountID: String
    ) -> [Article] {
        let sorted = parsed.items.sorted { lhs, rhs in
            switch (lhs.datePublished, rhs.datePublished) {
            case let (l?, r?) where l != r: return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.uniqueID < rhs.uniqueID
            }
        }
        let now = Date()
        return sorted.map { parsed in
            let status = ArticleStatus(
                articleID: parsed.uniqueID,
                read: false,
                starred: false,
                dateArrived: now
            )
            return Article(
                accountID: accountID,
                articleID: nil,  // upstream synthesizes via md5
                feedID: feedID,
                uniqueID: parsed.uniqueID,
                title: parsed.title,
                contentHTML: parsed.contentHTML,
                contentText: parsed.contentText,
                markdown: parsed.markdown,
                url: parsed.url,
                externalURL: parsed.externalURL,
                summary: parsed.summary,
                imageURL: parsed.imageURL,
                datePublished: parsed.datePublished,
                dateModified: parsed.dateModified,
                authors: nil,
                status: status
            )
        }
    }
}
