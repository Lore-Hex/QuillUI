import Foundation
import Testing
import AppKit
import Account
import Articles
import ActivityLog
import Images
import NetNewsWireContext
import NetNewsWireSharedCore
import RSCore
import RSCoreResources
import RSTree
import SafariServices
import UniformTypeIdentifiers
import WebKit
@testable import NetNewsWireMacCore

@Suite("Upstream NetNewsWire Mac core slice", .serialized)
struct NetNewsWireMacCoreTests {
    private typealias MacAppDefaults = NetNewsWireMacCore.AppDefaults
    private typealias TreeNode = Node

    private enum SampleError: LocalizedError {
        case sample

        var errorDescription: String? {
            "sample error"
        }
    }

    @MainActor
    private func makeUpstreamMainWindowShell(unreadCount: Int = 7) -> NetNewsWireLinuxMainWindowHost {
        NetNewsWireLinuxMainWindowHost(unreadCount: unreadCount)
    }

    @Test("Mac AppDefaults registers, migrates, and persists user defaults")
    @MainActor func macAppDefaultsRegisterMigrateAndPersist() {
        let keys = [
            MacAppDefaults.Key.firstRunDate,
            MacAppDefaults.Key.refreshInterval,
            MacAppDefaults.Key.articleTextSize,
            MacAppDefaults.Key.sidebarFontSize,
            MacAppDefaults.Key.timelineSortDirection,
            MacAppDefaults.Key.timelineGroupByFeed,
            MacAppDefaults.Key.openInBrowserInBackground,
            MacAppDefaults.Key.currentThemeName,
            MacAppDefaults.Key.articleContentJavascriptEnabled,
        ]

        withPreservedDefaults(keys) {
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
            UserDefaults.standard.set(2, forKey: MacAppDefaults.Key.refreshInterval)

            let defaults = MacAppDefaults()
            #expect(defaults.refreshInterval == .every30Minutes)
            #expect(UserDefaults.standard.integer(forKey: MacAppDefaults.Key.refreshInterval) == defaults.refreshInterval.rawValue)

            defaults.registerDefaults()
            #expect(defaults.sidebarFontSize == .medium)
            #expect(defaults.timelineFontSize == .medium)
            #expect(defaults.detailFontSize == .medium)
            #expect(defaults.timelineSortDirection == .orderedDescending)
            #expect(!defaults.timelineGroupByFeed)
            #expect(defaults.currentThemeName == MacAppDefaults.defaultThemeName)
            #expect(defaults.isArticleContentJavascriptEnabled)

            defaults.articleTextSize = .xxlarge
            defaults.refreshInterval = .every8Hours
            defaults.openInBrowserInBackground = true
            #expect(defaults.articleTextSize == .xxlarge)
            #expect(defaults.refreshInterval == .every8Hours)
            #expect(defaults.openInBrowserInBackground)

            #expect(defaults.actualFontSize(for: .medium) > defaults.actualFontSize(for: .small))
            #expect(defaults.actualFontSize(for: .large) > defaults.actualFontSize(for: .medium))
            #expect(defaults.actualFontSize(for: .veryLarge) > defaults.actualFontSize(for: .large))
        }
    }

    @Test("Browser title follows open-in-background default")
    @MainActor func browserTitleReflectsOpenInBackgroundPreference() {
        let keys = [
            MacAppDefaults.Key.openInBrowserInBackground,
        ]

        withPreservedDefaults(keys) {
            UserDefaults.standard.removeObject(forKey: MacAppDefaults.Key.openInBrowserInBackground)
            UserDefaults.standard.set(false, forKey: MacAppDefaults.Key.openInBrowserInBackground)
            #expect(Browser.titleForOpenInBrowserInverted == "Open in Browser in Background")

            UserDefaults.standard.set(true, forKey: MacAppDefaults.Key.openInBrowserInBackground)
            #expect(Browser.titleForOpenInBrowserInverted == "Open in Browser in Foreground")
        }
    }

    @Test("Log text style exposes upstream paragraph metrics")
    @MainActor func logTextStyleParagraphMetrics() {
        #expect(LogTextStyle.fontSize == 16.0)
        #expect(LogTextStyle.textContainerInset == 8.0)
        #expect(LogTextStyle.aboveCenterOffset == 40.0)
        #expect(LogTextStyle.entryParagraphStyle.lineSpacing == 4.0)
        #expect(LogTextStyle.entryParagraphStyle.paragraphSpacing == 7.0)
    }

    @Test("Log text views resize their text container and copy nonempty contents")
    @MainActor func logTextViewHelpers() {
        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let savedString {
                pasteboard.setString(savedString, forType: .string)
            }
        }

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.updateContainerSizeForLiveResize()
        #expect(textView.textContainer?.size.width == 184)
        #expect(textView.textContainer?.size.height == .greatestFiniteMagnitude)

        pasteboard.clearContents()
        pasteboard.setString("prior", forType: .string)
        textView.string = ""
        textView.copyAllToPasteboard()
        #expect(pasteboard.string(forType: .string) == "prior")

        textView.string = "copied log"
        textView.copyAllToPasteboard()
        #expect(pasteboard.string(forType: .string) == "copied log")
    }

    @Test("Log windows can be nudged above center")
    @MainActor func logWindowCenterAboveCenter() {
        let window = NSWindow(
            contentRect: NSRect(x: 10, y: 20, width: 300, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.centerAboveCenter(by: 40)
        #expect(window.frame.origin.x == 10)
        #expect(window.frame.origin.y == 60)
        #expect(window.frame.size.width == 300)
        #expect(window.frame.size.height == 200)
    }

    @Test("Error handler logs and routes presentation through NSApplication")
    @MainActor func errorHandlerPresentation() async {
        let app = NSApplication.shared
        app.quillClearPresentedErrors()
        defer { app.quillClearPresentedErrors() }

        ErrorHandler.log(SampleError.sample)
        ErrorHandler.present(SampleError.sample)
        await Task.yield()

        #expect(app.quillPresentedErrors.count == 1)
        #expect(app.quillPresentedErrors.first?.localizedDescription == "sample error")
    }

    @Test("Preferences background views expose AppKit drawing behavior")
    @MainActor func preferencesBackgroundDrawing() throws {
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let controls = PreferencesControlsBackgroundView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))
        #expect(controls.isFlipped)
        #expect(controls.isOpaque)
        #expect(controls.bounds.size.width == 240)
        #expect(controls.bounds.size.height == 80)

        controls.draw(NSRect(x: 12, y: 6, width: 100, height: 30))
        controls.effectiveAppearance = darkAppearance
        controls.draw(controls.bounds)

        let table = PreferencesTableViewBackgroundView(frame: NSRect(x: 0, y: 0, width: 160, height: 48))
        #expect(!table.isFlipped)
        #expect(!table.isOpaque)
        #expect(table.bounds.size.width == 160)
        #expect(table.bounds.size.height == 48)
        #expect(table.lightBorderColor.redComponent != table.darkBorderColor.redComponent)

        table.draw(NSRect(x: 4, y: 8, width: 80, height: 20))
        table.effectiveAppearance = darkAppearance
        table.draw(table.bounds)
    }

    @Test("About link controls highlight and restore linked text")
    @MainActor func aboutLinkControlsHighlightAndRestore() throws {
        let url = try #require(URL(string: "https://netnewswire.com/"))
        let linkRange = NSRange(location: 0, length: 4)
        let attributed = NSMutableAttributedString(string: "link text")
        attributed.addAttribute(.link, value: url, range: linkRange)
        attributed.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: linkRange)

        let label = LinkLabel(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        label.font = NSFont.systemFont(ofSize: 13)
        label.attributedStringValue = attributed
        label.resetCursorRects()
        #expect(label.quillCursorRects.count == 1)
        #expect(label.quillCursorRects.first?.rect == label.bounds)

        let labelDown = NSEvent()
        labelDown.locationInWindow = NSPoint(x: 5, y: 5)
        label.mouseDown(with: labelDown)
        let highlightedLabelColor = try #require(label.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(highlightedLabelColor.redComponent == NSColor.systemOrange.redComponent)
        #expect(label.attributedStringValue.attribute(.link, at: 0, effectiveRange: nil) == nil)

        let labelDragOut = NSEvent()
        labelDragOut.locationInWindow = NSPoint(x: 200, y: 200)
        label.mouseDragged(with: labelDragOut)
        #expect(label.attributedStringValue.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)

        let textView = LinksTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        textView.textStorage = NSTextStorage(attributedString: attributed)

        let textDown = NSEvent()
        textDown.locationInWindow = NSPoint(x: 7, y: 0)
        textView.mouseDown(with: textDown)
        #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) == nil)
        let highlightedTextColor = try #require(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(highlightedTextColor.redComponent == NSColor.systemOrange.redComponent)

        let textDragOut = NSEvent()
        textDragOut.locationInWindow = NSPoint(x: 120, y: 0)
        textView.mouseDragged(with: textDragOut)
        #expect(textView.textStorage?.attribute(.link, at: 0, effectiveRange: nil) as? URL == url)
    }

    @Test("About window controller configures translucent window and app metadata")
    @MainActor func aboutWindowControllerConfiguresUI() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let bundleVersion = try #require(info["CFBundleShortVersionString"] as? String)
        let bundleBuild = try #require(info["CFBundleVersion"] as? String)
        let bundleCopyright = try #require(info["NSHumanReadableCopyright"] as? String)

        let app = NSApplication.shared
        let savedIcon = app.applicationIconImage
        let icon = NSImage(size: NSSize(width: 64, height: 64))
        app.applicationIconImage = icon
        defer { app.applicationIconImage = savedIcon }

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView

        let controller = AboutWindowController(window: window)
        controller.appIconImageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        controller.appTitleLabel = NSTextField(labelWithString: "")
        controller.versionLabel = NSTextField(labelWithString: "")
        controller.copyrightLabel = LinksTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        controller.websiteLabel = LinkLabel(frame: NSRect(x: 0, y: 0, width: 160, height: 22))
        controller.creditsTextView = LinksTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 80))

        controller.windowDidLoad()

        #expect(window.isOpaque == false)
        #expect(window.backgroundColor.alphaComponent == 0)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.styleMask.contains(.fullSizeContentView))
        let effectView = contentView.subviews.first
        #expect(effectView is NSVisualEffectView || effectView is NSGlassEffectView)

        #expect(controller.appIconImageView.image === icon)
        #expect(controller.versionLabel.stringValue == "Version \(bundleVersion) (Build \(bundleBuild))")
        #expect(controller.creditsTextView.string == "Credits not available.")
        #expect(controller.copyrightLabel.textStorage?.string == bundleCopyright)
        let brentRange = try #require(bundleCopyright.range(of: "Brent Simmons"))
        #expect(controller.copyrightLabel.textStorage?.attribute(.link, at: NSRange(brentRange, in: bundleCopyright).location, effectiveRange: nil) as? URL == URL(string: "https://inessential.com/"))

        let website = controller.websiteLabel.attributedStringValue
        #expect(website.string == "netnewswire.com")
        #expect(website.attribute(.link, at: 0, effectiveRange: nil) as? URL == URL(string: "https://netnewswire.com/"))
        #expect(website.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("Article extractor button preserves image, progress, and accessibility states")
    @MainActor func articleExtractorButtonStates() {
        let button = ArticleExtractorButton(frame: NSRect(x: 0, y: 0, width: 32, height: 32))

        #expect(button.wantsLayer)
        #expect(button.bezelStyle == .texturedRounded)
        #expect(button.imageScaling == .scaleProportionallyDown)
        #expect(button.image != nil)
        #if os(Linux)
        #expect(button.image?.data?.isEmpty == false)
        #endif
        #expect(button.accessibilityLabel() == "Reader View")

        button.buttonState = .animated
        #expect(button.image == nil)
        #expect(!button.isEnabled)
        #expect(button.accessibilityLabel() == "Processing - Reader View")

        button.buttonState = .on
        #expect(button.image != nil)
        #if os(Linux)
        #expect(button.image?.data?.isEmpty == false)
        #endif
        #expect(button.isEnabled)
        #expect(button.accessibilityLabel() == "Selected - Reader View")

        button.buttonState = .error
        #expect(button.image != nil)
        #if os(Linux)
        #expect(button.image?.data?.isEmpty == false)
        #endif
        #expect(button.isEnabled)
        #expect(button.accessibilityLabel() == "Error - Reader View")

        button.buttonState = .off
        #expect(button.image != nil)
        #if os(Linux)
        #expect(button.image?.data?.isEmpty == false)
        #endif
        #expect(button.isEnabled)
        #expect(button.accessibilityLabel() == "Reader View")
    }

    #if os(Linux)
    @Test("NetNewsWire Mac asset catalog images resolve to bundled bytes")
    @MainActor func macAssetCatalogImagesResolve() {
        #expect(hasBytes(Assets.Images.accountLocal))
        #expect(hasBytes(Assets.Images.articleExtractorOn))
        #expect(hasBytes(Assets.Images.articleExtractorOff))
        #expect(hasBytes(Assets.Images.articleExtractorError))
        #expect(hasBytes(Assets.Images.markAllAsRead))
        #expect(hasBytes(Assets.Images.timelineStarSelected))
        #expect(hasBytes(Assets.Images.timelineStarUnselected))

        #expect(data(Assets.Images.accountLocal, hasPrefix: "%PDF"))
        #expect(data(Assets.Images.articleExtractorError, hasPrefix: "%PDF"))
        #expect(data(Assets.Images.timelineStarUnselected, hasPrefix: "%PDF"))
        #expect(data(Assets.Images.articleExtractorOn, hasPrefix: "<?xml"))
        #expect(data(Assets.Images.markAllAsRead, hasPrefix: "<?xml"))
    }

    @Test("NetNewsWire Mac app icon resolves from AppIcon asset catalog")
    @MainActor func macAppIconResolvesFromAssetCatalog() {
        let namedIcon = NSImage(named: NSImage.applicationIconName)
        #expect(hasBytes(namedIcon))
        #expect(hasPNGSignature(namedIcon))
        #expect(namedIcon?.data == NSApp.applicationIconImage?.data)
    }

    @Test("NetNewsWire Mac asset catalog colors resolve to bundled RGBA values")
    @MainActor func macAssetCatalogColorsResolve() {
        #expect(color(NSColor(named: "AccentColor"), equals: [0.031, 0.416, 0.933, 1]))
        #expect(color(NSColor(named: "StarColor"), equals: [0.976, 0.776, 0.204, 1]))
        #expect(color(NSColor(named: "SidebarUnreadCountBackground"), equals: [0, 0, 0, 0.5]))
        #expect(color(NSColor(named: "SidebarUnreadCountText"), equals: [1, 1, 1, 0.9]))
        #expect(color(NSColor(named: "timelineSeparatorColor"), equals: [0.9, 0.9, 0.9, 1]))
        #expect(color(NSColor(named: "iconLightBackgroundColor"), equals: [
            242.0 / 255.0,
            242.0 / 255.0,
            242.0 / 255.0,
            1
        ]))
        #expect(color(NSColor(named: "DetailStatusBarBackground"), equals: [0.94, 0.94, 0.94, 1]))
    }
    #endif

    @Test("Crash report window controller loads crash text and gates send actions")
    @MainActor func crashReportWindowControllerSurface() throws {
        let controller = CrashReportWindowController(crashLogText: "crash log")
        let textView = NSTextView()
        controller.sendCrashLogButton = NSButton()
        controller.dontSendButton = NSButton()
        controller.textView = textView
        controller.testing = true

        #expect(textView.string == "crash log")
        #expect(textView.textContainerInset == NSSize(width: 5, height: 5))
        let font = try #require(textView.font)
        #expect(font.fontDescriptor.symbolicTraits.contains(.monoSpace))

        controller.sendCrashReport(nil)
        #expect(!controller.sendCrashLogButton.isEnabled)
        #expect(!controller.dontSendButton.isEnabled)
    }

    @Test("Safari extension handler routes toolbar and validation messages")
    @MainActor func safariExtensionHandlerSurface() throws {
        let handler = SafariExtensionHandler()
        let page = SFSafariPage(properties: SFSafariPageProperties(isActive: true))
        let tab = SFSafariTab(activePage: page)
        let window = SFSafariWindow(activeTab: tab)

        handler.toolbarItemClicked(in: window)
        #expect(page.dispatchedMessages.last?.name == "toolbarButtonClicked")

        var validation: (Bool, String)?
        handler.validateToolbarItem(in: window) { shouldValidate, message in
            validation = (shouldValidate, message)
        }

        let ping = try #require(page.dispatchedMessages.last)
        #expect(ping.name == "ping")
        let validationID = try #require(ping.userInfo["validationID"])
        #expect(!validationID.isEmpty)

        handler.messageReceived(
            withName: "pong",
            from: page,
            userInfo: ["validationID": validationID, "shouldValidate": true]
        )
        #expect(validation?.0 == true)
        #expect(validation?.1 == "")
        #expect(SafariExtensionHandler.gPingPongMap[validationID] == nil)
    }

    @Test("App delegate keyboard shortcuts action loads bundled HTML")
    @MainActor func appDelegateKeyboardShortcutsWindowSurface() throws {
        let delegate = NetNewsWireMacCore.AppDelegate()

        delegate.showKeyboardShortcutsWindow(nil as Any?)

        let controllerValue = try #require(Mirror(reflecting: delegate).children.first {
            $0.label == "keyboardShortcutsWindowController"
        }?.value)
        let controller = try #require(unwrapOptional(controllerValue) as? WebViewWindowController)
        let displayedPath = try #require(controller.displayedPath)

        #expect(controller.window?.title == "Keyboard Shortcuts")
        #expect(displayedPath.hasSuffix("KeyboardShortcuts.html"))
        #expect(try String(contentsOfFile: displayedPath, encoding: .utf8).contains("Keyboard Shortcuts"))
    }

    @Test("Scripting command helpers and scriptable account specifiers preserve upstream model")
    @MainActor func scriptingCommandSurface() throws {
        try withFreshAccountManager { manager in
            let scriptableAccount = ScriptableAccount(manager.defaultAccount)
            let specifier = try #require(scriptableAccount.objectSpecifier as? NSUniqueIDSpecifier)
            #expect(specifier.key == "accounts")
            #expect(specifier.uniqueID as? String == manager.defaultAccount.accountID)

            let event = NSAppleEventDescriptor(eventClass: kInternetEventClass, eventID: kAEGetURL)
            event.setParam(NSAppleEventDescriptor(string: "feed:https://example.com/feed.xml"), forKeyword: keyDirectObject)
            let command = NetNewsWireCreateElementCommand(
                arguments: ["ObjectClass": Int("Feed".fourCharCode)],
                evaluatedArguments: ["KeyDictionary": ["name": "Example Feed"]],
                appleEvent: event,
                createClassDescription: NSScriptClassDescription(className: "feed")
            )

            #expect(command.isCreateCommand(forClass: "Feed"))
            #expect(!command.isCreateCommand(forClass: "fold"))
            #expect(command.property(forKey: "name") as? String == "Example Feed")
            let (account, folder) = command.accountAndFolderForNewChild()
            #expect(account === manager.defaultAccount)
            #expect(folder == nil)

            let exists = NetNewsWireExistsCommand()
            #expect((exists.performDefaultImplementation() as? NSNumber)?.boolValue == true)
        }
    }

    @Test("Main window article support resolves feeds through upstream AccountManager")
    @MainActor func mainWindowArticleFeedResolver() {
        let article = Article(
            accountID: "missing-account",
            articleID: nil,
            feedID: "missing-feed",
            uniqueID: "article-1",
            title: "Missing feed",
            contentHTML: nil,
            contentText: nil,
            markdown: nil,
            url: nil,
            externalURL: nil,
            summary: nil,
            imageURL: nil,
            datePublished: nil,
            dateModified: nil,
            authors: nil,
            status: ArticleStatus(articleID: "article-1", read: false, starred: false, dateArrived: Date())
        )

        #expect(article.quillMainWindowFeed == nil)
    }

    @Test("Current activity model and window expose upstream display behavior")
    @MainActor func currentActivityModelAndWindowBehavior() {
        #expect(CurrentActivityViewModel.symbolName(for: .pending) == "circle")
        #expect(CurrentActivityViewModel.symbolName(for: .running) == "circle.fill")
        #expect(CurrentActivityViewModel.symbolName(for: .completed) == "checkmark.circle.fill")
        #expect(CurrentActivityViewModel.symbolName(for: .failed) == "xmark.circle.fill")
        #expect(CurrentActivityViewModel.accessibilityLabel(for: .running) == "Running")

        let feedActivity = Activity(
            id: 1,
            owner: .account(accountID: "account-1", displayName: "Example Account"),
            kind: .refreshFeedContent(feedURL: "https://example.com/feed.xml"),
            detail: "Example Feed"
        )
        let feedText = CurrentActivityViewModel.displayText(for: feedActivity)
        #expect(feedText.title == "Example Feed")
        #expect(feedText.detail == "https://example.com/feed.xml")

        let finderActivity = Activity(
            id: 2,
            owner: .feedFinder,
            kind: .findFeed(urlString: "https://example.com/"),
            detail: nil
        )
        let finderText = CurrentActivityViewModel.displayText(for: finderActivity)
        #expect(finderText.title == "Finding feed")
        #expect(finderText.detail == "https://example.com/")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = CurrentActivityWindowController(window: window)
        controller.windowDidLoad()
        #expect(window.delegate === controller)

        window.isVisible = true
        controller.saveState()
        #expect(CurrentActivityWindowController.shouldOpenAtStartup)

        window.isVisible = false
        controller.saveState()
        #expect(!CurrentActivityWindowController.shouldOpenAtStartup)
    }

    @Test("Account stats totals and window state stay usable in the Mac core slice")
    @MainActor func accountStatsTotalsAndWindowBehavior() {
        let rows = [
            AccountStatsRowData(
                accountID: "account-1",
                name: "Local",
                typeName: "On My Mac",
                isActive: true,
                feedCount: 2,
                folderCount: 1,
                articleCount: 20,
                statusesCount: 18,
                unreadCount: 5,
                starredCount: 3,
                databaseSizeBytes: 1_024
            ),
            AccountStatsRowData(
                accountID: "account-2",
                name: "Cloud",
                typeName: "Cloud",
                isActive: false,
                feedCount: 4,
                folderCount: 2,
                articleCount: 40,
                statusesCount: 37,
                unreadCount: 9,
                starredCount: 1,
                databaseSizeBytes: 4_096
            ),
        ]
        let totals = AccountStatsTotals(rows: rows)
        #expect(totals.feedCount == 6)
        #expect(totals.folderCount == 3)
        #expect(totals.articleCount == 60)
        #expect(totals.statusesCount == 55)
        #expect(totals.unreadCount == 14)
        #expect(totals.starredCount == 4)
        #expect(totals.databaseSizeBytes == 5_120)

        let emptyTotals = AccountStatsTotals(rows: [])
        #expect(emptyTotals.feedCount == 0)
        #expect(emptyTotals.databaseSizeBytes == 0)

        withPreservedDefaults(["AccountStatsWindowIsOpen"]) {
            UserDefaults.standard.removeObject(forKey: "AccountStatsWindowIsOpen")

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 320),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let controller = AccountStatsWindowController(window: window)
            controller.windowDidLoad()

            let tableView = UtilityTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
            tableView.sortDescriptors = [NSSortDescriptor.quillKey("feedCount", ascending: false)]
            controller.tableView(tableView, sortDescriptorsDidChange: [])
            #expect(controller.numberOfRows(in: tableView) == 0)

            window.isVisible = true
            controller.saveState()
            #expect(AccountStatsWindowController.shouldOpenAtStartup)

            window.isVisible = false
            controller.saveState()
            #expect(!AccountStatsWindowController.shouldOpenAtStartup)
        }
    }

    @Test("Dinosaurs window uses AppKit compatibility hooks without account data")
    @MainActor func dinosaursWindowBehaviorAndCompatibilityHooks() {
        withPreservedDefaults(["DinosaurWindowIsOpen", "DinosaurMonthThreshold"]) {
            UserDefaults.standard.removeObject(forKey: "DinosaurWindowIsOpen")
            UserDefaults.standard.removeObject(forKey: "DinosaurMonthThreshold")

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            let controller = DinosaursWindowController(window: window)
            controller.windowDidLoad()
            #expect(window.delegate === controller)
            #expect(window.undoManager === controller.windowWillReturnUndoManager(window))

            let tableView = UtilityTableView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
            tableView.sortDescriptors = [NSSortDescriptor.quillKey(DinosaurSortKey.lastArticleDate.rawValue, ascending: false)]
            controller.tableView(tableView, sortDescriptorsDidChange: [])
            #expect(controller.numberOfRows(in: tableView) == 0)

            window.isVisible = true
            controller.saveState()
            #expect(DinosaursWindowController.shouldOpenAtStartup)

            window.isVisible = false
            controller.saveState()
            #expect(!DinosaursWindowController.shouldOpenAtStartup)

            #expect(Notification.Name.FaviconDidBecomeAvailable.rawValue == "FaviconDidBecomeAvailableNotification")
        }
    }

    @Test("Add folder window controller populates account menu and validates folder names")
    @MainActor func addFolderWindowControllerSurface() throws {
        try withPreservedDefaults([AppDefaults.Key.addFolderAccountID]) {
            try withFreshAccountManager { manager in
                let controller = AddFolderWindowController(window: NSWindow())
                controller.folderNameTextField = NSTextField(frame: .zero)
                controller.accountPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
                controller.addFolderButton = NSButton(frame: .zero)

                controller.windowDidLoad()

                #expect(controller.accountPopupButton.numberOfItems == manager.sortedActiveAccounts.count)
                #expect(controller.accountPopupButton.itemArray.map(\.title) == manager.sortedActiveAccounts.map(\.nameForDisplay))

                controller.folderNameTextField.stringValue = ""
                controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.folderNameTextField))
                #expect(!controller.addFolderButton.isEnabled)

                controller.folderNameTextField.stringValue = "News"
                controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.folderNameTextField))
                #expect(controller.addFolderButton.isEnabled)
            }
        }
    }

    @Test("Folder tree menu builds account and folder choices and selects defaults")
    @MainActor func folderTreeMenuSurface() throws {
        try withFreshAccountManager { manager in
            let account = manager.defaultAccount
            let folder = try #require(account.ensureFolder(with: "News"))
            let treeDelegate = FolderTreeControllerDelegate()
            let treeController = TreeController(delegate: treeDelegate)

            let menu = FolderTreeMenu.createFolderPopupMenu(with: treeController.rootNode)
            let accountItem = try #require(menu.items.first { ($0.representedObject as? Account) === account })
            let folderItem = try #require(menu.items.first { ($0.representedObject as? Folder) === folder })
            #expect(accountItem.title == account.nameForDisplay)
            #expect(folderItem.title == folder.nameForDisplay)
            #expect(folderItem.indentationLevel == 1)

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.menu = menu
            FolderTreeMenu.select(account: account, folder: folder, in: popup)
            let selectedFolder = try #require(popup.selectedItem?.representedObject as? Folder)
            #expect(selectedFolder === folder)

            FolderTreeMenu.select(account: account, folder: nil, in: popup)
            let selectedAccount = try #require(popup.selectedItem?.representedObject as? Account)
            #expect(selectedAccount === account)
        }
    }

    @Test("Add feed window controller validates URL, title, and container selection")
    @MainActor func addFeedWindowControllerSurface() throws {
        try withFreshAccountManager { manager in
            let account = manager.defaultAccount
            let folder = try #require(account.ensureFolder(with: "Reading"))
            let treeController = TreeController(delegate: FolderTreeControllerDelegate())
            let delegate = RecordingAddFeedDelegate()
            let controller = AddFeedWindowController(
                urlString: "https://example.com/feed.xml",
                name: " Example Feed ",
                account: account,
                folder: folder,
                folderTreeController: treeController,
                delegate: delegate
            )
            controller.urlTextField = NSTextField(frame: .zero)
            controller.nameTextField = NSTextField(frame: .zero)
            controller.addButton = NSButton(frame: .zero)
            controller.folderPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)

            let sheet = try #require(controller.window)
            #expect(sheet.title == "AddFeedSheet")
            #expect(controller.urlTextField.stringValue == "https://example.com/feed.xml")
            #expect(controller.nameTextField.stringValue == " Example Feed ")
            #expect(controller.addButton.isEnabled)
            #expect(controller.folderPopupButton.selectedItem?.representedObject as? Folder === folder)

            controller.addFeed(nil)
            #expect(delegate.windowController === controller)
            #expect(delegate.enteredURL?.absoluteString == "https://example.com/feed.xml")
            #expect(delegate.enteredTitle == "Example Feed")
            #expect(delegate.container as? Folder === folder)

            IndeterminateProgressController.beginProgressWithMessage("Finding feed")
            #expect(IndeterminateProgressController.isRunning)
            #expect(IndeterminateProgressController.message == "Finding feed")
            IndeterminateProgressController.endProgress()
            #expect(!IndeterminateProgressController.isRunning)
            #expect(IndeterminateProgressController.message == nil)

            let cancelDelegate = RecordingAddFeedDelegate()
            let cancelController = AddFeedWindowController(
                urlString: nil,
                name: nil,
                account: account,
                folder: nil,
                folderTreeController: treeController,
                delegate: cancelDelegate
            )
            cancelController.urlTextField = NSTextField(frame: .zero)
            cancelController.nameTextField = NSTextField(frame: .zero)
            cancelController.addButton = NSButton(frame: .zero)
            cancelController.folderPopupButton = NSPopUpButton(frame: .zero, pullsDown: false)
            _ = cancelController.window
            cancelController.cancel(nil)
            #expect(cancelDelegate.didCancel)
        }
    }

    @Test("OPML window controllers populate account menus and accept OPML file types")
    @MainActor func opmlWindowControllerSurface() throws {
        try withPreservedDefaults([MacAppDefaults.Key.importOPMLAccountID, MacAppDefaults.Key.exportOPMLAccountID]) {
            try withFreshAccountManager { manager in
                MacAppDefaults.shared.exportOPMLAccountID = manager.defaultAccount.accountID
                let exportController = ExportOPMLWindowController()
                exportController.accountPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)

                let exportWindow = try #require(exportController.window)
                #expect(exportWindow.title == "ExportOPMLSheet")
                #expect(exportController.accountPopUpButton.numberOfItems == manager.sortedAccounts.count)
                #expect(exportController.accountPopUpButton.itemArray.map(\.title) == manager.sortedAccounts.map(\.nameForDisplay))
                let selectedExportAccount = try #require(exportController.accountPopUpButton.selectedItem?.representedObject as? Account)
                #expect(selectedExportAccount === manager.defaultAccount)

                MacAppDefaults.shared.importOPMLAccountID = manager.defaultAccount.accountID
                let importController = ImportOPMLWindowController()
                importController.accountPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)

                let importWindow = try #require(importController.window)
                #expect(importWindow.title == "ImportOPMLSheet")
                #expect(importController.accountPopUpButton.numberOfItems == manager.sortedActiveAccounts.count)
                #expect(importController.accountPopUpButton.itemArray.map(\.title) == manager.sortedActiveAccounts.map(\.nameForDisplay))
                let selectedImportAccount = try #require(importController.accountPopUpButton.selectedItem?.representedObject as? Account)
                #expect(selectedImportAccount === manager.defaultAccount)

                let openPanel = NSOpenPanel()
                openPanel.acceptOPML()
                #expect(openPanel.allowedFileTypes == ["opml", "xml"])
            }
        }
    }

    @Test("NNW3 document converts subscription plists to escaped OPML")
    @MainActor func nnw3DocumentConvertsSubscriptionsPlist() throws {
        let plist: [[String: Any]] = [
            [
                "name": "News & Tech",
                "isContainer": true,
                "childrenArray": [
                    [
                        "name": "Swift <Daily>",
                        "home": "https://example.com/?a=1&b=2",
                        "rss": "https://example.com/feed?x=1&y=2",
                    ],
                ],
            ],
            [
                "name": "Empty \"Folder\"",
                "isContainer": true,
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NNW3Subscriptions-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)

        let document = try #require(NNW3Document(subscriptionsPlistURL: url))
        let opml = document.OPMLString(indentLevel: 0)

        #expect(opml.contains("<title>NetNewsWire 3 Subscriptions</title>"))
        #expect(opml.contains("News &amp; Tech"))
        #expect(opml.contains("Swift &lt;Daily&gt;"))
        #expect(opml.contains("https://example.com/?a=1&amp;b=2"))
        #expect(opml.contains("https://example.com/feed?x=1&amp;y=2"))
        #expect(opml.contains("Empty &quot;Folder&quot;"))
        #expect(NNW3Document(subscriptionsPlistURL: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).plist")) == nil)
    }

    @Test("NNW3 import accessory builds account popup without nibs")
    @MainActor func nnw3ImportAccessorySurface() throws {
        try withPreservedDefaults([MacAppDefaults.Key.importOPMLAccountID]) {
            try withFreshAccountManager { manager in
                MacAppDefaults.shared.importOPMLAccountID = manager.defaultAccount.accountID

                let controller = NNW3OpenPanelAccessoryViewController()
                let contentView = controller.view

                #expect(contentView.subviews.contains { $0 === controller.accountPopUpButton })
                #expect(controller.accountPopUpButton.numberOfItems == manager.sortedActiveAccounts.count)
                #expect(controller.accountPopUpButton.itemArray.map(\.title) == manager.sortedActiveAccounts.map(\.nameForDisplay))
                #expect(controller.selectedAccount === manager.defaultAccount)

                NNW3ImportController.askUserToImportNNW3Subscriptions(window: NSWindow())
            }
        }
    }

    @Test("Stepper and URL pasteboard writer cover Dinosaurs support shims")
    @MainActor func appKitStepperAndURLPasteboardWriter() {
        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 3
        stepper.increment = 2
        stepper.integerValue = 2
        stepper.incrementValue()
        #expect(stepper.integerValue == 3)

        stepper.decrementValue()
        #expect(stepper.integerValue == 1)

        stepper.valueWraps = true
        stepper.integerValue = 3
        stepper.incrementValue()
        #expect(stepper.integerValue == 1)

        stepper.decrementValue()
        #expect(stepper.integerValue == 3)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "NetNewsWireMacCoreDinosaursPasteboard"))
        URLPasteboardWriter.write(urlString: "https://example.com/feed.xml", to: pasteboard)
        #expect(pasteboard.string(forType: .URL) == "https://example.com/feed.xml")
        #expect(pasteboard.string(forType: .string) == "https://example.com/feed.xml")
        #expect(pasteboard.types()?.contains(.URL) == true)
        #expect(pasteboard.types()?.contains(.string) == true)

        let writer = URLPasteboardWriter(urlString: "http://[invalid")
        #expect(writer.writableTypes(for: pasteboard) == [.string])
        #expect(writer.pasteboardPropertyList(forType: .string) as? String == "http://[invalid")
        #expect(writer.pasteboardPropertyList(forType: .pdf) == nil)
    }

    @Test("CloudKit stats model exposes unavailable iCloud state and cleanup formatting")
    @MainActor func cloudKitStatsModelUnavailableStateAndFormatting() {
        withPreservedDefaults([AccountManager.syncArticleContentForUnreadArticlesKey]) {
            UserDefaults.standard.set(false, forKey: AccountManager.syncArticleContentForUnreadArticlesKey)

            let stats = CloudKitStats(
                statusCount: 12_107,
                starredStatusCount: 5,
                unreadStatusCount: 247,
                readStatusCount: 11_855,
                staleStatusCount: 876,
                articleCount: 8_387,
                starredArticleCount: 5,
                unreadArticleCount: 212,
                readArticleCount: 8_170
            )
            let plan = stats.cleanUpPlan(syncUnreadContent: false)
            #expect(plan.staleStatusCount == 876)
            #expect(plan.readContentCount == 8_170)
            #expect(plan.unreadContentCount == 212)
            #expect(plan.totalCount == 8_382)
            #expect(!plan.isEmpty)

            let model = CloudKitStatsViewModel()
            var changeCount = 0
            model.onChange = {
                changeCount += 1
            }

            model.stats = stats
            model.fetchStatus = .completed
            #expect(model.canCleanUp)
            #expect(model.statsText.contains("Status Records: 12,107"))
            #expect(model.statsText.contains("Read: 11,855"))
            #expect(model.cleanUpPlan.totalCount == 8_382)
            #expect(changeCount >= 2)

            let progress = CloudKitCleanUpProgress(
                phase: .deletingUnreadContent,
                staleStatusDeleted: 0,
                readContentDeleted: 9,
                unreadContentDeleted: 2
            )
            model.cleanUpStatus = .cleaning(progress)
            #expect(model.cleanUpStatus.isCleaning)
            #expect(model.cleanUpStatus.isActive)
            #expect(model.cleanUpStatsText.contains("Read Content Deleted: 9"))
            #expect(model.cleanUpStatsText.contains("Unread Content Deleted: 2"))

            model.cancelCleanUp()
            #expect(model.cleanUpStatus.isCanceled)
            #expect(model.cleanUpStatus.progress?.totalDeleted == 11)

            model.fetch()
            #expect(model.fetchStatus.fetchError?.localizedDescription == "No iCloud account found.")

            model.cleanUp()
            #expect(model.cleanUpStatus.cleanUpError?.localizedDescription == "No iCloud account found.")
        }
    }

    @Test("CloudKit stats window controller builds the upstream AppKit controller")
    @MainActor func cloudKitStatsWindowControllerLoadsRealController() throws {
        let controller = CloudKitStatsWindowController()
        let window = try #require(controller.window)

        #expect(window.frame.size.width == 400)
        #expect(window.frame.size.height == 530)
        #expect(window.title == "iCloud Storage Stats")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.contentViewController is CloudKitStatsViewController)
        #expect(window.representedURL == URL(string: "https://icloud.com/"))
        #expect(window.standardWindowButton(.documentIconButton)?.image != nil)

        controller.showWindow(nil)
        #expect(window.isVisible)
    }

    @Test("Inspector fallback controller updates empty and multiple-object states")
    @MainActor func inspectorFallbackControllerTextState() {
        let controller = NothingInspectorViewController()
        let nothingLabel = NSTextField(labelWithString: "Nothing")
        let multipleLabel = NSTextField(labelWithString: "Multiple")
        controller.nothingTextField = nothingLabel
        controller.multipleTextField = multipleLabel

        controller.objects = nil
        controller.viewDidLoad()
        #expect(!nothingLabel.isHidden)
        #expect(multipleLabel.isHidden)
        #expect(controller.canInspect([]))
        #expect(controller.windowTitle == "Inspector")

        controller.objects = [1, 2]
        #expect(nothingLabel.isHidden)
        #expect(!multipleLabel.isHidden)

        controller.objects = ["single"]
        #expect(!nothingLabel.isHidden)
        #expect(multipleLabel.isHidden)
    }

    @Test("Inspector window selects fallback and persists AppKit-compatible state")
    @MainActor func inspectorWindowFallbackAndStatePersistence() throws {
        let defaultsKeys = [
            "FloatingInspectorIsOpen",
            "FloatingInspectorOrigin",
        ]

        withPreservedDefaults(defaultsKeys) {
            UserDefaults.standard.removeObject(forKey: "FloatingInspectorIsOpen")
            UserDefaults.standard.removeObject(forKey: "FloatingInspectorOrigin")

            let fallback = NothingInspectorViewController()
            fallback.nothingTextField = NSTextField(labelWithString: "Nothing")
            fallback.multipleTextField = NSTextField(labelWithString: "Multiple")

            let window = NSWindow(
                contentRect: NSRect(x: 8, y: 12, width: 280, height: 180),
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = fallback

            let controller = InspectorWindowController(window: window)
            controller.windowDidLoad()
            #expect(window.contentViewController is NothingInspectorViewController)
            #expect(window.title == "Inspector")
            #expect(window.flippedOrigin == NSPoint(x: 256, y: 256))

            let fallbackInspector = controller.inspector(for: [NSObject()])
            #expect(fallbackInspector is NothingInspectorViewController)

            controller.objects = [NSObject(), NSObject()]
            #expect(window.contentViewController is NothingInspectorViewController)
            #expect(fallback.nothingTextField?.isHidden == true)
            #expect(fallback.multipleTextField?.isHidden == false)

            window.isVisible = true
            window.flippedOrigin = NSPoint(x: 42, y: 84)
            controller.saveState()
            #expect(InspectorWindowController.shouldOpenAtStartup)
            #expect(UserDefaults.standard.string(forKey: "FloatingInspectorOrigin") == NSStringFromPoint(NSPoint(x: 42, y: 84)))

            window.isVisible = false
            controller.saveState()
            #expect(!InspectorWindowController.shouldOpenAtStartup)
        }
    }

    @Test("Inspector-specific AppKit shims preserve macOS API semantics")
    @MainActor func inspectorAppKitCompatibilityHooks() throws {
        let nibName: NSNib.Name = "Inspector"
        #expect(nibName == "Inspector")
        #expect(NSFont.menuFont(ofSize: 0).pointSize == NSFont.systemFontSize)
        #expect(NSFont.menuFont(ofSize: 17).pointSize == 17)
        #expect(UTType.applicationBundle.conforms(to: .directory))

        let button = NSButton.checkbox(withTitle: "Mixed", target: nil, action: nil)
        #expect(button.state == .off)

        button.setNextState()
        #expect(button.state == .on)

        button.setNextState()
        #expect(button.state == .off)

        button.allowsMixedState = true
        button.setNextState()
        #expect(button.state == .on)
        button.setNextState()
        #expect(button.state == .mixed)
        button.setNextState()
        #expect(button.state == .off)

        let window = NSWindow(
            contentRect: NSRect(x: 10, y: 20, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        #expect(window.flippedOrigin == NSPoint(x: 10, y: 20))
        window.setFlippedOriginAdjustingForScreen(NSPoint(x: 64, y: 96))
        #expect(window.frame.origin == NSPoint(x: 64, y: 96))

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.setFrameIfNotEqual(view.frame)
        #expect(view.frame.size.width == 10)
        view.setFrameIfNotEqual(NSRect(x: 1, y: 2, width: 30, height: 40))
        #expect(view.frame == NSRect(x: 1, y: 2, width: 30, height: 40))

        let accessibilityLabel = "Feed icon"
        view.setAccessibilityLabel(accessibilityLabel)
        #expect(view.accessibilityLabel() == accessibilityLabel)

        let registered = NSViewController()
        NSStoryboard.quillRegisterController(identifier: "InspectorCompatibilityTest") {
            registered
        }
        let storyboard = NSStoryboard(name: "Inspector", bundle: nil)
        let instantiated = try #require(storyboard.instantiateController(withIdentifier: "InspectorCompatibilityTest") as? NSViewController)
        #expect(instantiated === registered)

        #expect(Notification.Name.imageDidBecomeAvailable.rawValue == "ImageDidBecomeAvailableNotification")
        #expect(Notification.Name.DidUpdateFeedPreferencesFromContextMenu.rawValue == "DidUpdateFeedPreferencesFromContextMenu")

        let popup = NSPopUpButton()
        let firstItem = NSMenuItem(title: "Default", action: nil, keyEquivalent: "")
        let secondItem = NSMenuItem(title: "Custom", action: nil, keyEquivalent: "")
        secondItem.representedObject = "custom-browser"
        popup.menu?.addItem(firstItem)
        popup.menu?.addItem(secondItem)
        #expect(popup.indexOfItem(withRepresentedObject: nil) == 0)
        #expect(popup.indexOfItem(withRepresentedObject: "custom-browser") == 1)
        #expect(popup.indexOfItem(withRepresentedObject: "missing") == -1)
    }

    @Test("Inspector concrete controllers reject unrelated objects without fixtures")
    @MainActor func inspectorConcreteControllersRejectUnrelatedObjects() {
        let unrelated = [NSObject()]
        #expect(!FeedInspectorViewController().canInspect(unrelated))
        #expect(!FolderInspectorViewController().canInspect(unrelated))
        #expect(!BuiltinSmartFeedInspectorViewController().canInspect(unrelated))
    }

    @Test("Preferences controllers populate menus and persist update-channel state")
    @MainActor func preferencesControllersPopulateAndPersistState() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let releaseURL = try #require(info["SUFeedURL"] as? String)
        let testURL = try #require(info["FeedURLForTestBuilds"] as? String)

        withPreservedDefaults([
            "SUFeedURL",
            MacAppDefaults.Key.currentThemeName,
            MacAppDefaults.Key.defaultBrowserID,
        ]) {
            UserDefaults.standard.removeObject(forKey: "SUFeedURL")
            UserDefaults.standard.removeObject(forKey: MacAppDefaults.Key.currentThemeName)
            UserDefaults.standard.removeObject(forKey: MacAppDefaults.Key.defaultBrowserID)

            let advanced = AdvancedPreferencesViewController()
            advanced.releaseBuildsButton = NSButton.radioButton(withTitle: "Release", target: nil, action: nil)
            advanced.testBuildsButton = NSButton.radioButton(withTitle: "Test", target: nil, action: nil)
            advanced.viewWillAppear()
            #expect(advanced.releaseBuildsURL == releaseURL)
            #expect(advanced.testBuildsURL == testURL)
            #expect(!advanced.wantsTestBuilds)
            #expect(advanced.releaseBuildsButton.state == .on)

            advanced.updateTypeButtonClicked(advanced.testBuildsButton)
            #expect(advanced.wantsTestBuilds)
            #expect(UserDefaults.standard.string(forKey: "SUFeedURL") == testURL)

            let general = GeneralPreferencesViewController(nibName: nil, bundle: nil)
            let articleTextSizeContainer = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 40))
            general.articleTextSizeLabel = NSTextField(labelWithString: "Article Text Size:")
            general.articleTextSizePopup = NSPopUpButton()
            articleTextSizeContainer.addSubview(general.articleTextSizeLabel)
            articleTextSizeContainer.addSubview(general.articleTextSizePopup)
            general.articleThemePopup = NSPopUpButton()
            general.defaultBrowserPopup = NSPopUpButton()

            general.viewWillAppear()
            #expect(general.articleThemePopup.itemTitles().contains("Default"))
            #expect(general.articleThemePopup.selectedItem?.title == "Default")
            #expect(general.defaultBrowserPopup.numberOfItems >= 1)
            #expect(general.defaultBrowserPopup.selectedItem?.title.hasPrefix("System Default") == true)

            let customBrowser = NSMenuItem(title: "Custom Browser", action: nil, keyEquivalent: "")
            customBrowser.representedObject = "/Applications/Custom Browser.app"
            general.defaultBrowserPopup.menu?.addItem(customBrowser)
            general.defaultBrowserPopup.selectItem(at: general.defaultBrowserPopup.indexOfItem(withRepresentedObject: customBrowser.representedObject))
            general.browserPopUpDidChangeValue(nil)
            #expect(MacAppDefaults.shared.defaultBrowserID == "/Applications/Custom Browser.app")
        }
    }

    @Test("Preferences window controller uses toolbar metadata and storyboard registry")
    @MainActor func preferencesWindowControllerBuildsToolbarAndInitialView() throws {
        let generalController = NSViewController()
        generalController.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        NSStoryboard.quillRegisterController(identifier: "General") {
            generalController
        }

        let window = NSWindow(
            contentRect: NSRect(x: 20, y: 40, width: 400, height: 220),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 220))

        let controller = PreferencesWindowController(window: window)
        controller.windowDidLoad()

        let toolbar = try #require(window.toolbar)
        #expect(window.title == "General")
        #expect(window.showsToolbarButton == false)
        #expect(toolbar.displayMode == .iconAndLabel)
        #expect(toolbar.selectedItemIdentifier?.rawValue == "General")
        #expect(controller.toolbarDefaultItemIdentifiers(toolbar).map(\.rawValue) == ["General", "Accounts", "Advanced"])
        #expect(window.contentView?.subviews.first === generalController.view)
        #expect(window.frame.size.width == 512)

        let advancedItem = try #require(controller.toolbar(toolbar, itemForItemIdentifier: NSToolbarItem.Identifier(rawValue: "Advanced"), willBeInsertedIntoToolbar: true))
        #expect(advancedItem.label == "Advanced")
        #expect(advancedItem.paletteLabel == "Advanced")
        #expect(advancedItem.target === controller)
        #expect(advancedItem.action?.name == "toolbarItemClicked(_:)")
    }

    @Test("Timeline cell layout/view shims build upstream table cells")
    @MainActor func timelineCellLayoutAndViewSurface() {
        let appearance = TimelineCellAppearance(showIcon: true, fontSize: .medium)
        let cellData = TimelineCellData()

        #expect(cellData.showFeedName == .none)
        #expect(appearance.iconSize == NSSize(width: 48, height: 48))
        #expect(Assets.Images.timelineStarSelected.size.width >= 0)
        #expect(Assets.Images.timelineStarUnselected.size.height >= 0)
        #if os(Linux)
        #expect(data(Assets.Images.timelineStarSelected, hasPrefix: "%PDF"))
        #expect(data(Assets.Images.timelineStarUnselected, hasPrefix: "%PDF"))
        #endif

        let singleLineSize = SingleLineTextFieldSizer.size(for: "Today", font: appearance.dateFont)
        #expect(singleLineSize.width > 0)
        #expect(singleLineSize.height > 0)

        let multilineSize = MultilineTextFieldSizer.size(
            for: "A longer NetNewsWire timeline title that should wrap",
            font: appearance.textOnlyFont,
            numberOfLines: 2,
            width: 120
        )
        #expect(multilineSize.size.width == 120)
        #expect(multilineSize.numberOfLinesUsed >= 1)
        #expect(multilineSize.numberOfLinesUsed <= 2)

        let layout = TimelineCellLayout(
            width: 320,
            height: 0,
            cellData: cellData,
            appearance: appearance,
            hasIcon: false
        )
        #expect(layout.width == 320)
        #expect(layout.height >= appearance.cellPadding.top + appearance.cellPadding.bottom)
        #expect(layout.titleRect.height == 0)
        #expect(layout.textRect.height == 0)
        #expect(layout.unreadIndicatorRect.size == NSSize(width: 8, height: 8))

        let cell = TimelineTableCellView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        cell.cellAppearance = appearance
        cell.cellData = cellData
        cell.layout()
        #expect(cell.isFlipped)
        #expect(cell.subviews.count == 8)

        let unread = UnreadIndicatorView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        unread.isSelected = true
        unread.isEmphasized = true
        #expect(UnreadIndicatorView.bezierPath.elementCount > 0)
        unread.draw(unread.bounds)
    }

    @Test("Timeline container, row, and table views preserve upstream AppKit behavior")
    @MainActor func timelineContainerRowAndTableSurface() throws {
        try withPreservedDefaults([MacAppDefaults.Key.timelineShowsSeparators]) {
            UserDefaults.standard.set(true, forKey: MacAppDefaults.Key.timelineShowsSeparators)

            let container = TimelineContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
            let firstContent = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
            let secondContent = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))

            container.contentView = firstContent
            #expect(container.subviews.count == 1)
            #expect(container.subviews.first === firstContent)
            #expect(firstContent.superview === container)
            #expect(firstContent.translatesAutoresizingMaskIntoConstraints == false)

            container.contentView = firstContent
            #expect(container.subviews.count == 1)

            container.contentView = secondContent
            #expect(firstContent.superview == nil)
            #expect(container.subviews.count == 1)
            #expect(container.subviews.first === secondContent)
            #expect(secondContent.superview === container)

            let appearance = TimelineCellAppearance(showIcon: false, fontSize: .medium)
            let row = TimelineTableRowView()
            let cell = TimelineTableCellView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
            cell.cellAppearance = appearance
            cell.cellData = TimelineCellData()
            row.addSubview(cell)

            let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
            host.addSubview(row)

            #expect(row.isOpaque)
            #expect(row.subviews.count == 2)
            let separator = try #require(row.subviews.first { $0 !== cell })
            #expect(separator.wantsLayer)
            #expect(separator.layer != nil)
            #expect(separator.layer?.backgroundColor != nil)

            row.isEmphasized = true
            #expect(cell.isEmphasized)
            row.isSelected = true
            #expect(cell.isSelected)
            #expect(separator.isHidden)

            row.removeFromSuperview()
            host.addSubview(row)
            #expect(row.subviews.filter { $0 !== cell }.count == 1)

            let table = TimelineTableView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
            scrollView.hasVerticalScroller = true
            scrollView.documentView = table

            #expect(table.accessibilityLabel() == "Timeline")
            #expect(table.isOpaque)
            #expect(table.enclosingScrollView === scrollView)

            table.viewWillStartLiveResize()
            #expect(scrollView.hasVerticalScroller == false)
            table.viewDidEndLiveResize()
            #expect(scrollView.hasVerticalScroller == true)

            let keyboardDelegate = RecordingKeyboardDelegate(handled: true)
            table.keyboardDelegate = keyboardDelegate
            table.keyDown(with: NSEvent())
            #expect(keyboardDelegate.eventsHandled == 1)
            #expect(keyboardDelegate.lastView === table)
        }
    }

    @Test("Detail status bar and container preserve link and content layout behavior")
    @MainActor func detailStatusBarAndContainerSurface() throws {
        let statusBar = DetailStatusBarView(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        statusBar.urlLabel = NSTextField(labelWithString: "")
        statusBar.wantsLayer = true

        #expect(!statusBar.isOpaque)
        #expect(statusBar.isFlipped)
        #expect(statusBar.wantsUpdateLayer)

        statusBar.mouseoverLink = "https://ranchero.com/netnewswire/"
        #expect(statusBar.isHidden == false)
        #expect(statusBar.urlLabel.stringValue == "ranchero.com/netnewswire/")

        statusBar.updateLayer()
        #expect(statusBar.layer?.cornerRadius == 4)
        #expect(statusBar.layer?.backgroundColor != nil)

        statusBar.mouseoverLink = ""
        #expect(statusBar.isHidden)
        #expect(statusBar.urlLabel.stringValue == "")

        let container = DetailContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        container.detailStatusBarView = statusBar
        container.addSubview(statusBar)

        let firstContent = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        container.contentView = firstContent
        #expect(container.subviews.first === firstContent)
        #expect(container.subviews.last === statusBar)
        #expect(firstContent.superview === container)
        #expect(firstContent.translatesAutoresizingMaskIntoConstraints == false)

        let firstConstraints = try #require(container.contentViewConstraints)
        #expect(firstConstraints.count == 4)
        #expect(firstConstraints.allSatisfy { $0.isActive })

        container.contentView = firstContent
        #expect(container.contentViewConstraints?.count == 4)
        #expect(container.subviews.filter { $0 === firstContent }.count == 1)

        let secondContent = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 80))
        container.contentView = secondContent
        #expect(firstContent.superview == nil)
        #expect(firstConstraints.allSatisfy { !$0.isActive })
        #expect(secondContent.superview === container)
        #expect(container.subviews.first === secondContent)

        container.contentView = nil
        #expect(secondContent.superview == nil)
        #expect(container.contentViewConstraints == nil)

        container.draw(container.bounds)
    }

    @Test("Detail icon scheme handler streams rendered icon data and reports failures")
    @MainActor func detailIconSchemeHandlerSurface() throws {
        let handler = DetailIconSchemeHandler()
        let webView = WKWebView()

        let missingTask = WKURLSchemeTask(request: URLRequest(url: URL(string: "nnw-icon://missing")!))
        handler.webView(webView, start: missingTask)
        let missingError = try #require(missingTask.error as? URLError)
        #expect(missingError.code == .fileDoesNotExist)
        #expect(!missingTask.isFinished)

        let author = try #require(Author(
            authorID: nil,
            name: "Icon Reporter",
            url: nil,
            avatarURL: "https://example.test/avatar.png",
            emailAddress: nil
        ))
        AuthorAvatarDownloader.shared.emptyCache()
        defer {
            AuthorAvatarDownloader.shared.emptyCache()
        }
        AuthorAvatarDownloader.shared.cache(
            IconImage(NSImage(size: NSSize(width: 16, height: 16))),
            for: author
        )

        handler.currentArticle = Article(
            accountID: "account-icon",
            articleID: "article-icon",
            feedID: "feed-icon",
            uniqueID: "unique-icon",
            title: "Icon article",
            contentHTML: nil,
            contentText: nil,
            markdown: nil,
            url: "https://example.test/icon",
            externalURL: nil,
            summary: nil,
            imageURL: nil,
            datePublished: nil,
            dateModified: nil,
            authors: Set([author]),
            status: ArticleStatus(articleID: "article-icon", read: false, starred: false, dateArrived: Date(timeIntervalSince1970: 0))
        )

        let successTask = WKURLSchemeTask(request: URLRequest(url: URL(string: "nnw-icon://article-icon")!))
        handler.webView(webView, start: successTask)

        #expect(successTask.error == nil)
        let response = try #require(successTask.receivedResponses.first as? HTTPURLResponse)
        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Cache-Control") == "no-cache")
        #expect(successTask.receivedData.first?.isEmpty == false)
        #expect(successTask.isFinished)

        let stopTask = WKURLSchemeTask(request: URLRequest(url: URL(string: "nnw-icon://article-icon")!))
        handler.webView(webView, stop: stopTask)
        let stopError = try #require(stopTask.error as? URLError)
        #expect(stopError.code == .unknown)
    }

    @Test("Detail keyboard delegate loads bundled shortcut plist")
    @MainActor func detailKeyboardDelegateSurface() {
        let delegate = DetailKeyboardDelegate()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let event = NSEvent()

        #expect(delegate.shortcuts.count == 1)
        #expect(containsShortcut(delegate.shortcuts, action: "navigateToTimeline:", key: "[leftarrow]"))
        #expect(!delegate.keydown(event, in: view))
    }

    @Test("Detail controllers render articles through promoted WebKit surface")
    @MainActor func detailViewControllerSurface() throws {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))
        let statusBar = DetailStatusBarView(frame: NSRect(x: 0, y: 278, width: 420, height: 22))
        statusBar.urlLabel = NSTextField(labelWithString: "")
        let container = DetailContainerView(frame: rootView.bounds)
        container.detailStatusBarView = statusBar
        rootView.addSubview(container)
        rootView.addSubview(statusBar)

        let controller = DetailViewController()
        controller.view = rootView
        controller.containerView = container
        controller.statusBarView = statusBar
        controller.viewDidLoad()

        let article = makeTimelineArticle(id: "detail-promoted", title: "Promoted detail article", read: false)
        controller.setState(.article(article, nil), mode: .regular)

        let regularWebView = try #require(container.contentView as? DetailWebView)
        #expect(regularWebView.navigationDelegate != nil)
        #expect(regularWebView.uiDelegate != nil)
        #expect(regularWebView.keyboardDelegate != nil)
        #expect(regularWebView.lastLoadedHTMLString?.contains("Promoted detail article") == true)
        #expect(regularWebView.lastLoadedHTMLBaseURL?.absoluteString == "https://example.com/detail-promoted")

        controller.stopMediaPlayback()
        #expect(regularWebView.evaluatedJavaScript.contains("stopMediaPlayback();"))

        controller.showDetail(for: .search)
        controller.setState(.loading, mode: .search)
        let searchWebView = try #require(container.contentView as? DetailWebView)
        #expect(searchWebView !== regularWebView)
        #expect(searchWebView.lastLoadedHTMLString?.contains("Loading") == true)
    }

    @Test("Timeline container controller wires timeline content and view options")
    @MainActor func timelineContainerViewControllerSurface() {
        withPreservedDefaults([
            MacAppDefaults.Key.timelineSortDirection,
            MacAppDefaults.Key.timelineGroupByFeed,
        ]) {
            UserDefaults.standard.set(ComparisonResult.orderedAscending.rawValue, forKey: MacAppDefaults.Key.timelineSortDirection)
            UserDefaults.standard.set(true, forKey: MacAppDefaults.Key.timelineGroupByFeed)

            let controller = TimelineContainerViewController()
            controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
            controller.viewOptionsPopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
            controller.newestToOldestMenuItem = NSMenuItem(title: "Newest to Oldest", action: nil, keyEquivalent: "")
            controller.oldestToNewestMenuItem = NSMenuItem(title: "Oldest to Newest", action: nil, keyEquivalent: "")
            controller.groupByFeedMenuItem = NSMenuItem(title: "Group by Feed", action: nil, keyEquivalent: "")
            controller.readFilteredButton = NSButton()
            controller.containerView = TimelineContainerView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))

            let regularTable = TimelineTableView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
            regularTable.tableColumns = [NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "timeline"))]
            controller.regularTimelineViewController.tableView = regularTable

            controller.viewDidLoad()

            #expect(controller.currentTimelineViewController === controller.regularTimelineViewController)
            #expect(controller.containerView.contentView === controller.regularTimelineViewController.view)
            #expect(regularTable.target === controller.regularTimelineViewController)
            #expect(regularTable.keyboardDelegate != nil)
            #expect(controller.readFilteredButton.isHidden)
            #expect(controller.newestToOldestMenuItem.state == .off)
            #expect(controller.oldestToNewestMenuItem.state == .on)
            #expect(controller.groupByFeedMenuItem.state == .on)
            #expect(controller.viewOptionsPopUpButton.title == "Oldest to Newest")
            #expect(controller.oldestToNewestMenuItem.attributedTitle?.string == "Oldest to Newest")

            controller.setRepresentedObjects(nil, mode: .regular)
            #expect(controller.regularTimelineViewController.representedObjects == nil)
            #expect(controller.regularTimelineViewControllerHasRepresentedObjects(nil))
        }
    }

    @Test("Upstream main window shell assembles promoted AppKit controllers")
    @MainActor func upstreamMainWindowShellAssembly() async {
        withFreshAccountManager { _ in
            let shell = makeUpstreamMainWindowShell()

            #expect(shell.window.toolbar?.identifier == "MainWindowToolbar")
            #expect(shell.window.toolbar?.delegate === shell.mainWindowController)
            #expect(shell.window.frame.size == NSSize(width: 1345, height: 900))
            #expect(shell.window.minSize == NSSize(width: 600, height: 600))
            #expect(shell.window.title == "NetNewsWire")
            #expect(shell.window.subtitle == "7 unread")

            #expect(shell.splitViewController.splitViewItems.count == 3)
            #expect(shell.splitViewController.splitViewItems[0].viewController === shell.sidebarController)
            #expect(shell.splitViewController.splitViewItems[1].viewController === shell.timelineController)
            #expect(shell.splitViewController.splitViewItems[2].viewController === shell.detailController)
            #expect(shell.splitViewController.splitViewItems[2].minimumThickness == 384)

            #expect(shell.sidebarController.delegate === shell.mainWindowController)
            #expect(shell.sidebarController.splitViewItem === shell.splitViewController.splitViewItems[0])
            #expect(shell.timelineController.delegate === shell.mainWindowController)
            #expect(shell.timelineController.currentTimelineViewController === shell.timelineController.regularTimelineViewController)
            #expect(shell.timelineController.containerView.contentView === shell.timelineController.regularTimelineViewController.view)
            #expect(shell.detailContainer.contentView is DetailWebView)
            #expect(shell.mainWindowController.selectedObjectsInSidebar()?.isEmpty == true)
        }
    }

    @Test("Upstream main window shell refreshes unread subtitle")
    @MainActor func upstreamMainWindowShellRefreshesUnreadSubtitle() async {
        withFreshAccountManager { _ in
            let shell = makeUpstreamMainWindowShell(unreadCount: 1)
            #expect(shell.window.subtitle == "1 unread")

            shell.refreshUnreadCount(42)
            #expect(shell.window.title == "NetNewsWire")
            #expect(shell.window.subtitle == "42 unread")
        }
    }

    @Test("Upstream Linux host exposes stable public snapshot")
    @MainActor func upstreamLinuxHostSnapshot() async {
        withFreshAccountManager { _ in
            let shell = makeUpstreamMainWindowShell(unreadCount: 12)
            let snapshot = shell.snapshot

            #expect(snapshot.title == "NetNewsWire")
            #expect(snapshot.subtitle == "12 unread")
            #expect(snapshot.toolbarIdentifier == "MainWindowToolbar")
            #expect(snapshot.splitViewItemCount == 3)
            #expect(snapshot.detailMinimumThickness == 384)
            #expect(snapshot.windowWidth == 1345)
            #expect(snapshot.windowHeight == 900)
            #expect(snapshot.minimumWidth == 600)
            #expect(snapshot.minimumHeight == 600)
            #expect(snapshot.hasDetailWebView)

            shell.refreshUnreadCount(2)
            #expect(shell.snapshot.subtitle == "2 unread")
        }
    }

    @Test("Sidebar primitives draw badges, resize outlines, and initialize status progress")
    @MainActor func sidebarPrimitiveSurface() {
        let badge = UnreadCountView(frame: NSRect(x: 0, y: 0, width: 64, height: 20))
        #expect(badge.isFlipped)
        #expect(badge.unreadCountString == "")
        #expect(badge.intrinsicContentSize == .zero)

        badge.unreadCount = 1234
        #expect(badge.unreadCountString == "1,234")
        #expect(badge.intrinsicContentSize.width > 0)
        #expect(badge.intrinsicContentSize.height > 0)
        badge.isSelected = true
        badge.draw(badge.bounds)
        badge.unreadCount = 0
        #expect(badge.intrinsicContentSize == .zero)

        let outline = SidebarOutlineView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        outline.tableColumns = [NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "sidebar"))]
        outline.tableColumns[0].width = 180
        let root = TreeNode.genericRootNode()
        let child = root.createChildNode(NSObject())
        let dataSource = SingleNodeOutlineDataSource(node: child)
        outline.dataSource = dataSource
        outline.reloadData()

        let cellFrame = outline.frameOfCell(atColumn: 0, row: 0)
        let displayedNode = outline.item(atRow: 0) as? TreeNode
        #expect(displayedNode === child)
        #expect(cellFrame.origin.x == 4)
        #expect(cellFrame.size.width == 176)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = outline
        outline.viewWillStartLiveResize()
        #expect(scrollView.hasVerticalScroller == false)
        outline.viewDidEndLiveResize()
        #expect(scrollView.hasVerticalScroller == true)

        let keyboardDelegate = RecordingKeyboardDelegate(handled: true)
        outline.keyboardDelegate = keyboardDelegate
        outline.keyDown(with: NSEvent())
        #expect(keyboardDelegate.eventsHandled == 1)
        #expect(keyboardDelegate.lastView === outline)

        let statusBar = SidebarStatusBarView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        let progressIndicator = NSProgressIndicator(frame: .zero)
        let progressLabel = NSTextField(frame: .zero)
        statusBar.progressIndicator = progressIndicator
        statusBar.progressLabel = progressLabel
        statusBar.bottomConstraint = NSLayoutConstraint()
        statusBar.heightConstraint = NSLayoutConstraint()
        statusBar.heightConstraint.constant = 32
        NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 64)).addSubview(statusBar)

        statusBar.awakeFromNib()
        statusBar.updateUI()
        #expect(statusBar.isFlipped)
        #expect(progressIndicator.isHidden)
        #expect(progressLabel.isHidden)
        #expect(progressLabel.stringValue == "")
    }

    @Test("Sidebar keyboard delegate loads bundled shortcut plist")
    @MainActor func sidebarKeyboardDelegateSurface() {
        let delegate = SidebarKeyboardDelegate()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        let event = NSEvent()

        #expect(delegate.sidebarViewController == nil)
        #expect(delegate.shortcuts.count == 12)
        #expect(containsShortcut(delegate.shortcuts, action: "navigateToTimeline:", key: "[tab]"))
        #expect(containsShortcut(delegate.shortcuts, action: "delete:", key: "[delete]"))
        #expect(containsShortcut(delegate.shortcuts, action: "expandAll:", key: "[rightarrow]", option: true, command: true))
        #expect(!delegate.keydown(event, in: view))
    }

    @Test("Timeline and global keyboard delegates load bundled shortcut plists")
    @MainActor func timelineAndGlobalKeyboardDelegateSurfaces() {
        let timelineDelegate = TimelineKeyboardDelegate()
        #expect(timelineDelegate.shortcuts.count == 4)
        #expect(containsShortcut(timelineDelegate.shortcuts, action: "selectNextUp:", key: "[uparrow]"))
        #expect(containsShortcut(timelineDelegate.shortcuts, action: "navigateToDetail:", key: "[rightarrow]"))

        let globalShortcuts = MainWindowKeyboardHandler.shared.globalShortcuts
        #expect(globalShortcuts.count == 21)
        #expect(containsShortcut(globalShortcuts, action: "scrollOrGoToNextUnread:", key: "[space]"))
        #expect(containsShortcut(globalShortcuts, action: "scrollUp:", key: "[space]", shift: true))
        #expect(containsShortcut(globalShortcuts, action: "openInBrowserUsingOppositeOfSettings:", key: "[return]", shift: true))
    }

    @Test("Rename window controller validates names and finishes sheets")
    @MainActor func renameWindowControllerSurface() throws {
        let renamedObject = NSObject()
        let delegate = RecordingRenameDelegate()
        let controller = RenameWindowController(originalTitle: "Old Name", representedObject: renamedObject, delegate: delegate)
        controller.renamePrompt = NSTextField(frame: .zero)
        controller.newTitleTextField = NSTextField(frame: .zero)
        controller.renameButton = NSButton(frame: .zero)

        let sheet = try #require(controller.window)
        #expect(controller.newTitleTextField.stringValue == "Old Name")
        #expect(controller.renamePrompt.stringValue.contains("Old Name"))
        #expect(!controller.renameButton.isEnabled)

        controller.newTitleTextField.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.newTitleTextField))
        #expect(!controller.renameButton.isEnabled)

        controller.newTitleTextField.stringValue = "Old Name"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.newTitleTextField))
        #expect(!controller.renameButton.isEnabled)

        controller.newTitleTextField.stringValue = "New Name"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.newTitleTextField))
        #expect(controller.renameButton.isEnabled)

        let parent = NSWindow()
        parent.beginSheet(sheet)
        controller.rename(nil)

        #expect(sheet.sheetParent == nil)
        #expect(delegate.windowController === controller)
        #expect(delegate.renamedObject === renamedObject)
        #expect(delegate.newName == "New Name")
    }

    @Test("Sidebar cell lays out title, unread badge, icon, and accessibility text")
    @MainActor func sidebarCellSurface() {
        let cell = SidebarCell(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        cell.cellAppearance = SidebarCellAppearance(rowSizeStyle: .large)
        cell.name = "Unread"
        cell.unreadCount = 42
        cell.shouldShowImage = true
        cell.iconImage = IconImage(
            NSImage(size: NSSize(width: 18, height: 18)),
            isSymbol: true,
            preferredColor: NSColor.controlAccentColor.cgColor
        )

        #expect(cell.isFlipped)
        #expect(cell.name == "Unread")
        #expect(cell.unreadCount == 42)
        #expect(cell.accessibilityLabel() == "Unread 42 unread")
        #expect(cell.subviews.count == 3)

        cell.layout()
        cell.backgroundStyle = .emphasized
        cell.layout()

        cell.unreadCount = 0
        #expect(cell.accessibilityLabel() == "Unread")
    }

    @Test("Icon view aspect-fits raster images and fills symbol images")
    @MainActor func iconViewSurface() throws {
        let view = IconView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
        #expect(view.isFlipped)
        #expect(view.wantsLayer)
        #expect(view.layer?.cornerRadius == 4)

        let imageView = try #require(view.subviews.first as? NSImageView)
        #expect(imageView.imageAlignment == .alignCenter)
        #expect(imageView.imageScaling == .scaleProportionallyUpOrDown)

        view.iconImage = IconImage(NSImage(size: NSSize(width: 12, height: 24)))
        view.layout()
        #expect(imageView.frame == NSRect(x: 12, y: 0, width: 24, height: 48))

        view.iconImage = IconImage(NSImage(size: NSSize(width: 24, height: 12)))
        view.layout()
        #expect(imageView.frame == NSRect(x: 0, y: 12, width: 48, height: 24))

        view.iconImage = IconImage(NSImage(size: NSSize(width: 16, height: 16)), isSymbol: true)
        view.layout()
        #expect(imageView.frame == view.bounds)

        view.viewDidMoveToSuperview()
        view.draw(view.bounds)
    }

    @Test("Sidebar pasteboard feed and folder dictionaries round-trip")
    @MainActor func sidebarPasteboardFeedAndFolderSurface() throws {
        let feed = PasteboardFeed(
            url: "example.com/feed.xml",
            feedID: "feed-1",
            homePageURL: "example.com",
            name: "Example",
            editedName: "Edited Example",
            accountID: "account-1",
            accountType: .onMyMac,
            containerName: "News"
        )
        #expect(feed.url == "http://example.com/feed.xml")
        #expect(feed.homePageURL == "http://example.com/")
        #expect(feed.isLocalFeed)

        let exportDictionary = feed.exportDictionary()
        #expect(exportDictionary["URL"] == "http://example.com/feed.xml")
        #expect(exportDictionary["homePageURL"] == "http://example.com/")
        #expect(exportDictionary["name"] == "Edited Example")

        let internalDictionary = feed.internalDictionary()
        let feedFromDictionary = try #require(PasteboardFeed(dictionary: internalDictionary))
        #expect(feedFromDictionary == feed)

        let feedItem = NSPasteboardItem()
        feedItem.setPropertyList(internalDictionary, forType: FeedPasteboardWriter.feedUTIInternalType)
        let feedFromItem = try #require(PasteboardFeed(pasteboardItem: feedItem))
        #expect(feedFromItem == feed)

        let urlItem = NSPasteboardItem()
        urlItem.setString("https://example.com/rss", forType: .string)
        let externalFeed = try #require(PasteboardFeed(pasteboardItem: urlItem))
        #expect(externalFeed.url == "https://example.com/rss")
        #expect(!externalFeed.isLocalFeed)

        let folder = PasteboardFolder(name: "News", folderID: "folder-1", accountID: "account-1")
        let folderDictionary = folder.internalDictionary()
        let folderFromDictionary = try #require(PasteboardFolder(dictionary: folderDictionary))
        #expect(folderFromDictionary == folder)

        let folderItem = NSPasteboardItem()
        folderItem.setPropertyList(folderDictionary, forType: FolderPasteboardWriter.folderUTIInternalType)
        let folderFromItem = try #require(PasteboardFolder(pasteboardItem: folderItem))
        #expect(folderFromItem == folder)
    }

    @Test("Sidebar external feed drops route through app delegate add-feed requests")
    @MainActor func sidebarExternalFeedDropsRouteThroughAppDelegate() throws {
        try withFreshAccountManager { manager in
            let account = manager.defaultAccount
            let folder = try #require(account.ensureFolder(with: "News"))
            let treeDelegate = SidebarTreeControllerDelegate()
            let treeController = TreeController(delegate: treeDelegate)
            let dataSource = SidebarOutlineDataSource(treeController: treeController)
            let outlineView = NSOutlineView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
            let accountNode = try #require(treeController.nodeInTreeRepresentingObject(account))
            let folderNode = try #require(treeController.nodeInTreeRepresentingObject(folder))
            let dragInfo = TestDraggingInfo(pasteboard: makeExternalFeedPasteboard())
            NetNewsWireContext.appDelegate = NetNewsWireContext.AppDelegate()

            let accountOperation = dataSource.outlineView(
                outlineView,
                validateDrop: dragInfo,
                proposedItem: accountNode,
                proposedChildIndex: NSOutlineViewDropOnItemIndex
            )
            #expect(accountOperation == .copy)
            #expect(dataSource.outlineView(outlineView, acceptDrop: dragInfo, item: accountNode, childIndex: NSOutlineViewDropOnItemIndex))

            let accountRequest = try #require(NetNewsWireContext.appDelegate.lastAddFeedRequest)
            #expect(accountRequest.urlString == "https://example.com/feed.xml")
            #expect(accountRequest.name == "Edited Example")
            let requestAccount = try #require(accountRequest.account as? Account)
            #expect(requestAccount === account)
            #expect(accountRequest.folder == nil)

            NetNewsWireContext.appDelegate.resetAddFeedRequests()
            let folderOperation = dataSource.outlineView(
                outlineView,
                validateDrop: dragInfo,
                proposedItem: folderNode,
                proposedChildIndex: NSOutlineViewDropOnItemIndex
            )
            #expect(folderOperation == .copy)
            #expect(dataSource.outlineView(outlineView, acceptDrop: dragInfo, item: folderNode, childIndex: NSOutlineViewDropOnItemIndex))

            let folderRequest = try #require(NetNewsWireContext.appDelegate.lastAddFeedRequest)
            #expect(folderRequest.urlString == "https://example.com/feed.xml")
            #expect(folderRequest.name == "Edited Example")
            let requestFolderAccount = try #require(folderRequest.account as? Account)
            let requestFolder = try #require(folderRequest.folder as? Folder)
            #expect(requestFolderAccount === account)
            #expect(requestFolder === folder)
        }
    }

    @Test("Sidebar delete alert formats folder, feed, and multi-item confirmations")
    @MainActor func sidebarDeleteItemsAlertBuildsConfirmationText() throws {
        try withFreshAccountManager { manager in
            let folder = try #require(manager.defaultAccount.ensureFolder(with: "News"))
            let folderNode = TreeNode(representedObject: folder, parent: nil)
            let folderAlert = SidebarDeleteItemsAlert.build([folderNode])

            #expect(folderAlert.alertStyle == .warning)
            #expect(folderAlert.messageText == "Delete Folder")
            #expect(folderAlert.informativeText.contains("News"))
            #expect(folderAlert.buttons.map(\.title) == ["Delete", "Cancel"])

            let feed = TestSidebarItem(name: "Example Feed")
            let feedNode = TreeNode(representedObject: feed, parent: nil)
            let feedAlert = SidebarDeleteItemsAlert.build([feedNode])

            #expect(feedAlert.alertStyle == .warning)
            #expect(feedAlert.messageText == "Delete Feed")
            #expect(feedAlert.informativeText.contains("Example Feed"))
            #expect(feedAlert.buttons.map(\.title) == ["Delete", "Cancel"])

            let multiAlert = SidebarDeleteItemsAlert.build([folderNode, feedNode])

            #expect(multiAlert.alertStyle == .warning)
            #expect(multiAlert.messageText == "Delete Items")
            #expect(multiAlert.informativeText.contains("2 selected items"))
            #expect(multiAlert.buttons.map(\.title) == ["Delete", "Cancel"])
        }
    }

    @Test("Sharing service delegate derives subject and source window")
    @MainActor func sharingServiceDelegateSurface() throws {
        let window = NSWindow()
        let delegate = SharingServiceDelegate(window)
        let service = NSSharingService(title: "Share", image: NSImage(size: .zero), alternateImage: nil) {}
        let firstArticle = makeTimelineArticle(id: "share-1", title: "First Share", read: false)
        let secondArticle = makeTimelineArticle(id: "share-2", title: "Second Share", read: false)

        delegate.sharingService(
            service,
            willShareItems: [
                ArticlePasteboardWriter(article: firstArticle),
                "ignored",
                ArticlePasteboardWriter(article: secondArticle),
            ]
        )

        #expect(service.subject == "First Share, Second Share")

        var scope = NSSharingService.SharingContentScope.item
        let sourceWindow = delegate.sharingService(service, sourceWindowForShareItems: [], sharingContentScope: &scope)
        #expect(sourceWindow === window)
    }

    @Test("Sharing service picker filters NetNewsWire and returns source delegate")
    @MainActor func sharingServicePickerDelegateSurface() throws {
        let window = NSWindow()
        let delegate = SharingServicePickerDelegate(window)
        let picker = NSSharingServicePicker(items: [])
        let netNewsWire = NSSharingService(title: "NetNewsWire", image: NSImage(size: .zero), alternateImage: nil) {}
        let mail = NSSharingService(title: "Mail", image: NSImage(size: .zero), alternateImage: nil) {}

        let services = delegate.sharingServicePicker(
            picker,
            sharingServicesForItems: [],
            proposedSharingServices: [netNewsWire, mail]
        )

        #expect(services.map(\.menuItemTitle) == ["Mail"])
        #expect(SharingServicePickerDelegate.customSharingServices(for: []).isEmpty)

#if os(Linux)
        let applicationsDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/share/applications", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)
        let marsEditDesktop = applicationsDirectory.appendingPathComponent("com.red-sweater.marsedit5.desktop")
        let microBlogDesktop = applicationsDirectory.appendingPathComponent("blog.micro.mac.desktop")
        try? FileManager.default.removeItem(at: marsEditDesktop)
        try? FileManager.default.removeItem(at: microBlogDesktop)
        defer {
            try? FileManager.default.removeItem(at: marsEditDesktop)
            try? FileManager.default.removeItem(at: microBlogDesktop)
        }

        try desktopEntry(named: "MarsEdit").write(to: marsEditDesktop, atomically: true, encoding: .utf8)
        try desktopEntry(named: "Micro.blog").write(to: microBlogDesktop, atomically: true, encoding: .utf8)

        let article = makeTimelineArticle(id: "share-custom", title: "Custom Share", read: false)
        let customServices = SharingServicePickerDelegate.customSharingServices(for: [ArticlePasteboardWriter(article: article)])

        #expect(customServices.map(\.menuItemTitle) == ["MarsEdit", "Micro.blog"])
        #expect(customServices.allSatisfy { service in
            service.image?.data?.isEmpty == false
        })
#endif

        let sourceDelegate = try #require(delegate.sharingServicePicker(picker, delegateFor: mail))
        var scope = NSSharingService.SharingContentScope.item
        let sourceWindow = sourceDelegate.sharingService(mail, sourceWindowForShareItems: [], sharingContentScope: &scope)
        #expect(sourceWindow === window)
    }

    @Test("Article pasteboard writer exports timeline copy and drag payloads")
    @MainActor func articlePasteboardWriterSurface() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "NetNewsWireMacCoreArticlePasteboard"))
        pasteboard.clearContents()

        let article = Article(
            accountID: "account",
            articleID: "article-copy",
            feedID: "feed",
            uniqueID: "unique-copy",
            title: "Copy Title",
            contentHTML: "<p>Hello <b>world</b></p>",
            contentText: nil,
            markdown: nil,
            url: "https://example.com/article",
            externalURL: nil,
            summary: "Summary text",
            imageURL: "https://example.com/image.png",
            datePublished: Date(timeIntervalSince1970: 100),
            dateModified: nil,
            authors: nil,
            status: ArticleStatus(articleID: "article-copy", read: false, starred: true, dateArrived: Date(timeIntervalSince1970: 50))
        )

        let writer = ArticlePasteboardWriter(article: article)
        let types = writer.writableTypes(for: pasteboard)
        #expect(types.contains(ArticlePasteboardWriter.articleUTIType))
        #expect(types.contains(ArticlePasteboardWriter.articleUTIInternalType))
        #expect(types.contains(NSPasteboard.PasteboardType.URL))
        #expect(types.contains(NSPasteboard.PasteboardType.string))
        #expect(types.contains(NSPasteboard.PasteboardType.html))

        let plainText = try #require(writer.pasteboardPropertyList(forType: NSPasteboard.PasteboardType.string) as? String)
        #expect(plainText.contains("Copy Title"))
        #expect(plainText.contains("Summary text"))
        #expect(plainText.contains("URL: https://example.com/article"))

        let html = try #require(writer.pasteboardPropertyList(forType: NSPasteboard.PasteboardType.html) as? String)
        #expect(html.contains("<article>"))
        #expect(html.contains("Hello <b>world</b>"))

        let exported = try #require(writer.pasteboardPropertyList(forType: ArticlePasteboardWriter.articleUTIType) as? [String: Any])
        #expect(exported["articleID"] as? String == "article-copy")
        #expect(exported["title"] as? String == "Copy Title")
        #expect(exported["starred"] == nil)

        let internalPayload = try #require(writer.pasteboardPropertyList(forType: ArticlePasteboardWriter.articleUTIInternalType) as? [String: Any])
        #expect(internalPayload["accountID"] as? String == "account")

        #expect(pasteboard.writeObjects([writer]))
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType.URL) == "https://example.com/article")
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType.html)?.contains("Hello <b>world</b>") == true)

        pasteboard.copyObjects([article])
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType.URL) == "https://example.com/article")
        #expect(pasteboard.canCopyAtLeastOneObject([article]))
    }

    @Test("Timeline controller wires table actions, selection, validation, and copy")
    @MainActor func timelineViewControllerActionSurface() throws {
        let controller = TimelineViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        let table = TimelineTableView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        table.tableColumns = [NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "timeline"))]
        table.dataSource = controller
        table.delegate = controller
        table.nextResponder = controller
        controller.tableView = table

        controller.viewDidLoad()

        #expect(table.target === controller)
        #expect(table.doubleAction?.name == "openArticleInBrowser(_:)")
        #expect(table.externalDraggingSourceOperationMask.contains(.copy))
        #expect(table.keyboardDelegate != nil)
        #expect(table.style == .inset)
        #expect(table.rowHeight > 0)

        let firstArticle = makeTimelineArticle(id: "timeline-1", title: "First timeline article", read: false)
        let secondArticle = makeTimelineArticle(id: "timeline-2", title: "Second timeline article", read: true)
        let thirdArticle = makeTimelineArticle(id: "timeline-3", title: "Third timeline article", read: false)
        controller.articles = [firstArticle, secondArticle, thirdArticle]
        table.reloadData()

        #expect(controller.numberOfRows(in: table) == 3)
        #expect(table.numberOfRows == 3)
        let rowArticle = try #require(controller.tableView(table, objectValueFor: nil, row: 1) as? Article)
        #expect(rowArticle === secondArticle)
        #expect(controller.tableView(table, pasteboardWriterForRow: 1) is ArticlePasteboardWriter)
        #expect(controller.tableView(table, pasteboardWriterForRow: 99) == nil)
        #expect(controller.tableView(table, heightOfRow: 0) == table.rowHeight)

        table.selectRow(0)
        #expect(controller.selectedArticles.first === firstArticle)

        _ = NSApplication.shared.sendAction(Selector("selectNextDown(_:)"), to: nil, from: table)
        #expect(table.selectedRow == 1)
        #expect(controller.selectedArticles.first === secondArticle)

        _ = NSApplication.shared.sendAction(Selector("selectNextUp(_:)"), to: nil, from: table)
        #expect(table.selectedRow == 0)

        let copyItem = NSMenuItem(title: "Copy", action: Selector("copy(_:)"), keyEquivalent: "c")
        #expect(controller.validateUserInterfaceItem(copyItem))
        let openItem = NSMenuItem(title: "Open", action: Selector("openArticleInBrowser(_:)"), keyEquivalent: "")
        #expect(controller.validateUserInterfaceItem(openItem))

        let pasteboard = NSPasteboard.general
        let savedString = pasteboard.string(forType: .string)
        let savedURL = pasteboard.string(forType: .URL)
        defer {
            pasteboard.clearContents()
            if let savedString {
                pasteboard.setString(savedString, forType: .string)
            }
            if let savedURL {
                pasteboard.setString(savedURL, forType: .URL)
            }
        }

        pasteboard.clearContents()
        _ = NSApplication.shared.sendAction(Selector("copy(_:)"), to: nil, from: table)
        #expect(pasteboard.string(forType: .string)?.contains("First timeline article") == true)
        #expect(pasteboard.string(forType: .URL) == "https://example.com/timeline-1")
    }

    @Test("Timeline contextual menu matches clicked article command surface")
    @MainActor func timelineContextualMenuSurface() throws {
        let controller = TimelineViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        let table = TimelineTableView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        table.tableColumns = [NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "timeline"))]
        table.dataSource = controller
        table.delegate = controller
        table.nextResponder = controller
        controller.tableView = table
        controller.viewDidLoad()

        #expect(controller.contextualMenuForClickedRows() == nil)

        let article = makeTimelineArticle(id: "timeline-menu", title: "Menu article", read: false)
        controller.articles = [article]
        table.reloadData()
        table.clickedRow = 0
        table.selectRow(0)

        let menu = try #require(controller.contextualMenuForClickedRows())
        let commandItems = menu.items.filter { !$0.isSeparatorItem }
        #expect(commandItems.map(\.title) == [
            "Mark as Read",
            "Mark as Starred",
            "Open in Browser",
            "Copy Article URL",
            "Share…",
        ])
        #expect(menu.items.filter(\.isSeparatorItem).count == 3)

        let markReadItem = try #require(commandItems.first { $0.title == "Mark as Read" })
        #expect(markReadItem.target === controller)
        #expect(markReadItem.action?.name == "markArticlesReadFromContextualMenu(_:)")
        let representedArticles = try #require(markReadItem.representedObject as? [Article])
        #expect(representedArticles.count == 1)
        #expect(representedArticles.first === article)

        let openItem = try #require(commandItems.first { $0.title == "Open in Browser" })
        #expect(openItem.action?.name == "openInBrowserFromContextualMenu(_:)")
        #expect(openItem.representedObject as? String == "https://example.com/timeline-menu")
        #expect(openItem.image != nil)

        let copyItem = try #require(commandItems.first { $0.title == "Copy Article URL" })
        #expect(copyItem.action?.name == "copyURLFromContextualMenu(_:)")
        #expect(copyItem.representedObject as? String == "https://example.com/timeline-menu")

        let shareItem = try #require(commandItems.first { $0.title == "Share…" })
        #expect(shareItem.target === controller)
        #expect(shareItem.action?.name == "showShareSheet(_:)")
        #expect(shareItem.isEnabled)

        let dynamicMenu = NSMenu(title: "Dynamic")
        dynamicMenu.addItem(withTitle: "Stale", action: nil, keyEquivalent: "")
        controller.menuNeedsUpdate(dynamicMenu)
        #expect(dynamicMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == commandItems.map(\.title))
    }

    @Test("Main window state objects preserve secure coding payloads")
    @MainActor func mainWindowStateSecureCodingRoundTrip() throws {
        let sidebar = SidebarWindowState(
            isReadFiltered: true,
            expandedContainers: [["containerID": "local"]],
            selectedFeeds: [["feedID": "feed-1"]]
        )
        let timeline = TimelineWindowState(
            readArticlesFilterStateKeys: [["accountID": "local"]],
            readArticlesFilterStateValues: [true],
            selectedAccountID: "local",
            selectedArticleID: "article-1"
        )
        let detail = DetailWindowState(isShowingExtractedArticle: true, windowScrollY: 128.5)
        let state = MainWindowState(
            isFullScreen: true,
            splitViewWidths: [240, 560, 720],
            isSidebarHidden: false,
            sidebarWindowState: sidebar,
            timelineWindowState: timeline,
            detailWindowState: detail
        )

        #expect(MainWindowState.supportsSecureCoding)
        #expect(SidebarWindowState.supportsSecureCoding)
        #expect(TimelineWindowState.supportsSecureCoding)
        #expect(DetailWindowState.supportsSecureCoding)
        #expect(state.description.contains("fullScreen=true"))
        #expect(sidebar.description.contains("readFiltered=true"))
        #expect(timeline.description.contains("accountID=local"))
        #expect(detail.description.contains("scrollY=128.5"))

        let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
        let decoded = try #require(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? MainWindowState)

        #expect(decoded.isFullScreen)
        #expect(decoded.splitViewWidths == [240, 560, 720])
        #expect(!decoded.isSidebarHidden)
        #expect(decoded.sidebarWindowState?.expandedContainers == [["containerID": "local"]])
        #expect(decoded.sidebarWindowState?.selectedFeeds == [["feedID": "feed-1"]])
        #expect(decoded.timelineWindowState?.readArticlesFilterStateKeys == [["accountID": "local"]])
        #expect(decoded.timelineWindowState?.readArticlesFilterStateValues == [true])
        #expect(decoded.timelineWindowState?.selectedArticleID == "article-1")
        #expect(decoded.detailWindowState?.isShowingExtractedArticle == true)
        #expect(decoded.detailWindowState?.windowScrollY == 128.5)
    }

    private func makeTimelineArticle(id: String, title: String, read: Bool) -> Article {
        Article(
            accountID: "account-\(id)",
            articleID: id,
            feedID: "feed-\(id)",
            uniqueID: "unique-\(id)",
            title: title,
            contentHTML: "<p>\(title)</p>",
            contentText: nil,
            markdown: nil,
            url: "https://example.com/\(id)",
            externalURL: nil,
            summary: "Summary for \(title)",
            imageURL: nil,
            datePublished: Date(timeIntervalSince1970: 100),
            dateModified: nil,
            authors: nil,
            status: ArticleStatus(articleID: id, read: read, starred: false, dateArrived: Date(timeIntervalSince1970: 50))
        )
    }

    private func desktopEntry(named name: String) -> String {
        """
        [Desktop Entry]
        Type=Application
        Name=\(name)
        Exec=/bin/true
        """
    }

    private func withPreservedDefaults(_ keys: [String], _ body: () throws -> Void) rethrows {
        let savedValues = keys.map { key in (key, UserDefaults.standard.object(forKey: key)) }
        defer {
            for (key, value) in savedValues {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        try body()
    }

    @MainActor private func withFreshAccountManager<T>(_ body: (AccountManager) throws -> T) rethrows -> T {
        let previous = AccountManager.shared
        let manager = AccountManager()
        AccountManager.shared = manager
        defer {
            AccountManager.shared = previous
        }
        return try body(manager)
    }

    private func makeExternalFeedPasteboard() -> NSPasteboard {
        let feed = PasteboardFeed(
            url: "https://example.com/feed.xml",
            feedID: nil,
            homePageURL: "https://example.com/",
            name: "Example",
            editedName: "Edited Example",
            accountID: nil,
            accountType: nil
        )
        let item = NSPasteboardItem()
        item.setPropertyList(feed.exportDictionary(), forType: FeedPasteboardWriter.feedUTIType)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "NetNewsWireMacCoreSidebarFeedDrop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        _ = pasteboard.writeObjects([item])
        return pasteboard
    }

    private func containsShortcut(
        _ shortcuts: Set<KeyboardShortcut>,
        action: String,
        key: String,
        shift: Bool = false,
        option: Bool = false,
        command: Bool = false,
        control: Bool = false
    ) -> Bool {
        let dictionary: [String: Any] = [
            "action": action,
            "key": key,
            "shiftModifier": shift,
            "optionModifier": option,
            "commandModifier": command,
            "controlModifier": control,
        ]
        guard let shortcut = KeyboardShortcut(dictionary: dictionary) else {
            return false
        }
        return shortcuts.contains(shortcut)
    }

    private func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        return mirror.children.first?.value
    }

    #if os(Linux)
    private func hasBytes(_ image: NSImage?) -> Bool {
        image?.data?.isEmpty == false
    }

    private func data(_ image: NSImage?, hasPrefix prefix: String) -> Bool {
        guard let data = image?.data else { return false }
        return Array(data.prefix(prefix.utf8.count)) == Array(prefix.utf8)
    }

    private func hasPNGSignature(_ image: NSImage?) -> Bool {
        guard let data = image?.data else { return false }
        return Array(data.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10]
    }

    private func color(_ color: NSColor?, equals expected: [CGFloat], accuracy: CGFloat = 0.0001) -> Bool {
        guard let components = color?.components, components.count == expected.count else {
            return false
        }
        return zip(components, expected).allSatisfy { abs($0 - $1) <= accuracy }
    }
    #endif

    @MainActor
    private final class RecordingKeyboardDelegate: KeyboardDelegate {
        private let handled: Bool
        private(set) var eventsHandled = 0
        private(set) weak var lastView: NSView?

        init(handled: Bool) {
            self.handled = handled
        }

        func keydown(_ event: NSEvent, in view: NSView) -> Bool {
            _ = event
            eventsHandled += 1
            lastView = view
            return handled
        }
    }

    @MainActor
    private final class RecordingRenameDelegate: RenameWindowControllerDelegate {
        private(set) weak var windowController: RenameWindowController?
        private(set) weak var renamedObject: NSObject?
        private(set) var newName: String?

        func renameWindowController(_ windowController: RenameWindowController, didRenameObject object: Any, withNewName name: String) {
            self.windowController = windowController
            renamedObject = object as? NSObject
            newName = name
        }
    }

    @MainActor
    private final class RecordingAddFeedDelegate: AddFeedWindowControllerDelegate {
        private(set) weak var windowController: AddFeedWindowController?
        private(set) var enteredURL: URL?
        private(set) var enteredTitle: String?
        private(set) var container: Container?
        private(set) var didCancel = false

        func addFeedWindowController(_ windowController: AddFeedWindowController, userEnteredURL: URL, userEnteredTitle: String?, container: Container) {
            self.windowController = windowController
            enteredURL = userEnteredURL
            enteredTitle = userEnteredTitle
            self.container = container
        }

        func addFeedWindowControllerUserDidCancel(_ windowController: AddFeedWindowController) {
            self.windowController = windowController
            didCancel = true
        }
    }

    @MainActor
    private final class SingleNodeOutlineDataSource: NSObject, NSOutlineViewDataSource {
        private let node: TreeNode

        init(node: TreeNode) {
            self.node = node
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            item == nil ? 1 : 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            node
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            false
        }
    }

    @MainActor
    private final class TestSidebarItem: NSObject, SidebarItem {
        let nameForDisplay: String
        let unreadCount = 0
        var account: Account? { nil }
        var defaultReadFilterType: ReadFilterType { .none }
        var sidebarItemID: SidebarItemIdentifier? { .smartFeed(nameForDisplay) }

        init(name: String) {
            self.nameForDisplay = name
        }

        func fetchArticles() -> Set<Article> { [] }
        func fetchArticlesAsync() async -> Set<Article> { [] }
        func fetchUnreadArticles() -> Set<Article> { [] }
        func fetchUnreadArticlesAsync() async -> Set<Article> { [] }
    }

}

private final class TestDraggingInfo: NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    var draggingLocation = NSPoint(x: 0, y: 0)
    var draggingSource: Any?
    var draggingSourceOperationMask: NSDragOperation = .copy
    var draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(pasteboard: NSPasteboard) {
        self.draggingPasteboard = pasteboard
    }
}
