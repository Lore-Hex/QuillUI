/// Result returned from a SwiftUI `onKeyPress` handler.
public enum KeyPressResult: Equatable, Sendable {
    case handled
    case ignored
}

/// A key-specific action installed by `onKeyPress`.
public struct KeyPressAction {
    public let key: KeyEquivalent
    public let handler: () -> KeyPressResult

    public init(key: KeyEquivalent, handler: @escaping () -> KeyPressResult) {
        self.key = key
        self.handler = handler
    }
}

struct KeyPressActionsKey: EnvironmentKey {
    static let defaultValue: [KeyPressAction] = []
}

extension EnvironmentValues {
    public var keyPressActions: [KeyPressAction] {
        get { self[KeyPressActionsKey.self] }
        set { self[KeyPressActionsKey.self] = newValue }
    }
}

/// Installs a key press handler for descendant native controls.
public struct OnKeyPressView<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let key: KeyEquivalent
    public let action: () -> KeyPressResult

    public var body: Never { fatalError() }
}

extension View {
    /// Adds an action that runs when this view or a descendant control receives `key`.
    public func onKeyPress(_ key: KeyEquivalent, action: @escaping () -> KeyPressResult) -> OnKeyPressView<Self> {
        OnKeyPressView(content: self, key: key, action: action)
    }
}
