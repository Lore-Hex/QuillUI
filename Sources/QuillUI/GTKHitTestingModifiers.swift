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
