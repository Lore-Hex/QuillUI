#pragma once
// CQuillAppKitQt — extern "C" imperative Qt6-Widgets primitives that back the
// AppKit shadow's Qt runtime (QuillAppKitQt), the Qt analogue of how
// QuillAppKitGTK backs the same stubs through CGtk4.
//
// Same discipline as CQtBridge: Swift never imports Qt C++ headers. Every
// widget is an opaque void* (OpaquePointer in Swift) and every operation is a
// flat C function. The Qt C++ lives in CQuillAppKitQt.cpp, compiled with the
// Qt6Widgets include/cxx flags from the SwiftPM manifest.
//
// M1 slice 1 (issue #231): only NSApplication run loop + NSWindow. NSView,
// NSControl, NSTableView, … grow primitive-by-primitive in later slices.
//
// Threading: GUI-thread only, like CQtBridge.

#ifdef __cplusplus
extern "C" {
#endif

// Ensure a process-wide QApplication exists (honours QT_QPA_PLATFORM, e.g.
// "offscreen" for headless). Idempotent. Returns 1 if Qt is usable, else 0.
int quill_appkit_qt_app_init(void);

// Run the Qt event loop (blocks until quit). Backs NSApplication.run().
void quill_appkit_qt_app_run(void);

// Top-level window (a bare QWidget). Returns an opaque handle, or NULL if no
// QApplication exists yet.
void *quill_appkit_qt_window_new(void);
void quill_appkit_qt_window_set_title(void *window, const char *utf8);
void quill_appkit_qt_window_set_size(void *window, int width, int height);
void quill_appkit_qt_window_present(void *window);
void quill_appkit_qt_window_close(void *window);

// Read-backs — prove the C-side widget stored what Swift wrote (test
// verification, mirroring QuillAppKitGTK's gtkWindowTitle / gtkWindowDefaultSize).
// The returned string is valid until the next call on the same thread.
const char *quill_appkit_qt_window_title(void *window);
void quill_appkit_qt_window_size(void *window, int *width, int *height);

// --- NSView (M2): child QWidgets — hierarchy + absolute geometry ---
// Draw callback for custom NSView drawing hosts. The cairo_context is a
// cairo_t* surfaced as void* so Swift can import this header without exposing
// cairo headers through the public C ABI.
typedef void (*quill_appkit_qt_draw_callback)(
    void *cairo_context,
    int width,
    int height,
    void *user_data
);
typedef void (*quill_appkit_qt_destroy_callback)(void *user_data);

// A child view (a bare QWidget with no parent yet). Returns a handle or NULL.
void *quill_appkit_qt_view_new(void);
// A QWidget whose paintEvent calls `draw(cairo_t*, width, height, user_data)`.
void *quill_appkit_qt_drawing_view_new(
    quill_appkit_qt_draw_callback draw,
    void *user_data,
    quill_appkit_qt_destroy_callback destroy
);
// Reparent `child` under `parent` and show it (AppKit addSubview).
void quill_appkit_qt_view_add_subview(void *parent, void *child);
// Queue a repaint for an existing QWidget.
void quill_appkit_qt_view_update(void *view);
// Number of immediate child QWidgets (test verification).
int quill_appkit_qt_view_child_count(void *view);
// Absolute frame, in parent coordinates. Geometry is set by the Auto Layout
// pass (M2 slice 2); the getter is for round-trip verification.
void quill_appkit_qt_view_set_geometry(void *view, int x, int y, int width, int height);
void quill_appkit_qt_view_geometry(void *view, int *x, int *y, int *width, int *height);
// Make `view` the window's content view (reparent into the window, show).
void quill_appkit_qt_window_set_content_view(void *window, void *view);

// --- NSControl family (M3): controls are QWidgets, so they compose with the
// NSView hierarchy + layout above (QPushButton/QLabel derive QWidget). ---
void *quill_appkit_qt_button_new(const char *title);
void quill_appkit_qt_button_set_title(void *button, const char *title);
const char *quill_appkit_qt_button_title(void *button);

void *quill_appkit_qt_label_new(const char *text);
void quill_appkit_qt_label_set_text(void *label, const char *text);
const char *quill_appkit_qt_label_text(void *label);

// --- Render-to-PNG (visual parity) ---
// Render `window` (and its child widgets) to a PNG via QWidget::grab(). Works
// headless under QT_QPA_PLATFORM=offscreen — the foundation for comparing an
// AppKit view rendered on Qt against a macOS reference screenshot. The widget
// is resized to its stored size + laid out before grabbing. Returns 1 on
// success, 0 on failure.
int quill_appkit_qt_window_grab_png(void *window, const char *path);

#ifdef __cplusplus
}
#endif
