import Foundation

// SwiftUI View-modifier surface MOVED here from QuillUI/UpstreamCompatibility so a
// single canonical declaration is visible to BOTH QuillUI (via @_exported import
// SwiftOpenUI) and vendored real source (DesignSystem, which imports SwiftOpenUI
// through the SwiftUI shadow). These are metadata-passthrough modifiers that GTK
// does not render from here, so they are no-ops on Linux. (Having two copies — in
// QuillUI and here — makes their use ambiguous, hence the move.)
public struct SymbolEffect: Sendable {
    public init() {}
    public static let variableColor = SymbolEffect()
    public static let pulse = SymbolEffect()
    public static let bounce = SymbolEffect()
    public static let scale = SymbolEffect()
    public static let appear = SymbolEffect()
    public static let disappear = SymbolEffect()
    public var iterative: SymbolEffect { self }
}
public struct SymbolEffectOptions: Sendable {
    public init() {}
    public static let `default` = SymbolEffectOptions()
    public static func `repeat`(_ count: Int) -> SymbolEffectOptions { SymbolEffectOptions() }
}

public struct ListStyleType: Sendable {
    private let id: String
    public static let automatic = ListStyleType(id: "automatic")
    public static let plain = ListStyleType(id: "plain")
    public static let grouped = ListStyleType(id: "grouped")
    public static let inset = ListStyleType(id: "inset")
    public static let insetGrouped = ListStyleType(id: "insetGrouped")
    public static let sidebar = ListStyleType(id: "sidebar")
    public static let bordered = ListStyleType(id: "bordered")
}

public struct AccessibilityChildBehavior: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let ignore = AccessibilityChildBehavior("ignore")
    public static let combine = AccessibilityChildBehavior("combine")
    public static let contain = AccessibilityChildBehavior("contain")
}

extension View {
    // Typed-view modifiers MOVED from QuillUI/UpstreamCompatibility (struct + func)
    // so vendored source (imports SwiftOpenUI, not QuillUI) can use them while
    // QuillUI's own CompatibilityModuleTests — which assert each returns a named
    // view carrying its parameter (.shape/.enabled/.action/.visibility/.edges/.insets)
    // — keep passing via QuillUI's @_exported import SwiftOpenUI. The `.circle`
    // / Rectangle() cases resolve through the generic (Shape.circle returns Circle).
    public func contentShape<S: Shape>(_ shape: S) -> ContentShapeView<Self, S> {
        ContentShapeView(content: self, shape: shape)
    }
    public func onHover(perform action: @escaping (Bool) -> Void) -> OnHoverView<Self> {
        OnHoverView(content: self, action: action)
    }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func allowsHitTesting(_ enabled: Bool) -> AllowsHitTestingView<Self> {
        AllowsHitTestingView(content: self, enabled: enabled)
    }
    public func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> ListRowSeparatorView<Self> {
        ListRowSeparatorView(content: self, visibility: visibility, edges: edges)
    }
    public func accessibilityLabel<S>(_ label: S) -> some View { self }
    public func accessibilityValue<S>(_ value: S) -> some View { self }
    public func listRowInsets(_ insets: EdgeInsets?) -> ListRowInsetsView<Self> {
        ListRowInsetsView(content: self, insets: insets)
    }
    public func listStyle(_ style: ListStyleType) -> some View { self }
    public func symbolEffect<Value: Equatable>(_ effect: SymbolEffect, options: SymbolEffectOptions = .default, value: Value) -> some View {
        animation(.easeInOut(duration: 0.2), value: value)
    }
}

// Typed passthrough views (moved from QuillUI/UpstreamCompatibility). Each stores
// its parameter and renders `content` (GTK does not paint these from here). Names
// are load-bearing: CompatibilityModuleTests checks `type(of:)` contains them.
public struct ContentShapeView<Content: View, ShapeValue: Shape>: View {
    public let content: Content
    public let shape: ShapeValue
    public init(content: Content, shape: ShapeValue) {
        self.content = content
        self.shape = shape
    }
    public var body: some View { content }
}

public struct OnHoverView<Content: View>: View {
    public let content: Content
    public let action: (Bool) -> Void
    public init(content: Content, action: @escaping (Bool) -> Void) {
        self.content = content
        self.action = action
    }
    public var body: some View { content }
}

public struct AllowsHitTestingView<Content: View>: View {
    public let content: Content
    public let enabled: Bool
    public init(content: Content, enabled: Bool) {
        self.content = content
        self.enabled = enabled
    }
    public var body: some View { content }
}

public struct ListRowSeparatorView<Content: View>: View {
    public let content: Content
    public let visibility: Visibility
    public let edges: Edge.Set
    public init(content: Content, visibility: Visibility, edges: Edge.Set) {
        self.content = content
        self.visibility = visibility
        self.edges = edges
    }
    public var body: some View { content }
}

public struct ListRowInsetsView<Content: View>: View {
    public let content: Content
    public let insets: EdgeInsets?
    public init(content: Content, insets: EdgeInsets?) {
        self.content = content
        self.insets = insets
    }
    public var body: some View { content }
}
