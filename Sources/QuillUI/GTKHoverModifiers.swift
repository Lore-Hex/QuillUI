#if os(Linux)
import CGTK
import SwiftOpenUI
import BackendGTK4

private final class QuillGTKHoverActionBox {
    let action: (Bool) -> Void
    private var isHovered = false

    init(_ action: @escaping (Bool) -> Void) {
        self.action = action
    }

    func update(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        action(hovered)
    }
}

extension OnHoverView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKHoverWidgetPointer(gtkRenderView(content))
        let box = QuillGTKHoverActionBox(action)
        let retainedBox = Unmanaged.passRetained(box).toOpaque()
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)

        g_object_set_data_full(object, "quill-hover-action", retainedBox) { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKHoverActionBox>.fromOpaque(userData).release()
        }

        quillGTKInstallHoverControllers(on: widget, retainedBox: retainedBox)
        return OpaquePointer(widget)
    }
}

private func quillGTKInstallHoverControllers(
    on widget: UnsafeMutablePointer<GtkWidget>,
    retainedBox: UnsafeMutableRawPointer
) {
    quillGTKInstallHoverController(on: widget, retainedBox: retainedBox)

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        quillGTKInstallHoverControllers(on: current, retainedBox: retainedBox)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func quillGTKInstallHoverController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    retainedBox: UnsafeMutableRawPointer
) {
    let controller = gtk_event_controller_motion_new()
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)

    g_signal_connect_data(
        gpointer(controller),
        "enter",
        unsafeBitCast({ (_: gpointer?, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKHoverActionBox>.fromOpaque(userData).takeUnretainedValue().update(true)
        } as @convention(c) (gpointer?, Double, Double, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        nil,
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(controller),
        "leave",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKHoverActionBox>.fromOpaque(userData).takeUnretainedValue().update(false)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        nil,
        GConnectFlags(rawValue: 0)
    )

    gtk_widget_add_controller(widget, controller)
}

private func quillGTKHoverWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
