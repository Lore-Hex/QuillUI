import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import SwiftUI
import SwiftData
import Combine
import QuillKit
import ActivityIndicatorView
import MarkdownUI
import Splash
import OllamaKit
import AsyncAlgorithms
import Carbon
import IOKit
import IOKit.usb
import WrappingHStack
import Vortex
import KeyboardShortcuts
@_spi(QuillTesting) import QuillUI

@Suite("Linux compatibility import modules", .serialized)
struct CompatibilityModuleTests {
    private func pngDimensions(_ data: Data) -> (width: UInt32, height: UInt32)? {
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data.prefix(8)) == pngMagic else { return nil }

        let bytes = Array(data)
        let width = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16)
                  | (UInt32(bytes[18]) << 8)  |  UInt32(bytes[19])
        let height = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16)
                   | (UInt32(bytes[22]) << 8)  |  UInt32(bytes[23])
        return (width, height)
    }

    @Test("SwiftUI and SwiftData module aliases expose Quill APIs")
    func swiftUIAndSwiftDataAliasesExposeQuillAPIs() throws {
        _ = Text("Quill")
            .foregroundStyle(Color("label"))
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
        _ = ModelConfiguration(isStoredInMemoryOnly: true)
        _ = FetchDescriptor<CompatibilityModel>()
        _ = Window("Compatibility", id: "compatibility") {
            Text("Compatibility")
        }
    }

    @Test("QuillUI fallback modifiers record diagnostics")
    func quillUIFallbackModifiersRecordDiagnostics() {
        QuillCompatibilityDiagnostics.shared.clear()

        _ = Text("Fallback")
            .symbolEffect(.variableColor, value: true)
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            .mask(Rectangle())
            .mask(Text("Mask"))
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .gesture(DragGesture().onChanged { _ in }.onEnded { _ in })
            .onHover { _ in }
            .focusEffectDisabled(false)
            .edgesIgnoringSafeArea(.top)
            .ignoresSafeArea(.bottom)
            .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            .listRowSeparator(.hidden, edges: .vertical)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .minimumScaleFactor(0.5)
            .textSelection(.enabled)
            .keyboardType(.URL)
            .autocapitalization(.never)
            .disableAutocorrection(true)
            .textContentType(.URL)
            .symbolRenderingMode(.hierarchical)

        _ = Text("Icon scaled").imageScale(.large)
        _ = Image(systemName: "photo").renderingMode(.template)
        _ = Form { Text("Field") }.formStyle(.grouped)

#if os(Linux)
        let scaled = Text("Scaled").minimumScaleFactor(0.5)
        #expect(scaled.factor == 0.5)
        #expect(String(describing: type(of: scaled)).contains("MinimumScaleFactorView"))

        let imageScaled = Text("Icon scaled").imageScale(.large)
        #expect(String(describing: type(of: imageScaled)).contains("ImageScaleView"))
        #expect(String(describing: imageScaled.scale).lowercased().contains("large"))

        let symbolMode = Text("Symbol").symbolRenderingMode(.hierarchical)
        #expect(String(describing: type(of: symbolMode)).contains("SymbolRenderingModeView"))
        #expect(String(describing: symbolMode.mode).lowercased().contains("hierarchical"))

        let rowInsets = Text("Row").listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        #expect(String(describing: type(of: rowInsets)).contains("ListRowInsetsView"))
        #expect(rowInsets.insets == EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))

        let rowSeparator = Text("Row").listRowSeparator(.hidden, edges: .vertical)
        #expect(String(describing: type(of: rowSeparator)).contains("ListRowSeparatorView"))
        #expect(rowSeparator.visibility == .hidden)
        #expect(rowSeparator.edges == .vertical)

        let scrollIndicators = Text("Scroll").scrollIndicators(.hidden)
        #expect(String(describing: type(of: scrollIndicators)).contains("ScrollIndicatorsView"))
        #expect(String(describing: scrollIndicators.visibility).contains("hidden"))

        let scrollBackground = Text("Scroll").scrollContentBackground(.hidden)
        #expect(String(describing: type(of: scrollBackground)).contains("ScrollContentBackgroundView"))
        #expect(scrollBackground.visibility == .hidden)

        let shapedContent = Text("Hit area").contentShape(Rectangle())
        #expect(String(describing: type(of: shapedContent)).contains("ContentShapeView"))
        #expect(String(describing: type(of: shapedContent.shape)).contains("Rectangle"))

        let hitTesting = Text("Hit Test").allowsHitTesting(false)
        #expect(String(describing: type(of: hitTesting)).contains("AllowsHitTestingView"))
        #expect(hitTesting.enabled == false)
        #expect(quillTextLabel(from: hitTesting) == "Hit Test")

        let gestured = Text("Drag").gesture(DragGesture().onChanged { _ in }.onEnded { _ in })
        #expect(String(describing: type(of: gestured)).contains("GestureView"))
        #expect(String(describing: type(of: gestured.gesture)).contains("DragGesture"))
        #expect(quillTextLabel(from: gestured) == "Drag")

        let transitioned = Text("Transition").transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .top)))
        #expect(String(describing: type(of: transitioned)).contains("TransitionView"))
        #expect(String(describing: transitioned.transition).contains("combined"))
        #expect(String(describing: transitioned.transition).contains("opacity"))
        #expect(String(describing: transitioned.transition).contains("scale"))
        #expect(quillTextLabel(from: transitioned) == "Transition")

        let maskedContent = Text("Masked").mask(Text("Mask"))
        #expect(String(describing: type(of: maskedContent)).contains("ViewMaskView"))
        #expect(quillTextLabel(from: maskedContent) == "Masked")
        #expect(quillTextLabel(from: maskedContent.mask) == "Mask")

        var hoverStates: [Bool] = []
        let hoverable = Text("Hover").onHover { hoverStates.append($0) }
        #expect(String(describing: type(of: hoverable)).contains("OnHoverView"))
        hoverable.action(true)
        hoverable.action(false)
        #expect(hoverStates == [true, false])

        let focusEffect = Text("Focus").focusEffectDisabled(false)
        #expect(String(describing: type(of: focusEffect)).contains("FocusEffectDisabledView"))
        #expect(focusEffect.disabled == false)

        let legacySafeArea = Text("Legacy Safe Area").edgesIgnoringSafeArea(.top)
        #expect(String(describing: type(of: legacySafeArea)).contains("EdgesIgnoringSafeAreaView"))
        #expect(legacySafeArea.edges == .top)

        let ignoredSafeArea = Text("Safe Area").ignoresSafeArea(.bottom)
        #expect(String(describing: type(of: ignoredSafeArea)).contains("IgnoresSafeAreaView"))
        #expect(ignoredSafeArea.edges == .bottom)

        let selectable = Text("Selectable").textSelection(.enabled)
        #expect(String(describing: type(of: selectable)).contains("TextSelectionView"))
        #expect(String(describing: selectable.selection).contains("enabled"))

        let keyboardTyped = Text("URL").keyboardType(.URL)
        #expect(String(describing: type(of: keyboardTyped)).contains("KeyboardTypeView"))
        #expect(keyboardTyped.keyboardType == .URL)

        let autocapitalized = Text("Lowercase").autocapitalization(.never)
        #expect(String(describing: type(of: autocapitalized)).contains("AutocapitalizationView"))
        #expect(autocapitalized.autocapitalization == .never)

        let autocorrectionDisabled = Text("No correction").disableAutocorrection(true)
        #expect(String(describing: type(of: autocorrectionDisabled)).contains("AutocorrectionDisabledView"))
        #expect(autocorrectionDisabled.disabled == true)

        let typedContent = Text("URL").textContentType(.URL)
        #expect(String(describing: type(of: typedContent)).contains("TextContentTypeView"))
        #expect(typedContent.contentType == .URL)
#endif

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.isSuperset(of: Set([
            "symbolEffect",
            "matchedGeometryEffect",
            "transition",
            "mask",
            "contentShape",
            "allowsHitTesting",
            "gesture",
            "onHover",
            "focusEffectDisabled",
            "edgesIgnoringSafeArea",
            "ignoresSafeArea",
            "listRowInsets",
            "listRowSeparator",
            "scrollIndicators",
            "scrollContentBackground",
            "minimumScaleFactor",
            "textSelection",
            "keyboardType",
            "autocapitalization",
            "disableAutocorrection",
            "textContentType",
            "imageScale",
            "symbolRenderingMode",
            "renderingMode",
            "formStyle"
        ])))
    }

    @Test("third-party UI packages compile to visible SwiftUI-shaped views")
    func thirdPartyUIShimsCompile() {
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .rotatingDots(count: 5))
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .growingCircle)
        _ = Markdown("# Heading\n\n```swift\nprint(\"Quill\")\n```")
            .markdownCodeSyntaxHighlighter(PlainTextCodeSyntaxHighlighter())
            .markdownTheme(markdownContractTheme)
        _ = WrappingHStack(alignment: .leading) {
            Text("One")
            Text("Two")
        }
        _ = VortexView(.splash.makeUniqueCopy()) {
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
        }
        _ = KeyboardShortcuts.Recorder("Keyboard shortcut", name: "togglePanelMode")
        _ = Text("Shortcut").onKeyboardShortcut("togglePanelMode", type: .keyDown) {}
    }

    @Test("AppKit image and KeyboardShortcuts compatibility cover Enchanted full source")
    func appKitImageAndKeyboardShortcutCompatibility() throws {
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
        let name = KeyboardShortcuts.Name("togglePanelMode", default: shortcut)
        #expect(name.rawValue == "togglePanelMode")
        #expect(name.defaultShortcut == shortcut)
        #expect(KeyboardShortcuts.Shortcut(.character("p")).key == .character("p"))
        #expect(KeyboardShortcuts.Name("togglePanelMode") == name)

        let result = try AppleCompatibilitySmoke.runAppKitImageSmoke()
        #expect(result.sizeRoundTrip)
        #expect(result.namedImagePlaceholder)
        #expect(result.systemImagePlaceholder)
        #expect(result.workspaceFileIconPlaceholder)
        #expect(result.workspaceContentTypeIconPlaceholder)
        #expect(result.bitmapRepresentationRoundTrip)
        #expect(result.windowTabbingRoundTrip)
        #expect(result.operations.isSuperset(of: Set([
            "NSImage.lockFocus",
            "NSImage.draw",
            "NSImage.unlockFocus",
            "NSImage(named:)",
            "NSImage(systemName:)",
            "NSWorkspace.icon(forFile:)",
            "NSWorkspace.icon(forContentType:)"
        ])))
    }

    @Test("AppKit menu popups update delegates and track presentation")
    @MainActor
    func appKitMenuPopupsUpdateDelegatesAndTrackPresentation() {
        let result = AppleCompatibilitySmoke.runAppKitMenuSmoke()

        #expect(result.popupSucceeded)
        #expect(result.trackingBegan)
        #expect(result.rememberedPositioningItem)
        #expect(result.rememberedLocation)
        #expect(result.rememberedView)
        #expect(result.itemMenuBacklinks)
        #expect(result.submenuParentLink)
        #expect(result.replacedSubmenuClearedParentLink)
        #expect(result.clearedSubmenuParentLink)
        #expect(result.autoValidationDisabledItem)
        #expect(result.delegateEvents.isSuperset(of: Set([
            "numberOfItems:2",
            "needsUpdate:Chat",
            "update:Copy:0:false",
            "update:Disabled:1:false",
            "willOpen:Chat"
        ])))
        #expect(result.trackingEnded)
        #expect(result.removedItemClearedMenu)
        #expect(result.removeAllClearedMenus)
    }

    @Test("AppKit controls mirror values and button factories")
    func appKitControlsMirrorValuesAndButtonFactories() {
        let result = AppleCompatibilitySmoke.runAppKitControlSmoke()

        #expect(result.stringValueUpdatedNumericAndObjectValues)
        #expect(result.numericValuesUpdatedStringAndObjectValues)
        #expect(result.objectValueUpdatedStringAndNumericValues)
        #expect(result.attributedValueUpdatedStringAndNumericValues)
        #expect(result.explicitActionSentToTarget)
        #expect(result.missingActionOrTargetRejected)
        #expect(result.applicationExplicitActionSentToTarget)
        #expect(result.applicationMissingTargetRejected)
        #expect(result.textButtonPreservedTargetActionAndTitle)
        #expect(result.imageButtonPreservedTargetAndAction)
        #expect(result.checkboxFactoryPreservedTargetActionAndTitle)
        #expect(result.radioFactoryPreservedTargetActionAndTitle)
        #expect(result.labelInitializerPreservedLabelTraits)
        #expect(result.wrappingLabelInitializerPreservedWrappingTraits)
        #expect(result.stringInitializerPreservedEditableTraits)
        #expect(result.sliderInitializerPreservedRangeTargetAndAction)
    }

    @Test("AppKit pop-up buttons preserve menu selection state")
    func appKitPopUpButtonsPreserveMenuSelectionState() {
        let result = AppleCompatibilitySmoke.runAppKitPopUpButtonSmoke()

        #expect(result.firstItemSelectedAfterAdd)
        #expect(result.selectionFollowsIndex)
        #expect(result.invalidSelectionPreservesCurrentItem)
        #expect(result.selectionFollowsTitle)
        #expect(result.selectionFollowsTag)
        #expect(result.removedSelectedItemChoosesAdjacentItem)
        #expect(result.removeAllClearsSelection)
        #expect(result.menuReplacementSelectsFirstItem)
        #expect(result.menuItemBacklinks)
    }

    @Test("AppKit popovers maintain presentation and delegate state")
    @MainActor
    func appKitPopoversMaintainPresentationAndDelegateState() {
        let result = AppleCompatibilitySmoke.runAppKitPopoverSmoke()

        #expect(result.showUpdatedStateAndAnchor)
        #expect(result.repeatedShowUpdatedAnchorWithoutDuplicateCallbacks)
        #expect(result.closeVetoPreservedState)
        #expect(result.performCloseDelegatedToClose)
        #expect(result.redundantCloseIgnored)
    }

    @Test("AppKit toolbars ask delegates and maintain visible items")
    @MainActor
    func appKitToolbarsAskDelegatesAndMaintainVisibleItems() {
        let result = AppleCompatibilitySmoke.runAppKitToolbarSmoke()

        #expect(result.insertedItemsInDelegateOrder)
        #expect(result.delegateSawInsertedFlag)
        #expect(result.visibleItemsFollowItems)
        #expect(result.removedItemUpdatesItems)
        #expect(result.removingSelectedItemClearsSelection)
        #expect(result.outOfRangeRemoveIgnored)
    }

    @Test("AppKit windows maintain controller and child state")
    @MainActor
    func appKitWindowsMaintainControllerAndChildState() {
        let result = AppleCompatibilitySmoke.runAppKitWindowSmoke()

        #expect(result.controllerBacklinksRoundTrip)
        #expect(result.childWindowLinksRoundTrip)
        #expect(result.childReparentClearsPreviousParent)
        #expect(result.childRemovalClearsParent)
        #expect(result.tabbedWindowsRoundTrip)
        #expect(result.applicationTabIdentifierLookup)
        #expect(result.sheetLifecycleRoundTrip)
    }

    @Test("AppKit views maintain hierarchy and window links")
    @MainActor
    func appKitViewsMaintainHierarchyAndWindowLinks() {
        let result = AppleCompatibilitySmoke.runAppKitViewHierarchySmoke()

        #expect(result.addEstablishedLinks)
        #expect(result.addFiredSuperviewCallbacks)
        #expect(result.reparentedWithoutDuplicateBacklinks)
        #expect(result.removalClearedLinks)
        #expect(result.removalFiredSuperviewCallbacks)
        #expect(result.scrollDocumentViewInstalledInClipView)
        #expect(result.scrollContentSubviewFindsEnclosingScrollView)
        #expect(result.scrollDocumentViewClearingRemovedDocument)
        #expect(result.windowContentViewPropagated)
        #expect(result.windowContentViewCleared)
        #expect(result.windowCallbacksReachedSubview)
        #expect(result.frameInitializerEstablishedBounds)
        #expect(result.frameResizeScaledBounds)
        #expect(result.offWindowDisplayInvalidationIgnored)
        #expect(result.windowAttachmentMarksDisplayDirty)
        #expect(result.displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay)
        #expect(result.setNeedsDisplayMarksAncestorDirty)
        #expect(result.displayIfNeededClearsDirtyDescendants)
        #expect(result.forcedDisplayCallsViewWillDrawWhenClean)
        #expect(result.newViewsStartNeedingLayout)
        #expect(result.layoutSubtreeClearsNeedsLayout)
        #expect(result.layoutSubtreeVisitsDirtyDescendants)
        #expect(result.layoutSubtreeSkipsCleanViews)
        #expect(result.layoutSubtreeVisitsDirtyDescendantFromCleanAncestor)
        #expect(result.frameAndBoundsMutationsMarkNeedsLayout)
        #expect(result.hitTestReturnsTopmostVisibleSubview)
        #expect(result.hitTestIgnoresHiddenSubview)
        #expect(result.hitTestRejectsOutsideBounds)
        #expect(result.hitTestReturnsReceiverInsideBounds)
        #expect(result.convertFromDescendantAccumulatesFrameOrigins)
        #expect(result.convertToDescendantSubtractsFrameOrigins)
        #expect(result.convertBetweenSiblingsUsesCommonSuperview)
        #expect(result.convertRectPreservesSize)
        #expect(result.convertNilUsesWindowCoordinates)
        #expect(result.convertScaledBoundsAppliesBoundsTransform)
    }

    @Test("AppKit responders maintain chain and first responder lifecycle")
    @MainActor
    func appKitRespondersMaintainChainAndFirstResponderLifecycle() {
        let result = AppleCompatibilitySmoke.runAppKitResponderSmoke()

        #expect(result.explicitNextResponderRoundTrip)
        #expect(result.viewDefaultResponderChain)
        #expect(result.viewControllerOwnsViewResponder)
        #expect(result.eventForwardingReachesNextResponder)
        #expect(result.makeFirstResponderCallsLifecycle)
        #expect(result.rejectedFirstResponderPreservesCurrent)
        #expect(result.clearingFirstResponderResignsCurrent)
        #expect(result.applicationSendEventDispatchesToFirstResponder)
        #expect(result.applicationCurrentEventTracksDispatch)
        #expect(result.localEventMonitorCanRewriteEvent)
        #expect(result.localEventMonitorCanCancelEvent)
        #expect(result.globalEventMonitorObservesDispatchedEvent)
        #expect(result.removedEventMonitorStopsObserving)
    }

    @Test("AppKit view controllers maintain containment links")
    @MainActor
    func appKitViewControllersMaintainContainmentLinks() {
        let result = AppleCompatibilitySmoke.runAppKitViewControllerContainmentSmoke()

        #expect(result.addEstablishedParentLinks)
        #expect(result.secondChildPreservedOrder)
        #expect(result.removeClearedParentLinks)
        #expect(result.orphanRemoveIgnored)
    }

    @Test("AppKit split views maintain arranged item links")
    @MainActor
    func appKitSplitViewsMaintainArrangedItemLinks() {
        let result = AppleCompatibilitySmoke.runAppKitSplitViewSmoke()

        #expect(result.arrangedSubviewLinks)
        #expect(result.arrangedSubviewRemovalUpdatedOrder)
        #expect(result.defaultDividerMatchesAppKit)
        #expect(result.adjustSubviewsLaysOutTwoPanes)
        #expect(result.setPositionMovesAdjacentPanes)
        #expect(result.setPositionNotifiesDelegate)
        #expect(result.controllerAddedItemsInOrder)
        #expect(result.controllerRemoveClearedLinks)
        #expect(result.factoryBehaviorsRoundTrip)
    }

    @Test("AppKit views maintain tracking areas")
    @MainActor
    func appKitViewsMaintainTrackingAreas() {
        let result = AppleCompatibilitySmoke.runAppKitTrackingAreaSmoke()

        #expect(result.metadataRoundTripped)
        #expect(result.addRecordedTrackingArea)
        #expect(result.unknownRemoveIgnored)
        #expect(result.removeClearedTrackingArea)
    }

    @Test("AppKit text views apply edit APIs and notify delegates")
    @MainActor
    func appKitTextViewsApplyEditApisAndNotifyDelegates() {
        let result = AppleCompatibilitySmoke.runAppKitTextViewEditingSmoke()

        #expect(result.replaceUpdatesStringAndStorage)
        #expect(result.insertUsesSelectedRange)
        #expect(result.attributedInsertUsesStringContents)
        #expect(result.delegateCanVetoChange)
        #expect(result.delegateReceivesChangeAndSelectionNotifications)
    }

    @Test("AppKit table views maintain rows columns and selection")
    @MainActor
    func appKitTableViewsMaintainRowsColumnsAndSelection() {
        let result = AppleCompatibilitySmoke.runAppKitTableSmoke()

        #expect(result.reloadUpdatedRowCount)
        #expect(result.columnLookupAndRemoval)
        #expect(result.multiSelectionRoundTrip)
        #expect(result.singleSelectionAndEmptyRules)
        #expect(result.delegateSelectionNotification)
        #expect(result.rowAndCellViewsCached)
        #expect(result.frameUsesColumnWidthsAndRowHeight)
        #expect(result.rowColumnLookupFromViews)
        #expect(result.rowMutationsPreserveState)
    }

    @Test("AppKit outline views flatten expanded data source items")
    @MainActor
    func appKitOutlineViewsFlattenExpandedDataSourceItems() {
        let result = AppleCompatibilitySmoke.runAppKitOutlineSmoke()

        #expect(result.reloadShowsRootItems)
        #expect(result.expandShowsChildrenAndLevels)
        #expect(result.rowParentAndChildLookup)
        #expect(result.delegateViewsUseItems)
        #expect(result.selectionRoundTrip)
        #expect(result.collapseHidesChildrenAndClearsSelection)
        #expect(result.recursiveExpansionAndCollapse)
    }

    @Test("AppKit documents maintain edit and controller state")
    @MainActor
    func appKitDocumentsMaintainEditAndControllerState() {
        let result = AppleCompatibilitySmoke.runAppKitDocumentSmoke()

        #expect(result.displayNameFollowsFileURL)
        #expect(result.changeCountTracksEditedState)
        #expect(result.windowControllerLinksRoundTrip)
        #expect(result.documentControllerMaintainsCurrentDocument)
        #expect(result.openDocumentCreatesAndReusesDocument)
    }

    @Test("AppKit undo managers maintain action stacks")
    func appKitUndoManagersMaintainActionStacks() {
        let result = AppleCompatibilitySmoke.runAppKitUndoSmoke()

        #expect(result.singleActionUndoRedoRoundTrip)
        #expect(result.actionNamesRoundTrip)
        #expect(result.disablingRegistrationBlocksActions)
        #expect(result.targetRemovalClearsActions)
        #expect(result.groupedActionsUndoTogether)
        #expect(result.groupedActionsRedoTogether)
    }

    @Test("KeyboardShortcuts persist defaults and user overrides by raw name")
    func keyboardShortcutsPersistDefaultsAndUserOverrides() {
        let defaultShortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        let overrideShortcut = KeyboardShortcuts.Shortcut(.character("p"), modifiers: [.command, .shift])
        let name = KeyboardShortcuts.Name("togglePanelMode1", default: defaultShortcut)

        KeyboardShortcuts.reset(name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == defaultShortcut)

        KeyboardShortcuts.setShortcut(overrideShortcut, for: name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == overrideShortcut)
        #expect(KeyboardShortcuts.getShortcut(for: "togglePanelMode1") == overrideShortcut)

        KeyboardShortcuts.reset(name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == defaultShortcut)

        KeyboardShortcuts.resetAll()
    }

    @Test("MarkdownUI and Splash cover Enchanted markdown theme contracts")
    func markdownAndSplashContractsCompile() {
        let configuration = CodeBlockConfiguration(language: "swift", content: "let answer = 42")
        let highlighted = ContractSplashCodeSyntaxHighlighter(theme: .sunset(withFont: .init(size: 16)))
            .highlightCode(configuration.content, language: configuration.language)
        let richPlainText = Markdown.plainText(from: """
        # Plan

        - Render **Markdown**
        > Keep code readable

        ```swift
        let answer = 42
        ```
        """)

        let inlinePlainText = Markdown.plainText(
            from: "Use **bold**, _italic_, `code`, ~~old~~, [link](https://example.com), and ![chart](chart.png)"
        )
        let tablePlainText = Markdown.plainText(from: """
        | Property | Value |
        | --- | --- |
        | display | `flex` |
        | align-items | `center` |
        """)

        #expect(inlinePlainText.contains("bold"))
        #expect(inlinePlainText.contains("italic"))
        #expect(inlinePlainText.contains("code"))
        #expect(inlinePlainText.contains("old"))
        #expect(inlinePlainText.contains("link (https://example.com)"))
        #expect(inlinePlainText.contains("chart"))
        #expect(tablePlainText.contains("Property | Value"))
        #expect(tablePlainText.contains("display | flex"))
        #expect(tablePlainText.contains("align-items | center"))
        #expect(richPlainText.contains("Plan"))
        #expect(richPlainText.contains("• Render Markdown"))
        #expect(richPlainText.contains("Keep code readable"))
        #expect(richPlainText.contains("let answer = 42"))
        #expect(configuration.language == "swift")
        #expect(highlighted.content.contains("answer"))
        #expect(Splash.Theme.wwdc17(withFont: .init(size: 16)).tokenColors[.keyword] != nil)

        _ = markdownContractTheme
        _ = Markdown("```swift\nlet answer = 42\n```")
            .markdownCodeSyntaxHighlighter(PlainTextCodeSyntaxHighlighter())
            .markdownTheme(markdownContractTheme)
        _ = Markdown("| Property | Value |\n| --- | --- |\n| display | `flex` |")
        _ = Text("one") + Text(" two")
        _ = configuration.label
            .relativeLineSpacing(.em(0.225))
            .markdownTextStyle {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .markdownMargin(top: .zero, bottom: .em(0.8))
    }

    @Test("OllamaKit compatibility covers Enchanted model and chat contracts")
    func ollamaKitContractsCompileAndStream() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (200, #"{"version":"0.6.0"}"#),
            "/api/tags": (200, #"{"models":[{"name":"llava:latest","details":{"families":["clip"]}},{"name":"llama3.2:latest"}]}"#),
            "/api/chat": (
                200,
                """
                {"message":{"role":"assistant","content":"Hel"},"done":false}
                {"message":{"role":"assistant","content":"lo"},"done":false}
                {"done":true}
                """
            )
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            transport: transport
        )

        #expect(await kit.reachable())

        let models = try await kit.models()
        #expect(models.models.map(\.name) == ["llava:latest", "llama3.2:latest"])
        #expect(models.models.first?.details.families == ["clip"])

        var request = OKChatRequestData(
            model: "llava:latest",
            messages: [
                .init(role: .system, content: "short"),
                .init(role: .user, content: "describe", images: ["base64"])
            ]
        )
        request.options = OKCompletionOptions(temperature: 0)

        var values: [OKChatResponse] = []
        var finished = false
        var failure: Error?
        let cancellable = kit.chat(data: request)
            .sink { completion in
                switch completion {
                case .finished:
                    finished = true
                case .failure(let error):
                    failure = error
                }
            } receiveValue: { response in
                values.append(response)
            }

        let deadline = Date().addingTimeInterval(1)
        while !finished && failure == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        cancellable.cancel()

        #expect(failure == nil)
        #expect(finished)
        #expect(values.map { $0.message?.content ?? "" }.joined() == "Hello")
        #expect(values.last?.done == true)
        #expect(transport.requests.contains { $0.path == "/api/chat" && $0.authorization == "Bearer secret" })
        #expect(transport.chatBody?.contains(#""stream":true"#) == true)

        let sessionBackedKit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            session: "compat-session"
        )
        #expect(sessionBackedKit.baseURL.absoluteString == "http://localhost:11434")
        #expect(sessionBackedKit.bearerToken == "secret")
    }

    @Test("OllamaKit compatibility reports HTTP and stream parse failures")
    func ollamaKitErrorContractsAreDeterministic() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (503, #"{"error":"down"}"#),
            "/api/tags": (500, #"{"error":"boom"}"#)
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            transport: transport
        )

        #expect(await kit.reachable() == false)
        await #expect(throws: OllamaKitError.self) {
            _ = try await kit.models()
        }
        #expect(throws: (any Error).self) {
            _ = try OllamaKit.decodeChatResponses(from: Data("not-json\n".utf8))
        }
    }

    @Test("AsyncAlgorithms and Carbon compatibility cover prompt-panel imports")
    func asyncAlgorithmsAndCarbonContractsCompile() async {
        var iterator = AsyncTimerSequence(interval: .milliseconds(1), clock: .continuous).makeAsyncIterator()
        let firstTick = await iterator.next()

        #expect(firstTick != nil)
        #expect(CarbonCompatibility.available == false)
    }

    @Test("IOKit USB compatibility covers Quill USB watcher imports")
    func ioKitUSBContractsCompile() {
        var iterator: io_iterator_t = 99
        let port = IONotificationPortCreate(kIOMainPortDefault)
        let callback: IOServiceMatchingCallback = { _, iterator in
            _ = IOIteratorNext(iterator)
        }

        IONotificationPortSetDispatchQueue(port, nil)
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            nil,
            callback,
            nil,
            &iterator
        )

        #expect(result == kIOReturnUnsupported)
        #expect(iterator == 0)
        #expect(IOIteratorNext(iterator) == 0)
        #expect(IOObjectRelease(iterator) == kIOReturnSuccess)
        #expect(kIOUSBDeviceClassName == "IOUSBDevice")
        #expect(kUSBVendorID == "idVendor")
        #expect(kUSBProductID == "idProduct")

        IONotificationPortDestroy(port)
    }

    @Test("Apple service modules provide diagnostic Linux fallbacks")
    @MainActor
    func appleServiceModulesCompile() throws {
        #expect(QuillKitPlatform.current == .linux)
        #expect(QuillKitCapabilities.status(for: .clipboard) == .emulated)
        let result = try AppleCompatibilitySmoke.runAppleServiceSmoke()
        #expect(result.pasteboardString == "hello")
        #expect(result.pasteboardItemString == "item text")
        #expect(result.pasteboardItemDataRoundTrip)
        #expect(result.pasteboardItemPropertyListRoundTrip)
        #expect(result.pasteboardItemTypesRoundTrip)
        #expect(result.pasteboardWriteObjectsItemsRoundTrip)
        #expect(result.pasteboardWriteObjectsDataRoundTrip)
        #expect(result.pasteboardReadObjectsRoundTrip)
        #expect(result.pasteboardClearResetsItems)
        #expect(result.pasteboardSetStringClearsOldData)
        #expect(result.pasteboardWriteObjectsClearsOldData)
        #expect(result.pasteboardDeclareTypesRoundTrip)
        #expect(result.pasteboardDeclareTypesClearsOldTypes)
        #expect(result.pasteboardDeclareTypesChangeCount)
        #expect(result.pasteboardDeclareTypesOwnerProvidesData)
        #expect(result.pasteboardAvailableTypeOrder)
        #expect(result.uiPasteboardString == "hello")
        #expect(result.imagesRoundTrip)
        #expect(result.speechStopSucceeded)
        #expect(result.speechRecognitionUnavailable)
        #expect(result.launchServiceEnabled)
        #expect(result.launchServiceDisabled)
        #expect(result.updaterUnavailable)
    }

    @Test("Security CoreGraphics Accessibility and Alamofire adapters compile")
    func lowerLevelServiceModulesCompile() throws {
        #expect(try AppleCompatibilitySmoke.runLowerLevelServiceSmoke())
    }

    @Test("os Logger compatibility records privacy-aware diagnostics")
    func osLoggerCompatibilityRecordsDiagnostics() {
        let result = AppleCompatibilitySmoke.runOSLogSmoke()
        #expect(result.operations.contains("Logger.info"))
        #expect(result.operations.contains("Logger.error"))
        #expect(result.renderedPublicValue)
        #expect(result.redactedPrivateValue)
    }

    @Test("Combine compatibility publishers support cancellation and timer sinks")
    func combineNoOpPublishersCompile() {
        let cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in }
        cancellable.cancel()

        let publisher = AnyPublisher<Int, Never>()
            .map { $0 > 0 }
            .eraseToAnyPublisher()
        let mappedCancellable = publisher.sink { _ in }
        mappedCancellable.cancel()

        var stored = Set<AnyCancellable>()
        Just(1)
            .eraseToAnyPublisher()
            .sink { _ in }
            .store(in: &stored)
        #expect(stored.count == 1)
    }

    @Test("Combine compatibility publishers deliver completion edge cases")
    func combineCompletionEdgeCases() {
        var justEvents: [String] = []
        let justCancellable = Just("value")
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    justEvents.append("finished")
                }
            } receiveValue: { value in
                justEvents.append(value)
            }
        justCancellable.cancel()
        #expect(justEvents == ["value", "finished"])

        var emptyCompleted = false
        _ = Empty<Int, Never>()
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    emptyCompleted = true
                }
            } receiveValue: { _ in }
        #expect(emptyCompleted)

        var lazyEmptyCompleted = false
        _ = Empty<Int, Never>(completeImmediately: false)
            .eraseToAnyPublisher()
            .sink { _ in lazyEmptyCompleted = true } receiveValue: { _ in }
        #expect(lazyEmptyCompleted == false)

        var failedWithBoom = false
        _ = Fail<Int, CombineTestError>(error: .boom)
            .eraseToAnyPublisher()
            .sink { completion in
                if case .failure(.boom) = completion {
                    failedWithBoom = true
                }
            } receiveValue: { _ in
                Issue.record("Fail publisher should not emit values")
            }
        #expect(failedWithBoom)
    }

    @Test("Combine subjects and merge deliver values from both inputs")
    func combineSubjectsAndMergeDeliverValues() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        var values: [Int] = []

        let cancellable = Publishers.Merge(first, second)
            .eraseToAnyPublisher()
            .sink { values.append($0) }

        first.send(1)
        second.send(2)
        cancellable.cancel()
        first.send(3)

        #expect(values == [1, 2])
    }

    @Test("Combine merge buffers values beyond current downstream demand")
    func combineMergeBuffersBeyondCurrentDemand() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        let subscriber = DemandRecordingSubscriber<Int, Never>()

        Publishers.Merge(first, second).subscribe(subscriber)
        subscriber.subscription?.request(.max(1))

        first.send(1)
        second.send(2)
        #expect(subscriber.values == [1])
        #expect(subscriber.completions == 0)

        subscriber.subscription?.request(.max(1))
        #expect(subscriber.values == [1, 2])

        first.send(completion: .finished)
        #expect(subscriber.completions == 0)
        second.send(completion: .finished)
        #expect(subscriber.completions == 1)
    }

    @Test("Combine subject completion is terminal")
    func combineSubjectCompletionIsTerminal() {
        let subject = PassthroughSubject<Int, Never>()
        var values: [Int] = []
        var completions = 0

        let cancellable = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                completions += 1
            }
        } receiveValue: { value in
            values.append(value)
        }

        subject.send(1)
        subject.send(completion: .finished)
        subject.send(2)
        cancellable.cancel()

        var lateSubscriberCompleted = false
        _ = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                lateSubscriberCompleted = true
            }
        } receiveValue: { _ in
            Issue.record("Completed subjects should not emit values to late subscribers")
        }

        #expect(values == [1])
        #expect(completions == 1)
        #expect(lateSubscriberCompleted)
    }

    @Test("Combine timer and notification publishers emit values")
    func combineTimerAndNotificationPublishersEmitValues() throws {
        var timerEvents = 0
        let runLoop = RunLoop.current
        let timer = Timer.publish(every: 0.01, on: runLoop, in: .default)
            .autoconnect()
            .sink { _ in
                timerEvents += 1
            }

        let deadline = Date().addingTimeInterval(1)
        while timerEvents == 0, Date() < deadline {
            _ = runLoop.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        timer.cancel()
        #expect(timerEvents >= 1)

        let name = Notification.Name("quill.combine.notification.\(UUID().uuidString)")
        var notifications: [Notification] = []
        let notificationCancellable = NotificationCenter.default.publisher(for: name)
            .sink { notification in
                notifications.append(notification)
            }

        NotificationCenter.default.post(name: name, object: "payload")
        notificationCancellable.cancel()
        NotificationCenter.default.post(name: name, object: "ignored")

        #expect(notifications.count == 1)
        #expect(notifications.first?.object as? String == "payload")
    }

    @Test("Combine subject cancellation is scoped to the cancelled subscriber")
    func combineSubjectCancellationIsScoped() {
        let subject = PassthroughSubject<Int, Never>()
        var firstValues: [Int] = []
        var secondValues: [Int] = []

        let first = subject.eraseToAnyPublisher().sink { firstValues.append($0) }
        let second = subject.eraseToAnyPublisher().sink { secondValues.append($0) }

        subject.send(1)
        first.cancel()
        first.cancel()
        subject.send(2)
        second.cancel()
        subject.send(3)

        #expect(firstValues == [1])
        #expect(secondValues == [1, 2])
    }

    @Test("AnyCancellable cancellation is idempotent")
    func anyCancellableCancellationIsIdempotent() {
        var cancelCount = 0
        let cancellable = AnyCancellable {
            cancelCount += 1
        }

        cancellable.cancel()
        cancellable.cancel()

        #expect(cancelCount == 1)
    }

    @Test("platform fallback shims record diagnostics")
    @MainActor
    func platformFallbacksRecordDiagnostics() throws {
        let result = try AppleCompatibilitySmoke.runDiagnosticFallbackSmoke()
        #expect(result.speechAuthorizationDenied)
        #expect(result.operations.isSuperset(of: Set([
            "impactOccurred",
            "notificationOccurred",
            "speechSynthesis",
            "requestAuthorization",
            "recognitionTask",
            "keyState",
            "postEvent",
            "registerSingleUseSpace",
            "trustEvaluation",
            "launchAtLogin"
        ])))
    }

    @Test("previously-silent QuillUI stubs now record diagnostics")
    func previouslySilentStubsRecordDiagnostics() throws {
        QuillCompatibilityDiagnostics.shared.clear()

        // Bindings: previously returned self with no diagnostic.
        let binding: Binding<Int> = .constant(0)
        _ = binding.animation()
        _ = binding.animation(.easeOut(duration: 0.1))

        // listStyle(PlainListStyle): previously returned self with no diagnostic.
        _ = Text("List row").listStyle(PlainListStyle())

        // Animation chain methods: previously returned self with no diagnostic.
        _ = Animation.snappy()
        _ = Animation.snappy(duration: 0.5)
        _ = Animation.easeOut(duration: 0.2).repeatForever(autoreverses: true)
        _ = Animation.easeOut(duration: 0.2).delay(0.4)

        // ImageRenderer: previously returned nil with no diagnostic.
        let renderer = ImageRenderer(content: Text("rendered"))
        #expect(renderer.uiImage == nil)
        #expect(renderer.nsImage == nil)
        #expect(Image(systemName: "photo").render() == nil)
        let platformImage = PlatformImage(data: Data([1, 2, 3]))
        #expect(platformImage.convertImageToBase64String() == "AQID")
        #expect(platformImage.aspectFittedToHeight(200).data == Data([1, 2, 3]))
        #expect(platformImage.compressImageData() == Data([1, 2, 3]))

        // NSImage.tiffRepresentation: corrupt PNG-like bytes now return nil
        // with a warning instead of returning the original non-TIFF bytes.
        let corruptPng = NSImage(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(corruptPng?.tiffRepresentation == nil)

        let events = QuillCompatibilityDiagnostics.shared.events
        let operations = Set(events.map(\.operation))

        // ImageRenderer.init still records the partial-renderer fallback
        // contract, while the access path logs when content can't be
        // rasterized. The Text("rendered") used above is a non-Color view,
        // so uiImage/nsImage still warn.
        #expect(operations.isSuperset(of: Set([
            "Binding.animation",
            "listStyle(PlainListStyle)",
            "Animation.snappy",
            "Animation.repeatForever",
            "Animation.delay",
            "ImageRenderer.init",
            "ImageRenderer.uiImage",
            "ImageRenderer.nsImage",
            "Image.render",
            "PlatformImage.aspectFittedToHeight",
            "PlatformImage.compressImageData",
            "NSImage.tiffRepresentation"
        ])))

        // Severity: stubs that just no-op are .info; stubs that return wrong/missing
        // data (NSImage tiff lie, ImageRenderer always-nil) are .warning so they
        // surface louder in any diagnostic UI that filters by severity.
        let severitiesByOperation = Dictionary(
            grouping: events,
            by: \.operation
        ).mapValues { Set($0.map(\.severity)) }

        #expect(severitiesByOperation["Binding.animation"]?.contains(.info) == true)
        #expect(severitiesByOperation["listStyle(PlainListStyle)"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.repeatForever"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.delay"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.snappy"]?.contains(.warning) == true)
        #expect(severitiesByOperation["NSImage.tiffRepresentation"]?.contains(.warning) == true)
        #expect(severitiesByOperation["ImageRenderer.uiImage"]?.contains(.warning) == true)
        #expect(severitiesByOperation["ImageRenderer.nsImage"]?.contains(.warning) == true)
        #expect(severitiesByOperation["Image.render"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.aspectFittedToHeight"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.compressImageData"]?.contains(.warning) == true)
    }

    @Test("Image(data:) deduplicates identical bytes within a process")
    func imageDataInitDeduplicatesIdenticalBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUIImages", isDirectory: true)

        // Snapshot existing files so we measure only the delta from this test.
        let before = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        // Make the bytes unique to this test run so we don't collide with other
        // tests' images that may share content.
        let unique = "quill-image-dedup-\(UUID().uuidString)".data(using: .utf8)!

        // Same bytes, three calls; should write exactly one file.
        _ = Image(data: unique)
        _ = Image(data: unique)
        _ = Image(data: unique)

        let after = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let added = Set(after).subtracting(Set(before))
        #expect(added.count == 1, "Image(data:) should write a single PNG for repeated identical bytes; instead wrote \(added.count): \(added.sorted())")

        // Different bytes should write a second file.
        let unique2 = "quill-image-dedup-2-\(UUID().uuidString)".data(using: .utf8)!
        _ = Image(data: unique2)

        let afterSecond = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let addedSecond = Set(afterSecond).subtracting(Set(before))
        #expect(addedSecond.count == 2, "Image(data:) with new bytes should add a second PNG; saw \(addedSecond.count) total new files")
    }

    // MARK: - Symbol name compatibility

    @Test("QuillSystemSymbol preserves backend-covered SF Symbols and maps close variants")
    func quillSystemSymbolMapsKnownAndPassesUnknown() {
        let knownMappings: [(input: String, expected: String)] = [
            ("paperplane.fill", "paperplane.fill"),
            ("photo", "photo"),
            ("photo.fill", "photo.fill"),
            ("lightbulb", "lightbulb"),
            ("lightbulb.circle", "lightbulb.circle"),
            ("lightbulb.circle.fill", "lightbulb.circle.fill"),
            ("character.cursor.ibeam", "character.cursor.ibeam"),
            ("textformat", "textformat"),
            ("textformat.abc", "textformat.abc"),
            ("keyboard", "keyboard"),
            ("waveform", "waveform"),
            ("xmark", "xmark.circle.fill"),
            ("x.circle", "xmark.circle.fill"),
            ("x.circle.fill", "xmark.circle.fill")
        ]

        for (input, expected) in knownMappings {
            #expect(
                QuillSystemSymbol.compatibleName(input) == expected,
                "Expected \(input) -> \(expected); got \(QuillSystemSymbol.compatibleName(input))"
            )
        }

        // Unknown names pass through unchanged so apps requesting symbols Quill
        // hasn't aliased yet still render the original token.
        #expect(QuillSystemSymbol.compatibleName("unknown.symbol.name") == "unknown.symbol.name")
        #expect(QuillSystemSymbol.compatibleName("") == "")
    }

    // MARK: - AppStorage round-trip

    @Test("AppStorage persists values across reads for every supported scalar type")
    func appStorageRoundTripsScalarValues() {
        let suffix = UUID().uuidString
        let stringKey = "quill.test.string.\(suffix)"
        let boolKey = "quill.test.bool.\(suffix)"
        let intKey = "quill.test.int.\(suffix)"
        let doubleKey = "quill.test.double.\(suffix)"

        defer {
            UserDefaults.standard.removeObject(forKey: stringKey)
            UserDefaults.standard.removeObject(forKey: boolKey)
            UserDefaults.standard.removeObject(forKey: intKey)
            UserDefaults.standard.removeObject(forKey: doubleKey)
        }

        // Default values are returned when the key has never been written.
        #expect(AppStorage(wrappedValue: "default-string", stringKey).wrappedValue == "default-string")
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == true)
        #expect(AppStorage(wrappedValue: 42, intKey).wrappedValue == 42)
        #expect(AppStorage(wrappedValue: 3.14, doubleKey).wrappedValue == 3.14)

        // Writing through one wrapper and reading from a fresh wrapper proves
        // the value persisted to UserDefaults rather than just to local state.
        let stringStorage = AppStorage(wrappedValue: "ignored", stringKey)
        stringStorage.wrappedValue = "written"
        #expect(AppStorage(wrappedValue: "fallback", stringKey).wrappedValue == "written")

        let boolStorage = AppStorage(wrappedValue: false, boolKey)
        boolStorage.wrappedValue = true
        #expect(AppStorage(wrappedValue: false, boolKey).wrappedValue == true)
        boolStorage.wrappedValue = false
        // After explicit false write, value reads back as false (not the
        // wrapped default). Tests the object-existence guard in the read path.
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == false)

        let intStorage = AppStorage(wrappedValue: 0, intKey)
        intStorage.wrappedValue = 7
        #expect(AppStorage(wrappedValue: 0, intKey).wrappedValue == 7)

        let doubleStorage = AppStorage(wrappedValue: 0.0, doubleKey)
        doubleStorage.wrappedValue = 2.5
        #expect(AppStorage(wrappedValue: 0.0, doubleKey).wrappedValue == 2.5)
    }

    @Test("AppStorage encodes RawRepresentable enums via their raw value")
    func appStorageEncodesRawRepresentableEnums() {
        let key = "quill.test.mode.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Default value when nothing is stored.
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)

        let storage = AppStorage(wrappedValue: AppStorageMode.classic, key)
        storage.wrappedValue = .modern
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .modern)
        // Underlying storage uses the rawValue, not Codable JSON.
        #expect(UserDefaults.standard.string(forKey: key) == "modern")

        // A garbage rawValue at the storage key falls back to the default.
        UserDefaults.standard.set("not-a-case", forKey: key)
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)
    }

    // MARK: - File importer

    @Test("QuillFileImporter honors test-injected selection and validates types")
    func quillFileImporterUsesTestSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillFileImporterTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pngURL = directory.appendingPathComponent("hello.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
            QuillFileImporter.setTestSelection(nil)
        }

        QuillFileImporter.setTestSelection(pngURL)

        // Happy path: PNG conforms to image / png.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.image]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }

        switch QuillFileImporter.selectURL(allowedContentTypes: [.png]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected png to match png allowedType: \(error)")
        }

        // Empty allowedContentTypes accepts any URL (matches SwiftUI behavior).
        switch QuillFileImporter.selectURL(allowedContentTypes: []) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected empty allowedTypes to accept any URL: \(error)")
        }

        // Mismatched type fails with the right error case.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.jpeg]) {
        case .success:
            Issue.record("Expected jpeg-only allowedTypes to reject a .png URL")
        case .failure(let error):
            guard let quillError = error as? QuillCompatibilityError else {
                Issue.record("Expected QuillCompatibilityError, got \(type(of: error)): \(error)")
                return
            }
            switch quillError {
            case .unsupportedFileSelection(let url, let allowed):
                #expect(url == pngURL)
                #expect(allowed == [.jpeg])
            default:
                Issue.record("Expected .unsupportedFileSelection, got \(quillError)")
            }
        }
    }

    // MARK: - UTType behavior

    @Test("UTType infers types from file extensions and reports conformance")
    func utTypeInfersAndConforms() {
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.png")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.PNG")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tiff")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tif")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/document.txt")) == .plainText)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/document.rtf")) == .rtf)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/feed.xml")) == .xml)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/clip.mp4")) == .mpeg4Movie)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/audio.mp3")) == .mp3)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/no-extension")) == nil)

        // Identity conformance.
        #expect(UTType.png.conforms(to: .png))
        #expect(UTType.jpeg.conforms(to: .jpeg))

        // Apple UTType conformance is transitive through content/data roots.
        #expect(UTType.png.conforms(to: .image))
        #expect(UTType.png.conforms(to: .data))
        #expect(UTType.png.conforms(to: .item))
        #expect(UTType.jpeg.conforms(to: .image))
        #expect(UTType.tiff.conforms(to: .image))
        #expect(UTType.utf8PlainText.conforms(to: .plainText))
        #expect(UTType.plainText.conforms(to: .text))
        #expect(UTType.html.conforms(to: .text))
        #expect(UTType.json.conforms(to: .data))
        #expect(UTType.fileURL.conforms(to: .url))
        #expect(UTType.url.conforms(to: .data))
        #expect(UTType.folder.conforms(to: .directory))
        #expect(UTType.folder.conforms(to: .item))
        #expect(UTType.directory.conforms(to: .data) == false)

        // A custom type does not inherit from image unless explicitly modeled.
        #expect(UTType("public.text")?.conforms(to: .image) == false)

        // Unrelated concrete types do not conform to each other.
        #expect(UTType.png.conforms(to: .jpeg) == false)
    }

    // MARK: - NSItemProvider data flow

    @Test("NSItemProvider delivers data and file representations matching content type")
    func nsItemProviderDeliversMatchingRepresentations() throws {
        let payload = Data([0xCA, 0xFE, 0xBA, 0xBE])

        // Data-backed provider, matching type.
        let dataProvider = NSItemProvider(data: payload, type: .png)
        let dataCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .png) { data, error in
            dataCaptured.value = (data, error)
        }
        #expect(dataCaptured.value?.0 == payload)
        #expect(dataCaptured.value?.1 == nil)

        // Data-backed provider, image supertype matches concrete png too.
        let imgCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .image) { data, error in
            imgCaptured.value = (data, error)
        }
        #expect(imgCaptured.value?.0 == payload)
        #expect(imgCaptured.value?.1 == nil)

        // Data-backed provider, mismatched type produces an error.
        let mismatchCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .jpeg) { data, error in
            mismatchCaptured.value = (data, error)
        }
        #expect(mismatchCaptured.value?.0 == nil)
        #expect((mismatchCaptured.value?.1 as? QuillCompatibilityError) == .representationUnavailable("public.jpeg"))

        // File-backed provider reads bytes from the URL.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillItemProviderTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("payload.png")
        try payload.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileProvider = NSItemProvider(fileURL: fileURL)
        let fileCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = fileProvider.loadDataRepresentation(for: .png) { data, error in
            fileCaptured.value = (data, error)
        }
        #expect(fileCaptured.value?.0 == payload)
        #expect(fileCaptured.value?.1 == nil)

        // Empty provider always errors.
        let empty = NSItemProvider()
        let emptyCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = empty.loadDataRepresentation(for: .png) { data, error in
            emptyCaptured.value = (data, error)
        }
        #expect(emptyCaptured.value?.0 == nil)
        #expect(emptyCaptured.value?.1 != nil)
    }

    // MARK: - OpenURLAction custom handler

    @Test("OpenURLAction routes URLs through the configured handler")
    func openURLActionInvokesCustomHandler() {
        let captured = QuillTestBox<URL>()
        let action = OpenURLAction { url in
            captured.value = url
            return true
        }

        let url = URL(string: "https://quill.test/path?q=1")!
        let result = action(url)
        #expect(result == true)
        #expect(captured.value == url)

        // Returning false from the handler propagates.
        let rejecting = OpenURLAction { _ in false }
        #expect(rejecting(URL(string: "https://example.com")!) == false)
    }

    // MARK: - QuillMenuAction divider + disabled semantics

    @Test("QuillMenuAction divider is a divider and disabled actions never run")
    func quillMenuActionDividerAndDisabled() {
        let divider = QuillMenuAction.divider()
        #expect(divider.kind == .divider)
        // Calling perform() on a divider must not crash; the synthesized
        // empty closure is a no-op. Idempotent.
        divider.perform()
        divider.perform()

        // Disabled action does not invoke its closure.
        let disabledRan = QuillTestBox<Bool>(false)
        let disabled = QuillMenuAction(
            title: "Disabled",
            isDisabled: true,
            action: { disabledRan.value = true }
        )
        disabled.perform()
        #expect(disabledRan.value == false)

        // Enabled action invokes its closure exactly once per perform().
        let enabledCount = QuillTestBox<Int>(0)
        let enabled = QuillMenuAction(title: "Enabled") {
            enabledCount.value = (enabledCount.value ?? 0) + 1
        }
        enabled.perform()
        enabled.perform()
        #expect(enabledCount.value == 2)

        // Unspecified id falls back to the title.
        #expect(enabled.id == "Enabled")
        let withCustomID = QuillMenuAction(id: "explicit", title: "Title") {}
        #expect(withCustomID.id == "explicit")
    }

    // MARK: - Gradient.quillAverageColor

    @Test("Gradient.quillAverageColor averages stops by RGBA component")
    func gradientAverageColorAveragesStops() {
        // Two-stop gradient: red (1,0,0,1) and blue (0,0,1,1) averages to (0.5, 0, 0.5, 1).
        let twoStops = Gradient(colors: [
            Color(red: 1.0, green: 0.0, blue: 0.0, opacity: 1.0),
            Color(red: 0.0, green: 0.0, blue: 1.0, opacity: 1.0)
        ])
        let avg = twoStops.quillAverageColor
        #expect(abs(avg.red - 0.5) < 0.001, "expected red ~= 0.5, got \(avg.red)")
        #expect(abs(avg.green - 0.0) < 0.001, "expected green ~= 0.0, got \(avg.green)")
        #expect(abs(avg.blue - 0.5) < 0.001, "expected blue ~= 0.5, got \(avg.blue)")
        #expect(abs(avg.alpha - 1.0) < 0.001, "expected alpha ~= 1.0, got \(avg.alpha)")

        // Three identical stops average to that color (sanity check on the
        // reduce path; divisor must be count, not count - 1).
        let solid = Gradient(colors: [
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5),
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5),
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5)
        ])
        let solidAvg = solid.quillAverageColor
        #expect(abs(solidAvg.red - 0.4) < 0.001)
        #expect(abs(solidAvg.green - 0.6) < 0.001)
        #expect(abs(solidAvg.blue - 0.8) < 0.001)
        #expect(abs(solidAvg.alpha - 0.5) < 0.001)

        // Empty gradient returns .primary instead of dividing by zero.
        // We can't compare Color values directly across the SwiftOpenUI shim,
        // but accessing the property must not crash.
        _ = Gradient(colors: []).quillAverageColor
    }

    // MARK: - PresentationMode.dismiss

    @Test("PresentationMode invokes its dismiss closure")
    func presentationModeInvokesDismissClosure() {
        let invoked = QuillTestBox<Int>(0)
        let mode = PresentationMode(dismiss: {
            invoked.value = (invoked.value ?? 0) + 1
        })

        // The exposed `wrappedValue` returns self, so wrappedValue.dismiss()
        // hits the same action; both call paths must work.
        mode.dismiss()
        mode.wrappedValue.dismiss()
        #expect(invoked.value == 2)

        // Default initializer is a no-op closure that doesn't crash.
        PresentationMode().dismiss()
    }

    // MARK: - QuillCompatibilityError.errorDescription

    @Test("QuillCompatibilityError formats LocalizedError descriptions")
    func quillCompatibilityErrorDescriptions() {
        let unavailable = QuillCompatibilityError.representationUnavailable("public.png")
        #expect(unavailable.errorDescription == "No data representation is available for public.png.")

        let noProvider = QuillCompatibilityError.fileSelectionUnavailable
        #expect(noProvider.errorDescription == "No file selection provider is available.")

        let url = URL(fileURLWithPath: "/tmp/photo.txt")
        let unsupported = QuillCompatibilityError.unsupportedFileSelection(url, [.png, .jpeg])
        #expect(
            unsupported.errorDescription
                == "/tmp/photo.txt is not one of the allowed file types: public.png, public.jpeg.",
            "Got unexpected description: \(unsupported.errorDescription ?? "nil")"
        )

        // Empty allowedTypes still formats cleanly (joined separator collapses).
        let emptyAllowed = QuillCompatibilityError.unsupportedFileSelection(url, [])
        #expect(
            emptyAllowed.errorDescription
                == "/tmp/photo.txt is not one of the allowed file types: ."
        )
    }

    // MARK: - FocusState init paths

    @Test("FocusState exposes correct defaults across its three init paths")
    func focusStateInitPaths() {
        // Bool-defaulted init starts at false.
        let boolFocus = FocusState<Bool>()
        #expect(boolFocus.wrappedValue == false)

        // Optional<Wrapped> init starts at nil.
        let optionalFocus = FocusState<String?>()
        #expect(optionalFocus.wrappedValue == nil)

        // wrappedValue init starts at the provided Bool value.
        let provided = FocusState<Bool>(wrappedValue: true)
        #expect(provided.wrappedValue)

        // Mutating wrappedValue persists (FocusState boxes its storage so
        // nonmutating set works on a let-bound copy, just like SwiftUI).
        provided.wrappedValue = false
        #expect(!provided.wrappedValue)

        // Binding produced via projectedValue can read AND write.
        let binding = provided.projectedValue
        #expect(!binding.wrappedValue)
        binding.wrappedValue = true
        #expect(provided.wrappedValue)

        let optionalProvided = FocusState<String?>(wrappedValue: "message")
        #expect(optionalProvided.wrappedValue == "message")
    }

    // MARK: - Namespace identity

    @Test("Namespace generates unique IDs across instances and is Hashable")
    func namespaceGeneratesUniqueIdentities() {
        let first = Namespace()
        let second = Namespace()
        #expect(first.wrappedValue != second.wrappedValue)

        // Same Namespace returns the same ID across reads.
        let stored = first.wrappedValue
        #expect(first.wrappedValue == stored)

        // IDs are usable as Set / Dictionary keys.
        let ids: Set<Namespace.ID> = [
            first.wrappedValue,
            second.wrappedValue,
            first.wrappedValue
        ]
        #expect(ids.count == 2)
    }

    // MARK: - QuillSidebarNavigationAction.perform

    @Test("QuillSidebarNavigationAction perform invokes its action and id falls back to title")
    func quillSidebarNavigationActionPerformsAction() {
        let count = QuillTestBox<Int>(0)
        let action = QuillSidebarNavigationAction(
            title: "Settings",
            systemImage: "gear",
            action: { count.value = (count.value ?? 0) + 1 }
        )

        action.perform()
        action.perform()
        action.perform()
        #expect(count.value == 3)

        // id falls back to title when not provided.
        #expect(action.id == "Settings")

        // Explicit id wins over title.
        let custom = QuillSidebarNavigationAction(
            id: "settings.id",
            title: "Settings",
            systemImage: "gear",
            action: {}
        )
        #expect(custom.id == "settings.id")
    }

    // MARK: - QuillPrompt identity

    @Test("QuillPrompt id falls back to title and supports Hashable identity")
    func quillPromptIdentityFallsBackToTitle() {
        let untagged = QuillPrompt(title: "Summarize", systemImage: "doc.text")
        #expect(untagged.id == "Summarize")

        let tagged = QuillPrompt(id: "prompt.summarize.v2", title: "Summarize", systemImage: "doc.text")
        #expect(tagged.id == "prompt.summarize.v2")

        // Different titles with the same explicit id collapse via Hashable when
        // both id and title differ; Hashable is the full struct, not just id.
        let alpha = QuillPrompt(id: "x", title: "A", systemImage: "1.circle")
        let beta = QuillPrompt(id: "x", title: "A", systemImage: "1.circle")
        let gamma = QuillPrompt(id: "x", title: "B", systemImage: "1.circle")
        #expect(alpha == beta)
        #expect(alpha != gamma)

        let set: Set<QuillPrompt> = [alpha, beta, gamma]
        #expect(set.count == 2)
    }

    // MARK: - AnyTransition combinators

    @Test("AnyTransition combinators do not crash and return AnyTransition values")
    func anyTransitionCombinatorsAreSafe() {
        // Static factories.
        #expect(String(describing: AnyTransition.opacity).contains("opacity"))
        #expect(String(describing: AnyTransition.slide).contains("slide"))
        #expect(String(describing: AnyTransition.scale()).contains("scale"))
        #expect(String(describing: AnyTransition.scale(scale: 0.5, anchor: .center)).contains("0.5"))
        #expect(String(describing: AnyTransition.asymmetric(insertion: .opacity, removal: .slide)).contains("asymmetric"))

        // Init-from-self preserves the value.
        let copy = AnyTransition(.opacity)
        #expect(String(describing: copy).contains("opacity"))

        let combined = AnyTransition.opacity.combined(with: .slide)
        #expect(String(describing: combined).contains("combined"))
        #expect(String(describing: combined).contains("opacity"))
        #expect(String(describing: combined).contains("slide"))
    }

    // MARK: - QuillCompatibilityEvent equality

    // MARK: - SPI: view-tree introspection helpers

    @Test("quillTextLabel extracts text content from primitive view types")
    func quillTextLabelExtractsFromPrimitives() {
        // Text: returns its content directly.
        #expect(QuillUI.quillTextLabel(from: Text("Hello")) == "Hello")
        #expect(QuillUI.quillTextLabel(from: Text("")) == "")

        // Label: returns its title (the system-image side is ignored here).
        #expect(QuillUI.quillTextLabel(from: Label("Settings", systemImage: "gear")) == "Settings")

        // Image: bridges through quillSystemImageName and returns the symbol token.
        #expect(QuillUI.quillTextLabel(from: Image(systemName: "paperplane.fill")) == "paperplane.fill")

        // Unknown view type returns an empty string fallback (used so callers can detect
        // "no extractable label" without crashing on opaque view types).
        struct Unknown: View {
            var body: some View { Text("nope") }
        }
        #expect(QuillUI.quillTextLabel(from: Unknown()) == "")
    }

    @Test("quillSystemImageName preserves backend-covered SF Symbols and falls back gracefully")
    func quillSystemImageNameRemapsAndFallsBack() {
        // Backend-covered SF Symbols preserve the macOS token.
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "paperplane.fill")) == "paperplane.fill")
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "photo.fill")) == "photo.fill")
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "lightbulb.circle")) == "lightbulb.circle")

        // Unknown SF Symbol passes through unchanged.
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "custom.symbol.name")) == "custom.symbol.name")

        // Non-Image view returns a "circle" sentinel so the GTK-side has a real symbol
        // to render even if the caller passed something inappropriate.
        #expect(QuillUI.quillSystemImageName(from: Text("not-an-image")) == "circle")
    }

    @Test("quillTextLabel unwraps styled labels")
    func quillTextLabelUnwrapsStyledLabels() {
        let styledLabel = Text("Styled")
            .font(.body)
            .foregroundColor(.primary)
            .lineLimit(1)
            .bold()
            .help("Tooltip")
        #expect(QuillUI.quillTextLabel(from: styledLabel) == "Styled")

        #expect(QuillUI.quillTextLabel(from: Text("Visible").accessibilityLabel("Accessible")) == "Visible")
        #expect(QuillUI.quillTextLabel(from: EmptyView().accessibilityLabel("Fallback")) == "Fallback")
    }

    @Test("quillMenuElements walks Button, Disabled, KeyboardShortcut, and recurses MultiChildView")
    func quillMenuElementsWalksViewTree() {
        // Plain Button returns a single .item with the button's title and action.
        let buttonTapCount = QuillTestBox<Int>(0)
        let plainButton = Button("Save") {
            buttonTapCount.value = (buttonTapCount.value ?? 0) + 1
        }
        let plainElements = QuillUI.quillMenuElements(from: plainButton)
        #expect(plainElements.count == 1)
        if case .item(let label, let action) = plainElements.first {
            #expect(label == "Save")
            action()
            #expect(buttonTapCount.value == 1)
        } else {
            Issue.record("Expected .item, got \(String(describing: plainElements.first))")
        }

        // DisabledView wrapping a button replaces the action with a no-op
        // closure so calling it does nothing.
        let disabledTapCount = QuillTestBox<Int>(0)
        let disabledButton = Button("Delete") {
            disabledTapCount.value = (disabledTapCount.value ?? 0) + 1
        }.disabled(true)
        let disabledElements = QuillUI.quillMenuElements(from: disabledButton)
        #expect(disabledElements.count == 1)
        if case .item(let label, let action) = disabledElements.first {
            #expect(label == "Delete")
            action()
            // Disabled actions are replaced with empty closures, so the count
            // must stay at zero.
            #expect(disabledTapCount.value == 0)
        } else {
            Issue.record("Expected disabled .item, got \(String(describing: disabledElements.first))")
        }

        let chainedDisabledTapCount = QuillTestBox<Int>(0)
        let disabledThenShortcut = Button("Archive") {
            chainedDisabledTapCount.value = (chainedDisabledTapCount.value ?? 0) + 1
        }
        .disabled(true)
        .keyboardShortcut("a", modifiers: .command)
        let chainedDisabledElements = QuillUI.quillMenuElements(from: disabledThenShortcut)
        #expect(chainedDisabledElements.count == 1)
        if case .item(let label, let action) = chainedDisabledElements.first {
            #expect(label == "Archive")
            action()
            #expect(chainedDisabledTapCount.value == 0)
        } else {
            Issue.record("Expected chained disabled .item, got \(String(describing: chainedDisabledElements.first))")
        }

        let shortcutThenDisabled = Button("Export") {
            chainedDisabledTapCount.value = (chainedDisabledTapCount.value ?? 0) + 1
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(true)
        let shortcutThenDisabledElements = QuillUI.quillMenuElements(from: shortcutThenDisabled)
        #expect(shortcutThenDisabledElements.count == 1)
        if case .item(let label, let action) = shortcutThenDisabledElements.first {
            #expect(label == "Export")
            action()
            #expect(chainedDisabledTapCount.value == 0)
        } else {
            Issue.record("Expected shortcut then disabled .item, got \(String(describing: shortcutThenDisabledElements.first))")
        }

        let styledTapCount = QuillTestBox<Int>(0)
        let styledButton = Button(action: {
            styledTapCount.value = (styledTapCount.value ?? 0) + 1
        }) {
            Text("Rename")
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .help("Rename item")
        let styledElements = QuillUI.quillMenuElements(from: styledButton)
        #expect(styledElements.count == 1)
        if case .item(let label, let action) = styledElements.first {
            #expect(label == "Rename")
            action()
            #expect(styledTapCount.value == 1)
        } else {
            Issue.record("Expected styled .item, got \(String(describing: styledElements.first))")
        }

        // Unknown view type returns []
        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillMenuElements(from: Unknown()).isEmpty)
    }

    @Test("confirmationDialog compatibility preserves buttons and message text")
    func confirmationDialogCompatibilityPreservesButtonsAndMessage() {
        let deleteTapCount = QuillTestBox<Int>(0)
        let cancelTapCount = QuillTestBox<Int>(0)
        let dialog = Text("Row").confirmationDialog("Delete?", isPresented: .constant(true)) {
            Button("Delete") {
                deleteTapCount.value = (deleteTapCount.value ?? 0) + 1
            }
            Button("Cancel", role: .cancel) {
                cancelTapCount.value = (cancelTapCount.value ?? 0) + 1
            }
        } message: {
            Text("Delete this completion?")
        }

        #expect(dialog.title == "Delete?")
        #expect(dialog.message == "Delete this completion?")
        #expect(dialog.buttons.count == 2)
        #expect(dialog.buttons.map(\.label) == ["Delete", "Cancel"])
        guard dialog.buttons.count == 2 else {
            return
        }

        dialog.buttons[0].action()
        dialog.buttons[1].action()

        #expect(deleteTapCount.value == 1)
        #expect(cancelTapCount.value == 1)
    }

    @Test("quillCommandMenuItems extracts from Button and respects disabled state")
    func quillCommandMenuItemsExtraction() {
        let count = QuillTestBox<Int>(0)
        let button = Button("Open") {
            count.value = (count.value ?? 0) + 1
        }

        let items = QuillUI.quillCommandMenuItems(from: button)
        #expect(items.count == 1)
        #expect(items.first?.label == "Open")

        // Verify the action is the button's action (calls increment counter).
        items.first?.action()
        #expect(count.value == 1)

        let disabledShortcut = Button("Archive") {
            count.value = (count.value ?? 0) + 1
        }
        .disabled(true)
        .keyboardShortcut("a", modifiers: .command)
        let disabledShortcutItems = QuillUI.quillCommandMenuItems(from: disabledShortcut)
        #expect(disabledShortcutItems.count == 1)
        #expect(disabledShortcutItems.first?.label == "Archive")
        #expect(disabledShortcutItems.first?.isDisabled == true)
        #expect(disabledShortcutItems.first?.shortcut == KeyboardShortcut("a", modifiers: .command))

        let shortcutDisabled = Button("Export") {
            count.value = (count.value ?? 0) + 1
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(true)
        let shortcutDisabledItems = QuillUI.quillCommandMenuItems(from: shortcutDisabled)
        #expect(shortcutDisabledItems.count == 1)
        #expect(shortcutDisabledItems.first?.label == "Export")
        #expect(shortcutDisabledItems.first?.isDisabled == true)
        #expect(shortcutDisabledItems.first?.shortcut == KeyboardShortcut("e", modifiers: .command))

        let nestedDisabled = Button("Pinned") {
            count.value = (count.value ?? 0) + 1
        }
        .disabled(true)
        .disabled(false)
        let nestedDisabledItems = QuillUI.quillCommandMenuItems(from: nestedDisabled)
        #expect(nestedDisabledItems.count == 1)
        #expect(nestedDisabledItems.first?.label == "Pinned")
        #expect(nestedDisabledItems.first?.isDisabled == true)

        let styledCommand = Button("Sync") {
            count.value = (count.value ?? 0) + 1
        }
        .font(.body)
        .foregroundColor(.primary)
        .help("Sync now")
        let styledCommandItems = QuillUI.quillCommandMenuItems(from: styledCommand)
        #expect(styledCommandItems.count == 1)
        #expect(styledCommandItems.first?.label == "Sync")

        // Unknown view returns empty.
        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillCommandMenuItems(from: Unknown()).isEmpty)
    }

    @Test("quillPickerOptions extracts labels and tags from tagged view content")
    func quillPickerOptionsExtraction() {
        let options = QuillUI.quillPickerOptions(from: HStack {
            Text("").tag("a")
            Image(systemName: "photo.fill").tag("b")
        })

        #expect(options.count == 2)
        #expect(options[0].label == "a")
        #expect(options[0].tag == AnyHashable("a"))
        #expect(options[1].label == "photo.fill")
        #expect(options[1].tag == AnyHashable("b"))

        let styledOptions = QuillUI.quillPickerOptions(from: HStack {
            Text("Compact")
                .font(.body)
                .tag("compact")
            Text("Detailed")
                .tag("detailed")
                .foregroundColor(.primary)
        })
        #expect(styledOptions.count == 2)
        #expect(styledOptions[0].label == "Compact")
        #expect(styledOptions[0].tag == AnyHashable("compact"))
        #expect(styledOptions[1].label == "Detailed")
        #expect(styledOptions[1].tag == AnyHashable("detailed"))

        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillPickerOptions(from: Unknown()).isEmpty)
    }

    // MARK: - NSImage.tiffRepresentation parity

    @Test("QuillImageFormatDetector identifies the common container formats")
    func quillImageFormatDetectorIdentifiesContainers() {
        // TIFF little-endian and big-endian magic.
        #expect(QuillImageFormatDetector.detect(Data([0x49, 0x49, 0x2A, 0x00])) == .tiff)
        #expect(QuillImageFormatDetector.detect(Data([0x4D, 0x4D, 0x00, 0x2A, 0xAA])) == .tiff)

        // PNG magic.
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        #expect(QuillImageFormatDetector.detect(pngMagic) == .png)

        // JPEG magic (SOI + APP0/APP1 marker).
        #expect(QuillImageFormatDetector.detect(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(QuillImageFormatDetector.detect(Data([0xFF, 0xD8, 0xFF, 0xE1])) == .jpeg)

        // GIF87a / GIF89a.
        #expect(QuillImageFormatDetector.detect(Data("GIF87a".utf8)) == .gif)
        #expect(QuillImageFormatDetector.detect(Data("GIF89a".utf8)) == .gif)

        // BMP.
        #expect(QuillImageFormatDetector.detect(Data([0x42, 0x4D, 0x00])) == .bmp)

        // WebP container needs both RIFF and WEBP markers.
        let webp: [UInt8] = [
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x00, 0x00, 0x00, 0x00,  // size (any)
            0x57, 0x45, 0x42, 0x50   // "WEBP"
        ]
        #expect(QuillImageFormatDetector.detect(Data(webp)) == .webp)

        // Unknown / too short.
        #expect(QuillImageFormatDetector.detect(Data([0xDE, 0xAD, 0xBE, 0xEF])) == .unknown)
        #expect(QuillImageFormatDetector.detect(Data()) == .unknown)
        #expect(QuillImageFormatDetector.detect(Data([0xFF])) == .unknown)
    }

    @Test("NSImage.tiffRepresentation: TIFF input passes through unchanged on Linux")
    func nsImageTiffPassthroughIsDeterministic() {
        // A minimal little-endian TIFF header. Apple promises valid TIFF bytes
        // out for valid TIFF input, but not byte-for-byte equality. Linux keeps
        // this deterministic and returns source TIFF bytes unchanged.
        let tiffBytes = Data([0x49, 0x49, 0x2A, 0x00] + Array(repeating: 0xAA, count: 32))
        let img = NSImage(data: tiffBytes)
        #expect(img?.tiffRepresentation == tiffBytes)

        // Big-endian TIFF magic also passes through.
        let bigEndianTIFF = Data([0x4D, 0x4D, 0x00, 0x2A] + Array(repeating: 0xBB, count: 32))
        let img2 = NSImage(data: bigEndianTIFF)
        #expect(img2?.tiffRepresentation == bigEndianTIFF)
    }

    @Test("NSImage.tiffRepresentation: corrupt input returns nil and records a warning")
    func nsImageTiffCorruptInputReturnsNil() {
        QuillCompatibilityDiagnostics.shared.clear()

        // Corrupt PNG-like input should NOT come back labeled as TIFF.
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x00, count: 16))
        let pngImage = NSImage(data: pngBytes)
        #expect(pngImage?.tiffRepresentation == nil)

        // Corrupt JPEG-like input returns nil.
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 16))
        let jpegImage = NSImage(data: jpegBytes)
        #expect(jpegImage?.tiffRepresentation == nil)

        // Unknown bytes return nil with a separate diagnostic message.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
        let garbageImage = NSImage(data: garbage)
        #expect(garbageImage?.tiffRepresentation == nil)

        // All three calls recorded warnings (severity .warning, not .info).
        let warnings = QuillCompatibilityDiagnostics.shared.events
            .filter { $0.operation == "NSImage.tiffRepresentation" && $0.severity == .warning }
        #expect(warnings.count >= 3, "Expected at least 3 NSImage.tiffRepresentation warnings; got \(warnings.count)")
    }

    @Test("NSImage without bytes returns nil for TIFF")
    func nsImageWithoutBytesReturnsNilTIFF() {
        // The convenience init that takes only a size leaves data == nil.
        let blank = NSImage(size: CGSize(width: 64, height: 64))
        #expect(blank.tiffRepresentation == nil)
    }

    @Test("NSImage.tiffRepresentation transcodes a valid PNG to real TIFF via gdk-pixbuf")
    func nsImageTiffPNGToTIFFTranscodes() {
        // 67-byte 1x1 grayscale PNG. Same fixture as the cross-platform parity
        // test in QuillParityTests. Passing here proves the gdk-pixbuf bridge
        // produces TIFF output that's symmetric with what real Apple AppKit
        // produces on macOS.
        guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==") else {
            Issue.record("Failed to decode reference PNG fixture")
            return
        }

        guard let img = NSImage(data: png) else {
            Issue.record("NSImage(data:) failed to construct from valid PNG fixture")
            return
        }

        guard let tiff = img.tiffRepresentation else {
            Issue.record("Linux NSImage.tiffRepresentation returned nil for valid PNG; the gdk-pixbuf bridge should transcode it")
            return
        }

        #expect(tiff.count > 0, "TIFF output must not be empty")

        // Verify TIFF magic bytes (II*\0 little-endian or MM\0* big-endian).
        if tiff.count >= 4 {
            let prefix = Array(tiff.prefix(4))
            let isLittle = prefix == [0x49, 0x49, 0x2A, 0x00]
            let isBig = prefix == [0x4D, 0x4D, 0x00, 0x2A]
            #expect(isLittle || isBig, "Output must start with TIFF magic; got \(prefix)")
        }

        // Calling tiffRepresentation again must produce the same result (no
        // hidden mutation in the getter).
        let secondCall = img.tiffRepresentation
        #expect(secondCall == tiff, "tiffRepresentation must be deterministic for the same instance")
    }

    @Test("quillRenderSolidColorImage produces a real PNG of the requested size and color")
    func quillRenderSolidColorImageContract() {
        // Zero-size dimensions reject early.
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: 0, height: 16) == nil)
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: 16, height: 0) == nil)
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: -1, height: 16) == nil)

        // Valid red 4×4 PNG.
        guard let png = quillRenderSolidColorImage(
            red: 1, green: 0, blue: 0, alpha: 1,
            width: 4, height: 4,
            format: .png
        ) else {
            Issue.record("Expected non-nil PNG for valid solid-color render")
            return
        }
        // PNG magic prefix: \x89 P N G \r \n \x1a \n (8 bytes).
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(png.prefix(8)) == pngMagic, "Output must have PNG magic; got \(Array(png.prefix(8)))")

        // PNG IHDR chunk follows the magic and encodes width/height as
        // big-endian Int32 at byte offsets 16..19 and 20..23.
        if png.count >= 24 {
            let bytes = Array(png)
            let width = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16)
                      | (UInt32(bytes[18]) << 8)  |  UInt32(bytes[19])
            let height = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16)
                       | (UInt32(bytes[22]) << 8)  |  UInt32(bytes[23])
            #expect(width == 4, "PNG IHDR width should be 4; got \(width)")
            #expect(height == 4, "PNG IHDR height should be 4; got \(height)")
        }

        // Same call as TIFF — verify the format option actually switches
        // encoders (TIFF magic instead of PNG magic).
        guard let tiff = quillRenderSolidColorImage(
            red: 0, green: 1, blue: 0, alpha: 1,
            width: 8, height: 8,
            format: .tiff
        ) else {
            Issue.record("Expected non-nil TIFF for valid solid-color render")
            return
        }
        let tiffPrefix = Array(tiff.prefix(4))
        let isLittle = tiffPrefix == [0x49, 0x49, 0x2A, 0x00]
        let isBig    = tiffPrefix == [0x4D, 0x4D, 0x00, 0x2A]
        #expect(isLittle || isBig, "TIFF output must have TIFF magic; got \(tiffPrefix)")
    }

    @Test("PlatformImage scales and compresses valid image bytes through gdk-pixbuf")
    func platformImageTransformsValidImageData() {
        QuillCompatibilityDiagnostics.shared.clear()

        guard let png = quillRenderSolidColorImage(
            red: 1, green: 0, blue: 0, alpha: 1,
            width: 4, height: 2,
            format: .png
        ) else {
            Issue.record("Expected non-nil PNG for valid solid-color render")
            return
        }

        let image = PlatformImage(data: png)
        let resized = image.aspectFittedToHeight(6)
        guard let resizedData = resized.data else {
            Issue.record("Expected resized PlatformImage to retain PNG data")
            return
        }

        guard let dimensions = pngDimensions(resizedData) else {
            Issue.record("Expected resized image to be a valid PNG")
            return
        }
        #expect(dimensions.width == 12, "Aspect-fit width should scale from 4x2 to 12x6; got \(dimensions.width)x\(dimensions.height)")
        #expect(dimensions.height == 6, "Aspect-fit height should be 6; got \(dimensions.width)x\(dimensions.height)")

        guard let jpeg = image.compressImageData() else {
            Issue.record("Expected JPEG output for valid PNG input")
            return
        }
        #expect(Array(jpeg.prefix(3)) == [0xFF, 0xD8, 0xFF], "Compressed output must have JPEG magic; got \(Array(jpeg.prefix(3)))")

        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            ($0.operation == "PlatformImage.aspectFittedToHeight" || $0.operation == "PlatformImage.compressImageData")
                && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Valid image transforms should not record fallback warnings; got \(warnings.map(\.message))")
    }

    @Test("ImageRenderer rasterizes Color content to PNG bytes via gdk-pixbuf")
    func imageRendererRendersColorContent() {
        QuillCompatibilityDiagnostics.shared.clear()

        // Color is one of the few content types we currently support without
        // a full SwiftUI render pipeline; ImageRenderer should produce a real
        // PlatformImage with PNG bytes for it.
        let renderer = ImageRenderer(content: Color(red: 0.2, green: 0.4, blue: 0.6, opacity: 1.0))

        guard let image = renderer.nsImage else {
            Issue.record("Expected nsImage for Color content; got nil")
            return
        }
        guard let pngData = image.data else {
            Issue.record("PlatformImage produced by ImageRenderer must carry data")
            return
        }
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagic)

        // uiImage path returns the same shape (just a different ObjC accessor
        // name on Apple). Both paths share the underlying renderer.
        guard let uiImage = renderer.uiImage else {
            Issue.record("Expected uiImage for Color content; got nil")
            return
        }
        #expect(uiImage.data?.prefix(8) == Data(pngMagic))

        // No warnings should be recorded for the Color path — it's the
        // supported subset.
        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Color rendering should not record warnings; got \(warnings.map(\.message))")
    }

    @Test(
        "ImageRenderer offscreen pipeline produces real PNG bytes when explicitly enabled",
        .disabled(if: ProcessInfo.processInfo.environment["QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER"] != "1",
                  "Set QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1 (with xvfb / Wayland and GSK_RENDERER=cairo) to exercise the offscreen pipeline.")
    )
    func imageRendererOffscreenPipelineProducesRealPNG() throws {
        QuillCompatibilityDiagnostics.shared.clear()

        // Drive the full pipeline: gtkRenderView -> offscreen GtkWindow +
        // layout -> gtk_widget_snapshot -> gsk_render_node_draw -> cairo
        // image surface -> copied GdkPixbuf pixels -> gdk_pixbuf_save_to_bufferv.
        let renderer = ImageRenderer(content: Text("hello world"))
        guard let image = renderer.nsImage, let pngData = image.data else {
            let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
                $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
            }
            Issue.record("Offscreen pipeline returned nil with QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1; warnings: \(warnings.map(\.message))")
            return
        }

        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagic, "Expected PNG magic; got \(Array(pngData.prefix(8)))")
        #expect(pngData.count > 32, "PNG output suspiciously small: \(pngData.count) bytes")

        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Successful offscreen rendering should not record warnings; got \(warnings.map(\.message))")
    }

    @Test("ImageRenderer guards non-Color content behind the GTK offscreen pipeline")
    func imageRendererGuardsNonColorContentBehindGTKOptIn() {
        QuillCompatibilityDiagnostics.shared.clear()

        // Text content can take the experimental general path when
        // QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1:
        //   gtkRenderView → offscreen GtkWindow + size_allocate
        //   → gtk_widget_snapshot → gsk_render_node_draw
        //   → cairo_image_surface → copied GdkPixbuf pixels
        //   → gdk_pixbuf_save_to_bufferv
        // The default remains the safe nil+warning path because GTK can crash
        // if snapshotting starts outside a controlled display harness.
        let renderer = ImageRenderer(content: Text("hello world"))

        if let image = renderer.nsImage {
            // GTK initialized and the snapshot pipeline succeeded — verify
            // we got real PNG bytes back.
            let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            #expect(
                image.data?.prefix(8) == Data(pngMagic),
                "Expected PNG magic in offscreen-rendered image bytes; got \(image.data?.prefix(8) as Any)"
            )

            // Successful rendering should not record warnings.
            let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
                $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
            }
            #expect(warnings.isEmpty, "Successful rendering should not record warnings; got \(warnings.map(\.message))")
        } else {
            // The default path is gated off. Verify the warning surfaces the
            // content type so the developer knows what did not render.
            let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
                $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
            }
            #expect(!warnings.isEmpty, "Expected a warning when ImageRenderer returns nil")
            #expect(
                warnings.contains { $0.message.contains("Text") },
                "Expected the warning to name the content type 'Text'; got \(warnings.map(\.message))"
            )
        }
    }

    @Test("quillTranscodeImageDataToTIFF returns nil for empty / invalid input but TIFF for valid")
    func quillTranscodeImageDataToTIFFContract() {
        // Empty input returns nil.
        #expect(quillTranscodeImageDataToTIFF(Data()) == nil)

        // Garbage bytes return nil.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
        #expect(quillTranscodeImageDataToTIFF(garbage) == nil)

        // Truncated PNG (just the magic) returns nil.
        let truncated = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(quillTranscodeImageDataToTIFF(truncated) == nil)

        // Valid PNG returns non-nil TIFF with correct magic.
        guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==") else {
            Issue.record("Failed to decode reference PNG fixture")
            return
        }
        guard let tiff = quillTranscodeImageDataToTIFF(png) else {
            Issue.record("Bridge returned nil for valid PNG fixture")
            return
        }
        let prefix = Array(tiff.prefix(4))
        let isLittle = prefix == [0x49, 0x49, 0x2A, 0x00]
        let isBig = prefix == [0x4D, 0x4D, 0x00, 0x2A]
        #expect(isLittle || isBig, "Bridge output must have TIFF magic; got \(prefix)")
    }

    @Test("QuillCompatibilityEvent equality covers all fields")
    func quillCompatibilityEventEquatable() {
        let a = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "msg"
        )
        let b = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "msg"
        )
        let differentSeverity = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .warning,
            message: "msg"
        )
        let differentMessage = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "different"
        )

        #expect(a == b)
        #expect(a != differentSeverity)
        #expect(a != differentMessage)
    }
}

/// RawRepresentable enum for AppStorage round-trip tests. Defined at file
/// scope so its `RawValue` (String) is stable across compilations.
private enum AppStorageMode: String {
    case classic
    case modern
}

/// Tiny mutable reference container for capturing values out of closures in
/// tests without fighting Swift Testing's capture-list rules.
private final class QuillTestBox<Value>: @unchecked Sendable {
    var value: Value?

    init(_ value: Value? = nil) {
        self.value = value
    }
}

private struct CompatibilityModel: PersistentModel, Codable, Equatable {
    var id: String = UUID().uuidString
}

private final class FakeOllamaTransport: OllamaKitTransport, @unchecked Sendable {
    struct CapturedRequest: Sendable {
        var path: String
        var authorization: String?
    }

    private let routes: [String: (status: Int, body: String)]
    private let lock = NSLock()
    private var capturedRequests: [CapturedRequest] = []
    private var capturedChatBody: String?

    init(routes: [String: (Int, String)]) {
        self.routes = routes.mapValues { (status: $0.0, body: $0.1) }
    }

    var requests: [CapturedRequest] {
        lock.withLock { capturedRequests }
    }

    var chatBody: String? {
        lock.withLock { capturedChatBody }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? "/"
        lock.withLock {
            capturedRequests.append(
                CapturedRequest(
                    path: path,
                    authorization: request.value(forHTTPHeaderField: "Authorization")
                )
            )
            if path == "/api/chat", let httpBody = request.httpBody {
                capturedChatBody = String(data: httpBody, encoding: .utf8)
            }
        }

        let route = routes[path] ?? (404, #"{"error":"missing"}"#)
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: route.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(route.body.utf8), response)
    }
}

private let markdownContractTheme = MarkdownUI.Theme()
    .text {
        FontSize(14)
    }
    .code {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.85))
        BackgroundColor(Color("bgCustom"))
    }
    .strong {
        FontWeight(.semibold)
    }
    .link {
        ForegroundColor(.blue)
    }
    .heading1 { configuration in
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .relativePadding(.bottom, length: .em(0.3))
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(2))
                }
            Divider().overlay(Color.gray)
        }
    }
    .paragraph { configuration in
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.25))
            .markdownMargin(top: 0, bottom: 16)
    }
    .blockquote { configuration in
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray)
                .relativeFrame(width: .em(0.2))
            configuration.label
                .markdownTextStyle { ForegroundColor(.secondary) }
                .relativePadding(.horizontal, length: .em(1))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .codeBlock { configuration in
        VStack(spacing: 0) {
            Text(configuration.language ?? "code")
                .font(.system(size: 13, design: .monospaced))
                .fontWeight(.semibold)
            configuration.label
                .relativeLineSpacing(.em(0.225))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
        }
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }
    .listItem { configuration in
        configuration.label.padding(.bottom, 10)
    }
    .taskListMarker { configuration in
        Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.gray, Color("bgCustom"))
            .imageScale(.small)
            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
    }
    .table { configuration in
        configuration.label
            .markdownTableBorderStyle(.init(color: .gray))
            .markdownTableBackgroundStyle(.alternatingRows(.white, Color("bgCustom")))
            .markdownMargin(top: 0, bottom: 16)
    }
    .tableCell { configuration in
        configuration.label
            .markdownTextStyle {
                if configuration.row == 0 {
                    FontWeight(.semibold)
                }
                BackgroundColor(nil)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .relativeLineSpacing(.em(0.25))
    }
    .thematicBreak {
        Divider()
            .relativeFrame(height: .em(0.25))
            .overlay(Color.gray)
            .markdownMargin(top: 24, bottom: 24)
    }

private struct ContractSplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlighter: SyntaxHighlighter<ContractTextOutputFormat>

    init(theme: Splash.Theme) {
        self.highlighter = SyntaxHighlighter(format: ContractTextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard language != nil else { return Text(content) }
        return highlighter.highlight(content)
    }
}

private struct ContractTextOutputFormat: OutputFormat {
    var theme: Splash.Theme

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        var theme: Splash.Theme
        var accumulatedText: [Text] = []

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let color = theme.tokenColors[type] ?? theme.plainTextColor
            accumulatedText.append(Text(token).foregroundColor(.init(color)))
        }

        mutating func addPlainText(_ text: String) {
            accumulatedText.append(Text(text).foregroundColor(.init(theme.plainTextColor)))
        }

        mutating func addWhitespace(_ whitespace: String) {
            accumulatedText.append(Text(whitespace))
        }

        func build() -> Text {
            accumulatedText.reduce(Text(""), +)
        }
    }
}

private enum CombineTestError: Error {
    case boom
}

private final class DemandRecordingSubscriber<Input, Failure: Error>: Subscriber {
    var subscription: Subscription?
    var values: [Input] = []
    var completions = 0

    func receive(subscription: Subscription) {
        self.subscription = subscription
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        values.append(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        completions += 1
    }
}
