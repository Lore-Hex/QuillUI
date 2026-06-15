// main.swift — UIKit→GTK renderer host + first-light demo.
// =======================================================
// Opens a GTK4 window and renders a real QuillUIKit `UIViewController`'s view
// hierarchy through `UIKitGtkRenderer`. The first-light demo uses a trivial VC
// (UIStackView of UILabels) to PROVE the render pipeline end-to-end (UIView tree
// → GtkWidget → on-screen) before wiring Signal's heavier real view controllers.
//
// Run (under Xvfb): see scripts/quill-signal-screenshot.sh pattern.

import CGTK
import CGTKBridge
import QuillUIKit
import UIKit
import QuillFoundation
import Foundation

// MARK: - First-light demo view controller (trivial; no SignalUI dependency)

@MainActor
final class FirstLightViewController: UIViewController {
    override func loadView() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        root.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1)

        let title = UILabel(frame: .zero)
        title.text = "Signal UI — rendering on Linux"
        title.font = UIFont.systemFont(ofSize: 22)
        title.textColor = UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1)

        let subtitle = UILabel(frame: .zero)
        subtitle.text = "Real UIKit views drawn through QuillUI → GTK4"
        subtitle.font = UIFont.systemFont(ofSize: 15)
        subtitle.textColor = UIColor(red: 0.33, green: 0.33, blue: 0.36, alpha: 1)
        subtitle.numberOfLines = 0

        let card = UIView(frame: .zero)
        card.backgroundColor = .white
        card.layer.cornerRadius = 12

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 8
        stack.frame = CGRect(x: 20, y: 40, width: 350, height: 120)

        root.addSubview(stack)
        self.view = root
    }
}

// MARK: - Debug

@MainActor
func dumpViewTree(_ view: UIView, depth: Int) {
    let indent = String(repeating: "  ", count: depth)
    let f = view.frame
    var line = "\(indent)\(type(of: view)) frame=(\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width))x\(Int(f.height))) subviews=\(view.subviews.count)"
    if let label = view as? UILabel { line += " label=\"\(label.text ?? "")\"" }
    if let tv = view as? UITableView {
        let ds = tv.dataSource
        let secs = ds?.numberOfSections(in: tv) ?? -1
        line += " TABLE dataSource=\(ds == nil ? "nil" : "set") sections=\(secs)"
        if let ds, secs > 0 {
            for s in 0..<secs { line += " rows[\(s)]=\(ds.tableView(tv, numberOfRowsInSection: s))" }
        }
    }
    FileHandle.standardError.write(Data((line + "\n").utf8))
    for sub in view.subviews { dumpViewTree(sub, depth: depth + 1) }
}

// MARK: - GTK host

/// Install the global CSS baseline for the default display. The container's GTK
/// ships a dark default theme (GTK_THEME=Adwaita:light isn't guaranteed present),
/// which paints box/row nodes with a dark fill. Our provider runs at APPLICATION
/// priority (it wins even for `window`), so neutralize the theme's structural
/// fills to transparent and paint only what we want. `windowBackground` sets the
/// canvas (grouped-gray for Settings, white for a chat). The named classes are
/// applied by mappers (qcard/qcell/qsep) or via a view's accessibilityIdentifier
/// hint "qclass:NAME" (qbubble/qmsgpad/qheader/qcomposer/qfield).
@MainActor
func installBaseCSS(windowBackground: String) {
    let css = """
    window { background-color: \(windowBackground); }
    box, label, viewport, scrolledwindow, separator { background-color: transparent; }
    label { color: #1C1C1E; }
    .qcard { background-color: #FFFFFF; border-radius: 10px; }
    .qcell { background-color: transparent; padding: 11px 16px; }
    .qsep { background-color: rgba(60, 60, 67, 0.18); min-height: 1px; }
    .qbubble { padding: 7px 13px; }
    .qmsgpad { padding: 14px 16px; }
    .qheader { background-color: #FFFFFF; padding: 10px 16px; border-bottom: 1px solid rgba(60,60,67,0.15); }
    .qcomposer { background-color: #FFFFFF; padding: 10px 12px; border-top: 1px solid rgba(60,60,67,0.15); }
    .qfield { background-color: #FFFFFF; border: 1px solid rgba(60,60,67,0.30); border-radius: 18px; padding: 8px 14px; }
    """
    let provider = gtk_css_provider_new()
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

@MainActor
func renderRootViewController(_ vc: UIViewController, title: String, width: Int, height: Int,
                             windowBackground: String = "#EFEFF4") {
    installBaseCSS(windowBackground: windowBackground)

    // Force the view to load + lay out.
    vc.loadViewIfNeeded()
    vc.viewDidLoad()
    vc.view.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    vc.view.layoutIfNeeded()

    if ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DUMP"] == "1" {
        dumpViewTree(vc.view, depth: 0)
    }

    guard let rootWidget = UIKitGtkRenderer.render(vc.view) else {
        FileHandle.standardError.write(Data("signal-ui-render: root view produced no widget\n".utf8))
        return
    }

    let window = gtk_window_new()!
    let winPtr = windowPointer(window)
    title.withCString { gtk_window_set_title(winPtr, $0) }
    gtk_window_set_default_size(winPtr, gint(width), gint(height))
    gtk_window_set_child(winPtr, rootWidget)
    gtk_window_present(winPtr)
}

// MARK: - Entry

guard gtk_init_check() != 0 else {
    FileHandle.standardError.write(Data("signal-ui-render: gtk_init_check failed (no display?)\n".utf8))
    exit(1)
}

// Top-level code is nonisolated; the VC + render path are @MainActor (UIKit +
// GTK are main-thread-only). We're on the main thread here, so assume isolation.
// SIGNAL_UI_RENDER_DEMO selects the screen:
//   firstlight   → trivial pipeline proof
//   conversation → a chat styled by Signal's REAL ConversationStyle
//   (default)    → Signal's REAL OWSTableViewController2 (Settings)
MainActor.assumeIsolated {
    switch ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DEMO"] {
    case "firstlight":
        renderRootViewController(FirstLightViewController(), title: "Signal UI on Linux", width: 390, height: 600)
    case "conversation":
        renderRootViewController(SignalConversationDemo.makeConversationViewController(),
                                 title: "Signal on Linux", width: 760, height: 720,
                                 windowBackground: "#FFFFFF")
    case "privacy":
        renderRootViewController(SignalSettingsDemo.makePrivacyViewController(),
                                 title: "Signal Privacy on Linux", width: 390, height: 720)
    default:
        renderRootViewController(SignalSettingsDemo.makeSettingsViewController(),
                                 title: "Signal Settings on Linux", width: 390, height: 720)
    }
}

let loop = g_main_loop_new(nil, 0)
g_main_loop_run(loop)
g_main_loop_unref(loop)
