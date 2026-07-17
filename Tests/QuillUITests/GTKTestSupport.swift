import Foundation

#if os(Linux)
import CGTK

@MainActor
func gtkTestDisplayIsAvailable() -> Bool {
    // A failed gtk_init_check can still mark GTK initialized, poisoning later headless tests.
    let environment = ProcessInfo.processInfo.environment
    let hasDisplayAddress = ["DISPLAY", "WAYLAND_DISPLAY", "BROADWAY_DISPLAY"].contains {
        environment[$0]?.isEmpty == false
    }
    guard hasDisplayAddress else { return false }

    if gtk_is_initialized() == 0, gtk_init_check() == 0 {
        return false
    }
    return gdk_display_get_default() != nil
}
#endif
