#if os(Linux)
import Foundation

// `UndoManager` ships in Apple's Foundation but is missing from
// swift-corelibs-foundation on Linux. It's cloned here — in the
// Foundation-clone layer rather than in AppKit — so every library that
// `import`s QuillFoundation (RSCore/QuillRSCoreShim, Account, AppKit, …)
// resolves one shared definition instead of having to depend on AppKit
// just to get an undo stack. QuillFoundation `@_exported import`s
// Foundation, so a target that links it (and `import`s QuillFoundation)
// sees this alongside the real Foundation surface. On macOS/iOS the real
// Foundation `UndoManager` wins via the SDK, so this clone is Linux-only.
//
// Behavioral parity with Apple's `UndoManager` is pinned by
// Tests/QuillFoundationTests/UndoManagerTests.swift — the same assertions
// run against this clone (Linux) and the real type (macOS).

open class UndoManager: NSObject, @unchecked Sendable {
    private struct UndoAction {
        var targetIDs: Set<ObjectIdentifier>
        var name: String
        var grouped: Bool
        var invoke: () -> Void
    }

    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    private var actionGroups: [[UndoAction]] = []
    private var undoing = false
    private var redoing = false
    private var registrationEnabled = true

    public override init() {
        super.init()
    }

    public func registerUndo<T: AnyObject>(withTarget target: T, handler: @escaping (T) -> Void) {
        guard registrationEnabled else { return }

        let action = UndoAction(
            targetIDs: [ObjectIdentifier(target)],
            name: undoActionName,
            grouped: false,
            invoke: { [weak target] in
                guard let target else { return }
                handler(target)
            }
        )

        if !actionGroups.isEmpty {
            actionGroups[actionGroups.count - 1].append(action)
        } else if undoing {
            appendRedoAction(action)
        } else if redoing {
            appendUndoAction(action, clearsRedo: false)
        } else {
            appendUndoAction(action, clearsRedo: true)
        }
    }

    public func registerUndo(withTarget target: AnyObject, selector: Selector, object: Any?) {
        registerUndo(withTarget: target) { target in
            (target as? QuillSelectorDispatching)?.quillPerform(selector, with: object)
        }
    }

    public func beginUndoGrouping() {
        actionGroups.append([])
    }

    public func endUndoGrouping() {
        guard let group = actionGroups.popLast(), !group.isEmpty else { return }

        let groupedAction = makeGroupedAction(from: group, name: group.last?.name ?? "")

        if actionGroups.isEmpty {
            appendUndoAction(groupedAction, clearsRedo: true)
        } else {
            actionGroups[actionGroups.count - 1].append(groupedAction)
        }
    }

    public func undo() {
        guard let action = undoStack.popLast() else { return }
        undoing = true
        if action.grouped {
            actionGroups.append([])
        }
        action.invoke()
        let inverseGroup = action.grouped ? actionGroups.popLast() : nil
        undoing = false
        if let inverseGroup, !inverseGroup.isEmpty {
            appendRedoAction(makeGroupedAction(from: inverseGroup, name: action.name))
        }
        redoActionName = action.name
    }

    public func redo() {
        guard let action = redoStack.popLast() else { return }
        redoing = true
        if action.grouped {
            actionGroups.append([])
        }
        action.invoke()
        let inverseGroup = action.grouped ? actionGroups.popLast() : nil
        redoing = false
        if let inverseGroup, !inverseGroup.isEmpty {
            appendUndoAction(makeGroupedAction(from: inverseGroup, name: action.name), clearsRedo: false)
        }
        undoActionName = action.name
    }

    public func removeAllActions() {
        undoStack.removeAll()
        redoStack.removeAll()
        actionGroups.removeAll()
    }

    public func removeAllActions(withTarget target: Any) {
        guard let object = target as? AnyObject else { return }
        let targetID = ObjectIdentifier(object)
        undoStack.removeAll { $0.targetIDs.contains(targetID) }
        redoStack.removeAll { $0.targetIDs.contains(targetID) }
        actionGroups = actionGroups.map { group in
            group.filter { !$0.targetIDs.contains(targetID) }
        }
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var groupsByEvent: Bool = true
    public var levelsOfUndo: Int = 0 {
        didSet {
            trimUndoStack()
            trimRedoStack()
        }
    }
    public var undoActionName: String = ""
    public var redoActionName: String = ""
    public func setActionName(_ name: String) { undoActionName = name }
    public var isUndoing: Bool { undoing }
    public var isRedoing: Bool { redoing }
    public func disableUndoRegistration() { registrationEnabled = false }
    public func enableUndoRegistration() { registrationEnabled = true }
    public var isUndoRegistrationEnabled: Bool { registrationEnabled }

    private func appendUndoAction(_ action: UndoAction, clearsRedo: Bool) {
        undoStack.append(action)
        trimUndoStack()
        if clearsRedo {
            redoStack.removeAll()
        }
    }

    private func appendRedoAction(_ action: UndoAction) {
        redoStack.append(action)
        trimRedoStack()
    }

    private func makeGroupedAction(from group: [UndoAction], name: String) -> UndoAction {
        UndoAction(
            targetIDs: Set(group.flatMap(\.targetIDs)),
            name: name,
            grouped: true,
            invoke: {
                for action in group.reversed() {
                    action.invoke()
                }
            }
        )
    }

    private func trimUndoStack() {
        guard levelsOfUndo > 0, undoStack.count > levelsOfUndo else { return }
        undoStack.removeFirst(undoStack.count - levelsOfUndo)
    }

    private func trimRedoStack() {
        guard levelsOfUndo > 0, redoStack.count > levelsOfUndo else { return }
        redoStack.removeFirst(redoStack.count - levelsOfUndo)
    }
}
#endif
