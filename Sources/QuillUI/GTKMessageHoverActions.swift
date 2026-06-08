#if os(Linux)
import CGTK
import SwiftOpenUI
import BackendGTK4

extension QuillDesktopMessageHoverActionRow: GTKRenderable {
    func gtkCreateWidget() -> OpaquePointer {
        let container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let contentWidget = quillGTKMessageHoverWidgetPointer(gtkRenderView(content))
        let actionWidget = quillGTKMessageHoverWidgetPointer(gtkRenderView(actionBar))

        gtk_widget_set_hexpand(container, 1)
        gtk_widget_set_halign(container, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(contentWidget, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_halign(actionWidget, isUserMessage ? GTK_ALIGN_END : GTK_ALIGN_START)
        gtk_widget_set_margin_top(actionWidget, 2)
        gtk_widget_set_opacity(actionWidget, 0.0001)
        gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), contentWidget)
        gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), actionWidget)

        quillGTKInstallMessageHoverActionController(
            on: container,
            actionWidget: actionWidget
        )

        return OpaquePointer(container)
    }
}

private func quillGTKInstallMessageHoverActionController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    actionWidget: UnsafeMutablePointer<GtkWidget>
) {
    let controller = gtk_event_controller_motion_new()
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)
    let retainedActionWidget = UnsafeMutableRawPointer(actionWidget)

    g_signal_connect_data(
        gpointer(controller),
        "enter",
        unsafeBitCast({ (_: gpointer?, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            let actionWidget = userData.assumingMemoryBound(to: GtkWidget.self)
            gtk_widget_set_opacity(actionWidget, 1)
        } as @convention(c) (gpointer?, Double, Double, gpointer?) -> Void, to: GCallback.self),
        retainedActionWidget,
        nil,
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(controller),
        "leave",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let actionWidget = userData.assumingMemoryBound(to: GtkWidget.self)
            gtk_widget_set_opacity(actionWidget, 0.0001)
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedActionWidget,
        nil,
        GConnectFlags(rawValue: 0)
    )

    gtk_widget_add_controller(widget, controller)
}

private func quillGTKMessageHoverWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
