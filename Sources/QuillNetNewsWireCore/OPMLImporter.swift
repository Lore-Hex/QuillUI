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
}
