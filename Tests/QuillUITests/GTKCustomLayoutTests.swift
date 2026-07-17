import Testing

#if os(Linux)
@testable import BackendGTK4
import CGTK
import CGTKBridge
import Foundation
import QuillSwiftUICompatibility
import SwiftUI

@Suite("GTK custom layout", .serialized)
@MainActor
struct GTKCustomLayoutTests {
    @Test("custom Layout contains child fill intent inside an IceCubes list row")
    func customLayoutContainsChildFillIntent() throws {
        if !gtkTestDisplayIsAvailable() {
            return
        }

        let root = widgetFromOpaque(gtkRenderView(
            List {
                VStack(alignment: .leading, spacing: 12) {
                    Text("QuillUI fixture timeline")
                    HStack {
                        GTKIceCubesFeaturedMediaLayout(
                            originalWidth: 640,
                            originalHeight: 360
                        ) {
                            Group {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.blue)
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray, lineWidth: 1)
                                    )
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            Text("ALT")
                        }
                        .clipped()
                        .cornerRadius(10)
                    }
                    Text("Actions")
                }
            }
            .frame(width: 560, height: 500)
        ))
        let window = gtk_window_new()!
        defer {
            gtk_window_destroy(customLayoutWindowPointer(window))
            drainCustomLayoutGTKMainContext()
        }
        gtk_window_set_default_size(customLayoutWindowPointer(window), 560, 500)
        gtk_window_set_child(customLayoutWindowPointer(window), root)
        gtk_window_present(customLayoutWindowPointer(window))
        drainCustomLayoutGTKMainContext(maxIterations: 300, waitForFrameTicks: true)

        var drawingAreas: [UnsafeMutablePointer<GtkWidget>] = []
        collectCustomLayoutWidgets(ofType: "GtkDrawingArea", in: root, into: &drawingAreas)
        let mediaSizes = drawingAreas.map {
            (width: gtk_widget_get_width($0), height: gtk_widget_get_height($0))
        }
        let media = try #require(mediaSizes.max { lhs, rhs in
            lhs.width * lhs.height < rhs.width * rhs.height
        })

        #expect(media.width >= 500, Comment(rawValue: "drawing areas: \(mediaSizes)"))
        #expect(media.height >= 280, Comment(rawValue: "drawing areas: \(mediaSizes)"))
        #expect(media.height <= 320, Comment(rawValue: "drawing areas: \(mediaSizes)"))
    }
}

private struct GTKIceCubesFeaturedMediaLayout: Layout {
    let originalWidth: CGFloat
    let originalHeight: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        _ = subviews
        _ = cache
        let width = proposal.width ?? originalWidth
        guard width > 0, originalWidth > 0 else { return .zero }
        return CGSize(
            width: max(width, 200),
            height: min(width / originalWidth * originalHeight, 450)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let view = subviews.first else { return }
        view.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

private func collectCustomLayoutWidgets(
    ofType typeName: String,
    in widget: UnsafeMutablePointer<GtkWidget>,
    into matches: inout [UnsafeMutablePointer<GtkWidget>]
) {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == typeName {
        matches.append(widget)
    }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        collectCustomLayoutWidgets(ofType: typeName, in: current, into: &matches)
        child = gtk_widget_get_next_sibling(current)
    }
}

private func drainCustomLayoutGTKMainContext(
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

private func customLayoutWindowPointer(
    _ widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWindow> {
    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWindow.self)
}
#endif
