import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `HTTPConditionalGetInfo`: reads Last-Modified / Etag
/// from a response (or header dict), and writes If-Modified-Since / If-None-Match
/// onto a request (with the 2038 last-modified guard).
@Suite("RSWeb clone — HTTPConditionalGetInfo")
struct HTTPConditionalGetInfoTests {

    @Test("init requires at least one of lastModified / etag")
    func requiresOne() {
        #expect(HTTPConditionalGetInfo(lastModified: nil, etag: nil) == nil)
        #expect(HTTPConditionalGetInfo(lastModified: "x", etag: nil) != nil)
        #expect(HTTPConditionalGetInfo(lastModified: nil, etag: "y") != nil)
    }

    @Test("reads Last-Modified and Etag from an HTTPURLResponse")
    func fromResponse() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT", "Etag": "\"abc\""]
        )!
        let info = HTTPConditionalGetInfo(urlResponse: response)
        #expect(info?.lastModified == "Wed, 21 Oct 2015 07:28:00 GMT")
        #expect(info?.etag == "\"abc\"")

        let none = HTTPURLResponse(
            url: URL(string: "https://example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
        )!
        #expect(HTTPConditionalGetInfo(urlResponse: none) == nil)
    }

    @Test("reads from a header dictionary")
    func fromHeaders() {
        let info = HTTPConditionalGetInfo(headers: ["Last-Modified": "Wed, 21 Oct 2015 07:28:00 GMT", "Etag": "\"abc\""])
        #expect(info?.lastModified == "Wed, 21 Oct 2015 07:28:00 GMT")
        #expect(info?.etag == "\"abc\"")
    }

    @Test("writes If-Modified-Since / If-None-Match onto a request")
    func addsRequestHeaders() {
        let info = HTTPConditionalGetInfo(lastModified: "Wed, 21 Oct 2015 07:28:00 GMT", etag: "\"abc\"")!
        var request = URLRequest(url: URL(string: "https://example.com/feed")!)
        info.addRequestHeadersToURLRequest(&request)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 21 Oct 2015 07:28:00 GMT")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
    }

    @Test("skips a 2038 Last-Modified (the documented bug guard)")
    func skips2038() {
        let info = HTTPConditionalGetInfo(lastModified: "Tue, 19 Jan 2038 03:14:07 GMT", etag: nil)!
        var request = URLRequest(url: URL(string: "https://example.com/feed")!)
        info.addRequestHeadersToURLRequest(&request)
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }
}
