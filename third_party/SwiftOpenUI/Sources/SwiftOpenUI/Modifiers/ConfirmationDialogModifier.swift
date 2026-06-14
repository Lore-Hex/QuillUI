/// Visibility preference for titles and labels.
public enum Visibility: Equatable {
    case automatic
    case visible
    case hidden
    case never
}

/// Stored dismissal-confirmation configuration carried by a view tree.
public struct DismissalConfirmationConfiguration {
    public let title: String
    public let isPresented: Binding<Bool>
    public let titleVisibility: Visibility
    public let message: String
    public let buttons: [AlertButton]

    public init(
        title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility,
        message: String,
        buttons: [AlertButton]
    ) {
        self.title = title
        self.isPresented = isPresented
        self.titleVisibility = titleVisibility
        self.message = message
        self.buttons = buttons
    }
}

/// Protocol for views that carry dismissal-confirmation interception metadata.
public protocol DismissalConfirmationProvider {
    var dismissalConfirmationConfiguration: DismissalConfirmationConfiguration? { get }
}

/// A modifier that presents a confirmation dialog with vertical buttons
/// when a binding becomes true.
public struct ConfirmationDialogView<Content: View>: View, DismissalConfirmationProvider {
    public typealias Body = Never

    public let content: Content
    public let title: String
    public let isPresented: Binding<Bool>
    public let titleVisibility: Visibility
    public let message: String
    public let buttons: [AlertButton]
    public let participatesInDismissalInterception: Bool

    public var dismissalConfirmationConfiguration: DismissalConfirmationConfiguration? {
        guard participatesInDismissalInterception else { return nil }
        return DismissalConfirmationConfiguration(
            title: title,
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            message: message,
            buttons: buttons
        )
    }

    public var body: Never { fatalError("ConfirmationDialogView is a primitive view") }
}

extension View {
    /// Show a dismissal confirmation dialog when `shouldPresent` becomes true.
    public func dismissalConfirmationDialog(
        _ title: String,
        shouldPresent: Binding<Bool>,
        actions: [AlertButton]
    ) -> ConfirmationDialogView<Self> {
        ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: shouldPresent,
            titleVisibility: .automatic,
            message: "",
            buttons: actions,
            participatesInDismissalInterception: true
        )
    }

    /// Show a confirmation dialog when `isPresented` becomes true.
    /// Buttons are displayed vertically (action sheet style).
    public func confirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        actions: [AlertButton]
    ) -> ConfirmationDialogView<Self> {
        confirmationDialog(
            title,
            isPresented: isPresented,
            titleVisibility: .automatic,
            actions: actions,
            message: ""
        )
    }

    /// Show a confirmation dialog with explicit title visibility.
    public func confirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility,
        actions: [AlertButton]
    ) -> ConfirmationDialogView<Self> {
        confirmationDialog(
            title,
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            actions: actions,
            message: ""
        )
    }

    /// Show a confirmation dialog with explicit title visibility and message.
    public func confirmationDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility,
        actions: [AlertButton],
        message: String
    ) -> ConfirmationDialogView<Self> {
        ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            message: message,
            buttons: actions,
            participatesInDismissalInterception: false
        )
    }

    /// SwiftUI-shaped builder overload with a message view.
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> ConfirmationDialogView<Self> {
        return ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: isPresented,
            titleVisibility: .automatic,
            message: swiftOpenUITextLabel(from: message()),
            buttons: swiftOpenUIConfirmationDialogButtons(from: actions()),
            participatesInDismissalInterception: false
        )
    }

    /// SwiftUI-shaped builder overload WITHOUT a message — SwiftUI's
    /// `confirmationDialog(_:isPresented:titleVisibility:actions:)`. Without
    /// this, a no-message trailing-closure call (e.g. IceCubes StatusKit's
    /// `confirmationDialog("", isPresented:) { Button(…) }`) has no ViewBuilder
    /// candidate and the trailing closure falls back to the `[AlertButton]`
    /// overload ("trailing closure passed to parameter of type '[AlertButton]'").
    public func confirmationDialog<Actions: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> Actions
    ) -> ConfirmationDialogView<Self> {
        return ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: isPresented,
            titleVisibility: titleVisibility,
            message: "",
            buttons: swiftOpenUIConfirmationDialogButtons(from: actions()),
            participatesInDismissalInterception: false
        )
    }
}

private protocol SwiftOpenUIButtonRepresentable {
    var swiftOpenUIButtonLabel: String { get }
    var swiftOpenUIButtonAction: () -> Void { get }
}

extension Button: SwiftOpenUIButtonRepresentable {
    fileprivate var swiftOpenUIButtonLabel: String { swiftOpenUITextLabel(from: label) }
    fileprivate var swiftOpenUIButtonAction: () -> Void { action }
}

private protocol SwiftOpenUIDisabledRepresentable {
    var swiftOpenUIDisabledContent: any View { get }
}

extension DisabledView: SwiftOpenUIDisabledRepresentable {
    fileprivate var swiftOpenUIDisabledContent: any View { content }
}

private protocol SwiftOpenUIKeyboardShortcutRepresentable {
    var swiftOpenUIShortcutContent: any View { get }
}

extension KeyboardShortcutView: SwiftOpenUIKeyboardShortcutRepresentable {
    fileprivate var swiftOpenUIShortcutContent: any View { content }
}

private func swiftOpenUITextLabel(from view: any View) -> String {
    if let text = view as? Text {
        return text.content
    }

    if let shortcut = view as? any SwiftOpenUIKeyboardShortcutRepresentable {
        return swiftOpenUITextLabel(from: shortcut.swiftOpenUIShortcutContent)
    }

    if let disabled = view as? any SwiftOpenUIDisabledRepresentable {
        return swiftOpenUITextLabel(from: disabled.swiftOpenUIDisabledContent)
    }

    if let multi = view as? MultiChildView {
        for child in multi.children {
            let label = swiftOpenUITextLabel(from: child)
            if !label.isEmpty {
                return label
            }
        }
    }

    return ""
}

private func swiftOpenUIConfirmationDialogButtons(from view: any View) -> [AlertButton] {
    if let button = view as? any SwiftOpenUIButtonRepresentable {
        return [AlertButton(button.swiftOpenUIButtonLabel, action: button.swiftOpenUIButtonAction)]
    }

    if let shortcut = view as? any SwiftOpenUIKeyboardShortcutRepresentable {
        return swiftOpenUIConfirmationDialogButtons(from: shortcut.swiftOpenUIShortcutContent)
    }

    if let disabled = view as? any SwiftOpenUIDisabledRepresentable {
        return swiftOpenUIConfirmationDialogButtons(from: disabled.swiftOpenUIDisabledContent)
    }

    if let multi = view as? MultiChildView {
        return multi.children.flatMap(swiftOpenUIConfirmationDialogButtons)
    }

    return []
}
