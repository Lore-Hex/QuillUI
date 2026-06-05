import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `HTTPDateInfo` — reads the HTTP `Date` header.
///
/// Only the locale-independent nil paths are asserted: the upstream
/// `DateFormatter` sets no explicit locale, so successfully parsing a real HTTP
/// date string depends on the CI runner's current locale and is intentionally
/// not asserted here (it would be flaky across platforms).
@Suite("RSWeb clone — HTTPDateInfo")
struct HTTPDateInfoTests {

    private func response(headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }

    @Test("no Date header yields a nil date")
    func noHeader() {
        #expect(HTTPDateInfo(urlResponse: response(headers: [:]))?.date == nil)
    }

    @Test("an unparseable Date header yields a nil date")
    func unparseable() {
        #expect(HTTPDateInfo(urlResponse: response(headers: ["Date": "definitely not a date"]))?.date == nil)
    }
}
