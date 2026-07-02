#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint
import QuillPaintCairo

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

    let paint = MacButtonPaint()
    let chromeBox = QuillGTKPaintedChrome(
        chrome: chrome,
        frameProvider: QuillGTKPaintedChrome.fullFrame,
        stateProvider: {
            quillGTKPaintState(of: buttonWidget) { state in
                state.isDefault = isDefault
            }
        },
        render: { context, frame, state in
            paint.paint(into: context, frame: frame, state: state)
        }
    )

    chromeBox.installDrawFunc()
    chromeBox.connectStateFlagsChanged(on: buttonWidget)
    chromeBox.connectNotify("notify::sensitive", on: buttonWidget)
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
        color: \(PaintCSSColor.rgba(labelColor));
    }
    button.\(className):disabled {
        color: \(PaintCSSColor.rgba(disabledLabelColor));
    }
    button.\(className) label {
        color: inherit;
    }
    """

    quillGTKApplyCSS(css, to: button, cssClass: className)
}
#endif
