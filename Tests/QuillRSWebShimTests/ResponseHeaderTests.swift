import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb HTTP response-header base: the `HTTPResponseHeader`
/// name constants and the `URLResponse`/`HTTPURLResponse` helpers
/// (`statusIsOK`, `forcedStatusCode`, case-insensitive `valueForHTTPHeaderField`).
@Suite("RSWeb clone — HTTPResponseHeader + URLResponse helpers")
struct ResponseHeaderTests {

    private func httpResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
    }

    @Test("HTTPResponseHeader exposes the expected header-name constants")
    func headerConstants() {
        #expect(HTTPResponseHeader.contentType == "Content-Type")
        #expect(HTTPResponseHeader.date == "Date")
        #expect(HTTPResponseHeader.etag == "Etag")
        #expect(HTTPResponseHeader.lastModified == "Last-Modified")
        #expect(HTTPResponseHeader.cacheControl == "Cache-Control")
        #expect(HTTPResponseHeader.retryAfter == "Retry-After")
    }

    @Test("statusIsOK is true for 2xx only")
    func statusIsOK() {
        #expect(httpResponse(status: 200).statusIsOK)
        #expect(httpResponse(status: 299).statusIsOK)
        #expect(!httpResponse(status: 300).statusIsOK)
        #expect(!httpResponse(status: 404).statusIsOK)
    }

    @Test("forcedStatusCode returns the HTTP status, or 0 for a non-HTTP response")
    func forcedStatusCode() {
        #expect(httpResponse(status: 503).forcedStatusCode == 503)
        let plain = URLResponse(
            url: URL(string: "https://example.com")!,
            mimeType: nil, expectedContentLength: 0, textEncodingName: nil
        )
        #expect(plain.forcedStatusCode == 0)
        #expect(!plain.statusIsOK)
    }

    @Test("valueForHTTPHeaderField looks up headers case-insensitively")
    func valueForHTTPHeaderField() {
        let response = httpResponse(status: 200, headers: ["Content-Type": "text/html"])
        #expect(response.valueForHTTPHeaderField("Content-Type") == "text/html")
        #expect(response.valueForHTTPHeaderField("content-type") == "text/html")
        #expect(response.valueForHTTPHeaderField("CONTENT-TYPE") == "text/html")
        #expect(response.valueForHTTPHeaderField("X-Missing") == nil)
    }
}
