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

    @Test("NSError empty initializer lowers to the designated Foundation initializer")
    func nserrorEmptyInitializerLowers() {
        let source = """
        throw NSError()
        let error = NSError(domain: "Existing", code: 1)
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("throw NSError(domain: \"QuillFoundation.NSError\", code: 0, userInfo: nil)"))
        #expect(lowered.contains("let error = NSError(domain: \"Existing\", code: 1)"))
        #expect(!lowered.contains("NSError()"))
    }

    @Test("Formatter edit-validation overrides lower for swift-corelibs Foundation")
    func formatterEditValidationOverridesLower() {
        let source = """
        final class RegexFormatter: Formatter {
            override func string(for obj: Any?) -> String? { nil }
            override func getObjectValue(
                _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                for string: String,
                errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
            ) -> Bool { true }

            override open func isPartialStringValid(
                _ partialString: String,
                newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
            ) -> Bool { true }
        }
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("override func string(for obj: Any?) -> String? { nil }"))
        #expect(lowered.contains("func getObjectValue(\n"))
        #expect(lowered.contains("open func isPartialStringValid(\n"))
        #expect(!lowered.contains("override func getObjectValue"))
        #expect(!lowered.contains("override open func isPartialStringValid"))
    }

    @Test("Linux Foundation compatibility lowers CFURL, qualified networking types, and ProcessEnv imports")
    func linuxFoundationCompatibilityLowers() {
        let source = """
        import Foundation

        let request: Foundation.URLRequest? = nil
        let response: Foundation.HTTPURLResponse? = nil
        let urls = UnsafeMutablePointer<Unmanaged<CFURL>?>.allocate(capacity: 1)
        let parameters: Process.ExecutionParameters? = nil
        """

        let lowered = FoundationLowering().lower(source)
        #expect(lowered.contains("import Foundation\nimport ProcessEnv"))
        #expect(lowered.contains("let request: URLRequest? = nil"))
        #expect(lowered.contains("let response: HTTPURLResponse? = nil"))
        #expect(lowered.contains("UnsafeMutablePointer<Unmanaged<NSURL>?>.allocate"))
        #expect(lowered.contains("let parameters: Process.ExecutionParameters? = nil"))
        #expect(!lowered.contains("Foundation.URLRequest"))
        #expect(!lowered.contains("Unmanaged<CFURL>"))
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
