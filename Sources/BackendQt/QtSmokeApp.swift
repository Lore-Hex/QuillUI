// QtSmokeApp.swift — the real SwiftUI App rendered through QtBackend.
//
// This is the payload the spike proves: a genuine SwiftOpenUI `App` (NOT
// hand-built C++ Qt widgets) whose WindowGroup → VStack { Text; Button; panel }
// is walked by the generic QtBackend and rendered with native Qt widgets.
//
// It is shaped to exercise the SAME surface the existing Qt interaction smoke
// targets and the screenshot verifier check:
//   * window ~640x760 (validator requires 600–700 x 720–800)
//   * a tappable Button that toggles @State
//   * a dark panel (Color #111827) that appears on click and lands in the
//     verifier's open-panel ROI (x∈[+32,+430], y∈[+145,+310], dark≥10000)
//
// The point is that all of this is plain SwiftUI; the renderer is app-agnostic.

#if canImport(CQtBridge)
import SwiftOpenUI

/// Window/panel metrics chosen to satisfy validate_quill_backend_interaction_smoke.
enum QtSmokeMetrics {
    static let windowWidth: Double = 640
    static let windowHeight: Double = 760
    // Pushes the panel into the verifier's vertical ROI (top+145…+310) and
    // makes it wide/tall enough to clear the 10_000 dark-pixel threshold.
    static let topInsetHeight: Double = 150
    static let panelWidth: Double = 398
    static let panelHeight: Double = 170
}

public struct QtSmokeApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup("Quill Backend Interaction") {
            QtSmokeView()
        }
        .defaultWindowSize(width: QtSmokeMetrics.windowWidth, height: QtSmokeMetrics.windowHeight)
    }
}

struct QtSmokeView: View {
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Native backend click target")

            Button(isOpen ? "Hide Panel" : "Open Panel") {
                isOpen.toggle()
            }

            // Vertical inset so the toggled panel lands in the verifier ROI.
            Color(red: 0.969, green: 0.969, blue: 0.973)
                .frame(width: QtSmokeMetrics.panelWidth, height: QtSmokeMetrics.topInsetHeight)

            if isOpen {
                Color(hex: "#111827")
                    .frame(width: QtSmokeMetrics.panelWidth, height: QtSmokeMetrics.panelHeight)
            }
        }
    }
}

#endif
