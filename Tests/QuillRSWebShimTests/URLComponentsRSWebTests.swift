import Foundation
import Testing
@testable import RSWeb

/// Pins the vendored RSWeb `URLComponents.enhancedPercentEncodedQuery` — the
/// RFC-3986 `+`-encoding query builder (spaces become `+`, reserved chars are
/// percent-encoded).
@Suite("RSWeb clone — URLComponents.enhancedPercentEncodedQuery")
struct URLComponentsRSWebTests {

    private func query(_ items: [(String, String)]) -> String? {
        var components = URLComponents()
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.enhancedPercentEncodedQuery
    }

    @Test("spaces become + (not %20)")
    func spaceBecomesPlus() {
        #expect(query([("q", "hello world")]) == "q=hello+world")
    }

    @Test("reserved characters are percent-encoded")
    func reservedEncoded() {
        #expect(query([("q", "a&b")]) == "q=a%26b")
    }

    @Test("no query items yields nil")
    func emptyNil() {
        #expect(URLComponents().enhancedPercentEncodedQuery == nil)
    }
}
