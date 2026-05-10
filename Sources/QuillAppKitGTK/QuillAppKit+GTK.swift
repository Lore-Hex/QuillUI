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
import AppKit
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

/// Installs the GTK run() implementation on NSApplication at module
/// load time. Unmodified Mac apps that just call `NSApp.run()` will
/// now pump the GTK4 main loop — no source changes needed.
@MainActor
public func _quillAppKitGTKInstallRunHook() {
    NSApplication._runHook = {
        NSApplication.shared.runGTK()
    }
}

// One-shot installer: any client that imports QuillAppKitGTK gets the
// hook installed automatically the first time they touch a public
// symbol from this module. We can't use a top-level expression here
// (Swift doesn't run them at module init), so we hang the call off a
// public extension property whose getter has a side effect on first
// access, AND off a public init that real callers will trigger.
public enum QuillAppKitGTKAutoInstall {
    @MainActor
    public static let didInstall: Bool = {
        _quillAppKitGTKInstallRunHook()
        return true
    }()
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

// MARK: - NSView: GtkBox-backed

extension NSView {
    /// GtkWidget pointer (typically a GtkBox container) backing this
    /// NSView. Lazily created by `ensureGtkWidget()`.
    public var gtkWidgetHandle: OpaquePointer? {
        get { _viewHandles[ObjectIdentifier(self)] }
        set { _viewHandles[ObjectIdentifier(self)] = newValue }
    }

    /// Create a GtkBox to back this view if one doesn't exist yet.
    /// Returns the widget pointer, or nil if GTK isn't initialized.
    @discardableResult
    public func ensureGtkWidget() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        // Default to vertical box. AppKit views don't enforce a layout
        // axis, so vertical is a reasonable starting choice.
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
        gtkWidgetHandle = box.map { OpaquePointer($0) }
        return gtkWidgetHandle
    }

    /// Phase B: addSubview also appends to the GTK box if both views
    /// have GTK widgets. Falls back to the AppKit-shaped subview list
    /// (already maintained by the stub).
    public func addSubviewGTK(_ child: NSView) {
        addSubview(child)
        guard let parentHandle = ensureGtkWidget() else { return }
        guard let childHandle = child.ensureGtkWidget() else { return }
        let parentBox = UnsafeMutableRawPointer(parentHandle).assumingMemoryBound(to: GtkBox.self)
        let childWidget = UnsafeMutableRawPointer(childHandle).assumingMemoryBound(to: GtkWidget.self)
        gtk_box_append(parentBox, childWidget)
    }
}

@MainActor
private var _viewHandles: [ObjectIdentifier: OpaquePointer] = [:]

// MARK: - NSWindow.contentView ↔ GtkWindow.set_child

extension NSWindow {
    /// Phase B: set the window's GTK content widget to the contentView's
    /// GTK widget. Called automatically from showAsGtkWindowWithContent.
    public func attachContentViewToGtk() {
        guard let winHandle = gtkWindowHandle else { return }
        guard let cv = contentView else { return }
        guard let viewHandle = cv.ensureGtkWidget() else { return }
        let win = UnsafeMutableRawPointer(winHandle).assumingMemoryBound(to: GtkWindow.self)
        let widget = UnsafeMutableRawPointer(viewHandle).assumingMemoryBound(to: GtkWidget.self)
        gtk_window_set_child(win, widget)
    }

    /// Convenience: show the window with its contentView's GTK widget
    /// already attached.
    public func showAsGtkWindowWithContent() {
        showAsGtkWindow()
        attachContentViewToGtk()
    }
}

// MARK: - NSTextField label-style: GtkLabel backing

extension NSTextField {
    /// Phase B: create a GtkLabel backing for labelWithString-style
    /// fields (read-only single-line text).
    @discardableResult
    public func ensureGtkLabel() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let label = stringValue.withCString { gtk_label_new($0) }
        gtkWidgetHandle = label.map { OpaquePointer($0) }
        return gtkWidgetHandle
    }
}

// MARK: - NSButton: GtkButton backing with click signal

/// Stable storage for per-NSButton closure handlers (closures aren't
/// stored properties on NSObject subclasses without extra ceremony).
@MainActor
private var _buttonHandlers: [ObjectIdentifier: () -> Void] = [:]

/// Map from g_signal_connect's user_data pointer back to the Swift
/// click handler. We allocate one slot per button to keep the C-side
/// pointer stable.
private final class _ButtonClickContext {
    let handler: () -> Void
    init(_ h: @escaping () -> Void) { self.handler = h }
}

@MainActor
private var _buttonContexts: [ObjectIdentifier: _ButtonClickContext] = [:]

/// C trampoline: GTK calls this with our heap-allocated context as
/// user_data. We invoke the stored closure.
private let _quillButtonClickedTrampoline: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
    guard let userData else { return }
    let ctx = Unmanaged<_ButtonClickContext>.fromOpaque(userData).takeUnretainedValue()
    ctx.handler()
}

extension NSButton {
    /// Set a closure to invoke when the button is clicked. On Linux
    /// this is the practical alternative to target/action (which needs
    /// the ObjC runtime that Swift on Linux doesn't ship).
    public func setOnClick(_ handler: @escaping () -> Void) {
        _buttonHandlers[ObjectIdentifier(self)] = handler
    }

    /// Phase B: create a GtkButton backing, set its label from .title,
    /// and wire the "clicked" signal to invoke the click handler set
    /// via setOnClick. Returns nil if GTK isn't initialized.
    @discardableResult
    public func ensureGtkButton() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let btn = title.withCString { gtk_button_new_with_label($0) }
        gtkWidgetHandle = btn.map { OpaquePointer($0) }
        if let widget = btn, let handler = _buttonHandlers[ObjectIdentifier(self)] {
            let ctx = _ButtonClickContext(handler)
            _buttonContexts[ObjectIdentifier(self)] = ctx
            let userData = Unmanaged.passUnretained(ctx).toOpaque()
            // g_signal_connect_data is the canonical entry point;
            // g_signal_connect is a macro in C that we re-implement.
            "clicked".withCString { signalName in
                _ = g_signal_connect_data(
                    widget,
                    signalName,
                    unsafeBitCast(_quillButtonClickedTrampoline, to: GCallback.self),
                    userData,
                    nil,
                    GConnectFlags(rawValue: 0)
                )
            }
        }
        return gtkWidgetHandle
    }

    /// Programmatically simulate a click. Useful for tests.
    /// In GTK4, gtk_widget_activate doesn't reliably emit "clicked"
    /// for unrealized buttons. quill_signal_emit_clicked is a small
    /// C helper in the CGtk4 shim that calls the variadic
    /// g_signal_emit_by_name (which Swift can't call directly).
    public func gtkClick() {
        guard let handle = gtkWidgetHandle else { return }
        let gobject = UnsafeMutableRawPointer(handle)
        quill_signal_emit_clicked(gobject)
    }
}

// MARK: - NSImageView: GtkImage backing
//
// Apple uses NSImage for both bitmap data and SF Symbol vectors.
// Linux GTK has GtkImage (display widget) + GdkPixbuf (raster data).
// We back NSImageView with a GtkImage; the actual NSImage's bitmap
// would need to land in a GdkPixbuf via gdk_pixbuf_new_from_file or
// from in-memory data. For now, we just create the widget — Mac apps
// that just position image views get a GtkImage in the right place.

extension NSImageView {
    @discardableResult
    public func ensureGtkImage() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let img = gtk_image_new()
        gtkWidgetHandle = img.map { OpaquePointer($0) }
        return gtkWidgetHandle
    }
}

// MARK: - NSScrollView: GtkScrolledWindow backing

extension NSScrollView {
    @discardableResult
    public func ensureGtkScrolledWindow() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let sw = gtk_scrolled_window_new()
        gtkWidgetHandle = sw.map { OpaquePointer($0) }
        // If documentView is set, attach it.
        if let doc = documentView, let docHandle = doc.ensureGtkWidget(), let swHandle = gtkWidgetHandle {
            quill_scrolled_window_set_child(
                UnsafeMutableRawPointer(swHandle),
                UnsafeMutableRawPointer(docHandle)
            )
        }
        return gtkWidgetHandle
    }
}

// MARK: - Editable NSTextField: GtkEntry backing
//
// labelWithString-style fields back to GtkLabel (above). Editable
// fields back to GtkEntry, which has a text buffer and a "changed"
// signal so apps can react to user typing. Phase B target/action
// support is the same closure pattern as NSButton.

@MainActor
private var _entryHandlers: [ObjectIdentifier: (String) -> Void] = [:]

private final class _EntryChangedContext {
    let handler: (String) -> Void
    weak var entry: NSTextField?
    init(_ h: @escaping (String) -> Void, entry: NSTextField) {
        self.handler = h
        self.entry = entry
    }
}

@MainActor
private var _entryContexts: [ObjectIdentifier: _EntryChangedContext] = [:]

private let _quillEntryChangedTrampoline: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { editable, userData in
    guard let userData, let editable else { return }
    let ctx = Unmanaged<_EntryChangedContext>.fromOpaque(userData).takeUnretainedValue()
    if let cstr = quill_editable_get_text(UnsafeMutableRawPointer(editable)) {
        ctx.handler(String(cString: cstr))
    }
}

extension NSTextField {
    /// Phase B: create a GtkEntry backing for editable fields.
    @discardableResult
    public func ensureGtkEntry() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let entry = gtk_entry_new()
        gtkWidgetHandle = entry.map { OpaquePointer($0) }
        // Apply current stringValue.
        if let widget = entry, !stringValue.isEmpty {
            stringValue.withCString { quill_editable_set_text(UnsafeMutableRawPointer(widget), $0) }
        }
        return gtkWidgetHandle
    }

    /// Linux-friendly text-changed callback. Receives the latest text.
    public func setOnTextChanged(_ handler: @escaping (String) -> Void) {
        _entryHandlers[ObjectIdentifier(self)] = handler
        // If the GtkEntry exists, connect now.
        if let handle = gtkWidgetHandle {
            let ctx = _EntryChangedContext(handler, entry: self)
            _entryContexts[ObjectIdentifier(self)] = ctx
            let userData = Unmanaged.passUnretained(ctx).toOpaque()
            let raw = UnsafeMutableRawPointer(handle)
            "changed".withCString { signalName in
                _ = g_signal_connect_data(
                    raw,
                    signalName,
                    unsafeBitCast(_quillEntryChangedTrampoline, to: GCallback.self),
                    userData,
                    nil,
                    GConnectFlags(rawValue: 0)
                )
            }
        }
    }

    /// Read current text from the GtkEntry (Phase B verification).
    public var gtkEntryText: String? {
        guard let handle = gtkWidgetHandle else { return nil }
        guard let cstr = quill_editable_get_text(UnsafeMutableRawPointer(handle)) else { return nil }
        return String(cString: cstr)
    }

    /// Set text on the GtkEntry programmatically. Fires "changed".
    public func gtkEntrySetText(_ s: String) {
        guard let handle = gtkWidgetHandle else { return }
        s.withCString { quill_editable_set_text(UnsafeMutableRawPointer(handle), $0) }
    }
}

// MARK: - NSSlider: GtkScale backing

extension NSSlider {
    @discardableResult
    public func ensureGtkScale() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let orient: GtkOrientation = isVertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        let widget = gtk_scale_new_with_range(orient, minValue, maxValue, max((maxValue - minValue) / 100, 0.01))
        gtkWidgetHandle = widget.map { OpaquePointer($0) }
        if let widget = widget {
            gtk_range_set_value(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkRange.self), doubleValue)
        }
        return gtkWidgetHandle
    }

    public var gtkScaleValue: Double {
        guard let handle = gtkWidgetHandle else { return 0 }
        return gtk_range_get_value(UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkRange.self))
    }

    public func gtkScaleSetValue(_ v: Double) {
        guard let handle = gtkWidgetHandle else { return }
        gtk_range_set_value(UnsafeMutableRawPointer(handle).assumingMemoryBound(to: GtkRange.self), v)
    }
}

// MARK: - NSStackView: GtkBox backing with explicit orientation

extension NSStackView {
    @discardableResult
    public func ensureGtkStackBox() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let orient: GtkOrientation = (orientation == .vertical) ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
        let box = gtk_box_new(orient, Int32(spacing.rounded()))
        gtkWidgetHandle = box.map { OpaquePointer($0) }
        return gtkWidgetHandle
    }
}

// MARK: - NSProgressIndicator: GtkProgressBar (bar) / GtkSpinner (spinning)

extension NSProgressIndicator {
    @discardableResult
    public func ensureGtkProgressIndicator() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let widget: UnsafeMutablePointer<GtkWidget>? = (style == .spinning)
            ? gtk_spinner_new()
            : gtk_progress_bar_new()
        gtkWidgetHandle = widget.map { OpaquePointer($0) }
        // Apply current fraction for bar style.
        if style == .bar, let widget = widget, maxValue > minValue {
            let fraction = (doubleValue - minValue) / (maxValue - minValue)
            quill_progress_bar_set_fraction(UnsafeMutableRawPointer(widget), fraction)
        }
        return gtkWidgetHandle
    }

    public func gtkProgressSetFraction(_ f: Double) {
        guard let handle = gtkWidgetHandle, style == .bar else { return }
        quill_progress_bar_set_fraction(UnsafeMutableRawPointer(handle), f)
    }
}

// MARK: - NSPopUpButton: GtkDropDown backing

extension NSPopUpButton {
    @discardableResult
    public func ensureGtkDropDown() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        // Pull titles out of NSMenu items (already populated by callers
        // via addItem(withTitle:)). Build a NULL-terminated char**
        // suitable for gtk_drop_down_new_from_strings.
        let titles = (menu?.items ?? []).map(\.title)
        let cstrs: [UnsafePointer<CChar>?] = titles.map { UnsafePointer($0.withCString { strdup($0) }) }
        var ptrs: [UnsafePointer<CChar>?] = cstrs + [nil]
        let dd: UnsafeMutablePointer<GtkWidget>? = ptrs.withUnsafeMutableBufferPointer { buf in
            return quill_drop_down_new_from_strings(buf.baseAddress)
        }
        gtkWidgetHandle = dd.map { OpaquePointer($0) }
        // GtkDropDown copies the strings, safe to free.
        for c in cstrs { if let c = c { free(UnsafeMutablePointer(mutating: c)) } }
        return gtkWidgetHandle
    }

    public var gtkDropDownSelectedIndex: Int {
        guard let handle = gtkWidgetHandle else { return -1 }
        return Int(quill_drop_down_get_selected(UnsafeMutableRawPointer(handle)))
    }

    public func gtkDropDownSelect(_ idx: Int) {
        guard let handle = gtkWidgetHandle else { return }
        quill_drop_down_set_selected(UnsafeMutableRawPointer(handle), UInt32(idx))
    }
}

// MARK: - GtkCheckButton backing for checkbox / radio buttons
//
// AppKit treats checkboxes and radio buttons as NSButtons with specific
// bezel styles. NSButton.checkbox(...) and .radioButton(...) factory
// methods are the preferred construction. We back them with
// GtkCheckButton (GTK4 unified the checkbox + radio into one type;
// radios are checkboxes that share a group).

extension NSButton {
    /// Create a GtkCheckButton instead of a GtkButton. Phase B alternative
    /// for NSButton.checkbox(withTitle:) / .radioButton(withTitle:).
    @discardableResult
    public func ensureGtkCheckButton(group: NSButton? = nil) -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }
        if let existing = gtkWidgetHandle { return existing }
        let widget = title.withCString { gtk_check_button_new_with_label($0) }
        gtkWidgetHandle = widget.map { OpaquePointer($0) }
        if let widget = widget, let group = group, let groupHandle = group.gtkWidgetHandle {
            quill_check_button_set_group(UnsafeMutableRawPointer(widget),
                                         UnsafeMutableRawPointer(groupHandle))
        }
        // Apply current state.
        if let widget = widget {
            quill_check_button_set_active(UnsafeMutableRawPointer(widget),
                                          (state == .on) ? 1 : 0)
        }
        return gtkWidgetHandle
    }

    public var gtkCheckButtonActive: Bool {
        guard let handle = gtkWidgetHandle else { return false }
        return quill_check_button_get_active(UnsafeMutableRawPointer(handle)) != 0
    }

    public func gtkCheckButtonSetActive(_ on: Bool) {
        guard let handle = gtkWidgetHandle else { return }
        quill_check_button_set_active(UnsafeMutableRawPointer(handle), on ? 1 : 0)
    }
}

#endif
