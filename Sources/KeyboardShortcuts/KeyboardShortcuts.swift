import Foundation
import SwiftUI

public enum KeyboardShortcuts {
    private static let store = ShortcutStore()
    private static let handlerStore = ShortcutHandlerStore()

    public struct Shortcut: Hashable, Sendable {
        public enum Key: Hashable, Sendable {
            case k
            case space
            case escape
            case tab
            case `return`
            case delete
            case upArrow
            case downArrow
            case leftArrow
            case rightArrow
            case character(Character)
        }

        public var key: Key
        public var modifiers: EventModifiers

        public init(_ key: Key, modifiers: EventModifiers = .command) {
            self.key = key
            self.modifiers = modifiers
        }

        // Manual Hashable + Equatable conformance: SwiftUI's EventModifiers
        // is an OptionSet whose Hashable derivation differs across Swift
        // versions. Hash by its rawValue so this shim compiles cleanly on
        // both macOS (real SwiftUI) and Linux (our SwiftUI shadow).
        public func hash(into hasher: inout Hasher) {
            hasher.combine(key)
            hasher.combine(modifiers.rawValue)
        }
        public static func == (lhs: Shortcut, rhs: Shortcut) -> Bool {
            lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
        }
    }

    public struct Name: Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public var defaultShortcut: Shortcut?

        public init(_ rawValue: String) {
            self.rawValue = rawValue
            self.defaultShortcut = nil
        }

        public init(_ rawValue: String, default defaultShortcut: Shortcut?) {
            self.rawValue = rawValue
            self.defaultShortcut = defaultShortcut
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
            self.defaultShortcut = nil
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
        }

        public static func == (lhs: Name, rhs: Name) -> Bool {
            lhs.rawValue == rhs.rawValue
        }
    }

    public enum ShortcutType: Hashable, Sendable {
        case keyDown
        case keyUp
    }

    public struct Recorder: View {
        private let title: String
        private let name: Name

        public init(_ title: String, name: Name) {
            self.title = title
            self.name = name
        }

        public var body: some View {
            Text(title)
        }
    }

    public static func getShortcut(for name: Name) -> Shortcut? {
        store.shortcut(for: name) ?? name.defaultShortcut
    }

    public static func setShortcut(_ shortcut: Shortcut?, for name: Name) {
        store.setShortcut(shortcut, for: name)
    }

    public static func reset(_ name: Name) {
        store.setShortcut(nil, for: name)
    }

    public static func resetAll() {
        store.removeAll()
    }

    @discardableResult
    public static func trigger(_ name: Name, type: ShortcutType = .keyDown) -> Bool {
        handlerStore.trigger(name: name, type: type)
    }

    public static func resetAllHandlers() {
        handlerStore.removeAll()
    }

    fileprivate static func registerHandler(
        for name: Name,
        type: ShortcutType,
        perform: @escaping () -> Void
    ) {
        handlerStore.setHandler(perform, for: name, type: type)
    }
}

public extension View {
    func onKeyboardShortcut(
        _ name: KeyboardShortcuts.Name,
        type: KeyboardShortcuts.ShortcutType = .keyDown,
        perform: @escaping () -> Void
    ) -> Self {
        KeyboardShortcuts.registerHandler(for: name, type: type, perform: perform)
        return self
    }
}

private final class ShortcutStore: @unchecked Sendable {
    private static let keyPrefix = "com.lorehex.quillui.keyboard-shortcuts."

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shortcut(for name: KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? {
        lock.lock()
        defer { lock.unlock() }

        guard let payload = defaults.dictionary(forKey: storageKey(for: name)) else {
            return nil
        }

        return shortcut(from: payload)
    }

    func setShortcut(_ shortcut: KeyboardShortcuts.Shortcut?, for name: KeyboardShortcuts.Name) {
        lock.lock()
        defer { lock.unlock() }

        let key = storageKey(for: name)
        if let shortcut {
            defaults.set(payload(for: shortcut), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func storageKey(for name: KeyboardShortcuts.Name) -> String {
        Self.keyPrefix + name.rawValue
    }

    private func payload(for shortcut: KeyboardShortcuts.Shortcut) -> [String: Any] {
        var payload: [String: Any] = [
            "modifiers": shortcut.modifiers.rawValue
        ]

        switch shortcut.key {
        case .k:
            payload["key"] = "k"
        case .space:
            payload["key"] = "space"
        case .escape:
            payload["key"] = "escape"
        case .tab:
            payload["key"] = "tab"
        case .return:
            payload["key"] = "return"
        case .delete:
            payload["key"] = "delete"
        case .upArrow:
            payload["key"] = "upArrow"
        case .downArrow:
            payload["key"] = "downArrow"
        case .leftArrow:
            payload["key"] = "leftArrow"
        case .rightArrow:
            payload["key"] = "rightArrow"
        case .character(let character):
            payload["key"] = "character"
            payload["character"] = String(character)
        }

        return payload
    }

    private func shortcut(from payload: [String: Any]) -> KeyboardShortcuts.Shortcut? {
        guard let rawModifiers = integerValue(payload["modifiers"]),
              let key = payload["key"] as? String else {
            return nil
        }

        let modifiers = EventModifiers(rawValue: rawModifiers)

        switch key {
        case "k":
            return KeyboardShortcuts.Shortcut(.k, modifiers: modifiers)
        case "space":
            return KeyboardShortcuts.Shortcut(.space, modifiers: modifiers)
        case "escape":
            return KeyboardShortcuts.Shortcut(.escape, modifiers: modifiers)
        case "tab":
            return KeyboardShortcuts.Shortcut(.tab, modifiers: modifiers)
        case "return":
            return KeyboardShortcuts.Shortcut(.return, modifiers: modifiers)
        case "delete":
            return KeyboardShortcuts.Shortcut(.delete, modifiers: modifiers)
        case "upArrow":
            return KeyboardShortcuts.Shortcut(.upArrow, modifiers: modifiers)
        case "downArrow":
            return KeyboardShortcuts.Shortcut(.downArrow, modifiers: modifiers)
        case "leftArrow":
            return KeyboardShortcuts.Shortcut(.leftArrow, modifiers: modifiers)
        case "rightArrow":
            return KeyboardShortcuts.Shortcut(.rightArrow, modifiers: modifiers)
        case "character":
            guard let string = payload["character"] as? String,
                  let character = string.first else {
                return nil
            }
            return KeyboardShortcuts.Shortcut(.character(character), modifiers: modifiers)
        default:
            return nil
        }
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }
}

private struct ShortcutHandlerKey: Hashable {
    var name: KeyboardShortcuts.Name
    var type: KeyboardShortcuts.ShortcutType
}

private typealias ShortcutHandler = () -> Void

private final class ShortcutHandlerStore: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [ShortcutHandlerKey: ShortcutHandler] = [:]

    func setHandler(
        _ handler: @escaping ShortcutHandler,
        for name: KeyboardShortcuts.Name,
        type: KeyboardShortcuts.ShortcutType
    ) {
        lock.lock()
        defer { lock.unlock() }

        handlers[ShortcutHandlerKey(name: name, type: type)] = handler
    }

    @discardableResult
    func trigger(name: KeyboardShortcuts.Name, type: KeyboardShortcuts.ShortcutType) -> Bool {
        let handler: ShortcutHandler?

        lock.lock()
        handler = handlers[ShortcutHandlerKey(name: name, type: type)]
        lock.unlock()

        guard let handler else {
            return false
        }

        handler()
        return true
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }

        handlers.removeAll()
    }
}
