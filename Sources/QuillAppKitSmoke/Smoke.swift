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

func smokeGeometryStringHelpers() -> Bool {
    let rect = NSRect(x: -1.5, y: 2.25, width: 300, height: 40.5)
    let parsed = NSRectFromString(NSStringFromRect(rect))
    return parsed.origin.x == rect.origin.x &&
        parsed.origin.y == rect.origin.y &&
        parsed.size.width == rect.size.width &&
        parsed.size.height == rect.size.height
}

func smokeAppearanceMatching() -> Bool {
    let dark = NSAppearance(named: .darkAqua)
    let highContrastDark = NSAppearance(named: .accessibilityHighContrastDarkAqua)
    return dark?.name == .darkAqua &&
        dark?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua &&
        highContrastDark?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

func smokeFontManagerFallbacks() -> Bool {
    let manager = NSFontManager.shared
    let fonts = manager.availableFonts()
    let families = manager.availableFontFamilies()
    return !fonts.isEmpty &&
        !families.isEmpty &&
        fonts == fonts.sorted() &&
        families == families.sorted() &&
        fonts.contains("Helvetica") &&
        fonts.contains("Menlo-Regular") &&
        families.contains("Helvetica") &&
        manager.availableMembers(ofFontFamily: "Helvetica")?.first?.first as? String == "Helvetica" &&
        manager.availableMembers(ofFontFamily: "QuillCustomFamily") == nil
}

@MainActor
func smokeOpenPanelFallbacks() -> Bool {
    let panel = NSOpenPanel()
    let defaultsMatch =
        panel.canChooseFiles &&
        !panel.canChooseDirectories &&
        !panel.allowsMultipleSelection &&
        panel.resolvesAliases &&
        panel.urls.isEmpty &&
        panel.url == nil

    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = false
    panel.directoryURL = URL(fileURLWithPath: "/tmp")
    panel.allowedFileTypes = ["txt"]

    var beginResponse: NSApplication.ModalResponse?
    panel.begin { response in
        beginResponse = response
    }

    return defaultsMatch &&
        !panel.canChooseFiles &&
        panel.canChooseDirectories &&
        panel.allowsMultipleSelection &&
        !panel.resolvesAliases &&
        panel.directoryURL == URL(fileURLWithPath: "/tmp") &&
        panel.allowedFileTypes == ["txt"] &&
        panel.runModal() == .cancel &&
        beginResponse == .cancel
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
        return smokeGeometryStringHelpers() &&
            smokeAppearanceMatching() &&
            smokeFontManagerFallbacks() &&
            smokeOpenPanelFallbacks()
    }
}

#else

@MainActor
public enum QuillAppKitSmoke {
    public static func validate() -> Bool { true }
}

#endif
