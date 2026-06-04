import Foundation
import Testing
@testable import QuillRSCoreShim

/// A stand-in for the real OPML-exportable model types (Feed/Folder). Records
/// the `allowCustomAttributes` it was called with so the default-impl forwarder
/// can be pinned.
@MainActor private final class StubOPML: OPMLRepresentable {
    private(set) var lastIndent: Int?
    private(set) var lastAllowCustom: Bool?

    func OPMLString(indentLevel: Int, allowCustomAttributes: Bool) -> String {
        lastIndent = indentLevel
        lastAllowCustom = allowCustomAttributes
        return "indent=\(indentLevel) custom=\(allowCustomAttributes)"
    }
}

/// Pins the vendored RSCore `OPMLRepresentable` default-impl forwarder:
/// `OPMLString(indentLevel:)` calls the full method with
/// `allowCustomAttributes: false`.
@Suite("QuillRSCoreShim — OPMLRepresentable")
@MainActor
struct OPMLRepresentableTests {

    @Test("the indentLevel-only default forwards with allowCustomAttributes false")
    func defaultForwardsCustomFalse() {
        let stub = StubOPML()
        let result = stub.OPMLString(indentLevel: 2)
        #expect(stub.lastIndent == 2)
        #expect(stub.lastAllowCustom == false)
        #expect(result == "indent=2 custom=false")
    }

    @Test("the full method passes allowCustomAttributes through")
    func fullMethodPassesCustom() {
        let stub = StubOPML()
        _ = stub.OPMLString(indentLevel: 1, allowCustomAttributes: true)
        #expect(stub.lastIndent == 1)
        #expect(stub.lastAllowCustom == true)
    }
}
