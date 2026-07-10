import Testing

#if os(Linux)
@testable import BackendGTK4

/// Guards the button activation gate (#502): one physical click reaches the
/// action through redundant press-side paths (gesture, legacy capture, root
/// fallback) plus GtkButton's release-side `clicked` signal, and must fire
/// the action exactly once even when a loaded machine stretches the
/// press→release gap past any wall-clock dedup window.
///
/// The gate is exercised as a value here — no widgets. GTK widget creation
/// is thread-affine and swift-testing MainActor jobs are not guaranteed to
/// run on GTK's home thread, so end-to-end click behavior stays covered by
/// the CI interaction smokes (which is where #502 was caught).
@Suite("GTK button activation gate", .serialized)
struct GTKButtonActivationTests {
    /// `#expect` cannot expand a mutating call on a `var`, so drive the
    /// value-type gate through a reference-type shell.
    final class Gate {
        private var gate = GTKButtonActivationGate()

        func fire(_ phase: GTKButtonActivationGate.Phase, at now: Double) -> Bool {
            gate.shouldFire(phase, now: now)
        }
    }

    @Test("press then late clicked fires once")
    func pressThenLateClickedFiresOnce() {
        let gate = Gate()
        #expect(gate.fire(.pointerPress, at: 0))
        // The #502 CI failure: clicked dispatched >80ms after the press
        // paths on a loaded runner must NOT fire a second time.
        #expect(!gate.fire(.clicked, at: 0.2))
    }

    @Test("press then fast clicked fires once")
    func pressThenFastClickedFiresOnce() {
        let gate = Gate()
        #expect(gate.fire(.pointerPress, at: 0))
        #expect(!gate.fire(.clicked, at: 0.01))
    }

    @Test("redundant press paths fire once")
    func redundantPressPathsFireOnce() {
        let gate = Gate()
        // gesture + legacy + root-fallback dispatch within one main-loop
        // iteration; the wall-clock window still dedups those.
        #expect(gate.fire(.pointerPress, at: 0))
        #expect(!gate.fire(.pointerPress, at: 0.001))
        #expect(!gate.fire(.pointerPress, at: 0.002))
        #expect(!gate.fire(.clicked, at: 0.2))
    }

    @Test("keyboard clicked without press fires")
    func keyboardClickedWithoutPressFires() {
        let gate = Gate()
        #expect(gate.fire(.clicked, at: 1.0))
    }

    @Test("rapid keyboard clicked dedups within window")
    func rapidKeyboardClickedDedupsWithinWindow() {
        let gate = Gate()
        #expect(gate.fire(.clicked, at: 0))
        #expect(!gate.fire(.clicked, at: 0.01))
        #expect(gate.fire(.clicked, at: 0.5))
    }

    @Test("two separate clicks fire twice")
    func twoSeparateClicksFireTwice() {
        let gate = Gate()
        #expect(gate.fire(.pointerPress, at: 0))
        #expect(!gate.fire(.clicked, at: 0.05))
        #expect(gate.fire(.pointerPress, at: 0.5))
        #expect(!gate.fire(.clicked, at: 0.55))
    }

    @Test("abandoned press does not swallow the next click")
    func abandonedPressDoesNotSwallowNextClick() {
        let gate = Gate()
        // Press, drag off the button, release elsewhere: no clicked arrives.
        #expect(gate.fire(.pointerPress, at: 0))
        // The next full click still fires exactly once.
        #expect(gate.fire(.pointerPress, at: 1.0))
        #expect(!gate.fire(.clicked, at: 1.05))
    }
}
#endif
