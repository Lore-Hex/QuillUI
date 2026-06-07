import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `CacheControlInfo`: max-age parsing (from a
/// Cache-Control string and from an HTTPURLResponse) and the resume-time math.
@Suite("RSWeb clone — CacheControlInfo")
struct CacheControlInfoTests {

    @Test("init(value:) parses max-age and rejects missing/zero/non-numeric")
    func parseValue() {
        #expect(CacheControlInfo(value: "max-age=3600")?.maxAge == 3600)
        #expect(CacheControlInfo(value: "public, max-age=600")?.maxAge == 600)
        #expect(CacheControlInfo(value: "no-cache") == nil)
        #expect(CacheControlInfo(value: "max-age=0") == nil)
        #expect(CacheControlInfo(value: "max-age=abc") == nil)
    }

    @Test("init(urlResponse:) reads the Cache-Control header")
    func parseFromResponse() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Cache-Control": "max-age=300"]
        )!
        #expect(CacheControlInfo(urlResponse: response)?.maxAge == 300)

        let noHeader = HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
        )!
        #expect(CacheControlInfo(urlResponse: noHeader) == nil)
    }

    @Test("canResume reflects whether resumeDate (dateCreated + maxAge) has passed")
    func canResume() {
        // Created in 1970 with a 60s max age → long past → can resume.
        let past = CacheControlInfo(dateCreated: Date(timeIntervalSince1970: 0), maxAge: 60)
        #expect(past.canResume)
        #expect(past.canResume(maxMaxAge: 30)) // min(30, 60) still long past

        // Created now with a 1-hour max age → not yet → cannot resume.
        let fresh = CacheControlInfo(dateCreated: Date(), maxAge: 3600)
        #expect(!fresh.canResume)
    }
}
