#if os(Linux)
import CGTK
import QuillSwiftUICompatibility
import SwiftOpenUI
import BackendGTK4

private final class QuillGTKMoveCommandActionBox {
    let environment: EnvironmentValues
    let action: (MoveCommandDirection) -> Void

    init(environment: EnvironmentValues, action: @escaping (MoveCommandDirection) -> Void) {
        self.environment = environment
        self.action = action
    }

    func handle(keyval: guint) -> gboolean {
        guard let direction = quillGTKMoveCommandDirection(for: keyval) else { return 0 }
        let previous = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previous) }
        action(direction)
        return 1
    }
}

extension MoveCommandView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKMoveCommandWidgetPointer(gtkRenderView(content))
        quillGTKInstallMoveCommandController(
            on: widget,
            environment: getCurrentEnvironment(),
            action: action
        )
        return OpaquePointer(widget)
    }
}

private let quillGTKMoveCommandKeyPressedHandler: @convention(c) (
    OpaquePointer?,
    guint,
    guint,
    guint,
    gpointer?
) -> gboolean = { _, keyval, _, _, userData in
    guard let userData else { return 0 }
    return Unmanaged<QuillGTKMoveCommandActionBox>
        .fromOpaque(userData)
        .takeUnretainedValue()
        .handle(keyval: keyval)
}

private func quillGTKInstallMoveCommandController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    environment: EnvironmentValues,
    action: @escaping (MoveCommandDirection) -> Void
) {
    let controller = gtk_swift_key_capture_controller()!
    let box = Unmanaged.passRetained(QuillGTKMoveCommandActionBox(
        environment: environment,
        action: action
    )).toOpaque()
    g_signal_connect_data(
        gpointer(controller),
        "key-pressed",
        unsafeBitCast(quillGTKMoveCommandKeyPressedHandler, to: GCallback.self),
        box,
        { data, _ in
            guard let data else { return }
            Unmanaged<QuillGTKMoveCommandActionBox>.fromOpaque(data).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(widget, controller)
}

private func quillGTKMoveCommandDirection(for keyval: guint) -> MoveCommandDirection? {
    switch keyval {
    case 0xff52:
        return .up
    case 0xff54:
        return .down
    case 0xff51:
        return .left
    case 0xff53:
        return .right
    default:
        return nil
    }
}

private func quillGTKMoveCommandWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
