/// A view that fires an action when it appears on screen.
public struct OnAppearView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let action: () -> Void

    public var body: Never { fatalError("OnAppearView is a primitive view") }
}

/// A view that fires an action when it disappears from screen.
public struct OnDisappearView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let action: () -> Void

    public var body: Never { fatalError("OnDisappearView is a primitive view") }
}

/// A view that starts an asynchronous task when it appears on screen.
public struct TaskView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let priority: TaskPriority
    public let action: @Sendable () async -> Void

    public var body: Never { fatalError("TaskView is a primitive view") }
}

extension View {
    /// Perform an action when the view appears.
    public func onAppear(_ action: @escaping () -> Void) -> OnAppearView<Self> {
        OnAppearView(content: self, action: action)
    }

    /// Perform an action when the view disappears.
    public func onDisappear(_ action: @escaping () -> Void) -> OnDisappearView<Self> {
        OnDisappearView(content: self, action: action)
    }

    /// Start an asynchronous task for this view's lifecycle.
    public func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> TaskView<Self> {
        TaskView(content: self, priority: priority, action: action)
    }
}
