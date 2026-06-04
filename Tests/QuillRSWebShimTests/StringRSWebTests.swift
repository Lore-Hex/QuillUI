import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `String.escapedHTML` — escapes the five special HTML
/// characters (`&`, `<`, `>`, `"`, `'`) and leaves everything else untouched.
@Suite("RSWeb clone — String.escapedHTML")
struct StringRSWebTests {

    @Test("escapes all five special characters in context")
    func escapesSpecials() {
        #expect("a & b < c > d \" e ' f".escapedHTML
                == "a &amp; b &lt; c &gt; d &quot; e &apos; f")
    }

    @Test("each special character maps to its entity")
    func eachEntity() {
        #expect("&".escapedHTML == "&amp;")
        #expect("<".escapedHTML == "&lt;")
        #expect(">".escapedHTML == "&gt;")
        #expect("\"".escapedHTML == "&quot;")
        #expect("'".escapedHTML == "&apos;")
    }

    @Test("plain and empty strings are unchanged")
    func plainUnchanged() {
        #expect("plain text 123".escapedHTML == "plain text 123")
        #expect("".escapedHTML == "")
    }
}
