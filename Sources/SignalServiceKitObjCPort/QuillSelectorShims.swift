//
// SignalServiceKit selector-API compile shims for QuillOS (Track B).
//
// swift-corelibs-foundation on Linux has no Objective-C runtime, so the
// `Selector` type (an ObjectiveC-overlay type on Apple) and the selector-based
// Cocoa observation APIs are absent. The lowering pass rewrote `#selector(foo)`
// to the opaque token `Selector("foo")`. Defining `Selector` here — SAME MODULE
// as SignalServiceKit — means every SSK file resolves it with no extra import,
// and the no-op `addObserver` overload fixes the "extra argument 'selector'"
// calls that swift-corelibs-foundation's NotificationCenter does not provide.
//
// RUNTIME: selector-dispatched observers do NOT fire — a durable lowering pass
// should rewrite them to closures; tracked separately.
//
import Foundation

/// Opaque selector token (Apple's `Selector` lives in the ObjectiveC overlay,
/// which is absent on Linux). Mirrors QuillFoundation's shim.
public struct Selector: Hashable, Sendable {
    public let name: String
    public init(_ name: String = "") { self.name = name }
}

public extension NotificationCenter {
    func addObserver(_ observer: Any,
                     selector aSelector: Selector,
                     name aName: NSNotification.Name?,
                     object anObject: Any?) {
        // Selector dispatch is unavailable on Linux; no-op (deferred).
    }
}
