#if os(Linux)
import BackendGTK4
import CGTK
import QuillPaint
import QuillPaintCairo

private let quillListRowHookInstaller: Void = {
    BackendGTK4.quill_gtk_list_row_paint_hook = { button, content, isSelected, drawsIdleBackground in
        setupQuillListRowChrome(
            button: button,
            content: content,
            isSelected: isSelected,
            drawsIdleBackground: drawsIdleBackground
        )
        return true
    }
}()

public func installQuillListRowHook() {
    _ = quillListRowHookInstaller
}

public func setupQuillListRowChrome(
    button: OpaquePointer,
    content: OpaquePointer,
    isSelected: Bool,
    drawsIdleBackground: Bool
) {
    let buttonWidget = quillListRowGTKWidgetPointer(button)
    let contentWidget = quillListRowGTKWidgetPointer(content)
    let buttonPointer = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillListRowButton(buttonWidget)
    configureQuillListRowOverlay(overlay, content: contentWidget)
    configureQuillListRowChromeWidget(chrome, content: contentWidget)
    configureQuillListRowContentWidget(contentWidget)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), contentWidget)
    gtk_button_set_child(buttonPointer, overlay)

    let chromeBox = QuillGTKListRowChromeBox(
        button: buttonWidget,
        chrome: chrome,
        isSelected: isSelected,
        drawsIdleBackground: drawsIdleBackground
    )
    installQuillListRowDrawFunc(chrome: chrome, chromeBox: chromeBox)
    connectQuillListRowRedrawSignals(button: buttonWidget, chromeBox: chromeBox)
}

private final class QuillGTKListRowChromeBox {
    let button: UnsafeMutablePointer<GtkWidget>
    let chrome: UnsafeMutablePointer<GtkWidget>
    let paint = MacListRowPaint()
    let isSelected: Bool
    let drawsIdleBackground: Bool

    init(
        button: UnsafeMutablePointer<GtkWidget>,
        chrome: UnsafeMutablePointer<GtkWidget>,
        isSelected: Bool,
        drawsIdleBackground: Bool
    ) {
        self.button = button
        self.chrome = chrome
        self.isSelected = isSelected
        self.drawsIdleBackground = drawsIdleBackground
    }

    var paintState: PaintControlState {
        let flags = gtk_widget_get_state_flags(button)
        return PaintControlState(
            isPressed: quillListRowGTKStateFlagsContain(flags, GTK_STATE_FLAG_ACTIVE),
            isFocused: quillListRowGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUS_WITHIN)
                || quillListRowGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUSED),
            isDisabled: gtk_widget_get_sensitive(button) == 0,
            isHovered: quillListRowGTKStateFlagsContain(flags, GTK_STATE_FLAG_PRELIGHT),
            isSelected: isSelected
        )
    }

    var shouldDrawChrome: Bool {
        drawsIdleBackground || paintState.isHovered || paintState.isSelected || paintState.isPressed
    }

    func queueDraw() {
        gtk_widget_queue_draw(chrome)
    }
}

private func installQuillListRowDrawFunc(
    chrome: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKListRowChromeBox
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

            let chromeBox = Unmanaged<QuillGTKListRowChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            guard chromeBox.shouldDrawChrome else { return }

            chromeBox.paint.paint(
                into: CairoPaintContext(cr: cr),
                frame: PaintRect(x: 0, y: 0, width: Double(width), height: Double(height)),
                state: chromeBox.paintState
            )
        },
        retainedBox,
        { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKListRowChromeBox>.fromOpaque(userData).release()
        }
    )
}

private func connectQuillListRowRedrawSignals(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKListRowChromeBox
) {
    connectQuillListRowStateFlagsChanged(button: button, chromeBox: chromeBox)
    connectQuillListRowNotifySignal(button: button, signal: "notify::sensitive", chromeBox: chromeBox)
}

private func connectQuillListRowStateFlagsChanged(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKListRowChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        "state-flags-changed",
        unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKListRowChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKListRowChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillListRowNotifySignal(
    button: UnsafeMutablePointer<GtkWidget>,
    signal: String,
    chromeBox: QuillGTKListRowChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        signal,
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKListRowChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKListRowChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func configureQuillListRowButton(_ button: UnsafeMutablePointer<GtkWidget>) {
    let css = """
    button.quill-paint-list-row,
    button.quill-paint-list-row:hover,
    button.quill-paint-list-row:active,
    button.quill-paint-list-row:focus,
    button.quill-paint-list-row:disabled {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
        text-shadow: none;
    }
    """

    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(button) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(button, "quill-paint-list-row")
    g_object_unref(gpointer(provider))
}

private func configureQuillListRowOverlay(
    _ overlay: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_hexpand(overlay, gtk_widget_get_hexpand(content))
    gtk_widget_set_vexpand(overlay, gtk_widget_get_vexpand(content))
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(overlay, 0)
    gtk_widget_set_can_focus(overlay, 0)
}

private func configureQuillListRowChromeWidget(
    _ chrome: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>
) {
    var minimumWidth: gint = 0
    var naturalWidth: gint = 0
    var minimumHeight: gint = 0
    var naturalHeight: gint = 0

    gtk_swift_widget_measure(content, GTK_ORIENTATION_HORIZONTAL, -1, &minimumWidth, &naturalWidth)
    gtk_swift_widget_measure(content, GTK_ORIENTATION_VERTICAL, -1, &minimumHeight, &naturalHeight)
    gtk_swift_drawing_area_set_content_width(chrome, max(minimumWidth, naturalWidth))
    gtk_swift_drawing_area_set_content_height(chrome, max(minimumHeight, naturalHeight))
    gtk_widget_set_hexpand(chrome, 1)
    gtk_widget_set_vexpand(chrome, 1)
    gtk_widget_set_halign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_valign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(chrome, 0)
    gtk_widget_set_can_focus(chrome, 0)
}

private func configureQuillListRowContentWidget(_ content: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(content, 1)
    gtk_widget_set_vexpand(content, 1)
    gtk_widget_set_halign(content, GTK_ALIGN_FILL)
    gtk_widget_set_valign(content, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(content, 0)
    gtk_widget_set_can_focus(content, 0)
}

private func quillListRowGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func quillListRowGTKStateFlagsContain(_ flags: GtkStateFlags, _ flag: GtkStateFlags) -> Bool {
    (flags.rawValue & flag.rawValue) != 0
}
#endif
