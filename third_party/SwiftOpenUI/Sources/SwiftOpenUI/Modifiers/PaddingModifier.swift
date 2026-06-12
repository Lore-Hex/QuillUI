/// A view with padding applied around its content.
public struct PaddedView<Content: View>: View, PrimitiveView {
    public typealias Body = Never

    public let content: Content
    public let top: Int
    public let bottom: Int
    public let leading: Int
    public let trailing: Int

    public var body: Never { fatalError("PaddedView is a primitive view") }
}

extension View {
    /// Bare `.padding()`: explicit zero-arity overload so the call never
    /// has to tie-break between the two defaulted candidates below — the
    /// compiler ruled that genuinely ambiguous once the compat overload
    /// surface grew (generated Enchanted build, ChatMessageView).
    public func padding() -> PaddedView<Self> {
        padding(8)
    }

    /// Apply uniform padding on all sides. No default: bare `.padding()` is
    /// served by the explicit zero-arity overload above, and a default here
    /// made the two tie inside ViewBuilder closures.
    public func padding(_ amount: Int) -> PaddedView<Self> {
        PaddedView(content: self, top: amount, bottom: amount, leading: amount, trailing: amount)
    }

    /// Apply padding with specific values per edge. (Partial labels rely on
    /// the defaults; bare `.padding()` prefers the exact zero-arity overload
    /// because this one would need four defaults filled.)
    public func padding(top: Int = 0, bottom: Int = 0, leading: Int = 0, trailing: Int = 0) -> PaddedView<Self> {
        PaddedView(content: self, top: top, bottom: bottom, leading: leading, trailing: trailing)
    }

    // SwiftUI-typed adapters (Double/CGFloat?/Int? amounts). Declared in this
    // module — NOT a compat module — because cross-module overloads (even
    // disfavored ones) make bare `.padding()` ambiguous in generic contexts.
    @_disfavoredOverload
    public func padding(_ amount: Double) -> PaddedView<Self> {
        padding(Int(amount))
    }

    @_disfavoredOverload
    public func padding(_ edges: Edge.Set, _ amount: Double) -> PaddedView<Self> {
        padding(edges, Int(amount))
    }

    @_disfavoredOverload
    public func padding(_ edges: Edge.Set, _ amount: Int?) -> PaddedView<Self> {
        padding(edges, amount ?? 8)
    }

    // (No CGFloat? adapter here: CGFloat is QuillFoundation's on Linux and
    // this module stays platform-independent. Double? covers those calls.)
    @_disfavoredOverload
    public func padding(_ edges: Edge.Set, _ amount: Double?) -> PaddedView<Self> {
        padding(edges, Int(amount ?? 8))
    }

    /// SwiftUI-compatible edge-set padding.
    public func padding(_ edges: Edge.Set, _ amount: Int = 8) -> PaddedView<Self> {
        PaddedView(
            content: self,
            top: edges.contains(.top) ? amount : 0,
            bottom: edges.contains(.bottom) ? amount : 0,
            leading: edges.contains(.leading) ? amount : 0,
            trailing: edges.contains(.trailing) ? amount : 0
        )
    }
}
