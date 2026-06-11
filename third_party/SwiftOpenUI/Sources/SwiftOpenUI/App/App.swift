/// A type that represents the structure and behavior of an app.
///
/// Platform backends provide the concrete app lifecycle (GTK application,
/// Win32 message loop, etc.).
public protocol App {
    associatedtype Body: Scene
    @MainActor @SceneBuilder var body: Body { get }

    init()
}

public extension App {
    @_disfavoredOverload
    static func main() {
        _ = Self().body
    }
}

/// A part of an app's user interface with a lifecycle managed by the system.
public protocol Scene {
    associatedtype Body: Scene
    @MainActor @SceneBuilder var body: Body { get }
}

extension Never: Scene {}

/// A scene that presents a window.
public struct WindowGroup<Content: View>: Scene {
    public typealias Body = Never

    public let title: String
    public let content: Content
    public let defaultWindowWidth: Double?
    public let defaultWindowHeight: Double?
    public let minWindowWidth: Double?
    public let minWindowHeight: Double?
    public let maxWindowWidth: Double?
    public let maxWindowHeight: Double?
    public let windowSizing: WindowSizing?
    public let windowResizeBehavior: WindowResizeBehavior?
    public let windowResizability: WindowResizability?
    public let launchesAtStartup: Bool

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content())
    }

    public init(@ViewBuilder content: () -> Content) {
        self.init(title: "", content: content())
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.init(title: id, content: content(), launchesAtStartup: true)
    }

    public init<Value>(for valueType: Value.Type, @ViewBuilder content: (Binding<Value?>) -> Content) {
        self.init(
            title: String(describing: valueType),
            content: content(.constant(nil)),
            launchesAtStartup: false
        )
    }

    init(
        title: String,
        content: Content,
        defaultWindowWidth: Double? = nil,
        defaultWindowHeight: Double? = nil,
        minWindowWidth: Double? = nil,
        minWindowHeight: Double? = nil,
        maxWindowWidth: Double? = nil,
        maxWindowHeight: Double? = nil,
        windowSizing: WindowSizing? = nil,
        windowResizeBehavior: WindowResizeBehavior? = nil,
        windowResizability: WindowResizability? = nil,
        launchesAtStartup: Bool = true
    ) {
        self.title = title
        self.content = content
        self.defaultWindowWidth = defaultWindowWidth
        self.defaultWindowHeight = defaultWindowHeight
        self.minWindowWidth = minWindowWidth
        self.minWindowHeight = minWindowHeight
        self.maxWindowWidth = maxWindowWidth
        self.maxWindowHeight = maxWindowHeight
        self.windowSizing = windowSizing
        self.windowResizeBehavior = windowResizeBehavior
        self.windowResizability = windowResizability
        self.launchesAtStartup = launchesAtStartup
    }

    public var body: Never { fatalError("WindowGroup is a primitive scene") }
}

/// A composite scene that holds two child scenes.
public struct TupleScene<S0: Scene, S1: Scene>: Scene {
    public typealias Body = Never

    public let scene0: S0
    public let scene1: S1

    public init(_ s0: S0, _ s1: S1) {
        self.scene0 = s0
        self.scene1 = s1
    }

    public var body: Never { fatalError("TupleScene is a primitive scene") }
}

public extension Scene {
    func onChange<Value: Equatable>(
        of value: Value,
        _ action: @escaping (Value, Value) -> Void
    ) -> Self {
        _ = value
        _ = action
        return self
    }

    func windowResizability(_ resizability: WindowResizability) -> Self {
        _ = resizability
        return self
    }

    func defaultSize(width: Double, height: Double) -> Self {
        _ = width
        _ = height
        return self
    }
}

/// Result builder for composing scenes.
@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<Content: Scene>(_ content: Content) -> Content {
        content
    }

    public static func buildBlock<S0: Scene, S1: Scene>(_ s0: S0, _ s1: S1) -> TupleScene<S0, S1> {
        TupleScene(s0, s1)
    }
}
