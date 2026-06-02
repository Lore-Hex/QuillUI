import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// OPML 2.0 subscription-list parser.
///
/// NetNewsWire (Mac + iOS) reads and writes OPML for
/// subscription import/export, sync, and seeded defaults. The
/// upstream `RSParser` package's OPML reader carries a lot of
/// Apple-only baggage; this is a focused Foundation/XMLParser
/// port that handles the subset relevant to a Quill reader:
///
///   - `<outline type="rss" text="..." xmlUrl="..."/>` leaves
///   - Nested `<outline>` groups (folders) — currently flattened;
///     folder-tree support arrives with the sidebar folder slice
///   - `<title>` inside `<head>` for the list title
///   - Quietly skips `<outline>` rows that have no `xmlUrl`
///
/// Returns the imported subscription list verbatim; the caller
/// (typically `RSSReaderModel.importOPML(data:)`) is responsible
/// for de-duplication against the existing subscribed list.
public enum OPMLImporter {

    public struct Result: Equatable, Sendable {
        public var title: String?
        public var feeds: [Feed]

        public init(title: String? = nil, feeds: [Feed] = []) {
            self.title = title
            self.feeds = feeds
        }
    }

    /// Tree-preserving counterpart to `Result`. Mirrors the
    /// nested `<outline>` structure from upstream NetNewsWire's
    /// OPML import: leaves are subscriptions (Feed); branches
    /// are folders carrying further children. Used by the
    /// future feedsPane → RSTree migration that will render
    /// the hierarchy. The existing flat `parse()` continues to
    /// return all leaves for callers that just want a feed list.
    public struct Tree: Equatable, Sendable {
        public var title: String?
        public var root: Folder

        public init(title: String? = nil, root: Folder = Folder()) {
            self.title = title
            self.root = root
        }
    }

    public struct Folder: Equatable, Sendable, Identifiable {
        public var id: String { name }
        public var name: String
        public var feeds: [Feed]
        public var subfolders: [Folder]

        public init(name: String = "", feeds: [Feed] = [], subfolders: [Folder] = []) {
            self.name = name
            self.feeds = feeds
            self.subfolders = subfolders
        }

        /// All feeds in this folder and any nested subfolder
        /// (depth-first). Convenience for callers that want
        /// the flat-list semantics from the original parse().
        public var allFeeds: [Feed] {
            var out: [Feed] = feeds
            for sub in subfolders {
                out.append(contentsOf: sub.allFeeds)
            }
            return out
        }
    }

    public static func parse(data: Data) -> Result {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return Result(title: delegate.title, feeds: delegate.feeds)
    }

    public static func parse(xml: String) -> Result {
        parse(data: Data(xml.utf8))
    }

    public static func parseTree(data: Data) -> Tree {
        let delegate = TreeDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return Tree(title: delegate.title, root: delegate.root)
    }

    public static func parseTree(xml: String) -> Tree {
        parseTree(data: Data(xml.utf8))
    }

    final class Delegate: NSObject, XMLParserDelegate {
        var title: String?
        var feeds: [Feed] = []
        private var path: [String] = []
        private var buffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            path.append(elementName)
            buffer = ""
            if elementName == "outline", let xmlUrl = attributeDict["xmlUrl"], !xmlUrl.isEmpty {
                let text = attributeDict["text"]
                    ?? attributeDict["title"]
                    ?? xmlUrl
                feeds.append(Feed(title: text, url: xmlUrl))
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "title", path.contains("head"), title == nil {
                title = trimmed.isEmpty ? nil : trimmed
            }
            buffer = ""
            if !path.isEmpty { path.removeLast() }
        }
    }

    /// XMLParserDelegate that builds a Folder tree from nested
    /// `<outline>` elements. Each <outline> with an xmlUrl
    /// becomes a Feed in the current folder; each <outline>
    /// without an xmlUrl pushes a new folder onto a stack so
    /// its descendants attach to the right parent.
    final class TreeDelegate: NSObject, XMLParserDelegate {
        var title: String?
        var root = Folder()
        // Parallel stacks: `stack` carries the open Folder under
        // construction at each depth; `outlineWasFolder` flags
        // whether the current <outline> at that depth needs a
        // pop in didEndElement. xmlUrl-bearing leaves are not
        // pushed onto the stack at all.
        private var stack: [Folder] = [Folder()]
        private var outlineWasFolder: [Bool] = []
        private var path: [String] = []
        private var buffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            path.append(elementName)
            buffer = ""
            guard elementName == "outline" else { return }
            if let xmlUrl = attributeDict["xmlUrl"], !xmlUrl.isEmpty {
                // Leaf: append Feed to the current folder.
                let text = attributeDict["text"]
                    ?? attributeDict["title"]
                    ?? xmlUrl
                let leaf = Feed(title: text, url: xmlUrl)
                let topIdx = stack.count - 1
                stack[topIdx].feeds.append(leaf)
                outlineWasFolder.append(false)
            } else {
                // Folder: push a new Folder onto the stack.
                let folderName = attributeDict["text"] ?? attributeDict["title"] ?? ""
                stack.append(Folder(name: folderName))
                outlineWasFolder.append(true)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "title", path.contains("head"), title == nil {
                title = trimmed.isEmpty ? nil : trimmed
            }
            if elementName == "outline" {
                let wasFolder = outlineWasFolder.popLast() ?? false
                if wasFolder && stack.count > 1 {
                    // Pop the folder we built and attach it as a
                    // subfolder of the new top.
                    let closed = stack.removeLast()
                    let parentIdx = stack.count - 1
                    stack[parentIdx].subfolders.append(closed)
                }
            }
            buffer = ""
            if !path.isEmpty { path.removeLast() }
        }

        func parserDidEndDocument(_ parser: XMLParser) {
            // The single remaining stack entry is the root sentinel.
            root = stack.first ?? Folder()
        }
    }
}
