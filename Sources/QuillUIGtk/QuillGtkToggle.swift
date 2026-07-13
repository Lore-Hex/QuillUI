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
    let chromeButton = gtk_button_new()!
    let chrome = gtk_drawing_area_new()!
    quillToggleDebugLog("setup isSwitch=\(isSwitch) label='\(label)' active=\(quillToggleControlActive(controlWidget, isSwitch: isSwitch))")

    configureQuillToggleContainer(box, control: controlWidget)
    configureQuillToggleChromeButton(chromeButton, control: controlWidget, isSwitch: isSwitch)
    configureQuillToggleChromeWidget(chrome, isSwitch: isSwitch)
    configureQuillToggleNativeControl(controlWidget, isSwitch: isSwitch)
    gtk_button_set_child(quillToggleButtonPointer(chromeButton), chrome)
    installQuillToggleButtonAction(chromeButton, control: controlWidget, isSwitch: isSwitch)

    if isSwitch, !label.isEmpty {
        let labelWidget = quillToggleLabel(label)
        gtk_box_append(quillToggleBoxPointer(box), labelWidget)
        gtk_box_append(quillToggleBoxPointer(box), chromeButton)
        installQuillToggleLabelGesture(labelWidget, control: controlWidget, isSwitch: isSwitch)
    } else {
        gtk_box_append(quillToggleBoxPointer(box), chromeButton)
        if !label.isEmpty {
            let labelWidget = quillToggleLabel(label)
            gtk_box_append(quillToggleBoxPointer(box), labelWidget)
            installQuillToggleLabelGesture(labelWidget, control: controlWidget, isSwitch: isSwitch)
        }
    }

    let chromeBox = QuillGTKToggleChromeBox(
        control: controlWidget,
        chrome: chrome,
        interaction: chromeButton,
        isSwitch: isSwitch
    )
    installQuillToggleDrawFunc(chrome: chrome, chromeBox: chromeBox)
    connectQuillToggleRedrawSignals(control: controlWidget, isSwitch: isSwitch, chromeBox: chromeBox)
    connectQuillToggleButtonRedrawSignals(button: chromeButton, chromeBox: chromeBox)
    connectQuillToggleControlSensitivity(control: controlWidget, button: chromeButton, chromeBox: chromeBox)

    return OpaquePointer(box)
}

private final class QuillGTKToggleChromeBox {
    let control: UnsafeMutablePointer<GtkWidget>
    let chrome: UnsafeMutablePointer<GtkWidget>
    let interaction: UnsafeMutablePointer<GtkWidget>
    let isSwitch: Bool

    init(
        control: UnsafeMutablePointer<GtkWidget>,
        chrome: UnsafeMutablePointer<GtkWidget>,
        interaction: UnsafeMutablePointer<GtkWidget>,
        isSwitch: Bool
    ) {
        self.control = control
        self.chrome = chrome
        self.interaction = interaction
        self.isSwitch = isSwitch
    }

    var isActive: Bool {
        if isSwitch {
            return gtk_swift_switch_get_active(control) != 0
        }
        return gtk_check_button_get_active(quillToggleCheckButtonPointer(control)) != 0
    }

    var paintState: PaintControlState {
        let flags = gtk_widget_get_state_flags(interaction)
        return PaintControlState(
            isPressed: quillToggleGTKStateFlagsContain(flags, GTK_STATE_FLAG_ACTIVE),
            isFocused: quillToggleGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUS_WITHIN)
                || quillToggleGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUSED),
            isDisabled: gtk_widget_get_sensitive(interaction) == 0 || gtk_widget_get_sensitive(control) == 0,
            isHovered: quillToggleGTKStateFlagsContain(flags, GTK_STATE_FLAG_PRELIGHT),
            isSelected: isActive
        )
    }

    func queueDraw() {
        gtk_widget_queue_draw(chrome)
    }
}

private final class QuillGTKToggleActionBox {
    let closure: () -> Void
    private var lastActivation = Date.distantPast

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    func activate() {
        let now = Date()
        guard now.timeIntervalSince(lastActivation) > 0.15 else { return }
        lastActivation = now
        quillToggleDebugLog("action activate")
        closure()
    }
}

private final class QuillGTKToggleSensitivityBox {
    let control: UnsafeMutablePointer<GtkWidget>
    let button: UnsafeMutablePointer<GtkWidget>
    let chromeBox: QuillGTKToggleChromeBox

    init(
        control: UnsafeMutablePointer<GtkWidget>,
        button: UnsafeMutablePointer<GtkWidget>,
        chromeBox: QuillGTKToggleChromeBox
    ) {
        self.control = control
        self.button = button
        self.chromeBox = chromeBox
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

private func configureQuillToggleChromeButton(
    _ button: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let size = quillToggleControlSize(isSwitch: isSwitch)
    gtk_widget_set_size_request(button, gint(size.width), gint(size.height))
    gtk_widget_set_halign(button, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
    gtk_widget_set_can_target(button, 1)
    gtk_widget_set_can_focus(button, 1)
    gtk_widget_set_sensitive(button, gtk_widget_get_sensitive(control))
    applyQuillToggleButtonCSS(to: button, isSwitch: isSwitch)
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
    gtk_widget_set_can_target(control, 0)
    gtk_widget_set_can_focus(control, 0)
}

private func applyQuillToggleButtonCSS(to button: UnsafeMutablePointer<GtkWidget>, isSwitch: Bool) {
    let size = quillToggleControlSize(isSwitch: isSwitch)
    let css = """
    button.quill-paint-toggle-button {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        border-radius: 0;
        box-shadow: none;
        margin: 0;
        min-height: \(size.height)px;
        min-width: \(size.width)px;
        outline: none;
        padding: 0;
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
    gtk_widget_add_css_class(button, "quill-paint-toggle-button")
    g_object_unref(gpointer(provider))
}

private func quillToggleLabel(_ text: String) -> UnsafeMutablePointer<GtkWidget> {
    let label = gtk_label_new(text)!
    gtk_widget_set_halign(label, GTK_ALIGN_START)
    gtk_widget_set_valign(label, GTK_ALIGN_CENTER)

    let css = """
    label.quill-paint-toggle-label {
        color: \(quillToggleCSSRGBA(MacColors.controlText));
        font-size: 13px;
    }
    label.quill-paint-toggle-label:disabled {
        color: \(quillToggleCSSRGBA(MacColors.disabledControlText));
    }
    """
    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(label) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(label, "quill-paint-toggle-label")
    g_object_unref(gpointer(provider))
    return label
}

private func installQuillToggleDrawFunc(
    chrome: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKToggleChromeBox
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

            let chromeBox = Unmanaged<QuillGTKToggleChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            let context = CairoPaintContext(cr: cr)
            let frame = PaintRect(x: 0, y: 0, width: Double(width), height: Double(height))
            if chromeBox.isSwitch {
                MacSwitchPaint(isOn: chromeBox.isActive).paint(
                    into: context,
                    frame: frame,
                    state: chromeBox.paintState
                )
            } else {
                MacCheckboxPaint(value: chromeBox.isActive ? .on : .off).paint(
                    into: context,
                    frame: frame,
                    state: chromeBox.paintState
                )
            }
        },
        retainedBox,
        { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>.fromOpaque(userData).release()
        }
    )
}

private func connectQuillToggleRedrawSignals(
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool,
    chromeBox: QuillGTKToggleChromeBox
) {
    connectQuillToggleStateFlagsChanged(control: control, chromeBox: chromeBox)
    connectQuillToggleNotifySignal(control: control, signal: "notify::sensitive", chromeBox: chromeBox)
    if isSwitch {
        connectQuillToggleNotifySignal(control: control, signal: "notify::active", chromeBox: chromeBox)
    } else {
        connectQuillToggleToggledSignal(control: control, chromeBox: chromeBox)
    }
}

private func connectQuillToggleButtonRedrawSignals(
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKToggleChromeBox
) {
    connectQuillToggleStateFlagsChanged(control: button, chromeBox: chromeBox)
    connectQuillToggleNotifySignal(control: button, signal: "notify::sensitive", chromeBox: chromeBox)
}

private func connectQuillToggleControlSensitivity(
    control: UnsafeMutablePointer<GtkWidget>,
    button: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKToggleChromeBox
) {
    let retainedBox = Unmanaged.passRetained(QuillGTKToggleSensitivityBox(
        control: control,
        button: button,
        chromeBox: chromeBox
    )).toOpaque()
    g_signal_connect_data(
        gpointer(control),
        "notify::sensitive",
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<QuillGTKToggleSensitivityBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            gtk_widget_set_sensitive(box.button, gtk_widget_get_sensitive(box.control))
            box.chromeBox.queueDraw()
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleSensitivityBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillToggleStateFlagsChanged(
    control: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKToggleChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(control),
        "state-flags-changed",
        unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillToggleNotifySignal(
    control: UnsafeMutablePointer<GtkWidget>,
    signal: String,
    chromeBox: QuillGTKToggleChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(control),
        signal,
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func connectQuillToggleToggledSignal(
    control: UnsafeMutablePointer<GtkWidget>,
    chromeBox: QuillGTKToggleChromeBox
) {
    let retainedBox = Unmanaged.passRetained(chromeBox).toOpaque()
    g_signal_connect_data(
        gpointer(control),
        "toggled",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .queueDraw()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        retainedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleChromeBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func installQuillToggleLabelGesture(
    _ label: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    installQuillToggleActivationGesture(label, control: control, isSwitch: isSwitch)
}

private func installQuillToggleActivationGesture(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    gtk_widget_set_can_target(widget, 1)
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
    gtk_swift_add_capture_gesture(widget, gesture)
}

private func installQuillToggleButtonAction(
    _ button: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isSwitch: Bool
) {
    let actionBox = QuillGTKToggleActionBox {
        guard gtk_widget_get_sensitive(control) != 0 else { return }
        quillToggleNativeControl(control, isSwitch: isSwitch)
    }
    let clickedBox = Unmanaged.passRetained(actionBox).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        "clicked",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            quillToggleDebugLog("button clicked")
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).takeUnretainedValue().activate()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        clickedBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )

    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)
    let gestureBox = Unmanaged.passRetained(actionBox).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: Double, _: Double, userData: gpointer?) in
            guard let userData else { return }
            quillToggleDebugLog("button gesture pressed")
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).takeUnretainedValue().activate()
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        gestureBox,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToggleActionBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(button, gesture)
}

private func quillToggleNativeControl(_ control: UnsafeMutablePointer<GtkWidget>, isSwitch: Bool) {
    let before = quillToggleControlActive(control, isSwitch: isSwitch)
    if isSwitch {
        gtk_swift_switch_set_active(control, before ? 0 : 1)
    } else {
        let check = quillToggleCheckButtonPointer(control)
        gtk_check_button_set_active(check, before ? 0 : 1)
    }
    quillToggleDebugLog("native toggle before=\(before) after=\(quillToggleControlActive(control, isSwitch: isSwitch))")
}

private func quillToggleControlActive(_ control: UnsafeMutablePointer<GtkWidget>, isSwitch: Bool) -> Bool {
    if isSwitch {
        return gtk_swift_switch_get_active(control) != 0
    }
    return gtk_check_button_get_active(quillToggleCheckButtonPointer(control)) != 0
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

private func quillToggleButtonPointer(
    _ ptr: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkButton> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: GtkButton.self)
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

private func quillToggleDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    FileHandle.standardError.write(Data("[QuillGtkToggle] \(message)\n".utf8))
}
#endif
