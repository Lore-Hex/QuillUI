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
/// The type and its `View` conformance are main-actor isolated.
/// SwiftOpenUI's `View` protocol doesn't put `body` on the main
/// actor (unlike Apple's SwiftUI), so without isolation the
/// body's access to the `@MainActor RSSReaderModel`'s
/// `@Published` properties trips Swift 6 diagnostics. The
/// isolated conformance is required by Swift 6.2 on Linux so
/// the `body` witness does not cross into nonisolated protocol
/// requirements.
@MainActor
public struct QuillNetNewsWireContentView: @MainActor View {
    @StateObject private var model = RSSReaderModel()
    @State private var feedURL: String = "https://daringfireball.net/feeds/main"

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
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
                Task { @MainActor in await model.fetch(urlString: feedURL) }
            }
        }
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

            List {
                ForEach(model.items) { item in
                    Button {
                        model.selectedID = item.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline)
                                .lineLimit(2)
                            if !item.publishedSummary.isEmpty {
                                Text(item.publishedSummary)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            footerStatus
        }
    }

    private var footerStatus: some View {
        HStack(spacing: 8) {
            Text(model.statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
    }

    private var detail: some View {
        Group {
            if let item = model.selectedItem {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(item.title).font(.title).bold()
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
            } else {
                VStack(spacing: 12) {
                    Text("Select an article")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Self-contained RSS reader is fetching live items from \(feedURL).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    public var linkURL: URL? { link.flatMap { URL(string: $0) } }
    public var publishedSummary: String { pubDate ?? "" }
    public var plainTextBody: String { (descriptionHTML ?? "").stripBasicHTML() }
}

@MainActor
final class RSSReaderModel: ObservableObject {
    @Published var items: [RSSItem] = []
    @Published var feedTitle: String?
    @Published var error: String?
    @Published var isLoading = false
    @Published var selectedID: String?

    var selectedItem: RSSItem? {
        guard let selectedID else { return nil }
        return items.first(where: { $0.id == selectedID })
    }

    var statusText: String {
        if isLoading { return "Fetching feed…" }
        if let error { return "Error: \(error)" }
        return "\(items.count) items"
    }

    /// Profile-mode bypass: populate `items` + `feedTitle` with
    /// fixture content so the rendered timeline has shape, then
    /// skip the URLSession round-trip entirely. Used by the
    /// `QUILLUI_DISABLE_FETCH=1` path in `onAppear` so the
    /// Linux profile script can isolate URLSession-cost vs
    /// render-loop-cost.
    func seedProfileFixtures() {
        feedTitle = "Profile Fixture Feed"
        items = [
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
        ]
        selectedID = items.first?.id
        isLoading = false
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
            let parsed = RSSFeedParser.parse(data: data)
            self.feedTitle = parsed.title
            self.items = Array(parsed.items.prefix(50))
            if self.selectedID == nil {
                self.selectedID = self.items.first?.id
            }
        } catch {
            self.error = "\(error)"
        }
        isLoading = false
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
        parser.parse()
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
