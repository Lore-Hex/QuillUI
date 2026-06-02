// Linux-only polyfill for `os.OSAllocatedUnfairLock<T>` — Apple's
// shipping a generic state-protecting unfair lock since iOS 16.
// The vendored upstream Ranchero-Software/NetNewsWire targets
// (Articles' AuthorCache + ArticleStatus, RSWeb's caches) use
// OSAllocatedUnfairLock directly via `import os`.
//
// On Apple platforms `import os` resolves to the system framework
// and Apple's OSAllocatedUnfairLock is linked in automatically.
// On Linux, swift-corelibs-foundation has no `os` framework, and
// the in-tree Sources/osShim Quill target / library product is
// gated `#if os(Linux)` such that macOS-built target dep lists
// can't reference it conditionally (the same chicken-and-egg
// CoreGraphics + Network shim hit). So the simplest fix is to
// ship the type from QuillRSCoreShim itself (Foundation-only),
// available only on non-Apple where Apple's symbol is absent.
//
// Surface matches Apple's: init(initialState:), withLock { state in ... },
// withLockUnchecked { state in ... }. NSLock-backed — gives up
// the unfair-lock micro-optimization but matches semantics for
// the cache / counter workloads upstream uses it for.

#if !canImport(Darwin)
import Foundation

public final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private var state: State
    private let lock = NSLock()

    public init(initialState: State) {
        self.state = initialState
    }

    public func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }

    public func withLockUnchecked<R>(_ body: (inout State) throws -> R) rethrows -> R {
        try withLock(body)
    }
}
#endif
