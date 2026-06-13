// QuillUIKit · UIControl target-action
// ====================================
// UIControl.Event plus the target-action registration/dispatch surface for
// platforms without Apple's UIKit. It lives in this file beside UIControl
// (QuillUIKit.swift) because Event is nested in UIControl; the concrete text
// controls (UITextField — Sources/UIKitShim/UITextInput.swift) and the other
// UIControl subclasses build on it through the UIKit shim's re-export.
//
// Honest Linux semantics: no event system feeds controls yet, so registered
// actions fire only when code calls sendActions(for:) — which the shim
// controls do from their programmatic state changes (e.g. UITextField's
// becomeFirstResponder fires .editingDidBegin). Dispatch follows the repo's
// no-ObjC contract: a Selector is an opaque token, and a fired action reaches
// its target via QuillSelectorDispatching (QuillFoundation) — the protocol
// the AppKitLowering pass conforms app classes to with a generated
// quillPerform(_:with:) (see QuillAppKit/QuillActionDispatching.swift).
// A target that doesn't conform fails safe: the action is dropped.

import QuillFoundation

#if !os(iOS)

extension UIControl {

    /// UIControl.Event. Raw values match Apple's.
    public struct Event: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }

        public static let touchDown = Event(rawValue: 1 << 0)
        public static let touchDownRepeat = Event(rawValue: 1 << 1)
        public static let touchDragInside = Event(rawValue: 1 << 2)
        public static let touchDragOutside = Event(rawValue: 1 << 3)
        public static let touchDragEnter = Event(rawValue: 1 << 4)
        public static let touchDragExit = Event(rawValue: 1 << 5)
        public static let touchUpInside = Event(rawValue: 1 << 6)
        public static let touchUpOutside = Event(rawValue: 1 << 7)
        public static let touchCancel = Event(rawValue: 1 << 8)
        public static let valueChanged = Event(rawValue: 1 << 12)
        public static let primaryActionTriggered = Event(rawValue: 1 << 13)
        public static let menuActionTriggered = Event(rawValue: 1 << 14)
        public static let editingDidBegin = Event(rawValue: 1 << 16)
        public static let editingChanged = Event(rawValue: 1 << 17)
        public static let editingDidEnd = Event(rawValue: 1 << 18)
        public static let editingDidEndOnExit = Event(rawValue: 1 << 19)
        public static let allTouchEvents = Event(rawValue: 0x0000_0FFF)
        public static let allEditingEvents = Event(rawValue: 0x000F_0000)
        public static let applicationReserved = Event(rawValue: 0x0F00_0000)
        public static let systemReserved = Event(rawValue: 0xF000_0000)
        public static let allEvents = Event(rawValue: 0xFFFF_FFFF)
    }

    /// One registered target/action pair. The target is weak (UIKit semantics:
    /// addTarget does not retain); pairs whose target has gone away are pruned
    /// on the next add/remove/send.
    private struct QuillTargetAction {
        weak var target: AnyObject?
        let action: Selector
        let events: Event
    }

    private struct QuillControlAction {
        let action: UIAction
        let events: Event
    }

    /// Registrations for all controls, keyed by control identity. Static
    /// because an extension cannot add instance storage. Entries for a
    /// deallocated control are not reclaimed — a bounded leak of small
    /// structs (the weak targets inside them do get pruned), accepted for
    /// the shim and noted honestly.
    private static var quillTargetActions: [ObjectIdentifier: [QuillTargetAction]] = [:]
    private static var quillControlActions: [ObjectIdentifier: [QuillControlAction]] = [:]

    public func addTarget(_ target: Any?, action: Selector, for controlEvents: Event) {
        // A nil target means "walk the responder chain" on iOS; there is no
        // chain to walk here, so such registrations are dropped.
        guard let target else { return }
        let object = target as AnyObject
        let key = ObjectIdentifier(self)
        var entries = UIControl.quillTargetActions[key, default: []]
        entries.removeAll { $0.target == nil }
        let alreadyRegistered = entries.contains {
            $0.target === object && $0.action == action && $0.events == controlEvents
        }
        if !alreadyRegistered {
            entries.append(QuillTargetAction(target: object, action: action, events: controlEvents))
        }
        UIControl.quillTargetActions[key] = entries
    }

    public func removeTarget(_ target: Any?, action: Selector?, for controlEvents: Event) {
        let key = ObjectIdentifier(self)
        guard var entries = UIControl.quillTargetActions[key] else { return }
        let object = target.map { $0 as AnyObject }
        entries.removeAll { entry in
            if entry.target == nil { return true }
            if let object, entry.target !== object { return false }
            if let action, entry.action != action { return false }
            return !entry.events.intersection(controlEvents).isEmpty
        }
        UIControl.quillTargetActions[key] = entries.isEmpty ? nil : entries
    }

    public func sendActions(for controlEvents: Event) {
        let key = ObjectIdentifier(self)
        for entry in UIControl.quillControlActions[key, default: []] where !entry.events.intersection(controlEvents).isEmpty {
            entry.action.quillHandler(entry.action)
        }
        guard var entries = UIControl.quillTargetActions[key] else { return }
        entries.removeAll { $0.target == nil }
        UIControl.quillTargetActions[key] = entries.isEmpty ? nil : entries
        for entry in entries where !entry.events.intersection(controlEvents).isEmpty {
            (entry.target as? QuillSelectorDispatching)?.quillPerform(entry.action, with: self)
        }
    }

    public func addAction(_ action: UIAction, for controlEvents: Event) {
        let key = ObjectIdentifier(self)
        var entries = UIControl.quillControlActions[key, default: []]
        entries.append(QuillControlAction(action: action, events: controlEvents))
        UIControl.quillControlActions[key] = entries
    }
}

#endif // !os(iOS)
