import CGTK
import CGTKBridge
import Foundation
import QuillFoundation
import QuillUIKit
import SignalUIRenderCore
import UIKit

@MainActor
private final class CoreSmokeViewController: UIViewController {
    override func loadView() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 568, height: 300))
        root.backgroundColor = .white

        let title = UILabel(frame: CGRect(x: 24, y: 22, width: 320, height: 26))
        title.text = "Renderer Core Smoke"
        title.font = UIFont.boldSystemFont(ofSize: 20)
        title.textColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        root.addSubview(title)

        let subtitle = UILabel(frame: CGRect(x: 24, y: 52, width: 420, height: 20))
        subtitle.text = "UILabel, fixed layout, bubbles, and separators without SignalUI."
        subtitle.font = UIFont.systemFont(ofSize: 12)
        subtitle.textColor = UIColor(red: 0.23, green: 0.23, blue: 0.26, alpha: 1)
        root.addSubview(subtitle)

        let dateShell = UIView(frame: CGRect(x: 221, y: 94, width: 126, height: 27))
        let date = UILabel(frame: CGRect(x: 12, y: 3, width: 102, height: 21))
        date.text = "20/06/2026"
        date.font = UIFont.systemFont(ofSize: 13)
        date.textColor = UIColor(red: 0.56, green: 0.56, blue: 0.60, alpha: 1)
        date.textAlignment = .center
        dateShell.addSubview(date)
        root.addSubview(dateShell)

        root.addSubview(Self.bubble(
            frame: CGRect(x: 40, y: 150, width: 440, height: 54),
            text: "Hey, can you check the Linux render pass?\nFixed labels should stay visible.",
            background: UIColor(red: 0.91, green: 0.91, blue: 0.92, alpha: 1),
            foreground: UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        ))

        root.addSubview(Self.bubble(
            frame: CGRect(x: 84, y: 222, width: 444, height: 54),
            text: "On it. This smoke target builds without libsignal.",
            background: UIColor(red: 0.02, green: 0.32, blue: 0.94, alpha: 1),
            foreground: .white
        ))

        let unread = UIView(frame: CGRect(x: 40, y: 126, width: 488, height: 20))
        unread.addSubview(Self.separator(frame: CGRect(x: 0, y: 10, width: 180, height: 1)))
        let label = UILabel(frame: CGRect(x: 188, y: 0, width: 112, height: 20))
        label.text = "New Messages"
        label.font = UIFont.boldSystemFont(ofSize: 12)
        label.textColor = UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1)
        label.textAlignment = .center
        unread.addSubview(label)
        unread.addSubview(Self.separator(frame: CGRect(x: 308, y: 10, width: 180, height: 1)))
        root.addSubview(unread)

        view = root
    }

    private static func bubble(
        frame: CGRect,
        text: String,
        background: UIColor,
        foreground: UIColor
    ) -> UIView {
        let bubble = UIView(frame: frame)
        bubble.backgroundColor = background
        bubble.layer.cornerRadius = 18

        let label = UILabel(frame: CGRect(x: 13, y: 7, width: frame.width - 26, height: frame.height - 14))
        label.text = text
        label.font = UIFont.systemFont(ofSize: 18)
        label.textColor = foreground
        label.numberOfLines = 0
        bubble.addSubview(label)
        return bubble
    }

    private static func separator(frame: CGRect) -> UIView {
        let separator = UIView(frame: frame)
        separator.backgroundColor = UIColor(red: 0.235, green: 0.235, blue: 0.263, alpha: 0.18)
        return separator
    }
}

@MainActor
private func installBaseCSS() {
    let css = """
    window { background-color: #FFFFFF; }
    * { background-color: transparent; }
    box, label, viewport, scrolledwindow, separator { background-color: transparent; }
    label { color: #1C1C1E; }
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
private func render(_ viewController: UIViewController) {
    installBaseCSS()
    viewController.view.frame = CGRect(x: 0, y: 0, width: 568, height: 300)
    viewController.view.layoutIfNeeded()

    guard let root = UIKitGtkRenderer.render(viewController.view) else {
        FileHandle.standardError.write(Data("signal-ui-render-core-smoke: root view produced no widget\n".utf8))
        return
    }

    let window = gtk_window_new()!
    let winPtr = windowPointer(window)
    "Signal UI Renderer Core Smoke".withCString { gtk_window_set_title(winPtr, $0) }
    gtk_window_set_default_size(winPtr, 568, 300)
    gtk_window_set_child(winPtr, root)
    gtk_window_present(winPtr)
}

guard gtk_init_check() != 0 else {
    FileHandle.standardError.write(Data("signal-ui-render-core-smoke: gtk_init_check failed\n".utf8))
    exit(1)
}

MainActor.assumeIsolated {
    render(CoreSmokeViewController())
}

let loop = g_main_loop_new(nil, 0)
g_main_loop_run(loop)
g_main_loop_unref(loop)
