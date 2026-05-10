// QuillAppKitSmoke
// =================
// A single-file smoke test that exercises QuillAppKit's surface with
// realistic AppKit usage patterns drawn from CodeEdit, AltTab, and
// Maccy. If this compiles on Linux, the surface is coherent enough to
// host typical Mac-app glue code without source modifications.
//
// This target only exists on Linux — on macOS the real AppKit shadows
// us. The whole module is gated so it's a no-op on Apple platforms.

#if os(Linux)

import AppKit
import Foundation

// MARK: - Window + view + view controller (CodeEdit-shape)

@MainActor
final class SmokeWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Smoke Window"
        win.titlebarAppearsTransparent = true
        win.toolbarStyle = .unified
        win.collectionBehavior = [.fullScreenPrimary]
        super.init(window: win)
        win.delegate = self
    }

    func windowDidBecomeKey(_ notification: Notification) {}
    func windowWillClose(_ notification: Notification) {}
}

@MainActor
final class SmokeViewController: NSViewController, NSMenuDelegate, NSToolbarDelegate {
    private let label = NSTextField.labelWithString("Hello")
    private let button = NSButton(title: "Click", target: nil, action: nil)
    private let split = NSSplitView()

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        v.wantsLayer = true
        v.addSubview(label)
        v.addSubview(button)
        v.addSubview(split)
        view = v
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let item = NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q")
        item.keyEquivalentModifierMask = [.command]
        menu.addItem(item)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .toggleSidebar, NSToolbarItem.Identifier(rawValue: "Custom")]
    }
}

// MARK: - Outline view delegate (CodeEdit project navigator shape)

@MainActor
final class SmokeOutlineController: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { 0 }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let cell = NSTableCellView()
        cell.textField = NSTextField.labelWithString("row")
        return cell
    }
}

// MARK: - Pasteboard / workspace / cursor (Maccy shape)

@MainActor
func smokeClipboard() {
    let pb = NSPasteboard.general
    _ = pb.clearContents()
    _ = pb.setString("hi", forType: .string)
    _ = pb.string(forType: .string)
    _ = pb.types()
    _ = NSWorkspace.shared.icon(forFile: "/tmp")
    NSCursor.arrow.set()
}

// MARK: - Status item (Maccy menu bar)

@MainActor
final class SmokeStatusItem {
    let item: NSStatusItem
    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusBar.variableLength)
        item.button?.title = "📋"
        item.menu = NSMenu()
        item.menu?.delegate = nil
    }
}

// MARK: - Application delegate (top-level entry)

@MainActor
final class SmokeAppDelegate: NSObject, NSApplicationDelegate {
    var windowController: SmokeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let wc = SmokeWindowController()
        wc.contentViewController = SmokeViewController()
        wc.showWindow(nil)
        self.windowController = wc
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Public entry point so SwiftPM has a symbol to link

@MainActor
public enum QuillAppKitSmoke {
    public static func validate() -> Bool {
        let app = NSApplication.shared
        let delegate = SmokeAppDelegate()
        app.delegate = delegate
        _ = app.setActivationPolicy(.regular)
        // Don't actually run() — this is a compile-only smoke check.
        return true
    }
}

#else

@MainActor
public enum QuillAppKitSmoke {
    public static func validate() -> Bool { true }
}

#endif
