#if os(Linux)
import Foundation

// Compile-only Linux clones of Apple's KVO + ObjC associated-object APIs, which
// swift-corelibs-foundation lacks (both need the Objective-C runtime). These let
// verbatim Apple source that uses `observe(\.keyPath)` and `objc_*AssociatedObject`
// COMPILE on Linux. They do NOT implement real observation — the change handler
// never fires, and the associated-object store is a leaky side-table (no dealloc
// hook on Linux); a later runtime layer would make these live. QuillFoundation
// `@_exported import`s Foundation, so a target that links QuillFoundation and
// whose source `import`s QuillFoundation sees these alongside real Foundation.

public struct NSKeyValueObservingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let new = NSKeyValueObservingOptions(rawValue: 0x01)
    public static let old = NSKeyValueObservingOptions(rawValue: 0x02)
    public static let initial = NSKeyValueObservingOptions(rawValue: 0x04)
    public static let prior = NSKeyValueObservingOptions(rawValue: 0x08)
}

public enum NSKeyValueChange: UInt, Sendable {
    case setting = 1
    case insertion = 2
    case removal = 3
    case replacement = 4
}

/// Mirrors `NSKeyValueObservedChange<Value>` — the change payload handed to an
/// observer. On Linux it's only ever constructed by a (future) runtime layer.
public struct NSKeyValueObservedChange<Value> {
    public let kind: NSKeyValueChange
    public let newValue: Value?
    public let oldValue: Value?
    public let indexes: IndexSet?
    public let isPrior: Bool
    public init(kind: NSKeyValueChange = .setting, newValue: Value? = nil,
                oldValue: Value? = nil, indexes: IndexSet? = nil, isPrior: Bool = false) {
        self.kind = kind; self.newValue = newValue; self.oldValue = oldValue
        self.indexes = indexes; self.isPrior = isPrior
    }
}

/// Mirrors `NSKeyValueObservation` — the token returned by `observe`. Storing it
/// keeps the observation alive; dropping/`invalidate()`ing it stops observing.
public final class NSKeyValueObservation: NSObject {
    public func invalidate() {}
}

public extension NSObjectProtocol where Self: NSObject {
    /// Compile-only clone of KVO's block-based `observe`. Returns an inert token;
    /// the change handler never fires on Linux (real KVO is a runtime concern).
    func observe<Value>(_ keyPath: KeyPath<Self, Value>,
                        options: NSKeyValueObservingOptions = [],
                        changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void) -> NSKeyValueObservation {
        NSKeyValueObservation()
    }
}

// ObjC associated objects — a leaky side-table emulation (compile-only; no
// dealloc hook on Linux to clear entries). Keyed by object identity + raw key.
public enum objc_AssociationPolicy: UInt {
    case OBJC_ASSOCIATION_ASSIGN = 0
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC = 1
    case OBJC_ASSOCIATION_COPY_NONATOMIC = 3
    case OBJC_ASSOCIATION_RETAIN = 769
    case OBJC_ASSOCIATION_COPY = 771
}

private final class QuillAssociatedObjectStore: @unchecked Sendable {
    static let shared = QuillAssociatedObjectStore()
    private let lock = NSLock()
    private var store: [ObjectIdentifier: [UnsafeRawPointer: Any]] = [:]
    func set(_ obj: AnyObject, _ key: UnsafeRawPointer, _ value: Any?) {
        lock.lock(); defer { lock.unlock() }
        let id = ObjectIdentifier(obj)
        if let value { store[id, default: [:]][key] = value } else { store[id]?[key] = nil }
    }
    func get(_ obj: AnyObject, _ key: UnsafeRawPointer) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return store[ObjectIdentifier(obj)]?[key]
    }
}

public func objc_setAssociatedObject(_ object: Any, _ key: UnsafeRawPointer, _ value: Any?, _ policy: objc_AssociationPolicy) {
    QuillAssociatedObjectStore.shared.set(object as AnyObject, key, value)
}

public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? {
    QuillAssociatedObjectStore.shared.get(object as AnyObject, key)
}
#endif
