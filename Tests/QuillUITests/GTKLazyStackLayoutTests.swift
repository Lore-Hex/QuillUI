import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import QuillSwiftUICompatibility
import SwiftUI

@Suite("GTK lazy stack layout", .serialized)
@MainActor
struct GTKLazyStackLayoutTests {
    @Test("builder LazyHStack keeps ForEach horizontal and preserves spacing")
    func builderLazyHStackPreservesAxisAndSpacing() throws {
        if !gtkTestDisplayIsAvailable() {
            return
        }

        let root = widgetFromOpaque(gtkRenderView(
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 12) {
                    ForEach(0..<3, id: \.self) { index in
                        Text("Media \(index)")
                            .frame(width: 72, height: index == 1 ? 20 : 40)
                    }
                }
            }
            .frame(width: 260, height: 56)
        ))
        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(windowPointer(window))
            drainLazyStackGTKMainContext()
        }
        gtk_window_set_default_size(windowPointer(window), 260, 56)
        gtk_window_set_child(windowPointer(window), root)
        gtk_window_present(windowPointer(window))
        drainLazyStackGTKMainContext(maxIterations: 100)

        var labels: [UnsafeMutablePointer<GtkWidget>] = []
        collectLazyStackLabels(in: root, into: &labels)
        let mediaLabels = labels.filter {
            String(cString: gtk_label_get_text(OpaquePointer($0))).hasPrefix("Media ")
        }
        #expect(mediaLabels.count == 3)

        let origins = mediaLabels.map { lazyStackOrigin(of: $0, in: root) }
        #expect(origins[1].x - origins[0].x >= 80)
        #expect(origins[2].x - origins[1].x >= 80)
        #expect(origins[1].y > origins[0].y)
        #expect(abs(origins[0].y - origins[2].y) <= 1)
    }

    @Test("containerRelativeFrame divides the horizontal scroll viewport")
    func containerRelativeFrameDividesHorizontalScrollViewport() throws {
        if !gtkTestDisplayIsAvailable() {
            return
        }

        let root = widgetFromOpaque(gtkRenderView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue)
                        .containerRelativeFrame(
                            .horizontal,
                            count: 2,
                            span: 1,
                            spacing: 12
                        )
                        .frame(height: 40)
                }
            }
            .frame(width: 260, height: 56)
        ))
        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(windowPointer(window))
            drainLazyStackGTKMainContext()
        }
        gtk_window_set_default_size(windowPointer(window), 260, 56)
        gtk_window_set_child(windowPointer(window), root)
        gtk_window_present(windowPointer(window))
        drainLazyStackGTKMainContext(maxIterations: 200, waitForFrameTicks: true)

        var drawingAreas: [UnsafeMutablePointer<GtkWidget>] = []
        collectLazyStackWidgets(ofType: "GtkDrawingArea", in: root, into: &drawingAreas)
        let media = try #require(drawingAreas.first)
        let width = gtk_widget_get_width(media)

        #expect(width >= 115)
        #expect(width <= 135)
    }

    @Test("horizontal ScrollView proposes its height to filling relative content")
    func horizontalScrollViewProposesHeightToFillingRelativeContent() throws {
        if !gtkTestDisplayIsAvailable() {
            return
        }

        let root = widgetFromOpaque(gtkRenderView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        }
                        .overlay(alignment: .topTrailing) {
                            Text("ALT")
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .containerRelativeFrame(.horizontal)
                }
            }
            .frame(width: 260, height: 120)
        ))
        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(windowPointer(window))
            drainLazyStackGTKMainContext()
        }
        gtk_window_set_default_size(windowPointer(window), 260, 120)
        gtk_window_set_child(windowPointer(window), root)
        gtk_window_present(windowPointer(window))
        drainLazyStackGTKMainContext(maxIterations: 200, waitForFrameTicks: true)

        var drawingAreas: [UnsafeMutablePointer<GtkWidget>] = []
        collectLazyStackWidgets(ofType: "GtkDrawingArea", in: root, into: &drawingAreas)
        let media = try #require(drawingAreas.first)
        let tree = lazyStackWidgetTreeDescription(root)

        #expect(gtk_widget_get_width(media) >= 250, Comment(rawValue: tree))
        #expect(gtk_widget_get_height(media) >= 110, Comment(rawValue: tree))
    }
}

private func collectLazyStackLabels(
    in widget: UnsafeMutablePointer<GtkWidget>,
    into labels: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkLabel" {
        labels.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        collectLazyStackLabels(in: current, into: &labels)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func collectLazyStackWidgets(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    into matches: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == typeName {
        matches.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        collectLazyStackWidgets(ofType: typeName, in: current, into: &matches)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func lazyStackWidgetTreeDescription(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    depth: Int = 0
) -> String {
    var requestWidth: gint = 0
    var requestHeight: gint = 0
    gtk_widget_get_size_request(widget, &requestWidth, &requestHeight)
    let type = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    var lines = [
        "\(String(repeating: "  ", count: depth))\(type) "
            + "size=\(gtk_widget_get_width(widget))x\(gtk_widget_get_height(widget)) "
            + "request=\(requestWidth)x\(requestHeight) "
            + "expand=\(gtk_widget_get_hexpand(widget))/\(gtk_widget_get_vexpand(widget))"
    ]
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        lines.append(lazyStackWidgetTreeDescription(current, depth: depth + 1))
        child = gtk_widget_get_next_sibling(current)
    }
    return lines.joined(separator: "\n")
}

private func lazyStackOrigin(
    of widget: UnsafeMutablePointer<GtkWidget>,
    in root: UnsafeMutablePointer<GtkWidget>
) -> (x: Double, y: Double) {
    var x = 0.0
    var y = 0.0
    _ = gtk_widget_translate_coordinates(widget, root, 0, 0, &x, &y)
    return (x, y)
}

private func drainLazyStackGTKMainContext(
    maxIterations: Int = 20,
    waitForFrameTicks: Bool = false
) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0, !waitForFrameTicks {
            break
        }
        if waitForFrameTicks {
            g_usleep(5_000)
        }
    }
}
#endif
