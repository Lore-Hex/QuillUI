#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint
import QuillPaintCairo

private let quillToggleHookInstaller: Void = {
    BackendGTK4.quill_gtk_toggle_paint_hook = { control, _, isSwitch, label in
        setupQuillToggleChrome(control: control, isSwitch: isSwitch, label: label)
    }
}()

public func installQuillToggleHook() {
    _ = quillToggleHookInstaller
}

public func setupQuillToggleChrome(control: OpaquePointer, isSwitch: Bool, label: String) -> OpaquePointer {
    let controlWidget = quillToggleGTKWidgetPointer(control)
    let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, isSwitch ? 8 : 6)!
    let chromeOverlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillToggleContainer(box, control: controlWidget)
    configureQuillToggleChromeOverlay(chromeOverlay, isSwitch: isSwitch)
    configureQuillToggleChromeWidget(chrome, isSwitch: isSwitch)
    configureQuillToggleNativeControl(controlWidget, isSwitch: isSwitch)

    gtk_overlay_set_child(OpaquePointer(chromeOverlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(chromeOverlay), controlWidget)

    if isSwitch, !label.isEmpty {
        let labelWidget = quillToggleLabel(label)
        gtk_box_append(quillToggleBoxPointer(box), labelWidget)
        gtk_box_append(quillToggleBoxPointer(box), chromeOverlay)
        installQuillToggleLabelGesture(labelWidget, control: controlWidget, isSwitch: isSwitch)
    } else {
        gtk_box_append(quillToggleBoxPointer(box), chromeOverlay)
        if !label.isEmpty {
            let labelWidget = quillToggleLabel(label)
            gtk_box_append(quillToggleBoxPointer(box), labelWidget)
            installQuillToggleLabelGesture(labelWidget, control: controlWidget, isSwitch: isSwitch)
        }
    }

    let chromeBox = makeQuillToggleChrome(control: controlWidget, chrome: chrome, isSwitch: isSwitch)
    chromeBox.installDrawFunc()
    chromeBox.connectStateFlagsChanged(on: controlWidget)
    chromeBox.connectNotify("notify::sensitive", on: controlWidget)
    if isSwitch {
        chromeBox.connectNotify("notify::active", on: controlWidget)
    } else {
        chromeBox.connectVoidSignal("toggled", on: controlWidget)
    }

    return OpaquePointer(box)
}

/// True if the underlying native toggle (switch or check button) is on.
private func quillToggleIsActive(_ control: UnsafeMutablePointer<GtkWidget>, isSwitch: Bool) -> Bool {
    if isSwitch {
        return gtk_swift_switch_get_active(control) != 0
    }
    return gtk_check_button_get_active(quillToggleCheckButtonPointer(control)) != 0
}

/// Build the shared painted-chrome host for a toggle. The render closure
/// picks `MacSwitchPaint` or `MacCheckboxPaint` per the live active state,
/// matching the original draw func exactly.
private func makeQuillToggleChrome(
    control: UnsafeMutablePointer<GtkWidget>,
    chrome: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) -> QuillGTKPaintedChrome {
    QuillGTKPaintedChrome(
        chrome: chrome,
        frameProvider: QuillGTKPaintedChrome.fullFrame,
        stateProvider: {
            quillGTKPaintState(of: control) { state in
                state.isSelected = quillToggleIsActive(control, isSwitch: isSwitch)
            }
        },
        render: { context, frame, state in
            let isActive = quillToggleIsActive(control, isSwitch: isSwitch)
            if isSwitch {
                MacSwitchPaint(isOn: isActive).paint(into: context, frame: frame, state: state)
            } else {
                MacCheckboxPaint(value: isActive ? .on : .off).paint(into: context, frame: frame, state: state)
            }
        }
    )
}

private final class QuillGTKToggleActionBox {
    let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
}

private func configureQuillToggleContainer(
    _ box: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>
) {
    gtk_widget_set_halign(box, GTK_ALIGN_START)
    gtk_widget_set_valign(box, GTK_ALIGN_CENTER)
    gtk_widget_set_can_focus(box, 0)
    gtk_widget_set_sensitive(box, gtk_widget_get_sensitive(control))
}

private func configureQuillToggleChromeOverlay(
    _ overlay: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let size = quillToggleControlSize(isSwitch: isSwitch)
    gtk_widget_set_size_request(overlay, gint(size.width), gint(size.height))
    gtk_widget_set_halign(overlay, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(overlay, GTK_ALIGN_CENTER)
}

private func configureQuillToggleChromeWidget(
    _ chrome: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let size = quillToggleControlSize(isSwitch: isSwitch)
    gtk_swift_drawing_area_set_content_width(chrome, gint(size.width))
    gtk_swift_drawing_area_set_content_height(chrome, gint(size.height))
    gtk_widget_set_size_request(chrome, gint(size.width), gint(size.height))
    gtk_widget_set_halign(chrome, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(chrome, GTK_ALIGN_CENTER)
    gtk_widget_set_can_target(chrome, 0)
    gtk_widget_set_can_focus(chrome, 0)
}

private func configureQuillToggleNativeControl(
    _ control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let size = quillToggleControlSize(isSwitch: isSwitch)
    gtk_widget_set_size_request(control, gint(size.width), gint(size.height))
    gtk_widget_set_halign(control, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(control, GTK_ALIGN_CENTER)
    gtk_widget_set_opacity(control, 0.001)
    gtk_widget_set_can_target(control, 1)
    gtk_widget_set_can_focus(control, 1)
}

private func quillToggleLabel(_ text: String) -> UnsafeMutablePointer<GtkWidget> {
    let label = gtk_label_new(text)!
    gtk_widget_set_halign(label, GTK_ALIGN_START)
    gtk_widget_set_valign(label, GTK_ALIGN_CENTER)

    let css = """
    label.quill-paint-toggle-label {
        color: \(PaintCSSColor.rgba(MacColors.controlText));
        font-size: 13px;
    }
    label.quill-paint-toggle-label:disabled {
        color: \(PaintCSSColor.rgba(MacColors.disabledControlText));
    }
    """
    quillGTKApplyCSS(css, to: label, cssClass: "quill-paint-toggle-label")
    return label
}

private func installQuillToggleLabelGesture(
    _ label: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let gesture = gtk_gesture_click_new()!
    let toggleBox = Unmanaged.passRetained(QuillGTKToggleActionBox {
        quillToggleNativeControl(control, isSwitch: isSwitch)
    }).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "released",
        unsafeBitCast({ (_: gpointer?, _: gint, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).takeUnretainedValue().closure()
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        toggleBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_gesture(label, gesture)
}

private func quillToggleNativeControl(_ control: UnsafeMutablePointer<GtkWidget>, isSwitch: Bool) {
    if isSwitch {
        let active = gtk_swift_switch_get_active(control) != 0
        gtk_swift_switch_set_active(control, active ? 0 : 1)
    } else {
        let check = quillToggleCheckButtonPointer(control)
        let active = gtk_check_button_get_active(check) != 0
        gtk_check_button_set_active(check, active ? 0 : 1)
    }
}

private func quillToggleControlSize(isSwitch: Bool) -> (width: Int, height: Int) {
    if isSwitch {
        return (Int(MacMetrics.Switch.width), Int(MacMetrics.Switch.height))
    }
    return (Int(MacMetrics.Checkbox.size), Int(MacMetrics.Checkbox.size))
}

private func quillToggleGTKWidgetPointer(_ ptr: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: GtkWidget.self)
}

private func quillToggleCheckButtonPointer(
    _ ptr: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkCheckButton> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: GtkCheckButton.self)
}

private func quillToggleBoxPointer(
    _ ptr: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkBox> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: GtkBox.self)
}

private func quillToggleGTKStateFlagsContain(_ flags: GtkStateFlags, _ flag: GtkStateFlags) -> Bool {
    (UInt32(flags.rawValue) & UInt32(flag.rawValue)) != 0
}

private func quillToggleCSSRGBA(_ color: PaintColor) -> String {
    let red = Int(round(max(0, min(1, color.red)) * 255))
    let green = Int(round(max(0, min(1, color.green)) * 255))
    let blue = Int(round(max(0, min(1, color.blue)) * 255))
    let alpha = max(0, min(1, color.alpha))
    return "rgba(\(red), \(green), \(blue), \(alpha))"
}
#endif
