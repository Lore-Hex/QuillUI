import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `Data.isProbablyHTML` heuristic used by the real
/// NetNewsWire FeedFinder to tell an HTML page apart from a feed/other payload.
@Suite("QuillRSCoreShim — Data.isProbablyHTML")
struct DataRSCoreTests {

    private func d(_ s: String) -> Data { Data(s.utf8) }

    @Test("a DOCTYPE page is HTML")
    func doctype() {
        #expect(d("<!DOCTYPE html><html><body>hi</body></html>").isProbablyHTML)
        #expect(d("<!doctype html>\n<title>x</title>").isProbablyHTML)
    }

    @Test("html/head/body tags are HTML")
    func structuralTags() {
        #expect(d("<html lang=\"en\"></html>").isProbablyHTML)
        #expect(d("<head><title>x</title></head>").isProbablyHTML)
        #expect(d("<BODY>content</BODY>").isProbablyHTML)
    }

    @Test("common structural elements (div/p/span) are HTML")
    func commonElements() {
        #expect(d("<div>a</div>").isProbablyHTML)
        #expect(d("<p>a</p>").isProbablyHTML)
        #expect(d("<span>a</span>").isProbablyHTML)
    }

    @Test("UTF-16 HTML is detected")
    func utf16() {
        let utf16 = "<!DOCTYPE html><html></html>".data(using: .utf16LittleEndian)!
        #expect(utf16.isProbablyHTML)
    }

    @Test("plain text and angle-bracket math are not HTML")
    func notHTML() {
        #expect(!d("just some plain text, no markup").isProbablyHTML)
        #expect(!d("1 < 2 > 0 is arithmetic").isProbablyHTML)
        #expect(!d("").isProbablyHTML)
    }

    @Test("a feed without HTML structural tags is not classified as HTML")
    func feedIsNotHTML() {
        // Angle brackets but none of the tags the heuristic keys on
        // (html/head/body/div/p/span/doctype). isProbablyHTML is intentionally
        // loose — e.g. an Atom feed containing "http" trips the single-'p' check —
        // but FeedFinder runs FeedParser.canParse() first, so real feeds are caught
        // before isProbablyHTML is ever reached.
        #expect(!d("<rss version=\"2.0\"><channel><title>Site</title></channel></rss>").isProbablyHTML)
    }
}
