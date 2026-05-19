#if os(Linux)
import CGTK
import SwiftOpenUI
import BackendGTK4

private func quillGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func quillGTKOpaquePointer(_ widget: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer {
    OpaquePointer(widget)
}

extension AccessibilityLabelView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKWidgetPointer(gtkRenderView(content))
        label.withCString { labelPointer in
            gtk_swift_accessible_update_label(widget, labelPointer)
        }
        return quillGTKOpaquePointer(widget)
    }
}

extension AccessibilityValueView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKWidgetPointer(gtkRenderView(content))
        value.withCString { valuePointer in
            gtk_swift_accessible_update_description(widget, valuePointer)
        }
        return quillGTKOpaquePointer(widget)
    }
}

extension AccessibilityElementView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = quillGTKWidgetPointer(gtkRenderView(content))
        return quillGTKOpaquePointer(widget)
    }
}
#endif
