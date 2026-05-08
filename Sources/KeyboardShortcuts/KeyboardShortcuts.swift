import SwiftUI

public enum KeyboardShortcuts {
    public struct Name: Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(stringLiteral value: String) {
            self.rawValue = value
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

