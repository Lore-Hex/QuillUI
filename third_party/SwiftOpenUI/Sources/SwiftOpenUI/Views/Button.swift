/// A control that initiates an action.
public struct Button<Label: View>: View {
    public typealias Body = Never

    public let action: () -> Void
    public let label: Label
    public let role: ButtonRole?

    public var body: Never { fatalError("Button is a primitive view") }
}

/// Semantic role for a button, matching SwiftUI's public API surface.
public enum ButtonRole: Sendable, Equatable {
    case cancel
    case destructive
}

extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {
        self.init(title, role: nil, action: action)
    }

    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
        self.role = role
    }
}

extension Button {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.init(role: nil, action: action, label: label)
    }

    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.action = action
        self.label = label()
        self.role = role
    }
}
