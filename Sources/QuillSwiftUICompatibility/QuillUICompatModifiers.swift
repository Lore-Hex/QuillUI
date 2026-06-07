import QuillKit
import SwiftOpenUI

// SwiftUI View-modifier compatibility surface that vendored upstream source
// (DesignSystem, AppAccount, …) uses but that must ALSO be visible to QuillUI's
// own code/tests. This layer is the right home because it is:
//   • re-exported to vendored source via the `SwiftUI` shadow
//     (`@_exported import QuillSwiftUICompatibility`), and
//   • re-exported to QuillUI consumers (`QuillUI` does the same), and
//   • able to record QuillKit compatibility diagnostics — unlike SwiftOpenUI,
//     which is a separate lower package that cannot import QuillKit.
// Each modifier returns a named typed view carrying its parameter (so
// CompatibilityModuleTests' type/member assertions pass) and records a
// fallback diagnostic (so the "fallback modifiers record diagnostics" test
// sees the operation). GTK does not paint these from here — they are
// hit-testing / list-layout metadata passthroughs.

private func recordQuillUICompatFallback(_ operation: String, message: String) {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "QuillUI",
        operation: operation,
        severity: .info,
        message: message
    )
}

public struct ContentShapeView<Content: View, ShapeValue: Shape>: View {
    public let content: Content
    public let shape: ShapeValue
    public init(content: Content, shape: ShapeValue) {
        self.content = content
        self.shape = shape
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

public struct ListRowInsetsView<Content: View>: View {
    public let content: Content
    public let insets: EdgeInsets?
    public init(content: Content, insets: EdgeInsets?) {
        self.content = content
        self.insets = insets
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

// (scrollContentBackground stays in QuillUI on this branch; AppAccount's #441
//  moves it here alongside the others.)

extension View {
    public func contentShape<S: Shape>(_ shape: S) -> ContentShapeView<Self, S> {
        recordQuillUICompatFallback(
            "contentShape",
            message: "contentShape is preserved as hit-testing shape metadata on Linux."
        )
        return ContentShapeView(content: self, shape: shape)
    }

    public func allowsHitTesting(_ enabled: Bool) -> AllowsHitTestingView<Self> {
        recordQuillUICompatFallback(
            "allowsHitTesting",
            message: "allowsHitTesting is preserved as hit-testing metadata on Linux."
        )
        return AllowsHitTestingView(content: self, enabled: enabled)
    }

    public func listRowInsets(_ insets: EdgeInsets?) -> ListRowInsetsView<Self> {
        recordQuillUICompatFallback(
            "listRowInsets",
            message: "listRowInsets is preserved as list row layout metadata on Linux."
        )
        return ListRowInsetsView(content: self, insets: insets)
    }

    public func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> ListRowSeparatorView<Self> {
        recordQuillUICompatFallback(
            "listRowSeparator",
            message: "listRowSeparator is preserved as list row separator metadata on Linux."
        )
        return ListRowSeparatorView(content: self, visibility: visibility, edges: edges)
    }

    public func symbolEffect<Value: Equatable>(
        _ effect: SymbolEffect,
        options: SymbolEffectOptions = .default,
        value: Value
    ) -> AnimatedView<Self> {
        recordQuillUICompatFallback(
            "symbolEffect",
            message: "symbolEffect is approximated with value-driven animation on Linux."
        )
        return animation(.easeInOut(duration: 0.2), value: value)
    }
}
