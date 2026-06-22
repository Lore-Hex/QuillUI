import XCTest
import Foundation
import SwiftOpenUI
@testable import BackendGTK4
import CGTK
import CGTKBridge

final class GTK4ClipShapeTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        if gtk_is_initialized() == 0 {
            _ = gtk_init_check()
        }
    }

    // MARK: - ClippedView

    func testClippedWrapsInOverflowHidden() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipped()
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    func testClippedContentIsAccessible() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipped()
        ))
        let label = findFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertNotNil(label, "Clipped content should still be in the tree")
    }

    // MARK: - ClipShapeView with Circle

    func testClipShapeCircleAppliesBorderRadius50() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipShape(Circle())
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
        // The wrapper should have border-radius: 50% via CSS.
        // We can't directly query CSS from GTK in tests, but verify the
        // widget is a wrapper box (not the raw label).
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
        XCTAssertEqual(typeName, "GtkBox", "ClipShape should wrap in a GtkBox")
    }

    // MARK: - ClipShapeView with RoundedRectangle

    func testClipShapeRoundedRectangleRendersWrapper() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipShape(RoundedRectangle(cornerRadius: 12))
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    // MARK: - ClipShapeView with Capsule

    func testClipShapeCapsuleRendersWrapper() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipShape(Capsule())
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    // MARK: - ClipShapeView with Ellipse

    func testClipShapeEllipseRendersWrapper() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipShape(Ellipse())
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    // MARK: - ClipShapeView with Rectangle

    func testClipShapeRectangleRendersWrapper() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipShape(Rectangle())
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    // MARK: - Expand flag propagation

    func testClippedPreservesChildExpandFlags() throws {
        try requireGTK()

        // Circle expands by default (hexpand + vexpand)
        let widget = widgetFromOpaque(gtkRenderView(
            Circle().clipped()
        ))
        XCTAssertNotEqual(gtk_widget_get_hexpand(widget), 0,
                          "Clipped wrapper should inherit child hexpand")
        XCTAssertNotEqual(gtk_widget_get_vexpand(widget), 0,
                          "Clipped wrapper should inherit child vexpand")
    }

    func testClipShapePreservesChildExpandFlags() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Circle().clipShape(RoundedRectangle(cornerRadius: 8))
        ))
        XCTAssertNotEqual(gtk_widget_get_hexpand(widget), 0,
                          "ClipShape wrapper should inherit child hexpand")
        XCTAssertNotEqual(gtk_widget_get_vexpand(widget), 0,
                          "ClipShape wrapper should inherit child vexpand")
    }

    func testClippedNonExpandingChildDoesNotExpand() throws {
        try requireGTK()

        // Text does not expand
        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").clipped()
        ))
        XCTAssertEqual(gtk_widget_get_hexpand(widget), 0,
                       "Clipped non-expanding child should not expand")
    }

    // MARK: - Chaining

    func testClipShapeWithFrame() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").frame(width: 80, height: 80).clipShape(Circle())
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
        // Content should still be accessible inside the clip wrapper
        let label = findFirstDescendant(ofType: "GtkLabel", in: widget)
        XCTAssertNotNil(label)
    }

    func testClipShapeWithBackground() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").background(.blue).clipShape(RoundedRectangle(cornerRadius: 8))
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }

    func testTranslucentBackgroundUsesSeparateUnderlayInsideClipShape() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text("Scope")
            }
            .background(Color.white.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        ))

        XCTAssertEqual(gtkWidgetTypeName(widget), "GtkBox")
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)

        let overlay = try XCTUnwrap(gtk_widget_get_first_child(widget))
        XCTAssertEqual(gtkWidgetTypeName(overlay), "GtkOverlay")

        let underlay = try XCTUnwrap(gtk_widget_get_first_child(overlay))
        let content = try XCTUnwrap(gtk_widget_get_next_sibling(underlay))
        XCTAssertEqual(gtkWidgetTypeName(underlay), "GtkBox")
        XCTAssertNotNil(findFirstDescendant(ofType: "GtkLabel", in: content))
    }

    func testTranslucentToolbarBackgroundDoesNotDimChildPixels() throws {
        try requireGTK()

        let opaque = try renderToolbarContrastSample(backgroundAlpha: 1.0)
        let translucent = try renderToolbarContrastSample(backgroundAlpha: 0.25)

        XCTAssertGreaterThan(opaque.darkPixelCount, 20, "Fixture should render black Image/Text child pixels")
        XCTAssertLessThanOrEqual(
            abs(translucent.minimumLuminance - opaque.minimumLuminance),
            8,
            "Translucent background must not alter the darkest child glyph pixels"
        )
        XCTAssertGreaterThanOrEqual(
            translucent.darkPixelCount,
            Int(Double(opaque.darkPixelCount) * 0.85),
            "Translucent background must preserve the child glyph pixel population"
        )
    }

    func testClippedWithPadding() throws {
        try requireGTK()

        let widget = widgetFromOpaque(gtkRenderView(
            Text("Hello").padding().clipped()
        ))
        XCTAssertEqual(gtk_widget_get_overflow(widget), GTK_OVERFLOW_HIDDEN)
    }
}

// MARK: - Helpers

private struct ToolbarContrastSample {
    let minimumLuminance: Int
    let darkPixelCount: Int
}

private func renderToolbarContrastSample(backgroundAlpha: Double) throws -> ToolbarContrastSample {
    let width = 180
    let height = 64
    let view = ZStack(alignment: .topLeading) {
        Color.white
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
            Text("Scope")
        }
        .foregroundColor(.black)
        .padding(8)
        .background(Color.white.opacity(backgroundAlpha))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(width: 150, height: 40, alignment: .leading)
    }
    .frame(width: Double(width), height: Double(height), alignment: .topLeading)

    return try renderARGB32Sample(view, width: width, height: height)
}

private func renderARGB32Sample<V: View>(_ view: V, width: Int, height: Int) throws -> ToolbarContrastSample {
    let widget = widgetFromOpaque(gtkRenderView(view))
    g_object_ref(gpointer(widget))
    defer { g_object_unref(gpointer(widget)) }

    let windowWidget = try XCTUnwrap(gtk_window_new())
    let window = windowPointer(windowWidget)
    defer { gtk_window_destroy(window) }

    gtk_window_set_decorated(window, 0)
    gtk_window_set_default_size(window, gint(width), gint(height))
    gtk_window_set_child(window, widget)

    gtk_widget_set_hexpand(widget, 1)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_size_request(widget, gint(width), gint(height))
    gtk_widget_set_size_request(windowWidget, gint(width), gint(height))

    gtk_widget_realize(windowWidget)
    gtk_widget_set_visible(windowWidget, 1)
    while g_main_context_iteration(nil, 0) != 0 {}

    var allocation = GdkRectangle(x: 0, y: 0, width: gint(width), height: gint(height))
    gtk_widget_allocate(windowWidget, gint(width), gint(height), -1, nil)
    gtk_widget_size_allocate(widget, &allocation, -1)
    gtk_widget_allocate(widget, gint(width), gint(height), -1, nil)
    while g_main_context_iteration(nil, 0) != 0 {}

    let snapshot = try XCTUnwrap(gtk_snapshot_new())
    gtk_widget_snapshot_child(windowWidget, widget, snapshot)
    let renderNode = try XCTUnwrap(gtk_snapshot_to_node(snapshot))
    g_object_unref(gpointer(snapshot))
    defer { gsk_render_node_unref(renderNode) }

    let surface = try XCTUnwrap(cairo_image_surface_create(
        CAIRO_FORMAT_ARGB32,
        gint(width),
        gint(height)
    ))
    defer { cairo_surface_destroy(surface) }

    let cr = try XCTUnwrap(cairo_create(surface))
    defer { cairo_destroy(cr) }

    gsk_render_node_draw(renderNode, cr)
    cairo_surface_flush(surface)

    let raw = try XCTUnwrap(cairo_image_surface_get_data(surface))
    let stride = Int(cairo_image_surface_get_stride(surface))
    var minimumLuminance = 255
    var darkPixelCount = 0

    for y in 0..<height {
        let row = raw.advanced(by: y * stride)
        for x in 0..<width {
            let pixel = row.advanced(by: x * 4)
            let blue = Int(pixel[0])
            let green = Int(pixel[1])
            let red = Int(pixel[2])
            let alpha = Int(pixel[3])
            guard alpha > 0 else { continue }
            let luminance = (red * 299 + green * 587 + blue * 114) / 1000
            minimumLuminance = min(minimumLuminance, luminance)
            if luminance < 96 {
                darkPixelCount += 1
            }
        }
    }

    return ToolbarContrastSample(
        minimumLuminance: minimumLuminance,
        darkPixelCount: darkPixelCount
    )
}

private func requireGTK(
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard gtk_is_initialized() != 0 else {
        throw XCTSkip("GTK could not initialize in this environment.", file: file, line: line)
    }
}

private func gtkWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func findFirstDescendant(ofType typeName: String, in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
    guard gtk_swift_is_widget(widget) != 0 else { return nil }
    let name = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if name == typeName { return widget }
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        if let found = findFirstDescendant(ofType: typeName, in: c) { return found }
        child = gtk_widget_get_next_sibling(c)
    }
    return nil
}
