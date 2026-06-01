#pragma once

// CQtBridge — thin extern "C" wrapper over Qt6 Widgets for the GENERIC
// SwiftUI→Qt backend (`BackendQt`).
//
// This mirrors how SwiftOpenUI's BackendGTK4 talks to GTK through the
// `gtk_swift_*` helpers in CGTK/CGTKBridge: Swift never imports the Qt C++
// headers directly. Instead every widget is an opaque `void *` (surfaced to
// Swift as `OpaquePointer`) and every operation is a flat C function. The
// real Qt C++ lives in CQtBridge.cpp, which is compiled with the Qt6Widgets
// include/cxx flags supplied by the SwiftPM manifest.
//
// SCOPE (vertical slice #1): only the primitives needed to render a real
// SwiftUI tree of Text / Image / VStack / HStack / Button / Spacer / Color /
// EmptyView into a single window and run the Qt event loop. Everything here is
// deliberately minimal; the continuation plan grows it primitive-by-primitive.
//
// Threading: all functions must be called on the Qt GUI (main) thread. The
// generic backend runs the whole SwiftUI render on the main thread inside the
// QApplication, exactly like BackendGTK4 renders inside the GtkApplication
// "activate" handler.

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle types. Each maps to a QObject-derived pointer (QApplication,
// QWidget, QPushButton, QLabel). Swift treats them all as OpaquePointer.
typedef void *QuillQtAppHandle;
typedef void *QuillQtWidgetHandle;

// Click callback for buttons. `user_data` is the retained Swift box pointer.
typedef void (*quill_qt_bridge_click_callback)(void *user_data);

// Deferred (queued) callback used by QtViewHost to coalesce reactive rebuilds,
// mirroring GTK's `g_idle_add`. Posted via QTimer::singleShot(0, ...).
typedef void (*quill_qt_bridge_idle_callback)(void *user_data);

// --- Application lifecycle -------------------------------------------------

// Create the singleton QApplication. argv must stay alive for the process
// lifetime (pass CommandLine.unsafeArgv from Swift). Returns the app handle.
QuillQtAppHandle quill_qt_bridge_application_create(int argc, char **argv);

// Apply a process-wide stylesheet (QSS) to the application.
void quill_qt_bridge_application_set_stylesheet(
    QuillQtAppHandle app,
    const char *qss
);

// Run QApplication::exec(); returns its exit code. Blocks until the last
// window closes / quit() is called.
int quill_qt_bridge_application_exec(QuillQtAppHandle app);

// --- Window ----------------------------------------------------------------

// Create a top-level window (a QWidget with WA_DeleteOnClose unset). Returns
// the window handle. The window is NOT shown until quill_qt_bridge_widget_show.
QuillQtWidgetHandle quill_qt_bridge_window_create(const char *title);

// Set the window's default size. SwiftUI WindowGroup default sizing maps to
// QWidget::resize on the top-level window.
void quill_qt_bridge_window_resize(
    QuillQtWidgetHandle window,
    int width,
    int height
);

// Set a minimum window size (SwiftUI minWindowWidth/Height).
void quill_qt_bridge_window_set_minimum_size(
    QuillQtWidgetHandle window,
    int width,
    int height
);

// Install `content` as the window's single root child, filling the window.
// Re-parents content into window and gives it the window's client geometry.
void quill_qt_bridge_window_set_content(
    QuillQtWidgetHandle window,
    QuillQtWidgetHandle content
);

// --- Generic container (absolute placement) --------------------------------
//
// The generic backend mirrors GTK's "shared layout" path: it measures every
// child with the shared SwiftOpenUI layout engine (computeVStackLayout /
// computeHStackLayout) and then places each child at an absolute (x, y) with an
// explicit size inside a plain QWidget. This avoids fighting nested QBoxLayout
// intrinsic sizing and keeps the SwiftUI proposal model authoritative.

// Create a plain QWidget used as an absolute-placement container.
QuillQtWidgetHandle quill_qt_bridge_container_create(void);

// Add `child` into `parent` (re-parents; does NOT set geometry).
void quill_qt_bridge_widget_add_child(
    QuillQtWidgetHandle parent,
    QuillQtWidgetHandle child
);

// Delete (deleteLater) every direct child widget of `parent`. Used by
// QtViewHost.rebuild to tear down the previous body before re-rendering,
// mirroring GTK's gtk_box_remove loop over first-child. Deferred deletion is
// safe to call from inside a child's own signal handler (e.g. a Button click
// that mutates @State and triggers the rebuild).
void quill_qt_bridge_widget_delete_children(QuillQtWidgetHandle parent);

// Set a widget's geometry (x, y, width, height) in its parent's coordinates.
void quill_qt_bridge_widget_set_geometry(
    QuillQtWidgetHandle widget,
    int x,
    int y,
    int width,
    int height
);

// Set a widget's fixed size (used for the container's own size request).
void quill_qt_bridge_widget_set_fixed_size(
    QuillQtWidgetHandle widget,
    int width,
    int height
);

// --- Leaf widgets ----------------------------------------------------------

// Create a QLabel with the given UTF-8 text. Word-wrap is left off so the
// label reports its single-line intrinsic size to the layout engine, matching
// SwiftUI Text's default (no line limit imposed by the container).
QuillQtWidgetHandle quill_qt_bridge_label_create(const char *text);

// Register the bundled Material Symbols font for this QApplication process.
// `font_path` points at SwiftOpenUISymbols' MaterialSymbolsRounded-Regular.ttf.
void quill_qt_bridge_material_symbols_register_font(const char *font_path);

// Create a QLabel that renders Material Symbols text using the registered font
// family. `glyph` is UTF-8 text: usually a Unicode private-use codepoint
// resolved by SwiftOpenUISymbols, with ligature names allowed as a fallback.
QuillQtWidgetHandle quill_qt_bridge_material_symbol_label_create(
    const char *glyph,
    const char *font_family,
    int point_size
);

// Create a QLabel-backed image from a filesystem path. When `resizable` is
// true, QLabel scales the pixmap to whatever geometry the SwiftUI frame assigns.
QuillQtWidgetHandle quill_qt_bridge_image_create_from_file(
    const char *path,
    int resizable
);

// Create a QPushButton with the given UTF-8 title and connect its clicked()
// signal to `callback(user_data)`. `user_data` is owned by Swift (a retained
// box); `destroy` is invoked when the button is destroyed so Swift can release
// it (mirrors g_signal_connect_data's destroy notify).
QuillQtWidgetHandle quill_qt_bridge_button_create(
    const char *title,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
);

// --- Styling ---------------------------------------------------------------

// Set a widget's objectName so process-wide QSS rules (set via
// application_set_stylesheet) can target it (e.g. "#smokePanel { ... }").
void quill_qt_bridge_widget_set_object_name(
    QuillQtWidgetHandle widget,
    const char *name
);

// Set a per-widget stylesheet (QSS). Used for Color fills and inline styling.
void quill_qt_bridge_widget_set_stylesheet(
    QuillQtWidgetHandle widget,
    const char *qss
);

// Show / hide a widget. Showing the top-level window starts it displaying.
void quill_qt_bridge_widget_show(QuillQtWidgetHandle widget);
void quill_qt_bridge_widget_set_visible(QuillQtWidgetHandle widget, int visible);

// --- Measurement -----------------------------------------------------------
//
// Returns the widget's preferred (size-hint) width/height in device-
// independent pixels via out-params. This is the Qt analogue of GTK's
// gtk_widget_measure(...natural...) that the GTK backend feeds into the shared
// layout engine. For text this is QLabel::sizeHint() (font-metrics driven), so
// it satisfies the screenshot verifier's text dark-pixel thresholds.
void quill_qt_bridge_widget_size_hint(
    QuillQtWidgetHandle widget,
    int *out_width,
    int *out_height
);

// Returns a widget's RESOLVED size: the explicit size set via set_fixed_size /
// set_geometry if any, otherwise its size hint. Reliable for container widgets
// (whose sizeHint() is not meaningful) as well as leaf widgets. QtViewHost uses
// this to position the child it just built without trusting sizeHint().
void quill_qt_bridge_widget_resolved_size(
    QuillQtWidgetHandle widget,
    int *out_width,
    int *out_height
);

// --- Reactive rebuild scheduling -------------------------------------------

// Post `callback(user_data)` to run once on the next main-loop turn
// (QTimer::singleShot(0, ...)). Used by QtViewHost.scheduleRebuild to coalesce
// @State-driven rebuilds, mirroring GTK's g_idle_add. The callback runs exactly
// once; Swift owns user_data and releases it inside the callback.
void quill_qt_bridge_post_idle(
    quill_qt_bridge_idle_callback callback,
    void *user_data
);

#ifdef __cplusplus
}
#endif
