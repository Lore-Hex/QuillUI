#if os(Linux)
import BackendGTK4
import QuillAppKitGTK

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
// Rendering: NSViewRepresentable mounts for real — the default `body` is a
// QuillNSViewRepresentableHostView (GTKRenderable leaf) that creates the
// Coordinator + NSViewType and backs it with a GtkDrawingArea running
// `draw(_:)` through the Cairo-backed CGContext (see QuillAppKitGTK's
// QuillNSViewDrawingHost.swift). NSViewControllerRepresentable is still
// compile-only (its body traps).

@MainActor
public protocol NSViewRepresentable: View {
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

    /// Rendering: the default body is a GTK host leaf. (Apple declares
    /// Body == Never and intercepts in the framework; SwiftOpenUI's renderer
    /// instead walks `body` until it reaches a GTKRenderable, so the host IS
    /// the interception point. Conformers never declare `body`, exactly as on
    /// Apple, so source compatibility is unchanged.)
    public var body: QuillNSViewRepresentableHostView<Self> {
        QuillNSViewRepresentableHostView(self)
    }
}

/// GTK leaf that mounts an NSViewRepresentable: creates the Coordinator and
/// NSViewType, then backs the view with a GtkDrawingArea whose draw func runs
/// `draw(_:)` through the Cairo-backed CGContext (QuillAppKitGTK).
public struct QuillNSViewRepresentableHostView<R: NSViewRepresentable>: View, PrimitiveView, GTKRenderable {
    public typealias Body = Never
    let representable: R

    init(_ representable: R) { self.representable = representable }

    public var body: Never {
        fatalError("QuillNSViewRepresentableHostView is a primitive view")
    }

    public func gtkCreateWidget() -> OpaquePointer {
        // The GTK renderer runs on the GTK main loop == the main thread; the
        // representable protocol is @MainActor (as on Apple). OpaquePointer
        // isn't Sendable, so it crosses the assumeIsolated boundary through an
        // unsafe slot (same thread throughout — the annotation is a formality).
        nonisolated(unsafe) var slot: OpaquePointer?
        MainActor.assumeIsolated {
            let coordinator = representable.makeCoordinator()
            let context = NSViewRepresentableContext<R>(coordinator: coordinator)
            let nsView = representable.makeNSView(context: context)
            representable.updateNSView(nsView, context: context)
            // Apple's host owns the coordinator for the view's lifetime; app
            // code wires it as an unowned/weak delegate (SolderScope does
            // `view.delegate = context.coordinator`). Retain it alongside the
            // view so that pattern holds.
            QuillRepresentableCoordinatorStore.retain(coordinator, for: nsView)
            slot = nsView.ensureGtkCustomDrawWidget()
        }
        guard let widget = slot else {
            preconditionFailure(
                "NSViewRepresentable (\(R.self)) mounted without a usable GTK display")
        }
        return widget
    }
}

/// Retains coordinators for mounted representables, keyed by the NSView
/// identity. Entries live as long as the process (v1: mounts are recreated on
/// re-render and views are few; replace with dismantle-driven release when the
/// renderer grows teardown hooks).
@MainActor
enum QuillRepresentableCoordinatorStore {
    private static var store: [ObjectIdentifier: Any] = [:]
    static func retain(_ coordinator: Any, for view: NSView) {
        store[ObjectIdentifier(view)] = coordinator
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
