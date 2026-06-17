// QtBackend.swift — generic SwiftUI→Qt rendering backend for QuillUI.
//
// `QtBackend` is the Qt sibling of SwiftOpenUI's `GTK4Backend`: a concrete
// `RenderBackend` that takes a real SwiftUI `App`, walks its scene/view tree,
// builds native Qt widgets through CQtBridge, and runs QApplication::exec().
//
// This is the crux of the spike — proving that a single, generic renderer (zero
// app-specific code) can host a real SwiftUI tree on Qt, exactly as GTK already
// does. The per-app C++ shims under CQuillQt6WidgetsShim become unnecessary
// once this renderer reaches parity.

#if canImport(CQtBridge)
import CQtBridge
import SwiftOpenUI
import SwiftOpenUISymbols
import Foundation

/// Default window size used when a WindowGroup does not specify one. Matches the
/// GTK backend's automatic-sizing fallback closely enough for the smoke gate.
private let qtDefaultAutomaticWindowWidth: Double = 800
private let qtDefaultAutomaticWindowHeight: Double = 600

private func qtRegisterBundledIconFont() {
    quill_qt_bridge_material_symbols_register_font(
        MaterialSymbolsResources.roundedRegularFontURL.path
    )
}

/// Stderr breadcrumb for the Swift side of the generic-backend smoke. The
/// startup segfault this backend hit produced only a bare "*** Signal 11 ***"
/// under Xvfb with no Swift backtrace, so the whole launch path now logs each
/// step to stderr and flushes. Paired with CQtBridge's `[cqtbridge]` traces,
/// the CI app-log (/tmp/quillui-qt-generic-smoke-app.log) shows exactly how far
/// the App→Scene→View walk got before any future crash — splitting "crashed in
/// QApplication startup" from "crashed building the SwiftUI tree" from "crashed
/// entering the event loop".
@inline(__always)
func qtBackendTrace(_ message: String) {
    FileHandle.standardError.write(Data("[backendqt] \(message)\n".utf8))
}

/// Protocol for scenes that can render onto the Qt application. Mirror of GTK's
/// `GTKWindowRenderable`.
protocol QtWindowRenderable {
    func qtRender(app: OpaquePointer)
}

/// Generic Qt rendering backend for SwiftOpenUI.
public struct QtBackend: RenderBackend {
    public init() {}

    public func run<A: App>(_ appType: A.Type) {
        qtBackendTrace("run: enter")

        qtBackendTrace("run: before QApplication create")
        let app = qtOpaque(
            quill_qt_bridge_application_create(CommandLine.argc, CommandLine.unsafeArgv)
        )
        qtBackendTrace("run: after QApplication create")
        qtRegisterBundledIconFont()

        // Apply a baseline stylesheet so the smoke window's light chrome and
        // dark panel render with the colors the screenshot verifier expects.
        // App-authored styling flows through per-widget QSS in a later slice.
        quill_qt_bridge_application_set_stylesheet(qtHandle(app), QtBaselineStyle.qss)

        qtBackendTrace("run: before App init + scene render")
        let instance = A()
        MainActor.assumeIsolated {
            qtRenderScene(instance.body, app: app)
        }
        qtBackendTrace("run: after scene render")

        // Pump Foundation RunLoop sources alongside Qt's loop in a later slice
        // (Timer-driven SwiftUI work). Slice #1's smoke is event-driven only.
        qtBackendTrace("run: before event loop")
        let status = quill_qt_bridge_application_exec(qtHandle(app))
        qtBackendTrace("run: event loop returned status \(status)")
        if status != 0 {
            FileHandle.standardError.write(
                Data("Qt application exited with status \(status)\n".utf8)
            )
        }
    }
}

/// Recursively render a Scene. Terminal scenes (WindowGroup) render directly;
/// composite scenes recurse through `body`. Mirror of `gtkRenderScene`.
func qtRenderScene<S: Scene>(_ scene: S, app: OpaquePointer) {
    if let renderable = scene as? QtWindowRenderable {
        renderable.qtRender(app: app)
        return
    }
    if S.Body.self != Never.self {
        MainActor.assumeIsolated {
            qtRenderScene(scene.body, app: app)
        }
    }
}

extension WindowGroup: QtWindowRenderable {
    func qtRender(app: OpaquePointer) {
        guard launchesAtStartup else {
            qtBackendTrace("WindowGroup.qtRender: deferred title=\(title)")
            return
        }

        qtBackendTrace("WindowGroup.qtRender: creating window")
        let window = qtOpaque(quill_qt_bridge_window_create(title))

        let width = defaultWindowWidth ?? qtDefaultAutomaticWindowWidth
        let height = defaultWindowHeight ?? qtDefaultAutomaticWindowHeight
        quill_qt_bridge_window_resize(qtHandle(window), Int32(width), Int32(height))

        if let minW = minWindowWidth, let minH = minWindowHeight {
            quill_qt_bridge_window_set_minimum_size(qtHandle(window), Int32(minW), Int32(minH))
        }

        qtBackendTrace("WindowGroup.qtRender: building root content view")
        let content = qtRenderView(self.content)
        qtBackendTrace("WindowGroup.qtRender: root content view built")
        quill_qt_bridge_window_set_content(qtHandle(window), qtHandle(content))
        // Root content fills the window's client area.
        quill_qt_bridge_widget_set_geometry(
            qtHandle(content), 0, 0, Int32(width), Int32(height)
        )
        qtBackendTrace("WindowGroup.qtRender: before window show")
        quill_qt_bridge_widget_show(qtHandle(window))
        qtBackendTrace("WindowGroup.qtRender: window shown")
    }
}

extension TupleScene: QtWindowRenderable {
    func qtRender(app: OpaquePointer) {
        qtRenderScene(scene0, app: app)
        qtRenderScene(scene1, app: app)
    }
}

/// Baseline QSS for the generic backend. Keeps the smoke window's surfaces in
/// the same palette family the GTK/Qt smokes already use so the shared
/// screenshot verifier thresholds apply unchanged.
enum QtBaselineStyle {
    static let qss = """
    QWidget { background: #f7f7f8; color: #111827; font-size: 13px; }
    QLabel { background: transparent; }
    QPushButton { background: #ffffff; border: 1px solid #cfd3dc; border-radius: 6px; padding: 6px 10px; }
    QPushButton:pressed { background: #e7e9ef; }
    QWidget#quill-qt-smoke-panel { background: #111827; border-radius: 6px; }
    QLabel#quill-qt-smoke-panel-title { color: #ffffff; font-size: 18px; font-weight: 650; }
    QLabel#quill-qt-smoke-panel-text { color: #d1d5db; }
    QLabel#quill-qt-smoke-title { font-size: 24px; font-weight: 650; }
    """
}

#endif
