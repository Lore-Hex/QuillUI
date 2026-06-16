import Foundation
import Testing
@testable import QuillSourceLowering

@Suite("Foundation source lowering")
struct FoundationLoweringTests {
    @Test("NSSortDescriptor string-key construction lowers to Quill adapter")
    func sortDescriptorKeyInitLowers() {
        let source = """
        let descriptor = NSSortDescriptor(key: "name", ascending: ascending)
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("NSSortDescriptor.quillKey(\"name\", ascending: ascending)"))
        #expect(!lowered.contains("NSSortDescriptor(key:"))
    }

    @Test("NSSortDescriptor key access lowers only when the base names a sort descriptor")
    func sortDescriptorKeyAccessLowersConservatively() {
        let source = """
        let selectedKey = sortDescriptor?.key ?? "name"
        let untouched = dictionary.key
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("sortDescriptor?.quillKey ?? \"name\""))
        #expect(lowered.contains("dictionary.key"))
    }

    @Test("NSSortDescriptor unsupported initializer overloads are left alone")
    func unsupportedSortDescriptorInitializersArePreserved() {
        let source = """
        let descriptor = NSSortDescriptor(key: "name", ascending: true, selector: selector)
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("NSSortDescriptor(key: \"name\", ascending: true, selector: selector)"))
        #expect(!lowered.contains("quillKey"))
    }

    @Test("NSTextCheckingResult CheckingType static members lower to raw values")
    func textCheckingResultStaticMembersLower() {
        let source = """
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let transit = NSTextCheckingResult.CheckingType.transitInformation
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("NSDataDetector(types: NSTextCheckingResult.CheckingType(rawValue: 32).rawValue)"))
        #expect(lowered.contains("let transit = NSTextCheckingResult.CheckingType(rawValue: 4096)"))
        #expect(!lowered.contains("CheckingType.link"))
        #expect(!lowered.contains("CheckingType.transitInformation"))
    }

    @Test("NSTextCheckingResult CheckingType inferred inserts lower only for checking-type variables")
    func textCheckingResultInferredInsertsLowerConservatively() {
        let source = """
        var checkingTypes = NSTextCheckingResult.CheckingType()
        checkingTypes.insert(.link)
        checkingTypes.insert(.address)
        checkingTypes.insert(.phoneNumber)
        checkingTypes.insert(.date)
        unrelated.insert(.link)
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("checkingTypes.insert(NSTextCheckingResult.CheckingType(rawValue: 32))"))
        #expect(lowered.contains("checkingTypes.insert(NSTextCheckingResult.CheckingType(rawValue: 16))"))
        #expect(lowered.contains("checkingTypes.insert(NSTextCheckingResult.CheckingType(rawValue: 2048))"))
        #expect(lowered.contains("checkingTypes.insert(NSTextCheckingResult.CheckingType(rawValue: 8))"))
        #expect(lowered.contains("unrelated.insert(.link)"))
    }

    @Test("Foundation lowering is idempotent")
    func idempotent() {
        let source = """
        let descriptor = NSSortDescriptor(key: "name", ascending: true)
        let selectedKey = sortDescriptor?.key ?? "name"
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var checkingTypes = NSTextCheckingResult.CheckingType()
        checkingTypes.insert(.phoneNumber)
        """

        let first = FoundationLowering().lower(source)
        let second = FoundationLowering().lower(first)
        #expect(first == second)
        #expect(first.contains("NSSortDescriptor.quillKey(\"name\", ascending: true)"))
        #expect(first.contains("sortDescriptor?.quillKey ?? \"name\""))
        #expect(first.contains("NSTextCheckingResult.CheckingType(rawValue: 32).rawValue"))
        #expect(first.contains("checkingTypes.insert(NSTextCheckingResult.CheckingType(rawValue: 2048))"))
    }
}
