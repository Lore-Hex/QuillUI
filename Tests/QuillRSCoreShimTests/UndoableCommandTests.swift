import Foundation
import Testing
@testable import QuillRSCoreShim

/// A minimal UndoableCommand that records how many times it was performed/undone,
/// standing in for the real model-mutating commands NNW runs.
@MainActor private final class SpyCommand: UndoableCommand {
    let undoActionName = "Spy"
    let redoActionName = "Spy"
    let undoManager: UndoManager
    private(set) var performCount = 0
    private(set) var undoCount = 0

    init(undoManager: UndoManager) { self.undoManager = undoManager }

    func perform() { performCount += 1; registerUndo() }
    func undo() { undoCount += 1; registerRedo() }
}

@MainActor private final class SpyRunner: UndoableCommandRunner {
    var undoableCommands: [UndoableCommand] = []
    let undoManager: UndoManager?
    init(undoManager: UndoManager?) { self.undoManager = undoManager }
}

/// Pins the vendored RSCore `UndoableCommand` / `UndoableCommandRunner` default
/// implementations — the deterministic command-stack logic (run/push/clear).
/// `UndoManager`'s run-loop-grouped undo execution is intentionally not asserted
/// (it isn't deterministic outside a run loop, and differs by platform).
@Suite("QuillRSCoreShim — UndoableCommand / UndoableCommandRunner")
@MainActor
struct UndoableCommandTests {

    @Test("runCommand performs the command and pushes it on the stack")
    func runCommandPerformsAndPushes() {
        let um = UndoManager()
        let runner = SpyRunner(undoManager: um)
        let cmd = SpyCommand(undoManager: um)

        runner.runCommand(cmd)

        #expect(cmd.performCount == 1)
        #expect(runner.undoableCommands.count == 1)
    }

    @Test("pushUndoableCommand appends without performing")
    func pushDoesNotPerform() {
        let um = UndoManager()
        let runner = SpyRunner(undoManager: um)
        let cmd = SpyCommand(undoManager: um)

        runner.pushUndoableCommand(cmd)

        #expect(cmd.performCount == 0)
        #expect(runner.undoableCommands.count == 1)
    }

    @Test("clearUndoableCommands empties the stack when an undoManager is present")
    func clearWithUndoManager() {
        let um = UndoManager()
        let runner = SpyRunner(undoManager: um)
        runner.runCommand(SpyCommand(undoManager: um))
        runner.runCommand(SpyCommand(undoManager: um))
        #expect(runner.undoableCommands.count == 2)

        runner.clearUndoableCommands()
        #expect(runner.undoableCommands.isEmpty)
    }

    @Test("clearUndoableCommands is a no-op when undoManager is nil (early return)")
    func clearWithoutUndoManagerIsNoOp() {
        let um = UndoManager()
        let runner = SpyRunner(undoManager: nil)
        runner.pushUndoableCommand(SpyCommand(undoManager: um))
        #expect(runner.undoableCommands.count == 1)

        runner.clearUndoableCommands() // guard-let undoManager fails -> returns early

        #expect(runner.undoableCommands.count == 1) // stack untouched
    }

    @Test("perform/undo on the command bump their own counters")
    func performUndoCounters() {
        let um = UndoManager()
        let cmd = SpyCommand(undoManager: um)
        cmd.perform()
        cmd.undo()
        #expect(cmd.performCount == 1)
        #expect(cmd.undoCount == 1)
    }
}
