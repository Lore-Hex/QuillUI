import Foundation
import CGTK
import SwiftOpenUI

private let gtkImageRendererInitLock = NSLock()

private func imageRendererWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func imageRendererWindowPointer(
    _ widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWindow> {
    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWindow.self)
}

@discardableResult
private func ensureImageRendererGTKInitialized() -> Bool {
    gtkImageRendererInitLock.withLock {
        if gtk_is_initialized() != 0 {
            return true
        }
        return gtk_init_check() != 0
    }
}

private final class CairoPNGWriteBox {
    var data = Data()
}

private let cairoPNGWriteCallback: cairo_write_func_t = { closure, bytes, length in
    guard let closure, let bytes else {
        return CAIRO_STATUS_WRITE_ERROR
    }
    let box = Unmanaged<CairoPNGWriteBox>.fromOpaque(closure).takeUnretainedValue()
    box.data.append(bytes, count: Int(length))
    return CAIRO_STATUS_SUCCESS
}

private func pngData(from surface: OpaquePointer) -> Data? {
    let box = CairoPNGWriteBox()
    let status = cairo_surface_write_to_png_stream(
        surface,
        cairoPNGWriteCallback,
        Unmanaged.passUnretained(box).toOpaque()
    )
    guard status == CAIRO_STATUS_SUCCESS else {
        return nil
    }
    return box.data
}

func gtkRenderViewToPNGData(
    _ view: any View,
    configuration: ImageRendererConfiguration
) -> Data? {
    let width = max(1, configuration.width)
    let height = max(1, configuration.height)
    guard ensureImageRendererGTKInitialized() else { return nil }

    let widget = gtkRenderAnyView(view)
    let widgetPtr = imageRendererWidgetPointer(widget)
    g_object_ref(gpointer(widget))
    defer { g_object_unref(gpointer(widget)) }

    guard let windowWidget = gtk_window_new() else { return nil }
    let window = imageRendererWindowPointer(windowWidget)
    defer { gtk_window_destroy(window) }

    gtk_window_set_decorated(window, 0)
    gtk_window_set_default_size(window, gint(width), gint(height))
    gtk_window_set_child(window, widgetPtr)

    gtk_widget_set_hexpand(widgetPtr, 1)
    gtk_widget_set_vexpand(widgetPtr, 1)
    gtk_widget_set_halign(widgetPtr, GTK_ALIGN_FILL)
    gtk_widget_set_valign(widgetPtr, GTK_ALIGN_FILL)
    gtk_widget_set_size_request(widgetPtr, gint(width), gint(height))
    gtk_widget_set_size_request(windowWidget, gint(width), gint(height))

    gtk_widget_realize(windowWidget)
    gtk_widget_set_visible(windowWidget, 1)
    while g_main_context_iteration(nil, 0) != 0 {}

    var allocation = GdkRectangle(x: 0, y: 0, width: gint(width), height: gint(height))
    gtk_widget_allocate(windowWidget, gint(width), gint(height), -1, nil)
    gtk_widget_size_allocate(widgetPtr, &allocation, -1)
    gtk_widget_allocate(widgetPtr, gint(width), gint(height), -1, nil)
    while g_main_context_iteration(nil, 0) != 0 {}

    guard let snapshot = gtk_snapshot_new() else { return nil }
    gtk_widget_snapshot_child(windowWidget, widgetPtr, snapshot)
    let renderNodeOpt = gtk_snapshot_to_node(snapshot)
    g_object_unref(gpointer(snapshot))
    guard let renderNode = renderNodeOpt else { return nil }
    defer { gsk_render_node_unref(renderNode) }

    guard let cairoSurface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32,
        gint(width),
        gint(height)
    ) else {
        return nil
    }
    defer { cairo_surface_destroy(cairoSurface) }

    guard let cr = cairo_create(cairoSurface) else { return nil }
    defer { cairo_destroy(cr) }

    gsk_render_node_draw(renderNode, cr)
    cairo_surface_flush(cairoSurface)
    return pngData(from: cairoSurface)
}

public func installGTK4ImageRendererBackend() {
    ImageRendererBackend.installViewRenderer { view, configuration in
        gtkRenderViewToPNGData(view, configuration: configuration)
    }
}
