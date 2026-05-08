import SwiftUI

public enum KeyboardShortcuts {
    public struct Shortcut: Hashable, Sendable {
        public enum Key: Hashable, Sendable {
            case k
            case character(Character)
        }

        public var key: Key
        public var modifiers: EventModifiers

        public init(_ key: Key, modifiers: EventModifiers = .command) {
            self.key = key
            self.modifiers = modifiers
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
    }

    public enum ShortcutType: Sendable {
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
}

public extension View {
    func onKeyboardShortcut(
        _ name: KeyboardShortcuts.Name,
        type: KeyboardShortcuts.ShortcutType = .keyDown,
        perform: @escaping () -> Void
    ) -> Self {
        self
    }
}
