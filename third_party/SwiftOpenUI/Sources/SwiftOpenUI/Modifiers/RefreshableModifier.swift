/// A view that exposes an asynchronous refresh action to scrollable backends.
public struct RefreshableView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let action: @Sendable () async -> Void

    public init(content: Content, action: @escaping @Sendable () async -> Void) {
        self.content = content
        self.action = action
    }

    public var body: Never { fatalError("RefreshableView is a primitive view") }
}

private final class RefreshActionBox: @unchecked Sendable {
    private let action: () async -> Void

    init(_ action: @escaping () async -> Void) {
        self.action = action
    }

    func run() async {
        await action()
    }
}

extension View {
    /// Attach an asynchronous refresh action to the nearest scrollable surface.
    public func refreshable(action: @escaping () async -> Void) -> RefreshableView<Self> {
        let box = RefreshActionBox(action)
        return RefreshableView(content: self, action: { await box.run() })
    }
}
