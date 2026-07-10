#if os(Linux)
#if QUILLUI_SWIFTUI_GTK_MOUNT
// Implementation-only on BOTH: keeps CGTK (via BackendGTK4) and CGtk4 (via
// QuillAppKitGTK) OUT of the SwiftUI swiftmodule entirely, so dependents and
// sibling build graphs without gtk -Xcc flags can still load this module
// (the house bans systemLibrary pkgConfig, so C-module flag propagation is
// manual — hide the dependencies instead of propagating flags). The public
// host therefore must NOT conform to BackendGTK4's GTKRenderable; an
// INTERNAL leaf behind an opaque `body` carries the conformance.
@_implementationOnly import BackendGTK4
@_implementationOnly import QuillAppKitGTK
#elseif QUILLUI_SWIFTUI_QT_MOUNT
// Implementation-only for the same reason as the GTK branch: the public
// SwiftUI shadow must not expose BackendQt/CQuillAppKitQt details through its
// swiftmodule. The internal primitive leaf below carries QtRenderable.
@_implementationOnly import BackendQt
@_implementationOnly import QuillAppKitQt
#endif

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

// @preconcurrency matches Apple's exact declaration
// (`@MainActor @preconcurrency protocol NSViewRepresentable`): conformers'
// inferred type-level isolation is downgraded to warnings for
// pre-concurrency-shaped code (nonisolated nested Coordinators mutating the
// parent representable's @Binding properties — SolderScope does exactly this).
@preconcurrency
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

    /// Rendering: the default body is a toolkit host leaf. (Apple declares
    /// Body == Never and intercepts in the framework; SwiftOpenUI's renderer
    /// instead walks `body` until it reaches a backend renderable, so the host IS
    /// the interception point. Conformers never declare `body`, exactly as on
    /// Apple, so source compatibility is unchanged.)
    public nonisolated var body: QuillNSViewRepresentableHostView<Self> {
        QuillNSViewRepresentableHostView(self)
    }
}

/// Host view that lowers an NSViewRepresentable into the active native mount.
public struct QuillNSViewRepresentableHostView<R: NSViewRepresentable>: View {
#if QUILLUI_SWIFTUI_GTK_MOUNT
    nonisolated(unsafe) let representable: R

    nonisolated init(_ representable: R) { self.representable = representable }

    public var body: some View {
        _QuillGTKRepresentableMountLeaf(representable: representable)
    }
#elseif QUILLUI_SWIFTUI_QT_MOUNT
    nonisolated(unsafe) let representable: R

    nonisolated init(_ representable: R) { self.representable = representable }

    public var body: some View {
        _QuillQtRepresentableMountLeaf(representable: representable)
    }
#else
    nonisolated(unsafe) let representable: R

    nonisolated init(_ representable: R) { self.representable = representable }

    // Graphs without a native mount keep compile-only representables.
    public var body: Never {
        fatalError("""
        NSViewRepresentable (\(R.self)) rendering requires a SwiftUI native \
        mount graph; this package graph has no GTK or Qt mount enabled.
        """)
    }
#endif
}

#if QUILLUI_SWIFTUI_GTK_MOUNT
/// Internal renderable leaf: carries the GTKRenderable conformance so the
/// PUBLIC host never references an implementation-only protocol. The
/// renderer reaches it by walking the host's opaque body.
struct _QuillGTKRepresentableMountLeaf<R: NSViewRepresentable>: View, PrimitiveView, GTKRenderable, GTKDescribable {
    typealias Body = Never
    let representable: R

    var body: Never {
        fatalError("_QuillGTKRepresentableMountLeaf is a primitive view")
    }

    /// Terminal descriptor: a representable mount is an opaque native leaf.
    /// Without this, the describe pass falls through the Mirror
    /// describe-through path into the stored representable, whose body is the
    /// host view wrapping this leaf again — infinite recursion (stack
    /// overflow at app launch; SolderScope's MicroscopeView found it).
    nonisolated func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(kind: .composite, typeName: String(describing: Self.self))
    }

    func gtkCreateWidget() -> OpaquePointer {
        // The GTK renderer runs on the GTK main loop == the main thread; the
        // representable protocol is @MainActor (as on Apple). OpaquePointer
        // isn't Sendable, so it crosses the assumeIsolated boundary through an
        // unsafe slot (same thread throughout — the annotation is a formality).
        nonisolated(unsafe) var slot: OpaquePointer?
        MainActor.assumeIsolated {
            // Stable identity across rebuilds (enclosing stateful-view
            // namespace + type + per-pass occurrence index, same scheme as
            // @State storage identity). Re-renders REUSE the mounted
            // Coordinator + NSViewType and get Apple's updateNSView call;
            // without this, every observable tick would destroy and recreate
            // the native view (losing its state — a live camera view would
            // remount per frame).
            let key = gtkMountIdentity(for: Self.self)
            if let mounted = QuillRepresentableMountRegistry.entry(for: key),
               let nsView = mounted.nsView as? R.NSViewType,
               let coordinator = mounted.coordinator as? R.Coordinator {
                let context = NSViewRepresentableContext<R>(coordinator: coordinator)
                representable.updateNSView(nsView, context: context)
                quillGtkDetachFromParent(mounted.widget)
                slot = mounted.widget
                return
            }

            let coordinator = representable.makeCoordinator()
            let context = NSViewRepresentableContext<R>(coordinator: coordinator)
            let nsView = representable.makeNSView(context: context)
            representable.updateNSView(nsView, context: context)
            guard let widget = nsView.ensureGtkCustomDrawWidget() else {
                preconditionFailure(
                    "NSViewRepresentable (\(R.self)) mounted without a usable GTK display")
            }
            // Own the widget so it survives teardown of whichever render tree
            // it was parented in between rebuilds.
            quillGtkRetainWidget(widget)
            QuillRepresentableMountRegistry.store(
                key: key,
                entry: .init(coordinator: coordinator, nsView: nsView, widget: widget) {
                    R.dismantleNSView(nsView, coordinator: coordinator)
                    quillGtkReleaseWidget(widget)
                })
            slot = widget
        }
        guard let widget = slot else {
            preconditionFailure(
                "NSViewRepresentable (\(R.self)) mounted without a usable GTK display")
        }
        return widget
    }
}

/// Mounted-representable registry, keyed by render-tree mount identity.
/// One entry per mount SITE (same lifetime semantics as the renderer's
/// @State storage cache): replacing a key dismantles the previous mount
/// (Apple's dismantleNSView + widget release). Entries for mount sites that
/// disappear entirely persist like stale @State cache entries do — bounded
/// by distinct mount sites, not by render count.
@MainActor
enum QuillRepresentableMountRegistry {
    struct Entry {
        let coordinator: Any
        let nsView: NSView
        let widget: OpaquePointer
        let dismantle: () -> Void
    }

    private static var store: [String: Entry] = [:]

    static func entry(for key: String) -> Entry? { store[key] }

    static func store(key: String, entry: Entry) {
        if let previous = store[key] { previous.dismantle() }
        store[key] = entry
    }
}
#endif

#if QUILLUI_SWIFTUI_QT_MOUNT
/// Internal renderable leaf for the generic SwiftUI->Qt graph. Phase 1 only
/// creates a Qt drawing host; mount identity/Coordinator reuse is phase 2.
struct _QuillQtRepresentableMountLeaf<R: NSViewRepresentable>: View, PrimitiveView, QtRenderable {
    typealias Body = Never
    let representable: R

    var body: Never {
        fatalError("_QuillQtRepresentableMountLeaf is a primitive view")
    }

    func qtCreateWidget() -> OpaquePointer {
        nonisolated(unsafe) var slot: UnsafeMutableRawPointer?
        MainActor.assumeIsolated {
            let coordinator = representable.makeCoordinator()
            let context = NSViewRepresentableContext<R>(coordinator: coordinator)
            let nsView = representable.makeNSView(context: context)
            representable.updateNSView(nsView, context: context)
            slot = nsView.ensureQtCustomDrawWidget()
        }
        guard let widget = slot else {
            preconditionFailure(
                "NSViewRepresentable (\(R.self)) mounted without a usable Qt display")
        }
        return OpaquePointer(widget)
    }
}
#endif

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

    public nonisolated var body: Never {
        fatalError("""
        NSViewControllerRepresentable (\(Self.self)) was mounted but Linux \
        rendering for representables is not wired yet.
        """)
    }
}

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
