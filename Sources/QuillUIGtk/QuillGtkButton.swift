#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint

private let quillButtonHookInstaller: Void = {
    BackendGTK4.quill_gtk_button_paint_hook = { button, label, isDefault in
        setupQuillButtonChrome(button: button, label: label, isDefault: isDefault)
        return true
    }
}()

public func installQuillButtonHook() {
    _ = quillButtonHookInstaller
}

public func setupQuillButtonChrome(button: OpaquePointer, label: OpaquePointer, isDefault: Bool) {
    let buttonWidget = quillGTKWidgetPointer(button)
    let labelWidget = quillGTKWidgetPointer(label)
    let buttonPointer = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)

    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillButtonChromeWidget(chrome, label: labelWidget)
    configureQuillButtonLabelWidget(labelWidget)
    applyQuillButtonCSS(to: buttonWidget, isDefault: isDefault)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), labelWidget)
    gtk_button_set_child(buttonPointer, overlay)

    let chromeBox = QuillGTKButtonChromeBox(
        button: buttonWidget,
        chrome: chrome,
        isDefault: isDefault
    )

    installQuillButtonDrawFunc(chrome: chrome, chromeBox: chromeBox)
    connectQuillButtonRedrawSignals(button: buttonWidget, chromeBox: chromeBox)
}

private final class QuillGTKButtonChromeBox {
    let button: UnsafeMutablePointer<GtkWidget>
    let chrome: UnsafeMutablePointer<GtkWidget>
    let paint = MacButtonPaint()
    let isDefault: Bool

    init(
        button: UnsafeMutablePointer<GtkWidget>,
        chrome: UnsafeMutablePointer<GtkWidget>,
        isDefault: Bool
    ) {
        self.button = button
        self.chrome = chrome
        self.isDefault = isDefault
    }

    var paintState: PaintControlState {
        let flags = gtk_widget_get_state_flags(button)
        return PaintControlState(
            isPressed: quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_ACTIVE),
            isFocused: quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUS_WITHIN)
                || quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUSED),
            isDisabled: gtk_widget_get_sensitive(button) == 0,
            isHovered: quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_PRELIGHT),
            isDefault: isDefault
        )
    }

    func queueDraw() {
        gtk_widget_queue_draw(chrome)
    }
}

private func installQuillButtonDrawFunc(
    chrome: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKButtonChromeBox
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

            let chromeBox = Unmanaged<QuillGTKButtonChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            let context = CairoPaintContext(cr: cr)
            chromeBox.paint.paint(
                into: context,
                frame: PaintRect(
                    x: 0,
                    y: 0,
                    width: Double(width),
                    height: Double(height)
                ),
                state: chromeBox.paintState
            )
        },
        retainedBox,
        { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKButtonChromeBox>.fromOpaque(userData).release()
        }
    )
}

private func connectQuillButtonRedrawSignals(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKButtonChromeBox
) {
    connectQuillButtonStateFlagsChanged(button: button, chromeBox: chromeBox)
    connectQuillButtonSensitiveChanged(button: button, chromeBox: chromeBox)
}

private func connectQuillButtonStateFlagsChanged(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKButtonChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        "state-flags-changed",
        unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKButtonChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKButtonChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillButtonSensitiveChanged(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKButtonChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        "notify::sensitive",
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKButtonChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKButtonChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func configureQuillButtonChromeWidget(
    _ chrome: UnsafeMutablePointer<GtkWidget>,
    label: UnsafeMutablePointer<GtkWidget>
) {
    let contentSize = quillButtonContentSize(for: label)
    gtk_swift_drawing_area_set_content_width(chrome, gint(contentSize.width))
    gtk_swift_drawing_area_set_content_height(chrome, gint(contentSize.height))
    gtk_widget_set_hexpand(chrome, 1)
    gtk_widget_set_vexpand(chrome, 1)
    gtk_widget_set_halign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_valign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(chrome, 0)
    gtk_widget_set_can_focus(chrome, 0)
}

private func configureQuillButtonLabelWidget(_ label: UnsafeMutablePointer<GtkWidget>) {
    let labelWantsHExpand = gtk_widget_get_hexpand(label) != 0
    let labelWantsVExpand = gtk_widget_get_vexpand(label) != 0

    gtk_widget_set_halign(label, labelWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)
    gtk_widget_set_valign(label, labelWantsVExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)
    gtk_widget_set_can_target(label, 0)
    gtk_widget_set_can_focus(label, 0)
}

private func quillButtonContentSize(for label: UnsafeMutablePointer<GtkWidget>) -> (width: Int, height: Int) {
    var minimumWidth: gint = 0
    var naturalWidth: gint = 0
    var minimumHeight: gint = 0
    var naturalHeight: gint = 0

    gtk_swift_widget_measure(
        label,
        GTK_ORIENTATION_HORIZONTAL,
        -1,
        &minimumWidth,
        &naturalWidth
    )
    gtk_swift_widget_measure(
        label,
        GTK_ORIENTATION_VERTICAL,
        -1,
        &minimumHeight,
        &naturalHeight
    )

    let measuredWidth = max(Int(minimumWidth), Int(naturalWidth))
    let measuredHeight = max(Int(minimumHeight), Int(naturalHeight))
    let horizontalPadding = Int(MacMetrics.Button.horizontalPadding * 2)
    let verticalPadding = Int(MacMetrics.Button.verticalPadding * 2)

    return (
        width: max(measuredWidth + horizontalPadding, horizontalPadding),
        height: max(measuredHeight + verticalPadding, Int(MacMetrics.Button.regularHeight))
    )
}

private func applyQuillButtonCSS(to button: UnsafeMutablePointer<GtkWidget>, isDefault: Bool) {
    let className = isDefault ? "quill-paint-default-button" : "quill-paint-bordered-button"
    let labelColor = isDefault ? MacColors.defaultButtonText : MacColors.controlText
    let disabledLabelColor = MacColors.disabledControlText
    let css = """
    button.\(className),
    button.\(className):hover,
    button.\(className):active,
    button.\(className):focus,
    button.\(className):disabled {
        background: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
        text-shadow: none;
        color: \(quillCSSRGBA(labelColor));
    }
    button.\(className):disabled {
        color: \(quillCSSRGBA(disabledLabelColor));
    }
    button.\(className) label {
        color: inherit;
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
    gtk_widget_add_css_class(button, className)
    g_object_unref(gpointer(provider))
}

private func quillGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func quillGTKStateFlagsContain(_ flags: GtkStateFlags, _ flag: GtkStateFlags) -> Bool {
    (flags.rawValue & flag.rawValue) != 0
}

private func quillCSSRGBA(_ color: PaintColor) -> String {
    let red = Int((color.red * 255).rounded())
    let green = Int((color.green * 255).rounded())
    let blue = Int((color.blue * 255).rounded())
    return "rgba(\(red), \(green), \(blue), \(color.alpha))"
}
#endif
