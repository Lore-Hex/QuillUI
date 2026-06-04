import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `HTTPLinkPagingInfo`: parsing the (NNW-cased "Links")
/// HTTP Link header into next/last page URLs.
@Suite("RSWeb clone — HTTPLinkPagingInfo")
struct HTTPLinkPagingInfoTests {

    @Test("the direct initializer stores next/last page")
    func directInit() {
        let info = HTTPLinkPagingInfo(nextPage: "n", lastPage: "l")
        #expect(info.nextPage == "n")
        #expect(info.lastPage == "l")
    }

    @Test("parses next and last page from the Link header")
    func parseFromResponse() {
        let header = "<https://api.example.com/feed?page=2>; rel=\"next\", "
            + "<https://api.example.com/feed?page=9>; rel=\"last\""
        // Note: RSWeb reads HTTPResponseHeader.link, which is the string "Links".
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Links": header]
        )!
        let info = HTTPLinkPagingInfo(urlResponse: response)
        #expect(info.nextPage == "https://api.example.com/feed?page=2")
        #expect(info.lastPage == "https://api.example.com/feed?page=9")
    }

    @Test("no Link header yields nil pages")
    func noHeader() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/feed")!,
            statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:]
        )!
        let info = HTTPLinkPagingInfo(urlResponse: response)
        #expect(info.nextPage == nil)
        #expect(info.lastPage == nil)
    }
}
