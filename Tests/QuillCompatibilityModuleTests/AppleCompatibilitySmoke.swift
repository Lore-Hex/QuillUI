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
