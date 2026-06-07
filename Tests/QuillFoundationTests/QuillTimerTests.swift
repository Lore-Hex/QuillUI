#if os(Linux)
import Foundation
import Testing
import QuillFoundation

/// Covers `QuillTimer.make` — the pre-Concurrency `Timer` factory that lets
/// verbatim AppKit-app source (e.g. WireGuard's LogViewController) drive a Timer
/// with a closure that calls `@MainActor` methods, which corelibs' hard-`@Sendable`
/// `Timer.init` rejects on Linux. The real proof is that `TimerUsingMainActor`
/// *compiles* (the equivalent plain `Timer(...)` would be a compile error); the
/// runtime checks confirm `make` returns a usable, real `Timer`.
@Suite("QuillFoundation QuillTimer pre-Concurrency factory")
struct QuillTimerTests {

    /// The exact shape WireGuard uses: a `@MainActor` type scheduling a repeating
    /// Timer whose block calls a `@MainActor` method via `[weak self]`.
    @MainActor final class TimerUsingMainActor {
        var ticks = 0
        func onTick() { ticks += 1 } // @MainActor-isolated
        var timer: Timer?
        func start() {
            // Compiles ONLY because QuillTimer.make's block is non-@Sendable, so
            // this closure inherits @MainActor and may call onTick(). The plain
            // `Timer(timeInterval:repeats:){…}` form fails to compile here.
            let t = QuillTimer.make(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.onTick()
            }
            timer = t
            RunLoop.main.add(t, forMode: .common)
        }
    }

    @Test("make returns a real, invalidatable Timer and accepts a @MainActor closure")
    @MainActor func makeReturnsUsableTimer() {
        var fired = false
        let t = QuillTimer.make(timeInterval: 60, repeats: true) { _ in fired = true }
        #expect(t.isValid)   // a freshly created Timer is valid
        #expect(!fired)      // the block has not run synchronously
        t.invalidate()

        // The @MainActor-closure shape compiles and constructs a real Timer.
        let user = TimerUsingMainActor()
        user.start()
        #expect(user.timer != nil)
        user.timer?.invalidate()
    }
}
#endif
