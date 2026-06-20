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
import SignalUIRenderCore
import SignalUI
#if canImport(SignalApp)
import SignalApp
#endif
#if canImport(SignalServiceKit)
import SignalServiceKit
#endif
import Foundation
import Dispatch

@MainActor
private final class DeferredSignalButtonClick {
    let rootWidget: UnsafeMutableRawPointer
    let cssClass: String
    weak var viewController: UIViewController?

    init(rootWidget: UnsafeMutableRawPointer, cssClass: String, viewController: UIViewController?) {
        self.rootWidget = rootWidget
        self.cssClass = cssClass
        self.viewController = viewController
    }

    func run() {
        logSignalInputBody(in: viewController, label: "before send click")
        let didClick = quillSignalRenderClickButton(in: rootWidget, cssClass: cssClass)
        let status = didClick ? "clicked send button" : "found no send button"
        FileHandle.standardError.write(Data("signal-ui-render: \(status)\n".utf8))
        logSignalInputBody(in: viewController, label: "after send click")
        logSignalAcceptedInteractionSummary(label: "after send click interactions")
    }
}

private let deferredSignalButtonClick: @convention(c) (gpointer?) -> gboolean = { userData in
    guard let userData else { return 0 }
    let box = Unmanaged<DeferredSignalButtonClick>.fromOpaque(userData).takeRetainedValue()
    MainActor.assumeIsolated {
        box.run()
    }
    return 0
}

@MainActor
private func logSignalInputBody(in viewController: UIViewController?, label: String) {
    guard ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_LOG_INPUT_BODY"] == "1" else { return }
    guard let rootView = viewController?.view else {
        FileHandle.standardError.write(Data("signal-ui-render: \(label) body unavailable\n".utf8))
        return
    }
    guard let textView = firstBodyRangesTextView(in: rootView) else {
        FileHandle.standardError.write(Data("signal-ui-render: \(label) body text view missing\n".utf8))
        return
    }
    let body = textView.messageBodyForSending
    FileHandle.standardError.write(Data("signal-ui-render: \(label) body=\"\(body.text)\"\n".utf8))
}

@MainActor
private func logSignalAcceptedInteractionSummary(label: String) {
    guard ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_LOG_INTERACTIONS"] == "1" else { return }
    let delayMS = UInt64(
        ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_LOG_INTERACTIONS_DELAY_MS"]
            .flatMap(UInt64.init) ?? 1200
    )
    let summaryLabel = label
    Task.detached {
        if delayMS > 0 {
            try? await Task.sleep(nanoseconds: delayMS * 1_000_000)
        }
        #if canImport(SignalApp)
        if ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE"] == "1" {
            await logSignalSendQueueDrain(label: "\(summaryLabel) send queue")
        }
        do {
            let summary = try QuillSignalRealConversationProbe.acceptedInteractionDebugSummary()
            FileHandle.standardError.write(Data("signal-ui-render: \(summaryLabel) \(summary)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("signal-ui-render: \(summaryLabel) unavailable error=\"\(error)\"\n".utf8))
        }
        #else
        FileHandle.standardError.write(Data("signal-ui-render: \(summaryLabel) unavailable SignalApp not linked\n".utf8))
        #endif
    }
}

private enum SignalRenderSendQueueDrainError: Error {
    case timedOut
}

private func logSignalSendQueueDrain(label: String) async {
    #if canImport(SignalServiceKit)
    let timeoutMS = UInt64(
        ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DRAIN_SEND_QUEUE_TIMEOUT_MS"]
            .flatMap(UInt64.init) ?? 4_000
    )
    FileHandle.standardError.write(Data("signal-ui-render: \(label) draining\n".utf8))
    do {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await ThreadUtil.enqueueSendQueue.enqueue(operation: {}).value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutMS * 1_000_000)
                throw SignalRenderSendQueueDrainError.timedOut
            }
            _ = try await group.next()
            group.cancelAll()
        }
        FileHandle.standardError.write(Data("signal-ui-render: \(label) drained\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("signal-ui-render: \(label) drain error=\"\(error)\"\n".utf8))
    }
    #else
    FileHandle.standardError.write(Data("signal-ui-render: \(label) drain unavailable SignalServiceKit not linked\n".utf8))
    #endif
}

@MainActor
private func firstBodyRangesTextView(in view: UIView) -> BodyRangesTextView? {
    if let textView = view as? BodyRangesTextView {
        return textView
    }
    for subview in view.subviews {
        if let textView = firstBodyRangesTextView(in: subview) {
            return textView
        }
    }
    return nil
}

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
    func safeFrameValue(_ value: CGFloat) -> String {
        guard value.isFinite else { return String(describing: value) }
        guard value <= CGFloat(Int.max), value >= CGFloat(Int.min) else {
            return String(format: "%.3g", Double(value))
        }
        return String(Int(value.rounded()))
    }
    var line = "\(indent)\(type(of: view)) frame=(\(safeFrameValue(f.origin.x)),\(safeFrameValue(f.origin.y)),\(safeFrameValue(f.width))x\(safeFrameValue(f.height))) subviews=\(view.subviews.count)"
    if let label = view as? UILabel { line += " label=\"\(label.text ?? "")\"" }
    if let imageView = view as? UIImageView {
        if let image = imageView.image {
            let resourceName = image.quillResourceName ?? "-"
            let systemName = image.quillSystemSymbolName ?? "-"
            let hasData = image.dataRepresentation() != nil
            line += " image(resource=\"\(resourceName)\" system=\"\(systemName)\" data=\(hasData) size=\(safeFrameValue(image.size.width))x\(safeFrameValue(image.size.height)))"
        } else {
            line += " image=nil"
        }
    }
    if let renderedText = view.quillRenderedText { line += " renderedText=\"\(renderedText)\"" }
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
    * { background-color: transparent; }
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
    .qrealcomponentstack { padding: 8px 0; }
    .qrealcvcell { background-color: transparent; }
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

    // Force the view to load + lay out. `loadViewIfNeeded()` already calls
    // `viewDidLoad()` in QuillUIKit, but it also hides the chance to size the
    // root view before first-load code runs. Size first for unloaded controllers
    // so UIKit-style layout gates see the host window dimensions.
    if vc.isViewLoaded {
        vc.view.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
    } else {
        vc.loadView()
        if vc.viewIfLoaded == nil {
            vc.view = UIView()
        }
        vc.viewIfLoaded?.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        vc.viewDidLoad()
    }
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

    if let typedText = ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_TYPE_TEXT"],
       !typedText.isEmpty {
        let didSet = quillSignalRenderSetFirstTextEntry(
            in: UnsafeMutableRawPointer(rootWidget),
            text: typedText
        )
        let status = didSet ? "updated first text entry" : "found no text entry"
        FileHandle.standardError.write(Data("signal-ui-render: \(status)\n".utf8))
        logSignalInputBody(in: vc, label: "after text entry")
    }

    if ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_CLICK_SEND"] == "1" {
        let delayMS = UInt32(
            ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_CLICK_SEND_DELAY_MS"]
                .flatMap(UInt32.init) ?? 250
        )
        let box = Unmanaged.passRetained(DeferredSignalButtonClick(
            rootWidget: UnsafeMutableRawPointer(rootWidget),
            cssClass: "signal-uikit-button-send",
            viewController: vc
        )).toOpaque()
        g_timeout_add(guint(delayMS), deferredSignalButtonClick, box)
        FileHandle.standardError.write(Data("signal-ui-render: scheduled send button click\n".utf8))
    }

    gtk_window_present(winPtr)
}

@MainActor
func runGtkMainLoopCooperatively() async {
    while true {
        while g_main_context_iteration(nil, 0) != 0 {}
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
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
//   realapp-link → proves the GTK renderer links SignalApp / ConversationViewController
//   real-components → real CVItemModel/CVRootComponent/CVCellView render path
//   ssk-bootstrap → initializes real SSK globals + on-disk SDSDatabaseStorage
//   real-conversation → seeds storage + launches real ConversationViewController
//   real-conversation-accepted → launches CVC with a profile-whitelisted thread
//   (default)    → Signal's REAL OWSTableViewController2 (Settings)
let selectedDemo = ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DEMO"]
if selectedDemo == "ssk-bootstrap" || selectedDemo == "real-conversation" || selectedDemo == "real-conversation-accepted" {
    DispatchQueue.main.async {
        Task { @MainActor in
            let vc: UIViewController
            let title: String
            let width: Int
            let height: Int
            switch selectedDemo {
            case "real-conversation":
                vc = await SignalConversationDemo.makeRealConversationViewController()
                title = "Signal Real Conversation"
                width = 760
                height = 720
            case "real-conversation-accepted":
                vc = await SignalConversationDemo.makeAcceptedRealConversationViewController()
                title = "Signal Accepted Conversation"
                width = 760
                height = 720
            default:
                vc = await SignalConversationDemo.makeSSKBootstrapProbeViewController()
                title = "Signal Runtime Bootstrap"
                width = 620
                height = 280
            }
            renderRootViewController(vc, title: title, width: width, height: height, windowBackground: "#FFFFFF")
            await runGtkMainLoopCooperatively()
        }
    }
    dispatchMain()
} else {
    MainActor.assumeIsolated {
        switch selectedDemo {
    case "firstlight":
        renderRootViewController(FirstLightViewController(), title: "Signal UI on Linux", width: 390, height: 600)
    case "conversation":
        renderRootViewController(SignalConversationDemo.makeConversationViewController(),
                                 title: "Signal on Linux", width: 760, height: 720,
                                 windowBackground: "#FFFFFF")
    case "realapp-link":
        renderRootViewController(SignalConversationDemo.makeRealAppLinkProbeViewController(),
                                 title: "SignalApp Link Probe", width: 520, height: 260,
                                 windowBackground: "#FFFFFF")
    case "real-components":
        renderRootViewController(SignalConversationDemo.makeRealComponentPreviewViewController(),
                                 title: "Signal Real Components", width: 568, height: 300,
                                 windowBackground: "#FFFFFF")
    case "privacy":
        renderRootViewController(SignalSettingsDemo.makePrivacyViewController(),
                                 title: "Signal Privacy on Linux", width: 390, height: 720)
    default:
        renderRootViewController(SignalSettingsDemo.makeSettingsViewController(),
                                 title: "Signal Settings on Linux", width: 390, height: 720)
        }
    }
}

let loop = g_main_loop_new(nil, 0)
g_main_loop_run(loop)
g_main_loop_unref(loop)
