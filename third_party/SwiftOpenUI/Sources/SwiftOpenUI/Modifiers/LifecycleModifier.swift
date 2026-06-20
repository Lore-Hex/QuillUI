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
    public let lifecycleID: String?
    public let action: @Sendable () async -> Void

    public init(
        content: Content,
        priority: TaskPriority,
        lifecycleID: String? = nil,
        action: @escaping @Sendable () async -> Void
    ) {
        self.content = content
        self.priority = priority
        self.lifecycleID = lifecycleID
        self.action = action
    }

    public var body: Never { fatalError("TaskView is a primitive view") }
}

private final class TaskActionBox: @unchecked Sendable {
    private let action: () async -> Void

    init(_ action: @escaping () async -> Void) {
        self.action = action
    }

    func run() async {
        await action()
    }
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
        _ action: @escaping () async -> Void
    ) -> TaskView<Self> {
        let box = TaskActionBox(action)
        return TaskView(content: self, priority: priority, action: { await box.run() })
    }
}
