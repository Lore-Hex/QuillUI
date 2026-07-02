import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import SwiftUI

/// Guards the button activation gate (#502): one physical click reaches the
/// action through redundant press-side paths (gesture, legacy capture, root
/// fallback) plus GtkButton's release-side `clicked` signal, and must fire
/// the action exactly once even when a loaded machine stretches the
/// press→release gap past any wall-clock dedup window.
@Suite("GTK button activation gate", .serialized)
@MainActor
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
        #expect(!gate.fire(.clicked, at: 5.0), "clicked may consume at most one armed press")
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

    @Test("activating a rendered Button fires the action exactly once")
    func activatingRenderedButtonFiresActionOnce() throws {
        if gtk_is_initialized() == 0, gtk_init_check() == 0 {
            return
        }

        var fireCount = 0
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") { fireCount += 1 }
        ))
        let button = try firstGTKButton(in: widget)

        // Keyboard-style activation emits `clicked` with no pointer press.
        #expect(gtk_widget_activate(button) != 0, "GtkButton should be activatable")
        drainGTKMainContext(maxIterations: 100)

        #expect(fireCount == 1, "one activation must invoke the action exactly once")
    }
}

private func firstGTKButton(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkButton" {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = try? firstGTKButton(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    struct MissingGTKButton: Error {}
    throw MissingGTKButton()
}

private func drainGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
#endif
