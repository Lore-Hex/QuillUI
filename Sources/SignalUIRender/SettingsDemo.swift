// SettingsDemo.swift — render Signal's REAL Settings-style table view controller.
// =============================================================================
// Instantiates Signal-iOS's own `OWSTableViewController2` (unmodified, from the
// SignalUI framework) with a hand-built `OWSTableContents`, and hands its view
// tree to the UIKit→GTK renderer. No SSK database / network: `Theme`'s dark-mode
// probe is short-circuited via its test hook, and a minimal app context is
// installed so any incidental `CurrentAppContext()` access doesn't trap.
//
// This is the filmable shot: Signal's actual view controller, drawing on Linux.

import SignalUI
import SignalServiceKit
import QuillUIKit
import UIKit
import QuillFoundation
import Foundation

@MainActor
enum SignalSettingsDemo {

    /// Install just enough environment that `OWSTableViewController2` can lay out
    /// without the full SSK bootstrap.
    static func bootstrapMinimalEnvironment() {
        // Theme.isDarkThemeEnabled returns isSystemDarkThemeEnabled() early when the
        // app isn't marked ready (which we never do) — so it never reaches
        // CurrentAppContext()/databaseStorage. We still install a no-DB app context
        // for any other incidental CurrentAppContext() read in the layout path.
        if !quillRenderAppContextInstalled {
            SetCurrentAppContext(QuillSmokeAppContext(), isRunningTests: false)
            quillRenderAppContextInstalled = true
        }
    }

    /// Build a Settings-shaped table: Signal's real `OWSTableContents` model.
    static func makeSettingsViewController() -> UIViewController {
        bootstrapMinimalEnvironment()

        let vc = OWSTableViewController2()
        let contents = OWSTableContents(title: "Settings")

        let profileSection = OWSTableSection(title: nil, items: [
            OWSTableItem(title: "Jane Appleseed", actionBlock: nil),
        ])
        let mainSection = OWSTableSection(title: "Account", items: [
            OWSTableItem(title: "Account", actionBlock: nil),
            OWSTableItem(title: "Linked Devices", actionBlock: nil),
            OWSTableItem(title: "Donate to Signal", actionBlock: nil),
        ])
        let prefsSection = OWSTableSection(title: "Preferences", items: [
            OWSTableItem(title: "Appearance", actionBlock: nil),
            OWSTableItem(title: "Chats", actionBlock: nil),
            OWSTableItem(title: "Notifications", actionBlock: nil),
            OWSTableItem(title: "Privacy", actionBlock: nil),
            OWSTableItem(title: "Data Usage", actionBlock: nil),
        ])
        contents.add(profileSection)
        contents.add(mainSection)
        contents.add(prefsSection)
        vc.contents = contents
        return vc
    }
}

private var quillRenderAppContextInstalled = false
