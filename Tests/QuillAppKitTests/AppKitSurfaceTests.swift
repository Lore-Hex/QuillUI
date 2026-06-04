import Foundation
import Testing
import AppKit

/// AppKit shadow surface added so WireGuard's UnusableTunnelDetailViewController
/// compiles against QuillAppKit: NSTextField(labelWithAttributedString:) and
/// NSStackView's views-initializer + setCustomSpacing (with Foundation's
/// NSEdgeInsets). Model-only (no Qt); runs on the Swift Linux Backends job.
/// Driven from real upstream compile errors (the gap-analysis spike).
@Suite("QuillAppKit surface — UnusableTunnelDetail dependencies")
struct AppKitSurfaceTests {
    @Test("NSTextField(labelWithAttributedString:) carries the attributed string's text")
    func textFieldLabelWithAttributedString() {
        let label = NSTextField(labelWithAttributedString: NSAttributedString(string: "Public key:"))
        #expect(label.stringValue == "Public key:")
    }

    @Test("NSStackView(views:) seeds arranged subviews; edgeInsets struct + setCustomSpacing work")
    func stackViewViewsInit() {
        let a = NSView(frame: .zero)
        let b = NSView(frame: .zero)
        let stack = NSStackView(views: [a, b])
        #expect(stack.arrangedSubviews.count == 2)
        stack.edgeInsets = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        #expect(stack.edgeInsets.top == 5 && stack.edgeInsets.right == 5)
        stack.setCustomSpacing(8, after: a) // compiles (no-op until layout models spacing)
    }

    @Test("NSLayoutGuide: addLayoutGuide stores + owns; anchors build constraints with the guide as item")
    func layoutGuide() {
        let view = NSView(frame: .zero)
        let guide = NSLayoutGuide()
        view.addLayoutGuide(guide)
        #expect(view.layoutGuides.count == 1)
        #expect(guide.owningView === view)

        // The guide's anchors build real constraints, with the guide as the item.
        let c = guide.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        #expect(c.quillConstant == 8)
        #expect(c.quillFirstAnchor?.quillItem === guide)

        view.removeLayoutGuide(guide)
        #expect(view.layoutGuides.isEmpty)
        #expect(guide.owningView == nil)
    }

    @Test("NSImage template-name constants + NSEvent.specialKey (WireGuard's tunnels list)")
    func nsImageTemplateNamesAndSpecialKey() {
        // NSImage(named: NSImage.addTemplateName) etc. in the toolbar.
        #expect(NSImage.addTemplateName == "NSAddTemplate")
        #expect(NSImage.removeTemplateName == "NSRemoveTemplate")
        #expect(NSImage.actionTemplateName == "NSActionTemplate")
        // event.specialKey == .delete in keyDown; nil compile-stub on Linux.
        #expect(NSEvent().specialKey == nil)
        #expect(NSEvent.SpecialKey.delete == NSEvent.SpecialKey.delete)
        #expect(NSEvent.SpecialKey.delete != NSEvent.SpecialKey.tab)
    }

    @Test("NSView frame/bounds change notifications + posts flags + NSTableView.usesAutomaticRowHeights")
    @MainActor func viewNotificationsAndTableRowHeights() {
        // WireGuard's LogViewController observes frame/bounds changes to autoscroll.
        #expect(NSView.frameDidChangeNotification.rawValue == "NSViewFrameDidChangeNotification")
        #expect(NSView.boundsDidChangeNotification.rawValue == "NSViewBoundsDidChangeNotification")
        let v = NSView(frame: .zero)
        v.postsFrameChangedNotifications = true
        v.postsBoundsChangedNotifications = true
        #expect(v.postsFrameChangedNotifications && v.postsBoundsChangedNotifications)
        let table = NSTableView(frame: .zero)
        table.usesAutomaticRowHeights = true
        #expect(table.usesAutomaticRowHeights)
    }

    @Test("LogViewController AppKit deps: NSUserInterfaceItemIdentifier(_:), NSWindow.FrameAutosaveName, NSResponder.cancelOperation, NSTableView.row(at:)/NSView.scroll")
    @MainActor func logViewControllerAppKitSurface() {
        // NSTableColumn(identifier: NSUserInterfaceItemIdentifier("time")) — the
        // unlabeled convenience init WireGuard uses to build its log columns.
        let ident = NSUserInterfaceItemIdentifier("time")
        #expect(ident.rawValue == "time")
        let column = NSTableColumn(identifier: ident)
        #expect(column.identifier.rawValue == "time")

        // NSWindow.FrameAutosaveName (= String) flows into setFrameAutosaveName,
        // which LogViewController calls to persist the log window's geometry.
        let name = NSWindow.FrameAutosaveName("LogWindow")
        #expect(name == "LogWindow")
        let window = NSWindow()
        #expect(window.setFrameAutosaveName(name))

        // NSResponder.cancelOperation (Esc / Cmd-.) — compile-stub, callable.
        NSResponder().cancelOperation(nil)

        // NSTableView.row(at:) (compile-stub: -1 = no row) + NSView.scroll(_:):
        // LogViewController uses these to keep the log scrolled to the tail.
        let table = NSTableView(frame: .zero)
        #expect(table.row(at: NSPoint(x: 0, y: 0)) == -1)
        table.scroll(NSPoint(x: 0, y: 10))
    }

    @Test("NSColor(red:green:blue:alpha:) generic RGB init exists (WireGuard's NSColor(hex:) chains to it)")
    func nsColorGenericRGBInit() {
        // Compile-stub (ignores components), but must exist + be callable so
        // WireGuard's NSColor+Hex — NSColor(hex:) -> self.init(red:green:blue:alpha:) — compiles.
        let c = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        #expect(c.withAlphaComponent(1) === c) // stub returns self; proves a usable NSColor
    }
}
