import Foundation
import QuillFoundation
import QuillUI

enum QuillIceCubesProfileLabels {
    static let bareTimelineTitle = "IceCubes Public Timeline"
}

/// Mastodon public-timeline shell. Mirrors the upstream
/// IceCubes view shape so a future port of larger
/// Dimillian/IceCubesApp views compiles unmodified against
/// QuillUI's compatibility layer.
///
/// The Mastodon API surface (`Status`, `Account`, `HTMLString`,
/// `Timelines`, `MastodonClient`) is re-implemented locally in
/// `IceCubesAPI.swift` since the upstream `Models` and
/// `NetworkClient` packages pin
/// `platforms: [.iOS(.v18), .visionOS(.v1)]` and don't resolve
/// on macOS or Linux.
///
/// The type is main-actor isolated, while the `View.body`
/// witness remains nonisolated so SwiftOpenUI can instantiate it
/// from `WindowGroup` on Swift 6.2 Linux without tripping
/// isolated-conformance diagnostics.
@MainActor
public struct QuillIceCubesContentView: View {
    @State private var client = MastodonClient(server: "mastodon.social", version: .v1, oauthToken: nil)
    @State private var timelineRows: [IceCubesTimelineRow] = []
    @State private var selectedRowID: IceCubesTimelineRow.ID?
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var didStartTimelineLoad = false
    private let initialSelectionEnvironment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.initialSelectionEnvironment = environment
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated { profiledTimeline }
    }

    @ViewBuilder
    private var profiledTimeline: some View {
        // Profile experiments. Each env var swaps the body to a
        // simpler shape, isolating where the IceCubes CPU peg
        // lives on SwiftOpenUI's GTK4 backend. Production stays
        // matched to upstream Dimillian/IceCubesApp.
        //
        //   QUILLUI_PROFILE_BARE=1         body returns a single Text.
        //                                  Result (83369b4): 2.8/2.8 —
        //                                  fixture-app baseline. Spin
        //                                  is NOT in GTK host or
        //                                  @State; it's in the view tree.
        //   QUILLUI_PROFILE_PLAIN_ROW=1    Keep List + ForEach but use
        //                                  plain Text rows over fixture
        //                                  data. Bisects whether the
        //                                  cost is in List iteration or
        //                                  in statusRow's rich content.
        //   QUILLUI_PROFILE_STORED_PROPS=1 Full statusRow layout but
        //                                  Text values read stored
        //                                  properties (username,
        //                                  htmlValue) — no computed
        //                                  cachedDisplayName / asRawText
        //                                  chain. Bisects whether the
        //                                  cost is the chain itself.
        //   QUILLUI_PROFILE_FLAT=1         Skip NavigationStack only.
        //                                  Result (1807e71): only ~5 pp
        //                                  drop. NavigationStack is NOT
        //                                  the spinner.
        let env = ProcessInfo.processInfo.environment
        if env["QUILLUI_PROFILE_BARE"] == "1" {
            Text(QuillIceCubesProfileLabels.bareTimelineTitle)
        } else if env["QUILLUI_PROFILE_PLAIN_ROW"] == "1" {
            List {
                ForEach(QuillIceCubesProfileFixtures.rows) { row in
                    Text(row.id)
                }
            }
        } else if env["QUILLUI_PROFILE_STORED_PROPS"] == "1" {
            // Same shape as statusRow but Text values read STORED
            // properties (status.account.username,
            // status.content.htmlValue) instead of the computed
            // cachedDisplayName.asRawText / content.asRawText chains.
            // If CPU drops to fixture baseline, the computed chain
            // is the spinner. If CPU climbs, the cost is elsewhere
            // (likely SwiftOpenUI's render-loop diff handling
            // computed-property dependencies).
            List {
                ForEach(QuillIceCubesProfileFixtures.statuses) { status in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            avatarView(for: status.account.avatar)
                            VStack(alignment: .leading) {
                                Text(status.account.username).font(.headline)
                                Text("@\(status.account.acct)").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        Text(status.content.htmlValue).font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if env["QUILLUI_PROFILE_LITERAL_ROW"] == "1" {
            // Same shape as statusRow (HStack + Circle + nested
            // VStack + 3 Texts + .padding) but all Text values
            // are literal strings — no `.asRawText` /
            // `.cachedDisplayName.asRawText` computed-property
            // reads. If CPU stays at fixture baseline, the
            // computed properties were getting hammered in the
            // GTK4 render loop. If CPU climbs, the layout
            // structure itself is the spinner.
            List {
                ForEach(QuillIceCubesProfileFixtures.rows) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle().fill(Color.gray).frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text("Display Name").font(.headline)
                                Text("@handle").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                        Text("Status body literal text.").font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        } else if env["QUILLUI_PROFILE_FLAT"] == "1" {
            timelineContent
        } else {
            timelineContent
        }
    }

    @ViewBuilder
    private var timelineContent: some View {
        // IceCubes' real shape: SwiftUI's `NavigationSplitView` (Apple's
        // adaptive sidebar API, mirrored in SwiftOpenUI) — a navigation
        // sidebar, the timeline as the main column, and the focused post in
        // the detail column. This is the same Apple source the Mac/iPad app
        // renders, not a hand-rolled HStack split.
        NavigationSplitView {
            navigationSidebar
        } content: {
            timelineColumn
        } detail: {
            timelineDetail
        }
        // `.onAppear` (not `.task`) avoids `#SendableClosureCaptures` on the
        // non-Sendable view; the load is guarded so GTK's repeated onAppear
        // fires it once. `QUILLUI_DISABLE_FETCH=1` seeds fixtures + skips
        // URLSession for the deterministic Linux profile/smoke runs.
        .onAppear { startTimelineLoadIfNeeded() }
    }

    /// IceCubes' navigation sidebar: the timeline/section tabs, rendered with
    /// SwiftUI `Label(_, systemImage:)` (Apple's API) the same way the Mac/iPad
    /// app's sidebar does.
    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("IceCubes")
                .font(.title2)
                .bold()
                .padding(16)
            navItem("Home", systemImage: "house")
            navItem("Local", systemImage: "person.2")
            navItem("Federated", systemImage: "globe")
            navItem("Notifications", systemImage: "bell")
            navItem("Explore", systemImage: "magnifyingglass")
            navItem("Settings", systemImage: "gearshape")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func navItem(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
    }

    /// The Home timeline column: the public-timeline rows, selectable into the
    /// detail column.
    private var timelineColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home")
                    .font(.title2)
                    .bold()
                Text("Public timeline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            if isLoading && timelineRows.isEmpty {
                loadingPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, timelineRows.isEmpty {
                sidebarError(errorMessage)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(timelineRows) { row in
                            Button {
                                selectedRowID = row.id
                            } label: {
                                statusRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QuillDesktopChromeStyle.detailBackground)
    }

    private func sidebarError(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline unavailable")
                .font(.headline)
            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.red)
            Button("Retry") {
                Task { await fetchTimeline() }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var timelineDetail: some View {
        Group {
            if isLoading && timelineRows.isEmpty {
                loadingPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let row = selectedRow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            avatarView(for: row.avatar, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.displayNameText)
                                    .font(.title3)
                                    .bold()
                                Text(row.handleText)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                if !row.timeText.isEmpty {
                                    Text(row.timeText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }

                        styledContent(row)
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        statusStatsLine(row)
                        statusActionBar(row)

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeline unavailable")
                        .font(.title2)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select a timeline item")
                        .font(.title2)
                    Text("The public timeline will appear here after loading.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(QuillDesktopChromeStyle.detailBackground)
    }

    /// IceCubes' status-detail engagement summary ("12 Boosts · 28
    /// Favorites") — boosts + favorites only, matching the text stats
    /// row IceCubes shows above its action buttons. Hidden when both
    /// are zero.
    @ViewBuilder
    private func statusStatsLine(_ row: IceCubesTimelineRow) -> some View {
        let summary = QuillIceCubesStats.summary(reblogs: row.reblogsCount, favourites: row.favouritesCount)
        if !summary.isEmpty {
            Text(summary)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    /// IceCubes' status action row: reply, boost, favorite, bookmark,
    /// share. The reply (`arrowshape.turn.up.left` → Material `reply`)
    /// and boost (`arrow.2.squarepath` → Material `repeat`) glyphs are
    /// mapped in third_party/SwiftOpenUI so GTK's Pango ligature path
    /// renders real icons instead of a missing-glyph placeholder.
    /// Rendered once for the focused post, not per timeline row, to
    /// stay within the Linux profile budget.
    @ViewBuilder
    private func statusActionBar(_ row: IceCubesTimelineRow) -> some View {
        HStack(spacing: 28) {
            actionItem(systemName: "arrowshape.turn.up.left", count: row.repliesCount)
            actionItem(systemName: "arrow.2.squarepath", count: row.reblogsCount)
            actionItem(systemName: "star", count: row.favouritesCount)
            actionItem(systemName: "bookmark", count: nil)
            actionItem(systemName: "square.and.arrow.up", count: nil)
            Spacer()
        }
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func actionItem(systemName: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            if let count, count > 0 {
                Text(count.formatted(.number.notation(.compactName)))
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        // SwiftOpenUI's `ProgressView` initializer doesn't have
        // the title-only `init(_ title:)` overload that
        // Apple SwiftUI ships, so present the spinner alongside
        // a plain `Text` label.
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading Timeline…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func statusRow(_ row: IceCubesTimelineRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                avatarView(for: row.avatar)
                VStack(alignment: .leading) {
                    Text(row.displayNameText)
                        .font(.headline)
                    // Handle + IceCubes-style relative timestamp
                    // ("@alex · 2h"). Precomputed on the row so the
                    // GTK render loop never re-derives it.
                    Text(row.subtitleText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            styledContent(row)
                .font(.body)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .frame(height: 74, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedRowID == row.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    /// Mention/hashtag accent for post content (IceCubes' link color).
    private static let mentionAccent = Color.blue

    /// Renders post content with @mentions / #hashtags tinted, from the styled
    /// segments precomputed on the row — no per-frame parsing.
    private func styledContent(_ row: IceCubesTimelineRow) -> Text {
        Text(styledRuns: row.contentSegments.map { segment in
            Text.Run(text: segment.text, color: segment.isAccent ? Self.mentionAccent : nil)
        })
    }

    @ViewBuilder
    private func avatarView(for avatar: URL?, size: CGFloat = 40) -> some View {
        // Real SwiftUI `AsyncImage`, mirrored in SwiftOpenUI for the GTK/Qt
        // backends — so this is the same Apple source on every platform, no
        // `#if os(Linux)` fork. IceCubes' rounded-rectangle avatar; the gray
        // placeholder covers both the loading phase and a nil/unreachable URL.
        let cornerRadius = size * 0.22
        AsyncImage(url: avatar) { image in
            image.resizable()
        } placeholder: {
            Color.gray
        }
        .frame(width: size, height: size)
        .cornerRadius(cornerRadius)
    }

    private func startTimelineLoadIfNeeded() {
        guard !didStartTimelineLoad else { return }
        didStartTimelineLoad = true
        let env = ProcessInfo.processInfo.environment
        if env["QUILLUI_DISABLE_FETCH"] == "1" {
            seedProfileFixturesIfNeeded()
        } else {
            Task { @MainActor in await fetchTimeline() }
        }
    }

    private func seedProfileFixturesIfNeeded() {
        let rows = QuillIceCubesProfileFixtures.rows
        if timelineRows != rows {
            timelineRows = rows
        }
        applyInitialTimelineSelectionIfNeeded(to: rows)
        if isLoading {
            isLoading = false
        }
        if errorMessage != nil {
            errorMessage = nil
        }
    }

    private func fetchTimeline() async {
        if !isLoading {
            isLoading = true
        }
        if errorMessage != nil {
            errorMessage = nil
        }
        do {
            let fetchedStatuses: [Status] = try await client.get(
                endpoint: Timelines.pub(sinceId: nil, maxId: nil, minId: nil, local: true, limit: 20)
            )
            let rows = fetchedStatuses.map(IceCubesTimelineRow.init(status:))
            if self.timelineRows != rows {
                self.timelineRows = rows
            }
            self.applyInitialTimelineSelectionIfNeeded(to: rows)
        } catch {
            self.errorMessage = error.localizedDescription
        }
        if isLoading {
            isLoading = false
        }
    }

    private func applyInitialTimelineSelectionIfNeeded(to rows: [IceCubesTimelineRow]) {
        guard selectedRowID == nil else { return }
        selectedRowID = QuillIceCubesInitialSelection.selectedTimelineID(
            in: rows,
            environment: initialSelectionEnvironment
        )
    }

    private var selectedRow: IceCubesTimelineRow? {
        selectedRowID.flatMap { id in timelineRows.first { $0.id == id } } ?? timelineRows.first
    }
}

/// Render-facing projection of a Mastodon status. Keeping the
/// QuillUI `List` over plain stored values makes the GTK backend's
/// diff/evaluation path match the small fixture apps more closely
/// while preserving the upstream-shaped `Status` API at the boundary.
public struct IceCubesTimelineRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayNameText: String
    public let handleText: String
    /// "@handle · 2h" — precomputed so the GTK render loop reads a
    /// stored string instead of re-deriving it every frame.
    public let subtitleText: String
    public let contentText: String
    /// `contentText` split into plain + accent (mention/hashtag) segments,
    /// precomputed so the GTK render loop never re-parses. The accent color is
    /// applied in the view, keeping the model Hashable/Sendable.
    public let contentSegments: [IceCubesContentSegment]
    public let timeText: String
    public let repliesCount: Int
    public let reblogsCount: Int
    public let favouritesCount: Int
    public let avatar: URL?

    public init(
        id: String,
        displayNameText: String,
        handleText: String,
        contentText: String,
        timeText: String = "",
        repliesCount: Int = 0,
        reblogsCount: Int = 0,
        favouritesCount: Int = 0,
        avatar: URL? = nil,
        contentSegments: [IceCubesContentSegment]? = nil
    ) {
        self.id = id
        self.displayNameText = displayNameText
        self.handleText = handleText
        self.contentText = contentText
        self.contentSegments = contentSegments ?? IceCubesContentRuns.segments(fromRawText: contentText)
        self.timeText = timeText
        self.subtitleText = timeText.isEmpty ? handleText : "\(handleText) · \(timeText)"
        self.repliesCount = repliesCount
        self.reblogsCount = reblogsCount
        self.favouritesCount = favouritesCount
        self.avatar = avatar
    }

    public init(status: Status) {
        self.init(status: status, now: Date())
    }

    /// Testable projection: `now` is injectable so relative-time
    /// formatting ("2h", "Jan 1") is deterministic in unit tests.
    public init(status: Status, now: Date) {
        self.init(
            id: status.id,
            displayNameText: status.account.displayNameText,
            handleText: status.account.handleText,
            contentText: status.contentText,
            timeText: IceCubesRelativeTime.string(fromISO8601: status.createdAt, now: now),
            repliesCount: status.repliesCount,
            reblogsCount: status.reblogsCount,
            favouritesCount: status.favouritesCount,
            avatar: status.account.avatar,
            contentSegments: IceCubesContentRuns.segments(fromHTML: status.content.htmlValue)
        )
    }
}

/// A run of post content — plain text, or an accent-tinted @mention / #hashtag.
public struct IceCubesContentSegment: Hashable, Sendable {
    public let text: String
    public let isAccent: Bool
    public init(text: String, isAccent: Bool) {
        self.text = text
        self.isAccent = isAccent
    }
}

/// Splits Mastodon post content into plain + accent segments for the timeline.
/// `segments(fromHTML:)` is the real path (links/invisible-spans/line-breaks);
/// `segments(fromRawText:)` is the tag-stripped fallback that flags bare
/// `@mentions` / `#hashtags` (used when only plain text is available, e.g. tests).
public enum IceCubesContentRuns {
    public static func segments(fromRawText text: String) -> [IceCubesContentSegment] {
        var segments: [IceCubesContentSegment] = []
        var plain = ""
        let chars = Array(text)
        var i = 0

        func flushPlain() {
            if !plain.isEmpty {
                segments.append(IceCubesContentSegment(text: plain, isAccent: false))
                plain = ""
            }
        }

        while i < chars.count {
            let c = chars[i]
            let atBoundary = i == 0 || chars[i - 1] == " " || chars[i - 1] == "\n"
            if (c == "@" || c == "#") && atBoundary {
                var j = i + 1
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" {
                    j += 1
                }
                if j > i + 1 { // at least one word character after @ / #
                    flushPlain()
                    segments.append(IceCubesContentSegment(text: String(chars[i..<j]), isAccent: true))
                    i = j
                    continue
                }
            }
            plain.append(c)
            i += 1
        }
        flushPlain()
        return segments
    }

    /// Parses Mastodon post HTML into styled segments: `<a>` link text
    /// (mentions / hashtags / URLs) → accent; `<span class="invisible">`
    /// content (Mastodon's hidden URL prefixes) is dropped; `<br>` and `</p>`
    /// become newlines; other tags are stripped and HTML entities decoded.
    public static func segments(fromHTML html: String) -> [IceCubesContentSegment] {
        var segments: [IceCubesContentSegment] = []
        var buffer = ""
        var bufferAccent = false
        var linkDepth = 0
        var spanStack: [Bool] = [] // isInvisible per currently-open <span>
        let chars = Array(html)
        var i = 0

        func emit(_ text: String, accent: Bool) {
            if text.isEmpty { return }
            if accent != bufferAccent, !buffer.isEmpty {
                segments.append(IceCubesContentSegment(text: HTMLEntities.decode(buffer), isAccent: bufferAccent))
                buffer = ""
            }
            bufferAccent = accent
            buffer += text
        }

        while i < chars.count {
            let c = chars[i]
            if c == "<" {
                var tag = ""
                var j = i + 1
                while j < chars.count, chars[j] != ">" { tag.append(chars[j]); j += 1 }
                i = (j < chars.count) ? j + 1 : j
                let lower = tag.lowercased()
                let isClose = lower.hasPrefix("/")
                let name = String(lower.drop(while: { $0 == "/" }).prefix(while: { $0.isLetter || $0.isNumber }))
                let hidden = spanStack.contains(true)
                switch name {
                case "a":
                    linkDepth = isClose ? max(0, linkDepth - 1) : linkDepth + 1
                case "span":
                    if isClose {
                        if !spanStack.isEmpty { spanStack.removeLast() }
                    } else {
                        spanStack.append(lower.contains("invisible"))
                    }
                case "br":
                    if !hidden { emit("\n", accent: linkDepth > 0) }
                case "p":
                    if isClose, !hidden { emit("\n", accent: linkDepth > 0) }
                default:
                    break
                }
                continue
            }
            if !spanStack.contains(true) {
                emit(String(c), accent: linkDepth > 0)
            }
            i += 1
        }
        if !buffer.isEmpty {
            segments.append(IceCubesContentSegment(text: HTMLEntities.decode(buffer), isAccent: bufferAccent))
        }
        return normalize(segments)
    }

    /// Drops empty segments and trims leading/trailing whitespace + newlines.
    static func normalize(_ segments: [IceCubesContentSegment]) -> [IceCubesContentSegment] {
        var result = segments.filter { !$0.text.isEmpty }
        if let first = result.first {
            let trimmed = String(first.text.drop(while: { $0 == "\n" || $0 == " " }))
            result[0] = IceCubesContentSegment(text: trimmed, isAccent: first.isAccent)
        }
        if let last = result.last {
            var t = last.text
            while let lc = t.last, lc == "\n" || lc == " " { t.removeLast() }
            result[result.count - 1] = IceCubesContentSegment(text: t, isAccent: last.isAccent)
        }
        return result.filter { !$0.text.isEmpty }
    }
}

/// Mastodon-facing wrapper that parses a `created_at` ISO8601 string and
/// formats it with the shared `QuillFoundation.RelativeTime` ("now" / "5m"
/// / "2h" / "3d" within the last week, then a short absolute date). The
/// wire-format parsing stays here; the display logic is the reusable piece.
public enum IceCubesRelativeTime {
    public static func string(fromISO8601 createdAt: String, now: Date) -> String {
        string(fromISO8601: createdAt, now: now, calendar: .current)
    }

    /// `calendar` (carrying its time zone) is injectable so the
    /// absolute-date branch is deterministic in unit tests; the
    /// app uses `.current` to show dates in the viewer's zone.
    static func string(fromISO8601 createdAt: String, now: Date, calendar: Calendar) -> String {
        guard let date = parse(createdAt) else { return "" }
        return RelativeTime.string(for: date, now: now, calendar: calendar)
    }

    static func parse(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }
}

/// IceCubes' status-detail engagement summary line: "12 Boosts · 28
/// Favorites", with singular/plural agreement and Apple's compact
/// large-number formatting. A zero-count metric is omitted; an all-zero
/// status yields an empty string so the line can be hidden entirely.
public enum QuillIceCubesStats {
    public static func summary(reblogs: Int, favourites: Int) -> String {
        var parts: [String] = []
        if reblogs > 0 { parts.append(unit(reblogs, singular: "Boost")) }
        if favourites > 0 { parts.append(unit(favourites, singular: "Favorite")) }
        return parts.joined(separator: " · ")
    }

    static func unit(_ count: Int, singular: String) -> String {
        // Apple's compact-name notation ("1.3K", "1.5M") via Foundation's
        // IntegerFormatStyle — the real API, not a hand-rolled formatter.
        let formatted = count.formatted(.number.notation(.compactName))
        return count == 1 ? "1 \(singular)" : "\(formatted) \(singular)s"
    }
}

public enum QuillIceCubesInitialSelection {
    public static let selectedTimelineIndexEnvironmentKey = "QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START"

    public static func selectedTimelineID(
        in rows: [IceCubesTimelineRow],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> IceCubesTimelineRow.ID? {
        QuillInitialSelection.selectedID(
            in: rows,
            environmentKeys: [selectedTimelineIndexEnvironmentKey],
            environment: environment
        )
    }
}

/// Static content used by the `QUILLUI_DISABLE_FETCH=1` profile
/// path so the rendered timeline has a representative shape
/// without a URLSession round-trip. Not used in production —
/// production keeps fetching `mastodon.social/api/v1/timelines/public`.
public enum QuillIceCubesProfileFixtures {
    public static let statuses: [Status] = [
        Status(
            id: "1",
            account: Account(
                id: "1",
                acct: "fixture",
                username: "fixture",
                displayName: "Fixture User"
            ),
            content: HTMLString(stringLiteral: "<p>Hello from a QuillIceCubes profile fixture.</p>"),
            createdAt: "2026-01-01T00:00:00Z",
            repliesCount: 3,
            reblogsCount: 8,
            favouritesCount: 21
        ),
        Status(
            id: "2",
            account: Account(
                id: "2",
                acct: "deploybot",
                username: "deploybot",
                displayName: "Deploy Bot"
            ),
            content: HTMLString(stringLiteral: "<p>Canary rollout healthy after 30m. cc <a href=\"https://mastodon.social/@deploybot\" class=\"u-url mention\">@<span>deploybot</span></a></p>"),
            createdAt: "2026-01-01T00:01:00Z",
            repliesCount: 1,
            reblogsCount: 4,
            favouritesCount: 12
        ),
        Status(
            id: "3",
            account: Account(
                id: "3",
                acct: "swiftlinux",
                username: "swiftlinux",
                displayName: "Swift on Linux"
            ),
            content: HTMLString(stringLiteral: "<p>Desktop packaging notes are ready.<br>Next up: the toolchain smoke run.</p>"),
            createdAt: "2026-01-01T00:02:00Z",
            repliesCount: 6,
            reblogsCount: 19,
            favouritesCount: 47
        ),
        Status(
            id: "4",
            account: Account(
                id: "4",
                acct: "mastodon",
                username: "mastodon",
                displayName: "Mastodon"
            ),
            content: HTMLString(stringLiteral: "<p>Timeline cards, replies, and boosts remain grouped in the focused detail view.</p>"),
            createdAt: "2026-01-01T00:03:00Z",
            repliesCount: 0,
            reblogsCount: 2,
            favouritesCount: 9
        ),
        Status(
            id: "5",
            account: Account(
                id: "5",
                acct: "design",
                username: "design",
                displayName: "Mastodon Design"
            ),
            content: HTMLString(stringLiteral: "<p>Selection polish across GTK and Qt — see <a href=\"https://mastodon.social/tags/SwiftOnLinux\" class=\"mention hashtag\">#<span>SwiftOnLinux</span></a> <a href=\"https://swift.org/blog/swift-on-linux\"><span class=\"invisible\">https://</span><span class=\"ellipsis\">swift.org/blog</span><span class=\"invisible\">/swift-on-linux</span></a></p>"),
            createdAt: "2026-01-01T00:04:00Z",
            repliesCount: 12,
            reblogsCount: 140,
            favouritesCount: 1280
        ),
    ]

    public static let rows: [IceCubesTimelineRow] = statuses.map(IceCubesTimelineRow.init(status:))
}
