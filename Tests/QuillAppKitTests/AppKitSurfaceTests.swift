import Foundation
import Testing
import AppKit

private protocol XPCDataProvider {
    func getData(reply: @escaping (Data?, Error?) -> Void)
}

private final class XPCDataService: XPCDataProvider {
    let value: Data

    init(value: Data) {
        self.value = value
    }

    func getData(reply: @escaping (Data?, Error?) -> Void) {
        reply(value, nil)
    }
}

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
        #expect(NSEvent.EventTypeMask.otherMouseDown.contains(.otherMouseDown))
        #expect(NSEvent.EventTypeMask.otherMouseUp.contains(.otherMouseUp))
        #expect(NSEvent.EventTypeMask.otherMouseDragged.contains(.otherMouseDragged))
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

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = table
        scrollView.drawsBackground = true
        table.backgroundColor = NSColor.white
        table.viewDidMoveToWindow()
        #expect(!scrollView.drawsBackground)
        #expect(table.backgroundColor.alphaComponent == 0)
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

    @Test("CodeEdit split-view and find-panel AppKit surface")
    @MainActor func codeEditSplitViewAndFindPanelSurface() {
        final class CustomSplitView: NSSplitView {
            override var dividerThickness: CGFloat { 2 }
            override var dividerColor: NSColor { .separatorColor }
            override func drawDivider(in rect: NSRect) {
                _ = rect
            }
        }

        final class SplitController: NSSplitViewController {
            override func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
                dividerIndex == 1
            }
        }

        let splitView = CustomSplitView()
        #expect(splitView.dividerThickness == 2)
        #expect(splitView.dividerColor === NSColor.separatorColor)
        splitView.drawDivider(in: .zero)

        let controller = SplitController()
        #expect(controller.splitView(splitView, shouldHideDividerAt: 1))
        #expect(!controller.splitView(splitView, shouldHideDividerAt: 0))

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSViewController())
        sidebar.titlebarSeparatorStyle = .none
        sidebar.collapseBehavior = .useConstraints
        #expect(sidebar.behavior == .sidebar)
        #expect(sidebar.titlebarSeparatorStyle == .none)
        #expect(sidebar.animator().isCollapsed == false)
        sidebar.animator().isCollapsed.toggle()
        #expect(sidebar.isCollapsed)

        let inspector = NSSplitViewItem(inspectorWithViewController: NSViewController())
        inspector.maximumThickness = .greatestFiniteMagnitude
        #expect(inspector.behavior == .inspector)
        #expect(inspector.maximumThickness == .greatestFiniteMagnitude)

        #expect(NSFindPanelAction.showFindPanel.rawValue == 1)
        #expect(NSFindPanelAction.next != NSFindPanelAction.previous)
        #expect(NSFindPanelAction(rawValue: NSFindPanelAction.setFindString.rawValue) == .setFindString)
    }

    @Test("CodeEdit latest AppKit surface: active notification, split item spring loading, control colors, scrollable text view")
    @MainActor func codeEditLatestAppKitSurface() {
        #expect(NSApplication.didBecomeActiveNotification.rawValue == "NSApplicationDidBecomeActiveNotification")
        #expect(NSApplication.didResignActiveNotification.rawValue == "NSApplicationDidResignActiveNotification")
        #expect(NSMenu.didSendActionNotification.rawValue == "NSMenuDidSendActionNotification")
        #expect(NSColor.controlColor.alphaComponent == 1)
        #expect(NSColor.disabledControlTextColor.alphaComponent == 1)
        #expect(NSColor.unemphasizedSelectedTextBackgroundColor.alphaComponent == 1)
        #expect(NSColor.systemFill.alphaComponent > NSColor.quaternarySystemFill.alphaComponent)
        #expect(NSColor.secondarySystemFill.alphaComponent > NSColor.tertiarySystemFill.alphaComponent)
        let optionalFill: NSColor? = .tertiarySystemFill
        #expect(optionalFill === NSColor.tertiarySystemFill)
        #expect(NSEvent.SpecialKey.delete.unicodeScalar == Unicode.Scalar(0x7f)!)

        let splitItem = NSSplitViewItem(viewController: NSViewController())
        splitItem.isSpringLoaded = true
        #expect(splitItem.isSpringLoaded)

        let outlineView = NSOutlineView()
        outlineView.lineBreakMode = .byTruncatingTail
        outlineView.removeItems(at: IndexSet(integer: 0), inParent: nil)
        #expect(outlineView.lineBreakMode == .byTruncatingTail)

        let textField = NSTextField()
        textField.allowsEditingTextAttributes = true
        textField.cell?.usesSingleLineMode = false
        textField.selectText(nil)
        textField.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        #expect(textField.allowsEditingTextAttributes)
        #expect(textField.cell?.usesSingleLineMode == false)

        let scroller = NSScroller()
        scroller.controlSize = .mini
        #expect(scroller.controlSize == .mini)

        let scrollView = NSTextView.scrollableTextView()
        #expect(scrollView.documentView is NSTextView)
        #expect(scrollView.hasVerticalScroller)
        #expect(scrollView.verticalScroller != nil)

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular, scale: .medium)
        let imageView = NSImageView(frame: .zero)
        imageView.symbolConfiguration = symbolConfiguration
        let button = NSButton(frame: .zero)
        button.symbolConfiguration = symbolConfiguration
        #expect(imageView.symbolConfiguration != nil)
        #expect(button.symbolConfiguration != nil)
        #expect(NSImage(size: CGSize(width: 1, height: 1)).representations.isEmpty)
        #expect(NSImage(data: Data([0]))?.representations.count == 1)
    }

    @Test("NSXPC continuation optional reply handlers unwrap non-optional results")
    func xpcContinuationOptionalReplyHandlers() async throws {
        let expected = Data([1, 2, 3])
        let connection = NSXPCConnection(serviceName: "quill.test")
        connection.exportedObject = XPCDataService(value: expected)

        let value: Data = try await connection.withContinuation { (service: XPCDataProvider, continuation) in
            service.getData(reply: continuation.resumingHandler)
        }

        #expect(value == expected)
    }

    @Test("CodeEdit document and window AppKit surface")
    @MainActor func codeEditDocumentAndWindowSurface() {
        final class CodeDocumentProbe: NSDocument {
            override class var autosavesInPlace: Bool { false }
            override var isDocumentEdited: Bool { false }
            override var autosavingFileType: String? { "public.swift-source" }

            override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
                super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
            }

            override func scheduleAutosaving() {}
            override func presentedItemDidChange() {}
            override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
                super.fileNameExtension(forType: typeName, saveOperation: saveOperation)
            }
        }

        final class WorkspaceDocumentProbe: NSDocument {
            var observedShouldClose = false
            override func shouldCloseWindowController(
                _ windowController: NSWindowController,
                delegate: Any?,
                shouldClose shouldCloseSelector: Selector?,
                contextInfo: UnsafeMutableRawPointer?
            ) {
                observedShouldClose = true
                super.shouldCloseWindowController(
                    windowController,
                    delegate: delegate,
                    shouldClose: shouldCloseSelector,
                    contextInfo: contextInfo
                )
            }
        }

        let document = CodeDocumentProbe()
        #expect(!CodeDocumentProbe.autosavesInPlace)
        #expect(document.autosavingFileType == "public.swift-source")
        document.updateChangeCount(.changeDone)
        #expect(!document.isDocumentEdited)
        document.updateChangeCount(withToken: "token", for: .autosaveInPlaceOperation)
        document.scheduleAutosaving()
        document.presentedItemDidChange()
        #expect(document.fileNameExtension(forType: "swift", saveOperation: .saveOperation) == "swift")
        let documentURL = URL(fileURLWithPath: "/tmp/quill-codeedit-document.swift")
        let openedDocument = try? CodeDocumentProbe(
            for: documentURL,
            withContentsOf: documentURL,
            ofType: "public.swift-source"
        )
        #expect(openedDocument?.fileURL == documentURL)
        #expect(openedDocument?.fileType == "public.swift-source")

        let window = NSWindow()
        window.setAccessibilityIdentifier("workspace")
        window.setAccessibilityDocument("/tmp/project")
        window.titlebarSeparatorStyle = .line
        #expect(window.accessibilityIdentifier == "workspace")
        #expect(window.accessibilityDocument == "/tmp/project")
        #expect(window.titlebarSeparatorStyle == .line)
        #expect(NSWindow.willCloseNotification.rawValue == "NSWindowWillCloseNotification")
        NSApplication.shared.keyWindow = window
        #expect(NSApplication.shared.target(forAction: Selector("closeCurrentTab:")) as? NSWindow === window)

        let trackingItem = NSTrackingSeparatorToolbarItem(
            identifier: NSToolbarItem.Identifier("ItemListTrackingSeparator"),
            splitView: NSSplitView(),
            dividerIndex: 1
        )
        #expect(trackingItem.itemIdentifier.rawValue == "ItemListTrackingSeparator")
        #expect(trackingItem.dividerIndex == 1)

        let openPanel = NSOpenPanel()
        openPanel.showsResizeIndicator = false
        #expect(!openPanel.showsResizeIndicator)

        #if os(Linux)
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-codeedit-plist-\(UUID().uuidString).plist")
        try? """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ProductBuildVersion</key>
            <string>25A1</string>
        </dict>
        </plist>
        """.write(to: plistURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: plistURL) }
        #expect((NSDictionary(contentsOf: plistURL, error: ())?["ProductBuildVersion"] as? String) == "25A1")
        #endif

        let workspace = WorkspaceDocumentProbe()
        var shouldClose = false
        withUnsafeMutablePointer(to: &shouldClose) { pointer in
            workspace.shouldCloseWindowController(
                NSWindowController(window: window),
                delegate: nil,
                shouldClose: nil,
                contextInfo: UnsafeMutableRawPointer(pointer)
            )
        }
        #expect(workspace.observedShouldClose)
        #expect(shouldClose)
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

    @Test("NSStringEncoding constants expose Apple UInt raw values")
    func stringEncodingConstantsExposeAppleUIntRawValues() {
        let utf8: UInt = NSUTF8StringEncoding
        let utf16BE: UInt = NSUTF16BigEndianStringEncoding
        let utf16LE: UInt = NSUTF16LittleEndianStringEncoding

        #expect(utf8 == String.Encoding.utf8.rawValue)
        #expect(utf16BE == String.Encoding.utf16BigEndian.rawValue)
        #expect(utf16LE == String.Encoding.utf16LittleEndian.rawValue)
    }

    @Test("NSBezierPath.transform(using:) mutates recorded path points")
    func bezierPathTransformUsingAffineTransform() {
        let path = NSBezierPath(rect: NSRect(x: 1, y: 2, width: 3, height: 4))
        path.transform(using: CGAffineTransform(translationByX: 10, byY: -1))
        #expect(path.bounds == NSRect(x: 11, y: 1, width: 3, height: 4))
    }

    @Test("CodeEdit text editor AppKit surface: floating subviews, safe area guide, font descriptor and line height")
    func codeEditTextEditorAppKitSurface() {
        let scrollView = NSScrollView(frame: .zero)
        let gutter = NSView(frame: .zero)
        scrollView.addFloatingSubview(gutter, for: .horizontal)
        #expect(scrollView.subviews.contains { $0 === gutter })
        #expect(scrollView.safeAreaLayoutGuide.owningView === scrollView)
        #expect(scrollView.safeAreaInsets.top == 0)
        #expect(scrollView.contentView.safeAreaLayoutGuide.owningView === scrollView.contentView)
        #expect(NSFont.systemFontSize(for: .small) == NSFont.smallSystemFontSize)

        let weight = NSFont.Weight(rawValue: 0.12)
        let width = NSFont.Width(rawValue: -0.13)
        let font = NSFont.systemFont(ofSize: 12, weight: weight, width: width)
        #expect(font.pointSize == 12)
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.selectorIdentifier: kStylisticAltOneOnSelector]],
            .fixedAdvance: CGFloat(6)
        ])
        #expect(NSFont(descriptor: descriptor, size: 0)?.pointSize == 12)
        #expect(NSLayoutManager().defaultLineHeight(for: font) == font.lineHeight)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        popup.autoenablesItems = false
        popup.contentTintColor = .tertiaryLabelColor
        #expect(popup.font?.pointSize == NSFont.smallSystemFontSize)
        #expect(!popup.autoenablesItems)
        #expect(popup.contentTintColor === NSColor.tertiaryLabelColor)

        let button = NSButton(frame: .zero)
        button.contentTintColor = .secondaryLabelColor
        button.sendAction(on: .leftMouseDown)
        #expect(button.contentTintColor === NSColor.secondaryLabelColor)
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

    @Test("NSTextStorage.edited(_:range:changeInLength:) + EditActions (WireGuard's ConfTextStorage)")
    func nsTextStorageEditActions() {
        // ConfTextStorage : NSTextStorage calls edited(.editedCharacters/.editedAttributes, …)
        // after mutating its backing NSMutableAttributedString.
        #expect(NSTextStorage.EditActions.editedCharacters != NSTextStorage.EditActions.editedAttributes)
        let both: NSTextStorage.EditActions = [.editedCharacters, .editedAttributes]
        #expect(both.contains(.editedCharacters) && both.contains(.editedAttributes))
        let storage = NSTextStorage(string: "") // corelibs designated init (init() isn't)
        storage.edited(.editedCharacters, range: NSRange(location: 0, length: 0), changeInLength: 0)
        storage.processEditing() // compile-stubs, callable

        let contentStorage = NSTextContentStorage()
        contentStorage.textStorage = storage
        #expect(contentStorage.textStorage === storage)
    }

    @Test("NSFontManager.convert/convertWeight + NSFontTraitMask + NSTextStorage() (ConfTextStorage shadow)")
    func confTextStorageShadowSurface() {
        // ConfTextStorage derives bold/italic fonts via NSFontManager + builds on
        // NSTextStorage's designated init().
        #expect(NSFontTraitMask.italicFontMask != NSFontTraitMask.boldFontMask)
        let fm = NSFontManager.shared
        let base = NSFont.systemFont(ofSize: 15)            // no-weight overload
        let mono = NSFont(name: "Menlo-Regular", size: 14)
        #expect(!fm.availableFontFamilies.isEmpty)
        #expect(fm.availableFontFamilies.contains("Menlo"))
        #expect(mono?.isFixedPitch == true)
        #expect((mono?.numberOfGlyphs ?? 0) > 26)
        #expect(mono?.withSize(18).isFixedPitch == true)
        #expect(NSAppearance.currentDrawing().name == .aqua)
        _ = NSColor.systemYellow
        _ = NSColor.linkColor
        _ = ImageResource.gitHubIcon
        _ = ImageResource.gitLabIcon
        _ = ImageResource.bitBucketIcon
        _ = fm.convertWeight(true, of: base)                // compile-stubs (return the font)
        _ = fm.convert(base, toHaveTrait: .italicFontMask)
        // NSTextStorage() — the new designated init() ConfTextStorage overrides.
        let storage = NSTextStorage()
        storage.edited(.editedAttributes, range: NSRange(location: 0, length: 0), changeInLength: 0)
        _ = storage
    }

    @Test("NSTextView init(frame:textContainer:) + preserved NSTextView()/(frame:) + edit hooks (ConfTextView)")
    func confTextViewShadowSurface() {
        // The new designated init ConfTextView uses:
        let tv = NSTextView(frame: .zero, textContainer: NSTextContainer())
        tv.isAutomaticDataDetectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.undoManager = UndoManager()
        #expect((tv as NSResponder).undoManager === tv.undoManager)
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
        scroll.scroll(scroll.contentView, to: NSPoint(x: 12, y: 34))
        #expect(scroll.contentView.bounds.origin == NSPoint(x: 12, y: 34))
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
        menu.addItem(NSMenuItem.separator())
        menu.setSubmenu(NSMenu(), for: item)
        // NSMenu's init() is convenience (init(title:) designated) → a subclass can declare
        // its own init() WITHOUT `override` (what WireGuard's MainMenu/StatusMenu rely on).
        let custom = MenuInitModelProbe()
        #expect(custom.title == "probe")

        #expect(menu.indexOfItem(withTitle: "New") == 0)
        #expect(menu.indexOfItem(withTitle: "Missing") == -1)

        let view = NSView()
        view.menu = menu
        #expect(view.menu === menu)
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
        // Darwin-only C the detectors call — compile-stubs, never executed on Linux.
        #expect(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) == 0)
        #expect(proc_pidpath(0, nil, 0) == 0)
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
}

/// Probes the NSMenu init-model fix: a subclass declaring `init()` (a new designated
/// init calling super.init(title:)) compiles WITHOUT an `override` keyword — exactly
/// as WireGuard's MainMenu/StatusMenu do.
private final class MenuInitModelProbe: NSMenu {
    init() { super.init(title: "probe") }
    required init(coder decoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
