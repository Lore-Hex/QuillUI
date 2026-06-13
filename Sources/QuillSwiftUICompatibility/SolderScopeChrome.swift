// SolderScope app-chrome compatibility surface (issue #508).
//
// rjwalters/SolderScope is compiled UNMODIFIED with `import SwiftUI`, which
// resolves to the Linux SwiftUI shadow → this module → SwiftOpenUI. Several
// app-chrome shims it needs already existed in QuillUI (Material, the
// ButtonStyle protocol, ButtonRole, Animation.repeatForever, the command/menu
// builder expressions, WindowGroup conveniences) — but QuillUI is NOT visible
// through `import SwiftUI`, and QuillUI `@_exported import`s THIS module, so
// duplicating those names here would make every file that imports both
// modules ambiguous. Following the house pattern already documented in
// UpstreamCompatibility.swift (see the firstTextBaseline note), those
// declarations now live HERE canonically and were removed from QuillUI;
// `import QuillUI` clients keep seeing them through the re-export.
//
// Everything genuinely new in this file (MenuStyle, WindowStyle, the
// closure-based alert, onExitCommand) mirrors Apple's names and signatures
// exactly; inert behavior is documented inline.

import SwiftOpenUI

#if os(Linux)

// MARK: - Text.monospacedDigit

// monospacedDigit lives in DesignSystemSurfaceCompat.swift.

// MARK: - Animation.repeatForever (moved from QuillUI)

extension Animation {
    /// SwiftUI's `repeatForever(autoreverses:)`. The repeat metadata is
    /// preserved on the Animation value; GTK transition repeat loops are not
    /// yet implemented, so playback currently runs the transition once.
    public func repeatForever(autoreverses: Bool = true) -> Animation {
        Animation(
            curve: curve,
            duration: duration,
            delay: delay,
            repeatsForever: true,
            autoreverses: autoreverses
        )
    }
}

// MARK: - Material (moved from QuillUI)

// `Material` tokens live in DesignSystemSurfaceCompat.swift.

extension View {
    /// `.background(.ultraThinMaterial)` — Apple's ShapeStyle-based overload,
    /// narrowed to `Material` (this tree has no ShapeStyle protocol). The blur
    /// is approximated with translucent white via the existing color
    /// background, so the call renders today instead of being dropped.
    /// `ignoresSafeAreaEdges` is accepted for source compatibility and unused
    /// (safe-area reservation does not affect backgrounds on this backend).
    public func background(
        _ material: Material,
        ignoresSafeAreaEdges edges: Edge.Set = .all
    ) -> BackgroundView<Self, Color> {
        // Scheme-adaptive approximation: on macOS a material over dark video
        // reads as a dark pill with light content (SolderScope's reference
        // screenshot), over light content as a light pill. Per-token
        // translucency via the CSS rgba background (renders behind children;
        // the GTK background path paints the box background only).
        // Scheme-adaptive translucent approximation (dark pill over video on
        // macOS). Per-token alphas await a Material that carries them (the
        // DesignSystemSurfaceCompat tokens are indistinguishable instances).
        background(
            Color.quillPrefersDarkScheme
                ? Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.85)
                : Color.white.opacity(0.92)
        )
    }
}

// MARK: - ButtonStyle protocol (moved from QuillUI)

// ButtonStyle + ButtonStyleConfiguration live in DesignSystemSurfaceCompat.swift
// (same AnyView label shape; the functional buttonStyle overload below uses them).

extension View {
    /// Accepts a custom `ButtonStyle` conformance. Compile-surface: custom
    /// styles currently fall back to the plain GTK button chrome (the style's
    /// `makeBody` is not yet invoked by the renderer). Distinct parameter type
    /// keeps the built-in `buttonStyle(_: ButtonStyleType)` overload — and
    /// `.buttonStyle(.plain)` call sites — resolving exactly as before.
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
        // Functional custom styles for the direct application every real app
        // uses (`Button(...) .buttonStyle(MyStyle())`): rebuild the button
        // with makeBody's output as its label under plain GTK chrome — the
        // style owns ALL visuals (colors/padding/background), which is how
        // SolderScope's ToolbarButtonStyle paints its accent-blue active
        // states. isPressed is currently always false (GtkButton's own
        // :active pseudo-state still gives press feedback; reactive pressed
        // restyling needs press-signal plumbing — documented gap).
        if let button = self as? QuillStyleableButtonRepresentable {
            return AnyView(
                Button(action: button.quillStyleableAction) {
                    style.makeBody(configuration: .init(
                        label: button.quillStyleableLabel, isPressed: false))
                }
                .buttonStyle(ButtonStyleType.plain)
            )
        }
        // Indirect application (container subtrees) keeps the plain fallback.
        return AnyView(buttonStyle(ButtonStyleType.plain))
    }
}

/// Type-erased access to a Button's label and action so the generic
/// `buttonStyle` overload can rebuild it across any `Label` type.
/// @MainActor: members of main-actor-isolated View types.
@MainActor
public protocol QuillStyleableButtonRepresentable {
    var quillStyleableLabel: AnyView { get }
    var quillStyleableAction: () -> Void { get }
}

extension Button: QuillStyleableButtonRepresentable {
    public var quillStyleableLabel: AnyView { AnyView(label) }
    public var quillStyleableAction: () -> Void { action }
}

// MARK: - ButtonRole (moved from QuillUI)

// ButtonRole lives in DesignSystemSurfaceCompat.swift.

extension Button where Label == Text {
    /// Role-taking title initializer. The role is currently presentation-only
    /// metadata Apple uses for emphasis/ordering; it is accepted and dropped
    /// (the action and title are preserved).
    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(title, action: action)
    }
}

// Button(role:) inits live in DesignSystemSurfaceCompat.swift.

// MARK: - MenuStyle

/// SwiftUI's `MenuStyle` protocol. Styles are accepted for source
/// compatibility; the GTK menu button renders with its platform chrome either
/// way, which is visually closest to `.borderlessButton` already.
public protocol MenuStyle {}

/// The default menu style.
public struct DefaultMenuStyle: MenuStyle {
    public init() {}
}

/// Apple's borderless-button menu style token type.
public struct BorderlessButtonMenuStyle: MenuStyle {
    public init() {}
}

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle { DefaultMenuStyle() }
}

extension MenuStyle where Self == BorderlessButtonMenuStyle {
    public static var borderlessButton: BorderlessButtonMenuStyle { BorderlessButtonMenuStyle() }
}

extension View {
    /// Sets the style for menus within this view. Compile-surface: returns
    /// `self` unchanged (see `MenuStyle`).
    public func menuStyle<S: MenuStyle>(_ style: S) -> some View { self }
}

// MARK: - View-tree walkers (private)
//
// The builder expressions and the closure-based alert below need to lift
// labels/actions out of small view trees (`Button { HStack { Image; Text } }`,
// `ForEach(...) { Button(...) }`). QuillUI's original implementations leaned
// on its private Quill*Representable protocol web; these are self-contained
// equivalents over public SwiftOpenUI types only. Buttons and the typed
// wrapper views are reached through private retroactive conformances —
// generic types can't be matched from `any View` otherwise.

@MainActor
private protocol ChromeButtonRepresentable {
    var chromeButtonTitle: String { get }
    var chromeButtonAction: () -> Void { get }
}

extension Button: ChromeButtonRepresentable {
    var chromeButtonTitle: String { chromeTextLabel(from: label) }
    var chromeButtonAction: () -> Void { action }
}

@MainActor
private protocol ChromeShortcutRepresentable {
    var chromeShortcutContent: any View { get }
    var chromeShortcut: KeyboardShortcut { get }
}

extension KeyboardShortcutView: ChromeShortcutRepresentable {
    var chromeShortcutContent: any View { content }
    var chromeShortcut: KeyboardShortcut { shortcut }
}

@MainActor
private protocol ChromeDisabledRepresentable {
    var chromeDisabledContent: any View { get }
    var chromeIsDisabled: Bool { get }
}

extension DisabledView: ChromeDisabledRepresentable {
    var chromeDisabledContent: any View { content }
    var chromeIsDisabled: Bool { isDisabled }
}

/// Transparent single-child wrappers the walkers look through (the cosmetic
/// modifier chain between a Button/Menu label and its Text).
@MainActor
private protocol ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { get }
}

extension LineLimitView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension FrameView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension FontModifiedView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension ForegroundColorView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension HelpView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension PaddedView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension OpacityView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension OffsetView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension ScaleEffectView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

extension AnimatedView: ChromeWrappedViewRepresentable {
    var chromeWrappedContent: any View { content }
}

/// First non-empty text found in a label view tree (`Text` content, `Label`
/// title, or a stack/wrapper that eventually contains one). Images yield no
/// text and are skipped, so `HStack { Image(...); Text(name); Image(...) }`
/// resolves to `name`.
@MainActor
private func chromeTextLabel(from view: any View) -> String {
    if let text = view as? Text {
        return text.content
    }
    // Label is generic on main; the ubiquitous Label("x", systemImage:) shape
    // is Label<Text, Image>. Other arities fall through to the wrapped walk.
    if let label = view as? Label<Text, Image> {
        return label.title
    }
    if let wrapped = view as? any ChromeWrappedViewRepresentable {
        return chromeTextLabel(from: wrapped.chromeWrappedContent)
    }
    if let shortcut = view as? any ChromeShortcutRepresentable {
        return chromeTextLabel(from: shortcut.chromeShortcutContent)
    }
    if let disabled = view as? any ChromeDisabledRepresentable {
        return chromeTextLabel(from: disabled.chromeDisabledContent)
    }
    if let multi = view as? MultiChildView {
        for child in multi.children {
            let label = chromeTextLabel(from: child)
            if !label.isEmpty {
                return label
            }
        }
    }
    return ""
}

/// Menu elements lifted out of an arbitrary view (`ForEach` of Buttons, a
/// conditional `Text`, …). Views that carry no actionable content collapse to
/// the empty list, exactly like the QuillUI walker this replaces.
@MainActor
private func chromeMenuElements(from view: any View) -> [MenuElement] {
    if let button = view as? any ChromeButtonRepresentable {
        return [.item(label: button.chromeButtonTitle, action: button.chromeButtonAction)]
    }
    if let shortcut = view as? any ChromeShortcutRepresentable {
        return chromeMenuElements(from: shortcut.chromeShortcutContent)
    }
    if let disabled = view as? any ChromeDisabledRepresentable {
        return chromeMenuElements(from: disabled.chromeDisabledContent)
            .map { chromeDisabledMenuElement($0, disabled: disabled.chromeIsDisabled) }
    }
    if let wrapped = view as? any ChromeWrappedViewRepresentable {
        return chromeMenuElements(from: wrapped.chromeWrappedContent)
    }
    if view is Divider {
        return [.divider]
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap(chromeMenuElements)
    }
    return []
}

/// Disabled menu items keep their label but lose their action (GTK menu
/// models have no per-item enabled flag on this path yet).
private func chromeDisabledMenuElement(_ element: MenuElement, disabled: Bool) -> MenuElement {
    guard disabled else { return element }
    switch element {
    case .item(let label, _):
        return .item(label: label, action: {})
    case .divider:
        return .divider
    case .submenu(let label, let children):
        return .submenu(label: label, children: children.map { chromeDisabledMenuElement($0, disabled: true) })
    }
}

/// Command-menu items lifted out of an arbitrary view. Dividers have no
/// `CommandMenuItem` representation and are dropped (matching the QuillUI
/// walker this replaces).
@MainActor
private func chromeCommandMenuItems(from view: any View) -> [CommandMenuItem] {
    if let button = view as? any ChromeButtonRepresentable {
        return [CommandMenuItem(button.chromeButtonTitle, action: button.chromeButtonAction)]
    }
    if let shortcut = view as? any ChromeShortcutRepresentable {
        return chromeCommandMenuItems(from: shortcut.chromeShortcutContent)
            .map { chromeCommandMenuItem($0, shortcut: shortcut.chromeShortcut) }
    }
    if let disabled = view as? any ChromeDisabledRepresentable {
        return chromeCommandMenuItems(from: disabled.chromeDisabledContent)
            .map { $0.disabled(disabled.chromeIsDisabled || $0.isDisabled) }
    }
    if let wrapped = view as? any ChromeWrappedViewRepresentable {
        return chromeCommandMenuItems(from: wrapped.chromeWrappedContent)
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap(chromeCommandMenuItems)
    }
    return []
}

private func chromeCommandMenuItem(_ item: CommandMenuItem, shortcut: KeyboardShortcut) -> CommandMenuItem {
    CommandMenuItem(
        item.label,
        shortcut: item.shortcut ?? shortcut,
        action: item.action
    )
    .disabled(item.isDisabled)
}

/// Alert buttons lifted out of a ViewBuilder actions tree. Role metadata is
/// not carried by `Button` values (see `ButtonRole`), so every button maps to
/// a default-role `AlertButton`; tapping any button dismisses the alert.
@MainActor
private func chromeAlertButtons(from view: any View) -> [AlertButton] {
    if let button = view as? any ChromeButtonRepresentable {
        return [AlertButton(button.chromeButtonTitle, action: button.chromeButtonAction)]
    }
    if let shortcut = view as? any ChromeShortcutRepresentable {
        return chromeAlertButtons(from: shortcut.chromeShortcutContent)
    }
    if let disabled = view as? any ChromeDisabledRepresentable {
        return chromeAlertButtons(from: disabled.chromeDisabledContent)
    }
    if let wrapped = view as? any ChromeWrappedViewRepresentable {
        return chromeAlertButtons(from: wrapped.chromeWrappedContent)
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap(chromeAlertButtons)
    }
    return []
}

// MARK: - Menu label-builder init (moved from QuillUI)

// Menu(content:label:) lives in DesignSystemSurfaceCompat.swift.

// MARK: - MenuBuilder view expressions (moved from QuillUI)

// @MainActor: reads isolated View members; builder closures run in
// isolated Commands.body / View body contexts (whole-protocol isolation).
@MainActor
extension MenuBuilder {
    public static func buildExpression(_ elements: [MenuElement]) -> [MenuElement] {
        elements
    }

    public static func buildExpression<Label: View>(_ button: Button<Label>) -> [MenuElement] {
        [.item(label: chromeTextLabel(from: button.label), action: button.action)]
    }

    public static func buildExpression<Label: View>(_ shortcutView: KeyboardShortcutView<Button<Label>>) -> [MenuElement] {
        [.item(label: chromeTextLabel(from: shortcutView.content.label), action: shortcutView.content.action)]
    }

    public static func buildExpression<Content: View>(_ disabledView: DisabledView<Content>) -> [MenuElement] {
        chromeMenuElements(from: disabledView.content)
            .map { chromeDisabledMenuElement($0, disabled: disabledView.isDisabled) }
    }

    public static func buildExpression(_ divider: Divider) -> [MenuElement] {
        [.divider]
    }

    public static func buildExpression<Content: View>(_ view: Content) -> [MenuElement] {
        chromeMenuElements(from: view)
    }
}

// MARK: - CommandMenuBuilder view expressions (moved from QuillUI)

// @MainActor: reads isolated View members; builder closures run in
// isolated Commands.body / View body contexts (whole-protocol isolation).
@MainActor
extension CommandMenuBuilder {
    public static func buildExpression<Label: View>(_ button: Button<Label>) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                chromeTextLabel(from: button.label),
                action: button.action
            )
        ]
    }

    public static func buildExpression<Label: View>(_ shortcutView: KeyboardShortcutView<Button<Label>>) -> [CommandMenuItem] {
        [
            CommandMenuItem(
                chromeTextLabel(from: shortcutView.content.label),
                shortcut: shortcutView.shortcut,
                action: shortcutView.content.action
            )
        ]
    }

    public static func buildExpression<Content: View>(_ disabledView: DisabledView<Content>) -> [CommandMenuItem] {
        chromeCommandMenuItems(from: disabledView.content)
            .map { $0.disabled(disabledView.isDisabled || $0.isDisabled) }
    }

    public static func buildExpression<Content: View>(_ view: Content) -> [CommandMenuItem] {
        chromeCommandMenuItems(from: view)
    }
}

// MARK: - CommandsBuilder: wider blocks

// SwiftOpenUI ships buildBlock for one and two children; real command trees
// (SolderScope declares four siblings) need more. Components nest leftward
// into TupleCommands, which extractCommandGroups already recurses.
// @MainActor: TupleCommands is isolated (whole-protocol Commands isolation),
// and builder blocks run inside isolated Commands.body contexts.
@MainActor
extension CommandsBuilder {
    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands>(
        _ c0: C0, _ c1: C1, _ c2: C2
    ) -> TupleCommands<TupleCommands<C0, C1>, C2> {
        TupleCommands(TupleCommands(c0, c1), c2)
    }

    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3
    ) -> TupleCommands<TupleCommands<TupleCommands<C0, C1>, C2>, C3> {
        TupleCommands(TupleCommands(TupleCommands(c0, c1), c2), c3)
    }

    public static func buildBlock<C0: Commands, C1: Commands, C2: Commands, C3: Commands, C4: Commands>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4
    ) -> TupleCommands<TupleCommands<TupleCommands<TupleCommands<C0, C1>, C2>, C3>, C4> {
        TupleCommands(TupleCommands(TupleCommands(TupleCommands(c0, c1), c2), c3), c4)
    }
}

// MARK: - WindowStyle + WindowGroup conveniences

/// SwiftUI's `WindowStyle` protocol. Styles are accepted for source
/// compatibility; GTK window decoration is not yet derived from them.
public protocol WindowStyle {}

/// The default window style.
public struct DefaultWindowStyle: WindowStyle {
    public init() {}
}

/// Apple's hidden-title-bar window style token type.
public struct HiddenTitleBarWindowStyle: WindowStyle {
    public init() {}
}

extension WindowStyle where Self == DefaultWindowStyle {
    public static var automatic: DefaultWindowStyle { DefaultWindowStyle() }
}

extension WindowStyle where Self == HiddenTitleBarWindowStyle {
    public static var hiddenTitleBar: HiddenTitleBarWindowStyle { HiddenTitleBarWindowStyle() }
}

extension WindowGroup {
    /// SwiftUI's `defaultSize(width:height:)` (moved from QuillUI); routes to
    /// SwiftOpenUI's `defaultWindowSize`.
    // defaultSize(width:height:) lives in the fork (WindowSizing.swift).

    /// Accepts a `WindowStyle`. Compile-surface: returns `self` unchanged —
    /// WindowGroup's sizing/decoration fields are internal to SwiftOpenUI, so
    /// the style cannot be recorded from this module yet; GTK windows keep
    /// their platform title bar.
    public func windowStyle<S: WindowStyle>(_ style: S) -> WindowGroup<Content> {
        if style is HiddenTitleBarWindowStyle {
            return quillHidingTitleBar()
        }
        return self
    }
}

// MARK: - Closure-based alert

extension View {
    /// SwiftUI's `alert(_:isPresented:actions:message:)` with ViewBuilder
    /// closures. Buttons declared in `actions` are lifted into `AlertButton`s
    /// (role metadata is dropped — see `ButtonRole`); the `message` view is
    /// reduced to its first text run. Routes to the existing array-based
    /// alert modifier, so presentation behavior is identical. An empty or
    /// unrecognized actions tree falls back to a single OK button so the
    /// dialog stays dismissable.
    public func alert<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> AlertModifierView<Self> {
        let buttons = chromeAlertButtons(from: actions())
        return alert(
            title,
            isPresented: isPresented,
            actions: buttons.isEmpty ? [AlertButton("OK")] : buttons,
            message: chromeTextLabel(from: message())
        )
    }
}

// MARK: - onExitCommand

extension View {
    /// SwiftUI's `onExitCommand(perform:)`. Compile-surface: returns `self`
    /// unchanged — the Escape/cancel command path is not yet wired through
    /// the GTK key controller, so the handler is accepted and never invoked.
    public func onExitCommand(perform action: (() -> Void)?) -> some View {
        self
    }
}

#endif
