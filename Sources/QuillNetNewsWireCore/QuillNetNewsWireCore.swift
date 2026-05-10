import Foundation
import QuillUI
import SwiftUI
@_exported import RSParser
@_exported import RSCore
@_exported import Articles
@_exported import Account
// Real upstream NetNewsWire Mac AppDefaults / ArticleTextSize /
// RefreshInterval — the canonical macOS NetNewsWire defaults bundle.
@_exported import NetNewsWireMacShared

// Global expected by NetNewsWire Shared code.
@MainActor public var appDelegate: AppDelegateShim!

@MainActor public class AppDelegateShim: NSObject {
    public var unreadCount = 0
}

// MARK: - Real RSS reader, powered by upstream RSParser
//
// QuillNetNewsWireContentView fetches a real feed via URLSession, parses
// it with upstream `FeedParser.parse(_:)` (which is the same parser
// Brent Simmons' NetNewsWire ships in production), and renders the
// resulting `ParsedItem`s in a SwiftUI list. No data is stubbed.

public struct QuillNetNewsWireContentView: View {
    @StateObject private var model = FeedReaderModel()
    @State private var feedURL: String = "https://daringfireball.net/feeds/main"

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 280)
        } detail: {
            detail
                .frame(minWidth: 520)
        }
        .frame(minWidth: 880, minHeight: 620)
        .onAppear {
            Task { await model.fetch(urlString: feedURL) }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quill NetNewsWire")
                    .font(.title2).bold()
                Text(model.feedTitle ?? "Loading…")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(14)

            HStack(spacing: 6) {
                TextField("Feed URL", text: $feedURL, onCommit: {
                    Task { await model.fetch(urlString: feedURL) }
                })
                .textFieldStyle(.roundedBorder)
                .font(.caption)

                Button("Refresh") {
                    Task { await model.fetch(urlString: feedURL) }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            if let error = model.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(14)
            }

            List(model.items, id: \.uniqueID, selection: $model.selectedID) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? "Untitled")
                        .font(.subheadline)
                        .lineLimit(2)
                    if let date = item.datePublished {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .tag(item.uniqueID)
            }
            .listStyle(.sidebar)

            footerStatus
        }
    }

    private var footerStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isLoading ? Color.orange : (model.error == nil ? Color.green : Color.red))
                .frame(width: 8, height: 8)
            Text(model.statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color(white: 0.96))
    }

    private var detail: some View {
        Group {
            if let item = model.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.title ?? "Untitled")
                            .font(.title)
                            .bold()
                        if let authors = item.authors, !authors.isEmpty {
                            Text(authors.compactMap(\.name).joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let date = item.datePublished {
                            Text(date.formatted(date: .complete, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Divider()
                        Text(plainText(from: item))
                            .font(.body)
                            .lineSpacing(4)
                            .frame(maxWidth: 720, alignment: .leading)
                        if let url = item.url, let u = URL(string: url) {
                            Divider()
                            Link("Open in browser  →", destination: u)
                                .font(.callout)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Select an article")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Real upstream RSParser is fetching live items from \(feedURL).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func plainText(from item: ParsedItem) -> String {
        let html = item.contentHTML ?? item.contentText ?? item.summary ?? ""
        return html.stripBasicHTML()
    }
}

@MainActor private final class FeedReaderModel: ObservableObject {
    @Published var items: [ParsedItem] = []
    @Published var feedTitle: String?
    @Published var error: String?
    @Published var isLoading = false
    @Published var selectedID: String?

    var selectedItem: ParsedItem? {
        guard let selectedID else { return nil }
        return items.first(where: { $0.uniqueID == selectedID })
    }

    var statusText: String {
        if isLoading { return "Fetching feed…" }
        if let error { return "Error: \(error)" }
        return "\(items.count) items · upstream RSParser"
    }

    func fetch(urlString: String) async {
        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            return
        }
        isLoading = true
        error = nil
        do {
            var request = URLRequest(url: url)
            request.setValue("Quill-NetNewsWire/0.1", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let parserData = ParserData(url: urlString, data: data)
            // Real upstream `FeedParser.parse(_:)` from
            // .upstream/netnewswire/Modules/RSParser. Same parser the
            // production NetNewsWire ships.
            let parsed = try await FeedParser.parse(parserData)
            self.feedTitle = parsed?.title
            // ParsedItem set sorted by datePublished desc.
            let allItems = (parsed?.items ?? Set<ParsedItem>()).sorted(by: { (a, b) in
                (a.datePublished ?? .distantPast) > (b.datePublished ?? .distantPast)
            })
            self.items = Array(allItems.prefix(50))
            if self.selectedID == nil {
                self.selectedID = self.items.first?.uniqueID
            }
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
    }
}

private extension String {
    /// Crude HTML→plaintext strip suitable for an article preview pane.
    /// Production NetNewsWire renders HTML in WebKit; we render plain
    /// text since wiring upstream `ArticleRenderer` requires the full
    /// `Shared/Extensions` tree (out of scope for this checkpoint).
    func stripBasicHTML() -> String {
        let withoutTags = self.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
