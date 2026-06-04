import Testing
import Foundation
@testable import QuillFoundation

// Behavioral parity tests for the Linux `UndoManager` clone in
// QuillFoundation (UndoManagerLinuxClone.swift). On Linux `UndoManager`
// resolves to the clone; on macOS it resolves to Apple's real Foundation
// type via QuillFoundation's `@_exported import Foundation`. Every
// assertion below was checked to hold for BOTH, so this suite doubles as a
// parity check that the clone faithfully mirrors Apple's `UndoManager`.
//
// Apple's `UndoManager` throws ("must begin a group before registering
// undo") if you register with `groupsByEvent = false` and no open group,
// and its run-loop auto-grouping is nondeterministic in a synchronous
// test. So every test disables `groupsByEvent` and brackets registrations
// in explicit begin/endUndoGrouping — the documented way to drive an
// `UndoManager` off the run loop.

/// A reference cell whose mutations are made undoable.
private final class Counter {
    var value = 0
}

/// Registers the canonical self-inverse undo for `counter.value`: undoing
/// re-registers the redo, redoing re-registers the undo. Must be called
/// inside an open undo group. Captures the manager weakly to avoid a
/// retain cycle through the stored handler.
private func setValue(_ newValue: Int, on counter: Counter, using undo: UndoManager) {
    let old = counter.value
    undo.registerUndo(withTarget: counter) { [weak undo] target in
        guard let undo else { return }
        setValue(old, on: target, using: undo)
    }
    counter.value = newValue
}

@Suite("QuillFoundation UndoManager clone")
struct UndoManagerTests {
    /// A fresh manager configured for deterministic, run-loop-free use.
    private func makeManager() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    /// Runs `body` inside a single undo group.
    private func grouped(_ undo: UndoManager, _ body: () -> Void) {
        undo.beginUndoGrouping()
        body()
        undo.endUndoGrouping()
    }

    @Test("register → undo → redo round-trips the value and toggles canUndo/canRedo")
    func registerUndoRedo() {
        let undo = makeManager()
        let counter = Counter()

        #expect(undo.canUndo == false)
        #expect(undo.canRedo == false)

        grouped(undo) { setValue(5, on: counter, using: undo) }
        #expect(counter.value == 5)
        #expect(undo.canUndo == true)
        #expect(undo.canRedo == false)

        undo.undo()
        #expect(counter.value == 0)
        #expect(undo.canUndo == false)
        #expect(undo.canRedo == true)

        undo.redo()
        #expect(counter.value == 5)
        #expect(undo.canUndo == true)
        #expect(undo.canRedo == false)
    }

    @Test("separate groups undo in LIFO order")
    func twoGroupsUndoLIFO() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) { setValue(1, on: counter, using: undo) }
        grouped(undo) { setValue(2, on: counter, using: undo) }
        #expect(counter.value == 2)

        undo.undo()
        #expect(counter.value == 1)
        #expect(undo.canUndo == true)

        undo.undo()
        #expect(counter.value == 0)
        #expect(undo.canUndo == false)
        #expect(undo.canRedo == true)
    }

    @Test("multiple registrations in one group are undone together")
    func singleGroupMultipleActions() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) {
            setValue(1, on: counter, using: undo)
            setValue(2, on: counter, using: undo)
        }
        #expect(counter.value == 2)
        #expect(undo.canUndo == true)

        undo.undo()
        #expect(counter.value == 0) // one undo reverts both registrations
        #expect(undo.canUndo == false)
        #expect(undo.canRedo == true)
    }

    @Test("a fresh registration clears the redo stack")
    func newRegistrationClearsRedo() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) { setValue(1, on: counter, using: undo) }
        undo.undo()
        #expect(undo.canRedo == true)

        grouped(undo) { setValue(9, on: counter, using: undo) }
        #expect(undo.canRedo == false)
        #expect(undo.canUndo == true)
    }

    @Test("registration disabled while disabled records nothing")
    func disableRegistration() {
        let undo = makeManager()
        let counter = Counter()

        #expect(undo.isUndoRegistrationEnabled == true)
        undo.disableUndoRegistration()
        #expect(undo.isUndoRegistrationEnabled == false)

        grouped(undo) { setValue(3, on: counter, using: undo) }

        undo.enableUndoRegistration()
        #expect(undo.isUndoRegistrationEnabled == true)
        #expect(undo.canUndo == false)
    }

    @Test("removeAllActions(withTarget:) drops that target's actions")
    func removeAllActionsWithTarget() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) { setValue(4, on: counter, using: undo) }
        #expect(undo.canUndo == true)

        undo.removeAllActions(withTarget: counter)
        #expect(undo.canUndo == false)
        #expect(undo.canRedo == false)
    }

    @Test("removeAllActions() clears both stacks")
    func removeAllActionsClearsEverything() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) { setValue(1, on: counter, using: undo) }
        undo.undo()
        #expect(undo.canRedo == true)

        undo.removeAllActions()
        #expect(undo.canUndo == false)
        #expect(undo.canRedo == false)
    }

    @Test("setActionName names the pending undo action")
    func actionName() {
        let undo = makeManager()
        let counter = Counter()

        grouped(undo) {
            setValue(1, on: counter, using: undo)
            undo.setActionName("Typing")
        }

        #expect(undo.undoActionName == "Typing")
        #expect(undo.redoActionName == "")
    }
}
