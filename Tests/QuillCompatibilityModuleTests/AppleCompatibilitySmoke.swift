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
        var unknownBundleApplicationMissing: Bool
        var unknownSchemeApplicationMissing: Bool
        var bitmapRepresentationRoundTrip: Bool
        var windowTabbingRoundTrip: Bool
        var operations: Set<String>
    }

    struct AppKitGeometryResult {
        var stringRoundTrip: Bool
        var bracedFormatParsed: Bool
        var flatFormatParsed: Bool
        var exponentFormatParsed: Bool
        var invalidStringReturnsZero: Bool
    }

    struct AppKitAppearanceResult {
        var namedInitializerStoresName: Bool
        var highContrastNamesAreDistinct: Bool
        var directBestMatch: Bool
        var highContrastDarkFallsBackToDark: Bool
        var vibrantLightFallsBackToAqua: Bool
        var unknownAppearanceDoesNotInventMatch: Bool
    }

    struct AppKitFontResult {
        var fontsAreDeterministicAndNonEmpty: Bool
        var familiesAreDeterministicAndNonEmpty: Bool
        var membersAreDeterministicAndNonEmpty: Bool
        var fontsContainCommonMacFaces: Bool
        var familiesContainCommonMacFamilies: Bool
        var unknownFamilyReturnsNil: Bool
    }

    struct AppKitOpenPanelResult {
        var defaultConfigurationMatchesMacShape: Bool
        var configurationRoundTrips: Bool
        var runModalCancelsHeadless: Bool
        var beginReportsCancellation: Bool
        var beginSheetReportsCancellation: Bool
        var defaultSelectionIsEmpty: Bool
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

    struct AppKitControlResult {
        var stringValueUpdatedNumericAndObjectValues: Bool
        var numericValuesUpdatedStringAndObjectValues: Bool
        var objectValueUpdatedStringAndNumericValues: Bool
        var attributedValueUpdatedStringAndNumericValues: Bool
        var explicitActionSentToTarget: Bool
        var missingActionOrTargetRejected: Bool
        var applicationExplicitActionSentToTarget: Bool
        var applicationMissingTargetRejected: Bool
        var textButtonPreservedTargetActionAndTitle: Bool
        var imageButtonPreservedTargetAndAction: Bool
        var checkboxFactoryPreservedTargetActionAndTitle: Bool
        var radioFactoryPreservedTargetActionAndTitle: Bool
        var labelInitializerPreservedLabelTraits: Bool
        var wrappingLabelInitializerPreservedWrappingTraits: Bool
        var stringInitializerPreservedEditableTraits: Bool
        var sliderInitializerPreservedRangeTargetAndAction: Bool
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
        var scrollDocumentViewInstalledInClipView: Bool
        var scrollContentSubviewFindsEnclosingScrollView: Bool
        var scrollDocumentViewClearingRemovedDocument: Bool
        var windowContentViewPropagated: Bool
        var windowContentViewCleared: Bool
        var windowCallbacksReachedSubview: Bool
        var frameInitializerEstablishedBounds: Bool
        var frameResizeScaledBounds: Bool
        var offWindowDisplayInvalidationIgnored: Bool
        var windowAttachmentMarksDisplayDirty: Bool
        var displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay: Bool
        var setNeedsDisplayMarksAncestorDirty: Bool
        var displayIfNeededClearsDirtyDescendants: Bool
        var forcedDisplayCallsViewWillDrawWhenClean: Bool
        var newViewsStartNeedingLayout: Bool
        var layoutSubtreeClearsNeedsLayout: Bool
        var layoutSubtreeVisitsDirtyDescendants: Bool
        var layoutSubtreeSkipsCleanViews: Bool
        var layoutSubtreeVisitsDirtyDescendantFromCleanAncestor: Bool
        var frameAndBoundsMutationsMarkNeedsLayout: Bool
        var hitTestReturnsTopmostVisibleSubview: Bool
        var hitTestIgnoresHiddenSubview: Bool
        var hitTestRejectsOutsideBounds: Bool
        var hitTestReturnsReceiverInsideBounds: Bool
        var convertFromDescendantAccumulatesFrameOrigins: Bool
        var convertToDescendantSubtractsFrameOrigins: Bool
        var convertBetweenSiblingsUsesCommonSuperview: Bool
        var convertRectPreservesSize: Bool
        var convertNilUsesWindowCoordinates: Bool
        var convertScaledBoundsAppliesBoundsTransform: Bool
    }

    struct AppKitResponderResult {
        var explicitNextResponderRoundTrip: Bool
        var viewDefaultResponderChain: Bool
        var viewControllerOwnsViewResponder: Bool
        var eventForwardingReachesNextResponder: Bool
        var makeFirstResponderCallsLifecycle: Bool
        var rejectedFirstResponderPreservesCurrent: Bool
        var clearingFirstResponderResignsCurrent: Bool
        var applicationSendEventDispatchesToFirstResponder: Bool
        var applicationCurrentEventTracksDispatch: Bool
        var localEventMonitorCanRewriteEvent: Bool
        var localEventMonitorCanCancelEvent: Bool
        var globalEventMonitorObservesDispatchedEvent: Bool
        var removedEventMonitorStopsObserving: Bool
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
        var defaultDividerMatchesAppKit: Bool
        var adjustSubviewsLaysOutTwoPanes: Bool
        var setPositionMovesAdjacentPanes: Bool
        var setPositionNotifiesDelegate: Bool
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

    struct AppKitTextViewEditingResult {
        var replaceUpdatesStringAndStorage: Bool
        var insertUsesSelectedRange: Bool
        var attributedInsertUsesStringContents: Bool
        var delegateCanVetoChange: Bool
        var delegateReceivesChangeAndSelectionNotifications: Bool
    }

    struct AppKitTableResult {
        var reloadUpdatedRowCount: Bool
        var columnLookupAndRemoval: Bool
        var multiSelectionRoundTrip: Bool
        var singleSelectionAndEmptyRules: Bool
        var delegateSelectionNotification: Bool
        var rowAndCellViewsCached: Bool
        var frameUsesColumnWidthsAndRowHeight: Bool
        var rowColumnLookupFromViews: Bool
        var rowMutationsPreserveState: Bool
    }

    struct AppKitOutlineResult {
        var reloadShowsRootItems: Bool
        var expandShowsChildrenAndLevels: Bool
        var rowParentAndChildLookup: Bool
        var delegateViewsUseItems: Bool
        var selectionRoundTrip: Bool
        var collapseHidesChildrenAndClearsSelection: Bool
        var recursiveExpansionAndCollapse: Bool
    }

    struct AppKitDocumentResult {
        var displayNameFollowsFileURL: Bool
        var changeCountTracksEditedState: Bool
        var windowControllerLinksRoundTrip: Bool
        var documentControllerMaintainsCurrentDocument: Bool
        var openDocumentCreatesAndReusesDocument: Bool
    }

    struct AppKitUndoResult {
        var singleActionUndoRedoRoundTrip: Bool
        var actionNamesRoundTrip: Bool
        var disablingRegistrationBlocksActions: Bool
        var targetRemovalClearsActions: Bool
        var groupedActionsUndoTogether: Bool
        var groupedActionsRedoTogether: Bool
    }

    struct OSLogResult {
        var operations: Set<String>
        var renderedPublicValue: Bool
        var redactedPrivateValue: Bool
    }

    private final class AppKitControlTarget: NSObject {
        #if canImport(ObjectiveC)
        @objc func performControlAction(_ sender: Any?) {}
        #endif
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

        QuillUpdateService.shared.reset()
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

    static func runAppKitGeometrySmoke() -> AppKitGeometryResult {
        func rectMatches(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
            lhs.origin.x == rhs.origin.x &&
                lhs.origin.y == rhs.origin.y &&
                lhs.size.width == rhs.size.width &&
                lhs.size.height == rhs.size.height
        }

        let rect = NSRect(x: -1.5, y: 2.25, width: 300, height: 40.5)
        let stringRoundTrip = rectMatches(NSRectFromString(NSStringFromRect(rect)), rect)
        let bracedFormatParsed = rectMatches(
            NSRectFromString("{{1, 2}, {3, 4}}"),
            NSRect(x: 1, y: 2, width: 3, height: 4)
        )
        let flatFormatParsed = rectMatches(
            NSRectFromString("{1.25, -2.5, 3.75, 4.5}"),
            NSRect(x: 1.25, y: -2.5, width: 3.75, height: 4.5)
        )
        let exponentFormatParsed = rectMatches(
            NSRectFromString("{{1e1, -2e0}, {3.5e1, 4.25}}"),
            NSRect(x: 10, y: -2, width: 35, height: 4.25)
        )
        let invalidStringReturnsZero = rectMatches(NSRectFromString("not a rect"), .zero)

        return AppKitGeometryResult(
            stringRoundTrip: stringRoundTrip,
            bracedFormatParsed: bracedFormatParsed,
            flatFormatParsed: flatFormatParsed,
            exponentFormatParsed: exponentFormatParsed,
            invalidStringReturnsZero: invalidStringReturnsZero
        )
    }

    static func runAppKitAppearanceSmoke() -> AppKitAppearanceResult {
        let dark = NSAppearance(named: .darkAqua)
        let highContrastDark = NSAppearance(named: .accessibilityHighContrastDarkAqua)
        let vibrantLight = NSAppearance(named: .vibrantLight)
        let unknown = NSAppearance(named: NSAppearance.Name(rawValue: "QuillCustomAppearance"))

        let highContrastNames = [
            NSAppearance.Name.accessibilityHighContrastAqua.rawValue,
            NSAppearance.Name.accessibilityHighContrastDarkAqua.rawValue,
            NSAppearance.Name.accessibilityHighContrastVibrantLight.rawValue,
            NSAppearance.Name.accessibilityHighContrastVibrantDark.rawValue
        ]

        return AppKitAppearanceResult(
            namedInitializerStoresName: dark?.name == .darkAqua,
            highContrastNamesAreDistinct: Set(highContrastNames).count == highContrastNames.count &&
                !highContrastNames.contains(""),
            directBestMatch: dark?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            highContrastDarkFallsBackToDark: highContrastDark?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            vibrantLightFallsBackToAqua: vibrantLight?.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
            unknownAppearanceDoesNotInventMatch: unknown?.bestMatch(from: [.aqua, .darkAqua]) == nil
        )
    }

    static func runAppKitFontSmoke() -> AppKitFontResult {
        let manager = NSFontManager.shared
        let fonts = manager.availableFonts()
        let secondFonts = manager.availableFonts()
        let families = manager.availableFontFamilies()
        let secondFamilies = manager.availableFontFamilies()
        let helveticaMembers = manager.availableMembers(ofFontFamily: "Helvetica")
        let secondHelveticaMembers = manager.availableMembers(ofFontFamily: "Helvetica")

        return AppKitFontResult(
            fontsAreDeterministicAndNonEmpty: !fonts.isEmpty &&
                fonts == secondFonts &&
                fonts == fonts.sorted(),
            familiesAreDeterministicAndNonEmpty: !families.isEmpty &&
                families == secondFamilies &&
                families == families.sorted(),
            membersAreDeterministicAndNonEmpty: helveticaMembers != nil &&
                helveticaMembers?.count == secondHelveticaMembers?.count &&
                helveticaMembers?.first?.first as? String == "Helvetica",
            fontsContainCommonMacFaces: fonts.contains("Helvetica") &&
                fonts.contains("Helvetica-Bold") &&
                fonts.contains("Menlo-Regular"),
            familiesContainCommonMacFamilies: families.contains("Helvetica") &&
                families.contains("Menlo"),
            unknownFamilyReturnsNil: manager.availableMembers(ofFontFamily: "QuillCustomFamily") == nil
        )
    }

    @MainActor
    static func runAppKitOpenPanelSmoke() -> AppKitOpenPanelResult {
        #if os(Linux)
        let panel = NSOpenPanel()
        let defaultConfigurationMatchesMacShape =
            panel.canChooseFiles &&
            !panel.canChooseDirectories &&
            !panel.allowsMultipleSelection &&
            panel.resolvesAliases
        let defaultSelectionIsEmpty =
            panel.urls.isEmpty &&
            panel.url == nil

        let directoryURL = URL(fileURLWithPath: "/tmp")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.canSelectHiddenExtension = true
        panel.isExtensionHidden = true
        panel.treatsFilePackagesAsDirectories = true
        panel.allowsOtherFileTypes = true
        panel.prompt = "Choose"
        panel.message = "Pick a folder"
        panel.directoryURL = directoryURL
        panel.allowedFileTypes = ["png", "jpg"]
        panel.allowedContentTypes = ["public.png"]

        let configurationRoundTrips =
            !panel.canChooseFiles &&
            panel.canChooseDirectories &&
            panel.allowsMultipleSelection &&
            !panel.resolvesAliases &&
            !panel.canCreateDirectories &&
            panel.showsHiddenFiles &&
            panel.canSelectHiddenExtension &&
            panel.isExtensionHidden &&
            panel.treatsFilePackagesAsDirectories &&
            panel.allowsOtherFileTypes &&
            panel.prompt == "Choose" &&
            panel.message == "Pick a folder" &&
            panel.directoryURL == directoryURL &&
            panel.allowedFileTypes == ["png", "jpg"] &&
            panel.allowedContentTypes.count == 1 &&
            panel.allowedContentTypes.first as? String == "public.png"

        let runModalCancelsHeadless = panel.runModal() == .cancel
        var beginResponse: NSApplication.ModalResponse?
        panel.begin { response in
            beginResponse = response
        }
        var sheetResponse: NSApplication.ModalResponse?
        panel.beginSheetModal(for: NSWindow()) { response in
            sheetResponse = response
        }

        return AppKitOpenPanelResult(
            defaultConfigurationMatchesMacShape: defaultConfigurationMatchesMacShape,
            configurationRoundTrips: configurationRoundTrips,
            runModalCancelsHeadless: runModalCancelsHeadless,
            beginReportsCancellation: beginResponse == .cancel,
            beginSheetReportsCancellation: sheetResponse == .cancel,
            defaultSelectionIsEmpty: defaultSelectionIsEmpty
        )
        #else
        return AppKitOpenPanelResult(
            defaultConfigurationMatchesMacShape: true,
            configurationRoundTrips: true,
            runModalCancelsHeadless: true,
            beginReportsCancellation: true,
            beginSheetReportsCancellation: true,
            defaultSelectionIsEmpty: true
        )
        #endif
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
        let missingBundleApplication = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.quillui.missing.AppKitWorkspaceSmoke"
        )
        let missingSchemeApplication = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "quillui-missing-scheme://workspace-smoke")!
        )
        let encoded = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let rep = NSBitmapImageRep(data: encoded)
        NSWindow.allowsAutomaticWindowTabbing = false
        let windowTabbingRoundTrip = NSWindow.allowsAutomaticWindowTabbing == false
        NSWindow.allowsAutomaticWindowTabbing = true

        return AppKitImageResult(
            sizeRoundTrip: sizeRoundTrip,
            namedImagePlaceholder: namedImage?.size == CGSize(width: 32, height: 32),
            systemImagePlaceholder: systemImage?.size == CGSize(width: 32, height: 32),
            workspaceFileIconPlaceholder: workspaceFileIcon.size == CGSize(width: 32, height: 32),
            workspaceContentTypeIconPlaceholder: workspaceContentTypeIcon.size == CGSize(width: 32, height: 32),
            unknownBundleApplicationMissing: missingBundleApplication == nil,
            unknownSchemeApplicationMissing: missingSchemeApplication == nil,
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

    static func runAppKitControlSmoke() -> AppKitControlResult {
        let textField = NSTextField()
        textField.stringValue = "42.5"
        let stringValueUpdatedNumericAndObjectValues =
            textField.doubleValue == 42.5 &&
            textField.floatValue == 42.5 &&
            textField.integerValue == 42 &&
            textField.attributedStringValue.string == "42.5" &&
            (textField.objectValue as? String) == "42.5"

        textField.integerValue = 7
        let integerValueRoundTrip =
            textField.doubleValue == 7 &&
            textField.floatValue == 7 &&
            textField.stringValue == "7" &&
            textField.attributedStringValue.string == "7" &&
            (textField.objectValue as? Int) == 7

        textField.doubleValue = 3.25
        let doubleValueRoundTrip =
            textField.doubleValue == 3.25 &&
            textField.floatValue == 3.25 &&
            textField.integerValue == 3 &&
            textField.stringValue == "3.25" &&
            (textField.objectValue as? Double) == 3.25
        let numericValuesUpdatedStringAndObjectValues =
            integerValueRoundTrip && doubleValueRoundTrip

        textField.objectValue = NSNumber(value: 9)
        let objectValueUpdatedStringAndNumericValues =
            textField.doubleValue == 9 &&
            textField.floatValue == 9 &&
            textField.integerValue == 9 &&
            textField.stringValue == "9" &&
            textField.attributedStringValue.string == "9"

        textField.attributedStringValue = NSAttributedString(string: "18")
        let attributedValueUpdatedStringAndNumericValues =
            textField.doubleValue == 18 &&
            textField.floatValue == 18 &&
            textField.integerValue == 18 &&
            textField.stringValue == "18"

        let action = Selector("performControlAction:")
        let target = AppKitControlTarget()
        let actionButton = NSButton(title: "Run", target: target, action: action)
        let explicitActionSentToTarget = actionButton.sendAction(actionButton.action, to: actionButton.target)
        let missingActionOrTargetRejected =
            !NSButton(title: "Run", target: nil, action: nil).sendAction(nil, to: nil)
        let applicationExplicitActionSentToTarget =
            NSApplication.shared.sendAction(action, to: target, from: actionButton)
        let applicationMissingTargetRejected =
            !NSApplication.shared.sendAction(action, to: nil, from: actionButton)

        let textButtonPreservedTargetActionAndTitle =
            actionButton.title == "Run" &&
            actionButton.attributedTitle.string == "Run" &&
            actionButton.target === target &&
            actionButton.action == action

        let imageButton = NSButton(image: NSImage(size: NSSize(width: 1, height: 1)), target: target, action: action)
        let imageButtonPreservedTargetAndAction =
            imageButton.image != nil &&
            imageButton.target === target &&
            imageButton.action == action

        let checkbox = NSButton.checkbox(withTitle: "Remember me", target: target, action: action)
        let checkboxFactoryPreservedTargetActionAndTitle =
            checkbox.title == "Remember me" &&
            checkbox.attributedTitle.string == "Remember me" &&
            checkbox.target === target &&
            checkbox.action == action &&
            checkbox.state == .off

        let radio = NSButton.radioButton(withTitle: "Local", target: target, action: action)
        let radioFactoryPreservedTargetActionAndTitle =
            radio.title == "Local" &&
            radio.attributedTitle.string == "Local" &&
            radio.target === target &&
            radio.action == action &&
            radio.state == .off

        let label = NSTextField(labelWithString: "Status")
        let labelInitializerPreservedLabelTraits =
            label.stringValue == "Status" &&
            !label.isEditable &&
            !label.isSelectable &&
            !label.isBordered &&
            !label.isBezeled &&
            !label.drawsBackground &&
            label.maximumNumberOfLines == 0 &&
            label.lineBreakMode == .byClipping

        let wrappingLabel = NSTextField(wrappingLabelWithString: "Wrapped status")
        let wrappingLabelInitializerPreservedWrappingTraits =
            wrappingLabel.stringValue == "Wrapped status" &&
            !wrappingLabel.isEditable &&
            wrappingLabel.isSelectable &&
            !wrappingLabel.isBordered &&
            !wrappingLabel.isBezeled &&
            !wrappingLabel.drawsBackground &&
            wrappingLabel.maximumNumberOfLines == 0 &&
            wrappingLabel.lineBreakMode == .byWordWrapping

        let stringTextField = NSTextField(string: "Editable status")
        let stringInitializerPreservedEditableTraits =
            stringTextField.stringValue == "Editable status" &&
            stringTextField.isEditable &&
            stringTextField.isSelectable &&
            !stringTextField.isBordered &&
            stringTextField.isBezeled &&
            stringTextField.drawsBackground &&
            stringTextField.maximumNumberOfLines == 0 &&
            stringTextField.lineBreakMode == .byClipping

        let slider = NSSlider(value: 4.5, minValue: 1, maxValue: 9, target: target, action: action)
        let sliderInitializerPreservedRangeTargetAndAction =
            slider.doubleValue == 4.5 &&
            slider.minValue == 1 &&
            slider.maxValue == 9 &&
            slider.target === target &&
            slider.action == action &&
            slider.isEnabled

        return AppKitControlResult(
            stringValueUpdatedNumericAndObjectValues: stringValueUpdatedNumericAndObjectValues,
            numericValuesUpdatedStringAndObjectValues: numericValuesUpdatedStringAndObjectValues,
            objectValueUpdatedStringAndNumericValues: objectValueUpdatedStringAndNumericValues,
            attributedValueUpdatedStringAndNumericValues: attributedValueUpdatedStringAndNumericValues,
            explicitActionSentToTarget: explicitActionSentToTarget,
            missingActionOrTargetRejected: missingActionOrTargetRejected,
            applicationExplicitActionSentToTarget: applicationExplicitActionSentToTarget,
            applicationMissingTargetRejected: applicationMissingTargetRejected,
            textButtonPreservedTargetActionAndTitle: textButtonPreservedTargetActionAndTitle,
            imageButtonPreservedTargetAndAction: imageButtonPreservedTargetAndAction,
            checkboxFactoryPreservedTargetActionAndTitle: checkboxFactoryPreservedTargetActionAndTitle,
            radioFactoryPreservedTargetActionAndTitle: radioFactoryPreservedTargetActionAndTitle,
            labelInitializerPreservedLabelTraits: labelInitializerPreservedLabelTraits,
            wrappingLabelInitializerPreservedWrappingTraits: wrappingLabelInitializerPreservedWrappingTraits,
            stringInitializerPreservedEditableTraits: stringInitializerPreservedEditableTraits,
            sliderInitializerPreservedRangeTargetAndAction: sliderInitializerPreservedRangeTargetAndAction
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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 160))
        scrollView.documentView = documentView
        let scrollDocumentViewInstalledInClipView =
            scrollView.documentView === documentView &&
            scrollView.contentView.documentView === documentView &&
            scrollView.contentView.superview === scrollView &&
            scrollView.subviews.contains { $0 === scrollView.contentView } &&
            documentView.superview === scrollView.contentView &&
            documentView.enclosingScrollView === scrollView

        let contentSubview = NSView()
        scrollView.contentView.addSubview(contentSubview)
        let scrollContentSubviewFindsEnclosingScrollView =
            contentSubview.enclosingScrollView === scrollView

        scrollView.documentView = nil
        let scrollDocumentViewClearingRemovedDocument =
            scrollView.documentView == nil &&
            scrollView.contentView.documentView == nil &&
            documentView.superview == nil

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

        let hitTestRoot = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let bottomSubview = NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50))
        let topSubview = NSView(frame: NSRect(x: 20, y: 20, width: 50, height: 50))
        hitTestRoot.addSubview(bottomSubview)
        hitTestRoot.addSubview(topSubview)

        let frameInitializerEstablishedBounds =
            hitTestRoot.bounds == NSRect(x: 0, y: 0, width: 100, height: 100) &&
            bottomSubview.bounds == NSRect(x: 0, y: 0, width: 50, height: 50)

        bottomSubview.setFrameSize(NSSize(width: 100, height: 80))
        let frameResizeScaledBounds =
            bottomSubview.bounds == NSRect(x: 0, y: 0, width: 100, height: 80)
        bottomSubview.frame = NSRect(x: 10, y: 10, width: 50, height: 50)

        let offWindowDisplayView = DisplayProbe(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        offWindowDisplayView.setNeedsDisplay(NSRect(x: 1, y: 1, width: 2, height: 2))
        offWindowDisplayView.needsDisplay = true
        offWindowDisplayView.displayIfNeeded()
        let offWindowDisplayInvalidationIgnored =
            !offWindowDisplayView.needsDisplay &&
            offWindowDisplayView.willDrawCount == 0

        let displayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        let displayParent = DisplayProbe(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        let displayChild = DisplayProbe(frame: NSRect(x: 10, y: 10, width: 20, height: 20))
        displayParent.addSubview(displayChild)
        displayWindow.contentView = displayParent
        let windowAttachmentMarksDisplayDirty =
            displayParent.needsDisplay &&
            displayChild.needsDisplay

        displayParent.displayIfNeeded()
        let displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay =
            displayParent.willDrawCount == 1 &&
            displayChild.willDrawCount == 0 &&
            !displayParent.needsDisplay &&
            !displayChild.needsDisplay

        displayChild.setNeedsDisplay(NSRect(x: 1, y: 1, width: 2, height: 2))
        let setNeedsDisplayMarksAncestorDirty =
            displayParent.needsDisplay &&
            displayChild.needsDisplay

        displayParent.displayIfNeeded()
        let displayIfNeededClearsDirtyDescendants =
            displayParent.willDrawCount == 2 &&
            displayChild.willDrawCount == 0 &&
            !displayParent.needsDisplay &&
            !displayChild.needsDisplay

        displayParent.display()
        let forcedDisplayCallsViewWillDrawWhenClean =
            displayParent.willDrawCount == 3 &&
            !displayParent.needsDisplay &&
            !displayChild.needsDisplay

        let layoutRecorder = LayoutRecorder()
        let layoutRoot = LayoutProbe()
        layoutRoot.layoutName = "root"
        layoutRoot.recorder = layoutRecorder
        let layoutChild = LayoutProbe()
        layoutChild.layoutName = "child"
        layoutChild.recorder = layoutRecorder
        layoutRoot.addSubview(layoutChild)

        let newViewsStartNeedingLayout =
            layoutRoot.needsLayout &&
            layoutChild.needsLayout
        layoutRoot.layoutSubtreeIfNeeded()
        let layoutSubtreeClearsNeedsLayout =
            !layoutRoot.needsLayout &&
            !layoutChild.needsLayout
        let layoutSubtreeVisitsDirtyDescendants =
            layoutRecorder.events == ["root", "child"] &&
            layoutRoot.layoutCount == 1 &&
            layoutChild.layoutCount == 1

        layoutRoot.layoutSubtreeIfNeeded()
        let layoutSubtreeSkipsCleanViews =
            layoutRecorder.events == ["root", "child"] &&
            layoutRoot.layoutCount == 1 &&
            layoutChild.layoutCount == 1

        layoutChild.needsLayout = true
        layoutRoot.layoutSubtreeIfNeeded()
        let layoutSubtreeVisitsDirtyDescendantFromCleanAncestor =
            layoutRecorder.events == ["root", "child", "child"] &&
            layoutRoot.layoutCount == 1 &&
            layoutChild.layoutCount == 2 &&
            !layoutRoot.needsLayout &&
            !layoutChild.needsLayout

        let layoutMutationView = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        layoutMutationView.layoutSubtreeIfNeeded()
        let layoutMutationBaselineClean = !layoutMutationView.needsLayout
        layoutMutationView.setFrameOrigin(NSPoint(x: 1, y: 2))
        let frameOriginMarksNeedsLayout = layoutMutationView.needsLayout
        layoutMutationView.layoutSubtreeIfNeeded()
        layoutMutationView.setFrameSize(NSSize(width: 20, height: 30))
        let frameSizeMarksNeedsLayout = layoutMutationView.needsLayout
        layoutMutationView.layoutSubtreeIfNeeded()
        layoutMutationView.bounds = NSRect(x: 1, y: 2, width: 20, height: 30)
        let boundsMutationMarksNeedsLayout = layoutMutationView.needsLayout
        let frameAndBoundsMutationsMarkNeedsLayout =
            layoutMutationBaselineClean &&
            frameOriginMarksNeedsLayout &&
            frameSizeMarksNeedsLayout &&
            boundsMutationMarksNeedsLayout

        let hitTestReturnsTopmostVisibleSubview =
            hitTestRoot.hitTest(NSPoint(x: 25, y: 25)) === topSubview
        topSubview.isHidden = true
        let hitTestIgnoresHiddenSubview =
            hitTestRoot.hitTest(NSPoint(x: 25, y: 25)) === bottomSubview
        let hitTestRejectsOutsideBounds =
            hitTestRoot.hitTest(NSPoint(x: 150, y: 150)) == nil
        let hitTestReturnsReceiverInsideBounds =
            hitTestRoot.hitTest(NSPoint(x: 5, y: 5)) === hitTestRoot

        let convertRoot = NSView(frame: NSRect(x: 5, y: 7, width: 100, height: 100))
        let convertChild = NSView(frame: NSRect(x: 10, y: 20, width: 50, height: 50))
        let convertGrandchild = NSView(frame: NSRect(x: 3, y: 4, width: 10, height: 10))
        let convertSibling = NSView(frame: NSRect(x: 30, y: 5, width: 20, height: 20))
        convertRoot.addSubview(convertChild)
        convertChild.addSubview(convertGrandchild)
        convertRoot.addSubview(convertSibling)

        let convertFromDescendantAccumulatesFrameOrigins =
            convertRoot.convert(NSPoint(x: 0, y: 0), from: convertGrandchild) == NSPoint(x: 13, y: 24)
        let convertToDescendantSubtractsFrameOrigins =
            convertGrandchild.convert(NSPoint(x: 13, y: 24), from: convertRoot) == NSPoint(x: 0, y: 0)
        let convertBetweenSiblingsUsesCommonSuperview =
            convertSibling.convert(NSPoint(x: 0, y: 0), from: convertChild) == NSPoint(x: -20, y: 15)
        let convertRectPreservesSize =
            convertRoot.convert(NSRect(x: 1, y: 2, width: 7, height: 8), from: convertGrandchild) ==
            NSRect(x: 14, y: 26, width: 7, height: 8)
        let convertNilUsesWindowCoordinates =
            convertChild.convert(NSPoint(x: 15, y: 27), from: nil) == NSPoint(x: 0, y: 0) &&
            convertChild.convert(NSPoint(x: 0, y: 0), to: nil) == NSPoint(x: 15, y: 27)

        let scaledRoot = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let scaledChild = NSView(frame: NSRect(x: 10, y: 20, width: 50, height: 50))
        scaledRoot.addSubview(scaledChild)
        scaledChild.bounds = NSRect(x: 2, y: 3, width: 25, height: 25)
        let convertScaledBoundsAppliesBoundsTransform =
            scaledRoot.convert(NSPoint(x: 2, y: 3), from: scaledChild) == NSPoint(x: 10, y: 20) &&
            scaledChild.convert(NSPoint(x: 10, y: 20), from: scaledRoot) == NSPoint(x: 2, y: 3) &&
            scaledRoot.convert(NSRect(x: 2, y: 3, width: 5, height: 5), from: scaledChild) ==
            NSRect(x: 10, y: 20, width: 10, height: 10)

        return AppKitViewHierarchyResult(
            addEstablishedLinks: addEstablishedLinks,
            addFiredSuperviewCallbacks: addFiredSuperviewCallbacks,
            reparentedWithoutDuplicateBacklinks: reparentedWithoutDuplicateBacklinks,
            removalClearedLinks: removalClearedLinks,
            removalFiredSuperviewCallbacks: removalFiredSuperviewCallbacks,
            scrollDocumentViewInstalledInClipView: scrollDocumentViewInstalledInClipView,
            scrollContentSubviewFindsEnclosingScrollView: scrollContentSubviewFindsEnclosingScrollView,
            scrollDocumentViewClearingRemovedDocument: scrollDocumentViewClearingRemovedDocument,
            windowContentViewPropagated: windowContentViewPropagated,
            windowContentViewCleared: windowContentViewCleared,
            windowCallbacksReachedSubview: windowCallbacksReachedSubview,
            frameInitializerEstablishedBounds: frameInitializerEstablishedBounds,
            frameResizeScaledBounds: frameResizeScaledBounds,
            offWindowDisplayInvalidationIgnored: offWindowDisplayInvalidationIgnored,
            windowAttachmentMarksDisplayDirty: windowAttachmentMarksDisplayDirty,
            displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay: displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay,
            setNeedsDisplayMarksAncestorDirty: setNeedsDisplayMarksAncestorDirty,
            displayIfNeededClearsDirtyDescendants: displayIfNeededClearsDirtyDescendants,
            forcedDisplayCallsViewWillDrawWhenClean: forcedDisplayCallsViewWillDrawWhenClean,
            newViewsStartNeedingLayout: newViewsStartNeedingLayout,
            layoutSubtreeClearsNeedsLayout: layoutSubtreeClearsNeedsLayout,
            layoutSubtreeVisitsDirtyDescendants: layoutSubtreeVisitsDirtyDescendants,
            layoutSubtreeSkipsCleanViews: layoutSubtreeSkipsCleanViews,
            layoutSubtreeVisitsDirtyDescendantFromCleanAncestor: layoutSubtreeVisitsDirtyDescendantFromCleanAncestor,
            frameAndBoundsMutationsMarkNeedsLayout: frameAndBoundsMutationsMarkNeedsLayout,
            hitTestReturnsTopmostVisibleSubview: hitTestReturnsTopmostVisibleSubview,
            hitTestIgnoresHiddenSubview: hitTestIgnoresHiddenSubview,
            hitTestRejectsOutsideBounds: hitTestRejectsOutsideBounds,
            hitTestReturnsReceiverInsideBounds: hitTestReturnsReceiverInsideBounds,
            convertFromDescendantAccumulatesFrameOrigins: convertFromDescendantAccumulatesFrameOrigins,
            convertToDescendantSubtractsFrameOrigins: convertToDescendantSubtractsFrameOrigins,
            convertBetweenSiblingsUsesCommonSuperview: convertBetweenSiblingsUsesCommonSuperview,
            convertRectPreservesSize: convertRectPreservesSize,
            convertNilUsesWindowCoordinates: convertNilUsesWindowCoordinates,
            convertScaledBoundsAppliesBoundsTransform: convertScaledBoundsAppliesBoundsTransform
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

        let app = NSApplication.shared
        let previousWindows = app.windows
        let previousKeyWindow = app.keyWindow
        let previousMainWindow = app.mainWindow
        let previousCurrentEvent = app.currentEvent
        defer {
            app.windows = previousWindows
            app.keyWindow = previousKeyWindow
            app.mainWindow = previousMainWindow
            app.currentEvent = previousCurrentEvent
        }

        let dispatchWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let dispatchRecorder = EventRecorderResponder()
        _ = dispatchWindow.makeFirstResponder(dispatchRecorder)
        dispatchRecorder.events.removeAll()
        app.windows = [dispatchWindow]
        app.keyWindow = dispatchWindow
        app.mainWindow = dispatchWindow

        func makeDispatchEvent(type: NSEvent.EventType = .keyDown) -> NSEvent {
            let event = NSEvent()
            event.type = type
            event.window = dispatchWindow
            return event
        }

        let dispatchedEvent = makeDispatchEvent()
        app.sendEvent(dispatchedEvent)
        let applicationSendEventDispatchesToFirstResponder =
            dispatchRecorder.events == ["keyDown"]
        let applicationCurrentEventTracksDispatch = app.currentEvent === dispatchedEvent

        var localEventMonitorCanRewriteEvent = false
        do {
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let rewritten = NSEvent()
                rewritten.type = .scrollWheel
                rewritten.window = event.window
                return rewritten
            }
            defer {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }

            dispatchRecorder.events.removeAll()
            app.sendEvent(makeDispatchEvent())
            localEventMonitorCanRewriteEvent =
                dispatchRecorder.events == ["scrollWheel"] &&
                app.currentEvent?.type == .scrollWheel
        }

        var localEventMonitorCanCancelEvent = false
        do {
            let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in nil }
            defer {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }

            dispatchRecorder.events.removeAll()
            app.sendEvent(makeDispatchEvent())
            localEventMonitorCanCancelEvent = dispatchRecorder.events.isEmpty
        }

        var observedGlobalEvent: NSEvent?
        var globalEventMonitorObservesDispatchedEvent = false
        do {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                observedGlobalEvent = event
            }
            defer {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }

            let globalEvent = makeDispatchEvent()
            dispatchRecorder.events.removeAll()
            app.sendEvent(globalEvent)
            let globalDispatchStillReachedResponder = dispatchRecorder.events == ["keyDown"]
            globalEventMonitorObservesDispatchedEvent =
                observedGlobalEvent === globalEvent &&
                globalDispatchStillReachedResponder
        }

        var removedMonitorObservationCount = 0
        do {
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in
                removedMonitorObservationCount += 1
            }
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            app.sendEvent(makeDispatchEvent())
        }
        let removedEventMonitorStopsObserving = removedMonitorObservationCount == 0

        return AppKitResponderResult(
            explicitNextResponderRoundTrip: explicitNextResponderRoundTrip,
            viewDefaultResponderChain: viewDefaultResponderChain,
            viewControllerOwnsViewResponder: viewControllerOwnsViewResponder,
            eventForwardingReachesNextResponder: eventForwardingReachesNextResponder,
            makeFirstResponderCallsLifecycle: makeFirstResponderCallsLifecycle,
            rejectedFirstResponderPreservesCurrent: rejectedFirstResponderPreservesCurrent,
            clearingFirstResponderResignsCurrent: clearingFirstResponderResignsCurrent,
            applicationSendEventDispatchesToFirstResponder: applicationSendEventDispatchesToFirstResponder,
            applicationCurrentEventTracksDispatch: applicationCurrentEventTracksDispatch,
            localEventMonitorCanRewriteEvent: localEventMonitorCanRewriteEvent,
            localEventMonitorCanCancelEvent: localEventMonitorCanCancelEvent,
            globalEventMonitorObservesDispatchedEvent: globalEventMonitorObservesDispatchedEvent,
            removedEventMonitorStopsObserving: removedEventMonitorStopsObserving
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

        let layoutSplitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        layoutSplitView.isVertical = true
        let leadingPane = NSView()
        let trailingPane = NSView()
        layoutSplitView.addArrangedSubview(leadingPane)
        layoutSplitView.addArrangedSubview(trailingPane)

        let defaultDividerMatchesAppKit =
            layoutSplitView.dividerStyle == .thick &&
            layoutSplitView.dividerThickness == 9

        layoutSplitView.adjustSubviews()
        let adjustSubviewsLaysOutTwoPanes =
            leadingPane.frame == NSRect(x: 0, y: 0, width: 146, height: 120) &&
            trailingPane.frame == NSRect(x: 155, y: 0, width: 145, height: 120)

        let delegate = SplitViewDelegateProbe()
        layoutSplitView.delegate = delegate
        layoutSplitView.setPosition(80, ofDividerAt: 0)
        let setPositionMovesAdjacentPanes =
            leadingPane.frame == NSRect(x: 0, y: 0, width: 80, height: 120) &&
            trailingPane.frame == NSRect(x: 89, y: 0, width: 211, height: 120)
        let setPositionNotifiesDelegate =
            delegate.resizeNotifications == 1 &&
            delegate.lastNotification?.name == NSSplitView.didResizeSubviewsNotification &&
            (delegate.lastNotification?.object as? NSSplitView) === layoutSplitView

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
            defaultDividerMatchesAppKit: defaultDividerMatchesAppKit,
            adjustSubviewsLaysOutTwoPanes: adjustSubviewsLaysOutTwoPanes,
            setPositionMovesAdjacentPanes: setPositionMovesAdjacentPanes,
            setPositionNotifiesDelegate: setPositionNotifiesDelegate,
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
    static func runAppKitTextViewEditingSmoke() -> AppKitTextViewEditingResult {
        let selectedRangeSentinel = Foundation.NSNotFound

        let replaceView = NSTextView()
        let replaceDelegate = TextViewDelegateProbe()
        replaceView.delegate = replaceDelegate
        replaceView.string = "Hello world"
        replaceView.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Hi")
        let replaceUpdatesStringAndStorage =
            replaceView.string == "Hi world" &&
            replaceView.textStorage?.string == "Hi world" &&
            replaceDelegate.shouldChangeRequests == 1 &&
            replaceDelegate.lastReplacement == "Hi" &&
            replaceDelegate.changeNotifications == 1 &&
            replaceDelegate.changedTextView === replaceView

        let insertView = NSTextView()
        insertView.string = "Hello world"
        insertView.setSelectedRange(NSRange(location: 6, length: 5))
        insertView.insertText("Quill", replacementRange: NSRange(location: selectedRangeSentinel, length: 0))
        let insertUsesSelectedRange =
            insertView.string == "Hello Quill" &&
            insertView.selectedRange == NSRange(location: 11, length: 0)

        let attributedInsertView = NSTextView()
        attributedInsertView.string = "Say "
        attributedInsertView.setSelectedRange(NSRange(location: 4, length: 0))
        attributedInsertView.insertText(
            NSAttributedString(string: "hello"),
            replacementRange: NSRange(location: selectedRangeSentinel, length: 0)
        )
        let attributedInsertUsesStringContents =
            attributedInsertView.string == "Say hello" &&
            attributedInsertView.selectedRange == NSRange(location: 9, length: 0)

        let vetoView = NSTextView()
        let vetoDelegate = TextViewDelegateProbe()
        vetoDelegate.allowsChanges = false
        vetoView.delegate = vetoDelegate
        vetoView.string = "Keep"
        vetoView.replaceCharacters(in: NSRange(location: 0, length: 4), with: "Drop")
        let delegateCanVetoChange =
            vetoView.string == "Keep" &&
            vetoDelegate.shouldChangeRequests == 1 &&
            vetoDelegate.changeNotifications == 0

        let callbackView = NSTextView()
        let callbackDelegate = TextViewDelegateProbe()
        callbackView.delegate = callbackDelegate
        callbackView.string = "abcdef"
        callbackView.setSelectedRange(NSRange(location: 1, length: 3))
        callbackView.insertText("Z", replacementRange: NSRange(location: selectedRangeSentinel, length: 0))
        let delegateReceivesChangeAndSelectionNotifications =
            callbackDelegate.changeNotifications == 1 &&
            callbackDelegate.selectionNotifications >= 1 &&
            callbackDelegate.changedTextView === callbackView &&
            callbackDelegate.selectionTextView === callbackView

        return AppKitTextViewEditingResult(
            replaceUpdatesStringAndStorage: replaceUpdatesStringAndStorage,
            insertUsesSelectedRange: insertUsesSelectedRange,
            attributedInsertUsesStringContents: attributedInsertUsesStringContents,
            delegateCanVetoChange: delegateCanVetoChange,
            delegateReceivesChangeAndSelectionNotifications: delegateReceivesChangeAndSelectionNotifications
        )
    }

    @MainActor
    static func runAppKitTableSmoke() -> AppKitTableResult {
        let tableView = NSTableView()
        let delegate = TableDelegateProbe()
        tableView.delegate = delegate
        tableView.dataSource = delegate
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 5, height: 3)

        delegate.rowCount = 4
        tableView.reloadData()
        let reloadUpdatedRowCount = tableView.numberOfRows == 4

        let promptColumn = NSTableColumn(identifier: "prompt")
        promptColumn.width = 120
        let answerColumn = NSTableColumn(identifier: "answer")
        answerColumn.width = 80
        tableView.addTableColumn(promptColumn)
        tableView.addTableColumn(answerColumn)

        delegate.rowHeight = 28
        let frame = tableView.frameOfCell(atColumn: 1, row: 2)
        let frameUsesColumnWidthsAndRowHeight =
            frame == NSRect(x: 125, y: 50, width: 80, height: 28)

        let rowView = tableView.rowView(atRow: 0, makeIfNecessary: true)
        let sameRowView = tableView.rowView(atRow: 0, makeIfNecessary: false)
        let cellView = tableView.view(atColumn: 0, row: 0, makeIfNecessary: true)
        let sameCellView = tableView.view(atColumn: 0, row: 0, makeIfNecessary: false)
        let reusedCellView = tableView.makeView(withIdentifier: "cell-0-0", owner: nil)
        let rowAndCellViewsCached =
            rowView != nil &&
            rowView === sameRowView &&
            cellView != nil &&
            cellView === sameCellView &&
            cellView === reusedCellView &&
            delegate.addedRows == [0]

        let rowColumnLookupFromViews: Bool
        if let rowView, let cellView {
            rowColumnLookupFromViews =
                tableView.row(for: rowView) == 0 &&
                tableView.column(for: rowView) == -1 &&
                tableView.row(for: cellView) == 0 &&
                tableView.column(for: cellView) == 0
        } else {
            rowColumnLookupFromViews = false
        }

        var multiSelection = IndexSet()
        multiSelection.insert(1)
        multiSelection.insert(3)
        tableView.allowsMultipleSelection = true
        tableView.selectRowIndexes(multiSelection, byExtendingSelection: false)
        let multiSelectionRoundTrip =
            tableView.selectedRowIndexes == multiSelection &&
            tableView.selectedRow == 1

        var singleSelectionRequest = IndexSet()
        singleSelectionRequest.insert(0)
        singleSelectionRequest.insert(2)
        tableView.allowsMultipleSelection = false
        tableView.selectRowIndexes(singleSelectionRequest, byExtendingSelection: false)
        let singleSelectionKeptFirst =
            tableView.selectedRowIndexes == IndexSet(integer: 0) &&
            tableView.selectedRow == 0
        tableView.allowsEmptySelection = false
        tableView.deselectAll(nil)
        let singleSelectionAndEmptyRules =
            singleSelectionKeptFirst &&
            tableView.selectedRowIndexes == IndexSet(integer: 0) &&
            tableView.selectedRow == 0

        let lookupBeforeRemoval =
            tableView.numberOfColumns == 2 &&
            tableView.column(withIdentifier: "answer") == 1 &&
            tableView.tableColumn(withIdentifier: "prompt") === promptColumn
        tableView.selectedColumnIndexes = IndexSet([0, 1])
        tableView.removeTableColumn(promptColumn)
        let columnLookupAndRemoval =
            lookupBeforeRemoval &&
            tableView.numberOfColumns == 1 &&
            tableView.column(withIdentifier: "answer") == 0 &&
            tableView.tableColumn(withIdentifier: "prompt") == nil &&
            tableView.selectedColumnIndexes == IndexSet(integer: 0) &&
            tableView.column(for: cellView ?? NSView()) == -1

        let delegateSelectionNotification =
            delegate.selectionNotifications >= 2 &&
            delegate.selectionNotificationObject === tableView

        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        delegate.removedRows.removeAll()
        let removedRowView = tableView.rowView(atRow: 1, makeIfNecessary: true)
        let movedCellView = tableView.view(atColumn: 0, row: 2, makeIfNecessary: true)
        tableView.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
        tableView.clickedRow = 2
        tableView.insertRows(at: IndexSet([1, 3]), withAnimation: [])
        let insertShiftedState =
            tableView.numberOfRows == 6 &&
            tableView.selectedRowIndexes == IndexSet([2, 4]) &&
            tableView.clickedRow == 4 &&
            tableView.row(for: movedCellView ?? NSView()) == 4
        tableView.removeRows(at: IndexSet([0, 2]), withAnimation: [])
        let removeShiftedState =
            tableView.numberOfRows == 4 &&
            tableView.selectedRowIndexes == IndexSet(integer: 2) &&
            tableView.clickedRow == 2 &&
            tableView.row(for: movedCellView ?? NSView()) == 2 &&
            tableView.row(for: removedRowView ?? NSView()) == -1 &&
            delegate.removedRows == [0, 2]
        tableView.moveRow(at: 2, to: 3)
        let moveShiftedState =
            tableView.numberOfRows == 4 &&
            tableView.selectedRowIndexes == IndexSet(integer: 3) &&
            tableView.clickedRow == 3 &&
            tableView.row(for: movedCellView ?? NSView()) == 3
        let rowMutationsPreserveState = insertShiftedState && removeShiftedState && moveShiftedState

        return AppKitTableResult(
            reloadUpdatedRowCount: reloadUpdatedRowCount,
            columnLookupAndRemoval: columnLookupAndRemoval,
            multiSelectionRoundTrip: multiSelectionRoundTrip,
            singleSelectionAndEmptyRules: singleSelectionAndEmptyRules,
            delegateSelectionNotification: delegateSelectionNotification,
            rowAndCellViewsCached: rowAndCellViewsCached,
            frameUsesColumnWidthsAndRowHeight: frameUsesColumnWidthsAndRowHeight,
            rowColumnLookupFromViews: rowColumnLookupFromViews,
            rowMutationsPreserveState: rowMutationsPreserveState
        )
    }

    @MainActor
    static func runAppKitOutlineSmoke() -> AppKitOutlineResult {
        let leaf = OutlineItemProbe("Leaf")
        let grandchild = OutlineItemProbe("Grandchild")
        let nested = OutlineItemProbe("Nested", children: [grandchild])
        let folder = OutlineItemProbe("Folder", children: [leaf, nested])
        let sibling = OutlineItemProbe("Sibling")
        let probe = OutlineDelegateProbe(roots: [folder, sibling])

        let outlineView = NSOutlineView()
        let column = NSTableColumn(identifier: "outline")
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.dataSource = probe
        outlineView.delegate = probe

        outlineView.reloadData()
        let reloadShowsRootItems =
            outlineView.numberOfRows == 2 &&
            (outlineView.item(atRow: 0) as? OutlineItemProbe) === folder &&
            (outlineView.item(atRow: 1) as? OutlineItemProbe) === sibling &&
            outlineView.row(forItem: folder) == 0 &&
            outlineView.row(forItem: leaf) == -1 &&
            outlineView.numberOfChildren(ofItem: nil) == 2 &&
            (outlineView.child(0, ofItem: nil) as? OutlineItemProbe) === folder &&
            outlineView.childIndex(forItem: folder) == 0 &&
            outlineView.level(forRow: 0) == 0 &&
            outlineView.level(forItem: folder) == 0 &&
            outlineView.isExpandable(folder) &&
            !outlineView.isExpandable(leaf)

        outlineView.expandItem(folder)
        let leafRow = outlineView.row(forItem: leaf)
        let nestedRow = outlineView.row(forItem: nested)
        let expandShowsChildrenAndLevels =
            outlineView.numberOfRows == 4 &&
            outlineView.isItemExpanded(folder) &&
            leafRow == 1 &&
            nestedRow == 2 &&
            outlineView.level(forRow: leafRow) == 1 &&
            outlineView.level(forItem: nested) == 1 &&
            (outlineView.item(atRow: 3) as? OutlineItemProbe) === sibling

        let rowParentAndChildLookup =
            (outlineView.parent(forItem: leaf) as? OutlineItemProbe) === folder &&
            outlineView.childIndex(forItem: leaf) == 0 &&
            outlineView.childIndex(forItem: nested) == 1 &&
            outlineView.numberOfChildren(ofItem: folder) == 2 &&
            (outlineView.child(1, ofItem: folder) as? OutlineItemProbe) === nested

        let rowView = outlineView.rowView(atRow: leafRow, makeIfNecessary: true)
        let cellView = outlineView.view(atColumn: 0, row: leafRow, makeIfNecessary: true)
        let delegateViewsUseItems =
            rowView === probe.rowViews["Leaf"] &&
            cellView?.identifier == "outline-cell-Leaf"

        outlineView.selectRowIndexesInOutlineView(IndexSet(integer: leafRow))
        let selectionRoundTrip =
            outlineView.selectedRowIndexes == IndexSet(integer: leafRow) &&
            outlineView.selectedRow == leafRow &&
            probe.selectionNotifications == 1 &&
            probe.selectionNotificationObject === outlineView

        outlineView.collapseItem(folder)
        let collapseHidesChildrenAndClearsSelection =
            !outlineView.isItemExpanded(folder) &&
            outlineView.numberOfRows == 2 &&
            outlineView.row(forItem: leaf) == -1 &&
            outlineView.selectedRowIndexes.isEmpty &&
            outlineView.selectedRow == -1

        outlineView.expandItem(folder, expandChildren: true)
        let recursiveExpand =
            outlineView.isItemExpanded(folder) &&
            outlineView.isItemExpanded(nested) &&
            outlineView.row(forItem: grandchild) == 3 &&
            outlineView.level(forItem: grandchild) == 2
        outlineView.collapseItem(folder, collapseChildren: true)
        let recursiveExpansionAndCollapse =
            recursiveExpand &&
            !outlineView.isItemExpanded(folder) &&
            !outlineView.isItemExpanded(nested) &&
            outlineView.row(forItem: grandchild) == -1

        return AppKitOutlineResult(
            reloadShowsRootItems: reloadShowsRootItems,
            expandShowsChildrenAndLevels: expandShowsChildrenAndLevels,
            rowParentAndChildLookup: rowParentAndChildLookup,
            delegateViewsUseItems: delegateViewsUseItems,
            selectionRoundTrip: selectionRoundTrip,
            collapseHidesChildrenAndClearsSelection: collapseHidesChildrenAndClearsSelection,
            recursiveExpansionAndCollapse: recursiveExpansionAndCollapse
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

    static func runAppKitUndoSmoke() -> AppKitUndoResult {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let probe = UndoProbe()
        probe.undoManager = manager
        probe.setValue(1)
        manager.setActionName("Change Value")
        let actionNamesRoundTrip = manager.undoActionName == "Change Value"
        let registeredAction = manager.canUndo && probe.value == 1
        manager.undo()
        let undoneAction = probe.value == 0 && !manager.isUndoing && manager.canRedo
        manager.redo()
        let redoneAction = probe.value == 1 && !manager.isRedoing && manager.canUndo
        let singleActionUndoRedoRoundTrip = registeredAction && undoneAction && redoneAction

        let disabledManager = UndoManager()
        disabledManager.groupsByEvent = false
        let disabledProbe = UndoProbe()
        disabledProbe.undoManager = disabledManager
        disabledManager.disableUndoRegistration()
        disabledProbe.setValue(1)
        let disabledRegistrationBlocked =
            !disabledManager.isUndoRegistrationEnabled &&
            !disabledManager.canUndo &&
            disabledProbe.value == 1
        disabledManager.enableUndoRegistration()
        let disablingRegistrationBlocksActions =
            disabledRegistrationBlocked &&
            disabledManager.isUndoRegistrationEnabled

        let removalManager = UndoManager()
        removalManager.groupsByEvent = false
        let removalProbe = UndoProbe()
        removalProbe.undoManager = removalManager
        removalProbe.setValue(2)
        let removalRegistered = removalManager.canUndo
        removalManager.removeAllActions(withTarget: removalProbe)
        let targetRemovalClearsActions = removalRegistered && !removalManager.canUndo

        let groupedManager = UndoManager()
        groupedManager.groupsByEvent = false
        let groupedProbe = UndoProbe()
        groupedProbe.undoManager = groupedManager
        groupedManager.beginUndoGrouping()
        groupedProbe.setValue(1)
        groupedProbe.setValue(2)
        groupedManager.endUndoGrouping()
        let groupedRegistered = groupedManager.canUndo && groupedProbe.value == 2
        groupedManager.undo()
        let groupedActionsUndoTogether = groupedRegistered && groupedProbe.value == 0 && groupedManager.canRedo
        groupedManager.redo()
        let groupedActionsRedoTogether = groupedActionsUndoTogether && groupedProbe.value == 2

        return AppKitUndoResult(
            singleActionUndoRedoRoundTrip: singleActionUndoRedoRoundTrip,
            actionNamesRoundTrip: actionNamesRoundTrip,
            disablingRegistrationBlocksActions: disablingRegistrationBlocksActions,
            targetRemovalClearsActions: targetRemovalClearsActions,
            groupedActionsUndoTogether: groupedActionsUndoTogether,
            groupedActionsRedoTogether: groupedActionsRedoTogether
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

private final class UndoProbe: NSObject {
    weak var undoManager: UndoManager?
    private(set) var value: Int = 0

    func setValue(_ newValue: Int) {
        let oldValue = value
        undoManager?.registerUndo(withTarget: self) { probe in
            probe.setValue(oldValue)
        }
        value = newValue
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

private final class SplitViewDelegateProbe: NSObject, NSSplitViewDelegate {
    var resizeNotifications = 0
    var lastNotification: Notification?

    func splitViewDidResizeSubviews(_ notification: Notification) {
        resizeNotifications += 1
        lastNotification = notification
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

private final class TextViewDelegateProbe: NSObject, NSTextViewDelegate {
    var allowsChanges = true
    var shouldChangeRequests = 0
    var changeNotifications = 0
    var selectionNotifications = 0
    var lastReplacement: String?
    weak var changedTextView: NSTextView?
    weak var selectionTextView: NSTextView?

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        shouldChangeRequests += 1
        lastReplacement = replacementString
        return allowsChanges
    }

    func textDidChange(_ notification: Notification) {
        changeNotifications += 1
        changedTextView = notification.object as? NSTextView
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        selectionNotifications += 1
        selectionTextView = notification.object as? NSTextView
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

private final class LayoutRecorder {
    var events: [String] = []
}

private final class LayoutProbe: NSView {
    var layoutName = ""
    var recorder: LayoutRecorder?
    var layoutCount = 0

    override func layout() {
        layoutCount += 1
        recorder?.events.append(layoutName)
    }
}

private final class DisplayProbe: NSView {
    var willDrawCount = 0

    override func viewWillDraw() {
        willDrawCount += 1
    }
}

@MainActor
private final class TableDelegateProbe: NSObject, NSTableViewDelegate, NSTableViewDataSource {
    var rowCount = 0
    var rowHeight: CGFloat = 0
    var addedRows: [Int] = []
    var removedRows: [Int] = []
    var selectionNotifications = 0
    weak var selectionNotificationObject: NSTableView?

    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        NSTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let column = tableView.column(withIdentifier: tableColumn?.identifier ?? "")
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(rawValue: "cell-\(column)-\(row)")
        return view
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        rowHeight
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectionNotifications += 1
        selectionNotificationObject = notification.object as? NSTableView
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        addedRows.append(row)
    }

    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
        removedRows.append(row)
    }
}

private final class OutlineItemProbe: NSObject {
    let title: String
    let children: [OutlineItemProbe]

    init(_ title: String, children: [OutlineItemProbe] = []) {
        self.title = title
        self.children = children
    }
}

@MainActor
private final class OutlineDelegateProbe: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let roots: [OutlineItemProbe]
    var rowViews: [String: NSTableRowView] = [:]
    var selectionNotifications = 0
    weak var selectionNotificationObject: NSOutlineView?

    init(roots: [OutlineItemProbe]) {
        self.roots = roots
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        children(of: item).isEmpty == false
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        (item as? OutlineItemProbe)?.title
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let item = item as? OutlineItemProbe else { return nil }
        let rowView = NSTableRowView()
        rowViews[item.title] = rowView
        return rowView
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OutlineItemProbe else { return nil }
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(rawValue: "outline-cell-\(item.title)")
        return view
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        selectionNotifications += 1
        selectionNotificationObject = notification.object as? NSOutlineView
    }

    private func children(of item: Any?) -> [OutlineItemProbe] {
        guard let item = item as? OutlineItemProbe else { return roots }
        return item.children
    }
}

private final class TrackingAreaOwnerProbe: NSObject {}
