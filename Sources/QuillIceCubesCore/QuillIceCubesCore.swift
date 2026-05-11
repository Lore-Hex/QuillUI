import Foundation
import QuillUI

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
public struct QuillIceCubesContentView: View {
    @State private var client = MastodonClient(server: "mastodon.social", version: .v1, oauthToken: nil)
    @State private var statuses: [Status] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading && statuses.isEmpty {
                    loadingPlaceholder
                } else if let errorMessage {
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task { await fetchTimeline() }
                        }
                    }
                } else {
                    // SwiftOpenUI's `List` only ships
                    // `init(@ViewBuilder content:)` — no
                    // `List(_ data:rowContent:)` overload. Use a
                    // ForEach inside a `List { … }` so both
                    // backends compile.
                    List {
                        ForEach(statuses) { status in
                            statusRow(status)
                        }
                    }
                    #if !os(Linux)
                    .refreshable { await fetchTimeline() }
                    #endif
                }
            }
            .navigationTitle("Public Timeline")
        }
        .task { await fetchTimeline() }
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
    private func statusRow(_ status: Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                avatarView(for: status.account)
                VStack(alignment: .leading) {
                    Text(status.account.cachedDisplayName.asRawText)
                        .font(.headline)
                    Text("@\(status.account.acct)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Text(status.content.asRawText)
                .font(.body)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func avatarView(for account: Account) -> some View {
        // SwiftUI's `AsyncImage` isn't part of SwiftOpenUI's GTK4
        // backend yet — replace with a fixed circular placeholder.
        // Real avatar decoding lands when the GTK image-loader
        // shim grows URLSession-backed bitmap support.
        #if os(Linux)
        Circle()
            .fill(Color.gray)
            .frame(width: 40, height: 40)
        #else
        AsyncImage(url: account.avatar) { image in
            image.resizable()
        } placeholder: {
            Color.gray
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        #endif
    }

    private func fetchTimeline() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedStatuses: [Status] = try await client.get(
                endpoint: Timelines.pub(sinceId: nil, maxId: nil, minId: nil, local: true, limit: 20)
            )
            self.statuses = fetchedStatuses
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
