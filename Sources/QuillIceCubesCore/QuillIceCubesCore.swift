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
                        Text("Timeline item")
                            .font(.title)
                            .bold()
                        Text("\(row.displayNameText) \(row.handleText)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        detailCard(
                            title: "Post",
                            body: row.contentText
                        )
                        detailCard(
                            title: "Conversation",
                            body: "Replies, boosts, favorites, and sharing actions stay grouped with the selected post."
                        )
                        detailCard(
                            title: "Timeline status",
                            body: errorMessage ?? "Public timeline loaded with fixture-backed content for deterministic Linux rendering."
                        )
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

    private func detailCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillDesktopChromeStyle.cardBackground)
        .cornerRadius(8)
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
                    Text(row.handleText)
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
    private func avatarView(for avatar: URL?) -> some View {
        // SwiftUI's `AsyncImage` isn't part of SwiftOpenUI's GTK4
        // backend yet — replace with a fixed circular placeholder.
        // Real avatar decoding lands when the GTK image-loader
        // shim grows URLSession-backed bitmap support.
        #if os(Linux)
        Circle()
            .fill(Color.gray)
            .frame(width: 40, height: 40)
        #else
        AsyncImage(url: avatar) { image in
            image.resizable()
        } placeholder: {
            Color.gray
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
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
    public let contentText: String
    public let avatar: URL?

    public init(
        id: String,
        displayNameText: String,
        handleText: String,
        contentText: String,
        avatar: URL? = nil
    ) {
        self.id = id
        self.displayNameText = displayNameText
        self.handleText = handleText
        self.contentText = contentText
        self.avatar = avatar
    }

    public init(status: Status) {
        self.init(
            id: status.id,
            displayNameText: status.account.displayNameText,
            handleText: status.account.handleText,
            contentText: status.contentText,
            avatar: status.account.avatar
        )
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
            createdAt: "2026-01-01T00:00:00Z"
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
            createdAt: "2026-01-01T00:01:00Z"
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
            createdAt: "2026-01-01T00:02:00Z"
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
            createdAt: "2026-01-01T00:03:00Z"
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
            createdAt: "2026-01-01T00:04:00Z"
        ),
    ]

    public static let rows: [IceCubesTimelineRow] = statuses.map(IceCubesTimelineRow.init(status:))
}
