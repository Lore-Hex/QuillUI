// Linux-only: offscreen rasterization of arbitrary SwiftUI-shaped views.
//
// Closes the second half of the `ImageRenderer` parity gap: real Apple
// SwiftUI's `ImageRenderer` rasterizes any view tree into a `UIImage` /
// `NSImage`. On Linux we route a SwiftOpenUI-backed widget through GTK4's
// snapshot system, draw the resulting render node into a cairo image surface,
// then encode the surface via gdk-pixbuf.
//
// Pipeline:
//   1. `gtk_init_check()`  (idempotent; safe to call repeatedly)
//   2. `BackendGTK4.gtkRenderView(view)`  → GtkWidget*  (existing public API)
//   3. Parent the widget in an offscreen GtkWindow + realize it so the
//      widget tree has a layout. Without realization the widget hierarchy
//      hasn't been measured/sized and `gtk_widget_snapshot` returns an
//      empty render node.
//   4. `gtk_widget_size_allocate(widget, alloc, -1)` to force a final size.
//   5. `gtk_widget_snapshot(widget, snapshot)` → fills the snapshot.
//   6. `gtk_snapshot_to_node(snapshot)` → root GskRenderNode.
//   7. Create a `cairo_image_surface_t` of the requested size, get a `cairo_t`
//      context, and draw the node via `gsk_render_node_draw(node, cr)`.
//   8. Copy the cairo ARGB32 pixels into a GdkPixbuf, unpremultiplying
//      components into the straight-alpha RGB(A) format gdk-pixbuf encodes.
//   9. `gdk_pixbuf_save_to_bufferv(pixbuf, ..., "png" | "tiff", ...)` →
//      Swift-owned `Data` bytes; free the gdk-pixbuf-allocated buffer.
//
// Notes on parity coverage:
//  - `gsk_render_node_draw` walks each node and asks it to paint itself into
//    the cairo context. It works for the vast majority of widget output —
//    rectangles, text via Pango, images — but a few advanced GSK node types
//    (offscreen-effect nodes, blur, color-matrix) may fall back to a simpler
//    path. For the purposes of "produce real pixels for typical SwiftUI
//    views" this is sufficient; if pixel-perfect parity matters later, swap
//    in `gsk_cairo_renderer_new()` + `gsk_renderer_render_texture()`.
//  - GTK initialization needs a display backend. `gtk_init_check` succeeds
//    under xvfb (which `scripts/linux-backend-check.sh` already installs).
//    Without xvfb / Wayland it returns false and we surface a diagnostic.

#if os(Linux)
import Foundation
import CGTK
import CGdkPixbuf
import BackendGTK4

@_spi(QuillTesting)
public func quillInstallGTKImageRendererBackend() {
    installGTK4ImageRendererBackend()
}

/// Default offscreen canvas size used when callers don't specify one.
private let defaultRenderSize: (width: Int, height: Int) = (512, 512)
private let offscreenRenderFlag = "QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER"

/// One-shot lock so concurrent first-time `quillRenderViewToImage` calls
/// only race through `gtk_init_check` once.
private let gtkInitLock = NSLock()

private func gtkWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func gtkWindowPointer(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWindow> {
    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWindow.self)
}

private func unpremultipliedByte(_ component: UInt32, alpha: UInt32) -> guchar {
    guard alpha > 0 else { return 0 }
    return guchar(min(255, (component * 255 + alpha / 2) / alpha))
}

private func pixbufFromCairoARGB32Surface(
    _ surface: OpaquePointer,
    width: Int,
    height: Int
) -> OpaquePointer? {
    guard let pixbuf = gdk_pixbuf_new(
        GDK_COLORSPACE_RGB,
        1,
        8,
        gint(width),
        gint(height)
    ) else {
        return nil
    }

    cairo_surface_flush(surface)

    guard
        let sourcePixels = cairo_image_surface_get_data(surface),
        let destinationPixels = gdk_pixbuf_get_pixels(pixbuf)
    else {
        g_object_unref(gpointer(pixbuf))
        return nil
    }

    let sourceStride = Int(cairo_image_surface_get_stride(surface))
    let destinationStride = Int(gdk_pixbuf_get_rowstride(pixbuf))
    let destinationChannels = Int(gdk_pixbuf_get_n_channels(pixbuf))
    guard destinationChannels >= 4 else {
        g_object_unref(gpointer(pixbuf))
        return nil
    }

    for y in 0..<height {
        let sourceRow = sourcePixels.advanced(by: y * sourceStride)
        let destinationRow = destinationPixels.advanced(by: y * destinationStride)

        for x in 0..<width {
            let pixel = UnsafeRawPointer(sourceRow.advanced(by: x * 4)).load(as: UInt32.self)
            let alpha = (pixel >> 24) & 0xFF
            let red = (pixel >> 16) & 0xFF
            let green = (pixel >> 8) & 0xFF
            let blue = pixel & 0xFF
            let destinationPixel = destinationRow.advanced(by: x * destinationChannels)

            destinationPixel[0] = unpremultipliedByte(red, alpha: alpha)
            destinationPixel[1] = unpremultipliedByte(green, alpha: alpha)
            destinationPixel[2] = unpremultipliedByte(blue, alpha: alpha)
            destinationPixel[3] = guchar(alpha)
        }
    }

    return pixbuf
}

private func isGTKOffscreenRenderEnabled() -> Bool {
    let value = ProcessInfo.processInfo.environment[offscreenRenderFlag]?.lowercased()
    return value == "1" || value == "true" || value == "yes"
}

@discardableResult
private func ensureGTKInitialized() -> Bool {
    gtkInitLock.withLock {
        if gtk_is_initialized() != 0 {
            return true
        }
        return gtk_init_check() != 0
    }
}

/// Snapshot a SwiftUI-shaped view into encoded image bytes by way of
/// SwiftOpenUI's GTK4 backend + cairo + gdk-pixbuf.
///
/// Returns `nil` when GTK can't be initialized (no display backend), when
/// the snapshot/draw pipeline fails, or when the encoder rejects the result.
/// Failures attempt to free any `GError` they produce.
@_spi(QuillTesting)
public func quillRenderViewToImage<V: View>(
    _ view: V,
    width: Int? = nil,
    height: Int? = nil,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    let resolvedWidth = width ?? defaultRenderSize.width
    let resolvedHeight = height ?? defaultRenderSize.height
    guard resolvedWidth > 0, resolvedHeight > 0 else { return nil }
    guard isGTKOffscreenRenderEnabled() else { return nil }
    guard ensureGTKInitialized() else { return nil }

    // 1. Translate the SwiftUI-shaped view into a GtkWidget tree via
    //    SwiftOpenUI's public renderer entry point. The result is a borrowed
    //    GtkWidget* — its initial ref count is owned by the caller.
    let widget = gtkRenderView(view)
    let widgetPtr = gtkWidgetPointer(widget)

    // 2. Parent the widget in an offscreen window so realization triggers
    //    layout. The window is never shown and is destroyed after the
    //    snapshot. We hold an extra ref on the widget so it survives
    //    `gtk_window_destroy` (which unparents and unrefs its child).
    g_object_ref(UnsafeMutableRawPointer(widget))
    defer { g_object_unref(UnsafeMutableRawPointer(widget)) }

    guard let windowWidget = gtk_window_new() else { return nil }
    let window = gtkWindowPointer(windowWidget)
    defer { gtk_window_destroy(window) }

    gtk_window_set_decorated(window, 0)
    gtk_window_set_default_size(window, gint(resolvedWidth), gint(resolvedHeight))
    gtk_window_set_child(window, widgetPtr)
    gtk_widget_set_hexpand(widgetPtr, 1)
    gtk_widget_set_vexpand(widgetPtr, 1)
    gtk_widget_set_halign(widgetPtr, GTK_ALIGN_FILL)
    gtk_widget_set_valign(widgetPtr, GTK_ALIGN_FILL)

    // Force the widget to compute and apply a layout at the requested size.
    // Without this, snapshotting may produce an empty render node because the
    // widget has not been measured, mapped, or allocated by GTK's layout
    // machinery. Presenting happens only behind the explicit opt-in flag and
    // normally runs under Xvfb in QA.
    gtk_widget_set_size_request(widgetPtr, gint(resolvedWidth), gint(resolvedHeight))
    gtk_widget_set_size_request(windowWidget, gint(resolvedWidth), gint(resolvedHeight))
    gtk_widget_realize(windowWidget)
    gtk_widget_set_visible(windowWidget, 1)
    while g_main_context_iteration(nil, 0) != 0 {}

    // Do an explicit allocation using GTK4's public allocation entry point.
    // `-1` for the baseline tells GTK to use the widget's preferred baseline.
    var allocation = GdkRectangle(x: 0, y: 0, width: gint(resolvedWidth), height: gint(resolvedHeight))
    gtk_widget_allocate(windowWidget, gint(resolvedWidth), gint(resolvedHeight), -1, nil)
    gtk_widget_size_allocate(widgetPtr, &allocation, -1)
    gtk_widget_allocate(widgetPtr, gint(resolvedWidth), gint(resolvedHeight), -1, nil)
    while g_main_context_iteration(nil, 0) != 0 {}

    // 3. Snapshot the widget into a GskRenderNode. The current CGTK module
    // exposes GTK's parent-side snapshot helper, so we snapshot the child
    // from the offscreen parent window.
    guard let snapshot = gtk_snapshot_new() else { return nil }
    gtk_widget_snapshot_child(windowWidget, widgetPtr, snapshot)
    let renderNodeOpt = gtk_snapshot_to_node(snapshot)
    g_object_unref(UnsafeMutableRawPointer(snapshot))
    guard let renderNode = renderNodeOpt else { return nil }
    defer { gsk_render_node_unref(renderNode) }

    // 4. Cairo image surface backed by a real ARGB32 pixel buffer.
    guard let cairoSurface = cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32,
        gint(resolvedWidth),
        gint(resolvedHeight)
    ) else { return nil }
    defer { cairo_surface_destroy(cairoSurface) }

    guard let cr = cairo_create(cairoSurface) else { return nil }
    defer { cairo_destroy(cr) }

    // 5. Walk the render-node tree, asking each node to draw itself to the
    //    cairo context. Most node types support this directly.
    gsk_render_node_draw(renderNode, cr)

    // 6. Pull pixels back as a GdkPixbuf, then encode.
    guard let pixbuf = pixbufFromCairoARGB32Surface(
        cairoSurface,
        width: resolvedWidth,
        height: resolvedHeight
    ) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }

    var buffer: UnsafeMutablePointer<gchar>? = nil
    var bufferSize: gsize = 0
    var error: UnsafeMutablePointer<GError>? = nil
    let saveOK = format.rawValue.withCString { typeCString -> Int32 in
        gdk_pixbuf_save_to_bufferv(
            pixbuf,
            &buffer,
            &bufferSize,
            typeCString,
            nil,
            nil,
            &error
        )
    }
    if let error {
        g_error_free(error)
    }
    guard saveOK != 0, let buffer else { return nil }

    let result = Data(bytes: UnsafeRawPointer(buffer), count: Int(bufferSize))
    g_free(buffer)
    return result
}
#endif

#if !os(Linux)
import Foundation

/// macOS stub so the symbol is reachable in cross-platform code paths.
/// Real Apple SwiftUI's `ImageRenderer` is the canonical implementation
/// on Apple platforms; this stub never gets invoked on macOS.
@_spi(QuillTesting)
public func quillRenderViewToImage<V>(
    _ view: V,
    width: Int? = nil,
    height: Int? = nil,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    nil
}
#endif
