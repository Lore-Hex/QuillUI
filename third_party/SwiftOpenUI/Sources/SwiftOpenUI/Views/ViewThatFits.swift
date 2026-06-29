/// A container that displays the first child view whose measured size fits
/// within the available space, falling back to the last child if none fit.
public struct ViewThatFits: View, PrimitiveView {
    public typealias Body = Never

    public let children: [AnyView]

    public init<Content: View>(@ViewBuilder content: () -> Content) {
        self.children = Self.flatten(content()).map { AnyView(erasing: $0) }
    }

    public init(children: [AnyView]) {
        self.children = children
    }

    public var body: Never { fatalError("ViewThatFits is a primitive view") }

    private static func flatten(_ view: any View) -> [any View] {
        if let multi = view as? any TransparentMultiChildView {
            return multi.children.flatMap(flatten)
        }
        return [view]
    }
}

/// Result builder retained for source compatibility with early SwiftOpenUI
/// snapshots. New ViewThatFits call sites use standard ViewBuilder lowering.
@resultBuilder
public enum ViewThatFitsBuilder {
    public static func buildBlock(_ components: [AnyView]...) -> [AnyView] {
        components.flatMap { $0 }
    }

    public static func buildPartialBlock(first component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildPartialBlock(accumulated: [AnyView], next: [AnyView]) -> [AnyView] {
        accumulated + next
    }

    public static func buildExpression<Content: View>(_ expression: Content) -> [AnyView] {
        [AnyView(expression)]
    }

    public static func buildExpression(_ expression: AnyView) -> [AnyView] {
        [expression]
    }

    public static func buildOptional(_ component: [AnyView]?) -> [AnyView] {
        component ?? []
    }

    public static func buildEither(first component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildEither(second component: [AnyView]) -> [AnyView] {
        component
    }

    public static func buildArray(_ components: [[AnyView]]) -> [AnyView] {
        components.flatMap { $0 }
    }
}
