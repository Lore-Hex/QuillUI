// QuillAppKitQt — Qt6 runtime backing for the AppKit shadow, the Qt analogue of
// QuillAppKitGTK. Unmodified Mac apps that `import AppKit` and link this target
// get their NSApplication/NSWindow driven by Qt6 Widgets (via CQuillAppKitQt),
// laid out by QuillAutoLayout (kiwi Cassowary), with no source changes.
//
// M1 slice 1 (issue #231): NSApplication.run() + NSWindow create/show/title/size.
// NSView, NSControl, NSTableView, … follow in later slices. Mirrors the
// extension + auto-installed run-hook + ObjectIdentifier side-table pattern that
// QuillAppKitGTK established, so the AppKit shadow stays a clean stub.

import AppKit
import CQuillAppKitQt

/// Lazy QApplication bring-up (honours QT_QPA_PLATFORM, e.g. "offscreen").
public enum QuillQt {
    /// True if Qt is usable for widget creation.
    @discardableResult
    public static func ensureInitialized() -> Bool {
        quill_appkit_qt_app_init() != 0
    }

    public static func runMainLoop() {
        quill_appkit_qt_app_run()
    }
}

// MARK: - NSApplication: Qt event loop

extension NSApplication {
    /// Phase B runtime: route NSApplication.run() into Qt's event loop when Qt
    /// is available; otherwise behaves like the headless stub.
    public func runQt() {
        guard QuillQt.ensureInitialized() else { return }
        QuillQt.runMainLoop()
    }
}

/// Installs the Qt run() implementation on NSApplication. Unmodified apps that
/// call `NSApp.run()` then pump the Qt loop — no source changes needed.
public func _quillAppKitQtInstallRunHook() {
    NSApplication._runHook = {
        NSApplication.shared.runQt()
    }
}

/// One-shot installer: touching any public symbol of this module installs the
/// run hook (Swift doesn't run top-level expressions at module init, so we hang
/// the side effect off a lazy static — same trick as QuillAppKitGTK).
public enum QuillAppKitQtAutoInstall {
    public static let didInstall: Bool = {
        _quillAppKitQtInstallRunHook()
        return true
    }()
}

// MARK: - NSWindow: QWidget-backed

extension NSWindow {
    /// Lazily-created QWidget handle. Nil until `showAsQtWindow()` runs in a
    /// Qt-capable process. Backed by the lifetime-tied `quillBackendHandle`
    /// slot (NSResponder) so a reused object address can't surface a stale handle.
    public var qtWindowHandle: UnsafeMutableRawPointer? {
        get { quillBackendHandle }
        set { quillBackendHandle = newValue }
    }

    /// Phase B: create + show a real QWidget window if Qt is initialized.
    /// Falls back to a no-op stub when no Qt platform is available.
    public func showAsQtWindow() {
        guard QuillQt.ensureInitialized() else { return }
        if qtWindowHandle == nil {
            guard let widget = quill_appkit_qt_window_new() else { return }
            qtWindowHandle = widget
            title.withCString { quill_appkit_qt_window_set_title(widget, $0) }
            let width = Int32(frame.size.width.rounded())
            let height = Int32(frame.size.height.rounded())
            if width > 0 && height > 0 {
                quill_appkit_qt_window_set_size(widget, width, height)
            }
        }
        if let handle = qtWindowHandle {
            quill_appkit_qt_window_present(handle)
            isVisible = true
        }
    }

    public func closeQtWindow() {
        guard let handle = qtWindowHandle else { return }
        quill_appkit_qt_window_close(handle)
        qtWindowHandle = nil
        isVisible = false
    }

    /// Reads the title back from the underlying QWidget — proves the C side
    /// stored what Swift wrote (mirrors QuillAppKitGTK.gtkWindowTitle).
    public var qtWindowTitle: String? {
        guard let handle = qtWindowHandle else { return nil }
        guard let cstr = quill_appkit_qt_window_title(handle) else { return nil }
        return String(cString: cstr)
    }

    /// Reads width/height back from the QWidget. Returns (0, 0) if no handle.
    public var qtWindowSize: (Int32, Int32) {
        guard let handle = qtWindowHandle else { return (0, 0) }
        var w: Int32 = 0
        var h: Int32 = 0
        quill_appkit_qt_window_size(handle, &w, &h)
        return (w, h)
    }
}
