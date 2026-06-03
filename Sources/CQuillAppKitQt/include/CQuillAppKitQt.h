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

#ifdef __cplusplus
}
#endif
