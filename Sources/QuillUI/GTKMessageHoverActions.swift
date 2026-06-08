#if os(Linux)
import CGTK
import SwiftOpenUI
import BackendGTK4

private final class QuillGTKMessageHoverActionState {
    let actionWidget: UnsafeMutablePointer<GtkWidget>
    private var hoverDepth = 0
    private var generation = 0

    init(actionWidget: UnsafeMutablePointer<GtkWidget>) {
        self.actionWidget = actionWidget
        g_object_ref(gpointer(actionWidget))
    }

    deinit {
        g_object_unref(gpointer(actionWidget))
    }

    func enter() {
        hoverDepth += 1
        generation += 1
        gtk_widget_set_opacity(actionWidget, 1)
    }

    func leave() {
        if hoverDepth > 0 {
            hoverDepth -= 1
        }
        guard hoverDepth == 0 else { return }

        generation += 1
        let request = QuillGTKMessageHoverHideRequest(
            state: self,
            generation: generation
        )
        g_timeout_add(80, { userData -> gboolean in
            guard let userData else { return 0 }
            let request = Unmanaged<QuillGTKMessageHoverHideRequest>
                .fromOpaque(userData)
                .takeRetainedValue()
            request.state.hide(ifGeneration: request.generation)
            return 0
        }, Unmanaged.passRetained(request).toOpaque())
    }

    func hide(ifGeneration expectedGeneration: Int) {
        guard hoverDepth == 0, generation == expectedGeneration else { return }
        gtk_widget_set_opacity(actionWidget, 0.0001)
    }
}

private final class QuillGTKMessageHoverHideRequest {
    let state: QuillGTKMessageHoverActionState
    let generation: Int

    init(state: QuillGTKMessageHoverActionState, generation: Int) {
        self.state = state
        self.generation = generation
    }
}

extension QuillDesktopMessageHoverActionRow: GTKRenderable {
    func gtkCreateWidget() -> OpaquePointer {
        let container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let contentWidget = quillGTKMessageHoverWidgetPointer(gtkRenderView(content))
        let actionWidget = quillGTKMessageHoverWidgetPointer(gtkRenderView(actionBar))
        let state = QuillGTKMessageHoverActionState(actionWidget: actionWidget)
        let retainedState = Unmanaged.passRetained(state).toOpaque()
        let object = UnsafeMutableRawPointer(container).assumingMemoryBound(to: GObject.self)

        gtk_widget_set_hexpand(container, 1)
        gtk_widget_set_halign(container, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(contentWidget, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_halign(actionWidget, isUserMessage ? GTK_ALIGN_END : GTK_ALIGN_START)
        gtk_widget_set_margin_top(actionWidget, 2)
        gtk_widget_set_opacity(actionWidget, 0.0001)
        gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), contentWidget)
        gtk_box_append(UnsafeMutableRawPointer(container).assumingMemoryBound(to: GtkBox.self), actionWidget)

        g_object_set_data_full(object, "quill-message-hover-action-state", retainedState) { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKMessageHoverActionState>.fromOpaque(userData).release()
        }

        quillGTKInstallMessageHoverActionControllers(
            on: container,
            retainedState: retainedState
        )

        return OpaquePointer(container)
    }
}

private func quillGTKInstallMessageHoverActionControllers(
    on widget: UnsafeMutablePointer<GtkWidget>,
    retainedState: UnsafeMutableRawPointer
) {
    quillGTKInstallMessageHoverActionController(on: widget, retainedState: retainedState)

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        quillGTKInstallMessageHoverActionControllers(on: current, retainedState: retainedState)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func quillGTKInstallMessageHoverActionController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    retainedState: UnsafeMutableRawPointer
) {
    let controller = gtk_event_controller_motion_new()
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE)

    g_signal_connect_data(
        gpointer(controller),
        "enter",
        unsafeBitCast({ (_: gpointer?, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKMessageHoverActionState>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .enter()
        } as @convention(c) (gpointer?, Double, Double, gpointer?) -> Void, to: GCallback.self),
        retainedState,
        nil,
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(controller),
        "leave",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKMessageHoverActionState>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .leave()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedState,
        nil,
        GConnectFlags(rawValue: 0)
    )

    gtk_widget_add_controller(widget, controller)
}

private func quillGTKMessageHoverWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
