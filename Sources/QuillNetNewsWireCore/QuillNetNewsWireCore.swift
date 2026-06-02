import Foundation
import QuillFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import QuillUI
import QuillRSParser
import QuillArticles
import QuillRSWeb
import QuillFeedFinder

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
    @State private var addSubscriptionInput: String = ""
    @State private var opmlImportURLInput: String = ""
    @State private var showingSettings: Bool = false
    @State private var inspectedFeedID: Feed.ID? = nil

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
                    Task { @MainActor in await model.loadIfNeeded(urlString: activeFeedURL) }
                    // Kick off the periodic auto-refresh Task.
                    // Skipped in profile/disable-fetch mode so the
                    // Linux profile script doesn't see URLSession
                    // traffic from the background timer.
                    model.startBackgroundRefresh()
                }
            }
            .sheet(isPresented: Binding(
                get: { showingSettings },
                set: { showingSettings = $0 }
            )) {
                settingsSheet
            }
            .sheet(isPresented: Binding(
                get: { inspectedFeedID != nil },
                set: { if !$0 { inspectedFeedID = nil } }
            )) {
                inspectorSheet
            }
        }
    }

    /// Per-feed inspector sheet. Mirrors NetNewsWire's
    /// 'Get Info' window: shows feed title, fetch URL,
    /// homePageURL (clickable Link), last-fetch summary,
    /// item + unread counts, and the most recent error
    /// message when present. Bound to inspectedFeedID
    /// so opening from a feedRow's ℹ button works.
    private var inspectorSheet: some View {
        let feed = model.subscribedFeeds.first(where: { $0.id == inspectedFeedID })
        return VStack(alignment: .leading, spacing: 14) {
            Text("Feed Info").font(.title2).bold()
            if let feed {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feed.title).font(.headline)
                    Text(feed.url)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if let cache = model.feedCaches[feed.id] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(cache.items.count) items cached")
                            .font(.caption)
                        Text(Self.fetchAgeText(cache.lastFetchAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                let unread = model.unreadCount(forFeed: feed.id)
                if unread > 0 {
                    Text("\(unread) unread")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                if let iconURL = model.feedIconURLs[feed.id] {
                    Text("Icon: \(iconURL)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if let err = model.feedErrors[feed.id] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Last error")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(4)
                    }
                }
            } else {
                Text("Feed not found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack {
                if let feed {
                    // Per-feed refresh — fetches just this feed's
                    // contents into the cache (or active timeline
                    // when it's the selection). Disabled while a
                    // refresh is already in flight to avoid
                    // overlapping requests for the same URL.
                    Button("Refresh") {
                        Task { @MainActor in
                            await model.refreshFeed(urlString: feed.url)
                        }
                    }
                    .disabled(model.isLoading)
                }
                Spacer()
                Button("Done") { inspectedFeedID = nil }
            }
        }
        .padding(24)
        .frame(width: 380, height: 360)
    }

    /// Render a Date as "Last fetched 2 hours ago" / "never".
    /// Reuses the same relative-formatter shim the detail-view
    /// header uses.
    private static func fetchAgeText(_ date: Date) -> String {
        "Last fetched \(RSSReaderModel.relativeString(for: date, relativeTo: Date()))"
    }

    /// Settings sheet — Stepper for the background-refresh
    /// interval (in minutes), the persistence dir path label,
    /// and a Done button. NetNewsWire's preferences pane is
    /// much bigger; this is a minimum viable surface that
    /// covers the user-controlled state the model already
    /// exposes.
    private var settingsSheet: some View {
        let intervalMinutesBinding = Binding<Int>(
            get: { Int((model.refreshIntervalSeconds ?? 1800) / 60) },
            set: { newValue in
                let clamped = max(1, newValue)
                model.refreshIntervalSeconds = TimeInterval(clamped * 60)
            }
        )
        return VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2).bold()
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh interval")
                    .font(.subheadline)
                let minutes = Int((model.refreshIntervalSeconds ?? 1800) / 60)
                let summary = minutes == 1
                    ? "Every minute"
                    : minutes < 60
                        ? "Every \(minutes) minutes"
                        : "Every \(minutes / 60) hour\(minutes / 60 == 1 ? "" : "s")"
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    "Refresh interval (minutes)",
                    value: intervalMinutesBinding,
                    in: 1...1440,
                    step: 5
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Subscriptions / persisted state")
                    .font(.subheadline)
                Text(model.subscribedFeeds.count == 1
                    ? "1 feed subscribed"
                    : "\(model.subscribedFeeds.count) feeds subscribed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(model.readArticleIDs.count) read · \(model.starredArticleIDs.count) starred")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { showingSettings = false }
            }
        }
        .padding(24)
        .frame(width: 380, height: 360)
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
            Button("mark all read") {
                model.markAllVisibleAsRead()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("refresh all") {
                Task { @MainActor in await model.refreshAllFeeds() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            Button("next unread") {
                model.selectNextUnread()
            }
            .keyboardShortcut("n", modifiers: [])
            Button("mark unread") {
                model.markUnreadOnSelection()
            }
            .keyboardShortcut("u", modifiers: [])
            Button("previous unread") {
                model.selectPreviousUnread()
            }
            .keyboardShortcut("p", modifiers: [])
            // Cmd+Shift+U toggles "Hide Read Articles" — same
            // shortcut as upstream NetNewsWire.
            Button("toggle hide read") {
                model.hideReadArticles.toggle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
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
                    // Root folder's direct feeds + any subfolders.
                    // When no OPML tree has been imported, the model
                    // initializes subscriptionRoot to wrap every seed
                    // feed at top level so the existing flat render
                    // shape stays intact.
                    ForEach(model.subscriptionRoot.feeds) { feed in
                        feedRow(feed)
                            .onTapGesture {
                                Task { @MainActor in await model.selectFeed(id: feed.id) }
                            }
                    }
                    ForEach(model.subscriptionRoot.subfolders) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            // "Add feed URL" row. Routes through upstream
            // FeedFinder.find(url:) — takes a website URL or a
            // direct feed URL, walks the page for
            // <link rel="alternate"> + well-known feed-path
            // probes, picks the best candidate, appends to
            // subscribedFeeds (dedupes via mergeImportedFeeds).
            VStack(alignment: .leading, spacing: 4) {
                Text("Add Feed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    TextField("Site or feed URL", text: Binding(
                        get: { addSubscriptionInput },
                        set: { addSubscriptionInput = $0 }
                    ))
                        .font(.caption)
                    Button("Add") {
                        let input = addSubscriptionInput
                        addSubscriptionInput = ""
                        Task { @MainActor in
                            await model.addSubscription(urlString: input)
                        }
                    }
                    .font(.caption2)
                    .disabled(addSubscriptionInput.trimmingWhitespace.isEmpty)
                }
                HStack(spacing: 6) {
                    TextField("OPML URL", text: Binding(
                        get: { opmlImportURLInput },
                        set: { opmlImportURLInput = $0 }
                    ))
                        .font(.caption2)
                    Button("Import") {
                        let input = opmlImportURLInput
                        opmlImportURLInput = ""
                        Task { @MainActor in
                            await model.importOPMLFromURL(input)
                        }
                    }
                    .font(.caption2)
                    .disabled(opmlImportURLInput.trimmingWhitespace.isEmpty)
                }
                HStack(spacing: 6) {
                    Button("Export OPML") {
                        model.saveOPMLExportToDisk()
                    }
                    .font(.caption2)
                    Button("Settings") {
                        showingSettings = true
                    }
                    .font(.caption2)
                    if let url = model.lastOPMLExportURL {
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func smartFeedRow(_ kind: SmartFeed) -> some View {
        let count = model.count(for: kind)
        return HStack(spacing: 6) {
            Text(kind.symbol)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 14, alignment: .leading)
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

    /// Render a single OPML folder as a DisclosureGroup of its
    /// child feeds + nested subfolders. Default-expanded so the
    /// first render after OPML import shows every subscription
    /// without requiring the user to click open each section.
    /// Recurses through subfolders; folder names render as the
    /// disclosure title.
    /// AnyView return because folderRow recursively renders
    /// subfolders — `some View` would define the opaque type in
    /// terms of itself, which Swift can't infer.
    private func folderRow(_ folder: OPMLImporter.Folder) -> AnyView {
        // No `isExpanded:` arg — Apple's SwiftUI init takes a
        // Binding<Bool>, SwiftOpenUI's matching init takes a
        // Bool. Both default to collapsed; per-folder expansion
        // state will land alongside Settings persistence.
        let unread = model.unreadCount(in: folder)
        let title = folder.name.isEmpty ? "Folder" : folder.name
        let displayTitle = unread > 0 ? "\(title) (\(unread))" : title
        let inner = DisclosureGroup(displayTitle) {
            VStack(alignment: .leading, spacing: 2) {
                // 'Mark Read' inside the folder block — only
                // surfaces when something inside is unread.
                // Matches NetNewsWire's per-folder action menu
                // affordance.
                if unread > 0 {
                    Button("Mark folder read") {
                        model.markFolderAsRead(folder)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                }
                ForEach(folder.feeds) { feed in
                    feedRow(feed)
                        .onTapGesture {
                            Task { @MainActor in await model.selectFeed(id: feed.id) }
                        }
                }
                ForEach(folder.subfolders) { sub in
                    folderRow(sub)
                }
            }
            .padding(.leading, 8)
        }
        .font(.caption)
        return AnyView(inner)
    }

    private func feedRow(_ feed: Feed) -> some View {
        let isSelected = (model.selectedSmartFeed == nil) && (model.selectedFeedID == feed.id)
        let unread = model.unreadCount(forFeed: feed.id)
        let hasError = model.feedErrors[feed.id] != nil
        return HStack(spacing: 6) {
            if hasError {
                // Compact stale-feed warning. Mirrors NetNewsWire's
                // sidebar amber-warning glyph next to feeds whose
                // most recent fetch failed (HTTP 4xx/5xx, parse
                // failure, network timeout). Cleared automatically
                // on the next successful fetch.
                Text("⚠")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Text(feed.title)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if unread > 0 {
                // Compact NetNewsWire-style unread badge,
                // accurate across all cached feeds via feedCaches.
                Text("\(unread)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            // Inspect + delete affordances. Tiny ℹ + ✕ that
            // only surface in the selected row to keep visual
            // noise down — matches upstream NetNewsWire's
            // edit-mode delete button (a hover-only X in macOS,
            // edit-mode swipe on iOS) plus an info-row gesture.
            if isSelected {
                Button("ℹ") {
                    inspectedFeedID = feed.id
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                // Per-feed mark-as-read. Disabled when there's
                // nothing unread in this feed's cache so the
                // affordance is honest. Upstream's equivalent
                // is the feed-row "Mark All as Read" menu.
                Button("✓") {
                    model.markFeedAsRead(feed.id)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .disabled(unread == 0)
                Button("✕") {
                    model.removeSubscription(id: feed.id)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
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
            HStack(spacing: 6) {
                TextField("Search articles", text: Binding(
                    get: { model.searchQuery },
                    set: { model.searchQuery = $0 }
                ))
                if !model.searchQuery.isEmpty {
                    // Clear-search button only surfaces when there's
                    // something to clear; matches upstream NetNews
                    // Wire's search-field ✕ affordance.
                    Button("✕") { model.searchQuery = "" }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(14)
            }

            ScrollView {
                if model.filteredRows.isEmpty {
                    timelineEmptyState
                        .padding(.horizontal, 12)
                        .padding(.top, 32)
                } else {
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
            }

            footerStatus
        }
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    /// Placeholder for a 0-row timeline. Reads as a calm
    /// secondary-text block rather than a broken state.
    /// Mirrors upstream NetNewsWire's "No Articles" / "No
    /// Unread Articles" placeholder when the active view
    /// resolves to nothing.
    private var timelineEmptyState: some View {
        let (headline, detail) = model.emptyTimelineMessage()
        return VStack(spacing: 8) {
            Text(headline)
                .font(.subheadline)
                .foregroundColor(.secondary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
                if let feed = item.feedTitle, !feed.isEmpty {
                    // Cross-feed context (smart feed / search):
                    // surface which feed this article came from.
                    // Upstream NetNewsWire's timeline shows the
                    // feed name on cross-feed views so users
                    // aren't guessing the source.
                    Text(feed)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: 244, alignment: .leading)
                }
                let dateAuthor = item.dateAuthorLine
                if !dateAuthor.isEmpty {
                    Text(dateAuthor)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: 244, alignment: .leading)
                }
                if !item.previewText.isEmpty {
                    // 2-line body snippet so users can scan the
                    // timeline. Matches upstream NetNewsWire's
                    // 2-line preview under the date.
                    Text(item.previewText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(width: 244, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // 108pt covers: feed-title line (cross-feed views only)
        // + date line + 2-line preview + spacing. Active-feed
        // rows leave the feed-title slot unused; small waste
        // beats reshuffling height between views.
        .frame(height: 108, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(model.selectedID == item.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    private var footerStatus: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                let updated = model.lastFetchSummary
                if !updated.isEmpty {
                    Text(updated)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // Visible "Hide Read" toggle — same semantic as
            // Cmd+Shift+U. Glyph flips so the affordance reads at
            // a glance.
            Button(model.hideReadArticles ? "Show Read" : "Hide Read") {
                model.hideReadArticles.toggle()
            }
            .font(.caption2)
            // Sort-order flip. Arrow direction mirrors the
            // upstream NNW glyph (↓ newest at top, ↑ oldest at
            // top).
            Button(model.sortOrder == .newestFirst ? "Newest ↓" : "Oldest ↑") {
                model.sortOrder = (model.sortOrder == .newestFirst) ? .oldestFirst : .newestFirst
            }
            .font(.caption2)
            Button("All Read") {
                model.markAllVisibleAsRead()
            }
            .font(.caption2)
            .disabled(model.unreadCount == 0)
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.title).bold()
                                if let position = model.selectionPositionLabel() {
                                    // Position breadcrumb so users in
                                    // a long timeline know how far they
                                    // are. Matches upstream NetNewsWire's
                                    // "N of M" detail-header indicator.
                                    Text(position)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Read/Unread toggle in the detail
                            // header. ● = read, ○ = unread. Matches
                            // upstream NetNewsWire's detail-toolbar
                            // read-state control. Especially useful
                            // because opening an article auto-marks
                            // it read; this is how the user undoes
                            // that without leaving the detail pane.
                            Button(model.isRead(id: item.id) ? "●" : "○") {
                                if model.isRead(id: item.id) {
                                    model.markUnread(id: item.id)
                                } else {
                                    model.markRead(id: item.id)
                                }
                            }
                            .font(.title2)
                            .foregroundColor(.blue)
                            // Star toggle in the detail header. A
                            // filled glyph when starred, hollow when
                            // not — same affordance as upstream
                            // NetNewsWire's toolbar star button.
                            Button(model.isStarred(id: item.id) ? "★" : "☆") {
                                model.toggleStarred(id: item.id)
                            }
                            .font(.title2)
                        }
                        // Friendly date line: relative ("3 hours ago")
                        // when the published date is within 24h,
                        // absolute medium-style date otherwise. Falls
                        // through to raw publishedSummary string if
                        // upstream DateParser couldn't resolve the
                        // header.
                        let friendly = model.friendlyDateString(forItemID: item.id)
                        let dateLine = friendly.isEmpty ? item.publishedSummary : friendly
                        if let author = model.authorLine(forItemID: item.id) {
                            Text(dateLine.isEmpty ? "By \(author)" : "\(dateLine) · By \(author)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if !dateLine.isEmpty {
                            Text(dateLine)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        // One Text per HTML paragraph (split on
                        // block-level tags upstream of HTML
                        // stripping). Falls through to the
                        // single-Text plainTextBody when the
                        // body had no block markup so behavior
                        // is unchanged for plain-text feeds.
                        if item.bodyParagraphs.count > 1 {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(item.bodyParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                    Text(paragraph)
                                        .font(.body)
                                        .lineSpacing(4)
                                }
                            }
                        } else {
                            Text(item.plainTextBody)
                                .font(.body)
                                .lineSpacing(4)
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
                        if !item.inlineLinks.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Links in this article")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(Array(item.inlineLinks.enumerated()), id: \.offset) { _, link in
                                    let display = link.text.isEmpty ? link.urlString : link.text
                                    #if os(Linux)
                                    Link(display, destination: link.urlString)
                                        .font(.caption)
                                    #else
                                    if let url = link.url {
                                        Link(display, destination: url)
                                            .font(.caption)
                                    }
                                    #endif
                                }
                            }
                        }
                        if !item.inlineImages.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Images in this article")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(Array(item.inlineImages.enumerated()), id: \.offset) { _, image in
                                    let display = image.alt.isEmpty ? image.urlString : image.alt
                                    #if os(Linux)
                                    Link(display, destination: image.urlString)
                                        .font(.caption)
                                    #else
                                    if let url = image.url {
                                        Link(display, destination: url)
                                            .font(.caption)
                                    }
                                    #endif
                                }
                            }
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

public struct InlineLink: Hashable, Sendable {
    /// Anchor text rendered inline in the article body.
    public let text: String
    /// Resolved href. Empty `text` falls back to the URL itself
    /// when rendered so a UI list always has something to click.
    public let urlString: String

    public init(text: String, urlString: String) {
        self.text = text
        self.urlString = urlString
    }

    public var url: URL? { URL(string: urlString) }
}

public struct InlineImage: Hashable, Sendable {
    /// Image source URL (the `src` attribute).
    public let urlString: String
    /// Alt text — empty when the `<img>` had no alt attribute.
    public let alt: String

    public init(urlString: String, alt: String) {
        self.urlString = urlString
        self.alt = alt
    }

    public var url: URL? { URL(string: urlString) }
}

public struct RSSItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let link: String?
    public let pubDate: String?
    public let descriptionHTML: String?
    public let linkURL: URL?
    public let publishedSummary: String
    public let plainTextBody: String
    /// HTML body split on block-level boundaries (<p>, <br>,
    /// <h*>, <li>, <blockquote>, <div>, <hr>), each segment
    /// HTML-stripped + entity-decoded. Empty segments are
    /// removed. Lets the detail view render real paragraph
    /// structure without an HTML renderer (the underlying
    /// SwiftOpenUI backend has no rich-text widget today).
    public let bodyParagraphs: [String]
    /// Inline `<a href>` extractions from the HTML body, in
    /// source order. Empty when the body had no anchors. The
    /// detail view renders these in a "Links in this article"
    /// footer so href targets aren't lost when bodyParagraphs
    /// strips inline tags.
    public let inlineLinks: [InlineLink]
    /// Inline `<img src>` extractions from the HTML body, in
    /// source order. Same fate as inlineLinks — image refs are
    /// stripped from bodyParagraphs, but the detail view
    /// surfaces them as a "Images in this article" footer so
    /// the user can click through.
    public let inlineImages: [InlineImage]

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
        self.bodyParagraphs = (descriptionHTML ?? "").htmlParagraphs()
        self.inlineLinks = (descriptionHTML ?? "").htmlInlineLinks()
        self.inlineImages = (descriptionHTML ?? "").htmlInlineImages()
    }
}

public struct RSSArticleRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let publishedSummary: String
    /// Short body preview for the timeline. Upstream NetNewsWire
    /// renders ~2 lines of the article body under the title +
    /// date so users can scan the timeline without opening every
    /// article. Built from RSSItem.plainTextBody (already HTML-
    /// stripped) with whitespace runs collapsed and truncated to
    /// 160 chars with an ellipsis. Empty when the source body
    /// was empty (title-only feeds).
    public let previewText: String
    /// Source feed title — non-nil when the timeline is rendering
    /// articles from a feed other than the active selection
    /// (smart feeds, search results). Upstream NetNewsWire shows
    /// the feed name in this cross-feed context so users can tell
    /// which feed each article came from. Nil when the row belongs
    /// to the currently-active feed (the sidebar already shows
    /// the feed, so repeating it in each row is noise).
    public let feedTitle: String?
    /// Comma-joined author names (or nil when the upstream parser
    /// didn't surface any). Squeezed onto the date line as
    /// "date · by Author" — matches upstream NetNewsWire's
    /// timeline row format and what Quill's detail header already
    /// renders.
    public let authorLine: String?

    public init(
        id: String,
        title: String,
        publishedSummary: String,
        previewText: String = "",
        feedTitle: String? = nil,
        authorLine: String? = nil
    ) {
        self.id = id
        self.title = title
        self.publishedSummary = publishedSummary
        self.previewText = previewText
        self.feedTitle = feedTitle
        self.authorLine = authorLine
    }

    public init(item: RSSItem, feedTitle: String? = nil, authorLine: String? = nil) {
        self.init(
            id: item.id,
            title: item.title,
            publishedSummary: item.publishedSummary,
            previewText: Self.makePreview(from: item.plainTextBody),
            feedTitle: feedTitle,
            authorLine: authorLine
        )
    }

    /// Composed "date · by Author" line for the timeline row.
    /// Bridges both fields so the view doesn't repeat the
    /// detail-header logic.
    public var dateAuthorLine: String {
        switch (publishedSummary.isEmpty, authorLine?.isEmpty ?? true) {
        case (false, false): return "\(publishedSummary) · by \(authorLine!)"
        case (false, true):  return publishedSummary
        case (true, false):  return "by \(authorLine!)"
        case (true, true):   return ""
        }
    }

    /// Collapses internal whitespace runs to single spaces, trims
    /// edges, truncates to 160 chars with an ellipsis. Exposed
    /// so tests can pin the truncation behavior.
    public static func makePreview(from body: String) -> String {
        let collapsed = body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= 160 {
            return collapsed
        }
        let cut = collapsed.prefix(160).trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }
}

public struct RSSArticleDetail: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let publishedSummary: String
    public let plainTextBody: String
    /// Paragraph-segmented version of the article HTML body —
    /// see `RSSItem.bodyParagraphs`. The detail view renders one
    /// Text per segment so paragraph structure shows up even
    /// without a rich-text widget on the SwiftOpenUI backend.
    public let bodyParagraphs: [String]
    /// Inline `<a href>` extractions from the article HTML —
    /// see `RSSItem.inlineLinks`. Detail view surfaces these as
    /// a "Links" footer so href targets survive the
    /// bodyParagraphs inline-tag strip.
    public let inlineLinks: [InlineLink]
    /// Inline `<img src>` extractions — see `RSSItem.inlineImages`.
    public let inlineImages: [InlineImage]
    public let linkURL: URL?

    public init(
        id: String,
        title: String,
        publishedSummary: String,
        plainTextBody: String,
        bodyParagraphs: [String],
        inlineLinks: [InlineLink],
        inlineImages: [InlineImage],
        linkURL: URL?
    ) {
        self.id = id
        self.title = title
        self.publishedSummary = publishedSummary
        self.plainTextBody = plainTextBody
        self.bodyParagraphs = bodyParagraphs
        self.inlineLinks = inlineLinks
        self.inlineImages = inlineImages
        self.linkURL = linkURL
    }

    public init(item: RSSItem) {
        self.init(
            id: item.id,
            title: item.title,
            publishedSummary: item.publishedSummary,
            plainTextBody: item.plainTextBody,
            bodyParagraphs: item.bodyParagraphs,
            inlineLinks: item.inlineLinks,
            inlineImages: item.inlineImages,
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
/// Timeline sort order. String-raw so values round-trip
/// through the ViewOptions JSON persistence; CaseIterable
/// for a future sort-menu picker.
public enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case newestFirst
    case oldestFirst
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .newestFirst: return "Newest First"
        case .oldestFirst: return "Oldest First"
        }
    }
}

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

    /// Per-feed item cache keyed by Feed.ID. Populated on every
    /// successful fetch. Future iterations (cross-feed smart
    /// feeds, persistence) will read from here so behavior
    /// stays correct when feeds rotate in/out of the active
    /// timeline. The legacy `items` array stays pinned to the
    /// active feed for the existing render path.
    public struct FeedCache: Sendable, Equatable {
        public var items: [RSSItem]
        public var articles: [Article]
        public var lastFetchAt: Date

        public init(items: [RSSItem] = [], articles: [Article] = [], lastFetchAt: Date = Date()) {
            self.items = items
            self.articles = articles
            self.lastFetchAt = lastFetchAt
        }
    }
    @Published var feedCaches: [Feed.ID: FeedCache] = [:]

    /// Most-recent error message per subscribed feed, keyed by
    /// `Feed.ID`. Cleared automatically on a successful fetch.
    /// Used by the feedsPane to surface a small warning icon
    /// next to feeds whose last fetch failed (404, timeout,
    /// invalid XML, etc.). Mirrors NetNewsWire's stale-feed
    /// warning behavior in its sidebar.
    /// Persisted across launches so the warning glyph survives
    /// the user closing + relaunching — they see "this feed
    /// has been failing for a week" rather than losing the
    /// breadcrumb every restart.
    @Published var feedErrors: [Feed.ID: String] = [:] {
        didSet { persistFeedErrorsIfReady() }
    }

    private func persistFeedErrorsIfReady() {
        guard persistenceReady else { return }
        persistence.saveFeedErrors(feedErrors)
    }

    /// Icon / favicon URL per subscribed feed, harvested from
    /// upstream ParsedFeed.iconURL (preferred) or faviconURL
    /// (fallback) at fetch time. Persisted to disk via
    /// PersistenceStore.feedIconURLs.json so favicons survive
    /// across launches without re-fetching every feed first.
    /// Used by the feedsPane to show a per-feed icon once an
    /// async-image-loader iteration lands.
    @Published var feedIconURLs: [Feed.ID: String] = [:] {
        didSet { persistFeedIconURLsIfReady() }
    }

    private func persistFeedIconURLsIfReady() {
        guard persistenceReady else { return }
        persistence.saveFeedIconURLs(feedIconURLs)
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

    /// Set of article IDs the user has read. Loaded from JSON
    /// on init via `PersistenceStore` and re-saved on every
    /// change so mark-as-read history survives relaunches.
    /// Flat-set shape (rather than per-feed) so re-fetched
    /// articles keep their read state — same shape as
    /// upstream NetNewsWire's `articleIDs` read-status table.
    @Published private(set) var readArticleIDs: Set<String> = [] {
        didSet {
            updateStatusText()
            persistence.saveReadArticleIDs(readArticleIDs)
        }
    }

    /// Set of starred article IDs. Same flat-set shape as
    /// readArticleIDs; persisted alongside it. Upstream
    /// NetNewsWire surfaces starred articles via the Starred
    /// smart feed and a per-article star toggle in the detail
    /// header.
    @Published private(set) var starredArticleIDs: Set<String> = [] {
        didSet { persistence.saveStarredArticleIDs(starredArticleIDs) }
    }

    private let persistence: PersistenceStore

    /// QuillData-backed SQLite store for article rows. Optional
    /// because the QuillData ModelContainer init can throw
    /// (filesystem issues, migration mismatches); we degrade
    /// gracefully — the in-memory `items` / `articles` /
    /// `feedCaches` arrays keep running, just without
    /// cross-launch SQLite persistence. Set to nil to opt out
    /// of persistence entirely.
    public let articleStore: ArticleStore?

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
        didSet {
            updateStatusText()
            persistSelectionIfReady()
        }
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
    /// through `selectedFeedID`. Auto-persists via the
    /// PersistenceStore's OPML export — every mutation writes
    /// the current list to subscriptions.opml so launches
    /// after a subscribe / unsubscribe survive.
    @Published var subscribedFeeds: [Feed] {
        didSet { persistSubscriptionsIfReady() }
    }

    /// Hierarchical mirror of `subscribedFeeds`. When the user
    /// imports an OPML file with nested folders, the structure
    /// gets preserved here (the flat list keeps every feed for
    /// callers that don't care about folders). Defaults to a
    /// single root folder holding all seeded feeds.
    @Published var subscriptionRoot: OPMLImporter.Folder
    @Published var selectedFeedID: Feed.ID? {
        didSet { persistSelectionIfReady() }
    }

    /// View-option: when true, the timeline hides articles the
    /// user has already marked-as-read. Mirrors upstream
    /// NetNewsWire's "Hide Read Articles" toggle (Cmd+Shift+U).
    /// Doesn't apply to the Starred smart feed — that view
    /// intentionally shows starred items regardless of read
    /// status — but does apply to the default feed view and to
    /// the Today smart feed. (All Unread is already unread-only
    /// by definition.) Persisted via the per-instance
    /// PersistenceStore so tests stay isolated.
    @Published var hideReadArticles: Bool {
        didSet { persistViewOptionsIfReady() }
    }

    /// View-option: timeline sort order. Mirrors upstream
    /// NetNewsWire's View › Sort menu. Applied at filteredItems
    /// time so toggling re-renders without re-parsing. Persisted
    /// via PersistenceStore.ViewOptions.
    @Published var sortOrder: SortOrder {
        didSet { persistViewOptionsIfReady() }
    }

    private var didStartInitialLoad = false
    private let initialSelectionEnvironment: [String: String]

    /// Set during init AFTER all stored properties get their
    /// values, so the subscribedFeeds didSet doesn't try to
    /// persist the initial empty-state assignment. Without
    /// this guard, every init would overwrite the OPML file
    /// with whatever happened to be assigned first.
    private var persistenceReady: Bool = false

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        subscribedFeeds: [Feed] = DefaultFeedList.seed,
        persistence: PersistenceStore = .default,
        articleStore: ArticleStore? = nil
    ) {
        self.initialSelectionEnvironment = environment
        self.persistence = persistence
        let storedOptions = persistence.loadViewOptions()
        self.hideReadArticles = storedOptions.hideReadArticles
        self.sortOrder = storedOptions.sortOrder
            .flatMap { SortOrder(rawValue: $0) } ?? .newestFirst
        // Create an on-disk ArticleStore alongside the JSON
        // persistence dir if the caller didn't supply one.
        // Try/catch is mandatory — ModelContainer init throws
        // on filesystem issues, schema mismatches, etc. and we
        // don't want a corrupted DB to crash the reader; the
        // in-memory feedCaches / items still work.
        if let articleStore {
            self.articleStore = articleStore
        } else {
            self.articleStore = try? ArticleStore(directoryURL: persistence.directoryURL)
        }
        // Subscription list precedence: persisted OPML file if
        // present, otherwise the caller-supplied seed. Lets the
        // reader's seed catalog stay as the first-launch
        // default while still picking up post-add/remove state.
        let resolvedFeeds: [Feed]
        if let data = persistence.loadOPMLExport() {
            let parsed = OPMLImporter.parseTree(data: data)
            let leaves = parsed.root.allFeeds
            resolvedFeeds = leaves.isEmpty ? subscribedFeeds : leaves
        } else {
            resolvedFeeds = subscribedFeeds
        }
        self.subscribedFeeds = resolvedFeeds
        self.selectedFeedID = resolvedFeeds.first?.id
        // Default tree is a single root folder holding every
        // seeded feed. OPML import replaces this with the
        // tree-preserving counterpart when callers reach for
        // importOPMLTree(...).
        self.subscriptionRoot = OPMLImporter.Folder(
            name: "",
            feeds: resolvedFeeds,
            subfolders: []
        )
        // Restore mark-as-read + starred history. Failed reads
        // (first launch, missing file) yield empty sets so the
        // model just starts fresh.
        self.readArticleIDs = persistence.loadReadArticleIDs()
        self.starredArticleIDs = persistence.loadStarredArticleIDs()
        self.feedIconURLs = persistence.loadFeedIconURLs()
        self.feedErrors = persistence.loadFeedErrors()
        // Hydrate feedCaches from any persisted articles so the
        // timeline shows yesterday's items before today's fetch
        // even fires. Bucket by feedID, build the (items,
        // articles, lastFetchAt) triple per group. Errors swallow
        // — the in-memory empty caches keep the reader running.
        hydrateFeedCachesFromStoreIfReady()
        // Restore sidebar selection from disk so the reader
        // resumes where the user left off. A persisted feed that
        // no longer exists (unsubscribed across launches) falls
        // through to the default first-feed selection set above.
        // Smart feed wins over feed when both are set (the
        // serializer never writes both, but be defensive).
        if let saved = persistence.loadSelection() {
            if let smart = saved.smartFeed, let kind = SmartFeed(rawValue: smart) {
                self.selectedSmartFeed = kind
            } else if let feedID = saved.feedID,
                      resolvedFeeds.contains(where: { $0.id == feedID }) {
                self.selectedFeedID = feedID
            }
        }
        self.persistenceReady = true
    }

    /// Read every PersistentArticle from the QuillData store
    /// and rebuild `feedCaches` from the groups. Called from
    /// init's tail so the timeline can render persisted state
    /// before any network fetch. Doesn't reach the active
    /// feed's `items` / `articles` arrays directly — they get
    /// populated when the user selects (or auto-selects) a
    /// feed; for now those still start empty pending fetch.
    /// The lastFetchAt per group uses the newest dateArrived
    /// across that group's rows so 'Updated N ago' is honest.
    private func hydrateFeedCachesFromStoreIfReady() {
        guard let articleStore else { return }
        guard let rows = try? articleStore.fetchAll(), !rows.isEmpty else { return }
        var grouped: [String: [PersistentArticle]] = [:]
        for row in rows {
            grouped[row.feedID, default: []].append(row)
        }
        for (feedID, group) in grouped {
            // Newest first by datePublished; matches the live
            // fetch path's sort.
            let sorted = group.sorted { lhs, rhs in
                switch (lhs.datePublished, rhs.datePublished) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.id < rhs.id
                }
            }
            let items = sorted.map { row in
                RSSItem(
                    id: row.uniqueID,
                    title: row.title ?? "Untitled",
                    link: row.url,
                    pubDate: row.datePublished?.description,
                    descriptionHTML: row.contentHTML ?? row.contentText ?? row.summary
                )
            }
            let articles = sorted.map { row in
                Article(
                    accountID: row.accountID,
                    articleID: row.id,
                    feedID: row.feedID,
                    uniqueID: row.uniqueID,
                    title: row.title,
                    contentHTML: row.contentHTML,
                    contentText: row.contentText,
                    markdown: nil,
                    url: row.url,
                    externalURL: row.externalURL,
                    summary: row.summary,
                    imageURL: row.imageURL,
                    datePublished: row.datePublished,
                    dateModified: row.dateModified,
                    authors: nil,
                    status: ArticleStatus(
                        articleID: row.id,
                        read: row.isRead,
                        starred: row.isStarred,
                        dateArrived: row.dateArrived
                    )
                )
            }
            let lastFetchAt = sorted.map(\.dateArrived).max() ?? Date()
            feedCaches[feedID] = FeedCache(
                items: items,
                articles: articles,
                lastFetchAt: lastFetchAt
            )
        }
        // If the active feed has a cache now, surface its items
        // as the live timeline so the user sees content
        // immediately on launch.
        if let activeFeedID = selectedFeedID,
           let active = feedCaches[activeFeedID] {
            self.items = active.items
            self.articles = active.articles
            self.lastFetchAt = active.lastFetchAt
            self.didStartInitialLoad = true
        }
    }

    /// Called from subscribedFeeds.didSet. Writes the current
    /// list to subscriptions.opml so subscribe / unsubscribe /
    /// reorder all survive relaunch. No-op during init (the
    /// persistenceReady gate prevents the initial assignment
    /// from clobbering disk before init has resolved the
    /// final list).
    private func persistSubscriptionsIfReady() {
        guard persistenceReady else { return }
        persistence.saveOPMLExport(exportOPMLData())
    }

    /// Mirrors persistSubscriptionsIfReady for sidebar selection
    /// (smart feed kind or subscribed feed URL). Smart feed takes
    /// priority so toggling between a feed and a smart feed
    /// writes one or the other, never both. Same persistenceReady
    /// gate prevents init-time setter chains from racing the disk
    /// write before the restored value is applied.
    private func persistSelectionIfReady() {
        guard persistenceReady else { return }
        let state: PersistenceStore.SelectionState
        if let smart = selectedSmartFeed {
            state = PersistenceStore.SelectionState(smartFeed: smart.rawValue, feedID: nil)
        } else if let feedID = selectedFeedID {
            state = PersistenceStore.SelectionState(smartFeed: nil, feedID: feedID)
        } else {
            state = PersistenceStore.SelectionState()
        }
        persistence.saveSelection(state)
    }

    private func persistViewOptionsIfReady() {
        guard persistenceReady else { return }
        persistence.saveViewOptions(PersistenceStore.ViewOptions(
            hideReadArticles: hideReadArticles,
            sortOrder: sortOrder.rawValue
        ))
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

    /// Advance to the next *unread* article in the filtered
    /// timeline (skips already-marked-read items). Wraps from
    /// no-selection to the first unread. No-op when every
    /// visible item is already read. Powers upstream NetNewsWire's
    /// 'Next Unread' command (N keyboard shortcut + button).
    @discardableResult
    func selectNextUnread() -> Bool {
        let pool = filteredItems
        guard !pool.isEmpty else { return false }
        // Find the starting index — one past the current
        // selection, or 0 when nothing is selected.
        let startIndex: Int
        if let current = selectedID,
           let idx = pool.firstIndex(where: { $0.id == current }) {
            startIndex = idx + 1
        } else {
            startIndex = 0
        }
        for i in startIndex..<pool.count {
            let item = pool[i]
            if !readArticleIDs.contains(item.id) {
                selectItem(id: item.id)
                return true
            }
        }
        return false
    }

    /// Step the selection to the previous *unread* article in
    /// the filtered timeline. Wraps from no-selection to the
    /// last unread. No-op when nothing earlier is unread.
    /// Mirrors upstream NetNewsWire's 'Previous Unread' command
    /// (⌘⇧N keyboard shortcut).
    @discardableResult
    func selectPreviousUnread() -> Bool {
        let pool = filteredItems
        guard !pool.isEmpty else { return false }
        // Starting one before the current selection, or at the
        // end when nothing is selected.
        let startIndex: Int
        if let current = selectedID,
           let idx = pool.firstIndex(where: { $0.id == current }) {
            startIndex = idx - 1
        } else {
            startIndex = pool.count - 1
        }
        guard startIndex >= 0 else { return false }
        var i = startIndex
        while i >= 0 {
            let item = pool[i]
            if !readArticleIDs.contains(item.id) {
                selectItem(id: item.id)
                return true
            }
            i -= 1
        }
        return false
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
        return added
    }

    /// Tree-preserving counterpart to `importOPML(data:)`. Sets
    /// `subscriptionRoot` to the parsed folder hierarchy AND
    /// merges every leaf feed into the flat `subscribedFeeds`
    /// list (deduped by URL). Returns the count of newly-added
    /// feeds. After-import callers that want folder rendering
    /// read `subscriptionRoot`; the existing timeline / search /
    /// smart-feed paths keep reading the flat list.
    @discardableResult
    func importOPMLTree(data: Data) -> Int {
        let tree = OPMLImporter.parseTree(data: data)
        subscriptionRoot = tree.root
        return mergeImportedFeeds(tree.root.allFeeds)
    }

    @discardableResult
    func importOPMLTree(xml: String) -> Int {
        importOPMLTree(data: Data(xml.utf8))
    }

    /// Fetch an OPML file from a URL and import its
    /// subscriptions in one shot. Pulls bytes via the upstream
    /// QuillRSWeb Downloader so we get the same conditional-GET
    /// / User-Agent / ephemeral-session handling as feed
    /// fetches. Returns the count of newly-added feeds.
    /// On failure, surfaces a one-line error via setError so
    /// the UI hint propagates through the same path as fetch
    /// errors.
    @discardableResult
    func importOPMLFromURL(_ urlString: String) async -> Int {
        let normalized = urlString.trimmingWhitespace.normalizedURL
        guard let url = URL(string: normalized) else {
            setError("Invalid OPML URL")
            return 0
        }
        do {
            let (maybeData, _) = try await Downloader.shared.download(url)
            guard let data = maybeData else {
                setError("OPML download was empty")
                return 0
            }
            return importOPMLTree(data: data)
        } catch {
            setError("OPML import failed: \(error)")
            return 0
        }
    }

    /// Serialize the current subscribed feed list as OPML 2.0.
    /// The result round-trips through `importOPML(xml:)` to the
    /// same feed list (modulo the optional list title).
    func exportOPML(title: String? = nil) -> String {
        OPMLExporter.export(feeds: subscribedFeeds, title: title)
    }

    /// Remove a subscribed feed by ID. Drops its per-feed
    /// cache, the subscription row, and any reference in
    /// subscriptionRoot (top-level + nested folders). If the
    /// removed feed was active, the selection rotates to the
    /// first remaining feed (or nil when none remain). Mirrors
    /// upstream NetNewsWire's 'Delete Subscription' command.
    /// Returns true when a feed was actually removed.
    @discardableResult
    func removeSubscription(id: Feed.ID) -> Bool {
        let beforeCount = subscribedFeeds.count
        subscribedFeeds.removeAll { $0.id == id }
        guard subscribedFeeds.count != beforeCount else { return false }
        feedCaches.removeValue(forKey: id)
        // Walk the folder tree, removing the feed from every
        // level. Folder structure stays intact; only the leaf
        // disappears.
        subscriptionRoot = Self.removeFeed(id: id, from: subscriptionRoot)
        // Rotate selection if the active feed got pulled.
        if selectedFeedID == id {
            selectedFeedID = subscribedFeeds.first?.id
            selectItem(id: nil)
            items = []
            articles = []
        }
        return true
    }

    private static func removeFeed(id: Feed.ID, from folder: OPMLImporter.Folder) -> OPMLImporter.Folder {
        var copy = folder
        copy.feeds.removeAll { $0.id == id }
        copy.subfolders = copy.subfolders.map { removeFeed(id: id, from: $0) }
        return copy
    }

    /// Take a user-entered URL (a website URL or a direct feed
    /// URL) and add a subscription. Walks the page via upstream
    /// QuillFeedFinder to discover feed links when given a
    /// website URL, then picks the best candidate and appends
    /// it to subscribedFeeds (dedupes by URL via mergeImportedFeeds).
    /// Returns the added feed, or nil if no feed was found.
    @discardableResult
    func addSubscription(urlString: String) async -> Feed? {
        let normalized = urlString.trimmingWhitespace.normalizedURL
        guard let url = URL(string: normalized) else { return nil }
        let candidates: Set<FeedSpecifier>
        do {
            candidates = try await FeedFinder.find(url: url)
        } catch {
            setError("Subscribe failed: \(error)")
            return nil
        }
        guard let best = FeedSpecifier.bestFeed(in: candidates) else {
            setError("No feed found at \(normalized)")
            return nil
        }
        let feed = Feed(title: best.title ?? best.urlString, url: best.urlString)
        let added = mergeImportedFeeds([feed])
        if added == 0 {
            // Already subscribed — return the existing record.
            return subscribedFeeds.first(where: { $0.id == feed.id })
        }
        return feed
    }

    func exportOPMLData(title: String? = nil) -> Data {
        OPMLExporter.exportData(feeds: subscribedFeeds, title: title)
    }

    /// Write the current OPML 2.0 export to disk under the
    /// PersistenceStore directory. Returns the URL on success.
    /// Used by the feedsPane Export button to give the user a
    /// concrete path they can open / copy / share. Also pins
    /// `lastOPMLExportURL` so the UI can show "Exported to ..."
    @discardableResult
    func saveOPMLExportToDisk() -> URL? {
        let data = exportOPMLData()
        guard let url = persistence.saveOPMLExport(data) else { return nil }
        lastOPMLExportURL = url
        return url
    }

    /// Path of the most recent OPML export, or nil when nothing
    /// has been exported yet. Surfaces in feedsPane footer so
    /// the user sees where the file landed.
    @Published var lastOPMLExportURL: URL?

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

    /// Walk every subscribed feed (except the currently-active
    /// one, which gets refreshed via `refresh`) and fetch each
    /// into `feedCaches` without disturbing the timeline. Powers
    /// upstream NetNewsWire's 'Refresh All' command (⌘⌥R).
    ///
    /// Sequential rather than parallel so the in-tree
    /// QuillRSWeb.DownloadSession's single-host connection
    /// limit stays honored across the batch; future
    /// performance work can add a small concurrency window.
    /// Per-feed errors are swallowed (cache stays at prior
    /// state for that feed) so one bad feed doesn't abort the
    /// whole pass.
    func refreshAllFeeds() async {
        guard !isLoading else { return }
        // Refresh active feed first so its UI updates promptly,
        // then drain the others into the cache only.
        if let activeURL = currentFeedURL {
            await fetch(urlString: activeURL)
        }
        for feed in subscribedFeeds where feed.url != currentFeedURL {
            await fetchIntoCache(urlString: feed.url)
        }
    }

    /// Internal: parse-and-cache for a single feed URL,
    /// touching only `feedCaches[feedID]`. Doesn't update
    /// `items`, `articles`, `selectedID`, `feedTitle`, or
    /// `lastFetchAt` since those track the currently-displayed
    /// feed. Errors are swallowed.
    /// Per-feed refresh. Active feed routes through fetch() so
    /// the timeline + articles update; any other feed routes
    /// through fetchIntoCache() so the cache + persistence
    /// update without disturbing the active selection. Mirrors
    /// upstream NetNewsWire's per-feed refresh action (the
    /// circular-arrow button next to a feed row in inspector
    /// and the keyboard-driven "Refresh Feed" command).
    func refreshFeed(urlString: String) async {
        guard !isLoading else { return }
        if urlString == currentFeedURL {
            await refresh(urlString: urlString)
        } else {
            await fetchIntoCache(urlString: urlString)
        }
    }

    private func fetchIntoCache(urlString: String) async {
        guard let url = URL(string: urlString) else {
            feedErrors[urlString] = "Invalid URL"
            return
        }
        do {
            let (maybeData, _) = try await Downloader.shared.download(url)
            guard let data = maybeData else {
                feedErrors[urlString] = "Empty response"
                return
            }
            let parsed = RSSFeedParser.parseUpstream(data: data, url: urlString)
            let upstreamArticles = RSSFeedParser.parseUpstreamArticles(data: data, url: urlString)
            let trimmedItems = Array(parsed.items.prefix(50))
            let trimmedArticles = Array(upstreamArticles.prefix(50))
            feedCaches[urlString] = FeedCache(
                items: trimmedItems,
                articles: trimmedArticles,
                lastFetchAt: Date()
            )
            // Mirror the active-feed fetch() path: persist
            // every refresh-all batch into SQLite too so
            // background refreshes accumulate cross-feed
            // articles on disk.
            if let articleStore {
                let rows = trimmedArticles.map { article in
                    PersistentArticle(
                        article,
                        isRead: readArticleIDs.contains(article.uniqueID),
                        isStarred: starredArticleIDs.contains(article.uniqueID)
                    )
                }
                try? articleStore.upsert(rows)
            }
            // Successful refresh-all path clears any prior error.
            feedErrors[urlString] = nil
            // Same icon-URL harvest as the active fetch path.
            if let icon = parsed.iconURL ?? parsed.faviconURL {
                feedIconURLs[urlString] = icon
            }
        } catch {
            // Quiet on the global Refresh-All path — one bad
            // feed shouldn't bust the whole pass — but stash
            // the error so feedsPane can show a warning glyph.
            feedErrors[urlString] = "\(error)"
        }
    }

    func fetch(urlString: String) async {
        guard let url = URL(string: urlString) else {
            setError("Invalid URL")
            feedErrors[urlString] = "Invalid URL"
            setLoading(false)
            return
        }
        setLoading(true)
        setError(nil)
        do {
            // Upstream RSWeb Downloader: ephemeral session, no
            // cookies, single-host connection limit, NNW
            // User-Agent header set by UserAgent.headers(), and
            // short-lived in-memory DownloadCache that collapses
            // overlapping concurrent requests to the same URL.
            // Conditional-GET (Etag/Last-Modified) lands when
            // the persistence iteration starts threading
            // HTTPConditionalGetInfo across fetches.
            let (maybeData, _) = try await Downloader.shared.download(url)
            guard let data = maybeData else {
                self.setError("Empty response")
                feedErrors[urlString] = "Empty response"
                setLoading(false)
                return
            }
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
            let trimmedItems = Array(parsed.items.prefix(50))
            let trimmedArticles = Array(upstreamArticles.prefix(50))
            let now = Date()
            self.setItems(trimmedItems)
            self.articles = trimmedArticles
            // Store the same data in the per-feed cache so
            // cross-feed roll-ups (unread badges, smart feeds)
            // stay accurate after this fetch even if the user
            // switches to a different feed. Cache key is the
            // fetched URL itself — matches Feed.id default.
            self.feedCaches[urlString] = FeedCache(
                items: trimmedItems,
                articles: trimmedArticles,
                lastFetchAt: now
            )
            // Persist parsed articles to SQLite via QuillData.
            // Marks each row's isRead / isStarred from the
            // in-memory sets so a relaunch reconstitutes the
            // user's mark-as-read history without rerunning
            // every per-feed fetch. Failures are silent so a
            // flaky disk doesn't degrade the read experience.
            if let articleStore {
                let rows = trimmedArticles.map { article in
                    PersistentArticle(
                        article,
                        isRead: readArticleIDs.contains(article.uniqueID),
                        isStarred: starredArticleIDs.contains(article.uniqueID)
                    )
                }
                try? articleStore.upsert(rows)
            }
            if self.selectedID == nil {
                self.selectItem(id: self.preferredInitialItemID(in: self.items))
            }
            self.lastFetchAt = now
            // Successful fetch clears any prior error tracked
            // for this feed.
            self.feedErrors[urlString] = nil
            // Harvest the feed-declared icon URL if present.
            // Prefer iconURL (RSS image / Atom logo / JSON Feed
            // icon — the spec-canonical site icon) over
            // faviconURL (which upstream populates from
            // <link rel="icon"> when present).
            if let icon = parsed.iconURL ?? parsed.faviconURL {
                self.feedIconURLs[urlString] = icon
            }
        } catch {
            self.setError("\(error)")
            self.feedErrors[urlString] = "\(error)"
        }
        setLoading(false)
    }

    /// Human-readable "Updated N ago" string for the footer
    /// status bar. Empty when no fetch has happened yet so the
    /// footer falls through to the regular item-count text.
    /// Refreshes on every call against the current wall clock
    /// (callers should re-read whenever they re-render the
    /// footer; relativeFormatter is locale-aware).
    var lastFetchSummary: String {
        guard let date = lastFetchAt else { return "" }
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 5 {
            return "Updated just now"
        }
        let formatted = Self.relativeString(for: date, relativeTo: now)
        return "Updated \(formatted)"
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
    /// elapsed, refresh every subscribed feed (active feed first
    /// for snappy UI, then cached fetches for the rest). Pure
    /// async function — the looping Task in
    /// `startBackgroundRefresh()` calls this between sleeps so
    /// tests can exercise the eligibility logic without a timer.
    ///
    /// Upstream NetNewsWire's background refresh keeps every
    /// feed warm so opening any feed in the sidebar shows the
    /// latest items without an explicit refresh; the previous
    /// implementation only kept the active feed fresh, which
    /// left every other cache stale until manual Refresh All.
    func backgroundRefreshTick(now: Date = Date()) async {
        guard isAutoRefreshDue(now: now) else { return }
        // No subscriptions → nothing to do (and refreshAllFeeds
        // returns immediately too, but skip the function-call
        // overhead on every tick).
        guard !subscribedFeeds.isEmpty else { return }
        await refreshAllFeeds()
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
    /// Propagates the change to the QuillData ArticleStore so
    /// the SQLite row's isRead bit updates without waiting for
    /// the next fetch — keeps the on-disk view in sync with
    /// the in-memory set.
    func markRead(id: String) {
        if readArticleIDs.insert(id).inserted {
            // didSet on readArticleIDs handles status text refresh.
            persistReadStateChange(uniqueID: id, isRead: true)
        }
    }

    /// Explicit mark-as-unread, symmetric to markRead. Idempotent
    /// — only triggers persistence + status text refresh when the
    /// removal actually changes the Set. Powers a future U
    /// keyboard shortcut + Mark Unread menu item, and is the
    /// shape upstream NetNewsWire's NSCommand expects.
    func markUnread(id: String) {
        if readArticleIDs.remove(id) != nil {
            persistReadStateChange(uniqueID: id, isRead: false)
        }
    }

    /// Mark the currently-selected article unread. No-op when
    /// no selection. Powers the U keyboard shortcut.
    func markUnreadOnSelection() {
        guard let selectedID else { return }
        markUnread(id: selectedID)
    }

    /// Propagate a single article's read/starred change to the
    /// ArticleStore. Translates the uniqueID (which is what
    /// readArticleIDs / starredArticleIDs sets carry) into the
    /// PersistentArticle id via the per-feed cache lookup. No-op
    /// when the article isn't yet in the store (e.g. fixtures
    /// that bypass fetch). Failures swallow so a flaky disk
    /// doesn't corrupt the in-memory state.
    private func persistReadStateChange(uniqueID: String, isRead: Bool) {
        guard let store = articleStore else { return }
        for (_, cache) in feedCaches {
            if let article = cache.articles.first(where: { $0.uniqueID == uniqueID }) {
                try? store.markRead(articleID: article.articleID)
                return
            }
        }
    }

    private func persistStarredStateChange(uniqueID: String, starred: Bool) {
        guard let store = articleStore else { return }
        for (_, cache) in feedCaches {
            if let article = cache.articles.first(where: { $0.uniqueID == uniqueID }) {
                try? store.markStarred(articleID: article.articleID, starred: starred)
                return
            }
        }
    }

    /// Mark every article in the currently-visible filtered
    /// timeline as read. Mirrors upstream NetNewsWire's
    /// 'Mark All Read' command (⌘⇧K). Returns the number of
    /// articles newly marked, so a UI surface can show
    /// "Marked 7 as read" feedback. No-op when the visible
    /// timeline is already fully-read or empty.
    @discardableResult
    func markAllVisibleAsRead() -> Int {
        let visibleIDs = filteredItems.map(\.id)
        let before = readArticleIDs.count
        for id in visibleIDs {
            // Route through markRead (not direct Set insert) so
            // each newly-marked article also propagates to the
            // ArticleStore. didSet still fires once per inserted
            // ID; persistence is per-row but batched closely so
            // SQLite handles it as one transaction.
            markRead(id: id)
        }
        return readArticleIDs.count - before
    }

    /// Mark every article above the current selection (in the
    /// filtered timeline) as read. Mirrors upstream NetNewsWire's
    /// 'Mark Above as Read' command. No-op when there's no
    /// selection or the selection is the first visible item.
    @discardableResult
    func markAboveSelectionAsRead() -> Int {
        guard let selectedID,
              let index = filteredItems.firstIndex(where: { $0.id == selectedID }),
              index > 0
        else { return 0 }
        let before = readArticleIDs.count
        for item in filteredItems.prefix(index) {
            markRead(id: item.id)
        }
        return readArticleIDs.count - before
    }

    /// Mark every article below the current selection (in the
    /// filtered timeline) as read. Mirrors upstream NetNewsWire's
    /// 'Mark Below as Read' command. No-op when there's no
    /// selection or the selection is the last visible item.
    @discardableResult
    func markBelowSelectionAsRead() -> Int {
        guard let selectedID,
              let index = filteredItems.firstIndex(where: { $0.id == selectedID }),
              index + 1 < filteredItems.count
        else { return 0 }
        let before = readArticleIDs.count
        for item in filteredItems.suffix(from: index + 1) {
            markRead(id: item.id)
        }
        return readArticleIDs.count - before
    }

    /// Toggle read state on the currently-selected article. Wired
    /// to a future keyboard shortcut + a Mark Unread menu item.
    func toggleReadOnSelection() {
        guard let selectedID else { return }
        if readArticleIDs.contains(selectedID) {
            readArticleIDs.remove(selectedID)
            persistReadStateChange(uniqueID: selectedID, isRead: false)
        } else {
            readArticleIDs.insert(selectedID)
            persistReadStateChange(uniqueID: selectedID, isRead: true)
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
            persistStarredStateChange(uniqueID: id, starred: false)
        } else {
            starredArticleIDs.insert(id)
            persistStarredStateChange(uniqueID: id, starred: true)
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

    /// Cross-reference helper: the upstream Article for a
    /// given item ID, if it's in the parallel articles array.
    /// Detail view uses it to surface the upstream-only fields
    /// (datePublished as real Date, authors set).
    func article(forItem itemID: String) -> Article? {
        articles.first(where: { $0.uniqueID == itemID })
    }

    /// Format an article's publish date for display in the
    /// detail header. Recent items (<24h) render as relative
    /// ("3 hours ago"); older items use a medium-style date.
    /// Falls back to the empty string when no parsed Date is
    /// available (caller can fall back to raw publishedSummary).
    func friendlyDateString(forItemID itemID: String) -> String {
        guard let article = article(forItem: itemID),
              let date = article.datePublished else {
            return ""
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(date)
        if elapsed >= 0 && elapsed < 86_400 {
            // Within 24h — relative form via Foundation's
            // RelativeDateTimeFormatter. Same conventions
            // upstream NNW uses for its "x hours ago" footer.
            return Self.relativeString(for: date, relativeTo: now)
        }
        return Self.absoluteFormatter.string(from: date)
    }

    /// Comma-joined author names for an article, or nil when
    /// the upstream parser didn't surface any. Detail header
    /// prepends 'by ' when rendering.
    func authorLine(forItemID itemID: String) -> String? {
        guard let article = article(forItem: itemID),
              let authors = article.authors, !authors.isEmpty else {
            return nil
        }
        let names = authors.compactMap(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.sorted().joined(separator: ", ")
    }

    /// "N of M" breadcrumb for the selected article within the
    /// current filtered timeline. Nil when nothing is selected
    /// or when the selection has fallen out of filteredItems
    /// (e.g. an active search hides it). 1-indexed; mirrors
    /// upstream NetNewsWire's detail-header position indicator.
    func selectionPositionLabel() -> String? {
        guard let id = selectedID else { return nil }
        let filtered = filteredItems
        guard let index = filtered.firstIndex(where: { $0.id == id }) else { return nil }
        return "\(index + 1) of \(filtered.count)"
    }

    #if canImport(Darwin)
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
    /// Darwin path delegates to Foundation's locale-aware
    /// RelativeDateTimeFormatter.
    static func relativeString(for date: Date, relativeTo now: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: now)
    }
    #else
    /// swift-corelibs-foundation has no RelativeDateTimeFormatter,
    /// so on Linux we synthesize 'N minutes/hours/days ago' from
    /// the time difference. Past tense only; future dates render
    /// 'in N units'. Plural/singular handled. Matches the shape
    /// of Apple's full-units-style output closely enough for the
    /// footer + detail-header strings to read naturally.
    static func relativeString(for date: Date, relativeTo now: Date) -> String {
        let delta = now.timeIntervalSince(date)
        let absDelta = abs(delta)
        let inPast = delta >= 0
        let (value, unit): (Int, String)
        if absDelta < 60 {
            value = Int(absDelta)
            unit = "second"
        } else if absDelta < 3600 {
            value = Int(absDelta / 60)
            unit = "minute"
        } else if absDelta < 86_400 {
            value = Int(absDelta / 3600)
            unit = "hour"
        } else if absDelta < 86_400 * 7 {
            value = Int(absDelta / 86_400)
            unit = "day"
        } else {
            value = Int(absDelta / (86_400 * 7))
            unit = "week"
        }
        let units = value == 1 ? unit : "\(unit)s"
        return inPast ? "\(value) \(units) ago" : "in \(value) \(units)"
    }
    #endif

    private static let absoluteFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Item count for a given smart feed across every cached
    /// feed (plus the active feed's live items, deduped). Used
    /// by the feedsPane badge next to each Smart Feed row.
    /// Mirrors filteredItems' cross-feed scope so the badge
    /// matches what selecting the smart feed will reveal.
    func count(for smart: SmartFeed) -> Int {
        // Build the same deduped union as filteredItems.
        var seen = Set<String>()
        var union: [RSSItem] = []
        for item in items {
            if seen.insert(item.id).inserted { union.append(item) }
        }
        for (_, cache) in feedCaches {
            for item in cache.items {
                if seen.insert(item.id).inserted { union.append(item) }
            }
        }
        switch smart {
        case .today:
            let cutoff = Date().addingTimeInterval(-86_400)
            let allArticles = articles + feedCaches.values.flatMap(\.articles)
            let recentIDs = Set(allArticles.compactMap { article -> String? in
                guard let d = article.datePublished, d >= cutoff else { return nil }
                return article.uniqueID
            })
            return union.reduce(0) { $0 + (recentIDs.contains($1.id) ? 1 : 0) }
        case .allUnread:
            return union.reduce(0) { $0 + (readArticleIDs.contains($1.id) ? 0 : 1) }
        case .starred:
            return union.reduce(0) { $0 + (starredArticleIDs.contains($1.id) ? 1 : 0) }
        }
    }

    /// Unread count for a subscribed feed. Reads from the
    /// per-feed cache populated by fetch(); falls back to the
    /// active feed's `unreadCount` when querying the
    /// currently-selected feed (since `items` is its latest
    /// state). Returns 0 for feeds that haven't been fetched
    /// yet (no cache entry).
    func unreadCount(forFeed feedID: Feed.ID) -> Int {
        if feedID == selectedFeedID {
            return unreadCount
        }
        guard let cache = feedCaches[feedID] else { return 0 }
        return cache.items.reduce(0) { acc, item in
            acc + (readArticleIDs.contains(item.id) ? 0 : 1)
        }
    }

    /// Rolled-up unread count for an OPML folder — sums
    /// `unreadCount(forFeed:)` over every leaf feed (recursive
    /// through subfolders). Today this is non-zero only when
    /// the folder contains the active feed (since unread state
    /// is tracked only for the active feed). When the
    /// persistence iteration lands a per-feed article cache,
    /// every folder will report the accurate roll-up.
    func unreadCount(in folder: OPMLImporter.Folder) -> Int {
        folder.allFeeds.reduce(0) { acc, feed in
            acc + unreadCount(forFeed: feed.id)
        }
    }

    /// Mark every article in a single feed as read without
    /// requiring that feed to be the active selection. Walks the
    /// feed's cached items (or the active feed's live items when
    /// it matches selectedFeedID), routes through markRead(id:)
    /// so the change propagates to readArticleIDs + ArticleStore
    /// + JSON persistence. Returns the count of newly-marked
    /// rows. Mirrors upstream NetNewsWire's feed-row "Mark All
    /// as Read" context-menu command.
    @discardableResult
    func markFeedAsRead(_ feedID: Feed.ID) -> Int {
        let before = readArticleIDs.count
        if feedID == selectedFeedID {
            for item in items {
                markRead(id: item.id)
            }
        } else if let cache = feedCaches[feedID] {
            for item in cache.items {
                markRead(id: item.id)
            }
        }
        return readArticleIDs.count - before
    }

    /// Mark every article across every feed inside an OPML folder
    /// (recursive via allFeeds) as read. Walks each feed's cached
    /// items + the active feed's live items, routes through
    /// markRead(id:) so the change propagates to readArticleIDs
    /// + the ArticleStore + the JSON persistence. Returns the
    /// count of newly-marked rows. Mirrors upstream NetNewsWire's
    /// 'Mark All as Read in [Folder]' menu command.
    @discardableResult
    func markFolderAsRead(_ folder: OPMLImporter.Folder) -> Int {
        let before = readArticleIDs.count
        for feed in folder.allFeeds {
            if feed.id == selectedFeedID {
                // Active feed: hit the live items so the badge
                // updates this tick.
                for item in items {
                    markRead(id: item.id)
                }
            } else if let cache = feedCaches[feed.id] {
                for item in cache.items {
                    markRead(id: item.id)
                }
            }
        }
        return readArticleIDs.count - before
    }

    /// Items in the current timeline that match the active smart
    /// feed (if any) AND the active search query (if any). When
    /// both filters are empty, returns the full items list. Smart
    /// feed runs first so the search field narrows whatever the
    /// smart-feed view is showing.
    ///
    /// Smart feeds aggregate ACROSS every fetched feed via the
    /// per-feed cache (the active feed's items are merged in
    /// since they may be newer than its cached snapshot). When
    /// no smart feed is active, scope is the active feed's
    /// timeline only.
    var filteredItems: [RSSItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchActive = !trimmed.isEmpty
        // Smart feeds and active-search both want cross-feed
        // scope (the user's intent in both cases is "find this
        // across everything I'm subscribed to"). Only the
        // default-active-feed view stays scoped to items.
        let pool: [RSSItem]
        if selectedSmartFeed != nil || searchActive {
            var seen = Set<String>()
            var combined: [RSSItem] = []
            for item in items {
                if seen.insert(item.id).inserted { combined.append(item) }
            }
            for (_, cache) in feedCaches {
                for item in cache.items {
                    if seen.insert(item.id).inserted { combined.append(item) }
                }
            }
            if let smart = selectedSmartFeed {
                switch smart {
                case .today:
                    let cutoff = Date().addingTimeInterval(-86_400)
                    let allArticles = articles + feedCaches.values.flatMap(\.articles)
                    let todayIDs = Set(allArticles.compactMap { article -> String? in
                        guard let published = article.datePublished, published >= cutoff else {
                            return nil
                        }
                        return article.uniqueID
                    })
                    pool = combined.filter { todayIDs.contains($0.id) }
                case .allUnread:
                    pool = combined.filter { !readArticleIDs.contains($0.id) }
                case .starred:
                    pool = combined.filter { starredArticleIDs.contains($0.id) }
                }
            } else {
                pool = combined
            }
        } else {
            pool = items
        }
        if searchActive {
            let needle = trimmed.lowercased()
            return applySortOrder(applyHideRead(pool.filter { item in
                if item.title.lowercased().contains(needle) { return true }
                if item.plainTextBody.lowercased().contains(needle) { return true }
                return false
            }))
        }
        return applySortOrder(applyHideRead(pool))
    }

    /// Filter out read items from `pool` when the user toggled
    /// "Hide Read Articles" on. Skipped when the active view is
    /// the Starred smart feed (starred items stay visible
    /// regardless of read state, matching upstream NetNewsWire)
    /// or the All Unread smart feed (already unread-only). No
    /// allocation when the toggle is off.
    private func applyHideRead(_ pool: [RSSItem]) -> [RSSItem] {
        guard hideReadArticles else { return pool }
        if selectedSmartFeed == .starred { return pool }
        if selectedSmartFeed == .allUnread { return pool }
        return pool.filter { !readArticleIDs.contains($0.id) }
    }

    /// Apply `sortOrder` to `pool`. Cross-feed views (smart feed
    /// or active search) cross feed boundaries, so first-seen
    /// dedupe order from filteredItems leaves rows grouped by
    /// source feed rather than ordered by date. Use the parallel
    /// `articles` lookup (active feed + every cached feed) to
    /// sort by datePublished. nil dates sort last in both
    /// directions; uniqueID tiebreaker keeps the sort stable.
    /// Active-feed-only views were already sorted newest-first
    /// at parse time, so re-running sort is cheap there.
    private func applySortOrder(_ pool: [RSSItem]) -> [RSSItem] {
        // Build a [itemID: Date?] lookup from articles.
        var dateByID: [String: Date] = [:]
        for article in articles {
            if let d = article.datePublished {
                dateByID[article.uniqueID] = d
            }
        }
        for (_, cache) in feedCaches {
            for article in cache.articles {
                if dateByID[article.uniqueID] == nil, let d = article.datePublished {
                    dateByID[article.uniqueID] = d
                }
            }
        }
        return pool.sorted { lhs, rhs in
            let lDate = dateByID[lhs.id]
            let rDate = dateByID[rhs.id]
            switch (lDate, rDate) {
            case let (l?, r?) where l != r:
                return sortOrder == .newestFirst ? l > r : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.id < rhs.id
            }
        }
    }

    /// Headline + detail strings for the timeline empty state.
    /// Tailored to why the timeline is empty: in-flight fetch,
    /// active search with no matches, smart feed with no items,
    /// Hide Read filtering everything out, or a genuinely empty
    /// feed. Mirrors upstream NetNewsWire's empty placeholders.
    func emptyTimelineMessage() -> (headline: String, detail: String) {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLoading {
            return ("Loading…", "Fetching articles.")
        }
        if !trimmedQuery.isEmpty {
            return (
                "No Articles Match",
                "No articles contain \u{201C}\(trimmedQuery)\u{201D}."
            )
        }
        if let smart = selectedSmartFeed {
            switch smart {
            case .today:     return ("No Articles Today", "Nothing published in the last 24 hours.")
            case .allUnread: return ("All Read", "Every article in every feed is marked read.")
            case .starred:   return ("No Starred Articles", "Star an article to add it here.")
            }
        }
        if hideReadArticles && !items.isEmpty {
            return (
                "No Unread Articles",
                "Toggle \u{201C}Show Read\u{201D} to see articles you have already read."
            )
        }
        return ("No Articles", "This feed has no articles to show.")
    }

    /// Row projection of `filteredItems` for the timeline view to
    /// render. Kept as a computed (rather than a stored @Published
    /// shadow) so the search filter doesn't require a parallel
    /// invalidation path for every items / searchQuery change.
    ///
    /// In cross-feed contexts (smart feed or active search) every
    /// row carries its source feedTitle so the timeline can label
    /// which feed each article came from. In the default active-
    /// feed context the title is nil (the sidebar already shows
    /// the feed, repeating it per-row is noise).
    var filteredRows: [RSSArticleRow] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let crossFeed = selectedSmartFeed != nil || !trimmed.isEmpty
        guard crossFeed else {
            return filteredItems.map { item in
                RSSArticleRow(
                    item: item,
                    feedTitle: nil,
                    authorLine: authorLine(forItemID: item.id)
                )
            }
        }
        // Build itemID → feedURL once so each row lookup is O(1).
        // Active feed's items use currentFeedURL; cached items use
        // their cache key.
        var itemFeedURL: [String: String] = [:]
        if let activeURL = currentFeedURL {
            for item in items {
                itemFeedURL[item.id] = activeURL
            }
        }
        for (feedURL, cache) in feedCaches {
            for item in cache.items where itemFeedURL[item.id] == nil {
                itemFeedURL[item.id] = feedURL
            }
        }
        // Lookup feed title via subscribedFeeds (URL is the join key).
        let feedTitleByURL = Dictionary(
            uniqueKeysWithValues: subscribedFeeds.map { ($0.url, $0.title) }
        )
        return filteredItems.map { item in
            let title = itemFeedURL[item.id].flatMap { feedTitleByURL[$0] }
            return RSSArticleRow(
                item: item,
                feedTitle: title,
                authorLine: authorLine(forItemID: item.id)
            )
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
        // Closure rather than function-reference because the
        // RSSArticleRow init signature uses default args (feed
        // Title:), which doesn't bind to a bare init reference.
        let nextRows = items.map { RSSArticleRow(item: $0) }
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
        /// Feed-level metadata captured from upstream ParsedFeed.
        /// homePageURL is the feed's site; iconURL/faviconURL
        /// are the channel-declared icons (RSS 2.0 channel/image,
        /// Atom <icon>/<logo>, JSON Feed icon/favicon). The model
        /// stashes these in feedIconURLs so the sidebar can show
        /// per-feed favicons once an image-loader lands.
        var homePageURL: String?
        var iconURL: String?
        var faviconURL: String?
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
        return Result(
            title: parsed.title,
            items: rssItems,
            homePageURL: parsed.homePageURL,
            iconURL: parsed.iconURL,
            faviconURL: parsed.faviconURL
        )
    }

    /// Translate one upstream ParsedItem into our local RSSItem
    /// shape. Body falls back through contentHTML → contentText
    /// → summary → nil. Title falls back to "Untitled" so the
    /// timeline always renders something. pubDate gets ISO 8601
    /// formatted when the upstream DateParser produced a Date.
    static func adaptParsedItem(_ item: ParsedItem) -> RSSItem {
        let title = (item.title?.isEmpty == false) ? item.title! : "Untitled"
        let body = item.contentHTML ?? item.contentText ?? item.summary
        return RSSItem(
            id: item.uniqueID,
            title: title,
            link: item.url,
            pubDate: formatPubDate(item.datePublished),
            descriptionHTML: body
        )
    }

    static func formatPubDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.iso8601Formatter.string(from: date)
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
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

private extension String {
    func stripBasicHTML() -> String {
        let withoutTags = self.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return HTMLEntities.decode(withoutTags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract `<a href="...">text</a>` anchors from an HTML
    /// body. Returns InlineLinks in source order. Empty when
    /// no anchors found. Used by the detail view to surface
    /// href targets that bodyParagraphs strips away with its
    /// inline-tag pass.
    ///
    /// Implementation: NSRegularExpression scan over
    /// `<a[^>]*href=["']...["'][^>]*>(text)</a>` so both
    /// single- and double-quoted hrefs are caught. The matched
    /// anchor text is HTML-entity-decoded and stripped of any
    /// nested inline tags (rare, but defensive). Empty-href
    /// anchors are skipped.
    func htmlInlineLinks() -> [InlineLink] {
        guard !isEmpty else { return [] }
        let pattern = #"<a\s[^>]*href\s*=\s*(?:\"([^\"]*)\"|'([^']*)')[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return [] }
        let nsself = self as NSString
        let matches = regex.matches(in: self, range: NSRange(location: 0, length: nsself.length))
        var out: [InlineLink] = []
        for m in matches {
            let hrefRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard hrefRange.location != NSNotFound else { continue }
            let href = nsself.substring(with: hrefRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            let textRange = m.range(at: 3)
            let rawText = textRange.location != NSNotFound ? nsself.substring(with: textRange) : ""
            let cleanedText = HTMLEntities.decode(
                rawText.replacingOccurrences(
                    of: "<[^>]+>", with: "", options: .regularExpression
                )
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(InlineLink(text: cleanedText, urlString: href))
        }
        return out
    }

    /// Extract `<img src>` tags from an HTML body. Returns
    /// InlineImages in source order. Empty when no images
    /// found. Handles attribute orders flexibly — src can come
    /// before or after alt. Skips data: URIs (inline encoded
    /// images aren't useful for the detail-view URL list).
    func htmlInlineImages() -> [InlineImage] {
        guard !isEmpty else { return [] }
        // Pull every <img ...> tag, then pluck src + alt from
        // each attribute string separately so attribute order
        // doesn't matter.
        let tagPattern = #"<img\b[^>]*>"#
        guard let tagRegex = try? NSRegularExpression(
            pattern: tagPattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let nsself = self as NSString
        let tagMatches = tagRegex.matches(
            in: self, range: NSRange(location: 0, length: nsself.length)
        )
        var out: [InlineImage] = []
        for tm in tagMatches {
            let tagText = nsself.substring(with: tm.range)
            let src = Self.attribute("src", from: tagText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !src.isEmpty, !src.hasPrefix("data:") else { continue }
            let alt = HTMLEntities.decode(Self.attribute("alt", from: tagText))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(InlineImage(urlString: src, alt: alt))
        }
        return out
    }

    /// Extract a single attribute value from one tag's text.
    /// Matches both double- and single-quoted forms. Returns
    /// an empty string when the attribute is missing.
    static func attribute(_ name: String, from tagText: String) -> String {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.caseInsensitive]
        ) else { return "" }
        let ns = tagText as NSString
        guard let m = regex.firstMatch(in: tagText, range: NSRange(location: 0, length: ns.length))
        else { return "" }
        let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
        guard r.location != NSNotFound else { return "" }
        return ns.substring(with: r)
    }

    /// Split HTML body on block-level boundaries, returning a
    /// non-empty paragraph list. Each paragraph has its inline
    /// HTML stripped and entities decoded. Same shape upstream
    /// NetNewsWire uses to render multi-paragraph article
    /// bodies in its iOS WebKit-free renderer fallback.
    ///
    /// Splits on opening + closing forms of: p, br, hr, h1..h6,
    /// li, blockquote, div. The `\n` boundary token sneaks in
    /// after each block element so a single regex .components
    /// pass produces the segments.
    func htmlParagraphs() -> [String] {
        guard !isEmpty else { return [] }
        // Insert a marker character at every block-level boundary,
        // then split on it. The marker is `\u{2029}` (PARAGRAPH
        // SEPARATOR) so it can't collide with any feed content.
        let blockTags = "p|br|hr|h[1-6]|li|blockquote|div|tr"
        let pattern = "</?(?:\(blockTags))(?:\\s[^>]*)?/?\\s*>"
        var work = self.replacingOccurrences(
            of: pattern,
            with: "\u{2029}",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip the remaining (inline) tags.
        work = work.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return work
            .components(separatedBy: "\u{2029}")
            .map { HTMLEntities.decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
