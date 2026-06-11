#if os(Linux)
// NSViewRepresentable / NSViewControllerRepresentable — Apple ships these in
// SwiftUI (NOT AppKit; `import AppKit` alone does not resolve them on macOS),
// so they live in the SwiftUI shim, which depends on both AppKit and the
// SwiftOpenUI core. Apple-faithful shape:
//   * plain protocols (struct conformers — real apps declare
//     `struct MicroscopeView: NSViewRepresentable`; the previous AnyObject
//     constraint in QuillAppKit made every such app fail to compile),
//   * @MainActor (so makeNSView/updateNSView bodies may touch main-actor
//     state, exactly as on Apple),
//   * View with Body == Never,
//   * full Coordinator plumbing with Apple's defaults.
//
// Rendering: not wired yet. The default `body` traps with a clear message if
// a representable is actually mounted; the compile surface is what unmodified
// upstream sources need today. The GTK mount (backing the NSViewType into the
// widget tree via QuillAppKitGTK) is the follow-up that makes these draw.

@MainActor
public protocol NSViewRepresentable: View where Body == Never {
    associatedtype NSViewType: NSView
    associatedtype Coordinator = Void
    typealias Context = NSViewRepresentableContext<Self>

    func makeNSView(context: Context) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: Context)
    func makeCoordinator() -> Coordinator
    static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator)
}

extension NSViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

extension NSViewRepresentable {
    public static func dismantleNSView(_ nsView: NSViewType, coordinator: Coordinator) {}

    public var body: Never {
        fatalError("""
        NSViewRepresentable (\(Self.self)) was mounted but Linux rendering for \
        representables is not wired yet — the type compiles for conformance; \
        the QuillAppKitGTK mount is the follow-up that makes it draw.
        """)
    }
}

@MainActor
public struct NSViewRepresentableContext<Representable: NSViewRepresentable> {
    public let coordinator: Representable.Coordinator
    public var environment: EnvironmentValues

    public init(coordinator: Representable.Coordinator,
                environment: EnvironmentValues = EnvironmentValues()) {
        self.coordinator = coordinator
        self.environment = environment
    }
}

@MainActor
public protocol NSViewControllerRepresentable: View where Body == Never {
    associatedtype NSViewControllerType: NSViewController
    associatedtype Coordinator = Void
    typealias Context = NSViewControllerRepresentableContext<Self>

    func makeNSViewController(context: Context) -> NSViewControllerType
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context)
    func makeCoordinator() -> Coordinator
    static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator)
}

extension NSViewControllerRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Coordinator { () }
}

extension NSViewControllerRepresentable {
    public static func dismantleNSViewController(_ nsViewController: NSViewControllerType, coordinator: Coordinator) {}

    public var body: Never {
        fatalError("""
        NSViewControllerRepresentable (\(Self.self)) was mounted but Linux \
        rendering for representables is not wired yet.
        """)
    }
}

@MainActor
public struct NSViewControllerRepresentableContext<Representable: NSViewControllerRepresentable> {
    public let coordinator: Representable.Coordinator
    public var environment: EnvironmentValues

    public init(coordinator: Representable.Coordinator,
                environment: EnvironmentValues = EnvironmentValues()) {
        self.coordinator = coordinator
        self.environment = environment
    }
}
#endif
