import Foundation
import CGTK
import QuillPaint
import QuillUI
import BackendGTK4

#if os(Linux)
/// Sets up the QuillPaint button hook in BackendGTK4.
/// This is called automatically when QuillUIGtk is used.
private let installHook: Void = {
    BackendGTK4.quill_gtk_button_paint_hook = { button, label, isDefault in
        setupQuillButtonChrome(button: button, label: label, isDefault: isDefault)
        return true
    }
}()

/// Public entry point to ensure the hook is installed.
public func installQuillButtonHook() {
    _ = installHook
}

/// Sets up a GtkButton to use QuillPaint for its chrome.
public func setupQuillButtonChrome(button: OpaquePointer, label: OpaquePointer, isDefault: Bool) {
    let buttonPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkWidget.self)
    let labelPtr = UnsafeMutableRawPointer(label).assumingMemoryBound(to: GtkWidget.self)

    // 1. Create Overlay to stack chrome and label
    let overlay = gtk_overlay_new()!
    let overlayPtr = UnsafeMutableRawPointer(overlay).assumingMemoryBound(to: GtkOverlay.self)
    
    // GtkButton set_child
    gtk_button_set_child(UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self),
                         UnsafeMutableRawPointer(overlay).assumingMemoryBound(to: GtkWidget.self))

    // 2. Create DrawingArea for the chrome
    let chrome = gtk_drawing_area_new()!
    gtk_overlay_set_child(overlayPtr, chrome)

    // 3. Add original label as an overlay (on top of chrome)
    gtk_overlay_add_overlay(overlayPtr, labelPtr)
    gtk_widget_set_halign(labelPtr, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(labelPtr, GTK_ALIGN_CENTER)
    
    // Ensure the label doesn't intercept clicks, so the button gets them
    gtk_widget_set_can_target(labelPtr, 0)
    gtk_widget_set_can_focus(labelPtr, 0)

    // 4. Reset native button chrome via CSS so only our QuillPaint shows
    let provider = gtk_css_provider_new()
    let css = """
    button {
        background: none;
        border: none;
        box-shadow: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
    }
    """
    gtk_css_provider_load_from_data(provider, css, -1)
    let context = gtk_widget_get_style_context(buttonPtr)
    gtk_style_context_add_provider(context, OpaquePointer(provider), guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION))
    g_object_unref(OpaquePointer(provider))

    // 5. Setup QuillPaint draw callback
    let paint = MacButtonPaint()
    
    // We need to capture buttonPtr to check its state
    let buttonBox = Unmanaged.passRetained(ButtonRefBox(buttonPtr)).toOpaque()

    gtk_swift_drawing_area_set_draw_func(chrome, { (widget, cr, w, h, userData) in
        guard let cr = cr, let userData = userData else { return }
        let box = Unmanaged<ButtonRefBox>.fromOpaque(userData).takeUnretainedValue()
        let button = box.button
        
        let flags = gtk_widget_get_state_flags(button)
        
        let state = PaintControlState(
            isPressed: flags.contains(GTK_STATE_FLAG_ACTIVE),
            isFocused: flags.contains(GTK_STATE_FLAG_FOCUS_WITHIN) || flags.contains(GTK_STATE_FLAG_FOCUSED),
            isDisabled: !gtk_widget_get_sensitive(button),
            isHovered: flags.contains(GTK_STATE_FLAG_PRELIGHT),
            isDefault: isDefault
        )

        let context = CairoPaintContext(cr: cr)
        paint.paint(into: context,
                    frame: PaintRect(x: 0, y: 0, width: Double(w), height: Double(h)),
                    state: state)
    }, buttonBox, { userData in
        if let userData = userData {
            Unmanaged<ButtonRefBox>.fromOpaque(userData).release()
        }
    })
    
    // Force redraw on state changes
    g_signal_connect_data(gpointer(button), "state-flags-changed", 
        unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
            guard let userData = userData else { return }
            let chromeWidget = Unmanaged<ChromeRefBox>.fromOpaque(userData).takeUnretainedValue().chrome
            gtk_widget_queue_draw(chromeWidget)
        } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
        Unmanaged.passRetained(ChromeRefBox(chrome)).toOpaque(),
        { (userData, _) in 
            if let userData = userData { Unmanaged<ChromeRefBox>.fromOpaque(userData).release() }
        },
        GConnectFlags(rawValue: 0)
    )
}

private class ButtonRefBox {
    let button: UnsafeMutablePointer<GtkWidget>
    init(_ button: UnsafeMutablePointer<GtkWidget>) {
        self.button = button
    }
}

private class ChromeRefBox {
    let chrome: UnsafeMutablePointer<GtkWidget>
    init(_ chrome: UnsafeMutablePointer<GtkWidget>) {
        self.chrome = chrome
    }
}
#endif
