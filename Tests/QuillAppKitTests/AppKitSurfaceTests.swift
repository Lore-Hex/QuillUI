import Foundation
import Testing
import AppKit

/// AppKit shadow surface added so WireGuard's UnusableTunnelDetailViewController
/// compiles against QuillAppKit: NSTextField(labelWithAttributedString:) and
/// NSStackView's views-initializer + setCustomSpacing (with Foundation's
/// NSEdgeInsets). Model-only (no Qt); runs on the Swift Linux Backends job.
/// Driven from real upstream compile errors (the gap-analysis spike).
@Suite("QuillAppKit surface — UnusableTunnelDetail dependencies", .serialized)
@MainActor
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

    @Test("NSView.fittingSize, NSImageView(image:), NSImageScaling aliases, and NSBezierPath(ovalIn:)")
    func timelineCellRenderingSurface() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 24))
        #expect(view.fittingSize == NSSize(width: 72, height: 24))

        let label = NSTextField(wrappingLabelWithString: "NetNewsWire timeline text wraps")
        label.preferredMaxLayoutWidth = 84
        #expect(label.fittingSize.width <= 84)
        #expect(label.fittingSize.height > 0)

        let image = NSImage(size: NSSize(width: 12, height: 14))
        let imageView = NSImageView(image: image)
        let scaling: NSImageScaling = .scaleNone
        let alignment: NSImageAlignment = .alignCenter
        imageView.imageScaling = scaling
        imageView.imageAlignment = alignment
        #expect(imageView.image === image)
        #expect(imageView.frame.size == image.size)
        #expect(imageView.imageScaling == .scaleNone)
        #expect(imageView.imageAlignment == .alignCenter)

        let path = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 8, height: 8))
        #expect(path.elementCount > 0)
    }

    @Test("NSApplication active notifications and AppKit system colors")
    @MainActor func applicationNotificationsAndSystemColors() {
        let app = NSApplication.shared
        app.deactivate()
        #expect(!app.isActive)
        #expect(NSApplication.didBecomeActiveNotification.rawValue == "NSApplicationDidBecomeActiveNotification")
        #expect(NSApplication.didResignActiveNotification.rawValue == "NSApplicationDidResignActiveNotification")

        app.activate()
        #expect(app.isActive)
        app.deactivate()
        #expect(!app.isActive)

        #expect(NSColor.systemBlue.blueComponent == 1.0)
        #expect(NSColor.systemPurple.redComponent > 0)
        #expect(NSColor.systemTeal.greenComponent > 0)
        #expect(NSColor.systemBrown.redComponent > 0)
        #expect(NSColor.systemIndigo.blueComponent > 0)
        #expect(NSColor.systemPink.redComponent == 1.0)
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

    @Test("NSWindowController nib-name lifecycle and window close hooks")
    @MainActor func windowControllerNibLifecycle() {
        final class LoadingWindowController: NSWindowController {
            var didLoadWindow = false

            override func windowDidLoad() {
                didLoadWindow = true
            }
        }

        final class Delegate: NSObject, NSWindowDelegate {
            var shouldCloseCount = 0
            var willCloseCount = 0
            var didBecomeKeyCount = 0
            var didResignKeyCount = 0

            func windowShouldClose(_ sender: NSWindow) -> Bool {
                shouldCloseCount += 1
                return true
            }

            func windowWillClose(_ notification: Notification) {
                willCloseCount += 1
            }

            func windowDidBecomeKey(_ notification: Notification) {
                didBecomeKeyCount += 1
            }

            func windowDidResignKey(_ notification: Notification) {
                didResignKeyCount += 1
            }
        }

        let controller = LoadingWindowController(windowNibName: "ActivityLogWindow")
        #expect(!controller.didLoadWindow)

        let delegate = Delegate()
        let loadedWindow = controller.window
        loadedWindow?.delegate = delegate

        #expect(controller.didLoadWindow)
        #expect(controller.window === loadedWindow)
        #expect(loadedWindow?.title == "ActivityLogWindow")
        #expect(loadedWindow?.windowController === controller)
        #expect(NSWindow.didBecomeMainNotification.rawValue == "NSWindowDidBecomeMainNotification")
        #expect(NSWindow.didResignMainNotification.rawValue == "NSWindowDidResignMainNotification")

        controller.showWindow(nil)
        #expect(controller.window?.isVisible == true)
        #expect(controller.window?.isKeyWindow == true)
        #expect(controller.window?.isMainWindow == true)
        #expect(delegate.didBecomeKeyCount == 1)

        controller.close()
        #expect(controller.window?.isVisible == false)
        #expect(controller.window?.isKeyWindow == false)
        #expect(controller.window?.isMainWindow == false)
        #expect(delegate.shouldCloseCount == 1)
        #expect(delegate.willCloseCount == 1)
        #expect(delegate.didResignKeyCount == 1)
    }

    @Test("NSColor(red:green:blue:alpha:) generic RGB init exists (WireGuard's NSColor(hex:) chains to it)")
    func nsColorGenericRGBInit() {
        let c = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let translucent = c.withAlphaComponent(0.5)
        #expect(translucent.redComponent == 0.2)
        #expect(translucent.greenComponent == 0.4)
        #expect(translucent.blueComponent == 0.6)
        #expect(translucent.alphaComponent == 0.5)
    }

    @Test("NSAppearance.isDarkMode follows AppKit appearance matching")
    func nsAppearanceDarkMode() throws {
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))
        let highContrastDark = try #require(NSAppearance(named: .accessibilityHighContrastDarkAqua))
        let vibrantDark = try #require(NSAppearance(named: .vibrantDark))

        #expect(!light.isDarkMode)
        #expect(dark.isDarkMode)
        #expect(highContrastDark.isDarkMode)
        #expect(vibrantDark.isDarkMode)
    }

    @Test("NSStatusItem.squareLength / variableLength sentinels (WireGuard's StatusItemController)")
    func nsStatusItemLengthSentinels() {
        // WireGuard: NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength).
        #expect(NSStatusItem.squareLength == -2)
        #expect(NSStatusItem.variableLength == -1)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = nil          // the status-bar button is reachable (compile-stub)
        item.length = NSStatusItem.squareLength
        #expect(item.length == -2)
    }

    @Test("NSWorkspace.OpenConfiguration carries browser-opening preferences")
    func workspaceOpenConfigurationBrowserFlags() {
        let configuration = NSWorkspace.OpenConfiguration()
        #expect(configuration.activates)
        #expect(!configuration.requiresUniversalLinks)
        #expect(configuration.promptsUserIfNeeded)

        configuration.activates = false
        configuration.requiresUniversalLinks = true
        configuration.promptsUserIfNeeded = false
        #expect(!configuration.activates)
        #expect(configuration.requiresUniversalLinks)
        #expect(!configuration.promptsUserIfNeeded)
    }

    @Test("NSTextStorage.edited(_:range:changeInLength:) + EditActions (WireGuard's ConfTextStorage)")
    func nsTextStorageEditActions() {
        // ConfTextStorage : NSTextStorage calls edited(.editedCharacters/.editedAttributes, …)
        // after mutating its backing NSMutableAttributedString.
        #expect(NSTextStorage.EditActions.editedCharacters != NSTextStorage.EditActions.editedAttributes)
        let both: NSTextStorage.EditActions = [.editedCharacters, .editedAttributes]
        #expect(both.contains(.editedCharacters) && both.contains(.editedAttributes))
        let storage = NSTextStorage(string: "") // corelibs designated init (init() isn't)
        storage.setAttributedString(NSAttributedString(string: "link"))
        storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: NSRange(location: 0, length: 4))
        #expect(storage.string == "link")
        #expect((storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.redComponent == NSColor.systemOrange.redComponent)
        storage.append(NSAttributedString(
            string: " done",
            attributes: [.foregroundColor: NSColor.systemGreen]
        ))
        #expect(storage.string == "link done")
        #expect((storage.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor)?.greenComponent == NSColor.systemGreen.greenComponent)
        storage.deleteCharacters(in: NSRange(location: 4, length: 5))
        #expect(storage.string == "link")
        storage.edited(.editedCharacters, range: NSRange(location: 0, length: 0), changeInLength: 0)
        storage.processEditing() // compile-stubs, callable
    }

    @Test("NSFontManager.convert/convertWeight + NSFontTraitMask + NSTextStorage() (ConfTextStorage shadow)")
    func confTextStorageShadowSurface() {
        // ConfTextStorage derives bold/italic fonts via NSFontManager + builds on
        // NSTextStorage's designated init().
        #expect(NSFontTraitMask.italicFontMask != NSFontTraitMask.boldFontMask)
        let fm = NSFontManager.shared
        let base = NSFont.systemFont(ofSize: 15)            // no-weight overload
        _ = fm.convertWeight(true, of: base)                // compile-stubs (return the font)
        _ = fm.convert(base, toHaveTrait: .italicFontMask)
        // NSTextStorage() — the new designated init() ConfTextStorage overrides.
        let storage = NSTextStorage()
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: 0), changeInLength: 0)
        _ = storage
    }

    @Test("NSFont descriptors retain size and traits inside attributed strings")
    func nsFontAttributedStringTraits() throws {
        let base = NSFont.systemFont(ofSize: 17)
        let bold = NSFont.systemFont(ofSize: 17, weight: .bold)
        let mono = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        let fixedPitch = try #require(NSFont.userFixedPitchFont(ofSize: 0))
        #expect(base.pointSize == 17)
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(mono.pointSize == 15)
        #expect(mono.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(fixedPitch.pointSize == NSFont.systemFontSize)
        #expect(fixedPitch.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let attributed = NSMutableAttributedString(string: "bold")
        attributed.addAttribute(.font, value: bold, range: NSRange(location: 0, length: attributed.length))
        let storedFont = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(storedFont.pointSize == 17)
        #expect(storedFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("NSTextView init(frame:textContainer:) + preserved NSTextView()/(frame:) + edit hooks (ConfTextView)")
    func confTextViewShadowSurface() {
        // The new designated init ConfTextView uses:
        let tv = NSTextView(frame: .zero, textContainer: NSTextContainer())
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        #expect(tv.shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: "x"))
        tv.didChangeText()
        // Preserved entry points (must still work — AppleCompatibilitySmoke uses NSTextView()):
        _ = NSTextView()
        _ = NSTextView(frame: .zero)
        // NSView appearance hooks ConfTextView overrides:
        let v = NSView(frame: .zero)
        _ = v.effectiveAppearance
        v.viewDidChangeEffectiveAppearance()
    }

    @Test("NSView cursor rects and NSTextView insertion hit testing support link controls")
    func linkControlSurface() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        view.addCursorRect(view.bounds, cursor: .pointingHand)
        #expect(view.quillCursorRects.count == 1)
        #expect(view.quillCursorRects.first?.rect == view.bounds)
        view.discardCursorRects()
        #expect(view.quillCursorRects.isEmpty)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 140, height: 30))
        textView.textContainerInset = NSSize(width: 7, height: 0)
        textView.textStorage?.setAttributedString(NSAttributedString(string: "abcdefghij"))
        #expect(textView.characterIndexForInsertion(at: NSPoint(x: -20, y: 0)) == 0)
        #expect(textView.characterIndexForInsertion(at: NSPoint(x: 7, y: 0)) == 0)
        #expect(textView.characterIndexForInsertion(at: NSPoint(x: 21, y: 0)) == 2)
        #expect(textView.characterIndexForInsertion(at: NSPoint(x: 200, y: 0)) == 10)
        textView.scrollToEndOfDocument(nil)
        #expect(textView.selectedRange.location == 10)
    }

    @Test("NSTokenField + NSTokenFieldDelegate (WireGuard's OnDemandControlsRow)")
    func nsTokenFieldSurface() {
        let tf = NSTokenField()
        tf.tokenStyle = .squared
        tf.tokenizingCharacterSet = CharacterSet([])
        #expect(tf.tokenStyle == .squared)
        // NSTokenFieldDelegate refines NSTextFieldDelegate; its completion hook
        // has a default impl (nil) so conformers override only what they need.
        final class D: NSObject, NSTokenFieldDelegate {}
        let d = D()
        #expect(d.tokenField(tf, completionsForSubstring: "x", indexOfToken: 0, indexOfSelectedItem: nil) == nil)
    }

    @Test("TunnelEditViewController shadow gaps: NSText min/maxSize, NSWindow.ignoresMouseEvents, NSStackView.setHuggingPriority, NSTextContainer.size")
    func tunnelEditShadowSurface() {
        let tv = NSTextView()
        tv.minSize = NSSize(width: 1, height: 1)
        tv.maxSize = NSSize(width: 100, height: 100)
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        #expect(tv.minSize.width == 1 && tv.maxSize.height == 100)
        let w = NSWindow()
        w.ignoresMouseEvents = true
        #expect(w.ignoresMouseEvents)
        let stack = NSStackView()
        stack.setHuggingPriority(.defaultHigh, for: .horizontal) // compile-stub
        let tc = NSTextContainer()
        tc.size = NSSize(width: 50, height: 50)
        #expect(tc.size.width == 50)
    }

    @Test("TunnelDetailTableViewController shadow gaps: NSView.toolTip, NSScrollView.drawsBackground, NSTableView.selectionHighlightStyle")
    @MainActor func tunnelDetailShadowSurface() {
        // ButtonRow.buttonToolTip / cell tooltips set NSView.toolTip (NSButton is an NSView).
        let button = NSButton()
        button.toolTip = "Activate"
        #expect(button.toolTip == "Activate")
        // TunnelDetail's table is hosted in a transparent scroll view.
        let scroll = NSScrollView(frame: .zero)
        scroll.drawsBackground = false
        #expect(scroll.drawsBackground == false)
        // The read-only detail rows use selectionHighlightStyle = .none.
        let table = NSTableView(frame: .zero)
        table.selectionHighlightStyle = .none
        #expect(table.selectionHighlightStyle == .none)
        #expect(NSTableView.SelectionHighlightStyle.none != NSTableView.SelectionHighlightStyle.regular)
    }

    @Test("TunnelsListTableViewController shadow gaps: NSControl.cell as? NSPopUpButtonCell, NSButton(frame:), @MainActor keyDown")
    @MainActor func tunnelsListShadowSurface() {
        // The add/action menus do (popup.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom.
        // NSPopUpButton seeds its cell with an NSPopUpButtonCell (now : NSCell) so the downcast succeeds.
        let popup = NSPopUpButton(frame: .zero, pullsDown: true)
        let cell = popup.cell as? NSPopUpButtonCell
        #expect(cell != nil)
        cell?.arrowPosition = .arrowAtBottom
        #expect(cell?.arrowPosition == .arrowAtBottom)
        // NSButton(frame:) — FillerButton: NSButton uses super.init(frame:).
        let filler = NSButton(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        #expect(filler.frame.width == 10)
        // keyDown is @MainActor (TunnelsList.keyDown calls @MainActor handleRemoveTunnelAction on Delete).
        NSResponder().keyDown(with: NSEvent())
    }

    @Test("ManageTunnelsRootViewController shadow gap: NSResponder.supplementalTarget(forAction:sender:)")
    @MainActor func manageTunnelsRootShadowSurface() {
        // The split-view root overrides supplementalTarget to route toolbar/menu actions
        // to its child VCs; the base returns nil (no supplemental target).
        let responder = NSResponder()
        #expect(responder.supplementalTarget(forAction: Selector("handleAddEmptyTunnelAction"), sender: nil) == nil)
    }

    @Test("MainMenu shadow gaps: NSMenuItem.separator() func + NSMenu(title:)/addItem(withTitle:action:keyEquivalent:)/setSubmenu + subclass init() w/o override")
    @MainActor func mainMenuShadowSurface() {
        let menu = NSMenu(title: "File")
        #expect(menu.title == "File")
        let item = menu.addItem(withTitle: "New", action: Selector("handleAddEmptyTunnelAction"), keyEquivalent: "n")
        item.keyEquivalentModifierMask = [.command, .option]
        #expect(item.keyEquivalent == "n")
        // separator() is the call form (was a `static var separator` property; MainMenu/StatusMenu use ()).
        let separator = NSMenuItem.separator()
        menu.addItem(separator)
        #expect(separator.isSeparatorItem)
        menu.addSeparatorIfNeeded()
        #expect(menu.numberOfItems == 2)
        menu.setSubmenu(NSMenu(), for: item)
        // NSMenu's init() is convenience (init(title:) designated) → a subclass can declare
        // its own init() WITHOUT `override` (what WireGuard's MainMenu/StatusMenu rely on).
        let custom = MenuInitModelProbe()
        #expect(custom.title == "probe")
    }

    @Test("StatusMenu shadow gaps: NSMenu.numberOfItems / removeItem(at:) / item(at:)")
    @MainActor func statusMenuShadowSurface() {
        let menu = NSMenu(title: "Status")
        let a = menu.addItem(withTitle: "A", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let c = menu.addItem(withTitle: "C", action: nil, keyEquivalent: "")
        #expect(menu.numberOfItems == 3)
        #expect(menu.item(at: 0) === a)
        menu.removeItem(at: 1) // remove the separator (StatusMenu rebuilds per-tunnel rows by index)
        #expect(menu.numberOfItems == 2)
        #expect(menu.item(at: 1) === c)
        menu.removeItem(at: 99) // out-of-range → no-op (no crash)
        #expect(menu.numberOfItems == 2)
    }

    @Test("Apple-Events detector shadow: NSAppleEventDescriptor + kAE constants + Darwin C stubs")
    func appleEventsDetectorShadow() {
        #if os(Linux)
        // LaunchedAtLoginDetector/MacAppStoreUpdateDetector compare eventClass/eventID
        // against these four-char-code constants (visible via AppKit → @_exported QuillFoundation).
        #expect(kCoreEventClass == 0x6165_7674) // 'aevt'
        #expect(kAEOpenApplication != kAEQuitApplication)
        let desc = NSAppleEventDescriptor()
        #expect(desc.eventClass == 0 && desc.eventID == 0 && desc.int32Value == 0)
        #expect(desc.attributeDescriptor(forKeyword: keySenderPIDAttr) == nil)
        // Darwin-only C the detectors call; Linux maps uptime to clock_gettime.
        #expect(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) > 0)
        #expect(proc_pidpath(0, nil, 0) == 0)
        #endif
    }

    @Test("AppleScript descriptor, specifier, and command shims preserve state")
    func appleScriptScriptingSurface() {
        #if os(Linux)
        #expect("GURL".fourCharCode == kInternetEventClass)
        #expect(0x4755_524C.fourCharCode == kAEGetURL)

        let event = NSAppleEventDescriptor(eventClass: kInternetEventClass, eventID: kAEGetURL, descriptorType: "GURL".fourCharCode)
        let directObject = NSAppleEventDescriptor(string: "feed:https://example.com/feed.xml")
        event.setParam(directObject, forKeyword: keyDirectObject)
        event.setAttribute(NSAppleEventDescriptor(int32Value: 42), forKeyword: keySenderPIDAttr)
        #expect(event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue == "feed:https://example.com/feed.xml")
        #expect(event.forKeyword(keyDirectObject)?.stringValue == "feed:https://example.com/feed.xml")
        #expect(event.attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value == 42)

        let manager = NSAppleEventManager.shared()
        let before = manager.installedHandlers.count
        manager.setEventHandler(NSObject(), andSelector: Selector("getURL(_:_:)"), forEventClass: kInternetEventClass, andEventID: kAEGetURL)
        #expect(manager.installedHandlers.count == before + 1)
        #expect(manager.installedHandlers.last?.selector == Selector("getURL(_:_:)"))

        let classDescription = NSScriptClassDescription(className: "feed")
        #expect(classDescription.className == "feed")
        let container = NSScriptObjectSpecifier(containerClassDescription: classDescription, containerSpecifier: nil, key: "feeds")
        let nameSpecifier = NSNameSpecifier(containerClassDescription: classDescription, containerSpecifier: container, key: "feeds", name: "Example")
        #expect(nameSpecifier.key == "feeds")
        #expect(nameSpecifier.name == "Example")
        #expect(nameSpecifier.containerSpecifier === container)

        let uniqueSpecifier = NSUniqueIDSpecifier(containerClassDescription: classDescription, containerSpecifier: container, key: "feeds", uniqueID: "feed-id")
        uniqueSpecifier.evaluatedObject = "resolved-feed"
        #expect(uniqueSpecifier.uniqueID as? String == "feed-id")
        #expect(uniqueSpecifier.objectsByEvaluatingSpecifier as? String == "resolved-feed")
        #expect(uniqueSpecifier.objectsByEvaluating(withContainers: "fallback") as? String == "resolved-feed")

        let command = NSCreateCommand(
            arguments: ["ObjectClass": Int("Feed".fourCharCode)],
            evaluatedArguments: ["KeyDictionary": ["name": "Example"]],
            appleEvent: event,
            createClassDescription: classDescription,
            receiversSpecifier: container,
            keySpecifier: uniqueSpecifier
        )
        command.suspendExecution()
        #expect(command.isExecutionSuspended)
        command.resumeExecution(withResult: "done")
        #expect(!command.isExecutionSuspended)
        #expect(command.resumedResult as? String == "done")
        #expect(command.performDefaultImplementation() == nil)
        #expect((NSExistsCommand().performDefaultImplementation() as? NSNumber)?.boolValue == true)
        #endif
    }

    @Test("AppDelegate shadow gaps: NSApp.activationPolicy() method/AboutPanel, NSWindow(contentViewController:)/attachedSheet, NSAppleEventManager")
    @MainActor func appDelegateShadowSurface() {
        // activationPolicy() is now a method (was a property); setActivationPolicy round-trips.
        _ = NSApp.setActivationPolicy(.accessory)
        #expect(NSApp.activationPolicy() == .accessory)
        _ = NSApp.setActivationPolicy(.regular)
        // Standard About panel (compile-stub) + its option keys.
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: "1.0", .version: "", .credits: ""])
        #expect(NSApplication.AboutPanelOptionKey.applicationVersion != NSApplication.AboutPanelOptionKey.credits)
        // NSWindow hosting a VC + attachedSheet (nil until sheets are modelled).
        let win = NSWindow(contentViewController: NSViewController())
        #expect(win.contentViewController != nil && win.attachedSheet == nil)
        // NSAppleEventManager (via AppKit → @_exported QuillFoundation): no current event on Linux.
        #if os(Linux)
        #expect(NSAppleEventManager.shared().currentAppleEvent == nil)
        #endif
    }

    @Test("Share extension context surface carries input, completion, cancellation, and nib names")
    @MainActor func shareExtensionContextSurface() {
        final class ProbeViewController: NSViewController {
            override var nibName: NSNib.Name? { "ProbeView" }
        }

        let provider = NSItemProvider(data: Data([1, 2, 3]), type: .url)
        let item = NSExtensionItem(attachments: [provider])
        let context = NSExtensionContext()
        context.inputItems = [item]
        let controller = ProbeViewController()
        controller.extensionContext = context

        #expect(controller.nibName == "ProbeView")
        #expect((controller.extensionContext?.inputItems.first as? NSExtensionItem)?.attachments?.first === provider)

        var completed = false
        context.completeRequest(returningItems: []) { success in
            completed = success
        }
        #expect(completed)
        #expect(context.didCompleteRequest)
        #expect(context.completedReturningItems?.isEmpty == true)

        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        context.cancelRequest(withError: error)
        #expect((context.cancellationError as NSError?)?.code == NSUserCancelledError)
    }

    @Test("NSApplication.presentError records presented errors for Linux testability")
    @MainActor func applicationPresentErrorSurface() {
        enum ProbeError: LocalizedError {
            case failed

            var errorDescription: String? { "probe failure" }
        }

        NSApp.quillClearPresentedErrors()
        defer { NSApp.quillClearPresentedErrors() }

        #expect(NSApp.presentError(ProbeError.failed))
        #expect(NSApp.quillPresentedErrors.count == 1)
        #expect(NSApp.quillPresentedErrors.first?.localizedDescription == "probe failure")
    }

    @Test("Nil-target NSApplication actions climb the responder chain")
    @MainActor func applicationSendActionUsesResponderChain() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let controller = ResponderActionProbe()
        view.nextResponder = controller

        #expect(NSApp.sendAction(Selector("copy(_:)"), to: nil, from: view))
        #expect(controller.receivedSelectors == ["copy(_:)"])
        #expect(controller.lastSender === view)

        #expect(NSApp.sendAction(Selector("selectNextDown(_:)"), to: controller, from: view))
        #expect(controller.receivedSelectors == ["copy(_:)", "selectNextDown(_:)"])
        #expect(controller.lastSender === view)
    }

    @Test("Window key-loop, control font, and popup title APIs preserve state")
    @MainActor func windowControlFontAndPopupTitleSurface() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.recalculateKeyViewLoop()
        #expect(window.frame.size.width == 240)

        let controlFont = NSFont.controlContentFont(ofSize: NSFont.systemFontSize)
        #expect(controlFont.pointSize == NSFont.systemFontSize)
        let fallbackControlFont = NSFont.controlContentFont(ofSize: 0)
        #expect(fallbackControlFont.pointSize == NSFont.systemFontSize)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ["Newest", "Oldest"])
        popup.selectItem(withTitle: "Oldest")
        #expect(popup.titleOfSelectedItem == "Oldest")
        popup.select(popup.itemWithTitle("Newest"))
        #expect(popup.indexOfSelectedItem == 0)
        #expect(popup.selectedItem?.title == "Newest")
        #expect(popup.titleOfSelectedItem == "Newest")
        popup.setTitle("Newest")
        #expect(popup.title == "Newest")
        #expect(popup.titleOfSelectedItem == "Newest")
    }

    @Test("Open panel iCloud options preserve state for OPML import flows")
    @MainActor func openPanelUbiquitousOptionsSurface() {
        let panel = NSOpenPanel()
        #expect(!panel.canDownloadUbiquitousContents)
        #expect(!panel.canResolveUbiquitousConflicts)
        #expect(!panel.isAccessoryViewDisclosed)

        panel.canDownloadUbiquitousContents = true
        panel.canResolveUbiquitousConflicts = true
        panel.isAccessoryViewDisclosed = true

        #expect(panel.canDownloadUbiquitousContents)
        #expect(panel.canResolveUbiquitousConflicts)
        #expect(panel.isAccessoryViewDisclosed)
    }

    @Test("NetNewsWire Accounts shims preserve AppKit model semantics")
    @MainActor func netNewsWireAccountsAppKitSurface() async {
        let cell = NSTableCellView(frame: .zero)
        #expect(cell.backgroundStyle == .normal)
        cell.backgroundStyle = .emphasized
        #expect(cell.backgroundStyle == .emphasized)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let child = NSView(frame: .zero)
        host.addSubview(child)

        let constraints = host.constraintsToMakeSubViewFullSize(child)
        #expect(constraints.count == 4)
        #expect(constraints.map(\.firstAttribute) == [.leading, .trailing, .top, .bottom])
        #expect(constraints.allSatisfy { $0.firstItem === child && $0.secondItem === host })
        #expect(constraints.allSatisfy { !$0.isActive })

        let activeCountBefore = NSLayoutConstraint.quillActive.count
        host.addFullSizeConstraints(forSubview: child)
        let addedConstraints = Array(NSLayoutConstraint.quillActive.dropFirst(activeCountBefore))
        defer { NSLayoutConstraint.deactivate(addedConstraints) }
        #expect(addedConstraints.count == 4)
        #expect(addedConstraints.allSatisfy { $0.isActive })
        #expect(addedConstraints.map(\.firstAttribute) == [.leading, .trailing, .top, .bottom])
        #expect(addedConstraints.allSatisfy { $0.quillRelation == .equal && $0.quillConstant == 0 })

        let username = NSTextField()
        username.contentType = .username
        #expect(username.contentType?.rawValue == "username")

        let password = NSSecureTextField()
        password.contentType = .password
        #expect(password.contentType == .password)

        let grid = NSGridView(frame: .zero)
        let firstRow = grid.row(at: 2)
        firstRow.isHidden = true
        #expect(grid.row(at: 2) === firstRow)
        #expect(grid.row(at: 2).isHidden)
        #expect(grid.row(at: 3) !== firstRow)

        let parent = NSWindow()
        let sheet = NSWindow()
        var response: NSApplication.ModalResponse?
        parent.beginSheet(sheet) { response = $0 }
        #expect(sheet.isVisible)
        #expect(sheet.sheetParent === parent)
        #expect(parent.sheets.contains { $0 === sheet })

        parent.endSheet(sheet, returnCode: .cancel)
        #expect(response == .cancel)
        #expect(!sheet.isVisible)
        #expect(sheet.sheetParent == nil)
        #expect(parent.sheets.isEmpty)
    }

    @Test("MainWindow toolbar and search item shims preserve AppKit state")
    @MainActor func mainWindowToolbarSurface() {
        let toolbar = NSToolbar(identifier: "MainWindowToolbar")
        let menuItem = NSMenuToolbarItem(itemIdentifier: NSToolbarItem.Identifier("articleThemeMenu"))
        let menu = NSMenu(title: "Themes")
        menu.addItem(withTitle: "Default", action: nil, keyEquivalent: "")
        menuItem.menu = menu
        toolbar.items = [menuItem]
        toolbar.visibleItems = [menuItem]

        #expect(toolbar.existingItem(withIdentifier: NSToolbarItem.Identifier("articleThemeMenu")) === menuItem)
        #expect((toolbar.existingItem(withIdentifier: NSToolbarItem.Identifier("articleThemeMenu")) as? NSMenuToolbarItem)?.menu === menu)

        let searchItem = NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier("search"))
        searchItem.searchField.stringValue = "swift"
        #expect(searchItem.view === searchItem.searchField)
        #expect(searchItem.searchField.stringValue == "swift")

        let splitView = NSSplitView()
        let trackingItem = NSTrackingSeparatorToolbarItem(
            identifier: NSToolbarItem.Identifier("timelineTrackingSeparator"),
            splitView: splitView,
            dividerIndex: 1
        )
        #expect(trackingItem.itemIdentifier.rawValue == "timelineTrackingSeparator")
        #expect(trackingItem.splitView === splitView)
        #expect(trackingItem.dividerIndex == 1)

        let button = NSButton()
        let previousMask = button.sendAction(on: .leftMouseDown)
        #expect(previousMask == Int(NSEvent.EventTypeMask.leftMouseUp.rawValue))
        #expect(button.quillSendActionEventMask == .leftMouseDown)
    }

    @Test("NSWindow restoration helpers and fullscreen state round-trip")
    @MainActor func windowRestorationHelpers() {
        let window = NSWindow()
        window.setPointAndSizeAdjustingForScreen(
            point: NSPoint(x: 128, y: 64),
            size: NSSize(width: 320, height: 240),
            minimumSize: NSSize(width: 600, height: 600)
        )
        #expect(window.frame.origin == NSPoint(x: 128, y: 64))
        #expect(window.frame.size == NSSize(width: 600, height: 600))
        #expect(window.minSize == NSSize(width: 600, height: 600))
        #expect(!window.styleMask.contains(.fullScreen))

        window.toggleFullScreen(nil)
        #expect(window.styleMask.contains(.fullScreen))
        window.toggleFullScreen(nil)
        #expect(!window.styleMask.contains(.fullScreen))
        #expect(window.setFrameUsingName(NSWindow.FrameAutosaveName("MainWindow"), force: true) == false)

        let splitItem = NSSplitViewItem(viewController: NSViewController())
        splitItem.automaticallyAdjustsSafeAreaInsets = true
        #expect(splitItem.automaticallyAdjustsSafeAreaInsets)
    }

    @Test("NSUserActivity carries deep-link metadata")
    @MainActor func userActivityMetadata() {
        let activity = NSUserActivity(activityType: "com.example.article")
        activity.title = "Article"
        activity.addUserInfoEntries(from: ["feedID": "f1", "articleID": "a1"])
        activity.addUserInfoEntries(from: ["articleID": "a2"])

        #expect(activity.activityType == "com.example.article")
        #expect(activity.title == "Article")
        #expect(activity.userInfo?["feedID"] as? String == "f1")
        #expect(activity.userInfo?["articleID"] as? String == "a2")
    }

    @Test("NSTableView row navigation actions clamp and handle empty selection")
    @MainActor func tableRowNavigationActions() {
        final class Source: NSObject, NSTableViewDataSource {
            func numberOfRows(in tableView: NSTableView) -> Int { 3 }
        }

        let table = NSTableView()
        let source = Source()
        table.dataSource = source
        table.reloadData()

        table.selectNextRow(nil)
        #expect(table.selectedRow == 0)
        table.selectNextRow(nil)
        #expect(table.selectedRow == 1)
        table.selectNextRow(nil)
        table.selectNextRow(nil)
        #expect(table.selectedRow == 2)

        table.selectPreviousRow(nil)
        #expect(table.selectedRow == 1)
        table.deselectAll(nil)
        table.selectPreviousRow(nil)
        #expect(table.selectedRow == 2)
    }
}

/// Probes the NSMenu init-model fix: a subclass declaring `init()` (a new designated
/// init calling super.init(title:)) compiles WITHOUT an `override` keyword — exactly
/// as WireGuard's MainMenu/StatusMenu do.
private final class MenuInitModelProbe: NSMenu {
    init() { super.init(title: "probe") }
    required init(coder decoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor
private final class ResponderActionProbe: NSResponder {
    private(set) var receivedSelectors: [String] = []
    private(set) weak var lastSender: AnyObject?

    override func quillPerform(_ selector: Selector, with sender: Any?) {
        switch selector.name {
        case "copy(_:)", "selectNextDown(_:)":
            receivedSelectors.append(selector.name)
            lastSender = sender as AnyObject?
        default:
            super.quillPerform(selector, with: sender)
        }
    }
}
