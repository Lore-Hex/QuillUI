/// A view with another view layered on top.
public struct OverlayView<Content: View, Overlay: View>: View {
    public typealias Body = Never

    public let content: Content
    public let overlay: Overlay
    public let alignment: Alignment

    public init(content: Content, overlay: Overlay, alignment: Alignment) {
        self.content = content
        self.overlay = overlay
        self.alignment = alignment
    }

    public var body: Never { fatalError("OverlayView is a primitive view") }
}

extension View {
    /// Layer an overlay view on top of this view.
    public func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> OverlayView<Self, V> {
        OverlayView(content: self, overlay: overlay, alignment: alignment)
    }

    /// Concrete Color overload beside the generic (mirrors `background`'s
    /// concrete-Color + generic pair in StyleModifiers.swift): enables
    /// implicit-member calls (`.overlay(.red)`) — and it must live in THIS
    /// module: the same adapter in QuillSwiftUICompatibility formed a
    /// cross-module concrete-vs-generic pair on every Color argument (Color
    /// is a View), the ambiguity disease. Same-module ranking is reliable.
    public func overlay(_ color: Color, alignment: Alignment = .center) -> OverlayView<Self, Color> {
        OverlayView(content: self, overlay: color, alignment: alignment)
    }

    /// Layer an overlay view on top of this view.
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder _ overlay: () -> V) -> OverlayView<Self, V> {
        OverlayView(content: self, overlay: overlay(), alignment: alignment)
    }

    /// SwiftUI-compatible labeled content closure.
    @_disfavoredOverload
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> OverlayView<Self, V> {
        OverlayView(content: self, overlay: content(), alignment: alignment)
    }
}
