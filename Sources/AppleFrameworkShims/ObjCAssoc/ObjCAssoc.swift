//
// QuillOS Linux shim for the handful of Objective-C associated-object APIs that
// SignalServiceKit uses (Util/ObjectRetainer, Network/ProxiedContentDownloader).
// Linux has no Objective-C runtime, so associated objects are backed by a locked
// map keyed by the object's identity plus the association-key pointer.
//
// Deliberately NOT named `ObjectiveC`: a module of that name flips
// `canImport(ObjectiveC)` true package-wide, which breaks Foundation's own
// Selector plumbing and cascades (see QuillUI docs/appkit-reimplementation.md).
//
// NOTE: entries are not cleared on dealloc — a small, bounded leak. ObjectRetainer
// intentionally retains its target, and the URLSessionTask request/segment cache
// is short-lived, so this is acceptable for the source-recompile port.
//
import Foundation

public enum objc_AssociationPolicy {
    case OBJC_ASSOCIATION_ASSIGN
    case OBJC_ASSOCIATION_RETAIN_NONATOMIC
    case OBJC_ASSOCIATION_COPY_NONATOMIC
    case OBJC_ASSOCIATION_RETAIN
    case OBJC_ASSOCIATION_COPY
}

private let _assocLock = NSLock()
private nonisolated(unsafe) var _assoc: [ObjectIdentifier: [UInt: Any]] = [:]

public func objc_setAssociatedObject(
    _ object: Any,
    _ key: UnsafeRawPointer,
    _ value: Any?,
    _ policy: objc_AssociationPolicy
) {
    guard let obj = object as AnyObject? else { return }
    let oid = ObjectIdentifier(obj)
    let k = UInt(bitPattern: key)
    _assocLock.lock(); defer { _assocLock.unlock() }
    if let value {
        _assoc[oid, default: [:]][k] = value
    } else {
        _assoc[oid]?.removeValue(forKey: k)
    }
}

public func objc_getAssociatedObject(_ object: Any, _ key: UnsafeRawPointer) -> Any? {
    guard let obj = object as AnyObject? else { return nil }
    let oid = ObjectIdentifier(obj)
    let k = UInt(bitPattern: key)
    _assocLock.lock(); defer { _assocLock.unlock() }
    return _assoc[oid]?[k]
}
