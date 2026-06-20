#include <gtk/gtk.h>
#include <glib.h>
#include <glib-object.h>

// Swift can't call variadic C functions like g_signal_emit_by_name.
// This static-inline helper takes the no-arg form (sufficient for
// the "clicked" signal on GtkButton) and is callable from Swift.
static inline void quill_signal_emit_clicked(gpointer instance) {
    if (instance == NULL || !GTK_IS_BUTTON(instance)) {
        return;
    }
    g_signal_emit_by_name(instance, "clicked");
}

static inline int quill_widget_is_button(gpointer instance) {
    if (instance == NULL) {
        return 0;
    }
    return GTK_IS_BUTTON(instance) ? 1 : 0;
}

static inline int quill_widget_has_css_class(gpointer instance, const char *class_name) {
    if (instance == NULL || class_name == NULL || !GTK_IS_WIDGET(instance)) {
        return 0;
    }
    return gtk_widget_has_css_class(GTK_WIDGET(instance), class_name) ? 1 : 0;
}

// Non-variadic typed wrapper around g_signal_connect_data. Importing both the
// SwiftOpenUI CGTK module and this filtered CGtk4 module can leave Swift with
// ambiguous overload context for the raw GLib function; this keeps call sites on
// one unambiguous C symbol.
static inline gulong quill_signal_connect_data(gpointer instance,
                                               const char *detailed_signal,
                                               GCallback c_handler,
                                               gpointer data,
                                               GClosureNotify destroy_data) {
    return g_signal_connect_data(instance,
                                 detailed_signal,
                                 c_handler,
                                 data,
                                 destroy_data,
                                 (GConnectFlags)0);
}

// GtkEditable is a GObject interface; Swift's typed-pointer handling
// can't bind to interface types directly. These helpers accept a
// gpointer to any GtkEditable-conforming widget (GtkEntry, GtkText,
// GtkSpinButton, GtkSearchEntry, etc.).
static inline int quill_widget_is_editable(gpointer instance) {
    if (instance == NULL) {
        return 0;
    }
    return GTK_IS_EDITABLE(instance) ? 1 : 0;
}
static inline const char *quill_editable_get_text(gpointer instance) {
    if (instance == NULL || !GTK_IS_EDITABLE(instance)) {
        return "";
    }
    return gtk_editable_get_text(GTK_EDITABLE(instance));
}
static inline void quill_editable_set_text(gpointer instance, const char *text) {
    if (instance == NULL || !GTK_IS_EDITABLE(instance)) {
        return;
    }
    gtk_editable_set_text(GTK_EDITABLE(instance), text);
}
static inline void quill_entry_set_placeholder_text(gpointer instance, const char *text) {
    if (instance == NULL || !GTK_IS_ENTRY(instance)) {
        return;
    }
    gtk_entry_set_placeholder_text(GTK_ENTRY(instance), text);
}

// GtkLabel helpers, again through gpointer because not all Swift GTK imports
// expose the opaque GtkLabel name.
static inline void quill_label_set_wrap(gpointer label, int wrap) {
    gtk_label_set_wrap(GTK_LABEL(label), (gboolean)wrap);
}
static inline void quill_label_set_xalign(gpointer label, float xalign) {
    gtk_label_set_xalign(GTK_LABEL(label), xalign);
}

// GtkScrolledWindow's set_child takes a typed GtkScrolledWindow* but
// Swift's typed-pointer binding to GTK's struct hierarchy is fragile;
// this helper accepts gpointer to any widget that's a GtkScrolledWindow.
static inline void quill_scrolled_window_set_child(gpointer scrolled, gpointer child) {
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled),
                                  GTK_WIDGET(child));
}

// Helper: count direct children of a GtkBox / GtkWidget. Iterates
// gtk_widget_get_first_child / gtk_widget_get_next_sibling. Useful
// for tests / debugging to verify the widget tree shape.
static inline int quill_widget_child_count(gpointer parent) {
    int n = 0;
    GtkWidget *child = gtk_widget_get_first_child(GTK_WIDGET(parent));
    while (child) {
        n++;
        child = gtk_widget_get_next_sibling(child);
    }
    return n;
}

// Force a widget to recompute its size + layout. Useful when adding
// children after the parent has already been presented.
static inline void quill_widget_queue_resize(gpointer w) {
    gtk_widget_queue_resize(GTK_WIDGET(w));
}

// Cursor helper: Swift can pass the CSS/GDK cursor name chosen by the AppKit
// backend without importing GdkCursor's ownership details at the call site.
static inline void quill_widget_set_cursor_name(gpointer widget, const char *name) {
    GdkCursor *cursor = NULL;
    if (name && name[0]) {
        cursor = gdk_cursor_new_from_name(name, NULL);
    }
    gtk_widget_set_cursor(GTK_WIDGET(widget), cursor);
    if (cursor) {
        g_object_unref(cursor);
    }
}

static inline void quill_widget_clear_cursor(gpointer widget) {
    gtk_widget_set_cursor(GTK_WIDGET(widget), NULL);
}

// Window helpers for runtime shims that build lightweight modal surfaces.
static inline void quill_window_set_modal(gpointer window, int modal) {
    gtk_window_set_modal(GTK_WINDOW(window), (gboolean)modal);
}
static inline void quill_window_set_transient_for(gpointer window, gpointer parent) {
    gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(parent));
}
static inline void quill_window_set_child(gpointer window, gpointer child) {
    gtk_window_set_child(GTK_WINDOW(window), GTK_WIDGET(child));
}
static inline void quill_window_destroy(gpointer window) {
    gtk_window_destroy(GTK_WINDOW(window));
}

// GMainLoop helpers exposed as gpointer to keep Swift call sites simple.
static inline gpointer quill_main_loop_new(void) {
    return g_main_loop_new(NULL, FALSE);
}
static inline void quill_main_loop_run(gpointer loop) {
    g_main_loop_run((GMainLoop *)loop);
}
static inline void quill_main_loop_quit(gpointer loop) {
    g_main_loop_quit((GMainLoop *)loop);
}
static inline void quill_main_loop_unref(gpointer loop) {
    g_main_loop_unref((GMainLoop *)loop);
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

// Decode PNG/JPEG/etc. bytes through GTK's GdkTexture loader and install the
// resulting paintable into a GtkImage. Returns non-zero on success.
static inline int quill_gtk_image_set_from_bytes(
    gpointer image,
    const unsigned char *bytes,
    size_t count
) {
    if (!image || !bytes || count == 0) {
        return 0;
    }

    GBytes *gbytes = g_bytes_new(bytes, count);
    GError *error = NULL;
    GdkTexture *texture = gdk_texture_new_from_bytes(gbytes, &error);
    g_bytes_unref(gbytes);

    if (error) {
        g_error_free(error);
        return 0;
    }
    if (!texture) {
        return 0;
    }

    gtk_image_set_from_paintable(GTK_IMAGE(image), GDK_PAINTABLE(texture));
    g_object_unref(texture);
    return 1;
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
