import SwiftOpenUI
import QuillFoundation

// SwiftUI View modifiers used by vendored real source (e.g. IceCubes'
// DesignSystem: AccountPopoverView / NextPageView / ScrollToView /
// TagRowView / ToastOverlayView) that the SwiftUI shadow didn't yet provide.
// All inert on QuillOS — the GTK/Qt backends don't implement pointer-hover,
// SF-symbol animation, list-row-separator styling, or hit-test masking yet —
// so this is a source-compatibility surface that lets the unmodified app
// type-check. These live in QuillSwiftUICompatibility (re-exported by the
// SwiftUI shadow) rather than QuillUI so DesignSystem, which only imports the
// shadow, can see them. HoverEffect, Visibility, TextSelectability, Edge.Set,
// and AnyTransition already exist elsewhere in this module / SwiftOpenUI.
// (SymbolEffect — with `.pulse` etc. — is declared in DesignSystemSurfaceCompat.)

public extension View {
    /// Pointer-hover callback (iPadOS/macOS). Inert headless. Disfavored:
    /// QuillUI declares a functional `onHover` returning `OnHoverView`;
    /// callers that see both (e.g. QuillUI/Controls.swift) must bind to that
    /// one, while shadow-only vendored DesignSystem source uses this fallback.
    @_disfavoredOverload
    func onHover(perform action: @escaping (Bool) -> Void) -> Self {
        _ = action
        return self
    }

    /// Interaction hit-test shape. Disfavored because QuillUI declares a
    /// `contentShape` returning a `ContentShapeView`; callers that see both
    /// (e.g. the compat-module tests) bind to that richer one, while
    /// shadow-only vendored source (DesignSystem) uses this inert fallback.
    @_disfavoredOverload
    func contentShape<S: Shape>(_ shape: S) -> Self {
        _ = shape
        return self
    }

    /// Whether the view's text is user-selectable. Inert headless.
    func textSelection(_ selectability: TextSelectability) -> Self {
        _ = selectability
        return self
    }

    /// Drive an SF Symbol effect from an `Equatable` value (iOS 17+). Inert.
    func symbolEffect<V: Equatable>(_ effect: SymbolEffect, value: V) -> Self {
        _ = effect
        _ = value
        return self
    }

    func symbolEffect(_ effect: SymbolEffect) -> Self {
        _ = effect
        return self
    }

    /// List-row separator visibility (and which edges). Inert headless.
    /// Disfavored: QuillUI declares a functional `listRowSeparator` returning
    /// `ListRowSeparatorView`; callers that see both must bind to that one.
    @_disfavoredOverload
    func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> Self {
        _ = visibility
        _ = edges
        return self
    }

    /// Whether the view participates in hit-testing. Inert headless.
    func allowsHitTesting(_ enabled: Bool) -> Self {
        _ = enabled
        return self
    }

    /// List-row content insets. Disfavored because QuillUI declares a
    /// `listRowInsets` returning a `ListRowInsetsView`; shadow-only vendored
    /// source (DesignSystem ScrollToView's `.listRowInsets(.init())`) uses this
    /// inert fallback. (`EdgeInsets` comes from SwiftOpenUI.)
    @_disfavoredOverload
    func listRowInsets(_ insets: EdgeInsets?) -> Self {
        _ = insets
        return self
    }

    /// Hierarchical / SF-Symbol-palette `foregroundStyle` (2- and 3-color
    /// forms, e.g. IceCubes AppAccountView's `.foregroundStyle(.white, .green)`).
    /// The shadow only had the single-style form. Only the primary color is
    /// meaningful headless; the secondary/tertiary palette colors are inert.
    func foregroundStyle(_ primary: Color, _ secondary: Color) -> Self {
        _ = primary
        _ = secondary
        return self
    }

    func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Self {
        _ = primary
        _ = secondary
        _ = tertiary
        return self
    }
}
