//
//  OSUnfairLockShim.swift
//  QuillRSCoreShim
//
//  Linux polyfill for `os.OSAllocatedUnfairLock(initialState:)`, the lock the
//  vendored RSCore `Cache.swift` uses. On Darwin the real `os` module
//  provides it (Cache.swift conditionally imports os there); QuillRSCoreShim
//  is dependency-free, so the Linux surface lives in-module. NSLock instead
//  of an unfair lock: the semantics Cache needs are mutual exclusion around
//  its state, not priority-donation behavior.
//

#if !canImport(Darwin)
import Foundation

// Internal on purpose: modules that import both QuillRSCoreShim and the os
// shim (e.g. QuillArticles) must keep resolving the os shim's lock without
// ambiguity; this copy exists only for QuillRSCoreShim's own vendored files.
final class OSAllocatedUnfairLock<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(initialState: State) {
        self.state = initialState
    }

    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}

extension OSAllocatedUnfairLock where State == Void {
    convenience init() {
        self.init(initialState: ())
    }

    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        try withLock { (_: inout State) in try body() }
    }
}
#endif
