import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore `URL` helpers: `percentEncodedEmailAddress` (mailto
/// only) and `encodeSpacesIfNeeded` (space → %20 fallback).
@Suite("QuillRSCoreShim — URL+RSCore")
struct URLRSCoreTests {

    @Test("percentEncodedEmailAddress returns a mailto URL for a mailto link")
    func mailtoEncoded() {
        let url = URL(string: "mailto:foo@bar.com")!
        let encoded = url.percentEncodedEmailAddress
        #expect(encoded != nil)
        #expect(encoded?.scheme == "mailto")
    }

    @Test("percentEncodedEmailAddress is nil for a non-mailto URL")
    func nonMailtoIsNil() {
        let url = URL(string: "https://example.com")!
        #expect(url.percentEncodedEmailAddress == nil)
    }

    @Test("encodeSpacesIfNeeded replaces spaces with %20")
    func encodeSpaces() {
        let url = URL.encodeSpacesIfNeeded("https://example.com/a b c")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("%20") == true)
        #expect(url?.absoluteString.contains(" ") == false)
    }

    @Test("encodeSpacesIfNeeded returns nil for nil or empty input")
    func encodeSpacesNilOrEmpty() {
        #expect(URL.encodeSpacesIfNeeded(nil) == nil)
        #expect(URL.encodeSpacesIfNeeded("") == nil)
    }
}
