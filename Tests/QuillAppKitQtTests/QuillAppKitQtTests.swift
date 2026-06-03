import Testing
import AppKit
@testable import QuillAppKitQt

/// M1 slice 1 (issue #231): prove the AppKit shadow's NSApplication/NSWindow are
/// backed by a real Qt6 widget on Linux — i.e. unmodified `import AppKit` code
/// drives Qt. Run headless with QT_QPA_PLATFORM=offscreen (CI/Docker). Mirrors
/// QuillAppKitGTK's Phase-B round-trip verification.
@Suite("QuillAppKitQt / Qt-backed AppKit (M1)")
@MainActor
struct QuillAppKitQtTests {

    @Test("NSWindow backs onto a real QWidget; title + size round-trip through the bridge")
    func windowRoundTrip() {
        guard QuillQt.ensureInitialized() else {
            // No Qt platform available (e.g. no offscreen plugin) — nothing to
            // assert; matches the headless no-op stub. Don't fail the suite.
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: .titled,
            backing: .buffered,
            defer: false
        )
        window.title = "Manage WireGuard Tunnels"
        window.showAsQtWindow()

        // The stub now owns a live QWidget.
        #expect(window.qtWindowHandle != nil)
        // The C-side widget stored exactly what Swift wrote.
        #expect(window.qtWindowTitle == "Manage WireGuard Tunnels")
        let (w, h) = window.qtWindowSize
        #expect(w == 480 && h == 320)

        window.closeQtWindow()
        #expect(window.qtWindowHandle == nil)
    }

    @Test("The run hook is installed so NSApp.run() routes into Qt")
    func runHookInstalled() {
        #expect(QuillAppKitQtAutoInstall.didInstall)
        #expect(NSApplication._runHook != nil)
    }
}
