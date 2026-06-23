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

// Toggle callback for checkboxes. `checked` is 1 when on, 0 when off.
typedef void (*quill_qt_bridge_toggle_callback)(int checked, void *user_data);

// Text callback for line edits. `text` is a UTF-8 string valid for the call.
typedef void (*quill_qt_bridge_text_callback)(const char *text, void *user_data);

// Index callback for combo boxes. `index` is the selected item index.
typedef void (*quill_qt_bridge_index_callback)(int index, void *user_data);

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

// --- Clipboard -------------------------------------------------------------

// Write/read QApplication's process clipboard. Returns non-zero when a Qt
// clipboard is available. The returned text pointer stays valid until the next
// quill_qt_bridge_clipboard_text call.
int quill_qt_bridge_clipboard_set_text(const char *text);
const char *quill_qt_bridge_clipboard_text(void);

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

// Create a QWidget backed by a QGridLayout for ZStack-style overlays. Children
// added at the same row/column overlap, with later children raised above
// earlier ones.
QuillQtWidgetHandle quill_qt_make_overlay_container(void);

// Create a QWidget backed by a QGridLayout for LazyVGrid. Columns are stretched
// evenly by default so flexible GridItem columns share the available width.
QuillQtWidgetHandle quill_qt_make_grid_container(int column_count);

// Add `child` into `parent` (re-parents; does NOT set geometry).
void quill_qt_bridge_widget_add_child(
    QuillQtWidgetHandle parent,
    QuillQtWidgetHandle child
);

// Add `child` into an overlay container's single grid cell. Alignment values
// are: horizontal 0=leading, 1=center, 2=trailing; vertical 0=top, 1=center,
// 2=bottom.
void quill_qt_overlay_container_add_child(
    QuillQtWidgetHandle container,
    QuillQtWidgetHandle child,
    int horizontal_alignment,
    int vertical_alignment
);

// Configure horizontal/vertical cell gaps on a grid container.
void quill_qt_grid_container_set_spacing(
    QuillQtWidgetHandle container,
    int horizontal_spacing,
    int vertical_spacing
);

// Add `child` into a LazyVGrid grid container at row/column.
void quill_qt_grid_container_add_child(
    QuillQtWidgetHandle container,
    QuillQtWidgetHandle child,
    int row,
    int column
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

// Toggle text selection on every QLabel in a rendered SwiftUI subtree.
// Non-label widgets are traversed recursively.
void quill_qt_widget_set_text_selectable_recursive(
    QuillQtWidgetHandle widget,
    int selectable
);

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

// Create a thin QFrame-backed SwiftUI Divider. It defaults to QFrame::HLine
// and can be re-oriented by stack containers when needed.
QuillQtWidgetHandle quill_qt_make_divider(void);

// Return non-zero when the handle is a divider created by quill_qt_make_divider.
int quill_qt_widget_is_divider(QuillQtWidgetHandle widget);

// Configure a divider's line orientation. vertical=0 => QFrame::HLine;
// vertical!=0 => QFrame::VLine. Non-divider/null handles are ignored.
void quill_qt_divider_set_orientation(
    QuillQtWidgetHandle divider,
    int vertical
);

// Create a QProgressBar. Swift configures determinate vs indeterminate state
// separately to mirror SwiftUI's ProgressView initializers.
QuillQtWidgetHandle quill_qt_make_progress_bar(void);

// Set a QProgressBar to determinate mode with a 0.0...1.0 fraction.
void quill_qt_progress_bar_set_fraction(
    QuillQtWidgetHandle progress_bar,
    double fraction
);

// Set a QProgressBar to indeterminate/busy mode.
void quill_qt_progress_bar_set_indeterminate(QuillQtWidgetHandle progress_bar);

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

// Create a QCheckBox. Swift configures text, checked state, and signal wiring
// separately so initial setChecked() does not fire the Swift binding callback.
QuillQtWidgetHandle quill_qt_make_check_box(void);

// Set the QCheckBox text from a UTF-8 SwiftUI Toggle label.
void quill_qt_check_box_set_text(
    QuillQtWidgetHandle check_box,
    const char *text
);

// Set the QCheckBox checked state. Non-zero means checked.
void quill_qt_check_box_set_checked(
    QuillQtWidgetHandle check_box,
    int checked
);

// Connect QCheckBox::toggled(bool) to Swift. `destroy` releases `user_data`
// when the checkbox is destroyed, mirroring the button closure lifetime.
void quill_qt_check_box_connect_toggled(
    QuillQtWidgetHandle check_box,
    quill_qt_bridge_toggle_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
);

// Create a QLineEdit. Swift configures placeholder, text, and signal wiring
// separately so the initial setText() does not fire the Swift binding callback.
QuillQtWidgetHandle quill_qt_make_line_edit(void);

// Set the QLineEdit placeholder text from a UTF-8 SwiftUI TextField title.
void quill_qt_line_edit_set_placeholder_text(
    QuillQtWidgetHandle line_edit,
    const char *text
);

// Set the QLineEdit current text from a UTF-8 SwiftUI TextField binding.
void quill_qt_line_edit_set_text(
    QuillQtWidgetHandle line_edit,
    const char *text
);

// Connect QLineEdit::textChanged(QString) to Swift. `destroy` releases
// `user_data` when the line edit is destroyed.
void quill_qt_line_edit_connect_text_changed(
    QuillQtWidgetHandle line_edit,
    quill_qt_bridge_text_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
);

// Create a QComboBox. Swift configures items, current index, and signal wiring
// separately so the initial setCurrentIndex() does not fire the Swift binding
// callback.
QuillQtWidgetHandle quill_qt_make_combo_box(void);

// Add one UTF-8 item to the QComboBox.
void quill_qt_combo_box_add_item(
    QuillQtWidgetHandle combo_box,
    const char *text
);

// Set the current QComboBox index.
void quill_qt_combo_box_set_current_index(
    QuillQtWidgetHandle combo_box,
    int index
);

// Connect QComboBox::currentIndexChanged(int) to Swift. `destroy` releases
// `user_data` when the combo box is destroyed.
void quill_qt_combo_box_connect_current_index_changed(
    QuillQtWidgetHandle combo_box,
    quill_qt_bridge_index_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
);

// Create a QToolButton with an owned QMenu and popup mode configured so
// clicking the button opens the menu.
QuillQtWidgetHandle quill_qt_make_menu_button(void);

// Set the QToolButton text from a SwiftUI Menu label/title.
void quill_qt_menu_button_set_text(
    QuillQtWidgetHandle menu_button,
    const char *text
);

// Add a QAction to the button's owned QMenu. `destroy` releases `user_data`
// when the action is destroyed, mirroring the button closure lifetime.
void quill_qt_menu_button_add_action(
    QuillQtWidgetHandle menu_button,
    const char *text,
    quill_qt_bridge_click_callback callback,
    void *user_data,
    quill_qt_bridge_click_callback destroy
);

// Add a visual separator to the owned QMenu.
void quill_qt_menu_button_add_separator(QuillQtWidgetHandle menu_button);

// Ensure clicks display the owned QMenu immediately.
void quill_qt_menu_button_show_as_popup(QuillQtWidgetHandle menu_button);

// Create a QListWidget-backed List container. Rows are added with
// quill_qt_bridge_list_widget_add_row_widget so SwiftUI child widgets can keep
// their native rendering while Qt provides list scrolling/chrome.
QuillQtWidgetHandle quill_qt_bridge_list_widget_create(void);

// Add a rendered SwiftUI child widget as one padded row in a QListWidget.
void quill_qt_bridge_list_widget_add_row_widget(
    QuillQtWidgetHandle list,
    QuillQtWidgetHandle child
);

// Create a QScrollArea-backed ScrollView container.
QuillQtWidgetHandle quill_qt_make_scroll_area(void);

// Install the rendered SwiftUI child as the QScrollArea's single widget.
void quill_qt_scroll_area_set_widget(
    QuillQtWidgetHandle scroll_area,
    QuillQtWidgetHandle child
);

// Configure which axes can scroll. Non-enabled axes hide their scroll bars.
void quill_qt_scroll_area_set_axis(
    QuillQtWidgetHandle scroll_area,
    int horizontal,
    int vertical
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
