import Foundation
import QuillKit
import AppKit
import UIKit
import AVFoundation
import Speech
import Magnet
import ServiceManagement
import Sparkle
import Security
import ApplicationServices
import CoreGraphics
import Alamofire
import os

enum AppleCompatibilitySmoke {
    struct AppleServiceResult {
        var pasteboardString: String?
        var pasteboardItemString: String?
        var pasteboardItemDataRoundTrip: Bool
        var pasteboardItemPropertyListRoundTrip: Bool
        var pasteboardItemTypesRoundTrip: Bool
        var pasteboardWriteObjectsItemsRoundTrip: Bool
        var pasteboardWriteObjectsDataRoundTrip: Bool
        var pasteboardReadObjectsRoundTrip: Bool
        var pasteboardClearResetsItems: Bool
        var pasteboardSetStringClearsOldData: Bool
        var pasteboardWriteObjectsClearsOldData: Bool
        var pasteboardDeclareTypesRoundTrip: Bool
        var pasteboardDeclareTypesClearsOldTypes: Bool
        var pasteboardDeclareTypesChangeCount: Bool
        var pasteboardDeclareTypesOwnerProvidesData: Bool
        var pasteboardAvailableTypeOrder: Bool
        var uiPasteboardString: String?
        var imagesRoundTrip: Bool
        var speechStopSucceeded: Bool
        var speechRecognitionUnavailable: Bool
        var launchServiceEnabled: Bool
        var launchServiceDisabled: Bool
        var updaterUnavailable: Bool
    }

    struct DiagnosticFallbackResult {
        var operations: Set<String>
        var speechAuthorizationDenied: Bool
    }

    struct AppKitImageResult {
        var sizeRoundTrip: Bool
        var namedImagePlaceholder: Bool
        var systemImagePlaceholder: Bool
        var workspaceFileIconPlaceholder: Bool
        var workspaceContentTypeIconPlaceholder: Bool
        var bitmapRepresentationRoundTrip: Bool
        var windowTabbingRoundTrip: Bool
        var operations: Set<String>
    }

    struct AppKitMenuResult {
        var popupSucceeded: Bool
        var trackingBegan: Bool
        var rememberedPositioningItem: Bool
        var rememberedLocation: Bool
        var rememberedView: Bool
        var itemMenuBacklinks: Bool
        var submenuParentLink: Bool
        var replacedSubmenuClearedParentLink: Bool
        var clearedSubmenuParentLink: Bool
        var autoValidationDisabledItem: Bool
        var delegateEvents: Set<String>
        var trackingEnded: Bool
        var removedItemClearedMenu: Bool
        var removeAllClearedMenus: Bool
    }

    struct AppKitPopUpButtonResult {
        var firstItemSelectedAfterAdd: Bool
        var selectionFollowsIndex: Bool
        var invalidSelectionPreservesCurrentItem: Bool
        var selectionFollowsTitle: Bool
        var selectionFollowsTag: Bool
        var removedSelectedItemChoosesAdjacentItem: Bool
        var removeAllClearsSelection: Bool
        var menuReplacementSelectsFirstItem: Bool
        var menuItemBacklinks: Bool
    }

    struct AppKitPopoverResult {
        var showUpdatedStateAndAnchor: Bool
        var repeatedShowUpdatedAnchorWithoutDuplicateCallbacks: Bool
        var closeVetoPreservedState: Bool
        var performCloseDelegatedToClose: Bool
        var redundantCloseIgnored: Bool
    }

    struct AppKitToolbarResult {
        var insertedItemsInDelegateOrder: Bool
        var delegateSawInsertedFlag: Bool
        var visibleItemsFollowItems: Bool
        var removedItemUpdatesItems: Bool
        var removingSelectedItemClearsSelection: Bool
        var outOfRangeRemoveIgnored: Bool
    }

    struct AppKitWindowResult {
        var controllerBacklinksRoundTrip: Bool
        var childWindowLinksRoundTrip: Bool
        var childReparentClearsPreviousParent: Bool
        var childRemovalClearsParent: Bool
        var tabbedWindowsRoundTrip: Bool
        var applicationTabIdentifierLookup: Bool
        var sheetLifecycleRoundTrip: Bool
    }

    struct AppKitViewHierarchyResult {
        var addEstablishedLinks: Bool
        var addFiredSuperviewCallbacks: Bool
        var reparentedWithoutDuplicateBacklinks: Bool
        var removalClearedLinks: Bool
        var removalFiredSuperviewCallbacks: Bool
        var windowContentViewPropagated: Bool
        var windowContentViewCleared: Bool
        var windowCallbacksReachedSubview: Bool
    }

    struct AppKitResponderResult {
        var explicitNextResponderRoundTrip: Bool
        var viewDefaultResponderChain: Bool
        var viewControllerOwnsViewResponder: Bool
        var eventForwardingReachesNextResponder: Bool
        var makeFirstResponderCallsLifecycle: Bool
        var rejectedFirstResponderPreservesCurrent: Bool
        var clearingFirstResponderResignsCurrent: Bool
    }

    struct AppKitViewControllerContainmentResult {
        var addEstablishedParentLinks: Bool
        var secondChildPreservedOrder: Bool
        var removeClearedParentLinks: Bool
        var orphanRemoveIgnored: Bool
    }

    struct AppKitSplitViewResult {
        var arrangedSubviewLinks: Bool
        var arrangedSubviewRemovalUpdatedOrder: Bool
        var controllerAddedItemsInOrder: Bool
        var controllerRemoveClearedLinks: Bool
        var factoryBehaviorsRoundTrip: Bool
    }

    struct AppKitTrackingAreaResult {
        var metadataRoundTripped: Bool
        var addRecordedTrackingArea: Bool
        var unknownRemoveIgnored: Bool
        var removeClearedTrackingArea: Bool
    }

    struct AppKitDocumentResult {
        var displayNameFollowsFileURL: Bool
        var changeCountTracksEditedState: Bool
        var windowControllerLinksRoundTrip: Bool
        var documentControllerMaintainsCurrentDocument: Bool
        var openDocumentCreatesAndReusesDocument: Bool
    }

    struct OSLogResult {
        var operations: Set<String>
        var renderedPublicValue: Bool
        var redactedPrivateValue: Bool
    }

    @MainActor
    static func runAppleServiceSmoke() throws -> AppleServiceResult {
        UIPasteboard.general.string = "hello"

        NSPasteboard.general.setString("hello", forType: .string)
        let pasteboardString = NSPasteboard.general.string(forType: .string)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("item text", forType: .string)
        pasteboardItem.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        pasteboardItem.setPropertyList("item title", forType: .html)

        let itemPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.item.\(UUID().uuidString)"))
        _ = itemPasteboard.clearContents()
        _ = itemPasteboard.writeObjects([pasteboardItem])
        let writtenPasteboardItem = itemPasteboard.pasteboardItems?.first
        let pasteboardWriteObjectsItemsRoundTrip =
            itemPasteboard.pasteboardItems?.count == 1 &&
            writtenPasteboardItem?.string(forType: .string) == "item text" &&
            writtenPasteboardItem?.data(forType: .png) == Data([0x89, 0x50, 0x4E, 0x47]) &&
            writtenPasteboardItem?.propertyList(forType: .html) as? String == "item title" &&
            writtenPasteboardItem?.types == [.string, .png, .html]
        let pasteboardWriteObjectsDataRoundTrip =
            itemPasteboard.string(forType: .string) == "item text" &&
            itemPasteboard.data(forType: .png) == Data([0x89, 0x50, 0x4E, 0x47])
        let itemPasteboardAvailableTypeOrder =
            itemPasteboard.availableType(from: [.html, .png]) == .html &&
            itemPasteboard.availableType(from: [.pdf]) == nil
        let readPasteboardString = itemPasteboard.readObjects(forClasses: [NSString.self], options: nil)?.first as? String
        let readPasteboardItem = itemPasteboard.readObjects(forClasses: [NSPasteboardItem.self], options: nil)?.first as? NSPasteboardItem
        let pasteboardReadObjectsItems =
            readPasteboardString == "item text" &&
            readPasteboardItem?.string(forType: .string) == "item text" &&
            itemPasteboard.canReadObject(forClasses: [NSString.self], options: nil) &&
            itemPasteboard.canReadObject(forClasses: [NSPasteboardItem.self], options: nil)
        _ = itemPasteboard.clearContents()
        let pasteboardClearResetsItems =
            itemPasteboard.pasteboardItems == nil &&
            itemPasteboard.string(forType: .string) == nil &&
            itemPasteboard.data(forType: .png) == nil &&
            itemPasteboard.availableType(from: [.string]) == nil

        let replacementPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.replacement.\(UUID().uuidString)"))
        _ = replacementPasteboard.setData(Data([0xCA, 0xFE]), forType: .png)
        _ = replacementPasteboard.setString("fresh", forType: .string)
        let pasteboardSetStringClearsOldData =
            replacementPasteboard.types() == [.string] &&
            replacementPasteboard.data(forType: .png) == nil &&
            replacementPasteboard.string(forType: .string) == "fresh"

        let writeReplacementPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.write-replacement.\(UUID().uuidString)"))
        _ = writeReplacementPasteboard.setData(Data([0xCA, 0xFE]), forType: .png)
        _ = writeReplacementPasteboard.writeObjects(["fresh"])
        let pasteboardWriteObjectsClearsOldData =
            writeReplacementPasteboard.types() == [.string] &&
            writeReplacementPasteboard.data(forType: .png) == nil &&
            writeReplacementPasteboard.string(forType: .string) == "fresh"

        let declaredPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.declared.\(UUID().uuidString)"))
        _ = declaredPasteboard.setString("stale", forType: .string)
        let previousChangeCount = declaredPasteboard.changeCount
        let declaredChangeCount = declaredPasteboard.declareTypes([.png, .html], owner: nil)
        let pasteboardDeclareTypesRoundTrip =
            declaredPasteboard.types() == [.png, .html] &&
            declaredPasteboard.pasteboardItems == nil
        let pasteboardDeclareTypesClearsOldTypes =
            declaredPasteboard.string(forType: .string) == nil &&
            declaredPasteboard.data(forType: .string) == nil
        let pasteboardDeclareTypesChangeCount = declaredChangeCount > previousChangeCount
        _ = declaredPasteboard.setData(Data([0x01, 0x02, 0x03]), forType: .png)
        let pasteboardDeclareTypesRetainedAfterData = declaredPasteboard.types() == [.png, .html]
        let pasteboardAvailableTypeOrder =
            itemPasteboardAvailableTypeOrder &&
            declaredPasteboard.availableType(from: [.html, .png]) == .html &&
            replacementPasteboard.availableType(from: [.png, .string]) == .string

        let urlPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.url.\(UUID().uuidString)"))
        _ = urlPasteboard.setString("https://example.com/upload", forType: .URL)
        let readURL = urlPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? NSURL
        let fileURLPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.file-url.\(UUID().uuidString)"))
        _ = fileURLPasteboard.setString("file:///tmp/quill-read-object.txt", forType: .fileURL)
        let readFileURL = fileURLPasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? NSURL
        let pasteboardReadObjectsURL =
            readURL?.absoluteString == "https://example.com/upload" &&
            readFileURL?.isFileURL == true &&
            fileURLPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
        let pasteboardReadObjectsRoundTrip = pasteboardReadObjectsItems && pasteboardReadObjectsURL

        #if os(Linux)
        let lazyOwner = LazyPasteboardOwner()
        let lazyPasteboard = NSPasteboard(name: .init(rawValue: "quill.compat.lazy.\(UUID().uuidString)"))
        _ = lazyPasteboard.declareTypes([.png], owner: lazyOwner)
        let pasteboardDeclareTypesOwnerProvidesData =
            lazyPasteboard.data(forType: .png) == lazyOwner.payload &&
            lazyOwner.requestedTypes == [.png] &&
            lazyPasteboard.types() == [.png]
        #else
        let pasteboardDeclareTypesOwnerProvidesData = true
        #endif

        let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==")!
        let nsImageTIFF = NSImage(data: imageData)?.tiffRepresentation
        let nsImageTranscoded = nsImageTIFF.map { data in
            let prefix = Array(data.prefix(4))
            return prefix == [0x49, 0x49, 0x2A, 0x00] || prefix == [0x4D, 0x4D, 0x00, 0x2A]
        } ?? false
        let imagesRoundTrip = nsImageTranscoded && UIImage(data: imageData)?.data == imageData

        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: "hello")
        utterance.voice = AVSpeechSynthesisVoice(identifier: "quill.linux.default")
        synthesizer.speak(utterance)

        let recognizer = SFSpeechRecognizer()

        if let combo = KeyCombo(key: .space, cocoaModifiers: [.command]) {
            let hotKey = HotKey(identifier: "space", keyCombo: combo) { key in
                key.unregister()
            }
            hotKey.register()
            hotKey.trigger()
        }

        let service = SMAppService.mainApp
        try service.register()
        let launchServiceEnabled = service.status == .enabled
        try service.unregister()
        let launchServiceDisabled = service.status == .notRegistered

        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        return AppleServiceResult(
            pasteboardString: pasteboardString,
            pasteboardItemString: pasteboardItem.string(forType: .string),
            pasteboardItemDataRoundTrip: pasteboardItem.data(forType: .png) == Data([0x89, 0x50, 0x4E, 0x47]),
            pasteboardItemPropertyListRoundTrip: pasteboardItem.propertyList(forType: .html) as? String == "item title",
            pasteboardItemTypesRoundTrip: pasteboardItem.types == [.string, .png, .html],
            pasteboardWriteObjectsItemsRoundTrip: pasteboardWriteObjectsItemsRoundTrip,
            pasteboardWriteObjectsDataRoundTrip: pasteboardWriteObjectsDataRoundTrip,
            pasteboardReadObjectsRoundTrip: pasteboardReadObjectsRoundTrip,
            pasteboardClearResetsItems: pasteboardClearResetsItems,
            pasteboardSetStringClearsOldData: pasteboardSetStringClearsOldData,
            pasteboardWriteObjectsClearsOldData: pasteboardWriteObjectsClearsOldData,
            pasteboardDeclareTypesRoundTrip: pasteboardDeclareTypesRoundTrip && pasteboardDeclareTypesRetainedAfterData,
            pasteboardDeclareTypesClearsOldTypes: pasteboardDeclareTypesClearsOldTypes,
            pasteboardDeclareTypesChangeCount: pasteboardDeclareTypesChangeCount,
            pasteboardDeclareTypesOwnerProvidesData: pasteboardDeclareTypesOwnerProvidesData,
            pasteboardAvailableTypeOrder: pasteboardAvailableTypeOrder,
            uiPasteboardString: UIPasteboard.general.string,
            imagesRoundTrip: imagesRoundTrip,
            speechStopSucceeded: synthesizer.stopSpeaking(at: .immediate),
            speechRecognitionUnavailable: recognizer?.isAvailable == false,
            launchServiceEnabled: launchServiceEnabled,
            launchServiceDisabled: launchServiceDisabled,
            updaterUnavailable: updater.updater.canCheckForUpdates == false
        )
    }

    static func runLowerLevelServiceSmoke() throws -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, Data([1, 2, 3]) as CFData) else {
            return false
        }
        let trust = SecTrust()
        guard SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess else {
            return false
        }
        SecTrustSetAnchorCertificatesOnly(trust, true)
        guard SecTrustEvaluateWithError(trust, nil) else {
            return false
        }

        guard AXIsProcessTrustedWithOptions(nil) == false else {
            return false
        }
        let element = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute, &value) == .failure else {
            return false
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)

        let trustManager = ServerTrustManager(allHostsMustBeEvaluated: false, evaluators: ["localhost": Evaluator()])
        let session = Session(serverTrustManager: trustManager)
        var responseDidFabricateData = false
        session.request("https://localhost", method: .get)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: CompatibilityResponse.self) { response in
                if case .success = response.result {
                    responseDidFabricateData = true
                }
            }
        return responseDidFabricateData == false
    }

    @MainActor
    static func runDiagnosticFallbackSmoke() throws -> DiagnosticFallbackResult {
        QuillCompatibilityDiagnostics.shared.clear()

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UINotificationFeedbackGenerator().notificationOccurred(.warning)

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(AVSpeechUtterance(string: "hello"))

        var authorizationStatus: SFSpeechRecognizerAuthorizationStatus?
        SFSpeechRecognizer.requestAuthorization { status in
            authorizationStatus = status
        }
        _ = SFSpeechRecognizer()?.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, _ in }

        _ = CGEventSource.keyState(.combinedSessionState, key: 42)
        CGEvent(keyboardEventSource: CGEventSource(stateID: .combinedSessionState), virtualKey: 42, keyDown: true)?
            .post(tap: .cghidEventTap)
        QuillHotkeyService.shared.registerSingleUseSpace(modifiers: []) {
            nil
        }

        _ = SecTrustEvaluateWithError(SecTrust(), nil)

        try SMAppService.mainApp.register()
        try SMAppService.mainApp.unregister()

        return DiagnosticFallbackResult(
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation)),
            speechAuthorizationDenied: authorizationStatus == .denied
        )
    }

    static func runAppKitImageSmoke() throws -> AppKitImageResult {
        QuillCompatibilityDiagnostics.shared.clear()

        let size = NSSize(width: 24, height: 16)
        let image = NSImage(size: size)
        let sizeRoundTrip = image.size == size
        image.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: 24, height: 16),
            from: NSRect(x: 0, y: 0, width: 12, height: 8),
            operation: .copy,
            fraction: 0.5
        )
        image.unlockFocus()

        let namedImage = NSImage(named: "StatusBarIcon")
        let systemImage = NSImage(systemName: "paperplane.fill")
        let workspaceFileIcon = NSWorkspace.shared.icon(forFile: "/tmp/enchanted-export.txt")
        let workspaceContentTypeIcon = NSWorkspace.shared.icon(forContentType: "public.plain-text")
        let encoded = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let rep = NSBitmapImageRep(data: encoded)
        NSWindow.allowsAutomaticWindowTabbing = false
        let windowTabbingRoundTrip = NSWindow.allowsAutomaticWindowTabbing == false
        NSWindow.allowsAutomaticWindowTabbing = true

        return AppKitImageResult(
            sizeRoundTrip: sizeRoundTrip,
            namedImagePlaceholder: namedImage?.size == CGSize(width: 1, height: 1),
            systemImagePlaceholder: systemImage?.size == CGSize(width: 1, height: 1),
            workspaceFileIconPlaceholder: workspaceFileIcon.size == CGSize(width: 1, height: 1),
            workspaceContentTypeIconPlaceholder: workspaceContentTypeIcon.size == CGSize(width: 1, height: 1),
            bitmapRepresentationRoundTrip: rep?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) == encoded,
            windowTabbingRoundTrip: windowTabbingRoundTrip,
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        )
    }

    @MainActor
    static func runAppKitMenuSmoke() -> AppKitMenuResult {
        let menu = NSMenu(title: "Chat")
        let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "c")
        let disabledItem = NSMenuItem(title: "Disabled", action: nil, keyEquivalent: "")
        let validator = MenuItemValidator(enabled: false)
        disabledItem.target = validator

        menu.addItem(copyItem)
        menu.addItem(disabledItem)
        let submenu = NSMenu(title: "Nested")
        menu.setSubmenu(submenu, for: copyItem)
        let replacementSubmenu = NSMenu(title: "Replacement")
        menu.setSubmenu(replacementSubmenu, for: copyItem)
        let replacedSubmenuClearedParentLink =
            submenu.supermenu == nil &&
            replacementSubmenu.supermenu === menu
        menu.setSubmenu(nil, for: copyItem)
        let clearedSubmenuParentLink =
            replacementSubmenu.supermenu == nil &&
            copyItem.submenu == nil
        menu.setSubmenu(submenu, for: copyItem)

        let delegate = MenuDelegateProbe()
        menu.delegate = delegate
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        let location = NSPoint(x: 12, y: 34)

        let didShow = menu.popUp(positioning: copyItem, at: location, in: anchorView)
        let trackingBegan = menu.isTracking
        let rememberedPositioningItem = menu.lastPopUpPositioningItem === copyItem
        let rememberedLocation = menu.lastPopUpLocation == location
        let rememberedView = menu.lastPopUpView === anchorView
        let itemMenuBacklinks = copyItem.menu === menu && disabledItem.menu === menu
        let submenuParentLink = submenu.supermenu === menu
        let autoValidationDisabledItem = !disabledItem.isEnabled

        menu.cancelTracking()
        let trackingEnded = !menu.isTracking && delegate.events.last == "didClose:Chat"

        menu.removeItem(copyItem)
        let removedItemClearedMenu = copyItem.menu == nil
        menu.removeAllItems()
        let removeAllClearedMenus = disabledItem.menu == nil

        return AppKitMenuResult(
            popupSucceeded: didShow,
            trackingBegan: trackingBegan,
            rememberedPositioningItem: rememberedPositioningItem,
            rememberedLocation: rememberedLocation,
            rememberedView: rememberedView,
            itemMenuBacklinks: itemMenuBacklinks,
            submenuParentLink: submenuParentLink,
            replacedSubmenuClearedParentLink: replacedSubmenuClearedParentLink,
            clearedSubmenuParentLink: clearedSubmenuParentLink,
            autoValidationDisabledItem: autoValidationDisabledItem,
            delegateEvents: Set(delegate.events),
            trackingEnded: trackingEnded,
            removedItemClearedMenu: removedItemClearedMenu,
            removeAllClearedMenus: removeAllClearedMenus
        )
    }

    @MainActor
    static func runAppKitToolbarSmoke() -> AppKitToolbarResult {
        let toolbar = NSToolbar(identifier: "main")
        let delegate = ToolbarDelegateProbe()
        toolbar.delegate = delegate

        let accountID = NSToolbarItem.Identifier(rawValue: "account")
        let promptID = NSToolbarItem.Identifier(rawValue: "prompt")
        let exportID = NSToolbarItem.Identifier(rawValue: "export")

        toolbar.insertItem(withItemIdentifier: accountID, at: 0)
        toolbar.insertItem(withItemIdentifier: exportID, at: 99)
        toolbar.insertItem(withItemIdentifier: promptID, at: 1)

        let expectedOrder = [accountID, promptID, exportID]
        let insertedItemsInDelegateOrder = toolbar.items.map(\.itemIdentifier) == expectedOrder
        let delegateSawInsertedFlag = delegate.requests == [
            "account:true",
            "export:true",
            "prompt:true"
        ]
        let visibleItemsFollowItems = toolbar.visibleItems?.map(\.itemIdentifier) == expectedOrder

        toolbar.selectedItemIdentifier = promptID
        toolbar.removeItem(at: 1)
        let afterRemovalOrder = [accountID, exportID]
        let removedItemUpdatesItems =
            toolbar.items.map(\.itemIdentifier) == afterRemovalOrder &&
            toolbar.visibleItems?.map(\.itemIdentifier) == afterRemovalOrder
        let removingSelectedItemClearsSelection = toolbar.selectedItemIdentifier == nil

        toolbar.removeItem(at: 99)
        let outOfRangeRemoveIgnored = toolbar.items.map(\.itemIdentifier) == afterRemovalOrder

        return AppKitToolbarResult(
            insertedItemsInDelegateOrder: insertedItemsInDelegateOrder,
            delegateSawInsertedFlag: delegateSawInsertedFlag,
            visibleItemsFollowItems: visibleItemsFollowItems,
            removedItemUpdatesItems: removedItemUpdatesItems,
            removingSelectedItemClearsSelection: removingSelectedItemClearsSelection,
            outOfRangeRemoveIgnored: outOfRangeRemoveIgnored
        )
    }

    @MainActor
    static func runAppKitWindowSmoke() -> AppKitWindowResult {
        let firstWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let secondWindow = NSWindow(
            contentRect: NSRect(x: 20, y: 20, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = NSWindowController(window: firstWindow)
        let initialControllerLink =
            controller.window === firstWindow &&
            firstWindow.windowController === controller

        controller.window = secondWindow
        let reassignedControllerLink =
            controller.window === secondWindow &&
            secondWindow.windowController === controller &&
            firstWindow.windowController == nil

        controller.window = nil
        let clearedControllerLink =
            controller.window == nil &&
            secondWindow.windowController == nil
        let controllerBacklinksRoundTrip =
            initialControllerLink &&
            reassignedControllerLink &&
            clearedControllerLink

        let parent = NSWindow()
        let child = NSWindow()
        let sibling = NSWindow()
        let newParent = NSWindow()
        parent.addChildWindow(child, ordered: .above)
        parent.addChildWindow(sibling, ordered: .below)
        parent.addChildWindow(child, ordered: .above)

        let parentChildren = parent.childWindows ?? []
        let childWindowLinksRoundTrip =
            parentChildren.count == 2 &&
            parentChildren.first === sibling &&
            parentChildren.last === child &&
            child.parentWindow === parent &&
            sibling.parentWindow === parent

        newParent.addChildWindow(child, ordered: .above)
        let parentChildrenAfterReparent = parent.childWindows ?? []
        let newParentChildren = newParent.childWindows ?? []
        let childReparentClearsPreviousParent =
            child.parentWindow === newParent &&
            !parentChildrenAfterReparent.contains { $0 === child } &&
            newParentChildren.contains { $0 === child }

        parent.removeChildWindow(sibling)
        let parentChildrenAfterRemoval = parent.childWindows ?? []
        let childRemovalClearsParent =
            sibling.parentWindow == nil &&
            !parentChildrenAfterRemoval.contains { $0 === sibling }

        let tabParent = NSWindow()
        let firstTab = NSWindow()
        let secondTab = NSWindow()
        tabParent.addTabbedWindow(firstTab, ordered: .above)
        tabParent.addTabbedWindow(secondTab, ordered: .below)
        tabParent.addTabbedWindow(firstTab, ordered: .above)
        let tabbedWindows = tabParent.tabbedWindows ?? []
        let tabbedWindowsRoundTrip =
            tabbedWindows.count == 2 &&
            tabbedWindows.first === secondTab &&
            tabbedWindows.last === firstTab

        let app = NSApplication.shared
        let oldWindows = app.windows
        let oldKeyWindow = app.keyWindow
        let oldMainWindow = app.mainWindow
        defer {
            app.windows = oldWindows
            app.keyWindow = oldKeyWindow
            app.mainWindow = oldMainWindow
        }
        let matchingTabWindow = NSWindow()
        matchingTabWindow.tabbingIdentifier = "enchanted.chat"
        let otherTabWindow = NSWindow()
        otherTabWindow.tabbingIdentifier = "other"
        app.windows = [otherTabWindow, matchingTabWindow]
        let tabMatches = app.windows(withTabIdentifier: "enchanted.chat")
        let applicationTabIdentifierLookup =
            tabMatches.count == 1 &&
            tabMatches.first === matchingTabWindow

        let sheetParent = NSWindow()
        let sheet = NSWindow()
        var sheetResponse: NSApplication.ModalResponse?
        sheetParent.beginSheet(sheet) { response in
            sheetResponse = response
        }
        let sheetStarted =
            sheetParent.sheets.count == 1 &&
            sheetParent.sheets.first === sheet &&
            sheet.sheetParent === sheetParent &&
            sheet.isVisible
        sheetParent.endSheet(sheet, returnCode: .cancel)
        let sheetLifecycleRoundTrip =
            sheetStarted &&
            sheetParent.sheets.isEmpty &&
            sheet.sheetParent == nil &&
            sheet.isVisible == false &&
            sheetResponse == .cancel

        return AppKitWindowResult(
            controllerBacklinksRoundTrip: controllerBacklinksRoundTrip,
            childWindowLinksRoundTrip: childWindowLinksRoundTrip,
            childReparentClearsPreviousParent: childReparentClearsPreviousParent,
            childRemovalClearsParent: childRemovalClearsParent,
            tabbedWindowsRoundTrip: tabbedWindowsRoundTrip,
            applicationTabIdentifierLookup: applicationTabIdentifierLookup,
            sheetLifecycleRoundTrip: sheetLifecycleRoundTrip
        )
    }

    static func runAppKitPopUpButtonSmoke() -> AppKitPopUpButtonResult {
        let popup = NSPopUpButton()
        popup.addItem(withTitle: "Local")
        let firstItem = popup.itemArray[0]
        let firstItemSelectedAfterAdd =
            popup.selectedItem === firstItem &&
            popup.indexOfSelectedItem == 0 &&
            popup.titleOfSelectedItem == "Local"

        popup.addItem(withTitle: "Remote")
        let secondItem = popup.itemArray[1]
        secondItem.tag = 42

        popup.selectItem(at: 1)
        let selectionFollowsIndex =
            popup.selectedItem === secondItem &&
            popup.indexOfSelectedItem == 1 &&
            popup.titleOfSelectedItem == "Remote"

        popup.selectItem(at: 99)
        let invalidSelectionPreservesCurrentItem =
            popup.selectedItem === secondItem &&
            popup.indexOfSelectedItem == 1 &&
            popup.titleOfSelectedItem == "Remote"

        popup.selectItem(withTitle: "Local")
        let selectionFollowsTitle =
            popup.selectedItem === firstItem &&
            popup.indexOfSelectedItem == 0 &&
            popup.titleOfSelectedItem == "Local"

        let foundTaggedItem = popup.selectItem(withTag: 42)
        let selectionFollowsTag =
            foundTaggedItem &&
            popup.selectedItem === secondItem &&
            popup.indexOfSelectedItem == 1 &&
            popup.titleOfSelectedItem == "Remote"

        popup.removeItem(at: 1)
        let removedSelectedItemChoosesAdjacentItem =
            popup.selectedItem === firstItem &&
            popup.indexOfSelectedItem == 0 &&
            popup.titleOfSelectedItem == "Local" &&
            popup.numberOfItems == 1

        popup.removeAllItems()
        let removeAllClearsSelection =
            popup.selectedItem == nil &&
            popup.indexOfSelectedItem == -1 &&
            popup.titleOfSelectedItem == nil &&
            popup.numberOfItems == 0

        let replacementMenu = NSMenu(title: "Models")
        let cloudItem = NSMenuItem(title: "Cloud", action: nil, keyEquivalent: "")
        let localItem = NSMenuItem(title: "Local", action: nil, keyEquivalent: "")
        replacementMenu.addItem(cloudItem)
        replacementMenu.addItem(localItem)
        popup.menu = replacementMenu
        let menuReplacementSelectsFirstItem =
            popup.selectedItem === cloudItem &&
            popup.indexOfSelectedItem == 0 &&
            popup.titleOfSelectedItem == "Cloud"
        let menuItemBacklinks =
            cloudItem.menu === replacementMenu &&
            localItem.menu === replacementMenu

        return AppKitPopUpButtonResult(
            firstItemSelectedAfterAdd: firstItemSelectedAfterAdd,
            selectionFollowsIndex: selectionFollowsIndex,
            invalidSelectionPreservesCurrentItem: invalidSelectionPreservesCurrentItem,
            selectionFollowsTitle: selectionFollowsTitle,
            selectionFollowsTag: selectionFollowsTag,
            removedSelectedItemChoosesAdjacentItem: removedSelectedItemChoosesAdjacentItem,
            removeAllClearsSelection: removeAllClearsSelection,
            menuReplacementSelectsFirstItem: menuReplacementSelectsFirstItem,
            menuItemBacklinks: menuItemBacklinks
        )
    }

    @MainActor
    static func runAppKitPopoverSmoke() -> AppKitPopoverResult {
        let popover = NSPopover()
        let delegate = PopoverDelegateProbe()
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 48))
        let firstRect = NSRect(x: 8, y: 6, width: 24, height: 18)
        popover.delegate = delegate

        popover.show(relativeTo: firstRect, of: anchorView, preferredEdge: .maxY)
        let showUpdatedStateAndAnchor =
            popover.isShown &&
            popover.lastPresentationRect == firstRect &&
            popover.lastPresentationView === anchorView &&
            popover.lastPresentationEdge == .maxY &&
            delegate.events == ["willShow:true", "didShow:true"]

        let secondRect = NSRect(x: 12, y: 9, width: 30, height: 20)
        popover.show(relativeTo: secondRect, of: anchorView, preferredEdge: .minX)
        let repeatedShowUpdatedAnchorWithoutDuplicateCallbacks =
            popover.isShown &&
            popover.lastPresentationRect == secondRect &&
            popover.lastPresentationView === anchorView &&
            popover.lastPresentationEdge == .minX &&
            delegate.events == ["willShow:true", "didShow:true"]

        delegate.allowsClose = false
        popover.close()
        let closeVetoPreservedState =
            popover.isShown &&
            delegate.shouldCloseRequests == 1 &&
            delegate.events == ["willShow:true", "didShow:true"]

        delegate.allowsClose = true
        popover.performClose(nil)
        let closeEvents = ["willShow:true", "didShow:true", "willClose:true", "didClose:true"]
        let performCloseDelegatedToClose =
            !popover.isShown &&
            delegate.shouldCloseRequests == 2 &&
            delegate.events == closeEvents

        popover.close()
        let redundantCloseIgnored =
            !popover.isShown &&
            delegate.shouldCloseRequests == 2 &&
            delegate.events == closeEvents

        return AppKitPopoverResult(
            showUpdatedStateAndAnchor: showUpdatedStateAndAnchor,
            repeatedShowUpdatedAnchorWithoutDuplicateCallbacks: repeatedShowUpdatedAnchorWithoutDuplicateCallbacks,
            closeVetoPreservedState: closeVetoPreservedState,
            performCloseDelegatedToClose: performCloseDelegatedToClose,
            redundantCloseIgnored: redundantCloseIgnored
        )
    }

    @MainActor
    static func runAppKitViewHierarchySmoke() -> AppKitViewHierarchyResult {
        let parent = NSView()
        let child = ViewHierarchyProbe()

        parent.addSubview(child)
        let addEstablishedLinks =
            child.superview === parent &&
            parent.subviews.contains { $0 === child }
        let addFiredSuperviewCallbacks =
            child.events.contains("willSuperview:true") &&
            child.events.contains("didSuperview:true")

        let newParent = NSView()
        newParent.addSubview(child)
        let reparentedWithoutDuplicateBacklinks =
            child.superview === newParent &&
            !parent.subviews.contains { $0 === child } &&
            newParent.subviews.filter { $0 === child }.count == 1

        child.removeFromSuperview()
        let removalClearedLinks =
            child.superview == nil &&
            !newParent.subviews.contains { $0 === child }
        let removalFiredSuperviewCallbacks =
            child.events.contains("willSuperview:false") &&
            child.events.contains("didSuperview:false")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let contentView = ViewHierarchyProbe()
        let nestedView = ViewHierarchyProbe()
        contentView.addSubview(nestedView)
        contentView.events.removeAll()
        nestedView.events.removeAll()

        window.contentView = contentView
        let windowContentViewPropagated =
            contentView.window === window &&
            nestedView.window === window
        let windowCallbacksReachedSubview =
            contentView.events.contains("willWindow:true") &&
            contentView.events.contains("didWindow:true") &&
            nestedView.events.contains("willWindow:true") &&
            nestedView.events.contains("didWindow:true")

        window.contentView = nil
        let windowContentViewCleared =
            contentView.window == nil &&
            nestedView.window == nil

        return AppKitViewHierarchyResult(
            addEstablishedLinks: addEstablishedLinks,
            addFiredSuperviewCallbacks: addFiredSuperviewCallbacks,
            reparentedWithoutDuplicateBacklinks: reparentedWithoutDuplicateBacklinks,
            removalClearedLinks: removalClearedLinks,
            removalFiredSuperviewCallbacks: removalFiredSuperviewCallbacks,
            windowContentViewPropagated: windowContentViewPropagated,
            windowContentViewCleared: windowContentViewCleared,
            windowCallbacksReachedSubview: windowCallbacksReachedSubview
        )
    }

    @MainActor
    static func runAppKitResponderSmoke() -> AppKitResponderResult {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let root = NSView()
        let child = NSView()
        root.addSubview(child)
        window.contentView = root

        let explicit = EventRecorderResponder()
        child.nextResponder = explicit
        let explicitNextResponderRoundTrip = child.nextResponder === explicit
        child.nextResponder = nil
        let viewDefaultResponderChain =
            child.nextResponder === root &&
            root.nextResponder === window

        let viewController = NSViewController()
        let controllerView = NSView()
        viewController.view = controllerView
        let viewControllerOwnsViewResponder = controllerView.nextResponder === viewController

        let recorder = EventRecorderResponder()
        let sender = NSResponder()
        sender.nextResponder = recorder
        let event = NSEvent()
        sender.keyDown(with: event)
        sender.mouseDown(with: event)
        sender.scrollWheel(with: event)
        let eventForwardingReachesNextResponder =
            recorder.events == ["keyDown", "mouseDown", "scrollWheel"]

        let lifecycleWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let first = EventRecorderResponder()
        let second = EventRecorderResponder()
        let rejecting = RejectingResponder()
        let acceptedFirst = lifecycleWindow.makeFirstResponder(first)
        let switched = lifecycleWindow.makeFirstResponder(second)
        let rejected = lifecycleWindow.makeFirstResponder(rejecting)
        let makeFirstResponderCallsLifecycle =
            acceptedFirst &&
            switched &&
            first.events == ["become", "resign"] &&
            second.events == ["become"] &&
            lifecycleWindow.firstResponder === second
        let rejectedFirstResponderPreservesCurrent =
            !rejected &&
            lifecycleWindow.firstResponder === second &&
            rejecting.becomeAttempts == 0
        let cleared = lifecycleWindow.makeFirstResponder(nil)
        let clearingFirstResponderResignsCurrent =
            cleared &&
            lifecycleWindow.firstResponder == nil &&
            second.events == ["become", "resign"]

        return AppKitResponderResult(
            explicitNextResponderRoundTrip: explicitNextResponderRoundTrip,
            viewDefaultResponderChain: viewDefaultResponderChain,
            viewControllerOwnsViewResponder: viewControllerOwnsViewResponder,
            eventForwardingReachesNextResponder: eventForwardingReachesNextResponder,
            makeFirstResponderCallsLifecycle: makeFirstResponderCallsLifecycle,
            rejectedFirstResponderPreservesCurrent: rejectedFirstResponderPreservesCurrent,
            clearingFirstResponderResignsCurrent: clearingFirstResponderResignsCurrent
        )
    }

    @MainActor
    static func runAppKitViewControllerContainmentSmoke() -> AppKitViewControllerContainmentResult {
        let parent = NSViewController()
        let firstChild = NSViewController()
        let secondChild = NSViewController()

        parent.addChild(firstChild)
        let addEstablishedParentLinks =
            firstChild.parent === parent &&
            parent.children.contains { $0 === firstChild }

        parent.addChild(secondChild)
        let secondChildPreservedOrder =
            parent.children.count == 2 &&
            parent.children[0] === firstChild &&
            parent.children[1] === secondChild &&
            secondChild.parent === parent

        firstChild.removeFromParent()
        let removeClearedParentLinks =
            firstChild.parent == nil &&
            !parent.children.contains { $0 === firstChild } &&
            parent.children.contains { $0 === secondChild }

        let orphan = NSViewController()
        orphan.removeFromParent()
        let orphanRemoveIgnored = orphan.parent == nil

        return AppKitViewControllerContainmentResult(
            addEstablishedParentLinks: addEstablishedParentLinks,
            secondChildPreservedOrder: secondChildPreservedOrder,
            removeClearedParentLinks: removeClearedParentLinks,
            orphanRemoveIgnored: orphanRemoveIgnored
        )
    }

    @MainActor
    static func runAppKitSplitViewSmoke() -> AppKitSplitViewResult {
        let splitView = NSSplitView()
        let first = NSView()
        let second = NSView()

        splitView.addArrangedSubview(first)
        splitView.insertArrangedSubview(second, at: 0)
        let arrangedSubviewLinks =
            splitView.arrangedSubviews.count == 2 &&
            splitView.arrangedSubviews[0] === second &&
            splitView.arrangedSubviews[1] === first &&
            first.superview === splitView &&
            second.superview === splitView &&
            splitView.subviews.contains { $0 === first } &&
            splitView.subviews.contains { $0 === second }

        splitView.removeArrangedSubview(second)
        let arrangedSubviewRemovalUpdatedOrder =
            splitView.arrangedSubviews.count == 1 &&
            splitView.arrangedSubviews.first === first &&
            !splitView.arrangedSubviews.contains { $0 === second }

        let controller = NSSplitViewController()
        let sidebarController = NSViewController()
        let contentController = NSViewController()
        let sidebarItem = NSSplitViewItem.sidebar(with: sidebarController)
        let contentItem = NSSplitViewItem.contentListWithViewController(contentController)
        controller.addSplitViewItem(contentItem)
        controller.insertSplitViewItem(sidebarItem, at: 0)
        let controllerAddedItemsInOrder =
            controller.splitViewItems.count == 2 &&
            controller.splitViewItems[0] === sidebarItem &&
            controller.splitViewItems[1] === contentItem &&
            controller.splitView.arrangedSubviews.count == 2 &&
            controller.splitView.arrangedSubviews[0] === sidebarController.view &&
            controller.splitView.arrangedSubviews[1] === contentController.view &&
            sidebarController.parent === controller &&
            contentController.parent === controller

        controller.removeSplitViewItem(sidebarItem)
        let controllerRemoveClearedLinks =
            controller.splitViewItems.count == 1 &&
            controller.splitViewItems.first === contentItem &&
            controller.splitView.arrangedSubviews.count == 1 &&
            controller.splitView.arrangedSubviews.first === contentController.view &&
            sidebarController.parent == nil &&
            contentController.parent === controller

        let inspectorItem = NSSplitViewItem.inspector(with: NSViewController())
        let factoryBehaviorsRoundTrip =
            sidebarItem.behavior == .sidebar &&
            contentItem.behavior == .contentList &&
            inspectorItem.behavior == .inspector

        return AppKitSplitViewResult(
            arrangedSubviewLinks: arrangedSubviewLinks,
            arrangedSubviewRemovalUpdatedOrder: arrangedSubviewRemovalUpdatedOrder,
            controllerAddedItemsInOrder: controllerAddedItemsInOrder,
            controllerRemoveClearedLinks: controllerRemoveClearedLinks,
            factoryBehaviorsRoundTrip: factoryBehaviorsRoundTrip
        )
    }

    @MainActor
    static func runAppKitTrackingAreaSmoke() -> AppKitTrackingAreaResult {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        let owner = TrackingAreaOwnerProbe()
        let rect = NSRect(x: 4, y: 6, width: 24, height: 16)
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: owner,
            userInfo: ["purpose": "hover"]
        )

        let metadataRoundTripped =
            area.rect == rect &&
            area.options.contains(.mouseEnteredAndExited) &&
            area.options.contains(.activeAlways) &&
            (area.owner as AnyObject?) === owner &&
            (area.userInfo?["purpose"] as? String) == "hover"

        view.addTrackingArea(area)
        let addRecordedTrackingArea = view.trackingAreas.contains { $0 === area }

        let unknownArea = NSTrackingArea(rect: .zero, options: [.activeAlways], owner: nil, userInfo: nil)
        view.removeTrackingArea(unknownArea)
        let unknownRemoveIgnored = view.trackingAreas.contains { $0 === area }

        view.removeTrackingArea(area)
        let removeClearedTrackingArea = !view.trackingAreas.contains { $0 === area }

        return AppKitTrackingAreaResult(
            metadataRoundTripped: metadataRoundTripped,
            addRecordedTrackingArea: addRecordedTrackingArea,
            unknownRemoveIgnored: unknownRemoveIgnored,
            removeClearedTrackingArea: removeClearedTrackingArea
        )
    }

    @MainActor
    static func runAppKitDocumentSmoke() -> AppKitDocumentResult {
        let url = URL(fileURLWithPath: "/tmp/enchanted-session.quill")
        let document = NSDocument()
        document.fileURL = url
        let displayNameFollowsFileURL = document.displayName == "enchanted-session.quill"

        let startedClean = !document.isDocumentEdited && !document.hasUnautosavedChanges
        document.updateChangeCount(.changeDone)
        let markedChanged = document.isDocumentEdited && document.hasUnautosavedChanges
        document.updateChangeCount(.changeUndone)
        let markedUndone = !document.isDocumentEdited && !document.hasUnautosavedChanges
        document.updateChangeCount(.changeRedone)
        let markedRedone = document.isDocumentEdited && document.hasUnautosavedChanges
        document.updateChangeCount(.changeAutosaved)
        let markedAutosaved = !document.isDocumentEdited && !document.hasUnautosavedChanges
        document.updateChangeCount(.changeReadOtherContents)
        document.updateChangeCount(.changeCleared)
        let markedCleared = !document.isDocumentEdited && !document.hasUnautosavedChanges
        let changeCountTracksEditedState =
            startedClean &&
            markedChanged &&
            markedUndone &&
            markedRedone &&
            markedAutosaved &&
            markedCleared

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let windowController = NSWindowController(window: window)
        document.addWindowController(windowController)
        document.addWindowController(windowController)
        let addedController =
            document.windowControllers.count == 1 &&
            document.windowControllers.first === windowController &&
            windowController.document === document
        document.showWindows()
        let shownController = window.isVisible && window.isKeyWindow
        document.removeWindowController(windowController)
        let removedController =
            document.windowControllers.isEmpty &&
            windowController.document == nil
        let windowControllerLinksRoundTrip = addedController && shownController && removedController

        let controller = NSDocumentController()
        controller.addDocument(document)
        let secondDocument = NSDocument()
        controller.addDocument(secondDocument)
        controller.removeDocument(secondDocument)
        let returnedToPreviousDocument =
            controller.documents.count == 1 &&
            controller.documents.first === document &&
            controller.currentDocument === document
        controller.removeDocument(document)
        let documentControllerMaintainsCurrentDocument =
            returnedToPreviousDocument &&
            controller.documents.isEmpty &&
            controller.currentDocument == nil

        let openController = NSDocumentController()
        var openedDocument: NSDocument?
        var openedAlready = true
        var openedError: Error?
        openController.openDocument(withContentsOf: url, display: false) { document, alreadyOpen, error in
            openedDocument = document
            openedAlready = alreadyOpen
            openedError = error
        }

        var reopenedDocument: NSDocument?
        var reopenedAlready = false
        var reopenedError: Error?
        openController.openDocument(withContentsOf: url, display: false) { document, alreadyOpen, error in
            reopenedDocument = document
            reopenedAlready = alreadyOpen
            reopenedError = error
        }

        let openDocumentCreatesAndReusesDocument =
            openedError == nil &&
            reopenedError == nil &&
            openedDocument?.fileURL == url &&
            openedDocument?.fileType == "quill" &&
            openedAlready == false &&
            reopenedDocument === openedDocument &&
            reopenedAlready &&
            openController.documents.count == 1 &&
            openController.currentDocument === openedDocument

        return AppKitDocumentResult(
            displayNameFollowsFileURL: displayNameFollowsFileURL,
            changeCountTracksEditedState: changeCountTracksEditedState,
            windowControllerLinksRoundTrip: windowControllerLinksRoundTrip,
            documentControllerMaintainsCurrentDocument: documentControllerMaintainsCurrentDocument,
            openDocumentCreatesAndReusesDocument: openDocumentCreatesAndReusesDocument
        )
    }

    static func runOSLogSmoke() -> OSLogResult {
        QuillCompatibilityDiagnostics.shared.clear()

        let logger = Logger(subsystem: "co.lorehex.quillchat", category: "usb-launcher")
        logger.info("public value: \("visible", privacy: .public)")
        logger.error("private value: \("hidden", privacy: .private)")

        let messages = QuillCompatibilityDiagnostics.shared.events.map(\.message).joined(separator: "\n")
        return OSLogResult(
            operations: Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation)),
            renderedPublicValue: messages.contains("visible"),
            redactedPrivateValue: messages.contains("<private>") && !messages.contains("hidden")
        )
    }
}

#if os(Linux)
private final class LazyPasteboardOwner: NSPasteboardOwner {
    let payload = Data([0xDE, 0xAD, 0xBE, 0xEF])
    private(set) var requestedTypes: [NSPasteboard.PasteboardType] = []

    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        requestedTypes.append(type)
        if type == .png {
            sender.setData(payload, forType: .png)
        }
    }
}
#endif

private struct Evaluator: ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws {}
}

private struct CompatibilityResponse: Decodable {
    var value: String
}

private final class MenuItemValidator: NSObject, NSMenuItemValidation {
    let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        enabled
    }
}

@MainActor
private final class MenuDelegateProbe: NSObject, NSMenuDelegate {
    var events: [String] = []

    func menuWillOpen(_ menu: NSMenu) {
        events.append("willOpen:\(menu.title)")
    }

    func menuDidClose(_ menu: NSMenu) {
        events.append("didClose:\(menu.title)")
    }

    func numberOfItems(in menu: NSMenu) -> Int {
        events.append("numberOfItems:\(menu.items.count)")
        return menu.items.count
    }

    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        events.append("update:\(item.title):\(index):\(shouldCancel)")
        return false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        events.append("needsUpdate:\(menu.title)")
    }
}

@MainActor
private final class ToolbarDelegateProbe: NSObject, NSToolbarDelegate {
    var requests: [String] = []

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            NSToolbarItem.Identifier(rawValue: "account"),
            NSToolbarItem.Identifier(rawValue: "prompt"),
            NSToolbarItem.Identifier(rawValue: "export")
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        requests.append("\(id.rawValue):\(flag)")
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = id.rawValue
        return item
    }
}

private final class PopoverDelegateProbe: NSObject, NSPopoverDelegate {
    var events: [String] = []
    var allowsClose = true
    var shouldCloseRequests = 0

    func popoverWillShow(_ notification: Notification) {
        events.append("willShow:\((notification.object as? NSPopover) != nil)")
    }

    func popoverDidShow(_ notification: Notification) {
        events.append("didShow:\((notification.object as? NSPopover) != nil)")
    }

    func popoverWillClose(_ notification: Notification) {
        events.append("willClose:\((notification.object as? NSPopover) != nil)")
    }

    func popoverDidClose(_ notification: Notification) {
        events.append("didClose:\((notification.object as? NSPopover) != nil)")
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        shouldCloseRequests += 1
        return allowsClose
    }
}

private final class EventRecorderResponder: NSResponder {
    var events: [String] = []

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        events.append("become")
        return true
    }

    override func resignFirstResponder() -> Bool {
        events.append("resign")
        return true
    }

    override func keyDown(with event: NSEvent) {
        events.append("keyDown")
    }

    override func mouseDown(with event: NSEvent) {
        events.append("mouseDown")
    }

    override func scrollWheel(with event: NSEvent) {
        events.append("scrollWheel")
    }
}

private final class RejectingResponder: NSResponder {
    var becomeAttempts = 0

    override var acceptsFirstResponder: Bool { false }

    override func becomeFirstResponder() -> Bool {
        becomeAttempts += 1
        return false
    }
}

private final class ViewHierarchyProbe: NSView {
    var events: [String] = []

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        events.append("willSuperview:\(newSuperview != nil)")
    }

    override func viewDidMoveToSuperview() {
        events.append("didSuperview:\(superview != nil)")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        events.append("willWindow:\(newWindow != nil)")
    }

    override func viewDidMoveToWindow() {
        events.append("didWindow:\(window != nil)")
    }
}

private final class TrackingAreaOwnerProbe: NSObject {}
