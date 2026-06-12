/// A view with an explicit size or size constraints.
public struct FrameView<Content: View>: View, PrimitiveView {
    public typealias Body = Never

    public let content: Content
    public let width: Double?
    public let height: Double?
    public let minWidth: Double?
    public let minHeight: Double?
    public let maxWidth: Double?
    public let maxHeight: Double?
    public let alignment: Alignment

    public var body: Never { fatalError("FrameView is a primitive view") }
}

extension View {
    /// Set an explicit fixed size.
    public func frame(
        width: Double? = nil,
        height: Double? = nil,
        alignment: Alignment = .center
    ) -> FrameView<Self> {
        FrameView(
            content: self,
            width: width, height: height,
            minWidth: nil, minHeight: nil,
            maxWidth: nil, maxHeight: nil,
            alignment: alignment
        )
    }

    // SwiftUI-typed adapter (Int width/height). Declared in this module —
    // NOT a compat module — for the same reason as PaddingModifier's
    // Double/Int? adapters: the cross-module twin of the Double? overload
    // above (it lived in QuillSwiftUICompatibility) made integer-literal
    // calls like `.frame(width: 800, height: 600)` ambiguous, which the
    // expression solver reported as "ambiguous use of 'padding'" at the
    // head of the chain (generated Enchanted CompletionsEditorView).
    // Same-module ranking is reliable; disfavored so the canonical Double?
    // overload keeps winning literal calls.
    @_disfavoredOverload
    public func frame(
        width: Int? = nil,
        height: Int? = nil,
        alignment: Alignment = .center
    ) -> FrameView<Self> {
        frame(
            width: width.map(Double.init),
            height: height.map(Double.init),
            alignment: alignment
        )
    }

    /// Set flexible size constraints.
    public func frame(
        minWidth: Double? = nil,
        idealWidth: Double? = nil,
        maxWidth: Double? = nil,
        minHeight: Double? = nil,
        idealHeight: Double? = nil,
        maxHeight: Double? = nil,
        alignment: Alignment = .center
    ) -> FrameView<Self> {
        FrameView(
            content: self,
            width: idealWidth, height: idealHeight,
            minWidth: minWidth, minHeight: minHeight,
            maxWidth: maxWidth, maxHeight: maxHeight,
            alignment: alignment
        )
    }
}
