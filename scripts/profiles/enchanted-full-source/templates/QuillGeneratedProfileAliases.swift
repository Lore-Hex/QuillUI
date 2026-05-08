import AppKit
import QuillKit
import SwiftUI

typealias Accessibility = QuillAccessibilityService
typealias KeyBase = QuillKeyBase
typealias HotkeyCombination = QuillHotkeyCombination
typealias CGKeyCode = UInt16
typealias FloatingPanel = QuillFloatingPanel
typealias PanelManager = QuillPanelManager
typealias QuillUpdater = QuillUpdateService
typealias CheckForUpdatesMenuItem = QuillCheckForUpdatesMenuItem
typealias QuillUSBWatcher = QuillDeviceWatcher
typealias HotkeyService = QuillHotkeyService

extension CGKeyCode {
    static let kVK_ANSI_V: CGKeyCode = 0x09
}

enum QuillUSBLauncher {
    static func install() {
        QuillDeviceLauncher.install(
            label: "co.lorehex.quillchat.usb-launcher",
            subsystem: "co.lorehex.quillchat"
        )
    }
}
