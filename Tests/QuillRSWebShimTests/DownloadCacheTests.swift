import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import QuillRSCoreShim
@testable import RSWeb

/// Pins the vendored RSWeb DownloadCache (the in-memory cache behind real
/// FeedFinder.find()'s downloadUsingCache) and the HTTPResponse429
/// Retry-After bookkeeping.
// `.serialized`: these tests post the GLOBAL `.appDidGoToBackground` /
// `.lowMemory` notifications, and every live `DownloadCache` observes both on
// `NotificationCenter.default` and responds with `removeAll()`. Run in
// parallel (Swift Testing's default), one test's post races another's
// `cache["k"]` read and clears it first. Serializing this suite keeps each
// post scoped to the test that intends it.
@Suite("RSWeb clone — DownloadCache + HTTPResponse429", .serialized)
struct DownloadCacheTests {

    @Test("add() and subscript round-trip data and nils")
    func roundTrip() {
        let cache = DownloadCache()
        cache.add("https://example.com/feed", data: Data("payload".utf8), response: nil)
        #expect(cache["https://example.com/feed"]?.data == Data("payload".utf8))
        #expect(cache["https://example.com/feed"]?.response == nil)
        #expect(cache["https://example.com/other"] == nil)
    }

    @Test("appDidGoToBackground clears the cache")
    func backgroundClears() {
        let cache = DownloadCache()
        cache.add("k", data: Data([1]), response: nil)
        #expect(cache["k"] != nil)
        NotificationCenter.default.post(name: .appDidGoToBackground, object: nil)
        #expect(cache["k"] == nil)
    }

    @Test("lowMemory clears the cache")
    func lowMemoryClears() {
        let cache = DownloadCache()
        cache.add("k", data: Data([1]), response: nil)
        NotificationCenter.default.post(name: .lowMemory, object: nil)
        #expect(cache["k"] == nil)
    }
}

@Suite("RSWeb clone — HTTPResponse429")
struct HTTPResponse429Tests {

    @Test("host is captured lowercased; host-less URLs are rejected")
    func hostHandling() {
        let response = HTTPResponse429(url: URL(string: "https://API.Example.COM/feed")!, retryAfter: 10)
        #expect(response?.host == "api.example.com")
        #expect(HTTPResponse429(url: URL(string: "file:///tmp/x")!, retryAfter: 10) == nil)
    }

    @Test("resumeDate is dateCreated + retryAfter, and gates canResume")
    func retryAfterGating() {
        let waiting = HTTPResponse429(url: URL(string: "https://example.com/")!, retryAfter: 9999)!
        #expect(waiting.resumeDate == waiting.dateCreated + 9999)
        #expect(!waiting.canResume)

        let elapsed = HTTPResponse429(url: URL(string: "https://example.com/")!, retryAfter: 0)!
        #expect(elapsed.canResume)
    }
}
