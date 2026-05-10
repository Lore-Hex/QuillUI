#include <gtk/gtk.h>
#include <glib.h>
#include <glib-object.h>

// Swift can't call variadic C functions like g_signal_emit_by_name.
// This static-inline helper takes the no-arg form (sufficient for
// the "clicked" signal on GtkButton) and is callable from Swift.
static inline void quill_signal_emit_clicked(gpointer instance) {
    g_signal_emit_by_name(instance, "clicked");
}

// GtkEditable is a GObject interface; Swift's typed-pointer handling
// can't bind to interface types directly. These helpers accept a
// gpointer to any GtkEditable-conforming widget (GtkEntry, GtkText,
// GtkSpinButton, GtkSearchEntry, etc.).
static inline const char *quill_editable_get_text(gpointer instance) {
    return gtk_editable_get_text(GTK_EDITABLE(instance));
}
static inline void quill_editable_set_text(gpointer instance, const char *text) {
    gtk_editable_set_text(GTK_EDITABLE(instance), text);
}

// GtkScrolledWindow's set_child takes a typed GtkScrolledWindow* but
// Swift's typed-pointer binding to GTK's struct hierarchy is fragile;
// this helper accepts gpointer to any widget that's a GtkScrolledWindow.
static inline void quill_scrolled_window_set_child(gpointer scrolled, gpointer child) {
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled),
                                  GTK_WIDGET(child));
}

// Same gpointer pattern for GtkProgressBar.
static inline void quill_progress_bar_set_fraction(gpointer bar, double fraction) {
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(bar), fraction);
}
