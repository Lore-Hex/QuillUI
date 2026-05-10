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

// GtkDropDown new_from_strings takes a NULL-terminated char**. Safer
// to wrap in a helper that Swift can call with a pre-built array.
static inline GtkWidget *quill_drop_down_new_from_strings(const char **strings) {
    return gtk_drop_down_new_from_strings(strings);
}
static inline void quill_drop_down_set_selected(gpointer dropdown, unsigned int position) {
    gtk_drop_down_set_selected(GTK_DROP_DOWN(dropdown), position);
}
static inline unsigned int quill_drop_down_get_selected(gpointer dropdown) {
    return gtk_drop_down_get_selected(GTK_DROP_DOWN(dropdown));
}

// GtkCheckButton: active state + group membership.
static inline void quill_check_button_set_active(gpointer cb, int active) {
    gtk_check_button_set_active(GTK_CHECK_BUTTON(cb), (gboolean)active);
}
static inline int quill_check_button_get_active(gpointer cb) {
    return gtk_check_button_get_active(GTK_CHECK_BUTTON(cb)) ? 1 : 0;
}
static inline void quill_check_button_set_group(gpointer cb, gpointer group) {
    gtk_check_button_set_group(GTK_CHECK_BUTTON(cb), GTK_CHECK_BUTTON(group));
}
