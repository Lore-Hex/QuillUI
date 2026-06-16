#if os(Linux)
import Foundation

/// Pre-Concurrency-faithful `Timer` factory for the AppKit-app compatibility path.
///
/// swift-corelibs-Foundation declares `Timer.init(timeInterval:repeats:block:)`
/// with a hard `@Sendable` block. That forces any closure passed to it to be
/// `@Sendable` (nonisolated), so verbatim AppKit-app source like
///
///     Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateUI() }
///
/// — where `updateUI()` is `@MainActor` (NSViewController is `@MainActor`) —
/// fails to compile on Linux with *"call to main actor-isolated instance method
/// in a synchronous nonisolated context"*. macOS compiles the same code because
/// its SDK declares the block `@preconcurrency`. Two non-fixes were ruled out by
/// isolated `swiftc` repros: `-strict-concurrency=minimal` does NOT relax a
/// `@Sendable` parameter, and a same-label `Timer` overload is ambiguous at every
/// call site (trailing closures match the last parameter by position, ignoring
/// labels).
///
/// `QuillTimer.make` is a **distinct symbol** (no overload ambiguity) whose block
/// is **non-`@Sendable`**, so a closure formed in a `@MainActor` context inherits
/// `@MainActor` and may call `@MainActor` methods — exactly how AppKit apps drive
/// a `Timer` on the main run loop. It returns a real `Timer`, so `.invalidate()`
/// and `RunLoop.main.add(_:forMode:)` keep working. `AppKitLowering` rewrites
/// `Timer(timeInterval:repeats:){…}` call sites to `QuillTimer.make(…){…}` on the
/// Linux compat build (macOS keeps verbatim `Timer`).
public enum QuillTimer {
    public static func make(timeInterval interval: TimeInterval, repeats: Bool,
                            block: @escaping (Timer) -> Void) -> Timer {
        // Box the non-Sendable user block so the inner closure handed to corelibs'
        // @Sendable Timer.init captures only Sendable state. The block is invoked
        // on whatever run loop the Timer is scheduled in (the app uses .main).
        let box = QuillTimerBlockBox(block)
        return Timer(timeInterval: interval, repeats: repeats, block: { timer in
            box.value(timer)
        })
    }

    /// `Timer.scheduledTimer(withTimeInterval:repeats:block:)` counterpart — same
    /// non-`@Sendable` block trick, but schedules on the current run loop (`.main`
    /// at SignalUI's call sites). `AppKitLowering` rewrites
    /// `Timer.scheduledTimer(withTimeInterval:repeats:){…}` → `QuillTimer.scheduledTimer(…)`.
    @discardableResult
    public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool,
                                      block: @escaping (Timer) -> Void) -> Timer {
        let box = QuillTimerBlockBox(block)
        return Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: { timer in
            box.value(timer)
        })
    }
}

/// Carries the non-Sendable user block across corelibs' `@Sendable` `Timer.init`
/// boundary. `@unchecked Sendable` because the block runs on the timer's run loop
/// (the main run loop in AppKit usage), not concurrently from multiple threads.
private final class QuillTimerBlockBox: @unchecked Sendable {
    let value: (Timer) -> Void
    init(_ value: @escaping (Timer) -> Void) { self.value = value }
}
#endif
