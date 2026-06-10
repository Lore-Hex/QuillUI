#if os(Linux)
import Foundation
import Testing
// @testable: the objc associated-object clones are deliberately internal
// (ObjCAssoc owns the public API; see KeyValueObservingLinuxClone.swift).
@testable import QuillFoundation

/// Covers the Linux KVO + ObjC associated-object compile-clones in
/// QuillFoundation (KeyValueObservingLinuxClone.swift). They let verbatim Apple
/// source (WireGuard's TunnelsManager/TunnelContainer) compile on Linux. KVO is
/// compile-only (the handler never fires); associated objects DO round-trip via
/// a side-table.
@Suite("QuillFoundation KVO + objc associated-object Linux clones")
struct KeyValueObservingCloneTests {
    final class Obj: NSObject {
        var x: Int = 0
        static var assocKey = 0
    }

    @Test("observe(\\.kp) returns an invalidatable token (compile-only on Linux)")
    func observeReturnsToken() {
        let o = Obj()
        let token = o.observe(\.x, options: [.new, .old]) { _, _ in }
        token.invalidate() // no-op; handler never fires on Linux
        #expect(NSKeyValueObservingOptions.new.rawValue == 0x01)
        #expect(NSKeyValueObservingOptions.old.rawValue == 0x02)
    }

    @Test("objc_set/getAssociatedObject round-trips via the side-table")
    func associatedObjectRoundTrip() {
        let o = Obj()
        objc_setAssociatedObject(o, &Obj.assocKey, "hello", .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #expect(objc_getAssociatedObject(o, &Obj.assocKey) as? String == "hello")
        // Clearing with nil removes it.
        objc_setAssociatedObject(o, &Obj.assocKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #expect(objc_getAssociatedObject(o, &Obj.assocKey) == nil)
    }
}
#endif
