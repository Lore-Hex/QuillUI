import SwiftOpenUI

// iOS 18 / macOS 15 `scrollEdgeEffectStyle(_:for:)` and its `ScrollEdgeEffectStyle`.
// Vendored real source uses it to style the soft scroll-edge fade (e.g. IceCubes
// TimelineView: `.scrollEdgeEffectStyle(.soft, for: .top)`). Inert on QuillOS —
// the GTK/Qt backends don't render an edge effect yet; this is a
// source-compatibility surface so the chain type-checks.
public enum ScrollEdgeEffectStyle: Sendable {
    case automatic
    case hard
    case soft
}

public extension View {
    func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set) -> Self {
        _ = style
        _ = edges
        return self
    }
}
