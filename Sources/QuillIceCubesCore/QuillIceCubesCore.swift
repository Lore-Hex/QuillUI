import Foundation
@_exported import Models
@_exported import NetworkClient
import QuillUI

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
                    ProgressView("Loading Timeline...")
                } else if let errorMessage = errorMessage {
                    VStack {
                        Text("Error: \(errorMessage)")
                            .foregroundColor(.red)
                        Button("Retry") {
                            Task {
                                await fetchTimeline()
                            }
                        }
                    }
                } else {
                    List(statuses) { status in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                AsyncImage(url: status.account.avatar) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                
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
                    .refreshable {
                        await fetchTimeline()
                    }
                }
            }
            .navigationTitle("Public Timeline")
        }
        .task {
            await fetchTimeline()
        }
    }
    
    private func fetchTimeline() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedStatuses: [Status] = try await client.get(endpoint: Timelines.pub(sinceId: nil, maxId: nil, minId: nil, local: true, limit: 20))
            self.statuses = fetchedStatuses
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
