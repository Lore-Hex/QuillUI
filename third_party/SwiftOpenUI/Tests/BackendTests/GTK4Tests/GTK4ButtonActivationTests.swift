import XCTest
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

/// Tests for the button activation gate (#502): one physical click reaches
/// the action through redundant press-side paths plus GtkButton's
/// release-side `clicked` signal, and must fire the action exactly once
/// even when a loaded machine stretches the press→release gap past any
/// wall-clock dedup window.
final class GTK4ButtonActivationTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    // MARK: - Gate semantics (deterministic, no display required)

    func testPressThenLateClickedFiresOnce() {
        var gate = GTKButtonActivationGate()
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0))
        // The #502 CI failure: clicked dispatched >80ms after the press
        // paths on a loaded runner must NOT fire a second time.
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.2))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 5.0), "clicked may consume at most one armed press")
    }

    func testPressThenFastClickedFiresOnce() {
        var gate = GTKButtonActivationGate()
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.01))
    }

    func testRedundantPressPathsFireOnce() {
        var gate = GTKButtonActivationGate()
        // gesture + legacy + root-fallback dispatch within one main-loop
        // iteration; the wall-clock window still dedups those.
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0))
        XCTAssertFalse(gate.shouldFire(.pointerPress, now: 0.001))
        XCTAssertFalse(gate.shouldFire(.pointerPress, now: 0.002))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.2))
    }

    func testKeyboardClickedWithoutPressFires() {
        var gate = GTKButtonActivationGate()
        XCTAssertTrue(gate.shouldFire(.clicked, now: 1.0))
    }

    func testRapidKeyboardClickedDedupsWithinWindow() {
        var gate = GTKButtonActivationGate()
        XCTAssertTrue(gate.shouldFire(.clicked, now: 0))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.01))
        XCTAssertTrue(gate.shouldFire(.clicked, now: 0.5))
    }

    func testTwoSeparateClicksFireTwice() {
        var gate = GTKButtonActivationGate()
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.05))
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0.5))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 0.55))
    }

    func testAbandonedPressDoesNotSwallowNextClick() {
        var gate = GTKButtonActivationGate()
        // Press, drag off the button, release elsewhere: no clicked arrives.
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 0))
        // The next full click still fires exactly once.
        XCTAssertTrue(gate.shouldFire(.pointerPress, now: 1.0))
        XCTAssertFalse(gate.shouldFire(.clicked, now: 1.05))
    }

    // MARK: - Widget wiring

    func testActivatingRenderedButtonFiresActionOnce() throws {
        try requireGTK()

        var fireCount = 0
        let widget = widgetFromOpaque(gtkRenderView(
            Button("Tap") { fireCount += 1 }
        ))
        let button = try findWidget(ofType: "GtkButton", in: widget)

        // Keyboard-style activation emits `clicked` with no pointer press.
        XCTAssertNotEqual(gtk_widget_activate(button), 0, "GtkButton should be activatable")
        drainMainLoop()

        XCTAssertEqual(fireCount, 1, "one activation must invoke the action exactly once")
    }
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}

private func findWidget(
    ofType expectedTypeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> UnsafeMutablePointer<GtkWidget> {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == expectedTypeName {
        return widget
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = try? findWidget(ofType: expectedTypeName, in: current, file: file, line: line) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }
    XCTFail("Expected widget tree to contain \(expectedTypeName).", file: file, line: line)
    throw XCTSkip()
}

private func drainMainLoop(limit: Int = 100) {
    for _ in 0..<limit {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
