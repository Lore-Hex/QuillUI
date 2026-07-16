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

/// A frame whose size is derived from the nearest container's proposal.
///
/// SwiftUI uses this primitive for paged media, galleries, and other views
/// whose item width is a fraction of a scroll viewport. Keeping the division
/// metadata intact lets each backend resolve the size after its native parent
/// has received a real allocation.
public struct ContainerRelativeFrameView<Content: View>: View, PrimitiveView {
    public typealias Body = Never

    public let content: Content
    public let axes: Axis
    public let count: Int
    public let span: Int
    public let spacing: Double
    public let alignment: Alignment

    public init(
        content: Content,
        axes: Axis,
        count: Int,
        span: Int,
        spacing: Double,
        alignment: Alignment
    ) {
        self.content = content
        self.axes = axes
        self.count = count
        self.span = span
        self.spacing = spacing
        self.alignment = alignment
    }

    public var body: Never { fatalError("ContainerRelativeFrameView is a primitive view") }

    /// Resolve one axis using SwiftUI's count/span/spacing division.
    public func resolvedLength(in containerLength: Double) -> Double {
        let resolvedCount = max(1, count)
        let resolvedSpan = min(max(1, span), resolvedCount)
        let resolvedSpacing = max(0, spacing)
        let available = max(0, containerLength - Double(resolvedCount - 1) * resolvedSpacing)
        let itemLength = available / Double(resolvedCount)
        return itemLength * Double(resolvedSpan) + Double(resolvedSpan - 1) * resolvedSpacing
    }
}

extension View {
    /// Set only frame alignment without changing size constraints.
    public func frame(alignment: Alignment) -> FrameView<Self> {
        FrameView(
            content: self,
            width: nil, height: nil,
            minWidth: nil, minHeight: nil,
            maxWidth: nil, maxHeight: nil,
            alignment: alignment
        )
    }

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

    /// Size this view relative to the nearest container on the selected axes.
    public func containerRelativeFrame(
        _ axes: Axis,
        alignment: Alignment = .center
    ) -> ContainerRelativeFrameView<Self> {
        ContainerRelativeFrameView(
            content: self,
            axes: axes,
            count: 1,
            span: 1,
            spacing: 0,
            alignment: alignment
        )
    }

    /// Divide the nearest container into equally sized slots and occupy a span.
    public func containerRelativeFrame(
        _ axes: Axis,
        count: Int,
        span: Int,
        spacing: Double,
        alignment: Alignment = .center
    ) -> ContainerRelativeFrameView<Self> {
        ContainerRelativeFrameView(
            content: self,
            axes: axes,
            count: count,
            span: span,
            spacing: spacing,
            alignment: alignment
        )
    }
}
