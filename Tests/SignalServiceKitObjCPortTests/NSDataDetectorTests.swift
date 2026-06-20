import Foundation
import SignalServiceKit
import Testing

@Suite("SignalServiceKit Linux NSDataDetector shim")
struct NSDataDetectorTests {
    private let linkCheckingType = UInt64(1) << 5

    @Test("detects HTTPS links with URL and trimmed range")
    func detectsHTTPSLinks() throws {
        let detector = try NSDataDetector(types: linkCheckingType)
        let text = "Open https://signal.org/blog, please."

        let matches = detector.matches(in: text, range: Self.fullRange(of: text))

        #expect(matches.count == 1)
        #expect(matches[0].resultType.rawValue == linkCheckingType)
        #expect((text as NSString).substring(with: matches[0].range) == "https://signal.org/blog")
        #expect(matches[0].url?.absoluteString == "https://signal.org/blog")
    }

    @Test("detects email addresses as mailto links")
    func detectsEmailAddresses() throws {
        let detector = try NSDataDetector(types: linkCheckingType)
        let text = "Contact alice@example.com for details"

        let match = try #require(detector.matches(in: text, range: Self.fullRange(of: text)).first)

        #expect((text as NSString).substring(with: match.range) == "alice@example.com")
        #expect(match.url?.absoluteString == "mailto:alice@example.com")
    }

    @Test("honors search range")
    func honorsSearchRange() throws {
        let detector = try NSDataDetector(types: linkCheckingType)
        let text = "First https://one.example and second https://two.example/path"
        let secondStart = (text as NSString).range(of: "https://two.example/path")

        let matches = detector.matches(in: text, range: secondStart)

        #expect(matches.count == 1)
        #expect(matches[0].range == secondStart)
        #expect(matches[0].url?.absoluteString == "https://two.example/path")
    }

    @Test("enumeration supports stop pointer")
    func enumerationSupportsStop() throws {
        let detector = try NSDataDetector(types: linkCheckingType)
        let text = "https://one.example https://two.example"
        var count = 0

        detector.enumerateMatches(in: text, range: Self.fullRange(of: text)) { _, _, stop in
            count += 1
            stop.pointee = true
        }

        #expect(count == 1)
    }

    @Test("non-link detector returns no matches")
    func nonLinkDetectorReturnsNoMatches() throws {
        let detector = try NSDataDetector(types: 0)
        let text = "https://signal.org"

        #expect(detector.matches(in: text, range: Self.fullRange(of: text)).isEmpty)
    }

    private static func fullRange(of text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }
}
