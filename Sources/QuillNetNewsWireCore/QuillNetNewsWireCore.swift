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
    @State private var pendingDeleteFeedID: Feed.ID? = nil
    @State private var pendingDeleteFolderName: String? = nil
    @State private var renameFeedInput: String = ""
    @State private var renameFolderName: String? = nil
    @State private var renameFolderInput: String = ""
    @State private var addFolderInput: String = ""
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.openURL) private var openURL

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
            .onChange(of: model.selectedFeedID) { _ in
                // Switching feeds disarms the pending-delete state.
                // Otherwise returning to a previously-armed row
                // would let a single click delete without a fresh
                // confirmation, defeating the "are you sure?" UX.
                pendingDeleteFeedID = nil
                pendingDeleteFolderName = nil
            }
            .onChange(of: model.selectedFolderName) { _ in
                // Same disarm logic for folder selection: armed
                // delete state should not survive navigation to a
                // different folder or back out to a feed.
                pendingDeleteFeedID = nil
                pendingDeleteFolderName = nil
            }
            .onChange(of: model.selectedSmartFeed) { _ in
                // And for smart-feed navigation (Today/All/Starred).
                pendingDeleteFeedID = nil
                pendingDeleteFolderName = nil
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
        // Wrap body in ScrollView so content fits at the
        // current frame size — iter #190's Move-to picker can
        // surface a long list of folders, iter #199's reorder
        // buttons add more vertical density, and stats blocks
        // (per-feed cache + errors + back-off counter) can pile
        // up. Without scrolling, tall content gets clipped by
        // the fixed 360-pt height. ScrollView preserves the
        // sheet's compact footprint without losing access to
        // anything below the fold.
        let feed = model.subscribedFeeds.first(where: { $0.id == inspectedFeedID })
        return ScrollView {
            inspectorBody(feed)
                .padding(.bottom, 8)
        }
        .frame(width: 380, height: 480)
    }

    private func inspectorBody(_ feed: Feed?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Feed Info").font(.title2).bold()
            if let feed {
                VStack(alignment: .leading, spacing: 4) {
                    // Same empty-title fallback as feedRow.
                    Text(feed.title.isEmpty ? (feed.url.isEmpty ? "Untitled" : feed.url) : feed.title)
                        .font(.headline)
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
                        // Last-published article time: useful
                        // diagnostic for "is this feed still
                        // alive?" — a feed whose lastFetchAt is
                        // 5 minutes ago but whose newest article
                        // is 6 months old is probably abandoned
                        // by the publisher. Walks cache.articles
                        // for the max datePublished; falls
                        // through silently when no article has
                        // a parsed Date.
                        if let newest = cache.articles
                            .compactMap(\.datePublished).max() {
                            Text("Latest post · \(RSSReaderModel.relativeString(for: newest, relativeTo: Date()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    // No cache → feed has never been fetched
                    // successfully. Surface that explicitly so
                    // user knows "Refresh" hasn't run for this
                    // feed yet (vs. "cache exists but is stale").
                    Text("Never fetched")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                        if let when = model.feedLastErrorAt[feed.id] {
                            Text("Last error · \(RSSReaderModel.relativeString(for: when, relativeTo: Date()))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Last error")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(4)
                    }
                }
                let failCount = model.feedFailureCount[feed.id] ?? 0
                if failCount >= RSSReaderModel.feedFailureSkipThreshold {
                    // Tell the user the background batch is now
                    // skipping this feed and how to recover. The
                    // Refresh button (above) is the recovery
                    // path — explicit fetches always try. The
                    // per-feed Reset button below clears just
                    // THIS feed's counter without running a
                    // network round-trip (useful when the user
                    // knows the upstream is fixed and wants
                    // Refresh All to pick the feed up on its
                    // next pass).
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skipped by Refresh All")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Failed \(failCount) times. Press Refresh to retry, or Reset to un-skip.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                        Button("Reset failure count") {
                            model.resetFailureCount(forFeed: feed.url)
                        }
                        .font(.caption2)
                    }
                } else if failCount > 0 {
                    // Soft hint: the feed has failed recently but
                    // hasn't crossed the back-off line yet.
                    Text("Failed \(failCount) time\(failCount == 1 ? "" : "s") in a row")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                // Rename affordance. Upstream NetNewsWire's
                // sidebar action "Rename Feed…" is the standard
                // place to override a publisher's generic title
                // ("News" → "Pat's News"). The model already had
                // renameFeed(_:to:) wired through subscribedFeeds
                // and subscriptionRoot — only the UI surface was
                // missing.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rename")
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        TextField(feed.title, text: Binding(
                            get: { renameFeedInput },
                            set: { renameFeedInput = $0 }
                        ))
                            .onSubmit {
                                let trimmed = renameFeedInput
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty, trimmed != feed.title else { return }
                                _ = model.renameFeed(feed.id, to: trimmed)
                                renameFeedInput = ""
                            }
                        Button("Save") {
                            let trimmed = renameFeedInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, trimmed != feed.title else { return }
                            _ = model.renameFeed(feed.id, to: trimmed)
                            renameFeedInput = ""
                        }
                        .disabled({
                            let trimmed = renameFeedInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            // No-op cases: empty, OR identical to
                            // the current title. Gate Save on both
                            // so the affordance reads honestly —
                            // before, clicking Save with the
                            // current title silently did nothing
                            // and the user wondered why.
                            return trimmed.isEmpty || trimmed == feed.title
                        }())
                    }
                }
                // Move feed up/down within its parent (folder or
                // root). Upstream NetNewsWire uses drag-and-drop;
                // SwiftOpenUI on Linux has no DnD plumbing, so
                // expose the same reorderFeed model API via
                // button pair. Stays inside the current parent;
                // crossing folders is the "Move to" block below.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reorder")
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        Button("↑ Move up") {
                            _ = model.reorderFeed(feed.id, by: -1)
                        }
                        .font(.caption2)
                        .disabled(!model.canReorderFeed(feed.id, by: -1))
                        Button("↓ Move down") {
                            _ = model.reorderFeed(feed.id, by: 1)
                        }
                        .font(.caption2)
                        .disabled(!model.canReorderFeed(feed.id, by: 1))
                    }
                }
                // Move to folder. Upstream NetNewsWire uses
                // drag-and-drop for this on macOS, which doesn't
                // translate cleanly to SwiftOpenUI on Linux.
                // Buttons-per-target instead: Root + every
                // current subfolder. The current home is
                // highlighted and disabled so it's obvious what
                // would change (and a click on it is a no-op).
                let currentParent = model.folderName(containing: feed.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Move to")
                        .font(.subheadline)
                    let rootIsCurrent = (currentParent == nil)
                    Button(rootIsCurrent ? "✓ Root (no folder)" : "Root (no folder)") {
                        _ = model.moveFeed(feed.id, toFolder: nil)
                    }
                    .font(.caption2)
                    .foregroundColor(rootIsCurrent ? .blue : .secondary)
                    .disabled(rootIsCurrent)
                    ForEach(model.allFolderTargets(), id: \.name) { target in
                        let isCurrent = (currentParent == target.name)
                        let indent = String(repeating: "  ", count: target.depth)
                        let label = isCurrent ? "✓ \(indent)\(target.name)" : "\(indent)\(target.name)"
                        Button(label) {
                            _ = model.moveFeed(feed.id, toFolder: target.name)
                        }
                        .font(.caption2)
                        .foregroundColor(isCurrent ? .blue : .secondary)
                        .disabled(isCurrent)
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
                    // when it's the selection). Disabled only when
                    // THIS feed's URL is in flight, not when ANY
                    // global fetch is loading (so the inspector
                    // stays usable during Refresh All on other
                    // feeds — matches #141's per-URL gate for
                    // refresh).
                    // Label mirrors the timeline footer's
                    // Refresh button (#149) so the in-flight
                    // signal is consistent everywhere.
                    Button(model.isLoading(forURL: feed.url) ? "Refreshing…" : "Refresh") {
                        Task { @MainActor in
                            await model.refreshFeed(urlString: feed.url)
                        }
                    }
                    .disabled(model.isLoading(forURL: feed.url))
                }
                Spacer()
                Button("Done") {
                    inspectedFeedID = nil
                    renameFeedInput = ""
                }
            }
        }
        .padding(24)
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
        // Same scroll-wrap as inspectorSheet: Settings has grown
        // a "Refresh back-off" section (iter #218) alongside the
        // existing refresh interval + stats blocks, and content
        // can grow further. ScrollView keeps the sheet's
        // compact footprint without losing access to anything.
        ScrollView {
            settingsBody.padding(.bottom, 8)
        }
        .frame(width: 380, height: 460)
    }

    private var settingsBody: some View {
        // 0 minutes = "Manual only" (refreshIntervalSeconds = nil).
        // Stepper's lower bound is 0 so the user can disable
        // background refresh from the UI — upstream NetNewsWire
        // has a "Refresh: Manually" preference; the only way to
        // get there before was to never set it (or load a manual
        // state from disk). Now the Settings sheet exposes it.
        let intervalMinutesBinding = Binding<Int>(
            get: {
                guard let s = model.refreshIntervalSeconds else { return 0 }
                return Int(s / 60)
            },
            set: { newValue in
                if newValue <= 0 {
                    model.refreshIntervalSeconds = nil
                } else {
                    model.refreshIntervalSeconds = TimeInterval(newValue * 60)
                }
            }
        )
        return VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2).bold()
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh interval")
                    .font(.subheadline)
                let summary: String = {
                    guard let s = model.refreshIntervalSeconds else {
                        return "Manual only (background refresh disabled)"
                    }
                    let minutes = Int(s / 60)
                    if minutes == 1 { return "Every minute" }
                    if minutes < 60 { return "Every \(minutes) minutes" }
                    let hours = minutes / 60
                    return "Every \(hours) hour\(hours == 1 ? "" : "s")"
                }()
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Stepper(
                    "Refresh interval (minutes; 0 = manual)",
                    value: intervalMinutesBinding,
                    in: 0...1440,
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
            // Reset back-off — surfaces a one-click affordance for
            // un-skipping every feed that crossed the failure
            // threshold. Without this, a user with a dozen
            // feeds-back-from-the-dead had to open each
            // inspector and hit Refresh individually. Disabled
            // when there's nothing to reset so it reads honestly.
            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh back-off")
                    .font(.subheadline)
                let skipped = model.feedFailureCount.filter {
                    $0.value >= RSSReaderModel.feedFailureSkipThreshold
                }.count
                let any = !model.feedFailureCount.isEmpty
                Text(skipped == 0
                    ? "No feeds are being skipped by Refresh All."
                    : "\(skipped) feed\(skipped == 1 ? "" : "s") skipped by Refresh All.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Reset all failure counts") {
                    _ = model.resetAllFailureCounts()
                }
                .font(.caption2)
                .disabled(!any)
            }
            Spacer()
            HStack {
                Spacer()
                Button("Done") { showingSettings = false }
            }
        }
        .padding(24)
    }

    private var keyboardShortcutSurface: some View {
        HStack(spacing: 0) {
            Button("next") { model.selectNextItem() }
                .keyboardShortcut("j", modifiers: [])
            Button("prev") { model.selectPreviousItem() }
                .keyboardShortcut("k", modifiers: [])
            // Arrow-key aliases for j/k. Upstream NetNewsWire
            // supports both — mouse-trained users reach for
            // arrows; vim-trained users reach for hjkl. Quill
            // had only the hjkl half, which was a needless
            // friction step for newcomers. The downArrow /
            // upArrow KeyEquivalents land on the same model
            // actions so behavior stays identical regardless of
            // which key the user reaches for.
            Button("next (arrow)") { model.selectNextItem() }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("prev (arrow)") { model.selectPreviousItem() }
                .keyboardShortcut(.upArrow, modifiers: [])
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
            // ⌘⌥K = Mark Older Articles as Read — upstream NNW's
            // canonical "I've triaged down to here, nuke the rest"
            // shortcut. Direction follows sortOrder so it stays
            // intuitive regardless of newest/oldest-first view.
            Button("mark older read") {
                model.markOlderThanSelectionAsRead()
            }
            .keyboardShortcut("k", modifiers: [.command, .option])
            Button("refresh all") {
                Task { @MainActor in await model.refreshAllFeeds() }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            Button("next unread") {
                Task { @MainActor in
                    await model.selectNextUnreadAcrossFeeds()
                }
            }
            .keyboardShortcut("n", modifiers: [])
            Button("mark unread") {
                model.markUnreadOnSelection()
            }
            .keyboardShortcut("u", modifiers: [])
            Button("previous unread") {
                Task { @MainActor in
                    await model.selectPreviousUnreadAcrossFeeds()
                }
            }
            .keyboardShortcut("p", modifiers: [])
            // Cmd+Shift+U toggles "Hide Read Articles" — same
            // shortcut as upstream NetNewsWire.
            Button("toggle hide read") {
                model.hideReadArticles.toggle()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            // Cmd+1 / Cmd+2 / Cmd+3 jump to the three smart
            // feeds. Matches upstream NetNewsWire's File menu
            // shortcuts (View > Today / All Unread / Starred).
            // Useful for keyboard-only triage flows that don't
            // touch the sidebar.
            Button("today") { model.selectSmartFeed(.today) }
                .keyboardShortcut("1", modifiers: .command)
            Button("all unread") { model.selectSmartFeed(.allUnread) }
                .keyboardShortcut("2", modifiers: .command)
            Button("starred") { model.selectSmartFeed(.starred) }
                .keyboardShortcut("3", modifiers: .command)
            // Cmd+0 clears any active smart feed OR folder view
            // and returns the timeline to the active subscribed-
            // feed view. Previously only handled smart feeds, so
            // a user in a folder view had no keyboard escape
            // back to the per-feed timeline.
            Button("clear smart feed / folder") {
                model.selectSmartFeed(nil)
                model.selectFolder(nil)
            }
            .keyboardShortcut("0", modifiers: .command)
            // Cmd+, opens the Settings sheet — the canonical Mac
            // "Preferences" shortcut. Matches upstream
            // NetNewsWire's File menu binding.
            Button("settings") { showingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
            // `b` opens the currently selected article in the
            // default browser. Single most-used keystroke in
            // upstream NetNewsWire's reader after j/k. The model
            // owns URL lookup; this button just hands it off to
            // the environment's openURL action.
            Button("open in browser") {
                if let url = model.selectedItemBrowserURL() {
                    openURL(url)
                }
            }
            .keyboardShortcut("b", modifiers: [])
            // ⌘⇧C = Copy Article URL — upstream NetNewsWire's
            // canonical "I want to share this" shortcut. Avoids
            // having to right-click the inline link in the
            // detail pane. Linux: shells out to wl-copy / xclip;
            // macOS: pbcopy.
            Button("copy url") {
                _ = model.copySelectedItemURLToClipboard()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            // ⌘F focuses the timeline search field. Standard
            // upstream NetNewsWire shortcut for jumping into
            // search without a mouse trip. Sets the @FocusState
            // bound to the search TextField via .focused(),
            // which the platform brings to the foreground.
            Button("focus search") {
                searchFieldFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            // ⌥⌘↓ / ⌥⌘↑ = Go to Next / Previous Feed. Matches
            // upstream NetNewsWire's sidebar nav shortcuts. j/k
            // walks within the active feed's timeline; these
            // walk across feeds.
            Button("next feed") {
                Task { @MainActor in await model.selectNextFeed() }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Button("prev feed") {
                Task { @MainActor in await model.selectPreviousFeed() }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
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
                if model.subscribedFeeds.isEmpty {
                    // First-launch empty state — points users at
                    // the Add Feed input below + the OPML import
                    // affordance. Without this hint, the sidebar
                    // just looks broken until the user notices
                    // the Add Feed field at the bottom.
                    VStack(spacing: 8) {
                        Text("No subscriptions yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Add a feed URL below or import an OPML file.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                } else {
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
                        .onSubmit {
                            // Enter in the field fires Add too —
                            // typing a URL and hitting Return is
                            // the natural flow (matches upstream
                            // NetNewsWire's add-feed dialog and
                            // browser-style URL bars). Without
                            // this, the user had to mouse over to
                            // the Add button after typing.
                            let trimmed = addSubscriptionInput.trimmingWhitespace
                            guard !trimmed.isEmpty, !model.isLoading else { return }
                            let input = addSubscriptionInput
                            addSubscriptionInput = ""
                            Task { @MainActor in
                                await model.addSubscription(urlString: input)
                            }
                        }
                    Button(model.isLoading ? "Adding…" : "Add") {
                        let input = addSubscriptionInput
                        addSubscriptionInput = ""
                        Task { @MainActor in
                            await model.addSubscription(urlString: input)
                        }
                    }
                    .font(.caption2)
                    // Disable while any fetch is in flight — Feed
                    // Finder + selectFeed-fetch chain on a click
                    // shouldn't be re-entered until the prior
                    // chain resolves. Also block on empty input.
                    .disabled(addSubscriptionInput.trimmingWhitespace.isEmpty || model.isLoading)
                }
                HStack(spacing: 6) {
                    TextField("OPML URL", text: Binding(
                        get: { opmlImportURLInput },
                        set: { opmlImportURLInput = $0 }
                    ))
                        .font(.caption2)
                        .onSubmit {
                            // Same onSubmit pattern as Add Feed
                            // — Enter fires Import.
                            let trimmed = opmlImportURLInput.trimmingWhitespace
                            guard !trimmed.isEmpty, !model.isLoading else { return }
                            let input = opmlImportURLInput
                            opmlImportURLInput = ""
                            Task { @MainActor in
                                await model.importOPMLFromURL(input)
                            }
                        }
                    Button(model.isLoading ? "Importing…" : "Import") {
                        let input = opmlImportURLInput
                        opmlImportURLInput = ""
                        Task { @MainActor in
                            await model.importOPMLFromURL(input)
                        }
                    }
                    .font(.caption2)
                    .disabled(opmlImportURLInput.trimmingWhitespace.isEmpty || model.isLoading)
                }
                // Add Folder — top-level only by design (mirrors
                // upstream NetNewsWire's New Folder command).
                // Surfaces the existing addFolder(named:) model
                // API; trim + non-empty + sibling-uniqueness
                // guards live in the model.
                HStack(spacing: 6) {
                    TextField("New folder name", text: Binding(
                        get: { addFolderInput },
                        set: { addFolderInput = $0 }
                    ))
                        .font(.caption2)
                        .onSubmit {
                            // Same Enter-submits-form pattern as
                            // Add Feed / Import (iter #234).
                            let trimmed = addFolderInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let ok = model.addFolder(named: trimmed)
                            if ok {
                                addFolderInput = ""
                            } else {
                                model.lastSubscribeMessage = "A folder named \u{201C}\(trimmed)\u{201D} already exists."
                            }
                        }
                    Button("New Folder") {
                        let trimmed = addFolderInput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let ok = model.addFolder(named: trimmed)
                        if ok {
                            addFolderInput = ""
                        } else {
                            // Duplicate at root (the only place
                            // addFolder creates folders). Surface
                            // a toast so the user knows why the
                            // input didn't clear / a folder
                            // didn't appear. Keep the input so
                            // they can edit + retry.
                            model.lastSubscribeMessage = "A folder named \u{201C}\(trimmed)\u{201D} already exists."
                        }
                    }
                    .font(.caption2)
                    .disabled(
                        addFolderInput
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }
                HStack(spacing: 6) {
                    Button(model.isLoading ? "Refreshing All…" : "Refresh All") {
                        Task { @MainActor in await model.refreshAllFeeds() }
                    }
                    .font(.caption2)
                    .disabled(model.isLoading || model.subscribedFeeds.isEmpty)
                    Button("Sort A-Z") {
                        model.sortFeedsAlphabetically()
                    }
                    .font(.caption2)
                    .disabled(model.subscribedFeeds.count <= 1)
                    Button("Export OPML") {
                        model.saveOPMLExportToDisk()
                    }
                    .font(.caption2)
                    // No subscriptions → nothing to export. Empty
                    // OPML on disk is misleading (looks like a
                    // failed save). Disable so the affordance
                    // reads honestly.
                    .disabled(model.subscribedFeeds.isEmpty)
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
                // Subscribe / import confirmation toast — fades
                // on next selectFeed. Without this the Add /
                // Import buttons gave zero visible feedback on
                // success or "already subscribed".
                if let msg = model.lastSubscribeMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                // Aggregate health summary so users with 50+ feeds
                // can tell at a glance how many are unhappy without
                // opening every inspector.
                let summary = model.feedHealthSummary()
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
        // 📁 prefix so folders stand out from feed rows in a
        // long sidebar — matches the visual weight of smart-
        // feed symbol prefixes (☀/●/★). Unread count appears
        // after the title to mirror feed-row badge ordering.
        let displayTitle = unread > 0 ? "📁 \(title) (\(unread))" : "📁 \(title)"
        let inner = DisclosureGroup(displayTitle) {
            VStack(alignment: .leading, spacing: 2) {
                // 'Show all' selects the folder as a smart-feed-
                // style view (filteredItems unions every feed in
                // the folder). Can't put the action on the
                // disclosure header itself — that gesture is
                // owned by expand/collapse — so it lives at the
                // top of the disclosure body.
                Button(model.selectedFolderName == folder.name
                       ? "✓ Showing all in folder"
                       : "Show all in folder") {
                    model.selectFolder(
                        model.selectedFolderName == folder.name ? nil : folder.name
                    )
                }
                .font(.caption2)
                .foregroundColor(model.selectedFolderName == folder.name ? .blue : .secondary)
                .padding(.leading, 8)
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
                // Reorder folder within its parent. reorderFolder
                // walks the tree by name and shifts within its
                // sibling list. addFolder is root-only so most
                // user-visible folders live at root, but the
                // model handles nested-folder reorder too.
                HStack(spacing: 6) {
                    Button("↑") {
                        _ = model.reorderFolder(named: folder.name, by: -1)
                    }
                    .font(.caption2)
                    .disabled(!model.canReorderFolder(named: folder.name, by: -1))
                    Button("↓") {
                        _ = model.reorderFolder(named: folder.name, by: 1)
                    }
                    .font(.caption2)
                    .disabled(!model.canReorderFolder(named: folder.name, by: 1))
                }
                .padding(.leading, 8)
                // Folder rename — two-step toggle so the
                // TextField only takes up sidebar space when the
                // user explicitly wants to rename. Mirrors the
                // feed-rename surface in the inspector but stays
                // inline since folders don't have a dedicated
                // inspector. Upstream NetNewsWire's sidebar
                // "Rename Folder…" surfaces the same affordance.
                let isRenaming = renameFolderName == folder.name
                if isRenaming {
                    HStack(spacing: 6) {
                        TextField(folder.name, text: Binding(
                            get: { renameFolderInput },
                            set: { renameFolderInput = $0 }
                        ))
                            .onSubmit {
                                let trimmed = renameFolderInput
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty, trimmed != folder.name else { return }
                                let ok = model.renameFolder(from: folder.name, to: trimmed)
                                if ok {
                                    renameFolderName = nil
                                    renameFolderInput = ""
                                } else {
                                    model.lastSubscribeMessage = "A folder named \u{201C}\(trimmed)\u{201D} already exists here."
                                }
                            }
                        Button("Save") {
                            let trimmed = renameFolderInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, trimmed != folder.name else { return }
                            let ok = model.renameFolder(from: folder.name, to: trimmed)
                            if ok {
                                renameFolderName = nil
                                renameFolderInput = ""
                            } else {
                                // Sibling-name collision (or
                                // unfindable folder). Surface a
                                // toast so the user knows why
                                // the Save did nothing. Stay in
                                // rename mode so they can edit
                                // the input without losing it.
                                model.lastSubscribeMessage = "A folder named \u{201C}\(trimmed)\u{201D} already exists here."
                            }
                        }
                        .disabled({
                            let trimmed = renameFolderInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            // Same no-op-gate as feed rename:
                            // disable when empty OR identical to
                            // the current name.
                            return trimmed.isEmpty || trimmed == folder.name
                        }())
                        Button("Cancel") {
                            renameFolderName = nil
                            renameFolderInput = ""
                        }
                    }
                    .font(.caption2)
                    .padding(.leading, 8)
                } else {
                    Button("Rename folder") {
                        renameFolderName = folder.name
                        renameFolderInput = folder.name
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                }
                // 'Delete folder' — same two-tap confirm pattern
                // as feed delete. removeFolder unwraps the
                // folder's feeds back into the root flat list, so
                // the feeds themselves stay subscribed — the
                // confirm is mostly belt-and-suspenders against
                // an accidental click destroying a useful
                // grouping the user spent time setting up.
                let isArmed = pendingDeleteFolderName == folder.name
                Button(isArmed ? "Delete folder?" : "Delete folder") {
                    if isArmed {
                        _ = model.removeFolder(named: folder.name)
                        pendingDeleteFolderName = nil
                    } else {
                        pendingDeleteFolderName = folder.name
                    }
                }
                .font(.caption2)
                .foregroundColor(isArmed ? .red : .secondary)
                .padding(.leading, 8)
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
        let isSkipped = (model.feedFailureCount[feed.id] ?? 0)
            >= RSSReaderModel.feedFailureSkipThreshold
        return HStack(spacing: 6) {
            if isSkipped {
                // Distinct glyph for "feed has been backed off and
                // is being skipped by Refresh All" — different
                // from the per-fetch warning so the user can tell
                // at a glance whether one bad refresh happened
                // vs. the feed is now being ignored.
                Text("⊘")
                    .font(.caption2)
                    .foregroundColor(.red)
            } else if hasError {
                // Compact stale-feed warning. Mirrors NetNewsWire's
                // sidebar amber-warning glyph next to feeds whose
                // most recent fetch failed (HTTP 4xx/5xx, parse
                // failure, network timeout). Cleared automatically
                // on the next successful fetch.
                Text("⚠")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            // Title fallback chain: explicit title → URL string
            // → "Untitled". Without this, a feed that ended up
            // with an empty title (corrupted OPML, parse edge
            // case) would render a blank row.
            Text(feed.title.isEmpty ? (feed.url.isEmpty ? "Untitled" : feed.url) : feed.title)
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
                // Two-tap delete: first tap arms (button flips
                // to "Delete?" in red), second tap on the same
                // row confirms. Mirrors upstream NetNewsWire's
                // "Are you sure?" dialog without spinning up an
                // alert sheet — instant on Linux + SwiftOpenUI
                // and reversible (tap any other row's ✕ or
                // select a different feed to disarm). Without
                // this, a single accidental tap on a populous
                // sidebar nuked a subscription with no recovery.
                let isArmed = pendingDeleteFeedID == feed.id
                Button(isArmed ? "Delete?" : "✕") {
                    if isArmed {
                        model.removeSubscription(id: feed.id)
                        pendingDeleteFeedID = nil
                    } else {
                        pendingDeleteFeedID = feed.id
                    }
                }
                .font(.caption2)
                .foregroundColor(isArmed ? .red : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    /// Subtitle for the timeline pane header — reflects the
    /// active view: smart-feed name > active feed's title >
    /// "Loading…" fallback. Composed so the header always
    /// matches what the timeline actually shows.
    private var timelineHeaderSubtitle: String {
        if let smart = model.selectedSmartFeed {
            return smart.displayName
        }
        if let folder = model.selectedFolderName {
            return "Folder: \(folder)"
        }
        return model.feedTitle ?? "Loading…"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quill NetNewsWire").font(.title2).bold()
                // Reflect the actual current view: smart-feed
                // name takes priority over the stale feedTitle
                // from the last per-feed fetch. Without this,
                // selecting "All Unread" left "Daring Fireball"
                // showing in the header — misleading.
                Text(timelineHeaderSubtitle)
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
                    .focused($searchFieldFocused)
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

            // ScrollViewReader so j/k navigation keeps the
            // selected row in view. Without this, hitting j
            // repeatedly drops the cursor off the bottom edge
            // and the user has no idea where the highlight went
            // until they manually scroll. Mirrors upstream
            // NetNewsWire's timeline auto-scroll behavior.
            ScrollViewReader { proxy in
                ScrollView {
                    if model.filteredRows.isEmpty {
                        timelineEmptyState
                            .padding(.horizontal, 12)
                            .padding(.top, 32)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.filteredRows) { item in
                                articleRow(item)
                                    .id(item.id)
                                    .onTapGesture {
                                        model.selectItem(id: item.id)
                                    }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 18)
                    }
                }
                .onChange(of: model.selectedID) { newID in
                    guard let newID else { return }
                    // anchor: .center so the row lands in the
                    // middle of the visible area rather than
                    // hugging the bottom edge — gives the user
                    // a couple of rows of context above and
                    // below the current selection.
                    withAnimation { proxy.scrollTo(newID, anchor: .center) }
                }
                .onChange(of: model.searchQuery) { query in
                    // Reset scroll to the top of the (filtered)
                    // timeline when the search changes — otherwise
                    // typing a query left the user stuck mid-scroll
                    // and matching results were likely off-screen
                    // above. NNW behavior. Use the first matching
                    // row's id as the scroll target with anchor:
                    // .top so the user sees the freshest matches.
                    // No-op when search is empty (skipping the
                    // jump avoids snapping the user back to the
                    // top whenever they clear the field).
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          let firstID = model.filteredRows.first?.id
                    else { return }
                    withAnimation { proxy.scrollTo(firstID, anchor: .top) }
                }
                .onChange(of: model.hideReadArticles) { _ in
                    // Toggling Hide Read reshapes filteredItems
                    // (read rows vanish or reappear). selectedID
                    // didn't change, so the existing scrollTo
                    // hop doesn't fire — without this, the
                    // viewport stayed where it was even though
                    // the row layout shifted, often hiding the
                    // selected row. Re-scroll to the selection
                    // so the row stays visible across the
                    // toggle.
                    guard let id = model.selectedID else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: model.sortOrder) { _ in
                    // Flipping sortOrder reverses filteredItems.
                    // The selected row jumps from near-top to
                    // near-bottom (or vice versa) — without a
                    // re-scroll, the viewport stays put and the
                    // selection is suddenly far off-screen.
                    // Same fix shape as the hide-read handler.
                    guard let id = model.selectedID else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
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
            // disabled gate uses filteredUnreadCount so smart-
            // feed / folder views with unread items in the pool
            // can still mark them — the active feed (which
            // unreadCount tracks) might be all-read even when
            // the cross-feed pool isn't.
            .disabled(model.filteredUnreadCount == 0)
            // In folder view, Refresh refreshes every feed in
            // the folder via refreshFolder (#162). In default
            // active-feed view, refresh the active feed only.
            // Per-URL gate for the active-feed branch matches
            // the inspector Refresh button (#148).
            if let folder = model.selectedFolderName {
                Button(model.isLoading ? "Refreshing All…" : "Refresh Folder") {
                    Task { @MainActor in await model.refreshFolder(folder) }
                }
                .font(.caption2)
                .disabled(model.isLoading)
            } else {
                Button(model.isLoading(forURL: activeFeedURL) ? "Refreshing…" : "Refresh") {
                    Task { @MainActor in await model.refresh(urlString: activeFeedURL) }
                }
                .font(.caption2)
                .disabled(model.isLoading(forURL: activeFeedURL))
            }
        }
        .padding(10)
    }

    private var detail: some View {
        Group {
            if let item = model.selectedDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            // Prev/next nav arrows. Disabled when
                            // at the boundary so the affordance
                            // reads honestly. Same code path as
                            // the j/k keyboard shortcuts.
                            Button("◀") { model.selectPreviousItem() }
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .disabled(!model.canSelectPrevious)
                            Button("▶") { model.selectNextItem() }
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .disabled(!model.canSelectNext)
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
                        // In cross-feed contexts (smart feed /
                        // search / folder view) surface the
                        // source feed name under the title —
                        // matches upstream NetNewsWire's detail-
                        // pane breadcrumb so users know which
                        // feed they're reading without flipping
                        // back to the timeline.
                        if (model.selectedSmartFeed != nil ||
                            model.selectedFolderName != nil ||
                            !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                            let sourceFeed = model.feedTitle(forItemID: item.id) {
                            Text(sourceFeed)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
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
                    // Reset scroll position when the selection
                    // changes. Without an .id tied to item.id,
                    // ScrollView keeps the old vertical offset on
                    // selection change — so jumping from a long
                    // article to a short one (or just advancing
                    // via j/k) drops the reader mid-body of the
                    // new article instead of starting at the
                    // title. SwiftUI rebuilds the subtree when
                    // the id changes, which resets the
                    // ScrollView's contentOffset to (0, 0).
                    // Matches upstream NetNewsWire's detail-pane
                    // behavior of always starting at the top of
                    // the just-selected article.
                    .id(item.id)
                }
                .background(QuillDesktopChromeStyle.detailBackground)
            } else {
                let (headline, detail) = detailEmptyState()
                VStack(spacing: 12) {
                    Text(headline)
                        .font(.title2)
                        .foregroundColor(.secondary)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(QuillDesktopChromeStyle.detailBackground)
            }
        }
    }

    /// State-aware empty copy for the detail pane. Matches the
    /// situations the timeline empty state already covers but
    /// scoped to the detail's "nothing selected" context.
    private func detailEmptyState() -> (headline: String, detail: String) {
        if model.isLoading {
            return ("Loading…", "Fetching articles.")
        }
        if model.subscribedFeeds.isEmpty {
            return (
                "No subscriptions yet",
                "Add a feed in the sidebar to start reading."
            )
        }
        if model.filteredRows.isEmpty {
            // Timeline is empty too — let it speak for itself.
            return ("No article selected", "")
        }
        // Tailor the hint: "press n for next unread" is dead
        // advice when no unread items are in view (post-read-all
        // state). Differentiate so the affordance points at a
        // path that actually works.
        if model.filteredUnreadCount > 0 {
            return (
                "Select an article",
                "Use the timeline to pick one, or press n for the next unread."
            )
        }
        return (
            "Select an article",
            "Use the timeline to pick one — every article in this view is already read."
        )
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
        // Pass linkURL as the base for relative-URL resolution
        // so href="/article/123" / img src="/photo.jpg" become
        // fully-qualified URLs the user can actually open. Real
        // RSS feeds (especially WordPress-generated) routinely
        // ship body HTML with site-relative paths; without
        // resolution the detail-pane Links / Images footer
        // showed clickable rows that opened to nothing.
        self.plainTextBody = (descriptionHTML ?? "").stripBasicHTML()
        self.bodyParagraphs = (descriptionHTML ?? "").htmlParagraphs()
        self.inlineLinks = (descriptionHTML ?? "").htmlInlineLinks(baseURL: linkURL)
        self.inlineImages = (descriptionHTML ?? "").htmlInlineImages(baseURL: linkURL)
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

    /// Convenience init that prefers a model-derived friendly
    /// date ("3h ago", "Jun 1") over the raw RSS pubDate string.
    /// Falls back to publishedSummary when friendly is empty
    /// (e.g. the parallel article record didn't have a parsed
    /// Date). Matches upstream NetNewsWire's timeline rows,
    /// which show compact friendly dates instead of the verbose
    /// "Sun, 01 Jun 2026 14:30:00 +0000" form from the feed.
    public init(
        item: RSSItem,
        feedTitle: String? = nil,
        authorLine: String? = nil,
        friendlyDate: String
    ) {
        let displayDate = friendlyDate.isEmpty ? item.publishedSummary : friendlyDate
        self.init(
            id: item.id,
            title: item.title,
            publishedSummary: displayDate,
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
            persistReadArticleIDsIfReady()
        }
    }

    private func persistReadArticleIDsIfReady() {
        guard persistenceReady else { return }
        persistence.saveReadArticleIDs(readArticleIDs)
    }

    /// Set of starred article IDs. Same flat-set shape as
    /// readArticleIDs; persisted alongside it. Upstream
    /// NetNewsWire surfaces starred articles via the Starred
    /// smart feed and a per-article star toggle in the detail
    /// header.
    @Published private(set) var starredArticleIDs: Set<String> = [] {
        didSet { persistStarredArticleIDsIfReady() }
    }

    private func persistStarredArticleIDsIfReady() {
        guard persistenceReady else { return }
        persistence.saveStarredArticleIDs(starredArticleIDs)
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

    /// Folder-as-smart-feed selection. When non-nil, the
    /// timeline shows the union of articles across every feed
    /// inside that folder (matches upstream NetNewsWire's
    /// folder-click behavior). Mutually exclusive with
    /// selectedSmartFeed AND the default active-feed view; the
    /// select* methods enforce the invariant.
    @Published var selectedFolderName: String? {
        didSet {
            updateStatusText()
            persistSelectionIfReady()
        }
    }

    /// Auto-refresh cadence in seconds for the active feed.
    /// Matches upstream NetNewsWire's default 30-minute refresh
    /// interval. Setting to nil disables background polling.
    /// Persisted via PersistenceStore.ViewOptions so user changes
    /// to the cadence survive relaunch.
    @Published var refreshIntervalSeconds: TimeInterval? = 30 * 60 {
        didSet {
            persistViewOptionsIfReady()
            // Rearm the background refresh Task so the new
            // cadence takes effect immediately. Without this,
            // changing 30m → 5m would still wait up to 30
            // minutes for the next tick (the existing Task
            // was sleeping on the old interval). Skipped
            // during init-time load (background task hasn't
            // started yet) via the persistenceReady gate
            // pattern.
            guard persistenceReady else { return }
            if refreshIntervalSeconds != nil {
                startBackgroundRefresh()
            } else {
                stopBackgroundRefresh()
            }
        }
    }

    /// Per-feed consecutive-failure counter. Incremented on every
    /// fetch error / HTTP 4xx-5xx / empty response, reset to 0
    /// on every successful parse. refreshAllFeeds skips feeds
    /// whose count has crossed `feedFailureSkipThreshold` so
    /// the background refresh batch doesn't keep hammering
    /// permanently-bad feeds. Explicit per-feed refresh
    /// (refreshFeed / refresh) does NOT honor the skip — that's
    /// how the user clears the skipped state after fixing the
    /// underlying feed URL. Persisted via PersistenceStore so
    /// back-off survives relaunch (otherwise the user would pay
    /// 5 retry hits per dead feed per launch).
    @Published var feedFailureCount: [Feed.ID: Int] = [:] {
        didSet { persistFeedFailureCountIfReady() }
    }

    /// Per-feed HTTP conditional-GET cache. Last-Modified +
    /// ETag harvested from the previous successful response,
    /// sent on the next fetch as If-Modified-Since / If-None-
    /// Match. 304 Not Modified means "your cache is current"
    /// → skip the parse, keep the existing items. Most active
    /// feeds publish a few times/day; conditional GET drops
    /// 99% of background refresh bandwidth.
    @Published var conditionalGetInfo: [Feed.ID: [String: String]] = [:] {
        didSet { persistConditionalGetInfoIfReady() }
    }

    private func persistConditionalGetInfoIfReady() {
        guard persistenceReady else { return }
        persistence.saveConditionalGetInfo(conditionalGetInfo)
    }

    /// Per-feed timestamp of the most recent error. Set by
    /// incrementFailureCount; surfaces in the inspector
    /// "Failed N ago" line so users can tell stale-but-failing
    /// from broken-just-now. Persisted as Unix seconds for
    /// JSON cleanliness.
    @Published var feedLastErrorAt: [Feed.ID: Date] = [:] {
        didSet { persistFeedLastErrorAtIfReady() }
    }

    private func persistFeedLastErrorAtIfReady() {
        guard persistenceReady else { return }
        let asDoubles = feedLastErrorAt.mapValues(\.timeIntervalSince1970)
        persistence.saveFeedLastErrorAt(asDoubles)
    }

    /// Consecutive-failure count at which refreshAllFeeds skips
    /// a feed. 5 chosen to give a feed plenty of chances to come
    /// back online during transient outages (~2.5 hours at the
    /// 30-minute default cadence) while still backing off
    /// before a definitively-dead feed wastes another day of
    /// background bandwidth.
    static let feedFailureSkipThreshold = 5

    /// Max items kept per feed (active items + cached articles).
    /// 100 matches what upstream NetNewsWire's Account models
    /// typically keep around — enough scrollback for an active
    /// feed's last week or two of posts without growing the
    /// SQLite store unbounded. Both fetch() and fetchIntoCache()
    /// trim to this; in-memory render cost stays O(N) per feed.
    static let articlesPerFeedLimit = 100

    /// Per-feed SQLite retention. After every fetch upsert, the
    /// feed's SQLite rows get pruned to the N newest. Larger
    /// than articlesPerFeedLimit (which caps the in-memory
    /// fetch batch) so SQLite preserves history beyond the
    /// per-batch slice — Starred / All Unread smart feeds rely
    /// on this for the full-history span (#113/#114).
    static let articleHistoryLimit = 500

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
        didSet {
            syncSubscriptionRootIfFlat()
            persistSubscriptionsIfReady()
        }
    }

    /// Hierarchical mirror of `subscribedFeeds`. When the user
    /// imports an OPML file with nested folders, the structure
    /// gets preserved here (the flat list keeps every feed for
    /// callers that don't care about folders). Defaults to a
    /// single root folder holding all seeded feeds.
    @Published var subscriptionRoot: OPMLImporter.Folder {
        didSet { persistSubscriptionsIfReady() }
    }
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
        let persistedOptions = persistence.loadViewOptionsIfPersisted()
        let storedOptions = persistedOptions ?? PersistenceStore.ViewOptions()
        self.hideReadArticles = storedOptions.hideReadArticles
        self.sortOrder = storedOptions.sortOrder
            .flatMap { SortOrder(rawValue: $0) } ?? .newestFirst
        // Restore persisted refresh cadence honoring an
        // explicitly-persisted nil ("Manual only"). Fresh
        // install (no viewOptions.json yet) keeps the 30-min
        // default; once the user has saved view-options at
        // least once, a nil interval is treated as their
        // explicit choice. Without this distinction, choosing
        // "Manual only" in Settings re-armed the 30-min
        // default on every relaunch.
        if persistedOptions != nil {
            self.refreshIntervalSeconds = storedOptions.refreshIntervalSeconds
        }
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
        let resolvedRoot: OPMLImporter.Folder
        if let data = persistence.loadOPMLExport() {
            let parsed = OPMLImporter.parseTree(data: data)
            let leaves = parsed.root.allFeeds
            if leaves.isEmpty {
                resolvedFeeds = subscribedFeeds
                resolvedRoot = OPMLImporter.Folder(
                    name: "",
                    feeds: subscribedFeeds,
                    subfolders: []
                )
            } else {
                resolvedFeeds = leaves
                // Restore the persisted folder hierarchy too —
                // tree-aware exportTree round-trips through parse
                // Tree so subfolder structure (and any future
                // rename / reorder) survives relaunch instead of
                // collapsing back to flat on every restart.
                resolvedRoot = parsed.root
            }
        } else {
            resolvedFeeds = subscribedFeeds
            resolvedRoot = OPMLImporter.Folder(
                name: "",
                feeds: subscribedFeeds,
                subfolders: []
            )
        }
        self.subscribedFeeds = resolvedFeeds
        self.selectedFeedID = resolvedFeeds.first?.id
        self.subscriptionRoot = resolvedRoot
        // Restore mark-as-read + starred history. Failed reads
        // (first launch, missing file) yield empty sets so the
        // model just starts fresh.
        self.readArticleIDs = persistence.loadReadArticleIDs()
        self.starredArticleIDs = persistence.loadStarredArticleIDs()
        self.feedIconURLs = persistence.loadFeedIconURLs()
        self.feedErrors = persistence.loadFeedErrors()
        self.feedFailureCount = persistence.loadFeedFailureCount()
        self.conditionalGetInfo = persistence.loadConditionalGetInfo()
        self.feedLastErrorAt = persistence.loadFeedLastErrorAt().mapValues {
            Date(timeIntervalSince1970: $0)
        }
        // Hydrate feedCaches from any persisted articles so the
        // timeline shows yesterday's items before today's fetch
        // even fires. Bucket by feedID, build the (items,
        // articles, lastFetchAt) triple per group. Errors swallow
        // — the in-memory empty caches keep the reader running.
        hydrateFeedCachesFromStoreIfReady()
        // Reconcile the in-memory JSON-persisted sets against
        // SQLite. If SQLite has isStarred=true rows whose unique
        // IDs are missing from starredArticleIDs (e.g. JSON file
        // corruption or pre-iteration-113 data), merge them in
        // so toggleStarred behaves correctly the first click.
        // Same for isRead. Direction: SQLite → JSON union; never
        // unstar / unread anything in the JSON set (that would
        // override the user's explicit JSON-persisted state).
        reconcileReadStarredFromStore()
        // Restore sidebar selection from disk so the reader
        // resumes where the user left off. A persisted feed that
        // no longer exists (unsubscribed across launches) falls
        // through to the default first-feed selection set above.
        // Smart feed wins over feed when both are set (the
        // serializer never writes both, but be defensive).
        if let saved = persistence.loadSelection() {
            if let smart = saved.smartFeed, let kind = SmartFeed(rawValue: smart) {
                self.selectedSmartFeed = kind
            } else if let folder = saved.folderName,
                      Self.findFolder(named: folder, in: resolvedRoot) != nil {
                // Restore folder view only when the folder
                // still exists in the tree — a folder that was
                // removed across launches falls through to the
                // default first-feed selection (already set
                // above).
                self.selectedFolderName = folder
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
    /// All starred articles ever persisted, regardless of
    /// whether they're still in the in-memory cache. Reads from
    /// articleStore so the Starred smart feed reflects the
    /// user's full star history rather than just the
    /// articlesPerFeedLimit-bounded recent slice. Returns RSS
    /// Items reconstituted from PersistentArticle rows in the
    /// same shape the live-fetch path produces.
    ///
    /// Empty when there's no articleStore (no-persistence test
    /// path) or no starred rows. Failures swallow → empty so
    /// the smart feed degrades gracefully.
    func storedStarredItems() -> [RSSItem] {
        guard let store = articleStore else { return [] }
        guard let rows = try? store.fetchStarred() else { return [] }
        // Same subscribed-feeds filter as hydrateFeedCachesFromStore
        // (iter #236): orphan SQLite rows from unsubscribed feeds
        // shouldn't leak into smart-feed surfaces. Otherwise a
        // starred-but-since-unsubscribed article would keep
        // appearing in the Starred view forever.
        let subscribedIDs = Set(subscribedFeeds.map(\.id))
        return rows
            .lazy
            .filter { subscribedIDs.contains($0.feedID) }
            .prefix(Self.smartFeedStoredLimit)
            .map(Self.rssItem(from:))
    }

    /// Symmetric to storedStarredItems for All Unread.
    /// SQLite-resident unread rows that may have aged out of
    /// the per-feed cache. Same degradation semantics.
    /// Honors the in-memory readArticleIDs set as the source
    /// of truth — a row whose SQLite isRead=false but is in the
    /// in-memory set was just marked-read this session; treat
    /// it as read so the user doesn't see it reappear in the
    /// All Unread list before the next fetch syncs the bits.
    func storedUnreadItems() -> [RSSItem] {
        guard let store = articleStore else { return [] }
        guard let rows = try? store.fetchUnread() else { return [] }
        let subscribedIDs = Set(subscribedFeeds.map(\.id))
        return rows
            .lazy
            .filter { subscribedIDs.contains($0.feedID) }
            .filter { !self.readArticleIDs.contains($0.uniqueID) }
            .prefix(Self.smartFeedStoredLimit)
            .map(Self.rssItem(from:))
    }

    /// Soft cap on rows surfaced by storedStarredItems /
    /// storedUnreadItems. Smart-feed pools are recomputed on
    /// every render (status text, filteredItems, ForEach), so
    /// an unbounded pull hurts heavy-history users — 5000
    /// unread × every render × multiple computes per render
    /// = noticeable lag. 500 covers virtually every active
    /// scrollback need (rows are newest-first, so the cap
    /// trims the OLDEST tail first) while keeping render
    /// cost bounded. Tail-cap matches upstream NetNewsWire's
    /// Account-level fetch-limit pattern.
    static let smartFeedStoredLimit = 500

    /// Shared row → RSSItem reconstitution used by every
    /// stored-* helper. Same field fallback chain as the live
    /// fetch path so SQLite-only items render identically to
    /// just-fetched ones. Title decoded through HTMLEntities so
    /// rows persisted before the per-parse decoding landed
    /// (#121) still render naturally — adaptParsedItem decoded
    /// at parse time for in-memory items, but toArticles
    /// upserted raw to SQLite. Both paths now decode on the
    /// read side too.
    private static func rssItem(from row: PersistentArticle) -> RSSItem {
        // Same external→url preference as adaptParsedItem
        // (#147) so SQLite-only stored items also open at the
        // linkblog target, not the linkblog post.
        let link = (row.externalURL?.isEmpty == false) ? row.externalURL : row.url
        return RSSItem(
            id: row.uniqueID,
            title: HTMLEntities.decode(row.title ?? "Untitled"),
            link: link,
            pubDate: row.datePublished?.description,
            descriptionHTML: row.contentHTML ?? row.contentText ?? row.summary
        )
    }

    /// One-shot union: merge SQLite isStarred=true / isRead=true
    /// uniqueIDs into the JSON-persisted starredArticleIDs /
    /// readArticleIDs sets. Direction is intentionally one-way
    /// (SQLite → JSON) so a stale SQLite row never silently
    /// re-marks an article the user explicitly unstarred /
    /// unread in the JSON set; the merge only ADDS missing
    /// entries.
    ///
    /// Without this, storedStarredItems / storedUnreadItems
    /// could show SQLite-only rows that aren't in the in-memory
    /// set — toggleStarred / markRead would then need TWO
    /// clicks (first click inserts into the set without
    /// changing visible state; second click toggles for real)
    /// since the toggle reads the set to decide direction.
    ///
    /// Skips the persistence write-through that didSet would
    /// fire by setting the published vars directly and then
    /// triggering a single deduped save.
    private func reconcileReadStarredFromStore() {
        guard let store = articleStore else { return }
        if let starredRows = try? store.fetchStarred() {
            var merged = starredArticleIDs
            for row in starredRows {
                merged.insert(row.uniqueID)
            }
            if merged.count != starredArticleIDs.count {
                starredArticleIDs = merged
            }
        }
        if let unreadRows = try? store.fetchUnread() {
            // SQLite's isRead=false means "not read". JSON set
            // contains read IDs. So we DROP these from JSON if
            // present? No — SQLite isRead=false could be stale
            // (user marked read but didn't fetch since). User's
            // JSON set is authoritative for "is read". Skip this
            // direction; only the starred branch above merges.
            // But: if JSON set has an id that SQLite doesn't
            // contradict (no row OR row with isRead=true), the
            // JSON wins. unreadRows here is just informational
            // — used by storedUnreadItems already. No action.
            _ = unreadRows
        }
    }

    private func hydrateFeedCachesFromStoreIfReady() {
        guard let articleStore else { return }
        guard let rows = try? articleStore.fetchAll(), !rows.isEmpty else { return }
        var grouped: [String: [PersistentArticle]] = [:]
        // Defensive: only hydrate caches for feeds that are
        // STILL subscribed. removeSubscription deletes per-feed
        // rows via try? articleStore.deleteForFeed, but that
        // call is silenced on failure (flaky disk). Without
        // this filter, a single failed delete leaves orphan
        // rows in SQLite that re-hydrate on every launch — the
        // unsubscribed feed's articles resurface in smart-feed
        // views forever.
        let subscribedIDs = Set(subscribedFeeds.map(\.id))
        for row in rows where subscribedIDs.contains(row.feedID) {
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
                    // Decode at read time: rows persisted before
                    // #121's per-parse entity decoding still
                    // store raw "AT&amp;T" form; decode on the
                    // way back into the in-memory items so the
                    // timeline reads naturally.
                    title: HTMLEntities.decode(row.title ?? "Untitled"),
                    link: (row.externalURL?.isEmpty == false) ? row.externalURL : row.url,
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
                    title: row.title.map(HTMLEntities.decode),
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
        //
        // Critically NOT setting didStartInitialLoad here: that
        // would block loadIfNeeded from firing the initial fetch
        // for the active feed, so the user would see stale cache
        // forever (until 30-min background tick or manual click).
        // Upstream NetNewsWire shows cache + immediately
        // refreshes; same pattern here — hydrate the visible
        // shape but leave the load gate open so onAppear's
        // loadIfNeeded triggers a fresh fetch.
        if let activeFeedID = selectedFeedID,
           let active = feedCaches[activeFeedID] {
            self.items = active.items
            self.articles = active.articles
            self.lastFetchAt = active.lastFetchAt
        }
    }

    /// Called from subscribedFeeds.didSet. Writes the current
    /// list to subscriptions.opml so subscribe / unsubscribe /
    /// reorder all survive relaunch. No-op during init (the
    /// persistenceReady gate prevents the initial assignment
    /// from clobbering disk before init has resolved the
    /// final list).
    /// Keep `subscriptionRoot` in lock-step with `subscribedFeeds`
    /// when the user is in the simple flat-list mode (no nested
    /// folders). Without this, appending to subscribedFeeds via
    /// addSubscription / mergeImportedFeeds would leave the root
    /// stale and the tree-export persistence path would write
    /// only the pre-mutation feeds, losing new additions across
    /// relaunch. When subscriptionRoot has real folder structure
    /// (named root OR any subfolders), assume the change came
    /// through an importer that already synced both views and
    /// don't touch.
    private func syncSubscriptionRootIfFlat() {
        let isFlatDefault = subscriptionRoot.name.isEmpty &&
            subscriptionRoot.subfolders.isEmpty
        if isFlatDefault {
            // Pure flat case — wholesale replace as before.
            guard subscriptionRoot.feeds != subscribedFeeds else { return }
            subscriptionRoot = OPMLImporter.Folder(
                name: "",
                feeds: subscribedFeeds,
                subfolders: []
            )
            return
        }
        // Tree-with-folders case: don't rebuild the tree (would
        // destroy folder structure), but DO append newly-added
        // feeds to root.feeds so a fresh addSubscription /
        // mergeImportedFeeds is visible in the sidebar. Without
        // this, addSubscription against a folder-organized
        // sidebar leaves the new feed in subscribedFeeds but
        // invisible in subscriptionRoot — sidebar doesn't
        // render it anywhere.
        let treeFeedIDs = Set(subscriptionRoot.allFeeds.map(\.id))
        let missingFromTree = subscribedFeeds.filter { !treeFeedIDs.contains($0.id) }
        guard !missingFromTree.isEmpty else { return }
        var copy = subscriptionRoot
        copy.feeds.append(contentsOf: missingFromTree)
        subscriptionRoot = copy
    }

    private func persistSubscriptionsIfReady() {
        guard persistenceReady else { return }
        // Tree-preserving export so folder structure (and any
        // future folder rename / reorder) round-trips through
        // the saved OPML. Flat exportOPMLData remains for tests
        // and callers that need flat semantics. OPMLImporter
        // .parseTree reads either shape back into the same
        // hierarchy.
        persistence.saveOPMLExport(exportOPMLTreeData())
    }

    /// Tree-preserving counterpart to exportOPMLData. Used by
    /// persistSubscriptionsIfReady so folder structure survives
    /// relaunch. Walks subscriptionRoot via OPMLExporter.exportTree.
    public func exportOPMLTreeData(title: String? = nil) -> Data {
        OPMLExporter.exportTreeData(root: subscriptionRoot, title: title)
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
        // Folder wins over feed (folder view supersedes the
        // active-feed selection it's blocking). Smart feed wins
        // over both — smart-feed select* clears the others.
        if let smart = selectedSmartFeed {
            state = PersistenceStore.SelectionState(smartFeed: smart.rawValue)
        } else if let folder = selectedFolderName {
            state = PersistenceStore.SelectionState(folderName: folder)
        } else if let feedID = selectedFeedID {
            state = PersistenceStore.SelectionState(feedID: feedID)
        } else {
            state = PersistenceStore.SelectionState()
        }
        persistence.saveSelection(state)
    }

    private func persistViewOptionsIfReady() {
        guard persistenceReady else { return }
        persistence.saveViewOptions(PersistenceStore.ViewOptions(
            hideReadArticles: hideReadArticles,
            sortOrder: sortOrder.rawValue,
            refreshIntervalSeconds: refreshIntervalSeconds
        ))
    }

    /// Persist the failure-count dict on every mutation. Same
    /// persistenceReady gate as the other did-set persistors
    /// so init-time loads don't ping-pong the disk.
    private func persistFeedFailureCountIfReady() {
        guard persistenceReady else { return }
        persistence.saveFeedFailureCount(feedFailureCount)
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
        let wasShowingFolder = selectedFolderName != nil
        selectedSmartFeed = nil
        selectedFolderName = nil
        guard id != selectedFeedID || wasShowingSmartFeed || wasShowingFolder else { return }
        selectedFeedID = id
        selectItem(id: nil)
        // Reset sticky-visible carry-over from the prior view.
        sessionStickyVisibleIDs.removeAll()
        // Clear the search field. Upstream NetNewsWire treats
        // search as per-view: switching feeds (or to a smart
        // feed / folder) returns the timeline to its full
        // contents. Without this, searching "swift" in Feed A
        // then clicking Feed B silently filtered Feed B too,
        // and the user couldn't tell why most rows were missing.
        searchQuery = ""
        // Dismiss any subscribe-toast lingering from the
        // previous view — feed switch is an explicit context
        // change that supersedes the older confirmation.
        lastSubscribeMessage = nil
        didStartInitialLoad = true
        // Hydrate from feedCaches IF the new selection has a
        // cached payload. Without this the previous feed's items
        // / articles / title linger on screen until fetch
        // resolves (often hundreds of ms on a slow network) —
        // misleading flash where the user sees feed A's content
        // under feed B's sidebar highlight. Cache wins
        // immediately; fetch updates further when it finishes
        // (merge semantics from iter #182 preserve cache items).
        // If no cache, clear items / articles / feedTitle so
        // the user sees an empty-but-correct view rather than
        // a stale-but-misleading one.
        if let cached = feedCaches[feed.id] {
            setItems(cached.items)
            articles = cached.articles
            // Restore subscribed-feed title so the header shows
            // the new feed's name even before parse completes.
            setFeedTitle(feed.title.isEmpty ? nil : feed.title)
        } else {
            setItems([])
            articles = []
            setFeedTitle(feed.title.isEmpty ? nil : feed.title)
        }
        await fetch(urlString: feed.url)
        autoSelectFirstUnreadIfNoSelection()
    }

    /// Auto-select the first unread item in the current view's
    /// filteredItems if nothing is currently selected. Called at
    /// the tail of selectFeed / selectSmartFeed / selectFolder so
    /// the detail pane isn't blank on view entry (matches
    /// upstream NetNewsWire's "land on something useful" behavior).
    ///
    /// Uses markAsRead: false (iter #206) — auto-select positions
    /// the cursor but does NOT mark the article read. The user
    /// hasn't actually opened it yet; they just navigated into a
    /// view. Marking read happens on j/k or click via the default
    /// selectItem path. Without this split, navigating into a
    /// view silently consumed one unread (badge dropped by 1 with
    /// zero user action; SQLite-sweep accounting diverged).
    func autoSelectFirstUnreadIfNoSelection() {
        guard selectedID == nil else { return }
        // Walk filteredItems (the actual visible pool) not the
        // raw items array. Smart-feed + folder views cross feed
        // boundaries; items only reflects the active feed.
        // Without filteredItems, entering All Unread or a folder
        // view would leave the detail pane blank because the
        // active feed might have nothing unread even though the
        // cross-feed view does.
        guard let firstUnread = filteredItems.first(where: { !readArticleIDs.contains($0.id) }) else {
            return
        }
        // markAsRead: false so the auto-select doesn't silently
        // consume an unread the user hasn't actually opened
        // yet. They explicitly opening via j/k or a click still
        // flips the bit through the default selectItem path.
        selectItem(id: firstUnread.id, markAsRead: false)
    }

    /// Pin the timeline to a smart-feed view (All Unread / Starred
    /// for now). Doesn't fetch — operates on whatever items the
    /// current feed already has loaded. Cross-feed aggregation
    /// arrives with the persistence iteration; until then, the
    /// smart feed effectively narrows the active feed's timeline.
    func selectSmartFeed(_ kind: SmartFeed?) {
        selectedSmartFeed = kind
        // Smart feed wins over folder; clear folder selection
        // so the two states don't compete in filteredItems.
        if kind != nil { selectedFolderName = nil }
        selectItem(id: nil)
        // Reset sticky-visible set on view change so the next
        // smart-feed visit starts with a clean filter; items
        // that were marked-read during the prior session no
        // longer linger.
        sessionStickyVisibleIDs.removeAll()
        // Search is per-view (matches upstream NetNewsWire); a
        // new smart-feed visit starts with the full pool.
        searchQuery = ""
        // Position the detail pane on the first unread without
        // consuming it (markAsRead: false). Matches upstream
        // NetNewsWire's "land on something useful on view
        // entry" behavior without lying about the unread count.
        autoSelectFirstUnreadIfNoSelection()
    }

    /// Select a folder-as-smart-feed view. Clears active smart
    /// feed AND active feed selection so filteredItems' folder
    /// branch engages. Pass nil to exit the folder view back to
    /// the active feed.
    func selectFolder(_ name: String?) {
        selectedFolderName = name
        if name != nil {
            selectedSmartFeed = nil
        }
        selectItem(id: nil)
        sessionStickyVisibleIDs.removeAll()
        // Search is per-view (matches upstream NetNewsWire).
        searchQuery = ""
        // Position the detail pane on the first unread without
        // consuming it (markAsRead: false). Same logic as
        // selectSmartFeed.
        autoSelectFirstUnreadIfNoSelection()
    }

    /// IDs of articles the user has opened during the current
    /// smart-feed / search session that should stay visible in
    /// the timeline even after auto-mark-as-read flips them
    /// read. Without this, opening an article in All Unread
    /// makes the row vanish mid-read (since the smart-feed
    /// filter immediately excludes read items). Cleared on
    /// selectFeed / selectSmartFeed / explicit refresh so the
    /// next view starts clean. Matches upstream NetNewsWire's
    /// behavior: the article you're reading stays where it is
    /// in the list, the row turns grey rather than disappearing,
    /// and the next refresh prunes it.
    @Published var sessionStickyVisibleIDs: Set<String> = []

    /// Move the active-feed selection to the next subscribed
    /// feed in subscribedFeeds order. Wraps at the end (last
    /// feed + next = no-op). Drops out of any active smart
    /// feed / folder view so the next feed's timeline becomes
    /// visible. Mirrors upstream NetNewsWire's ⌥⌘↓ "Go to Next
    /// Feed" command. No-op when there are zero or one
    /// subscribed feeds.
    func selectNextFeed() async {
        guard let nextID = adjacentFeedID(delta: 1) else { return }
        await selectFeed(id: nextID)
    }

    /// Symmetric to selectNextFeed for ⌥⌘↑ "Go to Previous
    /// Feed". Wraps at the start (first feed + prev = no-op).
    func selectPreviousFeed() async {
        guard let prevID = adjacentFeedID(delta: -1) else { return }
        await selectFeed(id: prevID)
    }

    /// Index lookup helper for the feed-nav shortcuts. When in
    /// a smart-feed / folder view (no selectedFeedID), start
    /// from the first feed regardless of direction so the user
    /// has a predictable entry point.
    private func adjacentFeedID(delta: Int) -> Feed.ID? {
        guard !subscribedFeeds.isEmpty else { return nil }
        guard let currentID = selectedFeedID,
              let idx = subscribedFeeds.firstIndex(where: { $0.id == currentID })
        else {
            return subscribedFeeds.first?.id
        }
        let nextIdx = idx + delta
        guard nextIdx >= 0, nextIdx < subscribedFeeds.count else { return nil }
        return subscribedFeeds[nextIdx].id
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

    /// Like `selectNextUnread()`, but when the current feed
    /// timeline is exhausted, jumps to the next subscribed feed
    /// (in sidebar order, wrapping past the end) that still has
    /// unread items in its cache and selects that feed's first
    /// unread article. Powers upstream NetNewsWire's "n" triage
    /// flow — press repeatedly to walk every unread article in
    /// every feed without manually switching feeds.
    ///
    /// Async because selectFeed itself awaits a fetch. The
    /// in-feed call (selectNextUnread) is sync and stays that
    /// way so existing button/shortcut callers continue to work
    /// without forcing every site to spawn a Task; this method
    /// is the upgrade path for callers that want cross-feed
    /// triage.
    @discardableResult
    func selectNextUnreadAcrossFeeds() async -> Bool {
        if selectNextUnread() { return true }
        guard let target = nextFeedIDWithUnread() else { return false }
        await selectFeed(id: target)
        return selectNextUnread()
    }

    /// Pure helper: returns the next subscribed feed (in sidebar
    /// order, wrapping past the end) after the current selection
    /// that has at least one unread item in its cache. Returns
    /// nil when:
    ///   - a smart feed is active (filteredItems already spans
    ///     every feed, so cross-feed jump is meaningless)
    ///   - no subscriptions
    ///   - no other feed has unread cached items
    ///
    /// Skips the current feed itself (the in-feed selectNextUnread
    /// already had its chance and returned false). Exposed so
    /// tests can pin the search logic without driving the real
    /// fetch() the async variant does.
    func nextFeedIDWithUnread() -> Feed.ID? {
        guard selectedSmartFeed == nil else { return nil }
        guard !subscribedFeeds.isEmpty else { return nil }
        // In folder view, the cross-feed pool (filteredItems →
        // itemsInFolder) already spans every feed inside the
        // folder. There's nowhere else to jump to without
        // escaping the folder view, which would surprise the
        // user. Return nil → caller no-ops at folder boundary.
        guard selectedFolderName == nil else { return nil }
        let currentIdx = subscribedFeeds.firstIndex(where: { $0.id == selectedFeedID }) ?? -1
        for offset in 1...subscribedFeeds.count {
            let idx = (currentIdx + offset) % subscribedFeeds.count
            let feed = subscribedFeeds[idx]
            if feed.id == selectedFeedID { continue }
            if unreadCount(forFeed: feed.id) > 0 {
                return feed.id
            }
        }
        return nil
    }

    /// Symmetric to nextFeedIDWithUnread but walks backwards.
    /// Used by selectPreviousUnreadAcrossFeeds so the back-
    /// triage flow is consistent with the forward one.
    func previousFeedIDWithUnread() -> Feed.ID? {
        guard selectedSmartFeed == nil else { return nil }
        guard selectedFolderName == nil else { return nil }
        guard !subscribedFeeds.isEmpty else { return nil }
        let currentIdx = subscribedFeeds.firstIndex(where: { $0.id == selectedFeedID })
            ?? subscribedFeeds.count
        for offset in 1...subscribedFeeds.count {
            // Modular subtraction; Swift's % returns negatives for
            // negative dividends, so normalize with .count.
            let idx = ((currentIdx - offset) % subscribedFeeds.count + subscribedFeeds.count) % subscribedFeeds.count
            let feed = subscribedFeeds[idx]
            if feed.id == selectedFeedID { continue }
            if unreadCount(forFeed: feed.id) > 0 {
                return feed.id
            }
        }
        return nil
    }

    /// Async counterpart to selectPreviousUnread that crosses
    /// feed boundaries — at the start-of-pool, jumps to the
    /// previous feed with unread and selects its LAST unread
    /// item (matching upstream's ⌘⇧N behavior of "walking
    /// backwards through everything I haven't read").
    @discardableResult
    func selectPreviousUnreadAcrossFeeds() async -> Bool {
        if selectPreviousUnread() { return true }
        guard let target = previousFeedIDWithUnread() else { return false }
        await selectFeed(id: target)
        // Land on the LAST unread, not the first — matches the
        // intuition of walking backwards.
        return selectLastUnreadInActiveFeed()
    }

    /// Select the LAST unread item in the current filteredItems
    /// pool. Returns true when something was selected. Used by
    /// the back-triage flow after crossing a feed boundary so
    /// the user lands at the bottom of the new feed's pool,
    /// not the top.
    @discardableResult
    func selectLastUnreadInActiveFeed() -> Bool {
        let pool = filteredItems
        for i in stride(from: pool.count - 1, through: 0, by: -1) {
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
        // Route through the tree-preserving import so dropped /
        // file-picked OPMLs surface their folder structure in
        // the sidebar (and round-trip through saved tree
        // persistence). Upstream NetNewsWire exports OPML with
        // <outline> group wrappers, so the previous flat parse
        // silently discarded the user's organization on every
        // import. The flat importOPML signature is preserved
        // for callers that don't care about hierarchy — they
        // still get the flat subscribedFeeds list as before.
        importOPMLTree(data: data)
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
        // Dedup on a stronger same-source key than raw URL: drop
        // scheme (treat http/https/feed as equivalent for dedup
        // purposes — server picks one), lowercase the host, and
        // strip any trailing slash. A re-imported OPML where the
        // same feed has a slightly-different surface form
        // (trailing slash, feed:// vs https://, case in host)
        // would otherwise double-subscribe AND double-render every
        // article in the timeline + the sidebar count.
        var existing = Set(subscribedFeeds.map { Self.feedDedupKey(for: $0.url) })
        var added = 0
        for feed in imported {
            let key = Self.feedDedupKey(for: feed.url)
            if existing.contains(key) { continue }
            existing.insert(key)
            subscribedFeeds.append(feed)
            added += 1
        }
        if selectedFeedID == nil {
            selectedFeedID = subscribedFeeds.first?.id
        }
        return added
    }

    /// Scheme-agnostic same-source key used by mergeImportedFeeds
    /// and any other dedup site that needs to treat http/https/
    /// feed variants of the same URL as the same feed. Internal
    /// so tests can pin specific normalizations without touching
    /// the broader normalizedURL helper (which is used at other
    /// call sites that care about scheme).
    static func feedDedupKey(for url: String) -> String {
        var s = url.trimmingWhitespace
        let lower = s.lowercased()
        for prefix in ["https://", "http://", "feeds://", "feed://"] {
            if lower.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        // Lowercase the host but preserve the path case (paths
        // are case-sensitive on most web servers — "/Feed" and
        // "/feed" can route to different resources). Split on
        // the first slash; everything before it is host.
        if let slashIdx = s.firstIndex(of: "/") {
            let host = s[..<slashIdx].lowercased()
            let path = s[slashIdx...]
            s = host + path
        } else {
            s = s.lowercased()
        }
        return s
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
        // Merge the imported tree into the existing
        // subscriptionRoot instead of clobbering it. The old
        // behavior — `subscriptionRoot = tree.root` — wiped
        // the user's existing folder organization the moment
        // they re-imported any OPML (or imported a second OPML
        // from a different source). Upstream NetNewsWire keeps
        // existing structure and adds only what's new.
        subscriptionRoot = Self.mergeFolderTrees(
            existing: subscriptionRoot,
            imported: tree.root
        )
        return mergeImportedFeeds(tree.root.allFeeds)
    }

    /// Merge `imported` into `existing`, returning a new tree
    /// that preserves every existing folder + feed and adds only
    /// what's new. Strategy:
    /// - Feeds: if `existing` (or any of its subfolders) already
    ///   contains a feed with matching feedDedupKey, skip it.
    ///   Otherwise add to whichever node of the IMPORTED tree
    ///   contained it — root-level imported feeds end up in
    ///   the existing root; folder-N imported feeds end up in
    ///   existing folder-N if it exists, else a new folder-N
    ///   is created under existing root.
    /// - Folders: matched by name (case-insensitive trim).
    ///   Same-name folders recurse. New folders get appended.
    static func mergeFolderTrees(
        existing: OPMLImporter.Folder, imported: OPMLImporter.Folder
    ) -> OPMLImporter.Folder {
        // Build a quick lookup of every feed dedup key in the
        // existing tree so we don't re-add anywhere.
        var existingKeys = Set<String>()
        collectFeedKeys(existing, into: &existingKeys)

        var merged = existing
        // Add root-level imported feeds that aren't anywhere
        // in existing.
        for feed in imported.feeds {
            let key = feedDedupKey(for: feed.url)
            if !existingKeys.contains(key) {
                merged.feeds.append(feed)
                existingKeys.insert(key)
            }
        }
        // Walk imported subfolders.
        for importedSub in imported.subfolders {
            let importedName = importedSub.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if let idx = merged.subfolders.firstIndex(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == importedName
            }) {
                merged.subfolders[idx] = mergeFolderTrees(
                    existing: merged.subfolders[idx],
                    imported: importedSub
                )
                collectFeedKeys(merged.subfolders[idx], into: &existingKeys)
            } else {
                // Whole new folder — adopt it as-is but filter out
                // feeds the user already has elsewhere in their
                // existing tree (those would create cross-folder
                // duplicates in the dedup key namespace).
                var copy = importedSub
                copy.feeds = importedSub.feeds.filter {
                    !existingKeys.contains(feedDedupKey(for: $0.url))
                }
                copy.subfolders = importedSub.subfolders.map {
                    filteringDuplicateFeeds(in: $0, against: existingKeys)
                }
                merged.subfolders.append(copy)
                collectFeedKeys(copy, into: &existingKeys)
            }
        }
        return merged
    }

    private static func collectFeedKeys(
        _ folder: OPMLImporter.Folder, into set: inout Set<String>
    ) {
        for feed in folder.feeds { set.insert(feedDedupKey(for: feed.url)) }
        for sub in folder.subfolders { collectFeedKeys(sub, into: &set) }
    }

    private static func filteringDuplicateFeeds(
        in folder: OPMLImporter.Folder, against keys: Set<String>
    ) -> OPMLImporter.Folder {
        var copy = folder
        copy.feeds = folder.feeds.filter {
            !keys.contains(feedDedupKey(for: $0.url))
        }
        copy.subfolders = folder.subfolders.map {
            filteringDuplicateFeeds(in: $0, against: keys)
        }
        return copy
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
        // Show the loading indicator during the OPML download +
        // parse. Same reasoning as addSubscription: user clicks
        // Import, otherwise no feedback until the round-trip
        // resolves. defer ensures it clears on every exit path
        // (success, throw, empty response).
        pushLoading()
        defer { popLoading() }
        do {
            let (maybeData, _) = try await Downloader.shared.download(url)
            guard let data = maybeData else {
                setError("OPML download was empty")
                return 0
            }
            // Pre-check the parse to distinguish "URL returned
            // HTML / not-OPML / empty OPML" from "OPML parsed
            // fine, all feeds were already subscribed." The
            // previous logic conflated both into "Already
            // subscribed" — misleading when the user pasted
            // the wrong URL (e.g. the site's home page instead
            // of an OPML export).
            let parsed = OPMLImporter.parseTree(data: data)
            if parsed.root.allFeeds.isEmpty {
                setError("No feeds found in OPML. Check the URL points to an OPML file.")
                return 0
            }
            let added = importOPMLTree(data: data)
            lastSubscribeMessage = added == 0
                ? "Already subscribed to those feeds"
                : "Imported \(added) feed\(added == 1 ? "" : "s")"
            return added
        } catch {
            setError("OPML import failed: \(Self.friendlyError(error))")
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
        // Clean per-feed state dicts so they don't accumulate
        // stale entries across the lifetime of the install. Each
        // of these gets persisted via its own JSON file; without
        // the cleanup, removing 100 feeds over a year leaves 100
        // dead entries in feedErrors.json + feedIconURLs.json +
        // implicit memory growth in feedFailureCount. Upstream
        // NetNewsWire's Account model handles this implicitly
        // via per-account-folder deletion; ours is flat so we do
        // it explicitly.
        feedErrors.removeValue(forKey: id)
        feedFailureCount.removeValue(forKey: id)
        feedIconURLs.removeValue(forKey: id)
        conditionalGetInfo.removeValue(forKey: id)
        feedLastErrorAt.removeValue(forKey: id)
        // Drop the feed's SQLite rows so they don't re-hydrate
        // into feedCaches on next launch and resurface in
        // smart-feed / search views. Failures swallow so a flaky
        // disk doesn't block the in-memory removal — the rows
        // would just leak quietly (much less bad than the unsub
        // never completing).
        try? articleStore?.deleteForFeed(id)
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
            // Clear feedTitle too — the timeline header subtitle
            // reads from it and would otherwise keep displaying
            // the deleted feed's name until the next selectFeed
            // fetch updated it. Misleading: user just unsub'd
            // "Daring Fireball" and the timeline header still
            // says "Daring Fireball" for several seconds.
            setFeedTitle(nil)
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
        // Short-circuit when the pasted URL already matches a
        // subscribed feed. Without this, an offline retry or a
        // duplicate paste pays the FeedFinder round-trip (HTTP
        // probe + HTML autodiscovery) just to discover what
        // we already know. Worse, offline runs return
        // "Subscribe failed: <network error>" instead of the
        // truthful "Already subscribed to X". Upstream NNW
        // does the same local pre-check.
        //
        // Uses feedDedupKey so the same surface-form rules apply
        // here as in mergeImportedFeeds — pasting feed://X or
        // https://X/ when subscribed to https://X both hit the
        // shortcut.
        let dedupKey = Self.feedDedupKey(for: normalized)
        if let existing = subscribedFeeds.first(where: { Self.feedDedupKey(for: $0.url) == dedupKey }) {
            lastSubscribeMessage = "Already subscribed to \(existing.title)"
            await selectFeed(id: existing.id)
            return existing
        }
        // Show the loading indicator during FeedFinder.find — it's
        // a real network round-trip (HTTP GET of the candidate
        // URL + HTML parse for <link rel="alternate"> + probes of
        // well-known feed paths). Without setLoading(true), the
        // UI looks frozen between Add-button-click and the
        // selectFeed-induced fetch that fires only after
        // autodiscovery resolves. Toggled back off either via
        // setLoading(false) on the failure paths or implicitly
        // via selectFeed → fetch's own push/popLoading on the
        // success path. Use push/pop here so the indicator
        // refcount stays balanced if selectFeed grabs it next.
        pushLoading()
        let candidates: Set<FeedSpecifier>
        do {
            candidates = try await FeedFinder.find(url: url)
        } catch {
            setError("Subscribe failed: \(Self.friendlyError(error))")
            popLoading()
            return nil
        }
        guard let best = FeedSpecifier.bestFeed(in: candidates) else {
            setError("No feed found at \(normalized)")
            popLoading()
            return nil
        }
        let feed = Feed(title: best.title ?? best.urlString, url: best.urlString)
        let added = mergeImportedFeeds([feed])
        if added == 0 {
            // Already subscribed — return the existing record.
            lastSubscribeMessage = "Already subscribed to \(feed.title)"
            popLoading()
            return subscribedFeeds.first(where: { $0.id == feed.id })
        }
        lastSubscribeMessage = "Subscribed to \(feed.title)"
        // selectFeed → fetch's own push/pop carries the
        // indicator forward; pop our refcount first so the
        // count stays correct.
        popLoading()
        // Auto-select the newly-subscribed feed so the sidebar
        // highlights it and the timeline starts populating with
        // its articles. Matches upstream NetNewsWire's post-
        // subscribe behavior. selectFeed already fetches, so the
        // user sees real items right away (or the empty state if
        // the feed has none).
        await selectFeed(id: feed.id)
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
        // User-facing export uses the tree shape so folder
        // organization makes it into the .opml file on disk.
        // Earlier this called exportOPMLData() — the FLAT shape —
        // so importing the file back (anywhere — Quill itself,
        // NetNewsWire, Feedbin, etc.) lost every folder. Tree
        // shape round-trips through OPMLImporter.parseTree on
        // re-import.
        let data = exportOPMLTreeData()
        guard let url = persistence.saveOPMLExport(data) else { return nil }
        lastOPMLExportURL = url
        return url
    }

    /// Path of the most recent OPML export, or nil when nothing
    /// has been exported yet. Surfaces in feedsPane footer so
    /// the user sees where the file landed.
    @Published var lastOPMLExportURL: URL?

    /// Transient confirmation for the last subscribe / import
    /// action — "Imported 5 feeds", "Already subscribed",
    /// "Subscribed to Daring Fireball", etc. Renders under the
    /// Import / Add row in the sidebar. Auto-clears on the next
    /// successful subscribe / import, on selectFeed (switching
    /// feeds dismisses the toast), and after a short delay set
    /// by the didSet auto-fade Task. Matches upstream NetNewsWire's
    /// transient toast that doesn't linger past relevance.
    @Published var lastSubscribeMessage: String? {
        didSet {
            // Rearm fade timer on every set, including the
            // explicit `= nil` clears (which just cancel the
            // prior fade Task without scheduling another).
            lastSubscribeMessageFadeTask?.cancel()
            guard let value = lastSubscribeMessage, !value.isEmpty else { return }
            lastSubscribeMessageFadeTask = Task { [weak self] in
                // 4s window — long enough to read a one-line
                // status without being intrusive, short enough
                // to disappear before the user has fully
                // forgotten what they just did.
                try? await Task.sleep(nanoseconds: 4 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Only clear if our message is still on
                    // screen — guards against racing a newer
                    // toast that already overwrote it.
                    if self?.lastSubscribeMessage == value {
                        self?.lastSubscribeMessage = nil
                    }
                }
            }
        }
    }
    private var lastSubscribeMessageFadeTask: Task<Void, Never>?

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
        // With no subscriptions, the view falls back to a hard-
        // coded URL (Daring Fireball) so the timeline always has
        // shape. But silently fetching that URL would surface
        // strangers' articles in a sidebar that says "No
        // subscriptions yet" — confusing. Skip the load when
        // the user has no real subscriptions; the empty state
        // makes the next step (Add Feed) explicit.
        guard !subscribedFeeds.isEmpty else {
            didStartInitialLoad = true
            return
        }
        didStartInitialLoad = true
        await fetch(urlString: urlString)
        // Refresh every other subscribed feed in the background
        // so sidebar unread counts + smart feeds reflect current
        // state shortly after launch. Upstream NetNewsWire does
        // the same — without it, every feed but the active one
        // stays at whatever cache age until the user selects it
        // or the 30-min background tick fires. Unawaited Task so
        // this doesn't block the active feed's UI handoff.
        // Honors the per-feed back-off skip from #98 so
        // permanently-dead feeds aren't re-hammered on every
        // launch.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for feed in self.subscribedFeeds where feed.url != urlString {
                if (self.feedFailureCount[feed.id] ?? 0) >= Self.feedFailureSkipThreshold {
                    continue
                }
                await self.fetchIntoCache(urlString: feed.url)
            }
        }
    }

    /// User-triggered refresh. Unlike `loadIfNeeded(urlString:)` this
    /// always re-fetches, even if the initial load has already run.
    /// No-op while a load is already in flight so rapid Refresh clicks
    /// don't pile up overlapping URLSession tasks.
    func refresh(urlString: String) async {
        // Per-URL gate instead of global isLoading so the user
        // can still trigger an active-feed refresh while
        // refreshAllFeeds' inactive batch is mid-flight.
        guard !isLoading(forURL: urlString) else { return }
        didStartInitialLoad = true
        await fetch(urlString: urlString)
    }

    /// Walk every subscribed feed (except the currently-active
    /// one, which gets refreshed via `refresh`) and fetch each
    /// into `feedCaches` without disturbing the timeline. Powers
    /// upstream NetNewsWire's 'Refresh All' command (⌘⌥R).
    ///
    /// Active feed first (UI updates promptly), then inactive
    /// feeds drain into the cache. Inactive-feed batch runs
    /// with a small concurrency window so 100 subscriptions
    /// don't take 100×fetch-time. The window is small (4) so
    /// we don't open too many TCP connections at once on
    /// shared hardware; httpMaximumConnectionsPerHost=1 in
    /// Downloader.swift still serializes per-host (different
    /// feeds usually live on different hosts).
    /// Per-feed errors are swallowed (cache stays at prior
    /// state for that feed) so one bad feed doesn't abort the
    /// whole pass.
    /// Refresh every feed inside the named folder concurrently.
    /// Used by the timeline Refresh button when the user is in
    /// folder view (#159) — without this, "Refresh" only hits
    /// the unrelated selectedFeedID feed. Honors per-feed back-
    /// off (same as refreshAllFeeds).
    func refreshFolder(_ folderName: String) async {
        guard !isLoading else { return }
        guard let folder = Self.findFolder(named: folderName, in: subscriptionRoot) else {
            return
        }
        let feedsInFolder = folder.allFeeds.filter { feed in
            (feedFailureCount[feed.id] ?? 0) < Self.feedFailureSkipThreshold
        }
        await Self.runWithConcurrencyLimit(feedsInFolder, limit: 4) { feed in
            await self.fetchIntoCache(urlString: feed.url)
        }
    }

    func refreshAllFeeds() async {
        guard !isLoading else { return }
        // Refresh active feed first so its UI updates promptly,
        // then drain the others into the cache only. Active
        // feed honors the same back-off threshold as the
        // inactive batch — otherwise a permanently-broken
        // active feed would re-hammer the network on every
        // Refresh All press. Explicit per-feed Refresh in the
        // inspector still bypasses back-off (that's the user
        // saying "no really, try again").
        if let activeURL = currentFeedURL,
           let activeFeed = subscribedFeeds.first(where: { $0.url == activeURL }),
           (feedFailureCount[activeFeed.id] ?? 0) < Self.feedFailureSkipThreshold {
            await fetch(urlString: activeURL)
        }
        let pending = subscribedFeeds.filter { feed in
            feed.url != currentFeedURL &&
            (feedFailureCount[feed.id] ?? 0) < Self.feedFailureSkipThreshold
        }
        await Self.runWithConcurrencyLimit(pending, limit: 4) { feed in
            await self.fetchIntoCache(urlString: feed.url)
        }
    }

    /// Run an async closure for each element with at most
    /// `limit` concurrent invocations. Used by refreshAllFeeds
    /// to bound the in-flight fetch count without going fully
    /// sequential. Order of completion is non-deterministic;
    /// per-feed callbacks must be independent.
    nonisolated static func runWithConcurrencyLimit<T: Sendable>(
        _ items: [T],
        limit: Int,
        _ work: @Sendable @escaping (T) async -> Void
    ) async {
        guard limit > 0, !items.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            var iterator = items.makeIterator()
            // Prime the pool with `limit` initial tasks.
            for _ in 0..<min(limit, items.count) {
                guard let item = iterator.next() else { break }
                group.addTask { await work(item) }
            }
            // As each finishes, queue the next item until the
            // iterator drains. Self-throttling — never more
            // than `limit` in flight at any moment.
            while await group.next() != nil {
                if let item = iterator.next() {
                    group.addTask { await work(item) }
                }
            }
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
        // Per-URL gate — Refresh All on OTHER feeds doesn't
        // block this one. Matches #141's refresh(urlString:)
        // semantic and the inspector button's disabled state
        // (#148).
        guard !isLoading(forURL: urlString) else { return }
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
        // Refcount-based isLoading so #139's concurrent
        // refreshAllFeeds doesn't race-flip the bool back to
        // false before all in-flight tasks finish. push/pop
        // hold isLoading=true until the LAST in-flight fetch
        // completes. Per-URL variant tracks which feed is in
        // flight so other paths can guard per-URL (#141).
        pushLoading(forURL: urlString)
        defer { popLoading(forURL: urlString) }
        // If the user removed this subscription between the time
        // refreshAllFeeds scheduled this fetch and the time it
        // actually ran, bail. Otherwise the fetch would resurrect
        // the cache entry (and the SQLite upsert below would
        // re-populate the per-feed rows we just deleted in
        // removeSubscription) — the feed would silently come
        // back from the dead until the next launch.
        guard subscribedFeeds.contains(where: { $0.url == urlString }) else {
            return
        }
        do {
            var request = URLRequest(url: url)
            if let info = Self.makeConditionalGetInfo(conditionalGetInfo[urlString]) {
                info.addRequestHeadersToURLRequest(&request)
            }
            let (maybeData, maybeResponse) = try await Downloader.shared.download(request)
            // 304 Not Modified — keep the cache, just bump
            // lastFetchAt + clear error.
            if let http = maybeResponse as? HTTPURLResponse, http.statusCode == 304 {
                feedErrors[urlString] = nil
                resetFailureCount(forFeed: urlString)
                if var cache = feedCaches[urlString] {
                    cache.lastFetchAt = Date()
                    feedCaches[urlString] = cache
                }
                // Refresh ETag / Last-Modified from the 304
                // response — RFC 7232 §4.1 allows servers to
                // update validators on a 304 (weak ETag bumped
                // without a body change). Without this, we'd
                // keep sending stale conditional headers and
                // potentially miss a real future update.
                if let dict = Self.dictFromConditionalGetInfo(HTTPConditionalGetInfo(urlResponse: http)) {
                    conditionalGetInfo[urlString] = dict
                }
                return
            }
            // Same HTTP-status guard as the active-feed fetch()
            // path — without it, a stale feed that's gone 410-Gone
            // would silently empty the cache without surfacing
            // the warning glyph in the sidebar.
            if let http = maybeResponse as? HTTPURLResponse, http.statusCode >= 400 {
                feedErrors[urlString] = Self.httpErrorMessage(forStatus: http.statusCode)
                incrementFailureCount(forFeed: urlString)
                return
            }
            guard let data = maybeData else {
                feedErrors[urlString] = "Empty response"
                incrementFailureCount(forFeed: urlString)
                return
            }
            let parsed = RSSFeedParser.parseUpstream(data: data, url: urlString)
            let upstreamArticles = RSSFeedParser.parseUpstreamArticles(data: data, url: urlString)
            // Append-merge with existing cache (dedupe by id /
            // uniqueID, new items win, cap by articlesPerFeedLimit).
            // Upstream NetNewsWire treats per-feed cache as an
            // accumulator — articles that fall off the live feed
            // shell still show under that feed's timeline until
            // retention prunes them. The old replace-behavior
            // silently dropped those rows from the in-memory cache
            // the moment they fell out of the publisher's feed
            // window, even though SQLite still had them. The smart-
            // feed views surfaced them via stored* helpers, but the
            // per-feed timeline went thin.
            let mergedItems = Self.mergeItemsForCache(
                new: parsed.items,
                existing: feedCaches[urlString]?.items ?? [],
                limit: Self.articlesPerFeedLimit
            )
            let mergedArticles = Self.mergeArticlesForCache(
                new: upstreamArticles,
                existing: feedCaches[urlString]?.articles ?? [],
                limit: Self.articlesPerFeedLimit
            )
            feedCaches[urlString] = FeedCache(
                items: mergedItems,
                articles: mergedArticles,
                lastFetchAt: Date()
            )
            // Use the merged-new view for SQLite upsert too so the
            // freshest payload wins on conflict (titles can change
            // post-publish; bodies can change too).
            let trimmedArticles = mergedArticles
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
                // Bound SQLite growth: drop the feed's oldest
                // rows beyond articleHistoryLimit. Per-feed
                // (not global) so popular feeds don't crowd
                // out infrequent ones. Read paths (stored*Items)
                // still see the kept window, which is way
                // beyond articlesPerFeedLimit.
                try? articleStore.pruneFeed(urlString, keeping: Self.articleHistoryLimit)
            }
            // Successful refresh-all path clears any prior error.
            feedErrors[urlString] = nil
            resetFailureCount(forFeed: urlString)
            // Save ETag / Last-Modified from the response so the
            // next fetch can send conditional-GET headers.
            if let http = maybeResponse as? HTTPURLResponse,
               let dict = Self.dictFromConditionalGetInfo(HTTPConditionalGetInfo(urlResponse: http)) {
                conditionalGetInfo[urlString] = dict
            }
            // Same icon-URL harvest as the active fetch path.
            if let icon = parsed.iconURL ?? parsed.faviconURL {
                feedIconURLs[urlString] = icon
            }
        } catch {
            // Quiet on the global Refresh-All path — one bad
            // feed shouldn't bust the whole pass — but stash
            // the error so feedsPane can show a warning glyph.
            feedErrors[urlString] = Self.friendlyError(error)
            incrementFailureCount(forFeed: urlString)
        }
    }

    func fetch(urlString: String) async {
        guard let url = URL(string: urlString) else {
            setError("Invalid URL")
            feedErrors[urlString] = "Invalid URL"
            return
        }
        pushLoading(forURL: urlString)
        defer { popLoading(forURL: urlString) }
        setError(nil)
        // Same removed-mid-flight guard as fetchIntoCache (iter
        // #222): if the user unsubscribed this URL between when
        // refreshAllFeeds queued the fetch and when it started
        // executing, bail before the network round-trip. Without
        // this, fetch would resurrect feedCaches[urlString] AND
        // overwrite items / articles for whatever feed is
        // currently active — clobbering the new feed's timeline
        // with the deleted feed's content. Daring Fireball
        // fallback (subscribedFeeds-empty path) is exempt: that
        // URL is intentionally synthetic and not in the
        // subscription list.
        if !subscribedFeeds.isEmpty,
           !subscribedFeeds.contains(where: { $0.url == urlString }) {
            return
        }
        do {
            // Upstream RSWeb Downloader: ephemeral session, no
            // cookies, single-host connection limit, NNW
            // User-Agent header set by UserAgent.headers(), and
            // short-lived in-memory DownloadCache that collapses
            // overlapping concurrent requests to the same URL.
            // Conditional GET: send If-Modified-Since /
            // If-None-Match from the prior response's headers.
            // Most active feeds publish a few times/day so this
            // turns ~99% of background refreshes into a 304
            // (no body, no parse).
            var request = URLRequest(url: url)
            if let info = Self.makeConditionalGetInfo(conditionalGetInfo[urlString]) {
                info.addRequestHeadersToURLRequest(&request)
            }
            let (maybeData, maybeResponse) = try await Downloader.shared.download(request)
            // 304 Not Modified — cache is current. Treat as
            // success (reset failure count, clear error) but
            // skip the parse + items update.
            if let http = maybeResponse as? HTTPURLResponse, http.statusCode == 304 {
                self.feedErrors[urlString] = nil
                resetFailureCount(forFeed: urlString)
                if let activeURL = currentFeedURL, activeURL == urlString {
                    self.lastFetchAt = Date()
                }
                // RFC 7232 §4.1 — servers can update validators
                // on a 304 (weak ETag bump without body change).
                // Refresh our stored conditional info so we
                // don't keep sending stale headers forever.
                if let dict = Self.dictFromConditionalGetInfo(HTTPConditionalGetInfo(urlResponse: http)) {
                    self.conditionalGetInfo[urlString] = dict
                }
                return
            }
            // Surface HTTP error status (4xx/5xx) as a descriptive
            // message instead of letting the parser run on the
            // error page body (which would silently produce
            // items=[] and look like a working-but-empty feed).
            // Matches upstream NetNewsWire's sidebar amber-warning
            // glyph + "Server returned 404" tooltip.
            if let http = maybeResponse as? HTTPURLResponse, http.statusCode >= 400 {
                let msg = Self.httpErrorMessage(forStatus: http.statusCode)
                self.setError(msg)
                feedErrors[urlString] = msg
                incrementFailureCount(forFeed: urlString)
                return
            }
            guard let data = maybeData else {
                self.setError("Empty response")
                feedErrors[urlString] = "Empty response"
                incrementFailureCount(forFeed: urlString)
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
            // Decode HTML entities in the parsed feed title before
            // surfacing it — many feeds publish their <title> with
            // entities ("AT&amp;T News") and we don't want those
            // literal in the sidebar / detail header.
            let decodedFeedTitle = parsed.title.map { HTMLEntities.decode($0) }
            // Header (feedTitle) prefers the user-renamed
            // subscribed-feed title when it diverges from the
            // URL fallback — without this, the parsed publisher
            // title would clobber the user's rename in the
            // detail-pane header (the sidebar already kept the
            // rename via updateSubscribedFeedTitleFromParse's
            // unedited guard; only the header was lying).
            let displayTitle: String? = {
                if let sub = self.subscribedFeeds.first(where: { $0.url == urlString }),
                   !sub.title.isEmpty,
                   sub.title != sub.url {
                    return sub.title
                }
                return decodedFeedTitle
            }()
            self.setFeedTitle(displayTitle)
            // If the parsed feed title is meaningful AND differs
            // from the user's sidebar entry, rename the
            // subscribed feed so the sidebar reads the canonical
            // <title> rather than the raw URL that was typed in
            // at subscribe time. Matches upstream NetNewsWire:
            // type "https://daringfireball.net/feeds/main", get
            // back "Daring Fireball" in the sidebar after the
            // first successful fetch. Only fires when the parsed
            // title is non-empty (preserves user's manual title
            // for feeds that lack <title>) and the sidebar entry
            // looks unedited (still equal to the feed URL —
            // signals "never been renamed yet").
            self.updateSubscribedFeedTitleFromParse(
                urlString: urlString, parsedTitle: decodedFeedTitle
            )
            // Append-merge with prior cache so items that fell
            // off the live feed shell stick around in the per-
            // feed timeline (matches upstream NetNewsWire's
            // accumulator semantics). Same helpers as the
            // refresh-all batch path so behavior is identical.
            let mergedItems = Self.mergeItemsForCache(
                new: parsed.items,
                existing: feedCaches[urlString]?.items ?? [],
                limit: Self.articlesPerFeedLimit
            )
            let mergedArticles = Self.mergeArticlesForCache(
                new: upstreamArticles,
                existing: feedCaches[urlString]?.articles ?? [],
                limit: Self.articlesPerFeedLimit
            )
            let trimmedItems = mergedItems
            let trimmedArticles = mergedArticles
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
                // Bound SQLite growth: drop the feed's oldest
                // rows beyond articleHistoryLimit. Per-feed
                // (not global) so popular feeds don't crowd
                // out infrequent ones. Read paths (stored*Items)
                // still see the kept window, which is way
                // beyond articlesPerFeedLimit.
                try? articleStore.pruneFeed(urlString, keeping: Self.articleHistoryLimit)
            }
            if self.selectedID == nil {
                // markAsRead: false — same reasoning as iter
                // #206's auto-select-on-view-change. Fetch-time
                // initial selection positions the cursor so the
                // detail pane has something to show; the user
                // hasn't actually opened the article. Marking
                // read would silently consume an unread on
                // every first fetch (and Mark-All-Read / SQLite-
                // sweep accounting would be off-by-one).
                self.selectItem(
                    id: self.preferredInitialItemID(in: self.items),
                    markAsRead: false
                )
            }
            self.lastFetchAt = now
            // Successful fetch clears any prior error tracked
            // for this feed.
            self.feedErrors[urlString] = nil
            resetFailureCount(forFeed: urlString)
            // Save ETag / Last-Modified for the NEXT request.
            if let http = maybeResponse as? HTTPURLResponse,
               let dict = Self.dictFromConditionalGetInfo(HTTPConditionalGetInfo(urlResponse: http)) {
                self.conditionalGetInfo[urlString] = dict
            }
            // Harvest the feed-declared icon URL if present.
            // Prefer iconURL (RSS image / Atom logo / JSON Feed
            // icon — the spec-canonical site icon) over
            // faviconURL (which upstream populates from
            // <link rel="icon"> when present).
            if let icon = parsed.iconURL ?? parsed.faviconURL {
                self.feedIconURLs[urlString] = icon
            }
        } catch {
            let friendly = Self.friendlyError(error)
            self.setError(friendly)
            self.feedErrors[urlString] = friendly
            incrementFailureCount(forFeed: urlString)
        }
        // popLoading via the defer at function top.
    }

    /// Human-readable "Updated N ago" string for the footer
    /// status bar. Empty when no fetch has happened yet so the
    /// footer falls through to the regular item-count text.
    /// Refreshes on every call against the current wall clock
    /// (callers should re-read whenever they re-render the
    /// footer; relativeFormatter is locale-aware).
    var lastFetchSummary: String {
        // In cross-feed views (smart feed or folder), the active
        // feed's lastFetchAt is misleading — the timeline is
        // showing a pool from every cached feed. Use the MAX
        // lastFetchAt across all caches (or the folder's
        // in-folder feeds) so the footer reflects the freshness
        // of what's actually rendered.
        let relevantDate: Date?
        if selectedSmartFeed != nil {
            // Smart feeds span everything.
            let allTimes = feedCaches.values.map(\.lastFetchAt) + [lastFetchAt].compactMap { $0 }
            relevantDate = allTimes.max()
        } else if let folderName = selectedFolderName,
                  let folder = Self.findFolder(named: folderName, in: subscriptionRoot) {
            // Folder view spans only the in-folder feeds.
            let inFolderTimes = folder.allFeeds.compactMap { feedCaches[$0.id]?.lastFetchAt }
            relevantDate = inFolderTimes.max()
        } else {
            relevantDate = lastFetchAt
        }
        guard let date = relevantDate else { return "" }
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
        selectItem(id: id, markAsRead: true)
    }

    /// Internal variant: `markAsRead: false` positions the cursor
    /// on an article without flipping it to read. Used by auto-
    /// select on view-entry — the user hasn't actually opened
    /// the article yet, just navigated into a view where the
    /// detail pane needs SOMETHING to show. Without this split,
    /// auto-selecting first-unread on smart-feed entry consumed
    /// the unread, dropping the badge by 1 the moment the user
    /// looked at the view (which broke tests AND silently lied
    /// to the user about the backlog size). Public so the auto-
    /// select wrapper can call through, but kept off the main
    /// API surface so casual callers default to mark-read.
    func selectItem(id: String?, markAsRead: Bool) {
        if selectedID != id {
            selectedID = id
        }
        guard let id else { return }
        // Sticky-visible needed wherever the next filteredItems
        // recompute would HIDE this row after markRead flips
        // its bit: cross-feed views (smart feed / folder /
        // search) AND active-feed view with Hide Read on.
        // Without the hideReadArticles case, opening an
        // article in the default active feed with Hide Read
        // toggled on made the row vanish mid-read just like
        // the cross-feed views did pre-#103.
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCrossFeedView = selectedSmartFeed != nil
            || selectedFolderName != nil
            || !trimmedQuery.isEmpty
        if isCrossFeedView || hideReadArticles {
            sessionStickyVisibleIDs.insert(id)
        }
        if markAsRead {
            markRead(id: id)
        }
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
                try? store.markRead(articleID: article.articleID, read: isRead)
                return
            }
        }
        // Cache miss → fall through to uniqueID-based lookup.
        // Necessary so mark-read on SQLite-only stored-unread /
        // stored-starred items (rows that have aged out of the
        // in-memory cache but are surfaced via #113/#114's
        // store-spanning smart feeds) actually update the
        // persistent bit. Without this, the JSON readArticleIDs
        // set caught the change but SQLite stayed stale, and
        // storedUnreadItems kept re-querying those rows on
        // every render.
        try? store.markReadByUniqueID(uniqueID, read: isRead)
    }

    private func persistStarredStateChange(uniqueID: String, starred: Bool) {
        guard let store = articleStore else { return }
        for (_, cache) in feedCaches {
            if let article = cache.articles.first(where: { $0.uniqueID == uniqueID }) {
                try? store.markStarred(articleID: article.articleID, starred: starred)
                return
            }
        }
        // Same cache-miss fall-through as persistReadStateChange.
        try? store.markStarredByUniqueID(uniqueID, starred: starred)
    }

    /// Mark every article in the currently-visible filtered
    /// timeline as read. Mirrors upstream NetNewsWire's
    /// 'Mark All Read' command (⌘⇧K). Returns the number of
    /// articles newly marked, so a UI surface can show
    /// "Marked 7 as read" feedback. No-op when the visible
    /// timeline is already fully-read or empty.
    @discardableResult
    func markAllVisibleAsRead() -> Int {
        let before = readArticleIDs.count
        // Snapshot visible IDs first — needed by every branch.
        let visibleIDs = filteredItems.map(\.id)
        for id in visibleIDs {
            // Route through markRead (not direct Set insert) so
            // each newly-marked article also propagates to the
            // ArticleStore. didSet still fires once per inserted
            // ID; persistence is per-row but batched closely so
            // SQLite handles it as one transaction.
            markRead(id: id)
        }
        // When the active view is the All Unread smart feed,
        // the rendered pool is capped at smartFeedStoredLimit
        // (500). A user with 5000 unread would have to click
        // Mark All Read ten times to actually reach zero.
        // Upstream NetNewsWire's ⌘⇧K on All Unread marks every
        // unread row, not just the visible cap. Walk the full
        // SQLite unread set to match.
        if selectedSmartFeed == .allUnread, let articleStore {
            if let storedRows = try? articleStore.fetchUnread() {
                for row in storedRows where !readArticleIDs.contains(row.uniqueID) {
                    markRead(id: row.uniqueID)
                }
            }
        }
        // Same logic for the Starred smart feed: a user with
        // 800 starred-and-unread items would otherwise need
        // ceil(800/500) clicks to clear them. Starred rows stay
        // visible even after read so the visual stays
        // consistent — Mark All Read just bumps the unread
        // badge. fetchStarred returns ALL starred rows (no read
        // filter), so we filter to unread-only here.
        if selectedSmartFeed == .starred, let articleStore {
            if let storedRows = try? articleStore.fetchStarred() {
                for row in storedRows where !readArticleIDs.contains(row.uniqueID) {
                    markRead(id: row.uniqueID)
                }
            }
        }
        // Folder-view symmetry: when the user clicks "All Read"
        // in a folder view, sweep each in-folder feed's SQLite
        // tail too — matches the markFolderAsRead / markFeedAsRead
        // SQLite sweeps from iter #184 / #185. Without this, the
        // SQLite-tail unreads for any in-folder feed survive the
        // sweep and resurface in All Unread.
        if let folderName = selectedFolderName,
           let articleStore,
           let folder = Self.findFolder(named: folderName, in: subscriptionRoot) {
            for feed in folder.allFeeds {
                if let storedRows = try? articleStore.fetch(forFeed: feed.id) {
                    for row in storedRows where !readArticleIDs.contains(row.uniqueID) {
                        markRead(id: row.uniqueID)
                    }
                }
            }
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

    /// Mark every article older than the selection as read.
    /// "Older" is defined relative to the current `sortOrder`:
    /// newest-first puts older articles BELOW the selection,
    /// oldest-first puts them ABOVE. Mirrors upstream
    /// NetNewsWire's 'Mark Older Articles as Read' (⌘⌥K) —
    /// the canonical end-of-triage shortcut. No-op when
    /// there's no selection.
    @discardableResult
    func markOlderThanSelectionAsRead() -> Int {
        switch sortOrder {
        case .newestFirst: return markBelowSelectionAsRead()
        case .oldestFirst: return markAboveSelectionAsRead()
        }
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

    /// Returns the URL of the currently selected article, if any,
    /// for the "b" → open-in-browser shortcut. Pure read so it's
    /// trivial to unit-test without spinning up the OpenURLAction
    /// process plumbing. The UI layer takes the URL and hands it
    /// to the environment's openURL action (xdg-open on Linux,
    /// LSOpenCFURLRef on macOS).
    ///
    /// Upstream NetNewsWire binds `b` to "Open in Browser" — the
    /// single most-used keystroke in the article reader after
    /// j/k navigation. Without it, every browser jump needed a
    /// trackpad to reach the inline link.
    /// Write the selected article's URL to the system clipboard.
    /// Returns the URL string on success, nil if nothing selected
    /// or no link URL on the item. Linux: shells out to wl-copy
    /// (Wayland) or xclip (X11); macOS: NSPasteboard. Matches
    /// upstream NetNewsWire's "Copy Article URL" command — most
    /// common reader workflow after "Open in Browser" (which is
    /// already wired to `b`).
    ///
    /// Lighter than wiring through QuillAppKit's NSPasteboard
    /// shim (which adds a dependency chain). Discoverable
    /// command absence falls through silently — the user
    /// notices the URL didn't land in their clipboard and can
    /// fall back to Open in Browser.
    @discardableResult
    func copySelectedItemURLToClipboard() -> String? {
        guard let url = selectedItemBrowserURL() else { return nil }
        let urlString = url.absoluteString
        Self.writeToSystemClipboard(urlString)
        return urlString
    }

    private static func writeToSystemClipboard(_ string: String) {
        #if os(Linux)
        let env = ProcessInfo.processInfo.environment
        if env["WAYLAND_DISPLAY"] != nil {
            runClipboardCommand(["/usr/bin/wl-copy"], stdin: string)
            return
        }
        if env["DISPLAY"] != nil {
            runClipboardCommand(
                ["/usr/bin/xclip", "-selection", "clipboard"],
                stdin: string
            )
        }
        #else
        // macOS path. NSPasteboard requires AppKit — for the
        // QuillNetNewsWireCore module we shell out to pbcopy
        // to stay AppKit-free. Same lightweight approach as
        // the Linux branch.
        runClipboardCommand(["/usr/bin/pbcopy"], stdin: string)
        #endif
    }

    private static func runClipboardCommand(_ args: [String], stdin: String) {
        guard let first = args.first else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: first)
        if args.count > 1 {
            process.arguments = Array(args.dropFirst())
        }
        let pipe = Pipe()
        process.standardInput = pipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            if let data = stdin.data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
            try pipe.fileHandleForWriting.close()
            process.waitUntilExit()
        } catch {
            // Silent fail — command not installed or
            // permission denied. User notices the clipboard
            // didn't update and can fall back to Open in
            // Browser. Surfacing an error toast for an
            // optional convenience would be more noise than
            // signal.
        }
    }

    func selectedItemBrowserURL() -> URL? {
        guard let selectedID,
              let item = items.first(where: { $0.id == selectedID })
                  ?? feedCaches.values
                      .flatMap(\.items)
                      .first(where: { $0.id == selectedID })
        else { return nil }
        return item.linkURL
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
    ///
    /// Walks both the active feed's `articles` AND every
    /// cached feed's articles so cross-feed picks (smart feed
    /// row from another feed) still surface author byline +
    /// friendly date. SQLite-only stored items are NOT searched
    /// here — PersistentArticle drops authors at persist time
    /// so reconstitution would be empty-authored anyway; the
    /// detail-pane gracefully falls back to "no author line".
    func article(forItem itemID: String) -> Article? {
        if let active = articles.first(where: { $0.uniqueID == itemID }) {
            return active
        }
        for (_, cache) in feedCaches {
            if let cached = cache.articles.first(where: { $0.uniqueID == itemID }) {
                return cached
            }
        }
        return nil
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
        // Decode HTML entities in author names — same Wordpress-
        // pattern reason as title decoding in #121. "Jos&eacute;
        // Garc&iacute;a" should read as the actual name in the
        // timeline byline.
        let names = authors
            .compactMap(\.name)
            .filter { !$0.isEmpty }
            .map(HTMLEntities.decode)
        guard !names.isEmpty else { return nil }
        return names.sorted().joined(separator: ", ")
    }

    /// Source feed title for an article, derived by reverse-
    /// looking up the item id in the active feed's items list
    /// first, then every cached feed. Returns nil when nothing
    /// matches (e.g. the article cache evicted it). Used by
    /// the detail header in cross-feed views (smart feed,
    /// search) so users know which feed the article came from
    /// without going back to the timeline. Mirrors upstream
    /// NetNewsWire's detail-pane feed-name breadcrumb.
    func feedTitle(forItemID itemID: String) -> String? {
        // Active feed: items + currentFeedURL → look up
        // subscribedFeeds for the title.
        if let activeURL = currentFeedURL,
           items.contains(where: { $0.id == itemID }) {
            return subscribedFeeds.first(where: { $0.url == activeURL })?.title
        }
        // Cached feeds.
        for (feedURL, cache) in feedCaches {
            if cache.items.contains(where: { $0.id == itemID }) {
                return subscribedFeeds.first(where: { $0.url == feedURL })?.title
            }
        }
        return nil
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

    /// True when `selectNextItem()` would change the selection.
    /// Powers the detail-header prev/next arrows so the
    /// disabled-at-boundary state mirrors the actual behavior.
    /// Returns false when there's no selection (selectNextItem
    /// auto-selects the first item in that case, but a disabled
    /// "Next" affordance reads more honestly than a button that
    /// jumps the cursor in unexpectedly).
    var canSelectNext: Bool {
        let pool = filteredItems
        guard let id = selectedID,
              let index = pool.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return pool.index(after: index) < pool.endIndex
    }

    /// True when `selectPreviousItem()` would change the
    /// selection. Same disabled-at-boundary semantic as
    /// canSelectNext.
    var canSelectPrevious: Bool {
        let pool = filteredItems
        guard let id = selectedID,
              let index = pool.firstIndex(where: { $0.id == id }) else {
            return false
        }
        return index > 0
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

    /// Cutoff for the Today smart feed: start of the current
    /// local-time calendar day. Matches upstream NetNewsWire's
    /// SmartFeedDelegate behavior — "Today" means items
    /// published since local midnight, NOT a 24h sliding
    /// window. The sliding-window form silently dropped early-
    /// morning articles right after midnight (a 2 AM read
    /// session would have an empty Today feed even though
    /// items from 8 hours earlier were trivially "today").
    /// Internal so tests can wire a fixed now for determinism.
    static func todayCutoff(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }

    /// Today-cohort item count IGNORING readArticleIDs — i.e.,
    /// "how many today-published articles exist across all
    /// caches?" Used by the Today empty-state branch to
    /// distinguish "nothing published today" from "today's
    /// articles all read AND Hide Read is on". The regular
    /// count(for: .today) couples with readArticleIDs through
    /// applyHideRead during render, which is the wrong shape
    /// for an empty-state explanation.
    func todayItemCountIgnoringReadState() -> Int {
        let cutoff = Self.todayCutoff()
        let allArticles = articles + feedCaches.values.flatMap(\.articles)
        let todayIDs = Set(allArticles.compactMap { article -> String? in
            guard let d = article.datePublished, d >= cutoff else { return nil }
            return article.uniqueID
        })
        return todayIDs.count
    }

    /// Append-merge new RSSItems on top of existing cache items,
    /// dedupe by id (new wins), cap by limit. Newest items go
    /// first — input is already in newest-first parse order, and
    /// existing items are also stored newest-first, so a simple
    /// concat-then-dedupe preserves chronology adequately for
    /// the per-feed timeline.
    static func mergeItemsForCache(
        new: [RSSItem], existing: [RSSItem], limit: Int
    ) -> [RSSItem] {
        var seen = Set<String>()
        var merged: [RSSItem] = []
        for item in new {
            if seen.insert(item.id).inserted { merged.append(item) }
            if merged.count >= limit { return merged }
        }
        for item in existing {
            if seen.insert(item.id).inserted { merged.append(item) }
            if merged.count >= limit { return merged }
        }
        return merged
    }

    /// Same shape as mergeItemsForCache but for the parallel
    /// upstream Article array (keyed by uniqueID).
    static func mergeArticlesForCache(
        new: [Article], existing: [Article], limit: Int
    ) -> [Article] {
        var seen = Set<String>()
        var merged: [Article] = []
        for article in new {
            if seen.insert(article.uniqueID).inserted { merged.append(article) }
            if merged.count >= limit { return merged }
        }
        for article in existing {
            if seen.insert(article.uniqueID).inserted { merged.append(article) }
            if merged.count >= limit { return merged }
        }
        return merged
    }

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
            let cutoff = Self.todayCutoff()
            let allArticles = articles + feedCaches.values.flatMap(\.articles)
            let recentIDs = Set(allArticles.compactMap { article -> String? in
                guard let d = article.datePublished, d >= cutoff else { return nil }
                return article.uniqueID
            })
            return union.reduce(0) { $0 + (recentIDs.contains($1.id) ? 1 : 0) }
        case .allUnread:
            // Sidebar badge — must reflect the TRUE count, not
            // the smartFeedStoredLimit cap on the rendered pool.
            // Walk the full SQLite unread (cheap count query),
            // subtract the cached IDs that overlap (avoid double-
            // count), then add cache-only unread.
            let cachedUnread = union.filter { !readArticleIDs.contains($0.id) }
            let cachedIDs = Set(cachedUnread.map(\.id))
            let storedCount = (try? articleStore?.countUnread()) ?? 0 ?? 0
            // storedCount includes rows that ARE in cache, so
            // approximate the "stored-only-extras" by subtracting
            // cached overlap. Worst case slight under-count if
            // some cached items aren't in SQLite yet (transient).
            let storedOnly = max(0, storedCount - cachedIDs.count)
            return cachedIDs.count + storedOnly
        case .starred:
            // Same uncapped-count pattern as .allUnread.
            let cachedStarred = union.filter { starredArticleIDs.contains($0.id) }
            let cachedIDs = Set(cachedStarred.map(\.id))
            let storedCount = (try? articleStore?.countStarred()) ?? 0 ?? 0
            let storedOnly = max(0, storedCount - cachedIDs.count)
            return cachedIDs.count + storedOnly
        }
    }

    /// Unread count for a subscribed feed. Prefers the SQLite
    /// count (spans full history) over the cache count (capped
    /// by articlesPerFeedLimit), then falls back to cache when
    /// no articleStore is wired. Active feed previously used
    /// items-based `unreadCount` alone (undercount by SQLite-tail
    /// for feeds with >100 unread); now also takes max(items,
    /// SQLite) so the active-feed badge matches the inactive
    /// path.
    func unreadCount(forFeed feedID: Feed.ID) -> Int {
        let cacheCount: Int
        if feedID == selectedFeedID {
            // Active feed: items has the live merge (fresh fetch
            // + cache tail per iter #182). Use items count
            // rather than feedCaches[feedID] because brand-new
            // items haven't necessarily been mirrored into the
            // cache map yet.
            cacheCount = unreadCount
        } else if let cache = feedCaches[feedID] {
            cacheCount = cache.items.reduce(0) { acc, item in
                acc + (readArticleIDs.contains(item.id) ? 0 : 1)
            }
        } else {
            cacheCount = 0
        }
        // Prefer the larger of cache vs SQLite. In production
        // SQLite is always >= cache (every fetch upserts trimmed
        // articles), so SQLite wins — surfaces the full unread
        // backlog beyond articlesPerFeedLimit. In tests that
        // populate feedCaches directly without touching SQLite,
        // cache wins so the count isn't silently 0.
        let storedCount = (try? articleStore?.countUnread(forFeed: feedID)) ?? 0 ?? 0
        return max(cacheCount, storedCount)
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
        // Also walk SQLite — per-feed retention keeps up to
        // articleHistoryLimit rows (500 default), but the cache
        // caps at articlesPerFeedLimit (100). Anything in the
        // 100-500 stale tail won't get marked by the in-memory
        // pass above; without this, those stored-only unreads
        // would persist as unread in storedUnreadItems / the
        // All Unread smart-feed badge after "Mark Feed Read"
        // — directly contradicting the user's intent. Mirrors
        // upstream NetNewsWire's account-store mark-all-read
        // sweep that touches every persisted row for the feed.
        if let articleStore,
           let storedRows = try? articleStore.fetch(forFeed: feedID) {
            for row in storedRows where !readArticleIDs.contains(row.uniqueID) {
                markRead(id: row.uniqueID)
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
    /// Rename a folder anywhere in the subscriptionRoot
    /// hierarchy (recursive walk by name match). Returns true
    /// when a folder was found and renamed. Mirrors upstream
    /// NetNewsWire's sidebar folder-rename action. The mutation
    /// triggers persistence via the subscriptionRoot didSet, so
    /// the new name survives relaunch (now that exportTree
    /// preserves folder hierarchy).
    ///
    /// Conflict guard: refuses to rename when `to` is empty
    /// (would lose folder identity) or when a sibling folder
    /// already has the target name (would create a duplicate
    /// that Folder.id-by-name can't distinguish). Returns false
    /// in both cases without mutating.
    /// Manually rename a subscribed feed. Mirrors upstream
    /// NetNewsWire's "Rename Feed" sidebar action. Updates the
    /// title in both subscribedFeeds AND subscriptionRoot so
    /// the flat-list and tree-view stay in sync. Once a feed
    /// is manually renamed, the auto-rename-from-parse path
    /// (updateSubscribedFeedTitleFromParse) leaves it alone
    /// since the title no longer equals the URL.
    ///
    /// Refuses empty/whitespace new title (would lose the
    /// label entirely; URL fallback is the conservative
    /// default for nameless feeds). Returns true when a
    /// matching feed was found and renamed.
    @discardableResult
    func renameFeed(_ feedID: Feed.ID, to newTitle: String) -> Bool {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let idx = subscribedFeeds.firstIndex(where: { $0.id == feedID }) else {
            return false
        }
        let current = subscribedFeeds[idx]
        guard current.title != trimmed else { return true } // idempotent
        subscribedFeeds[idx] = Feed(title: trimmed, url: current.url)
        // Mirror into subscriptionRoot too — without this, the
        // tree view would still render the old title. Recursive
        // walk; first match wins (feeds are unique by URL).
        let (updated, _) = Self.renameFeedInTree(
            feedID: feedID, newTitle: trimmed, in: subscriptionRoot
        )
        subscriptionRoot = updated
        return true
    }

    private static func renameFeedInTree(
        feedID: Feed.ID,
        newTitle: String,
        in folder: OPMLImporter.Folder
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        if let idx = copy.feeds.firstIndex(where: { $0.id == feedID }) {
            copy.feeds[idx] = Feed(title: newTitle, url: copy.feeds[idx].url)
            return (copy, true)
        }
        var didRename = false
        var newSubfolders: [OPMLImporter.Folder] = []
        for sub in copy.subfolders {
            let (updatedSub, subDid) = renameFeedInTree(
                feedID: feedID, newTitle: newTitle, in: sub
            )
            if subDid { didRename = true }
            newSubfolders.append(updatedSub)
        }
        copy.subfolders = newSubfolders
        return (copy, didRename)
    }

    @discardableResult
    func renameFolder(from oldName: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != oldName else { return true } // no-op success
        let (updated, didRename) = Self.renameFolderRecursively(
            in: subscriptionRoot, from: oldName, to: trimmed
        )
        guard didRename else { return false }
        subscriptionRoot = updated
        // Carry the active folder selection across the rename
        // so the user stays in the same view rather than
        // dropping back to whatever the fall-through is.
        if selectedFolderName == oldName {
            selectedFolderName = trimmed
        }
        return true
    }

    /// Add a new top-level folder to subscriptionRoot. Returns
    /// true when the folder was added; false when the name is
    /// empty/whitespace or already exists as a top-level
    /// sibling. New folders start empty (no feeds, no
    /// subfolders) — the user populates them via subsequent
    /// move-feed actions. Mutation triggers persistence via
    /// the subscriptionRoot didSet chain.
    ///
    /// Top-level only by design — upstream NetNewsWire's "New
    /// Folder" command also creates at the root. Nested folder
    /// creation would need a parent-selection UI that doesn't
    /// exist yet.
    @discardableResult
    func addFolder(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !subscriptionRoot.subfolders.contains(where: { $0.name == trimmed }) else {
            return false
        }
        var copy = subscriptionRoot
        copy.subfolders.append(OPMLImporter.Folder(
            name: trimmed, feeds: [], subfolders: []
        ))
        subscriptionRoot = copy
        return true
    }

    /// Remove a folder anywhere in the subscriptionRoot
    /// hierarchy. Feeds inside the removed folder migrate to
    /// its parent (so subscriptions don't disappear when their
    /// folder does); subfolders likewise flatten up one level.
    /// Returns true when a folder was found and removed.
    ///
    /// Matches upstream NetNewsWire's "Delete Folder" behavior:
    /// the folder vanishes from the sidebar but the feeds it
    /// contained stay subscribed. The mutation triggers
    /// persistence via the subscriptionRoot didSet chain.
    @discardableResult
    func removeFolder(named name: String) -> Bool {
        let (updated, didRemove) = Self.removeFolderRecursively(
            in: subscriptionRoot, name: name
        )
        guard didRemove else { return false }
        subscriptionRoot = updated
        // Drop folder-view selection if the active folder was
        // the one removed — otherwise the view would silently
        // empty out (selection points at nonexistent folder).
        if selectedFolderName == name {
            selectedFolderName = nil
        }
        return true
    }

    /// Move a feed (by id) into the named folder, or to the
    /// top level when folderName is nil. Two-step mutation:
    /// first removes the feed from every existing location
    /// (top-level + every subfolder), then inserts at the
    /// destination. Returns true when the feed was found and
    /// moved; false when:
    ///   - feed id doesn't exist in subscriptionRoot
    ///   - target folder name doesn't exist (nil destination
    ///     is always valid — moves to top-level root)
    ///
    /// Idempotent in the same-destination case (moving a feed
    /// to its current folder is a successful no-op).
    ///
    /// Doesn't touch subscribedFeeds (the flat list is
    /// orthogonal to folder organization — the feed stays
    /// subscribed throughout the move). Mutation triggers
    /// persistence via the subscriptionRoot didSet chain.
    @discardableResult
    func moveFeed(_ feedID: Feed.ID, toFolder folderName: String?) -> Bool {
        // Verify the target folder exists (or destination is
        // root) before mutating — otherwise we'd strip the feed
        // from its current home and have nowhere to put it.
        if let folderName,
           !Self.folderExists(named: folderName, in: subscriptionRoot) {
            return false
        }
        // Snapshot the feed before removal so we can re-insert
        // after the tree is updated.
        guard let feed = Self.findFeed(feedID: feedID, in: subscriptionRoot) else {
            return false
        }
        let (stripped, _) = Self.removeFeedFromTree(feedID: feedID, in: subscriptionRoot)
        let updated = Self.insertFeed(feed, intoFolderNamed: folderName, in: stripped)
        subscriptionRoot = updated
        return true
    }

    /// Reorder a feed within its current parent (top-level or
    /// the folder it's in) by `delta` slots. Positive moves
    /// down, negative moves up. Saturates at the parent's
    /// bounds (no wraparound — moving the top feed up is a
    /// no-op, not a jump to bottom). Returns true when the
    /// feed actually moved.
    ///
    /// Doesn't cross folder boundaries — that's moveFeed
    /// (toFolder:)'s job. Mutation triggers persistence via
    /// the subscriptionRoot didSet chain.
    @discardableResult
    /// Sort every feed list alphabetically by title (case-
    /// insensitive). Applies to BOTH subscribedFeeds (flat
    /// list) AND subscriptionRoot (recursively into every
    /// folder's feeds). Folders themselves keep their order
    /// — only the leaf feeds get sorted within their parent.
    /// Mutation triggers persistence via the existing didSets
    /// so the new order survives relaunch.
    ///
    /// Same idempotent guarantee as the other tree mutators:
    /// if the sort produces the same order, no persistence
    /// write fires (didSet's setter is unconditional but the
    /// re-assign of identical content gives the same OPML
    /// output → atomic-write is a no-op for the file).
    func sortFeedsAlphabetically() {
        subscribedFeeds.sort { Self.lessByTitle($0, $1) }
        subscriptionRoot = Self.sortFeedsInTree(subscriptionRoot)
    }

    private static func lessByTitle(_ lhs: Feed, _ rhs: Feed) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func sortFeedsInTree(_ folder: OPMLImporter.Folder) -> OPMLImporter.Folder {
        var copy = folder
        copy.feeds.sort(by: lessByTitle)
        // Also alphabetize folder ORDER, not just feeds within
        // a folder. Upstream NetNewsWire's "Sort by Name" does
        // both — without this, the sidebar's folders stayed in
        // insertion order even after Sort A-Z, which made the
        // affordance feel incomplete for users with many
        // folders.
        copy.subfolders = copy.subfolders
            .map { sortFeedsInTree($0) }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return copy
    }

    func reorderFeed(_ feedID: Feed.ID, by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let (updated, didMove) = Self.reorderFeedInTree(
            feedID: feedID, by: delta, in: subscriptionRoot
        )
        guard didMove else { return false }
        subscriptionRoot = updated
        return true
    }

    /// Pure recursive helper. Finds the feed's parent (top
    /// folder or a subfolder), swaps it `delta` positions
    /// within that parent's `feeds` array. Returns (folder,
    /// didMove). First match wins.
    /// Would a `reorderFeed(_:by:)` call actually move the feed?
    /// Used by the inspector ↑/↓ buttons to greyout at-boundary
    /// so the affordance reads honestly. Returns false when the
    /// feed isn't in the tree, when delta is 0, or when target
    /// index equals current index (top-of-parent + up = no-op,
    /// bottom + down = no-op).
    func canReorderFeed(_ feedID: Feed.ID, by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        return Self.canReorderFeedInTree(
            feedID: feedID, by: delta, in: subscriptionRoot
        )
    }

    private static func canReorderFeedInTree(
        feedID: Feed.ID, by delta: Int, in folder: OPMLImporter.Folder
    ) -> Bool {
        if let idx = folder.feeds.firstIndex(where: { $0.id == feedID }) {
            let target = max(0, min(folder.feeds.count - 1, idx + delta))
            return target != idx
        }
        return folder.subfolders.contains {
            canReorderFeedInTree(feedID: feedID, by: delta, in: $0)
        }
    }

    private static func reorderFeedInTree(
        feedID: Feed.ID,
        by delta: Int,
        in folder: OPMLImporter.Folder
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        if let idx = copy.feeds.firstIndex(where: { $0.id == feedID }) {
            let target = max(0, min(copy.feeds.count - 1, idx + delta))
            guard target != idx else { return (copy, false) }
            let feed = copy.feeds.remove(at: idx)
            copy.feeds.insert(feed, at: target)
            return (copy, true)
        }
        var didMove = false
        var newSubfolders: [OPMLImporter.Folder] = []
        for sub in copy.subfolders {
            let (updatedSub, subDid) = reorderFeedInTree(
                feedID: feedID, by: delta, in: sub
            )
            if subDid { didMove = true }
            newSubfolders.append(updatedSub)
        }
        copy.subfolders = newSubfolders
        return (copy, didMove)
    }

    /// Reorder a folder within its current parent (root or
    /// a parent folder when nested) by `delta` slots. Symmetric
    /// to reorderFeed: positive moves down, negative moves up,
    /// saturates at parent bounds. Returns true when the folder
    /// actually moved.
    @discardableResult
    func reorderFolder(named name: String, by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        let (updated, didMove) = Self.reorderFolderInTree(
            named: name, by: delta, in: subscriptionRoot
        )
        guard didMove else { return false }
        subscriptionRoot = updated
        return true
    }

    /// Symmetric to canReorderFeed for the folder ↑/↓ buttons.
    /// False when delta=0, name not in tree, or target index ==
    /// current.
    func canReorderFolder(named name: String, by delta: Int) -> Bool {
        guard delta != 0 else { return false }
        return Self.canReorderFolderInTree(
            named: name, by: delta, in: subscriptionRoot
        )
    }

    private static func canReorderFolderInTree(
        named name: String, by delta: Int, in folder: OPMLImporter.Folder
    ) -> Bool {
        if let idx = folder.subfolders.firstIndex(where: { $0.name == name }) {
            let target = max(0, min(folder.subfolders.count - 1, idx + delta))
            return target != idx
        }
        return folder.subfolders.contains {
            canReorderFolderInTree(named: name, by: delta, in: $0)
        }
    }

    private static func reorderFolderInTree(
        named name: String,
        by delta: Int,
        in folder: OPMLImporter.Folder
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        if let idx = copy.subfolders.firstIndex(where: { $0.name == name }) {
            let target = max(0, min(copy.subfolders.count - 1, idx + delta))
            guard target != idx else { return (copy, false) }
            let f = copy.subfolders.remove(at: idx)
            copy.subfolders.insert(f, at: target)
            return (copy, true)
        }
        var didMove = false
        var newSubfolders: [OPMLImporter.Folder] = []
        for sub in copy.subfolders {
            let (updatedSub, subDid) = reorderFolderInTree(
                named: name, by: delta, in: sub
            )
            if subDid { didMove = true }
            newSubfolders.append(updatedSub)
        }
        copy.subfolders = newSubfolders
        return (copy, didMove)
    }

    private static func folderExists(
        named name: String,
        in folder: OPMLImporter.Folder
    ) -> Bool {
        if folder.subfolders.contains(where: { $0.name == name }) { return true }
        return folder.subfolders.contains { folderExists(named: name, in: $0) }
    }

    private static func findFeed(
        feedID: Feed.ID,
        in folder: OPMLImporter.Folder
    ) -> Feed? {
        if let feed = folder.feeds.first(where: { $0.id == feedID }) {
            return feed
        }
        for sub in folder.subfolders {
            if let feed = findFeed(feedID: feedID, in: sub) {
                return feed
            }
        }
        return nil
    }

    /// Name of the immediate-parent subfolder containing a feed,
    /// or nil when the feed is at the root level (or not in the
    /// tree at all). Used by the inspector's "Move to" picker so
    /// the current home is marked + disabled. Walks recursively;
    /// returns the deepest containing folder's name (a feed
    /// shouldn't appear in multiple folders simultaneously,
    /// but if it did, we'd report the first one encountered).
    func folderName(containing feedID: Feed.ID) -> String? {
        Self.folderName(containing: feedID, in: subscriptionRoot)
    }

    /// Flat list of every folder in subscriptionRoot, depth-
    /// first, for the inspector's "Move to" picker. Each entry
    /// carries depth so the UI can indent nested folders. Used
    /// to expose nested-folder destinations the prior surface
    /// missed (it only enumerated top-level subfolders, so
    /// imported OPMLs with nested structure couldn't target
    /// the inner folders).
    struct FolderTarget: Sendable, Hashable {
        public let name: String
        public let depth: Int
    }

    func allFolderTargets() -> [FolderTarget] {
        var out: [FolderTarget] = []
        Self.collectFolderTargets(subscriptionRoot, depth: 0, into: &out)
        return out
    }

    private static func collectFolderTargets(
        _ folder: OPMLImporter.Folder, depth: Int, into out: inout [FolderTarget]
    ) {
        for sub in folder.subfolders {
            out.append(FolderTarget(name: sub.name, depth: depth))
            collectFolderTargets(sub, depth: depth + 1, into: &out)
        }
    }

    private static func folderName(
        containing feedID: Feed.ID, in folder: OPMLImporter.Folder
    ) -> String? {
        for sub in folder.subfolders {
            if sub.feeds.contains(where: { $0.id == feedID }) {
                return sub.name
            }
            if let nested = folderName(containing: feedID, in: sub) {
                return nested
            }
        }
        return nil
    }

    /// Pure recursive feed-removal — strips every occurrence of
    /// the feed across the whole tree. Doesn't migrate anything
    /// (unlike removeFolderRecursively); the caller (moveFeed)
    /// re-inserts at the new destination.
    private static func removeFeedFromTree(
        feedID: Feed.ID,
        in folder: OPMLImporter.Folder
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        let before = copy.feeds.count
        copy.feeds.removeAll { $0.id == feedID }
        var didRemove = copy.feeds.count != before
        var newSubfolders: [OPMLImporter.Folder] = []
        for sub in copy.subfolders {
            let (updatedSub, subDid) = removeFeedFromTree(feedID: feedID, in: sub)
            if subDid { didRemove = true }
            newSubfolders.append(updatedSub)
        }
        copy.subfolders = newSubfolders
        return (copy, didRemove)
    }

    /// Pure recursive insert. Walks subfolders; appends to the
    /// first one with matching name. When folderName is nil,
    /// appends to root.feeds.
    private static func insertFeed(
        _ feed: Feed,
        intoFolderNamed folderName: String?,
        in folder: OPMLImporter.Folder
    ) -> OPMLImporter.Folder {
        var copy = folder
        guard let folderName else {
            copy.feeds.append(feed)
            return copy
        }
        if let idx = copy.subfolders.firstIndex(where: { $0.name == folderName }) {
            copy.subfolders[idx].feeds.append(feed)
            return copy
        }
        copy.subfolders = copy.subfolders.map {
            insertFeed(feed, intoFolderNamed: folderName, in: $0)
        }
        return copy
    }

    /// Pure recursive helper for removeFolder. Returns
    /// (updatedFolder, didRemove). At each level, if a direct
    /// subfolder matches, its feeds + subfolders bubble up
    /// into the current folder's lists; otherwise recurses
    /// into each subfolder. First match wins (no duplicate
    /// names within a level — see addFolder/renameFolder
    /// invariants).
    private static func removeFolderRecursively(
        in folder: OPMLImporter.Folder,
        name: String
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        if let matchIndex = copy.subfolders.firstIndex(where: { $0.name == name }) {
            let match = copy.subfolders.remove(at: matchIndex)
            copy.feeds.append(contentsOf: match.feeds)
            copy.subfolders.append(contentsOf: match.subfolders)
            return (copy, true)
        }
        var didRemove = false
        var newSubfolders: [OPMLImporter.Folder] = []
        for sub in copy.subfolders {
            let (updatedSub, subDid) = removeFolderRecursively(in: sub, name: name)
            if subDid { didRemove = true }
            newSubfolders.append(updatedSub)
        }
        copy.subfolders = newSubfolders
        return (copy, didRemove)
    }

    /// Pure recursive helper. Returns (updatedFolder, didRename).
    /// Walks every subfolder; at each level, checks for a
    /// sibling name conflict before applying the rename so the
    /// caller's no-duplicates invariant is preserved tree-wide.
    private static func renameFolderRecursively(
        in folder: OPMLImporter.Folder,
        from oldName: String,
        to newName: String
    ) -> (OPMLImporter.Folder, Bool) {
        var copy = folder
        // Conflict check at this level: refuse if a sibling
        // already owns the new name (and isn't the rename target
        // itself).
        let siblingHasNewName = copy.subfolders.contains { $0.name == newName }
        var didRename = false
        var newSubfolders: [OPMLImporter.Folder] = []
        for var sub in copy.subfolders {
            if sub.name == oldName {
                guard !siblingHasNewName else {
                    newSubfolders.append(sub) // no rename — conflict
                    continue
                }
                sub.name = newName
                didRename = true
                newSubfolders.append(sub)
            } else {
                let (renamed, subDid) = renameFolderRecursively(
                    in: sub, from: oldName, to: newName
                )
                if subDid { didRename = true }
                newSubfolders.append(renamed)
            }
        }
        copy.subfolders = newSubfolders
        return (copy, didRename)
    }

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
            // Same SQLite-tail sweep as markFeedAsRead: rows
            // beyond articlesPerFeedLimit (100) but still inside
            // articleHistoryLimit (500) would survive the in-
            // memory pass and resurface as unread via the All
            // Unread smart feed, contradicting "Mark Folder
            // Read". Upstream NetNewsWire's account-store walk
            // covers every persisted row per feed in the folder.
            if let articleStore,
               let storedRows = try? articleStore.fetch(forFeed: feed.id) {
                for row in storedRows where !readArticleIDs.contains(row.uniqueID) {
                    markRead(id: row.uniqueID)
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
        // Folder view wins over default active-feed (but loses
        // to smart feed + search since those have explicit
        // cross-feed scope). The folder branch reads the
        // already-computed itemsInFolder helper (#158). Search
        // INSIDE a folder narrows the folder pool — without
        // this, search in folder view escaped to the full
        // cross-feed pool because the smart-feed/search branch
        // didn't know about the folder context.
        let pool: [RSSItem]
        if let folderName = selectedFolderName, selectedSmartFeed == nil {
            pool = itemsInFolder(named: folderName)
        } else if selectedSmartFeed != nil || searchActive {
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
                    let cutoff = Self.todayCutoff()
                    let allArticles = articles + feedCaches.values.flatMap(\.articles)
                    let todayIDs = Set(allArticles.compactMap { article -> String? in
                        guard let published = article.datePublished, published >= cutoff else {
                            return nil
                        }
                        return article.uniqueID
                    })
                    pool = combined.filter { todayIDs.contains($0.id) }
                case .allUnread:
                    // Sticky-visible-IDs keep just-read articles
                    // in view for the current session so opening
                    // an article in All Unread doesn't make the
                    // row vanish mid-read. Cleared on view change.
                    var unreadPool = combined.filter {
                        !readArticleIDs.contains($0.id) ||
                            sessionStickyVisibleIDs.contains($0.id)
                    }
                    // Union with SQLite-only unread so older
                    // articles that aged out of the per-feed
                    // cache (articlesPerFeedLimit) still surface.
                    // Cached pool wins on dedupe (freshest fields);
                    // stored fills in the long tail.
                    let visibleIDs = Set(unreadPool.map(\.id))
                    for storedItem in storedUnreadItems()
                        where !visibleIDs.contains(storedItem.id) {
                        unreadPool.append(storedItem)
                    }
                    pool = unreadPool
                case .starred:
                    // Cache-only would miss old-but-still-starred
                    // articles that have aged out of the per-feed
                    // articlesPerFeedLimit window. Pull all starred
                    // rows from the store too and union them in,
                    // deduped by id. Mirrors upstream NetNewsWire's
                    // Starred smart feed that spans full history.
                    var starredPool = combined.filter { starredArticleIDs.contains($0.id) }
                    let visibleIDs = Set(starredPool.map(\.id))
                    for storedItem in storedStarredItems()
                        where !visibleIDs.contains(storedItem.id) {
                        starredPool.append(storedItem)
                    }
                    pool = starredPool
                }
            } else {
                pool = combined
            }
        } else {
            pool = items
        }
        if searchActive {
            // Case- AND diacritic-insensitive so "cafe" matches
            // "café" and "Renoir" matches "renoir". range(of:
            // options:) on raw strings beats lowercased()+
            // contains() because the comparison is locale-
            // aware Unicode collation rather than ASCII case
            // folding.
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            return applySortOrder(applyHideRead(pool.filter { item in
                if item.title.range(of: trimmed, options: options) != nil { return true }
                if item.plainTextBody.range(of: trimmed, options: options) != nil { return true }
                // Authors live on the parallel Article record (not
                // on RSSItem). Reverse-lookup via authorLine so
                // multi-author "Alice, Bob" matches either name.
                if let author = authorLine(forItemID: item.id),
                   author.range(of: trimmed, options: options) != nil { return true }
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
        // Same sticky-visible carve-out as the All Unread branch
        // in filteredItems so the active-feed Hide Read flow
        // doesn't make rows vanish mid-read either.
        return pool.filter {
            !readArticleIDs.contains($0.id) ||
                sessionStickyVisibleIDs.contains($0.id)
        }
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
            case .today:
                // Same Hide-Read split as the folder branch:
                // if Today's pool genuinely has items but they
                // all got filtered out by Hide Read, surface the
                // toggle hint rather than misleadingly say
                // "nothing published since midnight" (which is
                // false — there WERE today's articles, just
                // already read). Count via the cross-feed today
                // helper rather than walking the pool again.
                if hideReadArticles && todayItemCountIgnoringReadState() > 0 {
                    return (
                        "All Today's Read",
                        "Toggle \u{201C}Show Read\u{201D} to see today's articles you have already read."
                    )
                }
                return ("No Articles Today", "Nothing published since midnight.")
            case .allUnread:
                // Distinguish "user fully drained their inbox"
                // from "user just hasn't fetched anything yet"
                // — the same empty pool came from very
                // different states. Upstream NetNewsWire shows
                // matching distinct messages; without this,
                // a fresh install said "All Read" which read
                // as "nothing to do" instead of "click
                // Refresh All".
                let hasCachedArticles = !items.isEmpty
                    || feedCaches.values.contains(where: { !$0.items.isEmpty })
                if hasCachedArticles {
                    return ("All Read", "Every article in every feed is marked read.")
                } else {
                    return (
                        "No Articles Yet",
                        "Subscribe to a feed and Refresh All to load articles."
                    )
                }
            case .starred:
                return ("No Starred Articles", "Star an article to add it here.")
            }
        }
        if let folder = selectedFolderName {
            // Differentiate "folder has items but all read AND
            // Hide Read is on" from "folder has no items at all".
            // The first is a fixable user-toggle state; the
            // second is a publisher-state issue. Showing the
            // same generic message for both made the toggle
            // affordance unreachable from the empty view.
            if hideReadArticles && !itemsInFolder(named: folder).isEmpty {
                return (
                    "All Read in \(folder)",
                    "Toggle \u{201C}Show Read\u{201D} to see articles you have already read."
                )
            }
            // Empty folder (no feeds at all in it) is a user-
            // organization state, not a publisher state — the
            // "refresh or wait" hint is wrong (no feeds to
            // refresh). Surface a useful next step instead:
            // drop the feeds back to root via Delete folder, or
            // move feeds in via the inspector's Move to picker.
            if let resolved = Self.findFolder(named: folder, in: subscriptionRoot),
               resolved.allFeeds.isEmpty {
                return (
                    "Empty Folder",
                    "Move feeds into \u{201C}\(folder)\u{201D} from a feed's inspector, or delete the folder."
                )
            }
            return (
                "No Articles in \(folder)",
                "Feeds inside this folder have no articles to show — refresh or wait for new posts."
            )
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
        // Folder view is cross-feed too — label rows with their
        // source feed so the user can tell which feed each
        // article came from inside the folder pool.
        let crossFeed = selectedSmartFeed != nil
            || selectedFolderName != nil
            || !trimmed.isEmpty
        guard crossFeed else {
            return filteredItems.map { item in
                RSSArticleRow(
                    item: item,
                    feedTitle: nil,
                    authorLine: authorLine(forItemID: item.id),
                    friendlyDate: friendlyDateString(forItemID: item.id)
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
                authorLine: authorLine(forItemID: item.id),
                friendlyDate: friendlyDateString(forItemID: item.id)
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

    /// Unread count restricted to the CURRENT VIEW's pool —
    /// active-feed items in default view, the smart-feed /
    /// folder cross-feed pool otherwise. Used by the footer
    /// "All Read" button's disabled state so a smart-feed user
    /// with unread items in the visible pool can mark them even
    /// if the active feed itself is all-read. unreadCount (above)
    /// stays active-feed-scoped for the sidebar badge.
    var filteredUnreadCount: Int {
        filteredItems.reduce(0) { acc, item in
            acc + (readArticleIDs.contains(item.id) ? 0 : 1)
        }
    }

    /// All RSSItems from feeds inside the named folder
    /// (recursive into subfolders via allFeeds), deduped by id.
    /// Walks each feed's cache + the active feed's items for
    /// the matching URLs. Empty when the folder name isn't
    /// in subscriptionRoot or has no feeds with cached items.
    ///
    /// Future iteration will pair this with a selectedFolderName
    /// state for a "folder-as-smart-feed" view; for now it's a
    /// building block + a way to compute folder-scoped counts
    /// (markFolderAsRead already walks the folder a similar way).
    func itemsInFolder(named folderName: String) -> [RSSItem] {
        guard let folder = Self.findFolder(named: folderName, in: subscriptionRoot) else {
            return []
        }
        let feedURLs = Set(folder.allFeeds.map(\.url))
        var seen = Set<String>()
        var combined: [RSSItem] = []
        // Active feed first (its items are freshest).
        if let activeURL = currentFeedURL, feedURLs.contains(activeURL) {
            for item in items where seen.insert(item.id).inserted {
                combined.append(item)
            }
        }
        // Cached feeds that belong to this folder.
        for url in feedURLs {
            guard let cache = feedCaches[url] else { continue }
            for item in cache.items where seen.insert(item.id).inserted {
                combined.append(item)
            }
        }
        return combined
    }

    /// Recursively search subscriptionRoot for a folder with
    /// the given name. First match wins (folder-name uniqueness
    /// is enforced at addFolder/renameFolder per #86/#87).
    nonisolated private static func findFolder(named name: String, in folder: OPMLImporter.Folder) -> OPMLImporter.Folder? {
        if folder.name == name { return folder }
        for sub in folder.subfolders {
            if let found = findFolder(named: name, in: sub) {
                return found
            }
        }
        return nil
    }

    /// Total items across every loaded feed, deduped by id.
    /// Used as the denominator in smart-feed status text where
    /// the matching pool spans every feed, not just the active
    /// selection. Active feed's items contribute first; cached
    /// feeds add anything not already counted.
    /// Aggregate per-feed-health summary for the sidebar footer.
    /// Surfaces "N feeds failing" + "N skipped" so the user can
    /// see at a glance whether something needs attention without
    /// opening every inspector. Empty when every feed is happy.
    /// "Failing" = has a current error (might still be retried).
    /// "Skipped" = back-off threshold crossed, refreshAll is
    /// ignoring it until the user explicitly retries.
    func feedHealthSummary() -> String {
        let subscriptionIDs = Set(subscribedFeeds.map(\.id))
        let failing = feedErrors.keys.filter { subscriptionIDs.contains($0) }.count
        let skipped = feedFailureCount.filter {
            subscriptionIDs.contains($0.key) && $0.value >= Self.feedFailureSkipThreshold
        }.count
        if failing == 0 && skipped == 0 { return "" }
        var parts: [String] = []
        if failing > 0 {
            parts.append("\(failing) failing")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped")
        }
        return parts.joined(separator: " · ")
    }

    var crossFeedItemsCount: Int {
        var seen = Set<String>(items.map(\.id))
        for (_, cache) in feedCaches {
            for item in cache.items {
                seen.insert(item.id)
            }
        }
        return seen.count
    }

    private func updateSelectedItem() {
        let item = resolveItem(forID: selectedID)
        if selectedItem != item {
            selectedItem = item
        }
        let detail = item.map(RSSArticleDetail.init(item:))
        if selectedDetail != detail {
            selectedDetail = detail
        }
    }

    /// Resolve an item by id across every place it might live —
    /// active items + every cached feed's items + the SQLite-
    /// only stored-starred / stored-unread pools surfaced in
    /// smart-feed views since #113/#114. Without this fall-
    /// through, clicking a stored-only row in the Starred /
    /// All Unread smart feed showed a blank detail pane (items
    /// search missed, selectedDetail stayed nil).
    private func resolveItem(forID id: String?) -> RSSItem? {
        guard let id else { return nil }
        if let inItems = items.first(where: { $0.id == id }) {
            return inItems
        }
        for (_, cache) in feedCaches {
            if let cached = cache.items.first(where: { $0.id == id }) {
                return cached
            }
        }
        if let starred = storedStarredItems().first(where: { $0.id == id }) {
            return starred
        }
        if let unread = storedUnreadItems().first(where: { $0.id == id }) {
            return unread
        }
        return nil
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
        } else if let error, items.isEmpty {
            // Error wins ONLY when there's nothing else to show.
            // If a prior fetch left items in the timeline, hide
            // the error from status text (the sidebar's inline
            // error banner still surfaces it) so the user
            // doesn't think the visible articles are bogus.
            nextStatusText = "Error: \(error)"
        } else if error != nil {
            // Error AND items: render count first; appended note
            // tells the user the LATEST fetch failed but the
            // existing articles are still good.
            let unread = unreadCount
            let base = unread == 0
                ? "\(items.count) items"
                : "\(unread) unread · \(items.count) items"
            nextStatusText = "\(base) · refresh failed"
        } else if let smart = selectedSmartFeed {
            // Smart-feed view spans every fetched feed, not just
            // the active selection — the denominator must match.
            // Using items.count here would lie ("All Unread: 5
            // of 10" when the cross-feed pool actually has 100).
            let matching = filteredItems.count
            let suffix = searchActive ? " (search)" : ""
            nextStatusText = "\(smart.displayName): \(matching) of \(crossFeedItemsCount)\(suffix)"
        } else if let folder = selectedFolderName {
            // Folder view — counts scope to the folder pool, not
            // the active feed (which may be entirely outside).
            let folderItems = itemsInFolder(named: folder)
            let folderUnread = folderItems.reduce(0) { acc, item in
                acc + (readArticleIDs.contains(item.id) ? 0 : 1)
            }
            let matching = filteredItems.count
            let suffix = searchActive ? " (search)" : ""
            if matching != folderItems.count {
                // Search narrowed inside the folder.
                nextStatusText = "Folder \(folder): \(matching) of \(folderItems.count)\(suffix)"
            } else if folderUnread == 0 {
                nextStatusText = "Folder \(folder): \(folderItems.count) items"
            } else {
                nextStatusText = "Folder \(folder): \(folderUnread) unread · \(folderItems.count) items"
            }
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

    /// Friendly HTTP error string for the common feed-fetch
    /// failure codes. Falls through to a generic "HTTP <code>"
    /// for codes we don't special-case. Returned strings are
    /// short enough to fit the sidebar warning-glyph tooltip
    /// without truncation.
    /// Increment a feed's consecutive-failure counter. Used by
    /// the fetch + fetchIntoCache failure paths so the back-off
    /// in refreshAllFeeds kicks in after persistent failures.
    /// Exposed (not private) so tests can pin the counter
    /// state without driving real network traffic.
    func incrementFailureCount(forFeed urlString: String) {
        feedFailureCount[urlString, default: 0] += 1
        feedLastErrorAt[urlString] = Date()
    }

    /// Reset a feed's consecutive-failure counter to zero. Used
    /// by the success paths so the next failure starts a fresh
    /// count. Removing the entry rather than setting to 0 keeps
    /// the dict small for big subscription lists.
    func resetFailureCount(forFeed urlString: String) {
        feedFailureCount.removeValue(forKey: urlString)
        feedLastErrorAt.removeValue(forKey: urlString)
    }

    /// Reset every feed's failure counter so Refresh All stops
    /// skipping them. Use case: a publisher migrated their feed
    /// URL or fixed a server outage, and the user wants Refresh
    /// All to re-try every feed in one click instead of opening
    /// the inspector for each one. Returns the number of feeds
    /// whose counter actually got dropped. Errors stay set so
    /// the sidebar warning glyphs persist until next fetch
    /// success — only the back-off is cleared.
    @discardableResult
    func resetAllFailureCounts() -> Int {
        let count = feedFailureCount.count
        feedFailureCount.removeAll()
        feedLastErrorAt.removeAll()
        return count
    }

    /// Friendly error string for thrown Errors. Plain `"\(error)"`
    /// interpolation surfaces the NSError "Error Domain=...
    /// UserInfo={...}" form which is unreadable in the inspector
    /// + sidebar tooltip.
    ///
    /// URLError gets a code-based readable message (same set
    /// upstream NetNewsWire uses for its sidebar warning
    /// tooltip) since localizedDescription on swift-corelibs-
    /// foundation is unreliable for that family. Other NSError
    /// fall back to localizedDescription when it's meaningful
    /// (not the "Error Domain=" debug form). Last-resort
    /// fall-through is "\(error)" which at least beats nothing.
    nonisolated static func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlErrorDescription(urlError)
        }
        let nsError = error as NSError
        let described = nsError.localizedDescription
        if !described.isEmpty,
           !described.hasPrefix("Error Domain=") {
            return described
        }
        return "\(error)"
    }

    nonisolated private static func urlErrorDescription(_ urlError: URLError) -> String {
        switch urlError.code {
        case .cannotFindHost:           return "Cannot find host"
        case .cannotConnectToHost:      return "Cannot connect to host"
        case .timedOut:                 return "Connection timed out"
        case .notConnectedToInternet:   return "Not connected to the internet"
        case .networkConnectionLost:    return "Network connection lost"
        case .dnsLookupFailed:          return "DNS lookup failed"
        case .badServerResponse:        return "Bad server response"
        case .badURL:                   return "Invalid URL"
        case .unsupportedURL:           return "Unsupported URL scheme"
        case .userCancelledAuthentication: return "Authentication cancelled"
        case .userAuthenticationRequired:  return "Authentication required"
        case .serverCertificateUntrusted:  return "Server certificate untrusted"
        case .secureConnectionFailed:      return "Secure connection failed"
        default:                        return "Network error (\(urlError.code.rawValue))"
        }
    }

    /// Convert a [String: String] (the on-disk shape used by
    /// PersistenceStore.conditionalGetInfo.json) back into an
    /// HTTPConditionalGetInfo struct ready to add request
    /// headers. Returns nil when the dict has neither field
    /// (HTTPConditionalGetInfo's init? returns nil when both
    /// lastModified and etag are nil).
    nonisolated static func makeConditionalGetInfo(_ dict: [String: String]?) -> HTTPConditionalGetInfo? {
        guard let dict else { return nil }
        return HTTPConditionalGetInfo(
            lastModified: dict["lastModified"],
            etag: dict["etag"]
        )
    }

    /// Reverse of makeConditionalGetInfo — flatten to the
    /// dict-of-strings shape for JSON persistence. Returns nil
    /// when info itself is nil so the caller can skip assignment
    /// (avoids storing empty {} entries per feed).
    nonisolated static func dictFromConditionalGetInfo(_ info: HTTPConditionalGetInfo?) -> [String: String]? {
        guard let info else { return nil }
        var dict: [String: String] = [:]
        if let lm = info.lastModified { dict["lastModified"] = lm }
        if let et = info.etag { dict["etag"] = et }
        return dict.isEmpty ? nil : dict
    }

    nonisolated static func httpErrorMessage(forStatus code: Int) -> String {
        switch code {
        case 401: return "Unauthorized (401)"
        case 403: return "Forbidden (403)"
        case 404: return "Feed not found (404)"
        case 410: return "Feed gone (410)"
        case 429: return "Rate limited (429)"
        case 500: return "Server error (500)"
        case 502: return "Bad gateway (502)"
        case 503: return "Service unavailable (503)"
        case 504: return "Gateway timeout (504)"
        case 400...499: return "Client error (\(code))"
        case 500...599: return "Server error (\(code))"
        default: return "HTTP \(code)"
        }
    }

    private func setFeedTitle(_ newTitle: String?) {
        if feedTitle != newTitle {
            feedTitle = newTitle
        }
    }

    /// Rename a subscribed feed's title when the parsed RSS
    /// <title> is meaningful AND the user hasn't manually
    /// renamed it (sidebar title still equals the feed URL).
    /// Skipped for empty/whitespace parsed titles so a feed
    /// without a <title> element keeps the URL fallback. Routes
    /// through the subscribedFeeds setter so persistence picks
    /// up the change.
    func updateSubscribedFeedTitleFromParse(
        urlString: String, parsedTitle: String?
    ) {
        let trimmed = parsedTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        guard let idx = subscribedFeeds.firstIndex(where: { $0.url == urlString }) else {
            return
        }
        let current = subscribedFeeds[idx]
        // Skip if title is already this. Skip if title has been
        // user-edited (no longer equals the URL).
        guard current.title != trimmed else { return }
        guard current.title == current.url else { return }
        subscribedFeeds[idx] = Feed(title: trimmed, url: current.url)
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

    /// In-flight fetch refcount. With #139's concurrent
    /// refreshAllFeeds, multiple fetchIntoCache calls can be
    /// alive at once — the bool-flip-on-each-entry setLoading
    /// pattern raced (first finisher flipped to false while
    /// others were still in flight). Track a refcount instead
    /// and derive isLoading = refcount > 0. All fetch paths
    /// should route through pushLoading / popLoading.
    private var loadingRefcount: Int = 0

    /// Per-URL in-flight tracker. Lets refresh(urlString:) skip
    /// only when THIS url is already loading, instead of when
    /// ANY fetch is loading. Without this, refreshAllFeeds'
    /// inactive-feed batch (which holds isLoading=true for the
    /// duration) blocks the user from manually refreshing the
    /// active feed.
    private var inFlightURLs: Set<String> = []

    /// True when this URL currently has a fetch / fetchIntoCache
    /// in flight. Exposed so refresh() can guard per-URL
    /// instead of via the global isLoading.
    func isLoading(forURL urlString: String) -> Bool {
        inFlightURLs.contains(urlString)
    }

    func pushLoading() {
        pushLoading(forURL: nil)
    }

    /// Per-URL push that also tracks the URL in inFlightURLs.
    /// Calls without a URL (nil) only bump the refcount —
    /// used by helpers like FeedFinder/OPML import that don't
    /// map to a single feed URL.
    func pushLoading(forURL urlString: String?) {
        if let urlString {
            inFlightURLs.insert(urlString)
        }
        loadingRefcount += 1
        if loadingRefcount == 1 {
            setLoading(true)
        }
    }

    func popLoading() {
        popLoading(forURL: nil)
    }

    func popLoading(forURL urlString: String?) {
        if let urlString {
            inFlightURLs.remove(urlString)
        }
        loadingRefcount = max(0, loadingRefcount - 1)
        if loadingRefcount == 0 {
            setLoading(false)
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
        // Dedup by uniqueID — broken feeds occasionally ship
        // the same id on multiple items. First occurrence wins
        // (sorted newest-first, so the freshest copy stays).
        // Without this, ForEach hits duplicate-id warnings and
        // SwiftUI's diffing gets confused.
        var seen = Set<String>()
        let dedupedItems = sortedItems.filter { seen.insert($0.uniqueID).inserted }
        let rssItems = dedupedItems.map(adaptParsedItem(_:))
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
        // Many RSS feeds (Wordpress-based especially) ship titles
        // with literal HTML entities ("AT&amp;T announces&hellip;").
        // Decode through HTMLEntities so the timeline / detail
        // header reads naturally rather than showing source-form
        // entities.
        let rawTitle = (item.title?.isEmpty == false) ? item.title! : "Untitled"
        let title = HTMLEntities.decode(rawTitle)
        let body = item.contentHTML ?? item.contentText ?? item.summary
        // Prefer externalURL (JSON Feed's external_url — the
        // linkblog target) over url (which points to the
        // linkblog's own post page). For most feeds these are
        // the same; for Daring Fireball / Hacker News / Reddit
        // style "this is a link to X" posts, externalURL is the
        // actual destination the user wants when they tap
        // "Open in browser". Falls back to url when external
        // URL is nil (the common case).
        let link = (item.externalURL?.isEmpty == false) ? item.externalURL : item.url
        return RSSItem(
            id: item.uniqueID,
            title: title,
            link: link,
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
        // Same dedup-by-uniqueID pass as parseUpstream so the
        // parallel articles array doesn't keep duplicates that
        // the items array drops.
        var seen = Set<String>()
        let deduped = sorted.filter { seen.insert($0.uniqueID).inserted }
        let now = Date()
        return deduped.map { parsed in
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
                // Decode at write time so SQLite stores the
                // user-visible form. Read-side decode helpers
                // (hydration, rssItem(from:)) are idempotent so
                // the existing decoded-then-decoded chain is safe.
                title: parsed.title.map(HTMLEntities.decode),
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
    /// Drop entire <script>...</script> and <style>...</style>
    /// BLOCKS (tag + content). Many feeds (ad-supported,
    /// analytics-instrumented) ship tracking JS / inline CSS
    /// in descriptionHTML. The default `<[^>]+>` tag-only
    /// strip would leak the script source code into:
    ///   - plain-text body / preview / search (#119)
    ///   - detail-pane paragraphs (#123)
    ///   - inline-link / inline-image extraction (#124 — a
    ///     literal `<a>` string inside a script body would
    ///     otherwise show up as a clickable link)
    /// All four call sites delegate here so the regex stays
    /// in one place and any future tweak applies uniformly.
    func htmlWithoutScriptStyleBlocks() -> String {
        replacingOccurrences(
            of: "<(script|style)\\b[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    func stripBasicHTML() -> String {
        let withoutBlocks = htmlWithoutScriptStyleBlocks()
        let withoutTags = withoutBlocks.replacingOccurrences(
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
    func htmlInlineLinks(baseURL: URL? = nil) -> [InlineLink] {
        guard !isEmpty else { return [] }
        let pattern = #"<a\s[^>]*href\s*=\s*(?:\"([^\"]*)\"|'([^']*)')[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return [] }
        // Strip script/style blocks BEFORE the link-extraction
        // regex so a literal "<a href=...>" inside a tracker
        // script body doesn't surface as a clickable link in
        // the detail-pane "Links" footer.
        let source = htmlWithoutScriptStyleBlocks()
        let nsself = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsself.length))
        var out: [InlineLink] = []
        for m in matches {
            let hrefRange = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            guard hrefRange.location != NSNotFound else { continue }
            let rawHref = nsself.substring(with: hrefRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawHref.isEmpty else { continue }
            // Resolve relative paths against the article URL so
            // "/article/123" becomes "https://site.com/article/
            // 123". Falls through to the raw href when no base
            // (or resolution returns nil — e.g. already-absolute).
            let href = resolveURL(rawHref, against: baseURL)
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

    /// Resolve a possibly-relative URL string against a base URL.
    /// Returns the absolute form when resolution succeeds; falls
    /// through to the raw string otherwise (already-absolute,
    /// no base provided, mailto:/tel:/etc).
    private func resolveURL(_ raw: String, against base: URL?) -> String {
        guard let base else { return raw }
        // Already absolute? URL(string:) returns non-nil + non-
        // empty scheme.
        if let probe = URL(string: raw), probe.scheme != nil {
            return raw
        }
        guard let resolved = URL(string: raw, relativeTo: base) else {
            return raw
        }
        return resolved.absoluteURL.absoluteString
    }

    /// Extract `<img src>` tags from an HTML body. Returns
    /// InlineImages in source order. Empty when no images
    /// found. Handles attribute orders flexibly — src can come
    /// before or after alt. Skips data: URIs (inline encoded
    /// images aren't useful for the detail-view URL list).
    func htmlInlineImages(baseURL: URL? = nil) -> [InlineImage] {
        guard !isEmpty else { return [] }
        // Pull every <img ...> tag, then pluck src + alt from
        // each attribute string separately so attribute order
        // doesn't matter.
        let tagPattern = #"<img\b[^>]*>"#
        guard let tagRegex = try? NSRegularExpression(
            pattern: tagPattern,
            options: [.caseInsensitive]
        ) else { return [] }
        // Same script/style strip as htmlInlineLinks so tracker
        // pixel <img> tags inside <noscript> wrappers (which
        // sit inside <script> bodies in some ad inserts) don't
        // get extracted.
        let source = htmlWithoutScriptStyleBlocks()
        let nsself = source as NSString
        let tagMatches = tagRegex.matches(
            in: source, range: NSRange(location: 0, length: nsself.length)
        )
        var out: [InlineImage] = []
        for tm in tagMatches {
            let tagText = nsself.substring(with: tm.range)
            let rawSrc = Self.attribute("src", from: tagText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawSrc.isEmpty, !rawSrc.hasPrefix("data:") else { continue }
            let src = resolveURL(rawSrc, against: baseURL)
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
        let withoutBlocks = htmlWithoutScriptStyleBlocks()
        // Insert a marker character at every block-level boundary,
        // then split on it. The marker is `\u{2029}` (PARAGRAPH
        // SEPARATOR) so it can't collide with any feed content.
        let blockTags = "p|br|hr|h[1-6]|li|blockquote|div|tr"
        let pattern = "</?(?:\(blockTags))(?:\\s[^>]*)?/?\\s*>"
        var work = withoutBlocks.replacingOccurrences(
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
