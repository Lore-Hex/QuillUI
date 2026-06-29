#if os(Linux)
import Foundation
import QuillFoundation
import Testing

@Suite("QuillFoundation Objective-C runtime Linux shims")
struct ObjCRuntimeLinuxTests {
    @Test("class_getInstanceMethod returns an inert method handle for swizzle setup")
    func classGetInstanceMethodReturnsInertMethodHandle() {
        let original = class_getInstanceMethod(ObjCRuntimeProbe.self, Selector("original"))
        let replacement = class_getInstanceMethod(ObjCRuntimeProbe.self, Selector("replacement"))

        #expect(original != nil)
        #expect(replacement != nil)

        method_exchangeImplementations(original, replacement)
    }
}

private final class ObjCRuntimeProbe: NSObject {}
#endif
