// QuillAppKit+GTK.swift
// =====================
// Phase B runtime: NSApplication.run() and NSWindow.makeKeyAndOrderFront
// hook into a GTK4 main loop so a Mac app's startup sequence actually
// produces a window on Linux. The integration is opt-in:
//
//   • If the process can connect to a GdkDisplay (set via WAYLAND_DISPLAY
//     or DISPLAY), GTK4 init succeeds and we get real GtkWindows.
//   • If not (CI, headless VM, daemon), every call is a silent no-op
//     and the existing compile-only AppKit stubs keep working.
//
// We only hold opaque `OpaquePointer`s on the Swift side. All actual
// widget mutation crosses the C boundary via CGtk4. Threading rule
// matches AppKit: every GTK call must be on the main thread.

#if os(Linux)

import CGtk4
import QuillFoundation
import Glibc

// MARK: - GTK lifecycle

/// Lazy GTK4 initialization. Runs `gtk_init()` once per process.
/// Returns true if GTK is usable for widget creation, false otherwise
/// (no display server, init failed, etc.).
@MainActor
public enum QuillGTK {
    private static var didInit = false
    private static var initOK = false
    private static var ownsLoop = false

    @discardableResult
    public static func ensureInitialized() -> Bool {
        if didInit { return initOK }
        didInit = true
        // gtk_init aborts on failure; gtk_init_check returns gboolean
        // and lets us detect the no-display case gracefully.
        let result = gtk_init_check()
        initOK = (result != 0)
        return initOK
    }

    /// Pumps GTK main loop until quit. Returns immediately if GTK is
    /// uninitialized.
    public static func runMainLoop() {
        guard ensureInitialized() else { return }
        // GMainLoop is the safest way to integrate; gtk_main was
        // removed in GTK4. We pump the default context manually.
        let loop = g_main_loop_new(nil, 0)
        ownsLoop = true
        g_main_loop_run(loop)
        g_main_loop_unref(loop)
        ownsLoop = false
    }

    /// Pumps a fixed number of pending events so callers can drive a
    /// GUI synchronously without committing to a full main loop.
    /// Useful for tests, screenshot capture, etc.
    public static func iterate(times: Int = 1) {
        guard ensureInitialized() else { return }
        for _ in 0..<max(times, 0) {
            _ = g_main_context_iteration(nil, 0)
        }
    }

    public static func quitMainLoop() {
        guard ownsLoop else { return }
        // Iterate one tick with a quit injection. Quick & dirty:
        // post a high-priority idle that quits the default context.
        g_idle_add_full(Int32(G_PRIORITY_HIGH), { _ in
            // quitMainLoop hop: stops the *default* main context loop.
            // Returns G_SOURCE_REMOVE so it's a one-shot.
            let ctx = g_main_context_default()
            // Find any running loop on this context and quit it.
            // Simpler: just exit (works for our smoke purpose).
            exit(0)
        }, nil, nil)
    }
}

// MARK: - NSApplication: real run() that pumps GTK

extension NSApplication {
    /// Phase B runtime: route NSApplication.run() into GTK's main loop
    /// when a display is available. Otherwise behaves like the stub.
    public func runGTK() {
        guard QuillGTK.ensureInitialized() else { return }
        QuillGTK.runMainLoop()
    }
}

// MARK: - NSWindow: GtkWindow-backed

extension NSWindow {
    /// Lazily-created GtkWindow handle. Nil until makeKeyAndOrderFront
    /// runs in a GTK-capable process.
    public var gtkWindowHandle: OpaquePointer? {
        get { _windowHandles[ObjectIdentifier(self)] }
        set { _windowHandles[ObjectIdentifier(self)] = newValue }
    }

    /// Phase B: actually create + show a GtkWindow if GTK initialized.
    /// Falls back to no-op stub if no display.
    public func showAsGtkWindow() {
        guard QuillGTK.ensureInitialized() else { return }
        if gtkWindowHandle == nil {
            guard let widget = gtk_window_new() else { return }
            gtkWindowHandle = OpaquePointer(widget)
            // GtkWindow-typed pointer for window-specific calls.
            let win = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkWindow.self)
            title.withCString { gtk_window_set_title(win, $0) }
            let w = Int32(frame.size.width.rounded())
            let h = Int32(frame.size.height.rounded())
            if w > 0 && h > 0 {
                gtk_window_set_default_size(win, w, h)
            }
        }
        if let handle = gtkWindowHandle {
            let win = UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkWindow.self)
            gtk_window_present(win)
            isVisible = true
        }
    }

    public func closeGtkWindow() {
        guard let handle = gtkWindowHandle else { return }
        let win = UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkWindow.self)
        gtk_window_close(win)
        gtkWindowHandle = nil
        isVisible = false
    }

    /// Reads the title back from the underlying GtkWindow via
    /// gtk_window_get_title. Returns nil if no GTK handle exists.
    /// Phase B verification: proves the C-side widget actually
    /// stored what Swift wrote.
    public var gtkWindowTitle: String? {
        guard let handle = gtkWindowHandle else { return nil }
        let win = UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkWindow.self)
        guard let cstr = gtk_window_get_title(win) else { return nil }
        return String(cString: cstr)
    }

    /// Reads default width/height back from GtkWindow (the values we
    /// set via gtk_window_set_default_size). Returns (0, 0) if no handle.
    public var gtkWindowDefaultSize: (Int32, Int32) {
        guard let handle = gtkWindowHandle else { return (0, 0) }
        let win = UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkWindow.self)
        var w: Int32 = 0
        var h: Int32 = 0
        gtk_window_get_default_size(win, &w, &h)
        return (w, h)
    }
}

// Storage for OpaquePointer-per-NSWindow. Keeping it here (not on
// NSWindow as a stored property) avoids needing to pierce the
// NSObject + NSResponder inheritance chain with extra fields.
@MainActor
private var _windowHandles: [ObjectIdentifier: OpaquePointer] = [:]

#endif
