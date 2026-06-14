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
import UIKitShim
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
        title.font = UIFont.boldSystemFont(ofSize: 22)
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

// MARK: - GTK host

@MainActor
func renderRootViewController(_ vc: UIViewController, title: String, width: Int, height: Int) {
    // Force the view to load + lay out.
    vc.loadViewIfNeeded()
    vc.viewDidLoad()
    vc.view.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    vc.view.layoutIfNeeded()

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

renderRootViewController(FirstLightViewController(), title: "Signal UI on Linux", width: 390, height: 600)

let loop = g_main_loop_new(nil, 0)
g_main_loop_run(loop)
g_main_loop_unref(loop)
