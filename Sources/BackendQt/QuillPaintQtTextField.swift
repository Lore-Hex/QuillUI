// QuillPaintQtTextField.swift — route SwiftUI TextField through QuillPaint on Qt.
//
// Qt analogue of QuillUIGtk/QuillGtkTextField.swift. The GTK path puts a
// non-targetable GtkDrawingArea (the painted chrome) under an interactive
// GtkEntry inside a GtkOverlay, strips the entry's own background/border via
// CSS, and drives MacTextFieldPaint from the draw callback — repainting on the
// entry's state-flags-changed / notify::has-focus / notify::sensitive signals.
//
// Here a QuillQtPaintWidget paints the field chrome (MacTextFieldPaint) UNDER an
// interactive QLineEdit. The QLineEdit is stripped flat/transparent (so it shows
// no native frame/background but keeps the editable text, caret, and selection
// it draws on top), made the only mouse target, and the chrome is made
// mouse-transparent. An event filter forwards focus/enabled/resize events to the
// chrome's update(), so the focus ring + border track the live field state.

#if canImport(CQtBridge) && QUILLUI_QT_GENERIC
import CQtBridge
import QuillPaint

/// Retained per-field box driving the paint callback. Holds the native line-edit
/// handle (to read live state). Mirrors GTK's `QuillGTKTextInputChromeBox`.
final class QuillQtTextFieldPaintBox {
    let lineEditHandle: UnsafeMutableRawPointer
    let paint = MacTextFieldPaint()

    init(lineEditHandle: UnsafeMutableRawPointer) {
        self.lineEditHandle = lineEditHandle
    }

    /// Live native-field state snapshot. Text fields only consume isFocused /
    /// isDisabled (press / hover / default don't apply to text input on macOS),
    /// matching the GTK chrome box.
    var paintState: PaintControlState {
        PaintControlState(
            isPressed: false,
            isFocused: quill_qt_widget_has_focus(lineEditHandle) != 0,
            isDisabled: quill_qt_widget_is_enabled(lineEditHandle) == 0,
            isHovered: false,
            isDefault: false
        )
    }
}

/// Build a QuillPaint-painted TextField: native QLineEdit (interactive, text
/// binding wired by the caller) composed with a QuillQtPaintWidget chrome.
/// Returns the overlay container handle to mount in the view tree.
func quillPaintQtTextField(lineEdit: OpaquePointer) -> OpaquePointer {
    quillPaintQtStripLineEditChrome(lineEdit)

    let box = QuillQtTextFieldPaintBox(lineEditHandle: qtHandle(lineEdit))
    let retained = Unmanaged.passRetained(box).toOpaque()

    let paintCallback: quill_qt_bridge_paint_callback = { painter, width, height, userData in
        guard let painter, let userData else { return }
        let box = Unmanaged<QuillQtTextFieldPaintBox>.fromOpaque(userData).takeUnretainedValue()
        let context = QtPaintContext(painterHandle: painter)
        // Inset by half a pixel so the 1px border stroke stays fully inside the
        // widget bounds instead of clipping at the edge — the same calibration
        // the GTK text-field chrome applies (x:0.5, y:0.5, width-1, height-1).
        box.paint.paint(
            into: context,
            frame: PaintRect(
                x: 0.5,
                y: 0.5,
                width: max(0, width - 1),
                height: max(0, height - 1)
            ),
            state: box.paintState
        )
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QuillQtTextFieldPaintBox>.fromOpaque(userData).release()
    }

    let chrome = qtOpaque(quill_qt_paint_widget_create(paintCallback, retained, destroy))
    quill_qt_paint_widget_set_mouse_transparent(qtHandle(chrome), 1)
    quill_qt_paint_widget_attach_repaint_source(qtHandle(chrome), qtHandle(lineEdit))

    let overlay = qtOpaque(
        quill_qt_make_painted_control_overlay(qtHandle(chrome), qtHandle(lineEdit))
    )
    // Give the field a regular-control height so the chrome has room to draw the
    // bezel, matching the GTK overlay's MacMetrics.TextField.regularHeight floor.
    quill_qt_bridge_widget_set_object_name(
        qtHandle(overlay),
        "quill-qt-paint-text-field"
    )
    return overlay
}

/// Flatten a QLineEdit so the painted chrome underneath is the only visible
/// bezel: transparent background, no native frame, content padded to match the
/// macOS text-field inset. The editable text / caret / selection the QLineEdit
/// draws on top stay intact. Qt analogue of `configureQuillTextFieldEntry`'s CSS.
private func quillPaintQtStripLineEditChrome(_ lineEdit: OpaquePointer) {
    let pad = Int(MacMetrics.TextField.horizontalPadding)
    let qss = """
    QLineEdit {
        background: transparent;
        border: none;
        padding: 0px \(pad)px;
        margin: 0px;
        selection-background-color: rgba(10, 132, 255, 90);
    }
    """
    quill_qt_bridge_widget_set_stylesheet(qtHandle(lineEdit), qss)
}
#endif
