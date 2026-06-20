// SignalUIRender · ControlMappers
// ===============================
// UIKit→GTK4 mappers for interactive controls. Today: UISwitch → GtkSwitch, so
// Signal's real toggle rows (OWSTableItem.switch, which sets `cell.accessoryView
// = UISwitch()`) render as native GTK switches reflecting the model `isOn` state.

import CGTK            // gtk_swift_switch_new / gtk_swift_switch_set_active (CGTK exposes shim.h)
import QuillUIKit
import UIKit            // UISwitch
import Foundation

// MARK: - UIButton

@MainActor
private final class UIButtonGTKActionContext {
    weak var button: UIButton?

    init(button: UIButton) {
        self.button = button
    }

    func clicked() {
        button?.sendActions(for: [.primaryActionTriggered, .touchUpInside])
    }
}

private let uiButtonGTKClickedTrampoline: @convention(c) (gpointer?, gpointer?) -> Void = {
    _,
    userData in
    guard let userData else { return }
    let context = Unmanaged<UIButtonGTKActionContext>
        .fromOpaque(userData)
        .takeUnretainedValue()
    MainActor.assumeIsolated {
        context.clicked()
    }
}

private let releaseUIButtonGTKActionContext: @convention(c) (gpointer?, gpointer?) -> Void = {
    userData,
    _ in
    guard let userData else { return }
    Unmanaged<UIButtonGTKActionContext>.fromOpaque(userData).release()
}

@MainActor
public enum UIButtonGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        view is UIButton
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        guard let button = view as? UIButton else {
            return gtk_button_new()!
        }

        let widget = gtk_button_new()!
        gtk_widget_set_can_focus(widget, 1)
        gtk_widget_set_focusable(widget, 1)
        gtk_widget_set_sensitive(widget, (button.isEnabled && button.isUserInteractionEnabled) ? 1 : 0)
        applyButtonSize(widget, from: button)
        applyButtonStyle(widget)

        if let child = buttonContentWidget(for: button, ctx) {
            gtk_button_set_child(buttonPointer(widget), child)
        }

        let context = Unmanaged.passRetained(UIButtonGTKActionContext(button: button)).toOpaque()
        let destroyNotify = unsafeBitCast(releaseUIButtonGTKActionContext, to: GClosureNotify.self)
        let _: gulong = g_signal_connect_data(
            gpointer(widget),
            "clicked",
            unsafeBitCast(uiButtonGTKClickedTrampoline, to: GCallback.self),
            context,
            destroyNotify,
            GConnectFlags(rawValue: 0)
        )

        ctx.applyLayerStyle(widget, button)
        return widget
    }

    private static func buttonContentWidget(
        for button: UIButton,
        _ ctx: UIKitGtkRenderContext
    ) -> GtkWidgetPtr? {
        let renderedSubviews = button.subviews.compactMap { subview -> (UIView, GtkWidgetPtr)? in
            guard let widget = ctx.render(subview) else { return nil }
            return (subview, widget)
        }

        guard !renderedSubviews.isEmpty else {
            guard let title = button.currentAttributedTitle?.string ?? button.currentTitle, !title.isEmpty else {
                return nil
            }
            let label = gtk_label_new(title)!
            gtk_widget_set_halign(label, GTK_ALIGN_CENTER)
            gtk_widget_set_valign(label, GTK_ALIGN_CENTER)
            return label
        }

        let hasRealFrames = renderedSubviews.contains { view, _ in
            view.frame.width > 0 && view.frame.height > 0
        }
        if hasRealFrames {
            let fixed = gtk_fixed_new()!
            applyButtonSize(fixed, from: button)
            let fixedPtr = UnsafeMutableRawPointer(fixed).assumingMemoryBound(to: GtkFixed.self)
            for (subview, childWidget) in renderedSubviews {
                gtk_fixed_put(fixedPtr, childWidget, gdouble(subview.frame.origin.x), gdouble(subview.frame.origin.y))
                if subview.frame.width > 0, subview.frame.height > 0 {
                    gtk_widget_set_size_request(childWidget, gint(subview.frame.width), gint(subview.frame.height))
                }
            }
            return fixed
        }

        if renderedSubviews.count == 1 {
            return renderedSubviews[0].1
        }

        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_set_halign(box, GTK_ALIGN_CENTER)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)
        for (_, childWidget) in renderedSubviews {
            gtk_widget_set_halign(childWidget, GTK_ALIGN_CENTER)
            gtk_widget_set_valign(childWidget, GTK_ALIGN_CENTER)
            gtk_box_append(boxPointer(box), childWidget)
        }
        return box
    }

    private static func applyButtonSize(_ widget: GtkWidgetPtr, from button: UIButton) {
        let width = button.bounds.width > 0 ? button.bounds.width : button.frame.width
        let height = button.bounds.height > 0 ? button.bounds.height : button.frame.height
        if width > 0, height > 0 {
            gtk_widget_set_size_request(widget, gint(width), gint(height))
        }
        gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
    }

    private static func applyButtonStyle(_ widget: GtkWidgetPtr) {
        "signal-uikit-button".withCString {
            gtk_widget_add_css_class(widget, $0)
        }
        let provider = gtk_css_provider_new()
        let css = """
        .signal-uikit-button {
            background: transparent;
            border: none;
            box-shadow: none;
            outline: none;
            padding: 0;
            min-width: 0;
            min-height: 0;
        }
        .signal-uikit-button:disabled {
            opacity: 0.45;
        }
        """
        css.withCString { gtk_css_provider_load_from_string(provider, $0) }
        if let display = gdk_display_get_default() {
            gtk_style_context_add_provider_for_display(
                display,
                OpaquePointer(provider),
                guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
            )
        }
        g_object_unref(provider)
    }

    private static func buttonPointer(_ widget: GtkWidgetPtr) -> UnsafeMutablePointer<GtkButton> {
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkButton.self)
    }

    private static func boxPointer(_ widget: GtkWidgetPtr) -> UnsafeMutablePointer<GtkBox> {
        UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self)
    }
}

// MARK: - UISwitch

/// Maps a `UISwitch` to a GtkSwitch, carrying the `isOn` model state across.
@MainActor
public enum UISwitchGtkMapper: UIViewGtkMapper {

    public static func handles(_ view: UIView) -> Bool {
        view is UISwitch
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let toggle = gtk_swift_switch_new()!
        if let uiSwitch = view as? UISwitch {
            gtk_swift_switch_set_active(toggle, uiSwitch.isOn ? 1 : 0)
            gtk_widget_set_sensitive(toggle, uiSwitch.isEnabled ? 1 : 0)
        }
        // Sit at the trailing edge, vertically centered, at natural size.
        gtk_widget_set_halign(toggle, GTK_ALIGN_END)
        gtk_widget_set_valign(toggle, GTK_ALIGN_CENTER)
        return toggle
    }
}
