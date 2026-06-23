#if os(Linux)
import CGTK
import CGTKBridge
import QuillSwiftUICompatibility
import SwiftOpenUI
import BackendGTK4

extension TextSelectionView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKTextSelectionWidgetPointer(gtkRenderView(content))
        let selectable: gboolean
        switch selection {
        case .enabled:
            selectable = 1
        case .disabled:
            selectable = 0
        }
        quillGTKSetLabelsSelectable(in: widget, selectable: selectable)
        return OpaquePointer(widget)
    }
}

extension QuillCompatibilityTextSelectionView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKTextSelectionWidgetPointer(gtkRenderView(content))
        let selectable: gboolean
        switch selection {
        case .enabled:
            selectable = 1
        case .disabled:
            selectable = 0
        }
        quillGTKSetLabelsSelectable(in: widget, selectable: selectable)
        return OpaquePointer(widget)
    }
}

private func quillGTKSetLabelsSelectable(
    in widget: UnsafeMutablePointer<GtkWidget>,
    selectable: gboolean
) {
    guard gtk_swift_is_widget(widget) != 0 else { return }

    if quillGTKTextSelectionWidgetTypeName(widget) == "GtkLabel" {
        gtk_label_set_selectable(OpaquePointer(widget), selectable)
        return
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        quillGTKSetLabelsSelectable(in: current, selectable: selectable)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func quillGTKTextSelectionWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func quillGTKTextSelectionWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}
#endif
