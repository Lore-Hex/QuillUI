#if os(Linux)
import CGTK
import QuillSwiftUICompatibility
import SwiftOpenUI
import BackendGTK4

extension AllowsHitTestingView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        quillGTKCreateHitTestingWidget(content: content, enabled: enabled)
    }
}

extension QuillCompatibilityAllowsHitTestingView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        quillGTKCreateHitTestingWidget(content: content, enabled: enabled)
    }
}

extension QuillCompatibilityContentShapeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        quillGTKCreateContentShapeWidget(content: content)
    }
}

extension ContentShapeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        quillGTKCreateContentShapeWidget(content: content)
    }
}

private func quillGTKCreateHitTestingWidget<Content: View>(
    content: Content,
    enabled: Bool
) -> OpaquePointer {
    let widget = quillGTKHitTestingWidgetPointer(gtkRenderView(content))
    if !enabled {
        quillGTKDisableHitTesting(in: widget)
    }
    return OpaquePointer(widget)
}

private func quillGTKCreateContentShapeWidget<Content: View>(content: Content) -> OpaquePointer {
    let container = gtk_overlay_new()!
    let widget = quillGTKHitTestingWidgetPointer(gtkRenderView(content))

    gtk_widget_set_can_target(container, 1)
    gtk_widget_set_hexpand(container, 1)
    gtk_widget_set_halign(container, GTK_ALIGN_FILL)
    gtk_widget_set_hexpand(widget, 1)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)

    if gtk_widget_get_vexpand(widget) != 0 {
        gtk_widget_set_vexpand(container, 1)
        gtk_widget_set_valign(container, GTK_ALIGN_FILL)
        gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
    }

    gtk_overlay_set_child(OpaquePointer(container), widget)
    return OpaquePointer(container)
}

private func quillGTKDisableHitTesting(in widget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_can_target(widget, 0)
    gtk_widget_set_can_focus(widget, 0)

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        quillGTKDisableHitTesting(in: current)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func quillGTKHitTestingWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
