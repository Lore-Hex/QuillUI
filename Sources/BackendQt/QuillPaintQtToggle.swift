// QuillPaintQtToggle.swift — route SwiftUI Toggle through QuillPaint on Qt.
//
// Qt analogue of QuillUIGtk/QuillGtkToggle.swift. The GTK path overlays a
// non-targetable GtkDrawingArea (the painted chrome) on the interactive native
// control (GtkSwitch or GtkCheckButton, made near-invisible), beside a separate
// label widget, and drives MacSwitchPaint / MacCheckboxPaint from the draw
// callback — repainting on the control's state/active/sensitive signals.
//
// The Qt control is always a QCheckBox (a single interactive widget that toggles
// on a click of EITHER the indicator or the label, and already lays a label out
// beside its indicator). Instead of GTK's separate-label dance we keep that one
// widget: its native indicator is sized to the Mac switch/checkbox metrics and
// blanked (so it draws no native glyph), the label is recolored to the macOS
// control text, and a QuillQtPaintWidget paints the Mac chrome over the
// indicator subrect. The QCheckBox stays the sole mouse target; the chrome is
// mouse-transparent. An event filter forwards toggle/focus/hover/enabled events
// to the chrome's update().

#if canImport(CQtBridge) && QUILLUI_QT_GENERIC
import CQtBridge
import QuillPaint

/// Retained per-toggle box driving the paint callback. Holds the native
/// check-box handle (to read live checked + control state) and whether to paint
/// the switch or checkbox chrome. Mirrors GTK's `QuillGTKToggleChromeBox`.
final class QuillQtTogglePaintBox {
    let checkBoxHandle: UnsafeMutableRawPointer
    let isSwitch: Bool

    init(checkBoxHandle: UnsafeMutableRawPointer, isSwitch: Bool) {
        self.checkBoxHandle = checkBoxHandle
        self.isSwitch = isSwitch
    }

    var isOn: Bool {
        quill_qt_abstract_button_is_checked(checkBoxHandle) != 0
    }

    var paintState: PaintControlState {
        PaintControlState(
            isPressed: quill_qt_abstract_button_is_down(checkBoxHandle) != 0,
            isFocused: quill_qt_widget_has_focus(checkBoxHandle) != 0,
            isDisabled: quill_qt_widget_is_enabled(checkBoxHandle) == 0,
            isHovered: quill_qt_widget_is_under_mouse(checkBoxHandle) != 0,
            isSelected: isOn
        )
    }

    /// The indicator subrect within the full widget cell: a fixed-size Mac
    /// switch / checkbox glyph, left-aligned and vertically centered, matching
    /// the native QCheckBox indicator that is sized to the same metrics.
    func indicatorFrame(width: Double, height: Double) -> PaintRect {
        let size = QuillQtTogglePaintBox.indicatorSize(isSwitch: isSwitch)
        return PaintRect(
            x: 0,
            y: (height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    static func indicatorSize(isSwitch: Bool) -> (width: Double, height: Double) {
        if isSwitch {
            return (MacMetrics.Switch.width, MacMetrics.Switch.height)
        }
        return (MacMetrics.Checkbox.size, MacMetrics.Checkbox.size)
    }
}

/// Build a QuillPaint-painted Toggle: native QCheckBox (interactive, binding
/// wired by the caller) composed with a QuillQtPaintWidget chrome painting the
/// Mac switch or checkbox over the indicator. Returns the overlay container.
func quillPaintQtToggle(
    checkBox: OpaquePointer,
    isSwitch: Bool
) -> OpaquePointer {
    quillPaintQtStyleToggleControl(checkBox, isSwitch: isSwitch)

    let box = QuillQtTogglePaintBox(checkBoxHandle: qtHandle(checkBox), isSwitch: isSwitch)
    let retained = Unmanaged.passRetained(box).toOpaque()

    let paintCallback: quill_qt_bridge_paint_callback = { painter, width, height, userData in
        guard let painter, let userData else { return }
        let box = Unmanaged<QuillQtTogglePaintBox>.fromOpaque(userData).takeUnretainedValue()
        let context = QtPaintContext(painterHandle: painter)
        let frame = box.indicatorFrame(width: width, height: height)
        if box.isSwitch {
            MacSwitchPaint(isOn: box.isOn).paint(
                into: context,
                frame: frame,
                state: box.paintState
            )
        } else {
            MacCheckboxPaint(value: box.isOn ? .on : .off).paint(
                into: context,
                frame: frame,
                state: box.paintState
            )
        }
    }
    let destroy: quill_qt_bridge_click_callback = { userData in
        guard let userData else { return }
        Unmanaged<QuillQtTogglePaintBox>.fromOpaque(userData).release()
    }

    let chrome = qtOpaque(quill_qt_paint_widget_create(paintCallback, retained, destroy))
    quill_qt_paint_widget_set_mouse_transparent(qtHandle(chrome), 1)
    quill_qt_paint_widget_attach_repaint_source(qtHandle(chrome), qtHandle(checkBox))

    return qtOpaque(
        quill_qt_make_painted_control_overlay(qtHandle(chrome), qtHandle(checkBox))
    )
}

/// Blank the QCheckBox's native indicator (the painted chrome draws it instead)
/// while reserving its width at the Mac metrics so the label aligns to the right
/// of the painted glyph, and recolor the label to the macOS control text. The
/// QCheckBox keeps full interactivity (toggle on indicator OR label click). Qt
/// analogue of GTK's near-invisible native control + recolored label widget.
private func quillPaintQtStyleToggleControl(_ checkBox: OpaquePointer, isSwitch: Bool) {
    let size = QuillQtTogglePaintBox.indicatorSize(isSwitch: isSwitch)
    // Spacing between the indicator and the label, matching the GTK box spacing
    // (8px for switch, 6px for checkbox).
    let spacing = isSwitch ? 8 : 6
    let qss = """
    QCheckBox {
        background: transparent;
        color: rgb(0, 0, 0);
        spacing: \(spacing)px;
        outline: none;
    }
    QCheckBox:disabled {
        color: rgba(0, 0, 0, 102);
    }
    QCheckBox::indicator {
        width: \(Int(size.width))px;
        height: \(Int(size.height))px;
        background: transparent;
        border: none;
        image: none;
    }
    """
    quill_qt_bridge_widget_set_stylesheet(qtHandle(checkBox), qss)
}
#endif
