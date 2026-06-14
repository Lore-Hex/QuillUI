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

        // Signal colors its primary cell labels with `Theme.primaryTextColor`,
        // which on the no-DB Linux render path doesn't resolve to a dark ink (the
        // names came out invisible). Pass an explicit near-black `textColor` so the
        // row names render legibly regardless of the Theme bootstrap.
        let ink = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)

        // Use Signal's OWN cell factories (the same ones AccountSettingsViewController
        // et al. build their rows from): `item(...)` / `disclosureItem(...)` route
        // through OWSTableItem.buildCell, which populates `cell.contentView` with a
        // real horizontal UIStackView (icon + name label + optional accessory text).
        // The renderer walks that contentView, so the rows draw. (The bare
        // `OWSTableItem(title:)` path instead sets `cell.textLabel?.text`, and the
        // Linux UITableViewCell shim's textLabel is nil — so those rows render empty.)
        let profileSection = OWSTableSection(title: nil, items: [
            OWSTableItem.item(
                name: "Jane Appleseed",
                subtitle: "+1 555-0100",
                textColor: ink,
                accessoryType: .disclosureIndicator
            ),
        ])
        let mainSection = OWSTableSection(title: "Account", items: [
            OWSTableItem.disclosureItem(withText: "Account", textColor: ink),
            OWSTableItem.disclosureItem(withText: "Linked Devices", textColor: ink),
            OWSTableItem.disclosureItem(withText: "Donate to Signal", textColor: ink),
        ])
        let prefsSection = OWSTableSection(title: "Preferences", items: [
            OWSTableItem.item(name: "Appearance", textColor: ink, accessoryText: "System", accessoryType: .disclosureIndicator),
            OWSTableItem.disclosureItem(withText: "Chats", textColor: ink),
            OWSTableItem.disclosureItem(withText: "Notifications", textColor: ink),
            OWSTableItem.disclosureItem(withText: "Privacy", textColor: ink),
            OWSTableItem.item(name: "Data Usage", textColor: ink, accessoryText: "Wi-Fi", accessoryType: .disclosureIndicator),
        ])
        contents.add(profileSection)
        contents.add(mainSection)
        contents.add(prefsSection)
        vc.contents = contents
        return vc
    }
}

private var quillRenderAppContextInstalled = false
