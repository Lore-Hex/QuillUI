/// A transparent grouping container that flattens its children
/// into the parent container without introducing an extra wrapper.
/// Use Group to work around the ViewBuilder child limit.
public struct Group<Content> {
    public let content: Content
}

extension Group: View, PrimitiveView, MultiChildView, TransparentMultiChildView where Content: View {
    public typealias Body = Never

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { fatalError("Group is a primitive view") }

    public var children: [any View] {
        if let multi = content as? MultiChildView {
            return multi.children
        }
        return [content]
    }
}

extension Group: Scene where Content: Scene {
    public typealias Body = Never

    public init(@SceneBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { fatalError("Group is a primitive scene") }
}

extension Group: Commands where Content: Commands {
    public typealias Body = Never

    public init(@CommandsBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: Never { fatalError("Group is a primitive commands container") }
}
