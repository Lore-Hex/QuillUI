#include <gtk/gtk.h>
#include <glib.h>
#include <glib-object.h>

// Swift can't call variadic C functions like g_signal_emit_by_name.
// This static-inline helper takes the no-arg form (sufficient for
// the "clicked" signal on GtkButton) and is callable from Swift.
static inline void quill_signal_emit_clicked(gpointer instance) {
    g_signal_emit_by_name(instance, "clicked");
}
