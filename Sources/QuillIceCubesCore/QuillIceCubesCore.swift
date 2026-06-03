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
        HStack(spacing: 0) {
            timelineSidebar
                .frame(width: 320)
            Divider()
            timelineDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(QuillDesktopChromeStyle.detailBackground)
        // SwiftOpenUI's `.task { … }` modifier takes a
        // `@Sendable` closure; `QuillIceCubesContentView`
        // isn't Sendable (SwiftUI views aren't), so capturing
        // `self` for `fetchTimeline()` trips
        // `#SendableClosureCaptures`. Use `.onAppear` instead —
        // it's not `@Sendable` and still kicks off the fetch
        // after the view shows.
        //
        // `QUILLUI_DISABLE_FETCH=1` is a profile-mode escape
        // hatch: it seeds fixture content + skips URLSession,
        // so the Linux profile script can sample CPU on a
        // fetched-content-but-no-network path and isolate
        // whether the IceCubes CPU peg lives in the
        // URLSession / decode / @Published path or in the
        // SwiftOpenUI render-loop after the list populates.
        .onAppear { startTimelineLoadIfNeeded() }
    }

    private var timelineSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("IceCubes")
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
        .background(QuillDesktopChromeStyle.sidebarBackground)
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

                        Text(row.contentText)
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Divider()

                        statusStatsBar(row)

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

    /// IceCubes' status-detail engagement line: bold counts with
    /// labels ("8 Boosts · 21 Favorites"), matching the text stats
    /// row IceCubes shows above its action buttons. Rendered as plain
    /// text so every glyph resolves on the GTK Material-Symbols font
    /// — the iconified reply/boost/favorite/bookmark/share buttons
    /// land in a follow-up once `reply`/`repeat` glyphs are added to
    /// third_party/SwiftOpenUI's SF→Material map.
    @ViewBuilder
    private func statusStatsBar(_ row: IceCubesTimelineRow) -> some View {
        HStack(spacing: 22) {
            statGroup(count: row.repliesCount, label: "Replies")
            statGroup(count: row.reblogsCount, label: "Boosts")
            statGroup(count: row.favouritesCount, label: "Favorites")
            Spacer()
        }
    }

    @ViewBuilder
    private func statGroup(count: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Text(QuillIceCubesCountFormat.label(count))
                .font(.subheadline)
                .bold()
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            Text(row.contentText)
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

    @ViewBuilder
    private func avatarView(for avatar: URL?, size: CGFloat = 40) -> some View {
        // SwiftUI's `AsyncImage` isn't part of SwiftOpenUI's GTK4
        // backend yet — replace with a rounded placeholder matching
        // IceCubes' default rounded-rectangle avatar shape. Real
        // avatar decoding lands when the GTK image-loader shim grows
        // URLSession-backed bitmap support.
        let cornerRadius = size * 0.22
        #if os(Linux)
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.gray)
            .frame(width: size, height: size)
        #else
        AsyncImage(url: avatar) { image in
            image.resizable()
        } placeholder: {
            Color.gray
        }
        .frame(width: size, height: size)
        .cornerRadius(cornerRadius)
        #endif
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
        avatar: URL? = nil
    ) {
        self.id = id
        self.displayNameText = displayNameText
        self.handleText = handleText
        self.contentText = contentText
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
            avatar: status.account.avatar
        )
    }
}

/// IceCubes-style relative timestamp formatting for a Mastodon
/// `created_at` ISO8601 string: "now" / "5m" / "2h" / "3d" within
/// the last week, then an absolute short date ("Jan 1", or
/// "Jan 1, 2024" across a year boundary).
public enum IceCubesRelativeTime {
    public static func string(fromISO8601 createdAt: String, now: Date) -> String {
        string(fromISO8601: createdAt, now: now, calendar: .current)
    }

    /// `calendar` (carrying its time zone) is injectable so the
    /// absolute-date branch is deterministic in unit tests; the
    /// app uses `.current` to show dates in the viewer's zone.
    static func string(fromISO8601 createdAt: String, now: Date, calendar: Calendar) -> String {
        guard let date = parse(createdAt) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400))d" }
        return absoluteShortDate(date, now: now, calendar: calendar)
    }

    static func parse(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }

    static func absoluteShortDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

/// Compact engagement counts ("1.2k") for the status action bar.
public enum QuillIceCubesCountFormat {
    public static func label(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        }
        return String(count)
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
            content: HTMLString(stringLiteral: "<p>Canary rollout healthy after 30m.</p>"),
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
            content: HTMLString(stringLiteral: "<p>Desktop packaging notes are ready for the next toolchain smoke run.</p>"),
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
            content: HTMLString(stringLiteral: "<p>Selection polish keeps the lower row visually distinct across GTK and Qt.</p>"),
            createdAt: "2026-01-01T00:04:00Z",
            repliesCount: 12,
            reblogsCount: 140,
            favouritesCount: 1280
        ),
    ]

    public static let rows: [IceCubesTimelineRow] = statuses.map(IceCubesTimelineRow.init(status:))
}
