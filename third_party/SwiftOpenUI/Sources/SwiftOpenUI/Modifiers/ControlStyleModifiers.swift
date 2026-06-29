// MARK: - Button Style

/// Built-in button style variants.
public enum ButtonStyleType: Equatable {
    /// Platform default.
    case automatic
    /// No chrome — just the label.
    case plain
    /// Visible border around the button.
    case bordered
    /// Filled/prominent background.
    case borderedProminent
    /// Compact accessory/action button chrome used in toolbars and inspector bars.
    case accessoryBarAction
    /// QuillPaint macOS default button chrome.
    case quillPaintMacDefault
    /// QuillPaint macOS bordered button chrome.
    case quillPaintMacBordered
    /// QuillPaint macOS sidebar/list-row chrome.
    case quillPaintMacListRow(isSelected: Bool, drawsIdleBackground: Bool)
}

public struct ButtonStyleConfiguration {
    public let label: AnyView
    public let isPressed: Bool

    public init(label: AnyView, isPressed: Bool = false) {
        self.label = label
        self.isPressed = isPressed
    }
}

@MainActor @preconcurrency
public protocol ButtonStyle {
    associatedtype Body: View
    typealias Configuration = ButtonStyleConfiguration

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}

public struct PlainButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> AnyView {
        configuration.label
    }
}

public struct AnyButtonStyle {
    private let makeBodyClosure: @MainActor (ButtonStyleConfiguration) -> AnyView

    public init<S: ButtonStyle>(_ style: S) {
        self.makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    @MainActor
    public func makeBody(configuration: ButtonStyleConfiguration) -> AnyView {
        makeBodyClosure(configuration)
    }
}

struct ButtonStyleKey: EnvironmentKey {
    static let defaultValue: ButtonStyleType = .automatic
}

struct CustomButtonStyleKey: EnvironmentKey {
    static let defaultValue: AnyButtonStyle? = nil
}

extension EnvironmentValues {
    public var buttonStyle: ButtonStyleType {
        get { self[ButtonStyleKey.self] }
        set { self[ButtonStyleKey.self] = newValue }
    }

    public var customButtonStyle: AnyButtonStyle? {
        get { self[CustomButtonStyleKey.self] }
        set { self[CustomButtonStyleKey.self] = newValue }
    }
}

// MARK: - Toggle Style

/// Built-in toggle style variants.
public enum ToggleStyleType: Equatable {
    /// Platform default.
    case automatic
    /// Checkbox appearance.
    case checkbox
    /// Button-like toggle appearance.
    case button
    /// Switch appearance.
    case `switch`
}

public final class ToggleStyleConfiguration {
    public let label: AnyView
    private let isOnBinding: Binding<Bool>

    public var isOn: Bool {
        get { isOnBinding.wrappedValue }
        set { isOnBinding.wrappedValue = newValue }
    }

    public init(label: AnyView, isOn: Binding<Bool>) {
        self.label = label
        self.isOnBinding = isOn
    }
}

@MainActor @preconcurrency
public protocol ToggleStyle {
    associatedtype Body: View
    typealias Configuration = ToggleStyleConfiguration

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}

public struct AnyToggleStyle {
    private let makeBodyClosure: @MainActor (ToggleStyleConfiguration) -> AnyView

    public init<S: ToggleStyle>(_ style: S) {
        self.makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    @MainActor
    public func makeBody(configuration: ToggleStyleConfiguration) -> AnyView {
        makeBodyClosure(configuration)
    }
}

struct ToggleStyleKey: EnvironmentKey {
    static let defaultValue: ToggleStyleType = .automatic
}

struct CustomToggleStyleKey: EnvironmentKey {
    static let defaultValue: AnyToggleStyle? = nil
}

extension EnvironmentValues {
    public var toggleStyle: ToggleStyleType {
        get { self[ToggleStyleKey.self] }
        set { self[ToggleStyleKey.self] = newValue }
    }

    public var customToggleStyle: AnyToggleStyle? {
        get { self[CustomToggleStyleKey.self] }
        set { self[CustomToggleStyleKey.self] = newValue }
    }
}

// MARK: - Control Group Style

public struct ControlGroupStyleConfiguration {
    public let content: AnyView

    public init(content: AnyView) {
        self.content = content
    }
}

@MainActor @preconcurrency
public protocol ControlGroupStyle {
    associatedtype Body: View
    typealias Configuration = ControlGroupStyleConfiguration

    @ViewBuilder
    func makeBody(configuration: Configuration) -> Body
}

// MARK: - TextField Style

/// Built-in text field style variants.
public enum TextFieldStyleType: Equatable {
    /// Platform default.
    case automatic
    /// No visible border.
    case plain
    /// Rounded border around the field.
    case roundedBorder
}

struct TextFieldStyleKey: EnvironmentKey {
    static let defaultValue: TextFieldStyleType = .automatic
}

extension EnvironmentValues {
    public var textFieldStyle: TextFieldStyleType {
        get { self[TextFieldStyleKey.self] }
        set { self[TextFieldStyleKey.self] = newValue }
    }
}

// MARK: - Style Modifier Views

/// Sets the button style for descendant buttons.
public struct ButtonStyleModifier<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: ButtonStyleType
    public var body: Never { fatalError() }
}

/// Sets a custom SwiftUI-style button style for descendant buttons.
public struct CustomButtonStyleModifier<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: AnyButtonStyle
    public var body: Never { fatalError() }
}

/// Sets the toggle style for descendant toggles.
public struct ToggleStyleModifier<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: ToggleStyleType
    public var body: Never { fatalError() }
}

/// Sets a custom SwiftUI-style toggle style for descendant toggles.
public struct CustomToggleStyleModifier<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: AnyToggleStyle
    public var body: Never { fatalError() }
}

/// Sets a custom SwiftUI-style control group style for descendant controls.
public struct ControlGroupStyleModifier<Content: View, Style: ControlGroupStyle>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: Style
    public var body: Never { fatalError() }
}

/// Sets the text field style for descendant text fields.
public struct TextFieldStyleModifier<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: TextFieldStyleType
    public var body: Never { fatalError() }
}

// MARK: - View Extensions

extension View {
    /// Sets the style for buttons within this view.
    public func buttonStyle(_ style: ButtonStyleType) -> ButtonStyleModifier<Self> {
        ButtonStyleModifier(content: self, style: style)
    }

    /// Sets a custom style for buttons within this view.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> CustomButtonStyleModifier<Self> {
        CustomButtonStyleModifier(content: self, style: AnyButtonStyle(style))
    }

    /// Sets the style for toggles within this view.
    public func toggleStyle(_ style: ToggleStyleType) -> ToggleStyleModifier<Self> {
        ToggleStyleModifier(content: self, style: style)
    }

    /// Sets a custom style for toggles within this view.
    public func toggleStyle<S: ToggleStyle>(_ style: S) -> CustomToggleStyleModifier<Self> {
        CustomToggleStyleModifier(content: self, style: AnyToggleStyle(style))
    }

    /// Accept custom control group styles. SwiftOpenUI has no native
    /// ControlGroup primitive yet, so this modifier preserves the source shape
    /// and renders the original content unchanged.
    public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> ControlGroupStyleModifier<Self, S> {
        ControlGroupStyleModifier(content: self, style: style)
    }

    /// Sets the style for text fields within this view.
    public func textFieldStyle(_ style: TextFieldStyleType) -> TextFieldStyleModifier<Self> {
        TextFieldStyleModifier(content: self, style: style)
    }
}
