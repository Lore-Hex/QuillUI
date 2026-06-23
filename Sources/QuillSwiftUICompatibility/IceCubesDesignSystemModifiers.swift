import SwiftOpenUI
import QuillFoundation

// SwiftUI View modifiers used by vendored real source (e.g. IceCubes'
// DesignSystem: AccountPopoverView / NextPageView / ScrollToView /
// TagRowView / ToastOverlayView) that the SwiftUI shadow didn't yet provide.
// Most of these are inert on QuillOS until the GTK/Qt backends implement the
// matching behavior. `onHover` and `textSelection` are the first exceptions:
// they carry real wrappers so backends can install native pointer tracking and
// toggle native label selectability while unmodified SwiftUI-only app source
// still type-checks. These live in
// QuillSwiftUICompatibility (re-exported by the SwiftUI shadow) rather than
// QuillUI so DesignSystem, which only imports the shadow, can see them.
// HoverEffect, Visibility, TextSelectability, Edge.Set, and AnyTransition
// already exist elsewhere in this module / SwiftOpenUI.
// (SymbolEffect — with `.pulse` etc. — is declared in DesignSystemSurfaceCompat.)
//
// EVERY modifier here is `@_disfavoredOverload`. QuillUI already declares a
// *functional* twin for these (onHover→OnHoverView, listRowSeparator→
// ListRowSeparatorView, contentShape→ContentShapeView, textSelection→
// TextSelectionView, …, in QuillUI's UpstreamCompatibility.swift). QuillUI
// imports the SwiftUI shadow, so when QuillUI's own source compiles it sees
// BOTH its functional twin and these fallback overloads — an unqualified call
// would be "ambiguous use". `@_disfavoredOverload` makes the compiler prefer
// QuillUI's functional implementation whenever both are visible, while
// vendored shadow-only consumers (IceCubes, which can't see QuillUI) still
// bind to this module's fallbacks. Forgetting the attribute on any one of these
// silently breaks the *core* QuillUI build (and thus all of Linux CI), since
// this module is always compiled regardless of the IceCubes gate.

public struct QuillCompatibilityTextSelectionView<Content: View>: View {
    public let content: Content
    public let selection: TextSelectability

    public init(content: Content, selection: TextSelectability) {
        self.content = content
        self.selection = selection
    }

    public var body: Never {
        fatalError("QuillCompatibilityTextSelectionView is a backend-rendered primitive")
    }
}

public struct QuillCompatibilityOnHoverView<Content: View>: View {
    public let content: Content
    public let action: (Bool) -> Void

    public init(content: Content, action: @escaping (Bool) -> Void) {
        self.content = content
        self.action = action
    }

    public var body: Never {
        fatalError("QuillCompatibilityOnHoverView is a backend-rendered primitive")
    }
}

public extension View {
    /// Pointer-hover callback (iPadOS/macOS). Disfavored: QuillUI declares a
    /// functional `onHover` returning `OnHoverView`; callers that see both
    /// (e.g. QuillUI/Controls.swift) must bind to that one, while shadow-only
    /// vendored DesignSystem source uses this metadata wrapper.
    @_disfavoredOverload
    func onHover(perform action: @escaping (Bool) -> Void) -> QuillCompatibilityOnHoverView<Self> {
        QuillCompatibilityOnHoverView(content: self, action: action)
    }

    /// Interaction hit-test shape. QuillUI declares a functional
    /// `contentShape` returning a `ContentShapeView`.
    @_disfavoredOverload
    func contentShape<S: Shape>(_ shape: S) -> Self {
        _ = shape
        return self
    }

    /// Whether the view's text is user-selectable. Disfavored so QuillUI's
    /// functional overload wins for callers that see both; shadow-only vendored
    /// source keeps this metadata wrapper.
    @_disfavoredOverload
    func textSelection(_ selectability: TextSelectability) -> QuillCompatibilityTextSelectionView<Self> {
        QuillCompatibilityTextSelectionView(content: self, selection: selectability)
    }

    /// Drive an SF Symbol effect from an `Equatable` value (iOS 17+). Inert.
    @_disfavoredOverload
    func symbolEffect<V: Equatable>(_ effect: SymbolEffect, value: V) -> Self {
        _ = effect
        _ = value
        return self
    }

    @_disfavoredOverload
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
    /// Disfavored so QuillUI's functional `allowsHitTesting` wins for callers
    /// that see both.
    @_disfavoredOverload
    func allowsHitTesting(_ enabled: Bool) -> Self {
        _ = enabled
        return self
    }

    /// List-row content insets. QuillUI declares a functional `listRowInsets`
    /// returning a `ListRowInsetsView`. (`EdgeInsets` comes from SwiftOpenUI.)
    @_disfavoredOverload
    func listRowInsets(_ insets: EdgeInsets?) -> Self {
        _ = insets
        return self
    }

    /// Hierarchical / SF-Symbol-palette `foregroundStyle` (2- and 3-color
    /// forms, e.g. IceCubes AppAccountView's `.foregroundStyle(.white, .green)`).
    /// The shadow only had the single-style form. Only the primary color is
    /// meaningful headless; the secondary/tertiary palette colors are inert.
    @_disfavoredOverload
    func foregroundStyle(_ primary: Color, _ secondary: Color) -> Self {
        _ = primary
        _ = secondary
        return self
    }

    @_disfavoredOverload
    func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> Self {
        _ = primary
        _ = secondary
        _ = tertiary
        return self
    }
}
