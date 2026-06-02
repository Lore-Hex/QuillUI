import Foundation
import Testing
@testable import QuillRSWeb

/// Smoke tests for the vendored upstream RSWeb module. Pins
/// the value-types the next iteration will lean on for the
/// fetch-path migration (conditional GET, HTTP methods, MIME
/// detection). Upstream RSWeb's own test target wasn't
/// vendored — these are Quill-side guards.
@Suite("QuillRSWeb — vendored upstream smoke tests")
struct QuillRSWebSmokeTests {

    @Test("HTTPConditionalGetInfo is nil when both lastModified and etag are nil")
    func conditionalGetNilWhenEmpty() {
        let info = HTTPConditionalGetInfo(lastModified: nil, etag: nil)
        #expect(info == nil)
    }

    @Test("HTTPConditionalGetInfo round-trips etag + lastModified")
    func conditionalGetRoundTrip() {
        let info = HTTPConditionalGetInfo(
            lastModified: "Wed, 21 Oct 2025 07:28:00 GMT",
            etag: "\"abc123\""
        )
        #expect(info?.lastModified == "Wed, 21 Oct 2025 07:28:00 GMT")
        #expect(info?.etag == "\"abc123\"")
    }

    @Test("HTTPMethod constants match RFC 7231")
    func httpMethodConstants() {
        #expect(HTTPMethod.get == "GET")
        #expect(HTTPMethod.post == "POST")
        #expect(HTTPMethod.put == "PUT")
        #expect(HTTPMethod.delete == "DELETE")
    }

    @Test("MimeType image-format constants are the canonical strings")
    func mimeTypeConstants() {
        #expect(MimeType.png == "image/png")
        #expect(MimeType.jpeg == "image/jpeg")
        #expect(MimeType.gif == "image/gif")
    }
}
