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

// Paint callback for custom NSView.draw(_:) hosts. The paint_context is an
// opaque, paintEvent-scoped QPainter wrapper; it is valid only for the call.
typedef void (*quill_appkit_qt_draw_callback)(
    void *paint_context,
    int width,
    int height,
    void *user_data
);
typedef void (*quill_appkit_qt_destroy_callback)(void *user_data);

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
// A child view (a bare QWidget with no parent yet). Returns a handle or NULL.
void *quill_appkit_qt_view_new(void);
// Reparent `child` under `parent` and show it (AppKit addSubview).
void quill_appkit_qt_view_add_subview(void *parent, void *child);
// Number of immediate child QWidgets (test verification).
int quill_appkit_qt_view_child_count(void *view);
// Absolute frame, in parent coordinates. Geometry is set by the Auto Layout
// pass (M2 slice 2); the getter is for round-trip verification.
void quill_appkit_qt_view_set_geometry(void *view, int x, int y, int width, int height);
void quill_appkit_qt_view_geometry(void *view, int *x, int *y, int *width, int *height);
// Make `view` the window's content view (reparent into the window, show).
void quill_appkit_qt_window_set_content_view(void *window, void *view);

// A custom-draw QWidget that calls back during paintEvent. This backs
// NSViewRepresentable on the generic SwiftUI→Qt graph.
void *quill_appkit_qt_custom_draw_view_new(
    quill_appkit_qt_draw_callback draw,
    void *user_data,
    quill_appkit_qt_destroy_callback destroy
);

void quill_appkit_qt_widget_detach_from_parent(void *widget);
void quill_appkit_qt_widget_update(void *widget);
void quill_appkit_qt_widget_delete(void *widget);
void quill_appkit_qt_widget_mark_external_mount(void *widget, int retained);

// --- QPainter-backed CGContext operations for custom NSView.draw(_:) hosts ---
void quill_appkit_qt_paint_save(void *paint_context);
void quill_appkit_qt_paint_restore(void *paint_context);
void quill_appkit_qt_paint_translate(void *paint_context, double x, double y);
void quill_appkit_qt_paint_scale(void *paint_context, double x, double y);
void quill_appkit_qt_paint_rotate(void *paint_context, double radians);
void quill_appkit_qt_paint_set_fill_color(void *paint_context, double r, double g, double b, double a);
void quill_appkit_qt_paint_set_stroke_color(void *paint_context, double r, double g, double b, double a);
void quill_appkit_qt_paint_set_line_width(void *paint_context, double width);
void quill_appkit_qt_paint_set_line_cap(void *paint_context, int cap);
void quill_appkit_qt_paint_set_line_join(void *paint_context, int join);
void quill_appkit_qt_paint_set_alpha(void *paint_context, double alpha);
void quill_appkit_qt_paint_fill_rect(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_stroke_rect(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_fill_ellipse(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_stroke_ellipse(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_clear_rect(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_stroke_line_segments(void *paint_context, const double *xy_pairs, int point_count);
void quill_appkit_qt_paint_begin_path(void *paint_context);
void quill_appkit_qt_paint_close_path(void *paint_context);
void quill_appkit_qt_paint_move_to(void *paint_context, double x, double y);
void quill_appkit_qt_paint_add_line_to(void *paint_context, double x, double y);
void quill_appkit_qt_paint_add_rect(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_add_ellipse(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_add_arc(
    void *paint_context,
    double center_x,
    double center_y,
    double radius,
    double start_angle,
    double end_angle,
    int clockwise
);
void quill_appkit_qt_paint_fill_path(void *paint_context);
void quill_appkit_qt_paint_stroke_path(void *paint_context);
void quill_appkit_qt_paint_clip(void *paint_context);
void quill_appkit_qt_paint_clip_rect(void *paint_context, double x, double y, double width, double height);
void quill_appkit_qt_paint_draw_bgra_image(
    void *paint_context,
    const unsigned char *pixels,
    int width,
    int height,
    int stride,
    double x,
    double y,
    double target_width,
    double target_height,
    int nearest
);

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
