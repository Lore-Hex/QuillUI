import AppKit
import QuillKit
import QuillUI
import SwiftUI

typealias CheckForUpdatesMenuItem = QuillCheckForUpdatesMenuItem

enum QuillUSBLauncher {
    static func install() {
        QuillDeviceLauncher.install(
            label: "co.lorehex.quillchat.usb-launcher",
            subsystem: "co.lorehex.quillchat"
        )
    }
}
