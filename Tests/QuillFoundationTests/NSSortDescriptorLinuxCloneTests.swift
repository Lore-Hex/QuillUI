#if os(Linux)
import Foundation
import QuillFoundation
import Testing

@Suite("NSSortDescriptor Linux compatibility")
struct NSSortDescriptorLinuxCloneTests {
    @Test("Quill string-key adapter preserves key metadata and ascending flag")
    func quillKeyAdapterPreservesMetadata() {
        let descriptor = NSSortDescriptor.quillKey("name", ascending: false)

        #expect(descriptor.quillKey == "name")
        #expect(!descriptor.ascending)
    }

    @Test("Typed swift-corelibs descriptors do not report Quill string keys")
    func typedKeyPathDescriptorHasNoQuillKey() {
        struct Row {
            let name: String
        }

        let descriptor = NSSortDescriptor(keyPath: \Row.name, ascending: true)

        #expect(descriptor.quillKey == nil)
        #expect(descriptor.ascending)
    }
}
#endif
