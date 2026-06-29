/// A scene that presents a single unique window identified by a string.
///
/// Unlike `WindowGroup`, which can create multiple window instances,
/// `Window` represents a single window that is opened and closed by id.
public struct Window<Content: View>: Scene {
    public typealias Body = Never

    public let title: String
    public let id: String
    public let content: Content
    public let defaultWindowWidth: Double?
    public let defaultWindowHeight: Double?
    public let minWindowWidth: Double?
    public let minWindowHeight: Double?
    public let launchBehavior: WindowLaunchBehavior

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
        self.defaultWindowWidth = nil
        self.defaultWindowHeight = nil
        self.minWindowWidth = nil
        self.minWindowHeight = nil
        self.launchBehavior = .automatic
    }

    init(
        title: String,
        id: String,
        content: Content,
        defaultWindowWidth: Double?,
        defaultWindowHeight: Double?,
        minWindowWidth: Double?,
        minWindowHeight: Double?,
        launchBehavior: WindowLaunchBehavior
    ) {
        self.title = title
        self.id = id
        self.content = content
        self.defaultWindowWidth = defaultWindowWidth
        self.defaultWindowHeight = defaultWindowHeight
        self.minWindowWidth = minWindowWidth
        self.minWindowHeight = minWindowHeight
        self.launchBehavior = launchBehavior
    }

    public var body: Never { fatalError("Window is a primitive scene") }

    public func defaultWindowSize(width: Double, height: Double) -> Window<Content> {
        Window(
            title: title, id: id, content: content,
            defaultWindowWidth: width, defaultWindowHeight: height,
            minWindowWidth: minWindowWidth, minWindowHeight: minWindowHeight,
            launchBehavior: launchBehavior
        )
    }

    public func defaultLaunchBehavior(_ behavior: WindowLaunchBehavior) -> Window<Content> {
        Window(
            title: title, id: id, content: content,
            defaultWindowWidth: defaultWindowWidth, defaultWindowHeight: defaultWindowHeight,
            minWindowWidth: minWindowWidth, minWindowHeight: minWindowHeight,
            launchBehavior: behavior
        )
    }
}

/// Controls whether a window is shown at application launch.
public enum WindowLaunchBehavior: Sendable {
    /// Backend default — typically shown at launch.
    case automatic
    /// Window is not shown at launch; opened programmatically via `openWindow`.
    case suppressed
}

public enum SwiftOpenUIWindowLifecycleEventKind: Sendable {
    case didOpen
    case didClose
}

public struct SwiftOpenUIWindowLifecycleEvent: Sendable {
    public let kind: SwiftOpenUIWindowLifecycleEventKind
    public let id: String
    public let title: String
    public let nativeHandle: Int?

    public init(kind: SwiftOpenUIWindowLifecycleEventKind, id: String, title: String, nativeHandle: Int?) {
        self.kind = kind
        self.id = id
        self.title = title
        self.nativeHandle = nativeHandle
    }
}

@MainActor
public enum SwiftOpenUIWindowLifecycle {
    public typealias Handler = @MainActor (SwiftOpenUIWindowLifecycleEvent) -> Void

    private static var handlers: [Handler] = []

    public static func addHandler(_ handler: @escaping Handler) {
        handlers.append(handler)
    }

    public static func notifyWindowOpened(id: String, title: String, nativeHandle: Int? = nil) {
        notify(.init(kind: .didOpen, id: id, title: title, nativeHandle: nativeHandle))
    }

    public static func notifyWindowClosed(id: String, title: String = "", nativeHandle: Int? = nil) {
        notify(.init(kind: .didClose, id: id, title: title, nativeHandle: nativeHandle))
    }

    private static func notify(_ event: SwiftOpenUIWindowLifecycleEvent) {
        for handler in handlers {
            handler(event)
        }
    }
}
