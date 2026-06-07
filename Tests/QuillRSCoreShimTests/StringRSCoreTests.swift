import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `String` helpers reached by the real NetNewsWire
/// FeedFinder: `normalizedURL` (feed:/feeds: handling + scheme/trailing-slash
/// normalization), `caseInsensitiveContains`, `stripping(prefix:)`/`(suffix:)`,
/// and `trimmingWhitespace`.
@Suite("QuillRSCoreShim — String+RSCore")
struct StringRSCoreTests {

    @Test("normalizedURL strips feed: and keeps an embedded http URL")
    func feedPrefixWithEmbeddedHTTP() {
        // Upstream's documented edge case (boingboing.net).
        #expect("feed:http://boingboing.net/feed".normalizedURL == "http://boingboing.net/feed")
    }

    @Test("normalizedURL maps feeds: to https and adds a trailing slash for a bare host")
    func feedsPrefixBecomesHTTPS() {
        #expect("feeds:example.com".normalizedURL == "https://example.com/")
    }

    @Test("normalizedURL adds http:// to a scheme-less URL")
    func addsHTTPScheme() {
        #expect("example.com/feed".normalizedURL == "http://example.com/feed")
    }

    @Test("normalizedURL strips a leading // and adds http://")
    func stripsLeadingSlashes() {
        #expect("//example.com/feed".normalizedURL == "http://example.com/feed")
    }

    @Test("normalizedURL adds a trailing slash to a top-level URL only")
    func topLevelTrailingSlash() {
        #expect("https://ranchero.com".normalizedURL == "https://ranchero.com/")
        #expect("http://example.com/feed".normalizedURL == "http://example.com/feed")
    }

    @Test("normalizedURL trims surrounding whitespace first")
    func trimsBeforeNormalizing() {
        #expect("  http://example.com/x  \n".normalizedURL == "http://example.com/x")
    }

    @Test("caseInsensitiveContains matches regardless of case")
    func caseInsensitive() {
        #expect("Hello World".caseInsensitiveContains("hello"))
        #expect("Hello World".caseInsensitiveContains("WORLD"))
        #expect(!"Hello World".caseInsensitiveContains("xyz"))
    }

    @Test("stripping(prefix:) removes an anchored, case-insensitive prefix")
    func strippingPrefix() {
        #expect("FEED:abc".stripping(prefix: "feed:") == "abc")
        #expect("abc".stripping(prefix: "feed:") == "abc")
    }

    @Test("stripping(suffix:) removes an anchored suffix")
    func strippingSuffix() {
        #expect("abc/feed/".stripping(suffix: "/") == "abc/feed")
    }

    @Test("trimmingWhitespace removes surrounding whitespace and newlines")
    func trimming() {
        #expect("  x \n".trimmingWhitespace == "x")
    }
}
