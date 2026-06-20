/// Modifier that registers a navigation destination factory for path-based navigation.
public struct NavigationDestinationModifier<Content: View, D: Hashable, Destination: View>: View {
    public typealias Body = Never

    public let content: Content
    public let dataType: D.Type
    public let destination: (D) -> Destination

    public var body: Never { fatalError("NavigationDestinationModifier is a primitive view") }
}

/// Modifier that pushes a destination when a Boolean binding becomes true.
public struct NavigationPresentedDestinationModifier<Content: View, Destination: View>: View {
    public typealias Body = Never

    public let content: Content
    public let isPresented: Binding<Bool>
    public let destination: () -> Destination

    public init(
        content: Content,
        isPresented: Binding<Bool>,
        destination: @escaping () -> Destination
    ) {
        self.content = content
        self.isPresented = isPresented
        self.destination = destination
    }

    public var body: Never { fatalError("NavigationPresentedDestinationModifier is a primitive view") }
}

extension View {
    /// Register a destination view factory for NavigationPath-based navigation.
    ///
    /// ```swift
    /// NavigationStack(path: $path) {
    ///     List { ... }
    /// }
    /// .navigationDestination(for: String.self) { value in
    ///     Text("Detail: \(value)")
    /// }
    /// ```
    public func navigationDestination<D: Hashable, Destination: View>(
        for data: D.Type,
        @ViewBuilder destination: @escaping (D) -> Destination
    ) -> NavigationDestinationModifier<Self, D, Destination> {
        NavigationDestinationModifier(content: self, dataType: data, destination: destination)
    }

    /// Register a destination view that is pushed while `isPresented` is true.
    public func navigationDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> NavigationPresentedDestinationModifier<Self, Destination> {
        NavigationPresentedDestinationModifier(
            content: self,
            isPresented: isPresented,
            destination: destination
        )
    }
}
