#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint
import QuillPaintCairo

private let quillTextFieldHookInstaller: Void = {
    BackendGTK4.quill_gtk_text_field_paint_hook = { entry, _ in
        setupQuillTextFieldChrome(entry: entry)
    }
}()

public func installQuillTextFieldHook() {
    _ = quillTextFieldHookInstaller
}

public func setupQuillTextFieldChrome(entry: OpaquePointer) -> OpaquePointer {
    let entryWidget = quillTextFieldGTKWidgetPointer(entry)
    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillTextFieldOverlay(overlay, entry: entryWidget, chrome: chrome)
    configureQuillTextFieldEntry(entryWidget)
    configureQuillTextFieldChromeWidget(chrome)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), entryWidget)

    let chromeBox = QuillGTKTextFieldChromeBox(entry: entryWidget, chrome: chrome)
    installQuillTextFieldDrawFunc(chrome: chrome, chromeBox: chromeBox)
    connectQuillTextFieldRedrawSignals(entry: entryWidget, chromeBox: chromeBox)

    return OpaquePointer(overlay)
}

private final class QuillGTKTextFieldChromeBox {
    let entry: UnsafeMutablePointer<GtkWidget>
    let chrome: UnsafeMutablePointer<GtkWidget>
    let paint = MacTextFieldPaint()

    init(entry: UnsafeMutablePointer<GtkWidget>, chrome: UnsafeMutablePointer<GtkWidget>) {
        self.entry = entry
        self.chrome = chrome
    }

    var paintState: PaintControlState {
        let flags = gtk_widget_get_state_flags(entry)
        return PaintControlState(
            isPressed: false,
            isFocused: quillTextFieldGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUS_WITHIN)
                || quillTextFieldGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUSED),
            isDisabled: gtk_widget_get_sensitive(entry) == 0,
            isHovered: quillTextFieldGTKStateFlagsContain(flags, GTK_STATE_FLAG_PRELIGHT),
            isDefault: false
        )
    }

    func queueDraw() {
        gtk_widget_queue_draw(chrome)
    }
}

private func configureQuillTextFieldOverlay(
    _ overlay: UnsafeMutablePointer<GtkWidget>,
    entry: UnsafeMutablePointer<GtkWidget>,
    chrome: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_hexpand(overlay, gtk_widget_get_hexpand(entry))
    gtk_widget_set_vexpand(overlay, gtk_widget_get_vexpand(entry))
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_CENTER)
    gtk_widget_set_size_request(overlay, -1, gint(MacMetrics.TextField.regularHeight))
    gtk_widget_set_can_focus(overlay, 0)

    gtk_widget_set_can_target(chrome, 0)
    gtk_widget_set_can_focus(chrome, 0)
}

private func configureQuillTextFieldChromeWidget(_ chrome: UnsafeMutablePointer<GtkWidget>) {
    gtk_swift_drawing_area_set_content_width(chrome, 80)
    gtk_swift_drawing_area_set_content_height(chrome, gint(MacMetrics.TextField.regularHeight))
    gtk_widget_set_hexpand(chrome, 1)
    gtk_widget_set_vexpand(chrome, 1)
    gtk_widget_set_halign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_valign(chrome, GTK_ALIGN_FILL)
}

private func configureQuillTextFieldEntry(_ entry: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(entry, 1)
    gtk_widget_set_vexpand(entry, 1)
    gtk_widget_set_halign(entry, GTK_ALIGN_FILL)
    gtk_widget_set_valign(entry, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(entry, 1)
    gtk_widget_set_can_focus(entry, 1)

    let css = """
    entry.quill-paint-text-field,
    entry.quill-paint-text-field:hover,
    entry.quill-paint-text-field:focus,
    entry.quill-paint-text-field:disabled {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        padding: 0 \(Int(MacMetrics.TextField.horizontalPadding))px;
        min-height: 0;
        min-width: 0;
        text-shadow: none;
        color: \(quillTextFieldCSSRGBA(MacColors.controlText));
    }
    entry.quill-paint-text-field:disabled {
        color: \(quillTextFieldCSSRGBA(MacColors.disabledControlText));
    }
    entry.quill-paint-text-field placeholder {
        color: \(quillTextFieldCSSRGBA(MacColors.secondaryLabel));
    }
    """

    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(entry) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(entry, "quill-paint-text-field")
    g_object_unref(gpointer(provider))
}

private func installQuillTextFieldDrawFunc(
    chrome: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKTextFieldChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    gtk_swift_drawing_area_set_draw_func(
        chrome,
        { (_: UnsafeMutablePointer<GtkWidget>?,
           cr: OpaquePointer?,
           width: gint,
           height: gint,
           userData: gpointer?) in
            guard let cr, let userData else { return }

            let chromeBox = Unmanaged<QuillGTKTextFieldChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            chromeBox.paint.paint(
                into: CairoPaintContext(cr: cr),
                frame: PaintRect(
                    x: 0.5,
                    y: 0.5,
                    width: max(0, Double(width) - 1),
                    height: max(0, Double(height) - 1)
                ),
                state: chromeBox.paintState
            )
        },
        retainedBox,
        { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKTextFieldChromeBox>.fromOpaque(userData).release()
        }
    )
}

private func connectQuillTextFieldRedrawSignals(
    entry: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKTextFieldChromeBox
) {
    connectQuillTextFieldStateFlagsChanged(entry: entry, chromeBox: chromeBox)
    connectQuillTextFieldNotifySignal(entry: entry, signal: "notify::sensitive", chromeBox: chromeBox)
    connectQuillTextFieldNotifySignal(entry: entry, signal: "notify::has-focus", chromeBox: chromeBox)
}

private func connectQuillTextFieldStateFlagsChanged(
    entry: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKTextFieldChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(entry),
        "state-flags-changed",
        unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKTextFieldChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKTextFieldChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillTextFieldNotifySignal(
    entry: UnsafeMutablePointer<GtkWidget>,
    signal: String,
    chromeBox: QuillGTKTextFieldChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(entry),
        signal,
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKTextFieldChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKTextFieldChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func quillTextFieldGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func quillTextFieldGTKStateFlagsContain(_ flags: GtkStateFlags, _ flag: GtkStateFlags) -> Bool {
    (flags.rawValue & flag.rawValue) != 0
}

private func quillTextFieldCSSRGBA(_ color: PaintColor) -> String {
    let red = Int((color.red * 255).rounded())
    let green = Int((color.green * 255).rounded())
    let blue = Int((color.blue * 255).rounded())
    return "rgba(\(red), \(green), \(blue), \(color.alpha))"
}
#endif
