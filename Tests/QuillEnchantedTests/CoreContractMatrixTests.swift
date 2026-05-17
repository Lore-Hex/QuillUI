import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Core compatibility contract matrix")
struct CoreContractMatrixTests {
    @Test("compacts titles without whitespace or newlines", arguments: titleInputs)
    func titleCompactionContracts(input: String) {
        let title = input.quillTitle(maxLength: 32)

        #expect(!title.isEmpty)
        #expect(!title.contains("\n"))
        #expect(!title.contains("\r"))
        #expect(title == title.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(title.count <= 32)
    }

    @Test("cleans inline markdown markers", arguments: inlineCases)
    func inlineMarkdownContracts(testCase: TextCase) {
        #expect(MarkdownParser.cleanInline(testCase.input) == testCase.expected)
    }

    @Test("parses first structural markdown block", arguments: blockCases)
    func structuralMarkdownContracts(testCase: BlockCase) {
        let block = MarkdownParser.parse(testCase.markdown).first

        #expect(block?.kind == testCase.kind)
        #expect(block?.text == testCase.text)
    }

    @Test("parses Ollama stream content chunks", arguments: streamContentCases)
    func ollamaContentContracts(testCase: TextCase) throws {
        #expect(try OllamaStreamParser.parseLine(testCase.input) == .content(testCase.expected))
    }

    @Test("formats byte counts", arguments: byteCountCases)
    func byteCountContracts(testCase: ByteCountCase) {
        #expect(PendingImageAttachment.formatByteCount(testCase.byteCount) == testCase.expected)
    }

    @Test("accepts supported image extensions with media types", arguments: imageExtensionCases)
    func imageExtensionContracts(testCase: ImageExtensionCase) throws {
        let url = try temporaryFile(name: "sample.\(testCase.fileExtension)", bytes: [0x01, 0x02, 0x03])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let attachment = try PendingImageAttachment(fileURL: url, id: testCase.fileExtension)

        #expect(attachment.mediaType == testCase.mediaType)
        #expect(attachment.byteCount == 3)
        #expect(attachment.filename == "sample.\(testCase.fileExtension)")
    }

    @Test("rejects unsupported image extensions", arguments: unsupportedImageExtensions)
    func unsupportedImageExtensionContracts(fileExtension: String) throws {
        let url = try temporaryFile(name: "sample.\(fileExtension)", bytes: [0x01])
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: ImageAttachmentError.unsupportedFileType("sample.\(fileExtension)")) {
            try PendingImageAttachment(fileURL: url)
        }
    }

    @Test("decodes prompt kind from legacy system image payloads")
    func promptKindBackfillContracts() throws {
        let legacyQuestion = Data(
            #"{"title":"How to center div in HTML?","systemImage":"questionmark.circle"}"#.utf8
        )
        let prompt = try JSONDecoder().decode(EnchantedPrompt.self, from: legacyQuestion)

        #expect(prompt.kind == .question)
        #expect(prompt.systemImage == "questionmark.circle")

        let encoded = try JSONEncoder().encode(prompt)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(encodedObject["kind"] as? String == "question")
        #expect(encodedObject["systemImage"] as? String == "questionmark.circle")
    }

    @Test("normalizes attachment paths", arguments: pathCases)
    func pathNormalizationContracts(testCase: PathCase) throws {
        let url = try #require(PendingImageAttachment.fileURL(from: testCase.rawPath))

        #expect(url.path.hasSuffix(testCase.expectedSuffix))
    }

    @Test("Enchanted icon contract mirrors macOS symbols through Qt")
    func enchantedIconContractsMirrorMacOSSymbolsThroughQt() throws {
        let root = try packageRoot()
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let macOSRootView = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedRootView.swift"),
            encoding: .utf8
        )
        let sharedPrompts = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/QuillEnchantedShared.swift"),
            encoding: .utf8
        )
        let nativeShim = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp"),
            encoding: .utf8
        )

        for needle in [
            "var icons: Icons",
            "struct Icons: Codable, Sendable",
            "static let shared = Icons(",
            "newConversation: EnchantedIcon.newConversation",
            "attach: EnchantedIcon.attach",
            "dropTarget: EnchantedIcon.dropTarget",
            "attachment: EnchantedIcon.attachment",
            "send: EnchantedIcon.send",
            "stop: EnchantedIcon.stop",
            "removeAttachment: EnchantedIcon.removeAttachment",
            "icons: .shared"
        ] {
            expectContains(runtime, needle)
        }

        for needle in [
            "public enum EnchantedIcon",
            "public static let newConversation = \"square.and.pencil\"",
            "public static let attach = \"folder.badge.plus\"",
            "public static let dropTarget = attach",
            "public static let attachment = \"folder\"",
            "public static let send = \"arrow.forward.circle.fill\"",
            "public static let stop = \"square.fill\"",
            "public static let removeAttachment = \"xmark.circle.fill\""
        ] {
            expectContains(sharedPrompts, needle)
        }

        for needle in [
            "Image(systemName: EnchantedIcon.newConversation)",
            "Image(systemName: EnchantedIcon.attach)",
            "Image(systemName: model.isLoading ? EnchantedIcon.stop : EnchantedIcon.send)",
            "Image(systemName: EnchantedIcon.dropTarget)",
            "Image(systemName: EnchantedIcon.attachment)",
            "Image(systemName: EnchantedIcon.removeAttachment)"
        ] {
            expectContains(macOSRootView, needle)
        }

        for needle in [
            "QString iconName(const QJsonObject &icons, const char *key, const QString &fallback)",
            "QIcon systemImageIcon(const QString &systemImage)",
            "QIcon newConversationButtonIcon(const QJsonObject &icons)",
            "QIcon attachButtonIcon(const QJsonObject &icons)",
            "QIcon dropTargetIcon(const QJsonObject &icons)",
            "QIcon attachmentChipIcon(const QJsonObject &icons)",
            "QIcon sendButtonIcon(const QJsonObject &icons, bool isLoading)",
            "QIcon removeAttachmentButtonIcon(const QJsonObject &icons)",
            "QJsonObject icons = objectValue(payload, \"icons\")",
            "icons = objectValue(payload, \"icons\")",
            "newConversationButton->setIcon(newConversationButtonIcon(icons))",
            "attachButton->setIcon(attachButtonIcon(icons))",
            "dropTargetIcon(icons),\n        QStringLiteral(\"dropTargetIcon\"),\n        style",
            "attachmentChipIcon(icons),\n                QStringLiteral(\"attachmentChipIcon\"),\n                style",
            "removeAttachmentButton->setIcon(removeAttachmentButtonIcon(icons))",
            "updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle)",
            "QStringLiteral(\"document-new-symbolic\")",
            "QStringLiteral(\"folder-new-symbolic\")",
            "QStringLiteral(\"folder-symbolic\")",
            "QStringLiteral(\"window-close-symbolic\")",
            "QStringLiteral(\"process-stop-symbolic\")",
            "QStringLiteral(\"go-next-symbolic\")",
            "QStyle::SP_FileIcon",
            "QStyle::SP_FileDialogNewFolder",
            "QStyle::SP_DirIcon",
            "QStyle::SP_DialogCloseButton",
            "QStyle::SP_MediaStop",
            "QStyle::SP_MediaPlay"
        ] {
            expectContains(nativeShim, needle)
        }

        for needle in [
            "QIcon newChatButtonIcon()",
            "QLabel *dropTargetIconLabel = new QLabel()",
            "dropTargetIcon().pixmap(dropTargetIconSize, dropTargetIconSize)",
            "new QPushButton(QStringLiteral(\"x\"))"
        ] {
            expectDoesNotContain(nativeShim, needle)
        }
    }

    @Test("Enchanted Qt native target stays isolated from GTK graph")
    func enchantedQtNativeTargetContracts() throws {
        let root = try packageRoot()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let qtMain = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQt/main.swift"),
            encoding: .utf8
        )
        let coreApp = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedApp.swift"),
            encoding: .utf8
        )
        let upstreamSlice = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedUpstreamSlice/main.swift"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let genericQtRuntime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillGenericQtNativeRuntime/QuillGenericQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let macOSRootView = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedRootView.swift"),
            encoding: .utf8
        )
        let macOSMarkdownRendering = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/MarkdownRendering.swift"),
            encoding: .utf8
        )
        let imageAttachmentSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/ImageAttachment.swift"),
            encoding: .utf8
        )
        let sharedPrompts = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/QuillEnchantedShared.swift"),
            encoding: .utf8
        )
        let sharedOllama = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/OllamaClient.swift"),
            encoding: .utf8
        )
        let header = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/include/CQuillQt6WidgetsShim.h"),
            encoding: .utf8
        )
        let nativeShim = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillEnchantedQt6Widgets.cpp"),
            encoding: .utf8
        )
        let genericQtHost = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillGenericQt6Widgets.cpp"),
            encoding: .utf8
        )
        let nativeSupport = try String(
            contentsOf: root.appendingPathComponent("Sources/CQuillQt6WidgetsShim/QuillQtWidgetsSupport.hpp"),
            encoding: .utf8
        )

        #expect(manifest.contains(".init(product: \"quill-enchanted\", target: \"QuillEnchanted\", qtPath: \"Sources/QuillEnchantedQt\", qtRuntime: .enchantedQtNative)"))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedQt\""))
        #expect(manifest.contains("QuillEnchantedQtNativeRuntime"))
        #expect(manifest.contains("nativeQt: [\"QuillEnchantedQtNativeRuntime\"]"))
        #expect(manifest.contains(".define(\"QUILLUI_ENCHANTED_QT_NATIVE_BACKEND\")"))
        #expect(manifest.contains("name: \"QuillEnchantedShared\""))
        #expect(manifest.contains("dependencies: [\"QuillEnchantedData\", \"QuillFoundation\"]"))
        #expect(manifest.contains("name: \"QuillEnchantedData\""))
        #expect(manifest.contains("dependencies: [\"QuillData\"]"))
        #expect(manifest.contains("path: \"Sources/QuillEnchantedData\""))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillEnchantedData\", \"QuillUI\", \"QuillFoundation\"]"))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(manifest.contains("name: \"QuillEnchantedQtNativeRuntime\""))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillEnchantedData\", \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(qtMain.contains("#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND"))
        #expect(qtMain.contains("QuillEnchantedQtNativeApp.run()"))
        #expect(qtMain.contains("QuillQtApp.run(QuillEnchantedQtApp.self)"))
        #expect(qtMain.contains("import QuillEnchantedShared"))
        #expect(qtMain.contains("width: Double(EnchantedVisualMetrics.defaultWindowWidth)"))
        #expect(qtMain.contains("height: Double(EnchantedVisualMetrics.defaultWindowHeight)"))
        #expect(coreApp.contains("width: Double(EnchantedVisualMetrics.defaultWindowWidth)"))
        #expect(coreApp.contains("height: Double(EnchantedVisualMetrics.defaultWindowHeight)"))
        #expect(upstreamSlice.contains("import QuillEnchantedShared"))
        #expect(upstreamSlice.contains("width: Double(EnchantedVisualMetrics.defaultWindowWidth)"))
        #expect(upstreamSlice.contains("height: Double(EnchantedVisualMetrics.defaultWindowHeight)"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.sidebarWidth"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.sidebarIdealWidth"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.sidebarMaxWidth"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.composerMinWidth"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.composerMaxWidth"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.composerPadding"))
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.messageMaxWidth"))
        #expect(upstreamSlice.contains("EnchantedPalette.canvasColor"))
        #expect(upstreamSlice.contains("EnchantedPalette.sidebarColor"))
        #expect(upstreamSlice.contains("EnchantedPalette.sidebarSelectedColor"))
        #expect(upstreamSlice.contains("EnchantedPalette.cardQuietColor"))
        #expect(upstreamSlice.contains("EnchantedPalette.destructiveColor"))
        #expect(!upstreamSlice.contains("Color(hex: \"#FBFBFD\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#F5F5F7\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#E8E8ED\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#F4F4F6\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#D8D8DE\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#1D1D1F\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#6E6E73\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#4285F4\")"))
        #expect(!upstreamSlice.contains("Color(hex: \"#B42318\")"))
        #expect(upstreamSlice.contains("EnchantedPromptCatalog.emptyConversationPrompts.map"))
        #expect(!upstreamSlice.contains("private let prompts = ["))
        #expect(upstreamSlice.contains("EnchantedCopy.attachmentDefaultPrompt"))
        #expect(runtime.contains("import QuillEnchantedData"))
        #expect(runtime.contains("import QuillEnchantedShared"))
        #expect(genericQtRuntime.contains("import QuillEnchantedShared"))
        #expect(genericQtRuntime.contains("minimumWidth: EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(genericQtRuntime.contains("minimumHeight: EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(genericQtRuntime.contains("defaultWidth: EnchantedVisualMetrics.defaultWindowWidth"))
        #expect(genericQtRuntime.contains("defaultHeight: EnchantedVisualMetrics.defaultWindowHeight"))
        #expect(genericQtRuntime.contains("sidebarWidth: EnchantedVisualMetrics.sidebarWidth"))
        #expect(genericQtRuntime.contains("detailWidth: EnchantedVisualMetrics.detailWidth"))
        #expect(genericQtRuntime.contains("rootFontSize: EnchantedTypography.rootFontSize"))
        #expect(genericQtRuntime.contains("appTitleFontSize: EnchantedTypography.appTitleFontSize"))
        #expect(genericQtRuntime.contains("appTitleFontWeight: EnchantedTypography.appTitleFontWeight"))
        #expect(genericQtRuntime.contains("captionFontSize: EnchantedTypography.captionFontSize"))
        #expect(genericQtRuntime.contains("sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize"))
        #expect(genericQtRuntime.contains("sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight"))
        #expect(genericQtRuntime.contains("currentTitleFontSize: EnchantedTypography.currentTitleFontSize"))
        #expect(genericQtRuntime.contains("currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight"))
        #expect(genericQtRuntime.contains("messageBodyFontSize: EnchantedTypography.messageBodyFontSize"))
        #expect(genericQtRuntime.contains("conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize"))
        #expect(genericQtRuntime.contains("conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight"))
        #expect(runtime.contains("EnchantedModelContext.default()"))
        #expect(runtime.contains("QuillEnchantedQtSnapshot.preview"))
        #expect(runtime.contains("QuillEnchantedQtSnapshot.persisted("))
        #expect(runtime.contains("quill_enchanted_qt_run_app_json"))
        #expect(runtime.contains("quill_enchanted_qt_perform_action_json"))
        #expect(runtime.contains("quill_enchanted_qt_free_string"))
        #expect(sharedPrompts.contains("public enum EnchantedCopy"))
        #expect(runtime.contains("windowTitle: EnchantedCopy.windowTitle"))
        #expect(runtime.contains("sidebarSubtitle: EnchantedCopy.sidebarSubtitle"))
        #expect(runtime.contains("noModelsTitle: EnchantedCopy.noModelsTitle"))
        #expect(runtime.contains("chooseLocalModelStatus: EnchantedCopy.chooseLocalModelStatus"))
        #expect(runtime.contains("usingModelStatusPrefix: EnchantedCopy.usingModelStatusPrefix"))
        #expect(runtime.contains("completionsPanelSubtitle: EnchantedCopy.completionsPanelSubtitle"))
        #expect(runtime.contains("shortcutsPanelSubtitle: EnchantedCopy.shortcutsPanelSubtitle"))
        #expect(runtime.contains("settingsPanelSubtitle: EnchantedCopy.settingsPanelSubtitle"))
        #expect(runtime.contains("newConversationButtonTitle: EnchantedCopy.newChatTitle"))
        #expect(!runtime.contains("newChatTitle: EnchantedCopy.newChatTitle"))
        #expect(runtime.contains("newConversationTitle: EnchantedCopy.newConversationTitle"))
        #expect(runtime.contains("noMessagesYet: EnchantedCopy.noMessagesYet"))
        #expect(runtime.contains("self.lastMessage = summary.lastMessage"))
        #expect(!runtime.contains("summary.lastMessage.isEmpty ? EnchantedCopy.noMessagesYet : summary.lastMessage"))
        #expect(runtime.contains("attachTitle: EnchantedCopy.attachTitle"))
        #expect(runtime.contains("clearAttachmentsTitle: EnchantedCopy.clearAttachmentsTitle"))
        #expect(runtime.contains("attachmentsClearedStatus: EnchantedCopy.attachmentsClearedStatus"))
        #expect(runtime.contains("attachmentRemovedEmptyStatus: EnchantedCopy.readyStatus"))
        #expect(runtime.contains("removeAttachmentTooltip: EnchantedCopy.removeAttachmentTooltip"))
        #expect(runtime.contains("imageReadyStatusSingular: EnchantedCopy.imageReadyStatusSingular"))
        #expect(runtime.contains("imageReadyStatusPluralUnit: EnchantedCopy.imageReadyStatusPluralUnit"))
        #expect(runtime.contains("attachmentsTitle: EnchantedCopy.attachmentsTitle"))
        #expect(runtime.contains("attachmentDefaultPrompt: EnchantedCopy.attachmentDefaultPrompt"))
        #expect(runtime.contains("attachmentDefaultPromptPlural: EnchantedCopy.attachmentDefaultPromptPlural"))
        #expect(runtime.contains("attachmentSummaryTitle: EnchantedCopy.attachmentSummaryTitle"))
        #expect(runtime.contains("sendTitle: EnchantedCopy.sendTitle"))
        #expect(runtime.contains("stopTitle: EnchantedCopy.stopTitle"))
        #expect(runtime.contains("stoppingStatus: EnchantedCopy.stoppingStatus"))
        #expect(runtime.contains("isLoading: false"))
        #expect(sharedPrompts.contains("public enum EnchantedPreviewFixture"))
        #expect(sharedPrompts.contains("public static let selectedModel = \"llama3.1:8b\""))
        #expect(sharedPrompts.contains("public static let selectedConversationID = \"daily-brief\""))
        #expect(sharedPrompts.contains("public static let launchConversationMessages"))
        #expect(sharedPrompts.contains("public static let attachmentConversationMessages"))
        #expect(runtime.contains("selectedModel: EnchantedPreviewFixture.selectedModel"))
        #expect(runtime.contains("selectedConversationID: EnchantedPreviewFixture.selectedConversationID"))
        #expect(runtime.contains("models: EnchantedPreviewFixture.models"))
        #expect(runtime.contains("emptyHistoryTitle: EnchantedCopy.emptyHistoryTitle"))
        #expect(runtime.contains("emptyHistorySubtitle: EnchantedCopy.emptyHistorySubtitle"))
        #expect(runtime.contains("emptyStateTitle: EnchantedCopy.emptyStateTitle"))
        #expect(runtime.contains("emptyStateSubtitle: EnchantedCopy.emptyStateSubtitle"))
        #expect(runtime.contains("userRoleLabel: EnchantedCopy.userRoleLabel"))
        #expect(runtime.contains("assistantRoleLabel: EnchantedCopy.assistantRoleLabel"))
        #expect(runtime.contains("systemRoleLabel: EnchantedCopy.systemRoleLabel"))
        #expect(runtime.contains("prompts: EnchantedPromptCatalog.emptyConversationPrompts.map(QuillEnchantedQtSnapshot.Prompt.init)"))
        #expect(runtime.contains("var messages: [Message]? = nil"))
        #expect(runtime.contains("conversations: EnchantedPreviewFixture.conversations.map { Conversation($0) }"))
        #expect(runtime.contains("messages: EnchantedPreviewFixture.messages.map { Message($0) }"))
        #expect(!runtime.contains("private static let launchConversationMessages"))
        #expect(!runtime.contains("messages: launchConversationMessages"))
        #expect(!runtime.contains("messages: attachmentConversationMessages"))
        #expect(runtime.contains("canvasColor: EnchantedPalette.canvasColor"))
        #expect(runtime.contains("warningColor: EnchantedPalette.warningColor"))
        #expect(runtime.contains("systemColor: EnchantedPalette.systemColor"))
        #expect(runtime.contains("quoteRuleColor: EnchantedPalette.quoteRuleColor"))
        #expect(runtime.contains("codeBlockColor: EnchantedPalette.codeBlockColor"))
        #expect(runtime.contains("dividerColor: EnchantedPalette.dividerColor"))
        #expect(runtime.contains("cardBorderColor: EnchantedPalette.cardBorderColor"))
        #expect(runtime.contains("messageBorderColor: EnchantedPalette.messageBorderColor"))
        #expect(runtime.contains("controlBorderColor: EnchantedPalette.controlBorderColor"))
        #expect(runtime.contains("dropTargetBorderColor: EnchantedPalette.dropTargetBorderColor"))
        #expect(runtime.contains("disabledButtonBackgroundColor: EnchantedPalette.disabledButtonBackgroundColor"))
        #expect(runtime.contains("disabledButtonForegroundColor: EnchantedPalette.disabledButtonForegroundColor"))
        #expect(runtime.contains("disabledTextColor: EnchantedPalette.disabledTextColor"))
        #expect(runtime.contains("minimumWidth: EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(runtime.contains("minimumHeight: EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(runtime.contains("defaultWidth: EnchantedVisualMetrics.defaultWindowWidth"))
        #expect(runtime.contains("defaultHeight: EnchantedVisualMetrics.defaultWindowHeight"))
        #expect(runtime.contains("rootFontSize: EnchantedTypography.rootFontSize"))
        #expect(runtime.contains("appTitleFontSize: EnchantedTypography.appTitleFontSize"))
        #expect(runtime.contains("appTitleFontWeight: EnchantedTypography.appTitleFontWeight"))
        #expect(runtime.contains("captionFontSize: EnchantedTypography.captionFontSize"))
        #expect(runtime.contains("sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize"))
        #expect(runtime.contains("sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight"))
        #expect(runtime.contains("currentTitleFontSize: EnchantedTypography.currentTitleFontSize"))
        #expect(runtime.contains("currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight"))
        #expect(runtime.contains("messageBodyFontSize: EnchantedTypography.messageBodyFontSize"))
        #expect(runtime.contains("markdownHeading1FontSize: EnchantedTypography.markdownHeading1FontSize"))
        #expect(runtime.contains("markdownHeading2FontSize: EnchantedTypography.markdownHeading2FontSize"))
        #expect(runtime.contains("markdownHeadingFontSize: EnchantedTypography.markdownHeadingFontSize"))
        #expect(runtime.contains("markdownHeadingFontWeight: EnchantedTypography.markdownHeadingFontWeight"))
        #expect(runtime.contains("markdownCodeLanguageFontSize: EnchantedTypography.markdownCodeLanguageFontSize"))
        #expect(runtime.contains("markdownCodeFontSize: EnchantedTypography.markdownCodeFontSize"))
        #expect(runtime.contains("attachmentNameFontSize: EnchantedTypography.attachmentNameFontSize"))
        #expect(runtime.contains("attachmentSizeFontSize: EnchantedTypography.attachmentSizeFontSize"))
        #expect(runtime.contains("conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize"))
        #expect(runtime.contains("conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight"))
        #expect(runtime.contains("conversationPreviewFontSize: EnchantedTypography.conversationPreviewFontSize"))
        #expect(runtime.contains("warningTextFontSize: EnchantedTypography.warningTextFontSize"))
        #expect(runtime.contains("chipRemoveButtonFontWeight: EnchantedTypography.chipRemoveButtonFontWeight"))
        #expect(runtime.contains("sidebarWidth: EnchantedVisualMetrics.sidebarWidth"))
        #expect(runtime.contains("sidebarPadding: EnchantedVisualMetrics.sidebarPadding"))
        #expect(runtime.contains("sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing"))
        #expect(runtime.contains("sidebarTitleSpacing: EnchantedVisualMetrics.sidebarTitleSpacing"))
        #expect(runtime.contains("sidebarControlGroupSpacing: EnchantedVisualMetrics.sidebarControlGroupSpacing"))
        #expect(runtime.contains("statusRowSpacing: EnchantedVisualMetrics.statusRowSpacing"))
        #expect(runtime.contains("statusTextWidth: EnchantedVisualMetrics.statusTextWidth"))
        #expect(runtime.contains("statusDotSize: EnchantedVisualMetrics.statusDotSize"))
        #expect(runtime.contains("statusDotRadius: EnchantedVisualMetrics.statusDotRadius"))
        #expect(runtime.contains("conversationListSpacing: EnchantedVisualMetrics.conversationListSpacing"))
        #expect(runtime.contains("conversationRowPadding: EnchantedVisualMetrics.conversationRowPadding"))
        #expect(runtime.contains("conversationRowSpacing: EnchantedVisualMetrics.conversationRowSpacing"))
        #expect(runtime.contains("conversationRowRadius: EnchantedVisualMetrics.conversationRowRadius"))
        #expect(runtime.contains("conversationListItemRadius: EnchantedVisualMetrics.conversationListItemRadius"))
        #expect(runtime.contains("conversationListItemVerticalMargin: EnchantedVisualMetrics.conversationListItemVerticalMargin"))
        #expect(runtime.contains("conversationListItemPadding: EnchantedVisualMetrics.conversationListItemPadding"))
        #expect(runtime.contains("conversationActionsSpacing: EnchantedVisualMetrics.conversationActionsSpacing"))
        #expect(runtime.contains("attachmentChipPadding: EnchantedVisualMetrics.attachmentChipPadding"))
        #expect(runtime.contains("attachmentChipSpacing: EnchantedVisualMetrics.attachmentChipSpacing"))
        #expect(runtime.contains("attachmentChipTextSpacing: EnchantedVisualMetrics.attachmentChipTextSpacing"))
        #expect(runtime.contains("attachmentChipRadius: EnchantedVisualMetrics.attachmentChipRadius"))
        #expect(runtime.contains("attachmentTraySpacing: EnchantedVisualMetrics.attachmentTraySpacing"))
        #expect(runtime.contains("attachmentTrayChipSpacing: EnchantedVisualMetrics.attachmentTrayChipSpacing"))
        #expect(!runtime.contains("attachmentInputHorizontalPadding: EnchantedVisualMetrics.attachmentInputHorizontalPadding"))
        #expect(!runtime.contains("attachmentInputVerticalPadding: EnchantedVisualMetrics.attachmentInputVerticalPadding"))
        #expect(runtime.contains("attachmentInputSpacing: EnchantedVisualMetrics.attachmentInputSpacing"))
        #expect(runtime.contains("headerTitleWidth: EnchantedVisualMetrics.headerTitleWidth"))
        #expect(runtime.contains("headerSpacing: EnchantedVisualMetrics.headerSpacing"))
        #expect(runtime.contains("headerTitleSpacing: EnchantedVisualMetrics.headerTitleSpacing"))
        #expect(runtime.contains("headerPadding: EnchantedVisualMetrics.headerPadding"))
        #expect(runtime.contains("composerPadding: EnchantedVisualMetrics.composerPadding"))
        #expect(runtime.contains("composerSpacing: EnchantedVisualMetrics.composerSpacing"))
        #expect(runtime.contains("promptRowSpacing: EnchantedVisualMetrics.promptRowSpacing"))
        #expect(runtime.contains("composerMinWidth: EnchantedVisualMetrics.composerMinWidth"))
        #expect(runtime.contains("composerMaxWidth: EnchantedVisualMetrics.composerMaxWidth"))
        #expect(runtime.contains("composerMinHeight: EnchantedVisualMetrics.composerMinHeight"))
        #expect(runtime.contains("composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight"))
        #expect(runtime.contains("messageMaxWidth: EnchantedVisualMetrics.messageMaxWidth"))
        #expect(runtime.contains("contentPadding: EnchantedVisualMetrics.contentPadding"))
        #expect(runtime.contains("loadingRowSpacing: EnchantedVisualMetrics.loadingRowSpacing"))
        #expect(runtime.contains("loadingTopPadding: EnchantedVisualMetrics.loadingTopPadding"))
        #expect(runtime.contains("loadingSpinnerSize: EnchantedVisualMetrics.loadingSpinnerSize"))
        #expect(runtime.contains("messageSpacing: EnchantedVisualMetrics.messageSpacing"))
        #expect(runtime.contains("messageBubbleRowSpacing: EnchantedVisualMetrics.messageBubbleRowSpacing"))
        #expect(runtime.contains("messageBubblePadding: EnchantedVisualMetrics.messageBubblePadding"))
        #expect(runtime.contains("messageBubbleSpacing: EnchantedVisualMetrics.messageBubbleSpacing"))
        #expect(runtime.contains("messageBubbleRadius: EnchantedVisualMetrics.messageBubbleRadius"))
        #expect(runtime.contains("markdownBlockSpacing: EnchantedVisualMetrics.markdownBlockSpacing"))
        #expect(runtime.contains("markdownListItemSpacing: EnchantedVisualMetrics.markdownListItemSpacing"))
        #expect(runtime.contains("markdownNumberWidth: EnchantedVisualMetrics.markdownNumberWidth"))
        #expect(runtime.contains("markdownQuoteSpacing: EnchantedVisualMetrics.markdownQuoteSpacing"))
        #expect(runtime.contains("markdownQuoteRuleWidth: EnchantedVisualMetrics.markdownQuoteRuleWidth"))
        #expect(runtime.contains("markdownQuoteRuleRadius: EnchantedVisualMetrics.markdownQuoteRuleRadius"))
        #expect(runtime.contains("markdownQuoteVerticalPadding: EnchantedVisualMetrics.markdownQuoteVerticalPadding"))
        #expect(runtime.contains("markdownCodeBlockSpacing: EnchantedVisualMetrics.markdownCodeBlockSpacing"))
        #expect(runtime.contains("markdownCodeBlockPadding: EnchantedVisualMetrics.markdownCodeBlockPadding"))
        #expect(runtime.contains("markdownCodeBlockRadius: EnchantedVisualMetrics.markdownCodeBlockRadius"))
        #expect(runtime.contains("emptyHistoryPadding: EnchantedVisualMetrics.emptyHistoryPadding"))
        #expect(runtime.contains("emptyHistorySpacing: EnchantedVisualMetrics.emptyHistorySpacing"))
        #expect(runtime.contains("emptyHistoryRadius: EnchantedVisualMetrics.emptyHistoryRadius"))
        #expect(runtime.contains("emptyStatePadding: EnchantedVisualMetrics.emptyStatePadding"))
        #expect(runtime.contains("emptyStateSpacing: EnchantedVisualMetrics.emptyStateSpacing"))
        #expect(runtime.contains("emptyStateHeaderSpacing: EnchantedVisualMetrics.emptyStateHeaderSpacing"))
        #expect(runtime.contains("emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth"))
        #expect(runtime.contains("promptListSpacing: EnchantedVisualMetrics.promptListSpacing"))
        #expect(runtime.contains("promptButtonIconSpacing: EnchantedVisualMetrics.promptButtonIconSpacing"))
        #expect(runtime.contains("promptButtonTextWidthInset: EnchantedVisualMetrics.promptButtonTextWidthInset"))
        #expect(runtime.contains("promptButtonMinHeight: EnchantedVisualMetrics.promptButtonMinHeight"))
        #expect(runtime.contains("promptButtonWidth: EnchantedVisualMetrics.promptButtonWidth"))
        #expect(runtime.contains("promptButtonPadding: EnchantedVisualMetrics.promptButtonPadding"))
        #expect(runtime.contains("promptButtonRadius: EnchantedVisualMetrics.promptButtonRadius"))
        #expect(runtime.contains("primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding"))
        #expect(runtime.contains("primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding"))
        #expect(runtime.contains("primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius"))
        #expect(runtime.contains("actionButtonIconSize: EnchantedVisualMetrics.actionButtonIconSize"))
        #expect(runtime.contains("secondaryButtonVerticalPadding: EnchantedVisualMetrics.secondaryButtonVerticalPadding"))
        #expect(runtime.contains("secondaryButtonHorizontalPadding: EnchantedVisualMetrics.secondaryButtonHorizontalPadding"))
        #expect(runtime.contains("secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius"))
        #expect(runtime.contains("chipRemoveButtonVerticalPadding: EnchantedVisualMetrics.chipRemoveButtonVerticalPadding"))
        #expect(runtime.contains("chipRemoveButtonHorizontalPadding: EnchantedVisualMetrics.chipRemoveButtonHorizontalPadding"))
        #expect(runtime.contains("controlPadding: EnchantedVisualMetrics.controlPadding"))
        #expect(runtime.contains("controlRadius: EnchantedVisualMetrics.controlRadius"))
        #expect(runtime.contains("dropTargetPadding: EnchantedVisualMetrics.dropTargetPadding"))
        #expect(runtime.contains("dropTargetRadius: EnchantedVisualMetrics.dropTargetRadius"))
        #expect(runtime.contains("composerEditorRadius: EnchantedVisualMetrics.composerEditorRadius"))
        #expect(runtime.contains("context.insert(ConversationDraft(title: EnchantedCopy.newConversationTitle))"))
        #expect(runtime.contains("context.deleteConversation(id: conversationID)"))
        #expect(runtime.contains("context.deleteAllConversations()"))
        #expect(runtime.contains("var messageText: String?"))
        #expect(runtime.contains("var endpoint: String?"))
        #expect(runtime.contains("var selectedModel: String?"))
        #expect(runtime.contains("var models: [String]?"))
        #expect(runtime.contains("var attachmentPaths: [String]?"))
        #expect(runtime.contains("case \"sendMessage\":"))
        #expect(runtime.contains("case \"refreshModels\", \"configureEndpoint\":"))
        #expect(runtime.contains("case \"selectModel\":"))
        #expect(runtime.contains("OllamaClient(baseURL: endpoint).fetchModels()"))
        #expect(runtime.contains("context.updateConversationTitle(id: selectedConversationID, title: prompt.quillTitle())"))
        #expect(runtime.contains("let displayContent = PendingImageAttachment.displayContent(prompt: prompt, attachments: attachments)"))
        #expect(runtime.contains("content: displayContent"))
        #expect(runtime.contains("imagesForLastUserMessage: encodedImages"))
        #expect(runtime.contains("private static func imageAttachments(from rawPaths: [String]) throws -> [PendingImageAttachment]"))
        #expect(runtime.contains("var kind: String"))
        #expect(runtime.contains("self.kind = prompt.kind.rawValue"))
        #expect(sharedPrompts.contains("public struct EnchantedPrompt: Codable, Equatable, Hashable, Sendable"))
        #expect(sharedPrompts.contains("public enum Kind: String, Codable, Equatable, Hashable, Sendable"))
        #expect(sharedPrompts.contains("case question"))
        #expect(sharedPrompts.contains("case action"))
        #expect(sharedPrompts.contains("public init(title: String, kind: Kind)"))
        #expect(sharedPrompts.contains("public static let questionIconName = EnchantedPrompt.Kind.question.systemImage"))
        #expect(sharedPrompts.contains("public static let actionIconName = EnchantedPrompt.Kind.action.systemImage"))
        #expect(sharedPrompts.contains("kind: .question"))
        #expect(sharedPrompts.contains("kind: .action"))
        #expect(sharedPrompts.contains("public static let emptyConversationTitles = emptyConversationPrompts.map(\\.title)"))
        #expect(sharedPrompts.contains("public enum EnchantedPalette"))
        #expect(sharedPrompts.contains("public static let canvasColor = \"#FBFBFD\""))
        #expect(sharedPrompts.contains("public static let sidebarColor = \"#F5F5F7\""))
        #expect(sharedPrompts.contains("public static let sidebarSelectedColor = \"#E8E8ED\""))
        #expect(sharedPrompts.contains("public static let cardQuietColor = \"#F4F4F6\""))
        #expect(sharedPrompts.contains("public static let hairlineColor = \"#D8D8DE\""))
        #expect(sharedPrompts.contains("public static let textColor = \"#1D1D1F\""))
        #expect(sharedPrompts.contains("public static let secondaryTextColor = \"#6E6E73\""))
        #expect(sharedPrompts.contains("public static let accentColor = \"#4285F4\""))
        #expect(sharedPrompts.contains("public static let destructiveColor = \"#B42318\""))
        #expect(sharedPrompts.contains("public static let warningColor = \"#FF9F0A\""))
        #expect(sharedPrompts.contains("public static let primaryColor = EnchantedPalette.accentColor"))
        #expect(sharedPrompts.contains("public static let codeBlockColor = EnchantedPalette.cardQuietColor"))
        #expect(sharedPrompts.contains("public enum EnchantedVisualMetrics"))
        #expect(sharedPrompts.contains("public static let minimumWindowWidth = 980"))
        #expect(sharedPrompts.contains("public static let minimumWindowHeight = 680"))
        #expect(sharedPrompts.contains("public static let defaultWindowWidth = 1180"))
        #expect(sharedPrompts.contains("public static let defaultWindowHeight = 760"))
        #expect(sharedPrompts.contains("public static let sidebarWidth = 300"))
        #expect(sharedPrompts.contains("public static let sidebarIdealWidth = 330"))
        #expect(sharedPrompts.contains("public static let sidebarMaxWidth = 360"))
        #expect(sharedPrompts.contains("public static let detailWidth = defaultWindowWidth - sidebarWidth"))
        #expect(sharedPrompts.contains("public static let sidebarPadding = 18"))
        #expect(sharedPrompts.contains("public static let sidebarSpacing = 14"))
        #expect(sharedPrompts.contains("public static let sidebarTitleSpacing = 4"))
        #expect(sharedPrompts.contains("public static let sidebarControlGroupSpacing = 7"))
        #expect(sharedPrompts.contains("public static let statusRowSpacing = 8"))
        #expect(sharedPrompts.contains("public static let statusTextWidth = 240"))
        #expect(sharedPrompts.contains("public static let statusDotSize = 9"))
        #expect(sharedPrompts.contains("public static let statusDotRadius = 9"))
        #expect(sharedPrompts.contains("public static let headerTitleWidth = 560"))
        #expect(sharedPrompts.contains("public static let headerSpacing = 12"))
        #expect(sharedPrompts.contains("public static let headerTitleSpacing = 4"))
        #expect(sharedPrompts.contains("public static let headerPadding = 18"))
        #expect(sharedPrompts.contains("public static let contentPadding = 22"))
        #expect(sharedPrompts.contains("public static let loadingRowSpacing = 8"))
        #expect(sharedPrompts.contains("public static let loadingTopPadding = 8"))
        #expect(sharedPrompts.contains("public static let loadingSpinnerSize = 16"))
        #expect(sharedPrompts.contains("public static let promptButtonWidth = 620"))
        #expect(sharedPrompts.contains("public static let promptButtonMinHeight = 48"))
        #expect(sharedPrompts.contains("public static let emptyStateMaxWidth = 680"))
        #expect(sharedPrompts.contains("public static let emptyStatePadding = 26"))
        #expect(sharedPrompts.contains("public static let emptyStateSpacing = 18"))
        #expect(sharedPrompts.contains("public static let emptyStateHeaderSpacing = 8"))
        #expect(sharedPrompts.contains("public static let promptListSpacing = 10"))
        #expect(sharedPrompts.contains("public static let promptButtonIconSpacing = 10"))
        #expect(sharedPrompts.contains("public static let promptButtonTextWidthInset = 80"))
        #expect(sharedPrompts.contains("public static let promptButtonPadding = 12"))
        #expect(sharedPrompts.contains("public static let promptButtonRadius = 8"))
        #expect(sharedPrompts.contains("public static let primaryButtonPadding = 12"))
        #expect(sharedPrompts.contains("public static let primaryButtonIconSpacing = 8"))
        #expect(sharedPrompts.contains("public static let primaryButtonVerticalPadding = primaryButtonPadding"))
        #expect(sharedPrompts.contains("public static let primaryButtonHorizontalPadding = primaryButtonPadding"))
        #expect(sharedPrompts.contains("public static let primaryButtonRadius = 8"))
        #expect(sharedPrompts.contains("public static let actionButtonIconSpacing = 6"))
        #expect(sharedPrompts.contains("public static let actionButtonIconSize = 16"))
        #expect(sharedPrompts.contains("public static let secondaryButtonVerticalPadding = 7"))
        #expect(sharedPrompts.contains("public static let secondaryButtonHorizontalPadding = 10"))
        #expect(sharedPrompts.contains("public static let secondaryButtonRadius = 7"))
        #expect(sharedPrompts.contains("public static let dropTargetPadding = 8"))
        #expect(sharedPrompts.contains("public static let dropTargetRadius = 8"))
        #expect(sharedPrompts.contains("public static let conversationListSpacing = 8"))
        #expect(sharedPrompts.contains("public static let conversationActionsSpacing = 8"))
        #expect(sharedPrompts.contains("public static let conversationRowPadding = 11"))
        #expect(sharedPrompts.contains("public static let conversationRowSpacing = 5"))
        #expect(sharedPrompts.contains("public static let conversationRowRadius = 8"))
        #expect(sharedPrompts.contains("public static let conversationListItemRadius = 8"))
        #expect(sharedPrompts.contains("public static let conversationListItemVerticalMargin = 2"))
        #expect(sharedPrompts.contains("public static let conversationListItemPadding = 8"))
        #expect(sharedPrompts.contains("public static let emptyHistoryPadding = 12"))
        #expect(sharedPrompts.contains("public static let emptyHistorySpacing = 8"))
        #expect(sharedPrompts.contains("public static let emptyHistoryRadius = 8"))
        #expect(sharedPrompts.contains("public static let attachmentChipPadding = 8"))
        #expect(sharedPrompts.contains("public static let attachmentChipSpacing = 8"))
        #expect(sharedPrompts.contains("public static let attachmentChipTextSpacing = 2"))
        #expect(sharedPrompts.contains("public static let attachmentChipRadius = 8"))
        #expect(sharedPrompts.contains("public static let attachmentRemoveButtonWidth = 28"))
        #expect(sharedPrompts.contains("public static let attachmentTraySpacing = 7"))
        #expect(sharedPrompts.contains("public static let attachmentTrayChipSpacing = 8"))
        #expect(sharedPrompts.contains("public static let attachmentInputHorizontalPadding = 10"))
        #expect(sharedPrompts.contains("public static let attachmentInputVerticalPadding = 7"))
        #expect(sharedPrompts.contains("public static let attachmentInputSpacing = 8"))
        #expect(sharedPrompts.contains("public static let messageMaxWidth = 680"))
        #expect(sharedPrompts.contains("public static let messageSpacing = 14"))
        #expect(sharedPrompts.contains("public static let messageBubbleRowSpacing = 10"))
        #expect(sharedPrompts.contains("public static let messageBubblePadding = 13"))
        #expect(sharedPrompts.contains("public static let messageBubbleSpacing = 7"))
        #expect(sharedPrompts.contains("public static let messageBubbleRadius = 10"))
        #expect(sharedPrompts.contains("public static let markdownBlockSpacing = 9"))
        #expect(sharedPrompts.contains("public static let markdownListItemSpacing = 8"))
        #expect(sharedPrompts.contains("public static let markdownNumberWidth = 26"))
        #expect(sharedPrompts.contains("public static let markdownQuoteSpacing = 9"))
        #expect(sharedPrompts.contains("public static let markdownQuoteRuleWidth = 3"))
        #expect(sharedPrompts.contains("public static let markdownQuoteRuleRadius = 1"))
        #expect(sharedPrompts.contains("public static let markdownQuoteVerticalPadding = 2"))
        #expect(sharedPrompts.contains("public static let markdownCodeBlockSpacing = 7"))
        #expect(sharedPrompts.contains("public static let markdownCodeBlockPadding = 10"))
        #expect(sharedPrompts.contains("public static let markdownCodeBlockRadius = 7"))
        #expect(sharedPrompts.contains("public static let composerMinWidth = 620"))
        #expect(sharedPrompts.contains("public static let composerMaxWidth = 840"))
        #expect(sharedPrompts.contains("public static let composerPadding = 18"))
        #expect(sharedPrompts.contains("public static let composerSpacing = 10"))
        #expect(sharedPrompts.contains("public static let promptRowSpacing = 12"))
        #expect(sharedPrompts.contains("public static let composerSendButtonMinWidth = 86"))
        #expect(sharedPrompts.contains("public static let composerMinHeight = 74"))
        #expect(sharedPrompts.contains("public static let composerMaxHeight = 120"))
        #expect(sharedPrompts.contains("public enum EnchantedTypography"))
        #expect(sharedPrompts.contains("public static let rootFontSize = 14"))
        #expect(sharedPrompts.contains("public static let appTitleFontSize = 26"))
        #expect(sharedPrompts.contains("public static let chipRemoveButtonFontWeight = 700"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarTitleSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarControlGroupSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.headerTitleWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.headerSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.headerTitleSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.headerPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.statusRowSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.statusTextWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.statusDotSize"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.contentPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.loadingRowSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.loadingTopPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyStateMaxWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyStatePadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyStateSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyStateHeaderSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptListSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonIconSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonTextWidthInset"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonRadius"))
        #expect(macOSRootView.contains("Image(systemName: prompt.systemImage)"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.primaryButtonPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.primaryButtonIconSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.primaryButtonRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.actionButtonIconSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.dropTargetPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.dropTargetRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.conversationListSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.conversationActionsSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.conversationRowPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.conversationRowSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.conversationRowRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyHistoryPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyHistorySpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyHistoryRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentChipPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentChipSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentChipTextSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentChipRadius"))
        #expect(macOSRootView.contains("EnchantedTypography.rootFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.appTitleFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.captionFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.sectionTitleFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.currentTitleFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.messageBodyFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.attachmentNameFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.attachmentSizeFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.conversationTitleFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.conversationPreviewFontSize"))
        #expect(macOSRootView.contains("EnchantedTypography.warningTextFontSize"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentTraySpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentTrayChipSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.attachmentInputSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageMaxWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageBubbleRowSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageBubblePadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageBubbleSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageBubbleRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerPadding"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerEditorRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptRowSpacing"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerMinWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerMaxWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerMinHeight"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerMaxHeight"))
        for prompt in enchantedEmptyConversationPrompts {
            #expect(sharedPrompts.contains(prompt))
        }
        #expect(sharedOllama.contains("public struct OllamaClient: Sendable"))
        #expect(sharedOllama.contains("LocalizedError"))
        #expect(sharedOllama.contains("public var errorDescription: String?"))
        #expect(sharedOllama.contains("public enum OllamaStreamParser"))
        #expect(runtime.contains("private final class AsyncResultBox<Value: Sendable>"))
        #expect(runtime.contains("private static func waitForAsync<Value: Sendable>"))
        #expect(header.contains("quill_enchanted_qt_run_app_json"))
        #expect(header.contains("quill_enchanted_qt_action_callback"))
        #expect(header.contains("quill_enchanted_qt_free_string_callback"))
        #expect(nativeShim.contains("#include \"QuillQtWidgetsSupport.hpp\""))
        #expect(nativeShim.contains("#include <QJsonDocument>"))
        #expect(nativeShim.contains("using PromptAction = std::function<void(const QString &)>;"))
        #expect(nativeShim.contains("QJsonObject actionSnapshot("))
        #expect(nativeShim.contains("quill_enchanted_qt_action_callback actionCallback"))
        #expect(nativeShim.contains("quill_enchanted_qt_free_string_callback freeString"))
        #expect(nativeShim.contains("#include <QRegularExpression>"))
        #expect(nativeShim.contains("#include <QSignalBlocker>"))
        #expect(nativeShim.contains("QComboBox"))
        #expect(nativeShim.contains("QListWidget"))
        #expect(nativeShim.contains("QPlainTextEdit"))
        #expect(nativeShim.contains("class LoadingSpinner final : public QWidget"))
        #expect(nativeShim.contains("QScrollArea"))
        #expect(nativeShim.contains("using QuillQtWidgets::scrollAreaToBottomLater;"))
        #expect(nativeShim.contains("auto scrollTranscriptToBottom = [scrollArea]()"))
        #expect(nativeShim.contains("scrollAreaToBottomLater(scrollArea)"))
        #expect(nativeShim.contains("scrollTranscriptToBottom();"))
        #expect(nativeShim.contains("styleValue(style, \"canvasColor\", \"#FBFBFD\")"))
        #expect(nativeShim.contains("styleValue(style, \"quoteRuleColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"codeBlockColor\", \"#F4F4F6\")"))
        #expect(nativeShim.contains("styleValue(style, \"dividerColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"cardBorderColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"messageBorderColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"controlBorderColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"dropTargetBorderColor\", \"#4285F4\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledButtonBackgroundColor\", \"#D8D8DE\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledButtonForegroundColor\", \"#6E6E73\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledTextColor\", \"#6E6E73\")"))
        #expect(nativeShim.contains("intValue(style, \"sidebarWidth\", 300)"))
        #expect(nativeShim.contains("const int sidebarPadding = intValue(style, \"sidebarPadding\", 18)"))
        #expect(nativeShim.contains("sidebarLayout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding)"))
        #expect(nativeShim.contains("sidebarLayout->setSpacing(intValue(style, \"sidebarSpacing\", 14))"))
        #expect(nativeShim.contains("QWidget *sidebarTitleBlock = new QWidget()"))
        #expect(nativeShim.contains("sidebarTitleLayout->setSpacing(intValue(style, \"sidebarTitleSpacing\", 4))"))
        #expect(nativeShim.contains("void addSidebarField(\n    QVBoxLayout *layout,\n    const QString &title,\n    QWidget *field,\n    const QJsonObject &style\n)"))
        #expect(nativeShim.contains("groupLayout->setSpacing(intValue(style, \"sidebarControlGroupSpacing\", 7))"))
        #expect(nativeShim.contains("QFrame *conversationRowWidget(\n    const QJsonObject &conversation,\n    const QJsonObject &style,\n    const QString &newConversationTitle,\n    const QString &noMessagesYet\n)"))
        #expect(nativeShim.contains("const int conversationRowPadding = intValue(style, \"conversationRowPadding\", 11)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"conversationRowSpacing\", 5))"))
        #expect(nativeShim.contains("stringValue(conversation, \"title\", newConversationTitle)"))
        #expect(nativeShim.contains("const QString previewText = stringValue(conversation, \"lastMessage\", noMessagesYet)"))
        #expect(nativeShim.contains("if (!previewText.isEmpty())"))
        #expect(nativeShim.contains("QLabel *preview = label(previewText, QStringLiteral(\"conversationPreview\"))"))
        #expect(nativeShim.contains("QWidget *rowWidget = conversationRowWidget("))
        #expect(nativeShim.contains("rowWidget->sizeHint().height()"))
        #expect(!nativeShim.contains("layout->setContentsMargins(11, 9, 11, 9)"))
        #expect(nativeShim.contains("conversationActions->setSpacing(intValue(style, \"conversationActionsSpacing\", 8))"))
        #expect(!nativeShim.contains("conversationActions->setSpacing(8)"))
        #expect(nativeShim.contains("const int attachmentChipPadding = intValue(style, \"attachmentChipPadding\", 8)"))
        #expect(nativeShim.contains("attachmentChipLayout->setContentsMargins(\n                attachmentChipPadding,\n                attachmentChipPadding,\n                attachmentChipPadding,\n                attachmentChipPadding\n            )"))
        #expect(nativeShim.contains("attachmentChipLayout->setSpacing(intValue(style, \"attachmentChipSpacing\", 8))"))
        #expect(nativeShim.contains("attachmentTextLayout->setSpacing(intValue(style, \"attachmentChipTextSpacing\", 2))"))
        #expect(!nativeShim.contains("attachmentChipLayout->setContentsMargins(10, 7, 8, 7)"))
        #expect(!nativeShim.contains("attachmentTextLayout->setSpacing(2)"))
        #expect(nativeShim.contains("attachmentTrayLayout->setSpacing(intValue(style, \"attachmentTraySpacing\", 7))"))
        #expect(nativeShim.contains("attachmentChipListLayout->setSpacing(intValue(style, \"attachmentTrayChipSpacing\", 8))"))
        #expect(!nativeShim.contains("attachmentTrayLayout->setSpacing(7)"))
        #expect(!nativeShim.contains("attachmentChipListLayout->setSpacing(8)"))
        #expect(nativeShim.contains("QVBoxLayout *dropTargetLayout = new QVBoxLayout(dropTarget)"))
        #expect(nativeShim.contains("dropTargetLayout->setContentsMargins(0, 0, 0, 0)"))
        #expect(nativeShim.contains("QFrame *dropHint = QuillQtWidgets::frame(QStringLiteral(\"dropTargetHint\"))"))
        #expect(nativeShim.contains("const int dropTargetPadding = intValue(style, \"dropTargetPadding\", 8)"))
        #expect(nativeShim.contains("dropHintLayout->setContentsMargins(\n        dropTargetPadding,\n        dropTargetPadding,\n        dropTargetPadding,\n        dropTargetPadding\n    )"))
        #expect(nativeShim.contains("dropLayout->setContentsMargins(0, 0, 0, 0)"))
        #expect(nativeShim.contains("dropLayout->setSpacing(intValue(style, \"attachmentInputSpacing\", 8))"))
        #expect(!nativeShim.contains("const int attachmentInputHorizontalPadding = intValue(style, \"attachmentInputHorizontalPadding\", 10)"))
        #expect(!nativeShim.contains("const int attachmentInputVerticalPadding = intValue(style, \"attachmentInputVerticalPadding\", 7)"))
        #expect(!nativeShim.contains("dropLayout->setContentsMargins(10, 7, 10, 7)"))
        #expect(!nativeShim.contains("dropLayout->setSpacing(8)"))
        #expect(nativeShim.contains("intValue(style, \"headerTitleWidth\", 560)"))
        #expect(nativeShim.contains("statusLayout->setSpacing(intValue(style, \"statusRowSpacing\", 8))"))
        #expect(nativeShim.contains("statusText->setFixedWidth(intValue(style, \"statusTextWidth\", 240))"))
        #expect(nativeShim.contains("const int statusDotSize = intValue(style, \"statusDotSize\", 9)"))
        #expect(nativeShim.contains("statusDot->setFixedSize(statusDotSize, statusDotSize)"))
        #expect(nativeShim.contains("headerLayout->setSpacing(intValue(style, \"headerSpacing\", 12))"))
        #expect(nativeShim.contains("titleLayout->setSpacing(intValue(style, \"headerTitleSpacing\", 4))"))
        #expect(nativeShim.contains("messageLayout->setSpacing(intValue(style, \"messageSpacing\", 14))"))
        #expect(nativeShim.contains("QWidget *loadingRowWidget(const QString &status, const QJsonObject &style)"))
        #expect(nativeShim.contains("layout->setContentsMargins(0, intValue(style, \"loadingTopPadding\", 8), 0, 0)"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"loadingRowSpacing\", 8))"))
        #expect(nativeShim.contains("const int spinnerSize = intValue(style, \"loadingSpinnerSize\", 16)"))
        #expect(nativeShim.contains("setFixedSize(spinnerSize, spinnerSize)"))
        #expect(nativeShim.contains("QObject::connect(&timer, &QTimer::timeout, this, [this]()"))
        #expect(nativeShim.contains("rotationDegrees = (rotationDegrees + 30) % 360"))
        #expect(nativeShim.contains("QPainter painter(this)"))
        #expect(nativeShim.contains("layout->addWidget(new LoadingSpinner(style), 0, Qt::AlignVCenter)"))
        #expect(nativeShim.contains("layout->addWidget(label(status, QStringLiteral(\"caption\")), 0, Qt::AlignVCenter)"))
        #expect(nativeShim.contains("messageLayout->addWidget(loadingRowWidget(status, style))"))
        #expect(nativeShim.contains("row->setSpacing(intValue(style, \"messageBubbleRowSpacing\", 10))"))
        #expect(nativeShim.contains("const int messageBubblePadding = intValue(style, \"messageBubblePadding\", 13)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"messageBubbleSpacing\", 7))"))
        #expect(nativeShim.contains("const int emptyStatePadding = intValue(style, \"emptyStatePadding\", 26)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"emptyStateSpacing\", 18))"))
        #expect(nativeShim.contains("headerLayout->setSpacing(intValue(style, \"emptyStateHeaderSpacing\", 8))"))
        #expect(nativeShim.contains("promptList->setSpacing(intValue(style, \"promptListSpacing\", 10))"))
        #expect(nativeShim.contains("const int promptButtonWidth = intValue(style, \"promptButtonWidth\", 620)"))
        #expect(nativeShim.contains("const int promptButtonIconSpacing = intValue(style, \"promptButtonIconSpacing\", 10)"))
        #expect(nativeShim.contains("const int promptButtonTextWidth = promptButtonWidth - intValue(style, \"promptButtonTextWidthInset\", 80)"))
        #expect(nativeShim.contains("buttonLayout->setSpacing(promptButtonIconSpacing)"))
        #expect(nativeShim.contains("QLabel *promptIcon = iconLabel(promptButtonIcon(systemImage), QStringLiteral(\"promptButtonIcon\"), style)"))
        #expect(nativeShim.contains("QLabel *promptText = label(prompt, QStringLiteral(\"promptButtonText\"))"))
        #expect(nativeShim.contains("promptText->setFixedWidth(promptButtonTextWidth > 0 ? promptButtonTextWidth : 0)"))
        #expect(nativeShim.contains("button->setMinimumHeight(intValue(style, \"promptButtonMinHeight\", 48))"))
        #expect(nativeShim.contains("button->setFixedWidth(promptButtonWidth)"))
        #expect(nativeShim.contains("emptyState->setMaximumWidth(intValue(style, \"emptyStateMaxWidth\", 680))"))
        #expect(nativeShim.contains("const QString primaryButtonVerticalPadding = cssPixels(style, \"primaryButtonVerticalPadding\", 12)"))
        #expect(nativeShim.contains("const QString primaryButtonHorizontalPadding = cssPixels(style, \"primaryButtonHorizontalPadding\", 12)"))
        #expect(nativeShim.contains("const QString primaryButtonRadius = cssPixels(style, \"primaryButtonRadius\", 8)"))
        #expect(nativeShim.contains("const QString secondaryButtonVerticalPadding = cssPixels(style, \"secondaryButtonVerticalPadding\", 7)"))
        #expect(nativeShim.contains("const QString secondaryButtonHorizontalPadding = cssPixels(style, \"secondaryButtonHorizontalPadding\", 10)"))
        #expect(nativeShim.contains("const QString secondaryButtonRadius = cssPixels(style, \"secondaryButtonRadius\", 7)"))
        #expect(nativeShim.contains("const QString promptButtonPadding = cssPixels(style, \"promptButtonPadding\", 12)"))
        #expect(nativeShim.contains("const QString promptButtonRadius = cssPixels(style, \"promptButtonRadius\", 8)"))
        #expect(nativeShim.contains("const QString chipRemoveButtonVerticalPadding = cssPixels(style, \"chipRemoveButtonVerticalPadding\", 2)"))
        #expect(nativeShim.contains("const QString chipRemoveButtonHorizontalPadding = cssPixels(style, \"chipRemoveButtonHorizontalPadding\", 6)"))
        #expect(nativeShim.contains("const QString controlPadding = cssPixels(style, \"controlPadding\", 7)"))
        #expect(nativeShim.contains("const QString controlRadius = cssPixels(style, \"controlRadius\", 7)"))
        #expect(nativeShim.contains("const QString composerEditorRadius = cssPixels(style, \"composerEditorRadius\", 8)"))
        #expect(nativeShim.contains("const QString conversationRowRadius = cssPixels(style, \"conversationRowRadius\", 8)"))
        #expect(nativeShim.contains("const QString conversationListItemRadius = cssPixels(style, \"conversationListItemRadius\", 8)"))
        #expect(nativeShim.contains("const QString conversationListItemVerticalMargin = cssPixels(style, \"conversationListItemVerticalMargin\", 2)"))
        #expect(nativeShim.contains("const QString conversationListItemPadding = cssPixels(style, \"conversationListItemPadding\", 8)"))
        #expect(nativeShim.contains("list->setSpacing(intValue(style, \"conversationListSpacing\", 8))"))
        #expect(nativeShim.contains("const QString emptyHistoryRadius = cssPixels(style, \"emptyHistoryRadius\", 8)"))
        #expect(nativeShim.contains("const QString messageBubbleRadius = cssPixels(style, \"messageBubbleRadius\", 10)"))
        #expect(nativeShim.contains("const QString attachmentChipRadius = cssPixels(style, \"attachmentChipRadius\", 8)"))
        #expect(nativeShim.contains("const QString markdownQuoteRuleRadius = cssPixels(style, \"markdownQuoteRuleRadius\", 1)"))
        #expect(nativeShim.contains("const QString markdownCodeBlockRadius = cssPixels(style, \"markdownCodeBlockRadius\", 7)"))
        #expect(nativeShim.contains("const QString dropTargetRadius = cssPixels(style, \"dropTargetRadius\", 8)"))
        #expect(nativeShim.contains("const QString rootFontSize = cssPixels(style, \"rootFontSize\", 14)"))
        #expect(nativeShim.contains("const QString appTitleFontSize = cssPixels(style, \"appTitleFontSize\", 26)"))
        #expect(nativeShim.contains("const QString appTitleFontWeight = QString::number(intValue(style, \"appTitleFontWeight\", 700))"))
        #expect(nativeShim.contains("const QString captionFontSize = cssPixels(style, \"captionFontSize\", 12)"))
        #expect(nativeShim.contains("const QString sectionTitleFontSize = cssPixels(style, \"sectionTitleFontSize\", 15)"))
        #expect(nativeShim.contains("const QString sectionTitleFontWeight = QString::number(intValue(style, \"sectionTitleFontWeight\", 700))"))
        #expect(nativeShim.contains("const QString currentTitleFontSize = cssPixels(style, \"currentTitleFontSize\", 20)"))
        #expect(nativeShim.contains("const QString currentTitleFontWeight = QString::number(intValue(style, \"currentTitleFontWeight\", 650))"))
        #expect(nativeShim.contains("const QString messageBodyFontSize = cssPixels(style, \"messageBodyFontSize\", 14)"))
        #expect(nativeShim.contains("const QString markdownHeading1FontSize = cssPixels(style, \"markdownHeading1FontSize\", 17)"))
        #expect(nativeShim.contains("const QString markdownHeading2FontSize = cssPixels(style, \"markdownHeading2FontSize\", 15)"))
        #expect(nativeShim.contains("const QString markdownHeadingFontSize = cssPixels(style, \"markdownHeadingFontSize\", 14)"))
        #expect(nativeShim.contains("const QString markdownHeadingFontWeight = QString::number(intValue(style, \"markdownHeadingFontWeight\", 650))"))
        #expect(nativeShim.contains("const QString markdownCodeLanguageFontSize = cssPixels(style, \"markdownCodeLanguageFontSize\", 11)"))
        #expect(nativeShim.contains("const QString markdownCodeFontSize = cssPixels(style, \"markdownCodeFontSize\", 13)"))
        #expect(nativeShim.contains("const QString attachmentNameFontSize = cssPixels(style, \"attachmentNameFontSize\", 12)"))
        #expect(nativeShim.contains("const QString attachmentSizeFontSize = cssPixels(style, \"attachmentSizeFontSize\", 11)"))
        #expect(nativeShim.contains("const QString conversationTitleFontSize = cssPixels(style, \"conversationTitleFontSize\", 15)"))
        #expect(nativeShim.contains("const QString conversationTitleFontWeight = QString::number(intValue(style, \"conversationTitleFontWeight\", 700))"))
        #expect(nativeShim.contains("const QString conversationPreviewFontSize = cssPixels(style, \"conversationPreviewFontSize\", 12)"))
        #expect(nativeShim.contains("const QString warningTextFontSize = cssPixels(style, \"warningTextFontSize\", 12)"))
        #expect(nativeShim.contains("const QString chipRemoveButtonFontWeight = QString::number(intValue(style, \"chipRemoveButtonFontWeight\", 700))"))
        #expect(nativeShim.contains("QWidget#enchantedRoot { background: %1; color: %2; font-size: %3; }"))
        #expect(nativeShim.contains("QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }"))
        #expect(nativeShim.contains("QLabel#caption, QLabel#fieldLabel, QLabel#statusText, QLabel#messageRole { color: %5; font-size: %6; }"))
        #expect(nativeShim.contains("QFrame#sidebar { background: %1; border-right: 1px solid %2; }"))
        #expect(nativeShim.contains("QLabel#messageUserRole { color: %3; font-size: %4; }"))
        #expect(nativeShim.contains("QFrame#emptyHistory, QFrame#sidebarUtilityPanel { background: %1; border: 1px solid %2; border-radius: %3; }"))
        #expect(nativeShim.contains("QFrame#messageAssistant { background: %1; border: 1px solid %2; border-radius: %4; }"))
        #expect(nativeShim.contains("QFrame#messageSystem { background: %5; border: 1px solid %6; border-radius: %4; }"))
        #expect(nativeShim.contains("QFrame#messageUser { background: %7; border: 1px solid %6; border-radius: %4; }"))
        #expect(nativeShim.contains("QFrame#attachmentChip { background: %1; border: 1px solid %2; border-radius: %8; }"))
        #expect(nativeShim.contains("QPushButton#primaryButton, QPushButton#sendButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; text-align: left; }"))
        #expect(nativeShim.contains("QPushButton#sendButton:disabled { background: %6; color: %7; }"))
        #expect(nativeShim.contains("QPushButton#secondaryButton { background: transparent; color: %1; border: 1px solid %2; border-radius: %3; padding: %4 %5; text-align: left; }"))
        #expect(nativeShim.contains("QPushButton#secondaryButton:disabled { color: %6; border: 1px solid %7; }"))
        #expect(nativeShim.contains("QPushButton#chipRemoveButton { background: transparent; color: %1; border: 0; padding: %2 %3; font-weight: %4; }"))
        #expect(nativeShim.contains("QPushButton#promptButton { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; text-align: left; }"))
        #expect(nativeShim.contains("QLabel#promptButtonIcon, QLabel#promptButtonText { color: %2; font-size: %6; }"))
        #expect(nativeShim.contains("QLineEdit, QComboBox { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }"))
        #expect(nativeShim.contains("QPlainTextEdit { background: %1; color: %2; border: 1px solid %3; border-radius: %6; padding: %5; }"))
        #expect(!nativeShim.contains("font-size: 14px;"))
        #expect(!nativeShim.contains("font-size: 12px;"))
        #expect(!nativeShim.contains("font-weight: 700;"))
        #expect(genericQtHost.contains("const QString rootFontSize = cssPixels(style, \"rootFontSize\", 14)"))
        #expect(genericQtHost.contains("const QString appTitleFontSize = cssPixels(style, \"appTitleFontSize\", 26)"))
        #expect(genericQtHost.contains("const QString appTitleFontWeight = QString::number(intValue(style, \"appTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("const QString captionFontSize = cssPixels(style, \"captionFontSize\", 12)"))
        #expect(genericQtHost.contains("const QString sectionTitleFontSize = cssPixels(style, \"sectionTitleFontSize\", 15)"))
        #expect(genericQtHost.contains("const QString sectionTitleFontWeight = QString::number(intValue(style, \"sectionTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("const QString currentTitleFontSize = cssPixels(style, \"currentTitleFontSize\", 20)"))
        #expect(genericQtHost.contains("const QString currentTitleFontWeight = QString::number(intValue(style, \"currentTitleFontWeight\", 650))"))
        #expect(genericQtHost.contains("const QString messageBodyFontSize = cssPixels(style, \"messageBodyFontSize\", 14)"))
        #expect(genericQtHost.contains("const QString conversationTitleFontSize = cssPixels(style, \"conversationTitleFontSize\", 15)"))
        #expect(genericQtHost.contains("const QString conversationTitleFontWeight = QString::number(intValue(style, \"conversationTitleFontWeight\", 700))"))
        #expect(genericQtHost.contains("QWidget#genericRoot { background: %1; color: %2; font-size: %3; }"))
        #expect(genericQtHost.contains("QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }"))
        #expect(genericQtHost.contains("QLabel#bodyText, QLabel#messageText { color: %1; font-size: %2; line-height: 140%; }"))
        #expect(!genericQtHost.contains("font-size: 14px;"))
        #expect(!genericQtHost.contains("font-size: 12px;"))
        #expect(!genericQtHost.contains("font-size: 25px;"))
        #expect(!genericQtHost.contains("font-size: 22px;"))
        #expect(!genericQtHost.contains("font-weight: 700;"))
        #expect(!nativeShim.contains("#F6F7F2"))
        #expect(!nativeShim.contains("#EEF1EA"))
        #expect(!nativeShim.contains("#FBFCF7"))
        #expect(!nativeShim.contains("#315B7D"))
        #expect(!nativeShim.contains("#B86A31"))
        #expect(!nativeShim.contains("#8AA5B7"))
        #expect(!nativeShim.contains("#EEF3F4"))
        #expect(!nativeShim.contains("#D8DDD5"))
        #expect(!nativeShim.contains("#CDD5CA"))
        #expect(!nativeShim.contains("#AAB5BE"))
        #expect(!nativeShim.contains("statusLayout->setSpacing(8)"))
        #expect(!nativeShim.contains("statusText->setFixedWidth(240)"))
        #expect(!nativeShim.contains("statusDot->setFixedSize(9, 9)"))
        #expect(!nativeShim.contains("headerLayout->setSpacing(12)"))
        #expect(!nativeShim.contains("titleLayout->setSpacing(4)"))
        #expect(!nativeShim.contains("messageLayout->setSpacing(14)"))
        #expect(!nativeShim.contains("layout->setContentsMargins(0, 8, 0, 0)"))
        #expect(!nativeShim.contains("layout->setSpacing(8)"))
        #expect(!nativeShim.contains("setFixedSize(16, 16)"))
        #expect(nativeShim.contains("const int composerPadding = intValue(style, \"composerPadding\", 18)"))
        #expect(nativeShim.contains("composerContent->setMinimumWidth(intValue(style, \"composerMinWidth\", 620))"))
        #expect(nativeShim.contains("composerContent->setMaximumWidth(intValue(style, \"composerMaxWidth\", 840))"))
        #expect(nativeShim.contains("composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding)"))
        #expect(nativeShim.contains("composerLayout->setSpacing(intValue(style, \"composerSpacing\", 10))"))
        #expect(nativeShim.contains("promptRow->setSpacing(intValue(style, \"promptRowSpacing\", 12))"))
        #expect(nativeShim.contains("promptEditor->setMinimumHeight(intValue(style, \"composerMinHeight\", 74))"))
        #expect(nativeShim.contains("promptEditor->setMaximumHeight(intValue(style, \"composerMaxHeight\", 120))"))
        #expect(!nativeShim.contains("promptEditor->setFixedHeight(intValue(style, \"composerHeight\", 84))"))
        #expect(nativeShim.contains("selectedConversationMessages("))
        #expect(sharedPrompts.contains("public static let usingModelStatusPrefix = \"Using\""))
        #expect(sharedPrompts.contains("public static let removeAttachmentTooltip = \"Remove attachment\""))
        #expect(sharedPrompts.contains("public static let completionsPanelSubtitle = \"Prompt completions use the shared Enchanted profile.\""))
        #expect(sharedPrompts.contains("public static let shortcutsPanelSubtitle = \"Keyboard shortcuts use the shared QuillKit shortcut surface.\""))
        #expect(sharedPrompts.contains("public static let settingsPanelSubtitle = \"Refresh models, choose a local model, or clear history from this sidebar.\""))
        #expect(sharedPrompts.contains("public static let imageReadyStatusSingular = \"1 image ready to send\""))
        #expect(sharedPrompts.contains("public static let imageReadyStatusPluralUnit = \"images ready to send\""))
        #expect(sharedPrompts.contains("count == 1 ? imageReadyStatusSingular : \"\\(count) \\(imageReadyStatusPluralUnit)\""))
        #expect(nativeShim.contains("const QString chooseLocalModelStatus = stringValue("))
        #expect(nativeShim.contains("usingModelStatusPrefix\", QStringLiteral(\"Using\")"))
        #expect(nativeShim.contains("const QString newConversationButtonTitle = stringValue("))
        #expect(nativeShim.contains("\"newConversationButtonTitle\""))
        #expect(nativeShim.contains("\"newChatTitle\", QStringLiteral(\"New chat\")"))
        #expect(nativeShim.contains("QPushButton *newConversationButton = new QPushButton(newConversationButtonTitle)"))
        #expect(nativeShim.contains("\"completionsPanelSubtitle\","))
        #expect(nativeShim.contains("QStringLiteral(\"Prompt completions use the shared Enchanted profile.\")"))
        #expect(nativeShim.contains("\"shortcutsPanelSubtitle\","))
        #expect(nativeShim.contains("QStringLiteral(\"Keyboard shortcuts use the shared QuillKit shortcut surface.\")"))
        #expect(nativeShim.contains("\"settingsPanelSubtitle\","))
        #expect(nativeShim.contains("QStringLiteral(\"Refresh models, choose a local model, or clear history from this sidebar.\")"))
        #expect(nativeShim.contains("newConversationTitle\", QStringLiteral(\"New conversation\")"))
        #expect(nativeShim.contains("noMessagesYet\", QStringLiteral(\"No messages yet\")"))
        #expect(nativeShim.contains("userRoleLabel\", QStringLiteral(\"You\")"))
        #expect(nativeShim.contains("assistantRoleLabel\", QStringLiteral(\"Enchanted\")"))
        #expect(nativeShim.contains("systemRoleLabel\", QStringLiteral(\"System\")"))
        #expect(nativeShim.contains("QString modelStatusText(\n    const QString &selectedModel,\n    const QString &chooseLocalModelStatus,\n    const QString &usingModelStatusPrefix\n)"))
        #expect(nativeShim.contains("return chooseLocalModelStatus"))
        #expect(nativeShim.contains("return QStringLiteral(\"%1 %2\").arg(usingModelStatusPrefix, trimmedModel)"))
        #expect(nativeShim.contains("modelStatusText(stringValue(payload, \"selectedModel\"), chooseLocalModelStatus, usingModelStatusPrefix)"))
        #expect(nativeShim.contains("currentTitle->setFixedWidth(headerTitleWidth)"))
        #expect(nativeShim.contains("modelStatus->setFixedWidth(headerTitleWidth)"))
        #expect(nativeShim.contains("QString messageRoleTitle(\n    const QString &role,\n    const QString &userRoleLabel,\n    const QString &assistantRoleLabel,\n    const QString &systemRoleLabel\n)"))
        #expect(nativeShim.contains("return userRoleLabel"))
        #expect(nativeShim.contains("return assistantRoleLabel"))
        #expect(nativeShim.contains("return systemRoleLabel"))
        #expect(nativeShim.contains("messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel)"))
        #expect(nativeShim.contains("enum class MarkdownBlockKind"))
        #expect(nativeShim.contains("QString cleanMarkdownInline(QString text)"))
        #expect(nativeShim.contains("QList<MarkdownBlock> parseMarkdownBlocks(const QString &markdown)"))
        #expect(nativeShim.contains("QLabel#markdownHeading1"))
        #expect(nativeShim.contains("QFrame#markdownQuoteRule"))
        #expect(nativeShim.contains("QFrame#markdownCodeBlock"))
        #expect(nativeShim.contains("QFrame#markdownQuoteRule { background: %1; border-radius: %3; }"))
        #expect(nativeShim.contains("QFrame#markdownCodeBlock { background: %2; border-radius: %4; }"))
        #expect(nativeShim.contains(".arg(quoteRule, codeBlock, markdownQuoteRuleRadius, markdownCodeBlockRadius)"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"markdownListItemSpacing\", 8))"))
        #expect(nativeShim.contains("markerLabel->setFixedWidth(intValue(style, \"markdownNumberWidth\", 26))"))
        #expect(nativeShim.contains("const int verticalPadding = intValue(style, \"markdownQuoteVerticalPadding\", 2)"))
        #expect(nativeShim.contains("layout->setContentsMargins(0, verticalPadding, 0, verticalPadding)"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"markdownQuoteSpacing\", 9))"))
        #expect(nativeShim.contains("rule->setFixedWidth(intValue(style, \"markdownQuoteRuleWidth\", 3))"))
        #expect(nativeShim.contains("const int codeBlockPadding = intValue(style, \"markdownCodeBlockPadding\", 10)"))
        #expect(nativeShim.contains("layout->setContentsMargins(codeBlockPadding, codeBlockPadding, codeBlockPadding, codeBlockPadding)"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"markdownCodeBlockSpacing\", 7))"))
        #expect(nativeShim.contains("QWidget *markdownMessageWidget(const QString &markdown, const QJsonObject &style)"))
        #expect(nativeShim.contains("layout->setContentsMargins(0, 0, 0, 0)"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"markdownBlockSpacing\", 9))"))
        #expect(nativeShim.contains("addMarkdownBlocks(layout, markdown, style)"))
        #expect(nativeShim.contains("layout->addWidget(markdownMessageWidget(stringValue(message, \"content\"), style))"))
        #expect(!nativeShim.contains("layout->setContentsMargins(10, 10, 10, 10)"))
        #expect(!nativeShim.contains("layout->setSpacing(7)"))
        #expect(!nativeShim.contains("layout->setSpacing(9)"))
        #expect(!nativeShim.contains("layout->setContentsMargins(0, 2, 0, 2)"))
        #expect(!nativeShim.contains("rule->setFixedWidth(3)"))
        #expect(!nativeShim.contains("? 26 : 14"))
        #expect(nativeShim.contains("role == QStringLiteral(\"user\") ? QStringLiteral(\"messageUserRole\") : QStringLiteral(\"messageRole\")"))
        #expect(!nativeShim.contains("border-radius: 10px;"))
        #expect(!nativeShim.contains("border-radius: 8px;"))
        #expect(!nativeShim.contains("border-radius: 7px;"))
        #expect(!nativeShim.contains("border-radius: 1px;"))
        #expect(!nativeShim.contains("layout->setContentsMargins(13, 13, 13, 13)"))
        #expect(nativeShim.contains("QIcon promptButtonIcon(const QString &systemImage)"))
        #expect(nativeShim.contains("const QString normalized = systemImage.trimmed().toLower()"))
        #expect(nativeShim.contains("QString promptKind(const QJsonValue &value)"))
        #expect(nativeShim.contains("return stringValue(value.toObject(), \"kind\").trimmed().toLower()"))
        #expect(nativeShim.contains("if (kind == QStringLiteral(\"question\"))"))
        #expect(nativeShim.contains("return QStringLiteral(\"questionmark.circle\")"))
        #expect(nativeShim.contains("if (kind == QStringLiteral(\"action\"))"))
        #expect(nativeShim.contains("return QStringLiteral(\"lightbulb.circle\")"))
        #expect(nativeShim.contains("QStringLiteral(\"help-about-symbolic\")"))
        #expect(nativeShim.contains("QStringLiteral(\"dialog-information-symbolic\")"))
        #expect(nativeShim.contains("QStringLiteral(\"starred-symbolic\")"))
        #expect(nativeShim.contains("QStyle::SP_DialogYesButton"))
        #expect(nativeShim.contains("QLabel *iconLabel(const QIcon &icon, const QString &objectName, const QJsonObject &style)"))
        #expect(nativeShim.contains("QLabel *promptIcon = iconLabel(promptButtonIcon(systemImage), QStringLiteral(\"promptButtonIcon\"), style)"))
        #expect(nativeShim.contains("QLabel *promptText = label(prompt, QStringLiteral(\"promptButtonText\"))"))
        #expect(!nativeShim.contains("promptCardPrefix()"))
        #expect(!nativeShim.contains("new QPushButton(QStringLiteral(\"%1%2\").arg(promptCardPrefix(), prompt))"))
        #expect(!nativeShim.contains("layout->setContentsMargins(26, 26, 26, 26)"))
        #expect(!nativeShim.contains("promptList->setSpacing(10)"))
        #expect(!nativeShim.contains("button->setMinimumHeight(48)"))
        #expect(!nativeShim.contains("button->setFixedWidth(620)"))
        #expect(!nativeShim.contains("padding: 9px 12px"))
        #expect(!nativeShim.contains("border-radius: 7px; padding: 7px;"))
        #expect(!nativeShim.contains("padding: 2px 6px"))
        #expect(!nativeShim.contains("emptyState->setMaximumWidth(680)"))
        #expect(!nativeShim.contains("role.toUpper()"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.noModelsTitle)"))
        #expect(nativeShim.contains("stringValue(payload, \"noModelsTitle\", QStringLiteral(\"No models detected\"))"))
        #expect(nativeShim.contains("models.isEmpty() ? QStringLiteral(\"statusDotWarning\") : QStringLiteral(\"statusDot\")"))
        #expect(nativeShim.contains("QFrame#statusDot, QFrame#statusDotWarning"))
        #expect(nativeShim.contains("const QString statusDotSize = cssPixels(style, \"statusDotSize\", 9)"))
        #expect(nativeShim.contains("const QString statusDotRadius = cssPixels(style, \"statusDotRadius\", 9)"))
        #expect(nativeShim.contains("QFrame#statusDot, QFrame#statusDotWarning { min-width: %1; max-width: %1; min-height: %1; max-height: %1; border-radius: %2; }"))
        #expect(!nativeShim.contains("min-width: 9px; max-width: 9px; min-height: 9px; max-height: 9px; border-radius: 4px;"))
        #expect(nativeShim.contains(".arg(statusDotSize, statusDotRadius, success, warning, canvas, warningTextFontSize)"))
        #expect(nativeShim.contains("populateModelPicker(models, stringValue(payload, \"selectedModel\"))"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"endpoint\"), endpointField->text().trimmed())"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"selectedModel\"), currentModel)"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"models\"), currentModelList(modelPicker))"))
        #expect(nativeShim.contains("QObject::connect(endpointField, &QLineEdit::editingFinished"))
        #expect(nativeShim.contains("QObject::connect(refreshButton, &QPushButton::clicked"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.emptyHistoryTitle)"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.emptyHistorySubtitle)"))
        #expect(macOSRootView.contains("Button(EnchantedCopy.deleteChatTitle)"))
        #expect(macOSRootView.contains("model.deleteSelectedConversation()"))
        #expect(macOSRootView.contains("Button(EnchantedCopy.clearAllTitle)"))
        #expect(macOSRootView.contains("model.deleteAllConversations()"))
        #expect(nativeShim.contains("QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle, const QJsonObject &style)"))
        #expect(nativeShim.contains("const int emptyHistoryPadding = intValue(style, \"emptyHistoryPadding\", 12)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        emptyHistoryPadding,\n        emptyHistoryPadding,\n        emptyHistoryPadding,\n        emptyHistoryPadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"emptyHistorySpacing\", 8))"))
        #expect(nativeShim.contains("emptyHistoryWidget(\n        stringValue(payload, \"emptyHistoryTitle\", QStringLiteral(\"No saved chats yet\")),\n        stringValue(payload, \"emptyHistorySubtitle\", QStringLiteral(\"Start a chat and it will be saved locally.\")),\n        style\n    )"))
        #expect(!nativeShim.contains("QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle)"))
        #expect(!nativeShim.contains("layout->setContentsMargins(12, 12, 12, 12)"))
        #expect(!nativeShim.contains("layout->setSpacing(8)"))
        #expect(nativeShim.contains("stringValue(payload, \"emptyHistoryTitle\", QStringLiteral(\"No saved chats yet\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"emptyHistorySubtitle\", QStringLiteral(\"Start a chat and it will be saved locally.\"))"))
        #expect(macOSRootView.contains(".foregroundColor(isSelected ? .white : QuillColors.ink)"))
        #expect(macOSRootView.contains(".foregroundColor(isSelected ? QuillColors.selectedMuted : QuillColors.muted)"))
        #expect(macOSRootView.contains(".background(isSelected ? QuillColors.primary : QuillColors.card)"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.composerEditorRadius"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageBubbleRadius"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownBlockSpacing"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownListItemSpacing"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownNumberWidth"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownQuoteSpacing"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownQuoteRuleWidth"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownQuoteVerticalPadding"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownCodeBlockSpacing"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownCodeBlockPadding"))
        #expect(macOSMarkdownRendering.contains("EnchantedVisualMetrics.markdownCodeBlockRadius"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.messageBodyFontSize"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.markdownHeading1FontSize"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.markdownHeading2FontSize"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.markdownHeadingFontSize"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.markdownCodeLanguageFontSize"))
        #expect(macOSMarkdownRendering.contains("EnchantedTypography.markdownCodeFontSize"))
        #expect(nativeShim.contains("QListWidget#conversationList::item { border-radius: %1; margin: %2 0; padding: %3; }"))
        #expect(nativeShim.contains("QFrame#conversationRow { background: %3; border-radius: %6; }"))
        #expect(nativeShim.contains("QFrame#conversationRow[active=\"true\"] { background: %5; }"))
        #expect(nativeShim.contains("QLabel#conversationTitle[active=\"true\"] { color: white; }"))
        #expect(nativeShim.contains("QLabel#conversationTitle { color: %2; font-size: %7; font-weight: %8; }"))
        #expect(nativeShim.contains("QLabel#conversationPreview { color: %4; font-size: %9; }"))
        #expect(nativeShim.contains("QLabel#conversationPreview[active=\"true\"] { color: %1; }"))
        #expect(!nativeShim.contains("QLabel#conversationPreview { color: %5; font-size: %9; }"))
        #expect(nativeShim.contains("void updateConversationSelectionStyles(QListWidget *list)"))
        #expect(nativeShim.contains("widget->setProperty(\"active\", isSelected)"))
        #expect(macOSRootView.contains("?? EnchantedCopy.newConversationTitle"))
        #expect(nativeShim.contains("QStringLiteral(\"New conversation\")"))
        #expect(!nativeShim.contains("QuillUI backend parity"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.attachmentsTitle)"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.attachTitle)"))
        #expect(macOSRootView.contains("Button(EnchantedCopy.clearAttachmentsTitle)"))
        #expect(macOSRootView.contains("private var hasAttachmentPathCandidates: Bool"))
        #expect(macOSRootView.contains("PendingImageAttachment.attachmentPathCandidates(from: model.attachmentPath)"))
        #expect(macOSRootView.contains("Text(model.isLoading ? EnchantedCopy.stopTitle : EnchantedCopy.sendTitle)"))
        #expect(macOSRootView.contains(".background(model.isLoading ? QuillColors.warning : QuillColors.primary)"))
        #expect(macOSRootView.contains(".dropDestination(for: URL.self)"))
        #expect(macOSRootView.contains("model.addAttachments(urls: urls)"))
        #expect(macOSRootView.contains("model.isAttachmentDropTargeted = isTargeted"))
        #expect(imageAttachmentSource.contains("EnchantedCopy.attachmentDefaultPrompt"))
        #expect(imageAttachmentSource.contains("EnchantedCopy.attachmentSummaryTitle"))
        #expect(nativeSupport.contains("inline bool jsonBoolValue("))
        #expect(nativeShim.contains("stringValue(payload, \"attachTitle\", QStringLiteral(\"Attach\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"clearAttachmentsTitle\", QStringLiteral(\"Clear\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentsClearedStatus\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Attachments cleared\")"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentRemovedEmptyStatus\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Ready\")"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentsTitle\", QStringLiteral(\"Attachments\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentDefaultPrompt\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Describe this image.\")"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentDefaultPromptPlural\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Describe these images.\")"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentSummaryTitle\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"[Attached images]\")"))
        #expect(nativeShim.contains("QPushButton *clearAttachmentsButton"))
        #expect(nativeShim.contains("QString attachmentDefaultPromptForCount("))
        #expect(nativeShim.contains("QString attachmentDisplayContent("))
        #expect(nativeShim.contains("QStringList normalizedAttachmentPaths("))
        #expect(nativeShim.contains("QStringList attachmentPathCandidatesFromInput(const QString &rawText)"))
        #expect(nativeShim.contains("addPendingAttachmentPaths(rawPaths)"))
        #expect(nativeShim.contains("QStringList attachmentCandidatePathsFromMimeData(const QMimeData *mimeData)"))
        #expect(nativeShim.contains("QString attachmentSummaryForPaths("))
        #expect(nativeShim.contains("QString formattedAttachmentByteCount(qint64 byteCount)"))
        #expect(nativeShim.contains("QString attachmentDisplaySize(const QString &rawPath)"))
        #expect(nativeShim.contains("#include <QDir>"))
        #expect(nativeShim.contains("#include <QMimeData>"))
        #expect(nativeShim.contains("#include <QStringList>"))
        #expect(nativeShim.contains("const qint64 attachmentMaxByteCount = 20 * 1024 * 1024"))
        #expect(nativeShim.contains("struct AttachmentPathValidation"))
        #expect(nativeShim.contains("QStringList supportedAttachmentExtensions()"))
        #expect(nativeShim.contains("QStringLiteral(\"tif\")"))
        #expect(nativeShim.contains("QStringLiteral(\"tiff\")"))
        #expect(nativeShim.contains("QString normalizedAttachmentPath(const QString &rawPath)"))
        #expect(nativeShim.contains("QDir::homePath()"))
        #expect(nativeShim.contains("AttachmentPathValidation validatedAttachmentPaths(const QStringList &rawPaths)"))
        #expect(nativeShim.contains("const AttachmentPathValidation validation = validatedAttachmentPaths(rawPaths)"))
        #expect(nativeShim.contains("is not a supported image attachment."))
        #expect(nativeShim.contains("Could not read image attachment at %1."))
        #expect(nativeShim.contains("is too large to attach (%2)."))
        #expect(nativeShim.contains("formattedAttachmentByteCount(byteCount)"))
        #expect(!nativeShim.contains("QStringLiteral(\"TB\")"))
        #expect(nativeShim.contains("statusText->setText(validation.lastError)"))
        #expect(nativeShim.contains("const QString displaySize = attachmentDisplaySize(path)"))
        #expect(nativeShim.contains("QStringLiteral(\"- %1 (%2)\").arg(displayName, displaySize)"))
        #expect(imageAttachmentSource.contains("public static let maxByteCount: Int64 = 20 * 1024 * 1024"))
        #expect(imageAttachmentSource.contains("public static let supportedExtensions: Set<String> = [\"gif\", \"heic\", \"jpeg\", \"jpg\", \"png\", \"tif\", \"tiff\", \"webp\"]"))
        #expect(imageAttachmentSource.contains("case \"tif\", \"tiff\":"))
        #expect(imageAttachmentSource.contains("return \"image/tiff\""))
        #expect(imageAttachmentSource.contains("case .unsupportedFileType(let name):"))
        #expect(imageAttachmentSource.contains("case .unreadableFile(let path):"))
        #expect(imageAttachmentSource.contains("case .fileTooLarge(let name, let byteCount):"))
        #expect(imageAttachmentSource.contains("public static func attachmentPathCandidates(from rawPaths: String) -> [String]"))
        #expect(imageAttachmentSource.contains("public static func fileURLs(from rawPaths: String) -> [URL]"))
        #expect(imageAttachmentSource.contains("public static func fileURL(from rawPath: String) -> URL?"))
        #expect(imageAttachmentSource.contains("public static func attachmentSummary(for attachments: [PendingImageAttachment]) -> String"))
        #expect(imageAttachmentSource.contains("public static func formatByteCount(_ byteCount: Int64) -> String"))
        #expect(nativeShim.contains("class AttachmentDropFrame final : public QFrame"))
        #expect(nativeShim.contains("setAcceptDrops(true)"))
        #expect(nativeShim.contains("attachmentPath->setAcceptDrops(false)"))
        #expect(nativeShim.contains("mimeData->urls()"))
        #expect(nativeShim.contains("url.toLocalFile()"))
        #expect(nativeShim.contains("attachmentCandidatePathsFromMimeData(event->mimeData())"))
        #expect(macOSRootView.contains("if model.isAttachmentDropTargeted"))
        #expect(macOSRootView.contains("Text(EnchantedCopy.dropTargetTitle)"))
        #expect(nativeShim.contains("QFrame#dropTarget { background: transparent; border: 0; }"))
        #expect(nativeShim.contains("QFrame#dropTarget[dragActive=\"true\"]"))
        #expect(nativeShim.contains("QFrame#dropTargetHint { background: %1; border: 1px solid %2; border-radius: %5; }"))
        #expect(nativeShim.contains("QLabel#dropTargetLabel { color: %3; font-size: %6; }"))
        #expect(nativeShim.contains("QSplitter::handle { background: %4; }"))
        #expect(nativeShim.contains("void setDropHint(QWidget *hint)"))
        #expect(nativeShim.contains("dropHint->setVisible(property(\"dragActive\").toBool())"))
        #expect(nativeShim.contains("dropHint->setVisible(active)"))
        #expect(nativeShim.contains("stringValue(payload, \"dropTargetTitle\", QStringLiteral(\"Drop image files to attach\"))"))
        #expect(runtime.contains("dropTargetTitle: EnchantedCopy.dropTargetTitle"))
        #expect(nativeShim.contains("QStringList pendingAttachmentPaths"))
        #expect(nativeShim.contains("QScrollArea *attachmentScrollArea"))
        #expect(nativeShim.contains("QHBoxLayout *attachmentChipListLayout"))
        #expect(nativeShim.contains("QPushButton *removeAttachmentButton"))
        #expect(nativeShim.contains("removeAttachmentButton->setObjectName(QStringLiteral(\"chipRemoveButton\"))"))
        #expect(nativeShim.contains("QLabel *attachmentIcon = iconLabel("))
        #expect(nativeShim.contains("attachmentChipLayout->addWidget(attachmentIcon)"))
        #expect(nativeShim.contains("applyButtonIconSize(removeAttachmentButton, style)"))
        #expect(nativeShim.contains("removeAttachmentButton->setToolTip(removeAttachmentTooltip)"))
        #expect(nativeShim.contains("removeAttachmentButton->setAccessibleName(removeAttachmentTooltip)"))
        #expect(runtime.contains("attachmentRemoveButtonWidth: EnchantedVisualMetrics.attachmentRemoveButtonWidth"))
        #expect(nativeShim.contains("removeAttachmentButton->setFixedWidth(intValue(style, \"attachmentRemoveButtonWidth\", 28))"))
        #expect(!nativeShim.contains("removeAttachmentButton->setFixedWidth(28)"))
        #expect(nativeShim.contains("pendingAttachmentPaths.removeAll(path)"))
        #expect(nativeShim.contains("? attachmentRemovedEmptyStatus"))
        #expect(nativeShim.contains("attachmentReadyStatus(\n                            pendingAttachmentPaths.count(),\n                            imageReadyStatusSingular,\n                            imageReadyStatusPluralUnit\n                        )"))
        #expect(nativeShim.contains("attachmentReadyStatus(\n            pendingAttachmentPaths.count(),\n            imageReadyStatusSingular,\n            imageReadyStatusPluralUnit\n        )"))
        #expect(!nativeShim.contains(": attachmentReadyStatus(pendingAttachmentPaths.count())"))
        #expect(nativeShim.contains("QTimer::singleShot(0, attachmentTray, renderAttachmentTray)"))
        #expect(nativeShim.contains("clearLayout(attachmentChipListLayout)"))
        #expect(nativeShim.contains("boolValue(payload, \"isLoading\", false)"))
        #expect(nativeShim.contains("stringValue(payload, \"sendTitle\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Send\")"))
        #expect(nativeShim.contains("stringValue(payload, \"stopTitle\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Stop\")"))
        #expect(nativeShim.contains("stringValue(payload, \"stoppingStatus\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Stopping...\")"))
        #expect(nativeShim.contains("stringValue(payload, \"removeAttachmentTooltip\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"Remove attachment\")"))
        #expect(nativeShim.contains("stringValue(payload, \"imageReadyStatusSingular\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"1 image ready to send\")"))
        #expect(nativeShim.contains("stringValue(payload, \"imageReadyStatusPluralUnit\")"))
        #expect(!nativeShim.contains("QStringLiteral(\"images ready to send\")"))
        #expect(nativeShim.contains("#include <QIcon>"))
        #expect(nativeShim.contains("#include <QPixmap>"))
        #expect(nativeShim.contains("#include <QStyle>"))
        #expect(nativeShim.contains("QIcon themedActionIcon("))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.primaryButtonIconSpacing"))
        #expect(nativeShim.contains("int buttonIconSize(const QJsonObject &style)"))
        #expect(nativeShim.contains("return intValue(style, \"actionButtonIconSize\", 16)"))
        #expect(nativeShim.contains("void applyButtonIconSize(QPushButton *button, const QJsonObject &style)"))
        #expect(nativeShim.contains("const int iconSize = buttonIconSize(style)"))
        #expect(nativeShim.contains("button->setIconSize(QSize(iconSize, iconSize))"))
        #expect(nativeShim.contains("applyButtonIconSize(newConversationButton, style)"))
        #expect(nativeShim.contains("applyButtonIconSize(attachButton, style)"))
        #expect(nativeShim.contains("applyButtonIconSize(sendButton, style)"))
        #expect(nativeShim.contains("void updateSendButtonPresentation("))
        #expect(nativeShim.contains("updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle)"))
        #expect(nativeShim.contains("button->setProperty(\"loading\", isLoading)"))
        #expect(nativeShim.contains("button->setText(isLoading ? stopTitle : sendTitle)"))
        #expect(nativeShim.components(separatedBy: "button->setProperty(\"loading\", isLoading)").count == 2)
        #expect(nativeShim.components(separatedBy: "button->setText(isLoading ? stopTitle : sendTitle)").count == 2)
        #expect(runtime.contains("composerSendButtonMinWidth: EnchantedVisualMetrics.composerSendButtonMinWidth"))
        #expect(nativeShim.contains("sendButton->setMinimumWidth(intValue(style, \"composerSendButtonMinWidth\", 86))"))
        #expect(!nativeShim.contains("sendButton->setMinimumWidth(86)"))
        #expect(nativeShim.contains("QPushButton#sendButton[loading=\"true\"]"))
        #expect(nativeShim.contains("const bool hasPendingAttachments = !pendingAttachmentPaths.isEmpty()"))
        #expect(nativeShim.contains("bool hasAttachmentPathCandidates(const QLineEdit *field)"))
        #expect(nativeShim.contains("const bool hasAttachmentPathInput = hasAttachmentPathCandidates(attachmentPath)"))
        #expect(nativeShim.contains("attachButton->setEnabled(hasAttachmentPathInput)"))
        #expect(nativeShim.contains("clearAttachmentsButton->setEnabled(hasAttachmentPathInput || hasPendingAttachments)"))
        #expect(nativeShim.contains("sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || hasPendingAttachments)"))
        #expect(nativeShim.contains("statusText->setText(stoppingStatus)"))
        #expect(nativeShim.contains("clearAttachmentState(attachmentsClearedStatus)"))
        #expect(nativeShim.contains("clearAttachmentState(QString())"))
        #expect(nativeShim.contains("refreshButton->setEnabled(!isLoading)"))
        #expect(nativeShim.contains("isLoading = boolValue(payload, \"isLoading\", false)"))
        #expect(nativeShim.contains("refreshStyle(sendButton)"))
        #expect(nativeShim.contains("refreshStyle(sendButton);\n        updateComposerControlState()"))
        #expect(nativeShim.contains("modelStatus->setText(modelStatusText(model, chooseLocalModelStatus, usingModelStatusPrefix))"))
        #expect(nativeShim.contains("std::function<bool(const QString &, const QString &, const QString &, const QStringList &)> requestHistoryAction"))
        #expect(nativeShim.contains("QStringLiteral(\"sendMessage\"),"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"messageText\"), trimmedMessageText)"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"attachmentPaths\"), encodedAttachmentPaths)"))
        #expect(nativeShim.contains("attachmentSummaryForPaths(pendingAttachmentPaths)"))
        #expect(nativeShim.contains("pendingAttachmentPaths = normalizedAttachmentPaths(pendingAttachmentPaths)"))
        #expect(nativeShim.contains("dropTarget->setDropHandler"))
        #expect(nativeShim.contains("pendingAttachmentPaths.append(path)"))
        #expect(nativeShim.contains("auto attachPendingPath = [&]()"))
        #expect(nativeShim.contains("QObject::connect(attachButton, &QPushButton::clicked, attachPendingPath)"))
        #expect(nativeShim.contains("QObject::connect(attachmentPath, &QLineEdit::returnPressed, attachPendingPath)"))
        #expect(nativeShim.contains("appendComposerMessage(promptEditor->toPlainText())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"newConversation\"), QString(), QString(), QStringList())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"deleteConversation\"), deletedConversationID, QString(), QStringList())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"deleteAllConversations\"), QString(), QString(), QStringList())"))
        #expect(runtime.contains("OllamaClient(baseURL: endpoint).chat("))
        #expect(runtime.contains("context.insert(ChatMessage("))
        #expect(runtime.contains("role: .assistant"))
        #expect(runtime.contains("EnchantedCopy.emptyOllamaResponse"))
        #expect(nativeShim.contains("void removeConversationRow(QListWidget *list, int row)"))
        #expect(nativeShim.contains("deleteButton->setEnabled(conversationList->currentItem() != nullptr)"))
        #expect(nativeShim.contains("const bool hasConversations = conversationList->count() > 0"))
        #expect(nativeShim.contains("clearAllButton->setEnabled(hasConversations)"))
        #expect(nativeShim.contains("conversationList->setVisible(hasConversations)"))
        #expect(nativeShim.contains("emptyHistory->setVisible(!hasConversations)"))
        #expect(nativeShim.contains("conversationList->setCurrentRow(-1)"))
        #expect(nativeShim.contains("updateConversationSelectionStyles(conversationList)"))
        #expect(nativeShim.contains("QObject::connect(deleteButton, &QPushButton::clicked"))
        #expect(nativeShim.contains("removeConversationRow(conversationList, deletedRow)"))
        #expect(nativeShim.contains("QObject::connect(clearAllButton, &QPushButton::clicked"))
        #expect(nativeShim.contains("conversationList->clear()"))
        #expect(nativeShim.contains("QObject::connect(clearAttachmentsButton, &QPushButton::clicked"))
        #expect(nativeShim.contains("QObject::connect(promptEditor, &QPlainTextEdit::textChanged"))
        #expect(nativeShim.contains("emptyStateTitle"))
        #expect(nativeShim.contains("emptyStateSubtitle"))
        #expect(nativeShim.contains("promptAction(prompt)"))
        #expect(nativeShim.contains("appendComposerMessage(promptEditor->toPlainText())"))
        #expect(nativeShim.contains("renderMessageSet(selectedMessages)"))
        #expect(nativeShim.contains("renderMessages("))
        #expect(nativeShim.contains("QObject::connect(sendButton"))
        #expect(nativeSupport.contains("inline void clearLayout(QLayout *layout)"))
        #expect(nativeSupport.contains("inline bool parseJsonObjectPayload("))
        #expect(nativeSupport.contains("inline bool jsonBoolValue("))
        #expect(nativeSupport.contains("inline QByteArray executableNameBytes("))
        #expect(nativeSupport.contains("inline QSize minimumWindowSize("))
        #expect(nativeSupport.contains("inline QSize defaultWindowSize("))
        #expect(nativeSupport.contains("inline void scrollAreaToBottomLater(QScrollArea *scrollArea)"))
        #expect(nativeSupport.contains("QScrollBar *scrollBar = scrollArea->verticalScrollBar()"))
        #expect(nativeSupport.contains("scrollBar->setValue(scrollBar->maximum())"))
        #expect(nativeSupport.contains("%s: invalid payload JSON at offset %lld: %s\\n"))
        #expect(nativeShim.contains("parseJsonObjectPayload("))
        #expect(nativeShim.contains("QuillQtWidgets::executableNameBytes(argc, argv, \"quill-enchanted-qt\")"))
        #expect(nativeShim.contains("executableName.constData()"))
        #expect(nativeShim.contains("QuillQtWidgets::minimumWindowSize(payload, 980, 680)"))
        #expect(nativeShim.contains("QuillQtWidgets::defaultWindowSize(payload, minimumWindowSize)"))
        #expect(!nativeShim.contains("QSize resolvedMinimumWindowSize"))
        #expect(!nativeShim.contains("QSize resolvedDefaultWindowSize"))
        #expect(nativeShim.contains("clearLayout(messageLayout)"))
        #expect(!nativeShim.contains("void clearLayout(QLayout *layout)"))
    }

    private func temporaryFile(name: String, bytes: [UInt8]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let manifest = directory.appendingPathComponent("Package.swift")
            let sources = directory.appendingPathComponent("Sources")
            if FileManager.default.fileExists(atPath: manifest.path)
                && FileManager.default.fileExists(atPath: sources.path)
            {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw CoreContractMatrixTestError.packageRootNotFound
    }

    private func expectContains(_ source: String, _ needle: String) {
        #expect(source.contains(needle))
    }

    private func expectDoesNotContain(_ source: String, _ needle: String) {
        #expect(!source.contains(needle))
    }
}

private enum CoreContractMatrixTestError: Error {
    case packageRootNotFound
}

private let enchantedEmptyConversationPrompts: [String] = [
    "How to center div in HTML?",
    "How to do personal taxes in USA?",
    "Explain supercomputers like I'm five years old",
    "Write a text message asking a friend to be my plus-one at a wedding"
]

struct TextCase: Sendable {
    var input: String
    var expected: String
}

struct BlockCase: Sendable {
    var markdown: String
    var kind: MarkdownBlockKind
    var text: String
}

struct ByteCountCase: Sendable {
    var byteCount: Int64
    var expected: String
}

struct ImageExtensionCase: Sendable {
    var fileExtension: String
    var mediaType: String
}

struct PathCase: Sendable {
    var rawPath: String
    var expectedSuffix: String
}

private let titleInputs: [String] = [
    "",
    "   ",
    "\n\n",
    "Short title",
    "  Padded title  ",
    "First line\nSecond line",
    "First line\r\nSecond line",
    "A very long prompt that should be shortened into a compact conversation title",
    "Symbols !@#$%^&*() stay readable",
    "中文 title remains nonempty"
] + (0..<90).map { index in
    "  Generated title case \(index)\nwith continuation text that is intentionally long enough to trim  "
}

private let inlineCases: [TextCase] = [
    TextCase(input: "**bold**", expected: "bold"),
    TextCase(input: "__strong__", expected: "strong"),
    TextCase(input: "`code`", expected: "code"),
    TextCase(input: "~~gone~~", expected: "gone"),
    TextCase(input: "[QuillUI](https://example.com)", expected: "QuillUI (https://example.com)"),
    TextCase(input: "mix **bold** and `code`", expected: "mix bold and code"),
    TextCase(input: "  spaced **text**  ", expected: "spaced text"),
    TextCase(input: "[Docs](https://example.com/docs) **ship**", expected: "Docs (https://example.com/docs) ship")
] + (0..<62).map { index in
    TextCase(input: "**Generated \(index)** with `inline` markers", expected: "Generated \(index) with inline markers")
}

private let blockCases: [BlockCase] = [
    BlockCase(markdown: "# Heading", kind: .heading(level: 1), text: "Heading"),
    BlockCase(markdown: "## Heading", kind: .heading(level: 2), text: "Heading"),
    BlockCase(markdown: "###### Heading", kind: .heading(level: 6), text: "Heading"),
    BlockCase(markdown: "- Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "* Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "+ Item", kind: .unorderedListItem, text: "Item"),
    BlockCase(markdown: "1. Item", kind: .orderedListItem(number: 1), text: "Item"),
    BlockCase(markdown: "42. Item", kind: .orderedListItem(number: 42), text: "Item"),
    BlockCase(markdown: "> Quoted", kind: .quote, text: "Quoted"),
    BlockCase(markdown: "Plain paragraph", kind: .paragraph, text: "Plain paragraph")
] + (0..<40).map { index in
    BlockCase(markdown: "\(index + 1). Generated item \(index)", kind: .orderedListItem(number: index + 1), text: "Generated item \(index)")
}

private let streamContentCases: [TextCase] = (0..<70).map { index in
    let content = "chunk-\(index)"
    return TextCase(
        input: #"{"message":{"role":"assistant","content":"\#(content)"},"done":false}"#,
        expected: content
    )
}

private let byteCountCases: [ByteCountCase] = [
    ByteCountCase(byteCount: 0, expected: "0 bytes"),
    ByteCountCase(byteCount: 1, expected: "1 bytes"),
    ByteCountCase(byteCount: 1023, expected: "1023 bytes"),
    ByteCountCase(byteCount: 1024, expected: "1.0 KB"),
    ByteCountCase(byteCount: 1536, expected: "1.5 KB"),
    ByteCountCase(byteCount: 1_048_576, expected: "1.0 MB"),
    ByteCountCase(byteCount: 1_572_864, expected: "1.5 MB"),
    ByteCountCase(byteCount: 1_073_741_824, expected: "1.0 GB"),
    ByteCountCase(byteCount: 1_099_511_627_776, expected: "1024.0 GB")
] + (1...32).map { index in
    ByteCountCase(byteCount: Int64(index * 1024), expected: "\(index).0 KB")
}

private let imageExtensionCases: [ImageExtensionCase] = [
    ImageExtensionCase(fileExtension: "gif", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "heic", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "jpeg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "jpg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "png", mediaType: "image/png"),
    ImageExtensionCase(fileExtension: "tif", mediaType: "image/tiff"),
    ImageExtensionCase(fileExtension: "tiff", mediaType: "image/tiff"),
    ImageExtensionCase(fileExtension: "webp", mediaType: "image/webp"),
    ImageExtensionCase(fileExtension: "GIF", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "HEIC", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "JPEG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "JPG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "PNG", mediaType: "image/png"),
    ImageExtensionCase(fileExtension: "TIF", mediaType: "image/tiff"),
    ImageExtensionCase(fileExtension: "TIFF", mediaType: "image/tiff"),
    ImageExtensionCase(fileExtension: "WEBP", mediaType: "image/webp")
]

private let unsupportedImageExtensions = [
    "txt", "pdf", "svg", "bmp", "tga", "mp4", "mov", "json", "xml", "html",
    "md", "csv", "zip", "tar", "gz", "swift", "heif", "avif", "ico", "psd"
]

private let pathCases: [PathCase] = [
    PathCase(rawPath: "/tmp/image.png", expectedSuffix: "/tmp/image.png"),
    PathCase(rawPath: " /tmp/spaced.jpg ", expectedSuffix: "/tmp/spaced.jpg"),
    PathCase(rawPath: "file:///tmp/file-url.webp", expectedSuffix: "/tmp/file-url.webp"),
    PathCase(rawPath: "~/picture.gif", expectedSuffix: "/picture.gif")
] + (0..<26).map { index in
    PathCase(rawPath: "/tmp/generated-\(index).png", expectedSuffix: "/tmp/generated-\(index).png")
}
