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

    @Test("Foundation lowering is idempotent")
    func idempotent() {
        let source = """
        let descriptor = NSSortDescriptor(key: "name", ascending: true)
        let selectedKey = sortDescriptor?.key ?? "name"
        """

        let first = FoundationLowering().lower(source)
        let second = FoundationLowering().lower(first)
        #expect(first == second)
        #expect(first.contains("NSSortDescriptor.quillKey(\"name\", ascending: true)"))
        #expect(first.contains("sortDescriptor?.quillKey ?? \"name\""))
    }
}
