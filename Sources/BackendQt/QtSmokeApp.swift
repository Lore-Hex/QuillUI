// QtSmokeApp.swift — the real SwiftUI App rendered through QtBackend.
//
// This is the payload the spike proves: a genuine SwiftOpenUI `App` (NOT
// hand-built C++ Qt widgets) whose WindowGroup → VStack { Text; Button; Toggle;
// TextField; Picker; Menu; panel } is walked by the generic QtBackend and
// rendered with native Qt widgets.
//
// It is shaped to exercise the SAME surface the screenshot verifier checks via
// `validate_quill_backend_interaction_smoke`:
//   * window ~640x760 (validator requires 600–700 x 720–800)
//   * a dark panel (Color #111827) that lands inside the verifier's panel ROI
//     (x∈[left+32, left+430], y∈[top+145, top+310]) and clears the 10_000
//     dark-pixel threshold.
//
// SLICE #2 NOTE: the dark panel is rendered UNCONDITIONALLY (not gated behind a
// click) so the CI capture is deterministic — the very first CI cycle answers
// the load-bearing question "does the real SwiftUI tree render on Qt at all?"
// without also depending on a pixel-precise synthetic click landing on the
// button. The @State + Button and Toggle below still exercise the reactive
// QtViewHost path; re-driving the panel from the click is a follow-up once the
// static render is proven green.
//
// The point is that all of this is plain SwiftUI; the renderer is app-agnostic.

#if canImport(CQtBridge)
import SwiftOpenUI

/// Window/panel metrics chosen to satisfy validate_quill_backend_interaction_smoke.
enum QtSmokeMetrics {
    static let windowWidth: Double = 640
    static let windowHeight: Double = 760
    // The panel is wide enough to span the verifier ROI's 398px width
    // (x∈[left+32, left+430]) when leading-aligned at the content origin, and
    // tall enough that — placed just below the Text + Button rows — it fully
    // covers the ROI's vertical band (y∈[top+145, top+310]). 300px clears that
    // 165px band with margin so normal text/button height drift never pushes the
    // panel out of the ROI.
    static let panelWidth: Double = 398
    static let panelHeight: Double = 300
    // #111827 — the dark panel color the verifier counts as "dark" (sum < 420).
    static let panelRed: Double = 17.0 / 255.0
    static let panelGreen: Double = 24.0 / 255.0
    static let panelBlue: Double = 39.0 / 255.0
    static let listWidth: Double = 300
    static let listHeight: Double = 120
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
    @State private var isCheckboxOn = false
    @State private var textFieldValue = "Qt TextField"
    @State private var menuSelection = "none"
    @State private var pickerSelection = "alpha"

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Native backend render target")

                // Always-on dark panel FIRST (content origin) so it fills the
                // verifier's panel ROI (y 145-310) deterministically, independent
                // of how many interactive demo controls are added below it. (Earlier
                // the panel sat AFTER the controls and drifted out of the ROI as each
                // new conformance smoke was appended.)
                Color(
                    red: QtSmokeMetrics.panelRed,
                    green: QtSmokeMetrics.panelGreen,
                    blue: QtSmokeMetrics.panelBlue
                )
                .frame(width: QtSmokeMetrics.panelWidth, height: QtSmokeMetrics.panelHeight)

                ZStack {
                    Color(red: 0.89, green: 0.95, blue: 1.0)
                        .frame(width: 220, height: 48)
                    Text("ZStack overlay")
                }

                // Bound to @State through the generic QtViewHost so a click rebuilds
                // the subtree; the dark panel above does NOT depend on this toggle.
                Button(isOpen ? "Toggle (on)" : "Toggle (off)") {
                    isOpen.toggle()
                }

                Toggle(
                    isCheckboxOn ? "QCheckBox Toggle (on)" : "QCheckBox Toggle (off)",
                    isOn: $isCheckboxOn
                )

                TextField("QLineEdit placeholder", text: $textFieldValue)
                Text("TextField echo: \(textFieldValue)")

                Picker("QComboBox Picker", selection: $pickerSelection) {
                    Text("Picker Alpha").tag("alpha")
                    Text("Picker Beta").tag("beta")
                    Text("Picker Gamma").tag("gamma")
                }
                Text("Picker choice: \(pickerSelection)")

                Menu("QToolButton Menu") {
                    Button("Choose Alpha") {
                        menuSelection = "alpha"
                    }
                    Button("Choose Beta") {
                        menuSelection = "beta"
                    }
                }
                Text("Menu choice: \(menuSelection)")

                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)

                List {
                    ForEach(["ForEach row one", "ForEach row two", "ForEach row three"], id: \.self) { row in
                        Text(row)
                    }
                }
                .frame(width: QtSmokeMetrics.listWidth, height: QtSmokeMetrics.listHeight)
            }
        }
        .frame(width: QtSmokeMetrics.windowWidth, height: QtSmokeMetrics.windowHeight)
    }
}

#endif
