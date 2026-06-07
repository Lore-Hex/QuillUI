import Foundation

// SwiftUI surface used by vendored IceCubes packages (AppAccount/StatusKit/…)
// not yet in SwiftOpenUI. Additive, no-op on the Linux backend; reusable by all
// app ports. (Confirmed absent from QuillUI + SwiftOpenUI core, so no ambiguity.)

public struct Transaction: Sendable {
    public var disablesAnimations = false
    public var animation: Animation?
    public init() {}
}
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result { try body() }
public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R { try body() }

public enum ControlSize: Sendable, Hashable { case mini, small, regular, large, extraLarge }

public struct PresentationDetent: Hashable, Sendable {
    private let id: String
    public static let medium = PresentationDetent(id: "medium")
    public static let large = PresentationDetent(id: "large")
    public static func height(_ height: CGFloat) -> PresentationDetent { PresentationDetent(id: "h\(height)") }
    public static func fraction(_ fraction: CGFloat) -> PresentationDetent { PresentationDetent(id: "f\(fraction)") }
}

public struct NavigationTransition: Sendable {
    public static let automatic = NavigationTransition()
    public static func zoom(sourceID: some Hashable, in namespace: Namespace.ID) -> NavigationTransition { NavigationTransition() }
}

public enum TitleDisplayMode: Sendable { case automatic, inline, large }

public struct AccessibilityTraits: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let isButton = AccessibilityTraits(rawValue: 1 << 0)
    public static let isHeader = AccessibilityTraits(rawValue: 1 << 1)
    public static let isSelected = AccessibilityTraits(rawValue: 1 << 2)
    public static let isImage = AccessibilityTraits(rawValue: 1 << 3)
}

extension View {
    public func controlSize(_ size: ControlSize) -> some View { self }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    public func navigationTransition(_ transition: NavigationTransition) -> some View { self }
    public func navigationBarTitleDisplayMode(_ mode: TitleDisplayMode) -> some View { self }
    public func accessibilityHint<S>(_ hint: S) -> some View { self }
    public func accessibilityRepresentation<V: View>(@ViewBuilder representation: () -> V) -> some View { self }
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> some View { self }
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View { self }
}

extension ButtonStyleType { public static var glass: ButtonStyleType { .automatic } }
extension ToolbarItemPlacement { public static var navigationBarTrailing: ToolbarItemPlacement { .trailing } }
extension Shape where Self == Circle { public static var circle: Circle { Circle() } }
extension View {
    public func scrollContentBackground(_ visibility: Visibility) -> ScrollContentBackgroundView<Self> {
        ScrollContentBackgroundView(content: self, visibility: visibility)
    }
}

// Typed passthrough (moved from QuillUI). Name + .visibility are asserted by
// CompatibilityModuleTests; reaches both QuillUI (re-export) and vendored source.
public struct ScrollContentBackgroundView<Content: View>: View {
    public let content: Content
    public let visibility: Visibility
    public init(content: Content, visibility: Visibility) {
        self.content = content
        self.visibility = visibility
    }
    public var body: some View { content }
}

public struct Material: Sendable {
    public static let ultraThin = Material()
    public static let thin = Material()
    public static let regular = Material()
    public static let thick = Material()
    public static let ultraThick = Material()
    public static let bar = Material()
    public static let ultraThinMaterial = Material()
    public static let thinMaterial = Material()
    public static let regularMaterial = Material()
    public static let thickMaterial = Material()
}

extension View {
    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> some View { foregroundColor(primary) }
    public func foregroundStyle(_ primary: Color, _ secondary: Color, _ tertiary: Color) -> some View { foregroundColor(primary) }
    public func presentationBackground(_ material: Material) -> some View { self }
    public func presentationCornerRadius(_ radius: CGFloat) -> some View { self }
    public func presentationBackground<S>(_ style: S) -> some View { self }
}

extension View {
    // SwiftUI contextMenu takes arbitrary @ViewBuilder menu content (ForEach/Button),
    // not just SwiftOpenUI MenuItems. No-op on GTK; lets vendored source compile.
    public func contextMenu<MenuItems: View>(@ViewBuilder menuItems: () -> MenuItems) -> some View { self }
}
