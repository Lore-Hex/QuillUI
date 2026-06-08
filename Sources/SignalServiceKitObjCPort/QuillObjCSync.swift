//
// SignalServiceKit ObjC-runtime port for QuillOS (Track B).
//
// `objc_sync_enter` / `objc_sync_exit` are the Objective-C runtime primitives the
// compiler lowers `@synchronized(obj)` into — recursive mutual exclusion keyed by
// object identity. swift-corelibs-foundation on Linux has no Objective-C runtime,
// so these symbols are absent ("cannot find 'objc_sync_enter' in scope").
//
// SSK's ModelReadCache.performSync relies on them and documents that "our locking
// mechanism needs to be re-entrant", so this is a FAITHFUL port (not a stub): each
// synchronized object is mapped to a process-global NSRecursiveLock keyed by its
// identity, exactly preserving the recursive-lock semantics the real runtime
// provides. The lock table is never evicted (like the real runtime's global sync
// table); SSK only synchronizes on long-lived singletons, so the bounded set of
// entries is negligible.
//
import Foundation

private final class QuillObjCSyncTable {
    static let shared = QuillObjCSyncTable()
    private let master = NSLock()
    private var locks: [ObjectIdentifier: NSRecursiveLock] = [:]

    func lock(for obj: AnyObject) -> NSRecursiveLock {
        let id = ObjectIdentifier(obj)
        master.lock()
        defer { master.unlock() }
        if let existing = locks[id] {
            return existing
        }
        let created = NSRecursiveLock()
        locks[id] = created
        return created
    }
}

// Returns OBJC_SYNC_SUCCESS (0), matching the runtime's success path. `@synchronized`
// is only meaningful on class instances, so `obj as AnyObject` yields a stable
// identity for the real call sites (e.g. ModelReadCache passing `self`).
@discardableResult
public func objc_sync_enter(_ obj: Any) -> Int32 {
    QuillObjCSyncTable.shared.lock(for: obj as AnyObject).lock()
    return 0
}

@discardableResult
public func objc_sync_exit(_ obj: Any) -> Int32 {
    QuillObjCSyncTable.shared.lock(for: obj as AnyObject).unlock()
    return 0
}
