import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `URL` helpers: http/https classification, query-item
/// appending, and browser-prep. `absoluteStringWithHTTPOrHTTPSPrefixRemoved()`
/// is only checked on its correct (non-http → nil) branch; its positive branch
/// returns the scheme prefix (an upstream bug) and is intentionally not pinned.
@Suite("RSWeb clone — URL+RSWeb")
struct URLRSWebTests {

    @Test("http/https classification is case-insensitive")
    func classification() {
        #expect(URL(string: "https://example.com")!.isHTTPSURL())
        #expect(URL(string: "HTTPS://example.com")!.isHTTPSURL())
        #expect(URL(string: "http://example.com")!.isHTTPURL())
        #expect(!URL(string: "http://example.com")!.isHTTPSURL())
        #expect(URL(string: "https://example.com")!.isHTTPOrHTTPSURL())
        #expect(!URL(string: "ftp://example.com")!.isHTTPOrHTTPSURL())
    }

    @Test("appendingQueryItem(s) adds query parameters")
    func appendQuery() {
        let url = URL(string: "https://example.com/a")!
        #expect(url.appendingQueryItem(URLQueryItem(name: "k", value: "v"))?.absoluteString
                == "https://example.com/a?k=v")
        let two = url.appendingQueryItems([
            URLQueryItem(name: "a", value: "1"), URLQueryItem(name: "b", value: "2")
        ])
        #expect(two?.absoluteString == "https://example.com/a?a=1&b=2")
    }

    @Test("preparedForOpeningInBrowser decodes &amp; entities")
    func browserPrep() {
        let url = URL(string: "https://example.com/feed?a=1&amp;b=2")!
        #expect(url.preparedForOpeningInBrowser()?.absoluteString
                == "https://example.com/feed?a=1&b=2")
    }

    @Test("absoluteStringWithHTTPOrHTTPSPrefixRemoved returns nil for non-http URLs")
    func prefixRemovalNonHTTP() {
        #expect(URL(string: "ftp://example.com")!.absoluteStringWithHTTPOrHTTPSPrefixRemoved() == nil)
    }

    @Test("MacWebBrowser Linux shim mirrors path display and duplicate-name helpers")
    @MainActor func macWebBrowserSurface() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillRSWebShimTests-\(UUID().uuidString)")
        let appURL = root.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let browser = try #require(MacWebBrowser(path: appURL.path))
        #expect(browser.url == appURL)
        #expect(browser.bundlePath == appURL.path)
        #expect(browser.name == "Example")

        let duplicateA = MacWebBrowser(url: URL(fileURLWithPath: "/Applications/Example.app"))
        let duplicateB = MacWebBrowser(url: URL(fileURLWithPath: "/Users/test/Applications/Example.app"))
        #expect(MacWebBrowser.duplicateBrowserNames(in: [duplicateA, duplicateB]) == ["Example"])
        #expect(MacWebBrowser.displayPath(of: URL(fileURLWithPath: "/a/b/c/d/e/Example.app")) == "/a/.../e")
    }
}
