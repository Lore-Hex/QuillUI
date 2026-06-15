#if os(Linux)
import BackendGTK4
import CGTK
import QuillPaint
import QuillPaintCairo

private let quillTextFieldHookInstaller: Void = {
    BackendGTK4.quill_gtk_text_field_paint_hook = { entry, _ in
        setupQuillTextFieldChrome(entry: entry)
    }
    BackendGTK4.quill_gtk_text_editor_paint_hook = { scrolledWindow, textView in
        setupQuillTextEditorChrome(scrolledWindow: scrolledWindow, textView: textView)
    }
}()

public func installQuillTextFieldHook() {
    _ = quillTextFieldHookInstaller
}

public func setupQuillTextFieldChrome(entry: OpaquePointer) -> OpaquePointer {
    let entryWidget = quillGTKWidgetPointer(entry)
    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillTextFieldOverlay(overlay, entry: entryWidget, chrome: chrome)
    configureQuillTextFieldEntry(entryWidget)
    configureQuillTextFieldChromeWidget(chrome)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), entryWidget)

    let chromeBox = makeQuillTextInputChrome(stateWidget: entryWidget, chrome: chrome)
    chromeBox.installDrawFunc()
    connectQuillTextInputRedrawSignals(stateWidget: entryWidget, chromeBox: chromeBox)
    let focusEntry = {
        quillTextFieldGrabEditableFocus(entryWidget)
    }
    installQuillTextInputFocusGesture(on: overlay, focus: focusEntry)
    installQuillTextInputFocusGesture(on: entryWidget, focus: focusEntry)

    return OpaquePointer(overlay)
}

public func setupQuillTextEditorChrome(scrolledWindow: OpaquePointer, textView: OpaquePointer) -> OpaquePointer {
    let scrolledWidget = quillGTKWidgetPointer(scrolledWindow)
    let textViewWidget = quillGTKWidgetPointer(textView)
    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillTextEditorOverlay(overlay, scrolledWindow: scrolledWidget, chrome: chrome)
    configureQuillTextEditorWidgets(scrolledWindow: scrolledWidget, textView: textViewWidget)
    configureQuillTextFieldChromeWidget(chrome)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), scrolledWidget)

    let chromeBox = makeQuillTextInputChrome(stateWidget: textViewWidget, chrome: chrome)
    chromeBox.installDrawFunc()
    connectQuillTextInputRedrawSignals(stateWidget: textViewWidget, chromeBox: chromeBox)
    let focusTextView = {
        quillTextFieldForceFocus(textViewWidget)
    }
    installQuillTextInputFocusGesture(on: overlay, focus: focusTextView)
    installQuillTextInputFocusGesture(on: scrolledWidget, focus: focusTextView)
    installQuillTextInputFocusGesture(on: textViewWidget, focus: focusTextView)

    return OpaquePointer(overlay)
}

/// Build the shared painted-chrome host for a text field or text editor.
///
/// Both inputs paint `MacTextFieldPaint` into a half-pixel-inset frame (so
/// the 1px border lands crisply) and never report a pressed state.
private func makeQuillTextInputChrome(
    stateWidget: UnsafeMutablePointer<GtkWidget>,
    chrome: UnsafeMutablePointer<GtkWidget>
) -> QuillGTKPaintedChrome {
    let paint = MacTextFieldPaint()
    return QuillGTKPaintedChrome(
        chrome: chrome,
        frameProvider: QuillGTKPaintedChrome.halfPixelInsetFrame,
        stateProvider: {
            quillGTKPaintState(of: stateWidget, treatActiveAsPressed: false)
        },
        render: { context, frame, state in
            paint.paint(into: context, frame: frame, state: state)
        }
    )
}

private final class QuillGTKTextInputFocusBox {
    let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
}

private final class QuillGTKTextInputFocusTarget {
    let widget: UnsafeMutablePointer<GtkWidget>

    init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
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

private func configureQuillTextEditorOverlay(
    _ overlay: UnsafeMutablePointer<GtkWidget>,
    scrolledWindow: UnsafeMutablePointer<GtkWidget>,
    chrome: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_hexpand(overlay, gtk_widget_get_hexpand(scrolledWindow))
    gtk_widget_set_vexpand(overlay, gtk_widget_get_vexpand(scrolledWindow))
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)
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
    .quill-paint-text-field,
    .quill-paint-text-field:hover,
    .quill-paint-text-field:focus,
    .quill-paint-text-field:disabled,
    .quill-paint-text-field text,
    .quill-paint-text-field text:hover,
    .quill-paint-text-field text:focus,
    .quill-paint-text-field text:disabled {
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
        color: \(PaintCSSColor.rgba(MacColors.controlText));
    }
    .quill-paint-text-field:disabled,
    .quill-paint-text-field:disabled text {
        color: \(PaintCSSColor.rgba(MacColors.disabledControlText));
    }
    .quill-paint-text-field placeholder,
    .quill-paint-text-field text placeholder {
        color: \(PaintCSSColor.rgba(MacColors.secondaryLabel));
        opacity: 1;
    }
    """

    quillGTKApplyCSS(css, to: entry, cssClass: "quill-paint-text-field")
}

private func configureQuillTextEditorWidgets(
    scrolledWindow: UnsafeMutablePointer<GtkWidget>,
    textView: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_hexpand(scrolledWindow, 1)
    gtk_widget_set_vexpand(scrolledWindow, 1)
    gtk_widget_set_halign(scrolledWindow, GTK_ALIGN_FILL)
    gtk_widget_set_valign(scrolledWindow, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(scrolledWindow, 1)

    gtk_widget_set_hexpand(textView, 1)
    gtk_widget_set_vexpand(textView, 1)
    gtk_widget_set_halign(textView, GTK_ALIGN_FILL)
    gtk_widget_set_valign(textView, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(textView, 1)
    gtk_widget_set_can_focus(textView, 1)

    let css = """
    scrolledwindow.quill-paint-text-editor,
    scrolledwindow.quill-paint-text-editor:focus,
    scrolledwindow.quill-paint-text-editor:disabled {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
    }
    textview.quill-paint-text-editor,
    textview.quill-paint-text-editor:focus,
    textview.quill-paint-text-editor:disabled,
    textview.quill-paint-text-editor text,
    textview.quill-paint-text-editor text:focus {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        padding: \(Int(MacMetrics.TextField.verticalPadding))px \(Int(MacMetrics.TextField.horizontalPadding))px;
        min-height: 0;
        min-width: 0;
        text-shadow: none;
        color: \(PaintCSSColor.rgba(MacColors.controlText));
    }
    textview.quill-paint-text-editor:disabled,
    textview.quill-paint-text-editor:disabled text {
        color: \(PaintCSSColor.rgba(MacColors.disabledControlText));
    }
    """

    quillGTKApplyCSS(css, to: scrolledWindow, cssClass: "quill-paint-text-editor")
    gtk_widget_add_css_class(textView, "quill-paint-text-editor")
}

private func connectQuillTextInputRedrawSignals(
    stateWidget: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKPaintedChrome
) {
    chromeBox.connectStateFlagsChanged(on: stateWidget)
    chromeBox.connectNotify("notify::sensitive", on: stateWidget)
    chromeBox.connectNotify("notify::has-focus", on: stateWidget)
}

private func installQuillTextInputFocusGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    focus: @escaping () -> Void
) {
    let gesture = gtk_gesture_click_new()!
    let focusBox = Unmanaged.passRetained(QuillGTKTextInputFocusBox(focus)).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKTextInputFocusBox>.fromOpaque(userData).takeUnretainedValue().closure()
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        focusBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKTextInputFocusBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, gesture)
}

private func quillTextFieldGrabEditableFocus(_ entry: UnsafeMutablePointer<GtkWidget>) {
    quillTextFieldForceFocus(entry)
    if let delegate = gtk_editable_get_delegate(OpaquePointer(entry)) {
        quillTextFieldForceFocus(quillGTKWidgetPointer(delegate))
    } else {
        quillTextFieldForceFocus(entry)
    }
}

private func quillTextFieldForceFocus(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 1)
    gtk_widget_set_can_focus(widget, 1)
    gtk_widget_set_focusable(widget, 1)
    _ = gtk_swift_root_grab_focus(widget)
    quillTextFieldScheduleRootFocus(widget)
}

private func quillTextFieldScheduleRootFocus(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    g_object_ref(gpointer(widget))
    let target = QuillGTKTextInputFocusTarget(widget: widget)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<QuillGTKTextInputFocusTarget>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(target.widget)) }
        guard gtk_swift_is_widget(target.widget) != 0 else { return 0 }
        gtk_widget_set_can_target(target.widget, 1)
        gtk_widget_set_can_focus(target.widget, 1)
        gtk_widget_set_focusable(target.widget, 1)
        _ = gtk_swift_root_grab_focus(target.widget)
        return 0
    }, Unmanaged.passRetained(target).toOpaque())
}

#endif
