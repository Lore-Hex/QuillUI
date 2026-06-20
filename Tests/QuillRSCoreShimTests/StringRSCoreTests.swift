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

    @Test("mayBeURL accepts host-like strings and rejects empty or unsafe strings")
    func mayBeURL() {
        #expect("example.com/feed".mayBeURL)
        #expect("https://example.com/feed".mayBeURL)
        #expect("localhost:8080/feed".mayBeURL)
        #expect("http://[::1]/feed".mayBeURL)
        #expect(!"".mayBeURL)
        #expect(!"not-a-host".mayBeURL)
        #expect(!"https://example.com/bad path".mayBeURL)
        #expect(!"https://example.com/\u{0000}".mayBeURL)
    }

    @Test("prepending(tabCount:) adds leading tabs and preserves the payload")
    func prependingTabs() {
        #expect("outline".prepending(tabCount: 0) == "outline")
        #expect("outline".prepending(tabCount: 2) == "\t\toutline")
    }

    @Test("HTML link helpers preserve upstream string shape")
    func htmlLinkHelpers() {
        #expect("Ranchero".htmlByAddingLink("https://ranchero.com/") == #"<a href="https://ranchero.com/">Ranchero</a>"#)
        #expect("Ranchero".htmlByAddingLink("https://ranchero.com/", className: "byline") == #"<a class="byline" href="https://ranchero.com/">Ranchero</a>"#)
        #expect(String.htmlWithLink("https://ranchero.com/") == #"<a href="https://ranchero.com/">https://ranchero.com/</a>"#)
    }

    @Test("hmacUsingSHA1 matches upstream RSCore hex output")
    func hmacUsingSHA1() {
        #expect("what do ya want for nothing?".hmacUsingSHA1(key: "Jefe") == "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79")
        #expect("https://example.com/article".hmacUsingSHA1(key: "") == "7161205f3742a0ba9c0920532cae6983e85d27e5")
    }

    @Test("strippingHTTPOrHTTPSScheme removes only web URL schemes")
    func strippingHTTPOrHTTPS() {
        #expect("http://ranchero.com/".strippingHTTPOrHTTPSScheme == "ranchero.com/")
        #expect("https://ranchero.com/".strippingHTTPOrHTTPSScheme == "ranchero.com/")
        #expect("example://ranchero.com/".strippingHTTPOrHTTPSScheme == "example://ranchero.com/")
    }
}
