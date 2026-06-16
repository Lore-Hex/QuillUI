// SignalUIRender · ControlMappers
// ===============================
// UIKit→GTK4 mappers for interactive controls. Today: UISwitch → GtkSwitch, so
// Signal's real toggle rows (OWSTableItem.switch, which sets `cell.accessoryView
// = UISwitch()`) render as native GTK switches reflecting the model `isOn` state.

import CGTK            // gtk_swift_switch_new / gtk_swift_switch_set_active (CGTK exposes shim.h)
import QuillUIKit
import UIKit            // UISwitch
import Foundation

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
