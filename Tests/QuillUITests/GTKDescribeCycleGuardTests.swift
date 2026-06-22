import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import SwiftUI

@Suite("GTK describe cycle guard")
@MainActor
struct GTKDescribeCycleGuardTests {
    @Test("cyclic AnyView body records diagnostic chain")
    func cyclicAnyViewBodyRecordsDiagnosticChain() {
        let previousHandler = gtkDescribeDepthLimitExceededHandler
        var capturedNames: [String] = []

        gtkDescribeDepthLimitExceededHandler = { names in
            capturedNames = names
        }
        defer { gtkDescribeDepthLimitExceededHandler = previousHandler }

        _ = gtkDescribeView(Cyclic())

        #expect(capturedNames.count == 8)
        #expect(
            capturedNames.contains { $0.contains("Cyclic") },
            "Expected cycle chain to include Cyclic, got \(capturedNames.joined(separator: " -> "))"
        )
    }

    @Test("SwiftUI shadow foregroundStyle reaches GTK labels through wrappers")
    func swiftUIShadowForegroundStyleReachesGTKLabelsThroughWrappers() throws {
        if gtk_is_initialized() == 0, gtk_init_check() == 0 {
            return
        }

        let widget = widgetFromOpaque(gtkRenderView(
            LazyVStack([0]) { _ in
                Text("Ask QuillCode")
                    .font(.title3.weight(.semibold))
            }
            .background(Color(red: 0.03, green: 0.06, blue: 0.08))
            .foregroundStyle(Color(red: 0.93, green: 0.97, blue: 0.98))
        ))
        let window = gtk_window_new()!
        defer { gtk_window_destroy(windowPointer(window)) }
        gtk_window_set_child(windowPointer(window), widget)
        gtk_window_present(windowPointer(window))
        drainGTKMainContext(maxIterations: 100)
        let label = try firstGTKLabel(in: widget)

        #expect(String(cString: gtk_label_get_text(OpaquePointer(label))) == "Ask QuillCode")
        #expect(gtk_swift_label_get_use_markup(label) != 0)
    }
}

private struct Cyclic: View {
    var body: some View {
        AnyView(Cyclic())
    }
}

private func firstGTKLabel(in widget: UnsafeMutablePointer<GtkWidget>) throws -> UnsafeMutablePointer<GtkWidget> {
    if gtkWidgetTypeName(widget) == "GtkLabel" {
        return widget
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = try? firstGTKLabel(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    struct MissingGTKLabel: Error {}
    throw MissingGTKLabel()
}

private func gtkWidgetTypeName(_ widget: UnsafeMutablePointer<GtkWidget>) -> String {
    String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
}

private func drainGTKMainContext(maxIterations: Int = 20) {
    for _ in 0..<maxIterations {
        if g_main_context_iteration(nil, 0) == 0 {
            break
        }
    }
}
#endif
