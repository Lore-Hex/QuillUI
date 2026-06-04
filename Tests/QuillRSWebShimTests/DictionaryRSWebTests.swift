import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `[String: String].urlQueryString` — builds a
/// percent-encoded URL query string (or nil when empty).
@Suite("RSWeb clone — Dictionary.urlQueryString")
struct DictionaryRSWebTests {

    @Test("a single pair becomes key=value")
    func singlePair() {
        #expect(["foo": "bar"].urlQueryString == "foo=bar")
    }

    @Test("values are percent-encoded")
    func percentEncoded() {
        #expect(["a": "some thing"].urlQueryString == "a=some%20thing")
    }

    @Test("an empty dictionary yields nil")
    func empty() {
        #expect([String: String]().urlQueryString == nil)
    }

    @Test("multiple pairs all appear (order is unspecified)")
    func multiplePairs() {
        let query = ["a": "1", "b": "2"].urlQueryString
        #expect(query != nil)
        #expect(query!.contains("a=1"))
        #expect(query!.contains("b=2"))
        #expect(query!.contains("&"))
    }
}
