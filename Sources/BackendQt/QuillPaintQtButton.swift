// QuillPaintQtButton.swift — route SwiftUI Button through QuillPaint on Qt.
//
// This is the Qt analogue of QuillUIGtk/QuillGtkButton.swift. The GTK path puts
// a non-targetable GtkDrawingArea (the painted chrome) under the interactive
// GtkButton inside a GtkOverlay, strips the button's own background via CSS, and
// drives MacButtonPaint from the drawing area's draw callback — repainting on
// the button's state-flags-changed / notify::sensitive signals.
//
// The Qt composition mirrors that exactly:
//   * a QuillQtPaintWidget paints the macOS chrome (MacButtonPaint), sitting
//     UNDER the native QPushButton and made transparent to mouse events so it
//     never steals clicks;
//   * the native QPushButton stays fully interactive on top, but is stripped of
//     its own chrome (flat, transparent QSS) and its text is cleared — the paint
//     draws the label so the typography is the shared QuillPaint one;
//   * the two are stacked, both filling the cell, by a painted-control overlay
//     container that reports the button's size hint to the shared layout engine;
//   * an event filter on the button forwards paint-affecting events
//     (hover / press / focus / enabled) to the paint widget's update(), the Qt
//     analogue of the GTK redraw signal hookups.

#if canImport(CQtBridge) && QUILLUI_QT_GENERIC
import CQtBridge
import QuillPaint

/// Retained per-button box driving the paint callback. Holds the native button
/// handle (to read live state), the rendered label, and whether this is a
/// default (prominent) button. Mirrors GTK's `QuillGTKButtonChromeBox`.
final class QuillQtButtonPaintBox {
    let buttonHandle: UnsafeMutableRawPointer
    let label: String
    let isDefault: Bool
    let paint: MacButtonPaint

    init(buttonHandle: UnsafeMutableRawPointer, label: String, isDefault: Bool) {
        self.buttonHandle = buttonHandle
        self.label = label
        self.isDefault = isDefault
        self.paint = MacButtonPaint(label: label)
    }

    /// Read the live native-button state into a PaintControlState snapshot, the
    /// Qt analogue of GTK's gtk_widget_get_state_flags reads.
    var paintState: PaintControlState {
        PaintControlState(
            isPressed: quill_qt_abstract_button_is_down(buttonHandle) != 0,
            isFocused: quill_qt_widget_has_focus(buttonHandle) != 0,
            isDisabled: quill_qt_widget_is_enabled(buttonHandle) == 0,
            isHovered: quill_qt_widget_is_under_mouse(buttonHandle) != 0,
            isDefault: isDefault
        )
    }
}

/// Build a QuillPaint-painted Button: native QPushButton (interactive, click
/// wired by the caller) composed with a QuillQtPaintWidget chrome. Returns the
/// overlay container handle to mount in the view tree. `button` must already
/// have its click signal connected; its title is cleared here so the chrome owns
/// the label.
func quillPaintQtButton(
    button: OpaquePointer,
    label: String,
    isDefault: Bool
) -> OpaquePointer {
    // Strip the native button's own chrome: the painted layer owns the visuals.
    // The button stays interactive (clicks/focus), just visually flat and
    // transparent, so the chrome below shows through. Clearing the text keeps the
    // native widget from double-drawing the label the paint already renders.
    quillPaintQtStripButtonChrome(button)

    let box = QuillQtButtonPaintBox(
        buttonHandle: qtHandle(button),
        label: label,
        isDefault: isDefault
    )
    let retained = Unmanaged.passRetained(box).toOpaque()

    let paintCallback: quill_qt_bridge_paint_callback = { painter, width, height, userData in
        guard let painter, let userData else { return }
        let box = Unmanaged<QuillQtButtonPaintBox>.fromOpaque(userData).takeUnretainedValue()
        let context = QtPaintContext(painterHandle: painter)
        box.paint.paint(
            into: context,
            frame: PaintRect(x: 0, y: 0, width: width, height: height),
            state: box.paintState
        )
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QuillQtButtonPaintBox>.fromOpaque(userData).release()
    }

    let chrome = qtOpaque(quill_qt_paint_widget_create(paintCallback, retained, destroy))
    quill_qt_paint_widget_set_mouse_transparent(qtHandle(chrome), 1)
    quill_qt_paint_widget_attach_repaint_source(qtHandle(chrome), qtHandle(button))

    return qtOpaque(
        quill_qt_make_painted_control_overlay(qtHandle(chrome), qtHandle(button))
    )
}

/// Flatten a QPushButton to a transparent, text-less, borderless hit target so
/// the painted chrome underneath is the only visible affordance. Qt analogue of
/// `applyQuillButtonCSS` plus the label-clear (GTK keeps the label widget and
/// recolors it; here MacButtonPaint draws the label itself).
private func quillPaintQtStripButtonChrome(_ button: OpaquePointer) {
    quill_qt_button_set_title(qtHandle(button), "")
    let qss = """
    QPushButton {
        background: transparent;
        border: none;
        padding: 0px;
        margin: 0px;
        min-width: 0px;
        min-height: 0px;
        outline: none;
    }
    """
    quill_qt_bridge_widget_set_stylesheet(qtHandle(button), qss)
}
#endif
