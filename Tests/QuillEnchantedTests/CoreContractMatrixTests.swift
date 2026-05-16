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

    @Test("normalizes attachment paths", arguments: pathCases)
    func pathNormalizationContracts(testCase: PathCase) throws {
        let url = try #require(PendingImageAttachment.fileURL(from: testCase.rawPath))

        #expect(url.path.hasSuffix(testCase.expectedSuffix))
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
        #expect(manifest.contains("dependencies: [\"QuillEnchantedData\"]"))
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
        #expect(upstreamSlice.contains("EnchantedVisualMetrics.messageMaxWidth"))
        #expect(runtime.contains("import QuillEnchantedData"))
        #expect(runtime.contains("import QuillEnchantedShared"))
        #expect(genericQtRuntime.contains("import QuillEnchantedShared"))
        #expect(genericQtRuntime.contains("minimumWidth: EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(genericQtRuntime.contains("minimumHeight: EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(genericQtRuntime.contains("defaultWidth: EnchantedVisualMetrics.defaultWindowWidth"))
        #expect(genericQtRuntime.contains("defaultHeight: EnchantedVisualMetrics.defaultWindowHeight"))
        #expect(genericQtRuntime.contains("sidebarWidth: EnchantedVisualMetrics.sidebarWidth"))
        #expect(genericQtRuntime.contains("detailWidth: EnchantedVisualMetrics.detailWidth"))
        #expect(runtime.contains("EnchantedModelContext.default()"))
        #expect(runtime.contains("QuillEnchantedQtSnapshot.preview"))
        #expect(runtime.contains("QuillEnchantedQtSnapshot.persisted("))
        #expect(runtime.contains("quill_enchanted_qt_run_app_json"))
        #expect(runtime.contains("quill_enchanted_qt_perform_action_json"))
        #expect(runtime.contains("quill_enchanted_qt_free_string"))
        #expect(runtime.contains("windowTitle: \"Quill Enchanted\""))
        #expect(runtime.contains("sidebarSubtitle: \"QuillUI Linux preview\""))
        #expect(runtime.contains("noModelsTitle: \"No models detected\""))
        #expect(runtime.contains("attachTitle: \"Attach\""))
        #expect(runtime.contains("clearAttachmentsTitle: \"Clear\""))
        #expect(runtime.contains("attachmentsTitle: \"Attachments\""))
        #expect(runtime.contains("attachmentDefaultPrompt: \"Describe this image.\""))
        #expect(runtime.contains("attachmentSummaryTitle: \"[Attached images]\""))
        #expect(runtime.contains("sendTitle: \"Send\""))
        #expect(runtime.contains("stopTitle: \"Stop\""))
        #expect(runtime.contains("stoppingStatus: \"Stopping...\""))
        #expect(runtime.contains("isLoading: false"))
        #expect(runtime.contains("selectedModel: \"llama3.1:8b\""))
        #expect(runtime.contains("emptyHistoryTitle: \"No saved chats yet\""))
        #expect(runtime.contains("emptyHistorySubtitle: \"Start a chat and it will be saved locally.\""))
        #expect(runtime.contains("emptyStateTitle: \"Ask your local model\""))
        #expect(runtime.contains("emptyStateSubtitle: \"This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.\""))
        #expect(runtime.contains("prompts: EnchantedPromptCatalog.emptyConversationTitles"))
        #expect(runtime.contains("var messages: [Message]? = nil"))
        #expect(runtime.contains("messages: attachmentConversationMessages"))
        #expect(runtime.contains("canvasColor: \"#F6F7F2\""))
        #expect(runtime.contains("warningColor: \"#B86A31\""))
        #expect(runtime.contains("systemColor: \"#E8EDF3\""))
        #expect(runtime.contains("quoteRuleColor: \"#8AA5B7\""))
        #expect(runtime.contains("codeBlockColor: \"#EEF3F4\""))
        #expect(runtime.contains("dividerColor: \"#D8DDD5\""))
        #expect(runtime.contains("cardBorderColor: \"#E0E5DD\""))
        #expect(runtime.contains("messageBorderColor: \"#D4DFE8\""))
        #expect(runtime.contains("controlBorderColor: \"#CDD5CA\""))
        #expect(runtime.contains("dropTargetBorderColor: \"#C8DED3\""))
        #expect(runtime.contains("disabledButtonBackgroundColor: \"#AAB5BE\""))
        #expect(runtime.contains("disabledButtonForegroundColor: \"#F4F6F7\""))
        #expect(runtime.contains("disabledTextColor: \"#9CA6AD\""))
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
        #expect(runtime.contains("sidebarPadding: 18"))
        #expect(runtime.contains("sidebarSpacing: 14"))
        #expect(runtime.contains("statusRowSpacing: 8"))
        #expect(runtime.contains("statusDotSize: 9"))
        #expect(runtime.contains("statusDotRadius: 9"))
        #expect(runtime.contains("conversationRowPadding: 11"))
        #expect(runtime.contains("conversationRowSpacing: 5"))
        #expect(runtime.contains("conversationRowRadius: 8"))
        #expect(runtime.contains("conversationListItemRadius: 8"))
        #expect(runtime.contains("conversationListItemVerticalMargin: 2"))
        #expect(runtime.contains("conversationListItemPadding: 8"))
        #expect(runtime.contains("conversationActionsSpacing: 8"))
        #expect(runtime.contains("attachmentChipPadding: 8"))
        #expect(runtime.contains("attachmentChipSpacing: 8"))
        #expect(runtime.contains("attachmentChipTextSpacing: 2"))
        #expect(runtime.contains("attachmentChipRadius: 8"))
        #expect(runtime.contains("attachmentTraySpacing: 7"))
        #expect(runtime.contains("attachmentTrayChipSpacing: 8"))
        #expect(runtime.contains("attachmentInputHorizontalPadding: 10"))
        #expect(runtime.contains("attachmentInputVerticalPadding: 7"))
        #expect(runtime.contains("attachmentInputSpacing: 8"))
        #expect(runtime.contains("headerTitleWidth: EnchantedVisualMetrics.headerTitleWidth"))
        #expect(runtime.contains("headerSpacing: 12"))
        #expect(runtime.contains("headerTitleSpacing: 4"))
        #expect(runtime.contains("composerPadding: 18"))
        #expect(runtime.contains("composerSpacing: 10"))
        #expect(runtime.contains("promptRowSpacing: 12"))
        #expect(runtime.contains("composerMinHeight: EnchantedVisualMetrics.composerMinHeight"))
        #expect(runtime.contains("composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight"))
        #expect(runtime.contains("messageMaxWidth: EnchantedVisualMetrics.messageMaxWidth"))
        #expect(runtime.contains("messageSpacing: 14"))
        #expect(runtime.contains("messageBubbleRowSpacing: 10"))
        #expect(runtime.contains("messageBubblePadding: 13"))
        #expect(runtime.contains("messageBubbleSpacing: 7"))
        #expect(runtime.contains("messageBubbleRadius: 10"))
        #expect(runtime.contains("markdownBlockSpacing: 9"))
        #expect(runtime.contains("markdownListItemSpacing: 8"))
        #expect(runtime.contains("markdownNumberWidth: 26"))
        #expect(runtime.contains("markdownQuoteSpacing: 9"))
        #expect(runtime.contains("markdownQuoteRuleWidth: 3"))
        #expect(runtime.contains("markdownQuoteRuleRadius: 1"))
        #expect(runtime.contains("markdownQuoteVerticalPadding: 2"))
        #expect(runtime.contains("markdownCodeBlockSpacing: 7"))
        #expect(runtime.contains("markdownCodeBlockPadding: 10"))
        #expect(runtime.contains("markdownCodeBlockRadius: 7"))
        #expect(runtime.contains("emptyHistoryPadding: 12"))
        #expect(runtime.contains("emptyHistorySpacing: 8"))
        #expect(runtime.contains("emptyHistoryRadius: 8"))
        #expect(runtime.contains("emptyStatePadding: 26"))
        #expect(runtime.contains("emptyStateSpacing: 18"))
        #expect(runtime.contains("emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth"))
        #expect(runtime.contains("promptListSpacing: 10"))
        #expect(runtime.contains("promptButtonMinHeight: 48"))
        #expect(runtime.contains("promptButtonWidth: EnchantedVisualMetrics.promptButtonWidth"))
        #expect(runtime.contains("promptButtonPadding: 12"))
        #expect(runtime.contains("promptButtonRadius: 8"))
        #expect(runtime.contains("primaryButtonVerticalPadding: 12"))
        #expect(runtime.contains("primaryButtonHorizontalPadding: 12"))
        #expect(runtime.contains("primaryButtonRadius: 8"))
        #expect(runtime.contains("secondaryButtonVerticalPadding: 7"))
        #expect(runtime.contains("secondaryButtonHorizontalPadding: 10"))
        #expect(runtime.contains("secondaryButtonRadius: 7"))
        #expect(runtime.contains("chipRemoveButtonVerticalPadding: 2"))
        #expect(runtime.contains("chipRemoveButtonHorizontalPadding: 6"))
        #expect(runtime.contains("controlPadding: 7"))
        #expect(runtime.contains("controlRadius: 7"))
        #expect(runtime.contains("dropTargetRadius: 8"))
        #expect(runtime.contains("context.insert(ConversationDraft(title: \"New conversation\"))"))
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
        #expect(sharedPrompts.contains("public enum EnchantedVisualMetrics"))
        #expect(sharedPrompts.contains("public static let minimumWindowWidth = 980"))
        #expect(sharedPrompts.contains("public static let minimumWindowHeight = 680"))
        #expect(sharedPrompts.contains("public static let defaultWindowWidth = 1180"))
        #expect(sharedPrompts.contains("public static let defaultWindowHeight = 760"))
        #expect(sharedPrompts.contains("public static let sidebarWidth = 300"))
        #expect(sharedPrompts.contains("public static let sidebarIdealWidth = 330"))
        #expect(sharedPrompts.contains("public static let sidebarMaxWidth = 360"))
        #expect(sharedPrompts.contains("public static let detailWidth = defaultWindowWidth - sidebarWidth"))
        #expect(sharedPrompts.contains("public static let headerTitleWidth = 560"))
        #expect(sharedPrompts.contains("public static let promptButtonWidth = 620"))
        #expect(sharedPrompts.contains("public static let emptyStateMaxWidth = 680"))
        #expect(sharedPrompts.contains("public static let messageMaxWidth = 680"))
        #expect(sharedPrompts.contains("public static let composerMinWidth = 620"))
        #expect(sharedPrompts.contains("public static let composerMaxWidth = 840"))
        #expect(sharedPrompts.contains("public static let composerMinHeight = 74"))
        #expect(sharedPrompts.contains("public static let composerMaxHeight = 120"))
        #expect(sharedPrompts.contains("public enum EnchantedTypography"))
        #expect(sharedPrompts.contains("public static let rootFontSize = 14"))
        #expect(sharedPrompts.contains("public static let appTitleFontSize = 26"))
        #expect(sharedPrompts.contains("public static let chipRemoveButtonFontWeight = 700"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.sidebarWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.minimumWindowWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.minimumWindowHeight"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.headerTitleWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.promptButtonWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.emptyStateMaxWidth"))
        #expect(macOSRootView.contains("EnchantedVisualMetrics.messageMaxWidth"))
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
        #expect(nativeShim.contains("QScrollArea"))
        #expect(nativeShim.contains("styleValue(style, \"canvasColor\", \"#F6F7F2\")"))
        #expect(nativeShim.contains("styleValue(style, \"quoteRuleColor\", \"#8AA5B7\")"))
        #expect(nativeShim.contains("styleValue(style, \"codeBlockColor\", \"#EEF3F4\")"))
        #expect(nativeShim.contains("styleValue(style, \"dividerColor\", \"#D8DDD5\")"))
        #expect(nativeShim.contains("styleValue(style, \"cardBorderColor\", \"#E0E5DD\")"))
        #expect(nativeShim.contains("styleValue(style, \"messageBorderColor\", \"#D4DFE8\")"))
        #expect(nativeShim.contains("styleValue(style, \"controlBorderColor\", \"#CDD5CA\")"))
        #expect(nativeShim.contains("styleValue(style, \"dropTargetBorderColor\", \"#C8DED3\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledButtonBackgroundColor\", \"#AAB5BE\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledButtonForegroundColor\", \"#F4F6F7\")"))
        #expect(nativeShim.contains("styleValue(style, \"disabledTextColor\", \"#9CA6AD\")"))
        #expect(nativeShim.contains("intValue(style, \"sidebarWidth\", 300)"))
        #expect(nativeShim.contains("const int sidebarPadding = intValue(style, \"sidebarPadding\", 18)"))
        #expect(nativeShim.contains("sidebarLayout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding)"))
        #expect(nativeShim.contains("sidebarLayout->setSpacing(intValue(style, \"sidebarSpacing\", 14))"))
        #expect(nativeShim.contains("QFrame *conversationRowWidget(const QJsonObject &conversation, const QJsonObject &style)"))
        #expect(nativeShim.contains("const int conversationRowPadding = intValue(style, \"conversationRowPadding\", 11)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"conversationRowSpacing\", 5))"))
        #expect(nativeShim.contains("conversationRowWidget(conversation, style)"))
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
        #expect(nativeShim.contains("const int attachmentInputHorizontalPadding = intValue(style, \"attachmentInputHorizontalPadding\", 10)"))
        #expect(nativeShim.contains("const int attachmentInputVerticalPadding = intValue(style, \"attachmentInputVerticalPadding\", 7)"))
        #expect(nativeShim.contains("dropLayout->setContentsMargins(\n        attachmentInputHorizontalPadding,\n        attachmentInputVerticalPadding,\n        attachmentInputHorizontalPadding,\n        attachmentInputVerticalPadding\n    )"))
        #expect(nativeShim.contains("dropLayout->setSpacing(intValue(style, \"attachmentInputSpacing\", 8))"))
        #expect(!nativeShim.contains("dropLayout->setContentsMargins(10, 7, 10, 7)"))
        #expect(!nativeShim.contains("dropLayout->setSpacing(8)"))
        #expect(nativeShim.contains("intValue(style, \"headerTitleWidth\", 560)"))
        #expect(nativeShim.contains("statusLayout->setSpacing(intValue(style, \"statusRowSpacing\", 8))"))
        #expect(nativeShim.contains("const int statusDotSize = intValue(style, \"statusDotSize\", 9)"))
        #expect(nativeShim.contains("statusDot->setFixedSize(statusDotSize, statusDotSize)"))
        #expect(nativeShim.contains("headerLayout->setSpacing(intValue(style, \"headerSpacing\", 12))"))
        #expect(nativeShim.contains("titleLayout->setSpacing(intValue(style, \"headerTitleSpacing\", 4))"))
        #expect(nativeShim.contains("messageLayout->setSpacing(intValue(style, \"messageSpacing\", 14))"))
        #expect(nativeShim.contains("row->setSpacing(intValue(style, \"messageBubbleRowSpacing\", 10))"))
        #expect(nativeShim.contains("const int messageBubblePadding = intValue(style, \"messageBubblePadding\", 13)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"messageBubbleSpacing\", 7))"))
        #expect(nativeShim.contains("const int emptyStatePadding = intValue(style, \"emptyStatePadding\", 26)"))
        #expect(nativeShim.contains("layout->setContentsMargins(\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding\n    )"))
        #expect(nativeShim.contains("layout->setSpacing(intValue(style, \"emptyStateSpacing\", 18))"))
        #expect(nativeShim.contains("promptList->setSpacing(intValue(style, \"promptListSpacing\", 10))"))
        #expect(nativeShim.contains("button->setMinimumHeight(intValue(style, \"promptButtonMinHeight\", 48))"))
        #expect(nativeShim.contains("button->setFixedWidth(intValue(style, \"promptButtonWidth\", 620))"))
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
        #expect(nativeShim.contains("const QString conversationRowRadius = cssPixels(style, \"conversationRowRadius\", 8)"))
        #expect(nativeShim.contains("const QString conversationListItemRadius = cssPixels(style, \"conversationListItemRadius\", 8)"))
        #expect(nativeShim.contains("const QString conversationListItemVerticalMargin = cssPixels(style, \"conversationListItemVerticalMargin\", 2)"))
        #expect(nativeShim.contains("const QString conversationListItemPadding = cssPixels(style, \"conversationListItemPadding\", 8)"))
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
        #expect(nativeShim.contains("QFrame#emptyHistory { background: %1; border: 1px solid %2; border-radius: %3; }"))
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
        #expect(nativeShim.contains("QLineEdit, QComboBox, QPlainTextEdit { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }"))
        #expect(!nativeShim.contains("font-size: 14px;"))
        #expect(!nativeShim.contains("font-size: 12px;"))
        #expect(!nativeShim.contains("font-weight: 700;"))
        #expect(!nativeShim.contains("border-right: 1px solid #D8DDD5"))
        #expect(!nativeShim.contains("color: #DDEBFA; font-size: 12px;"))
        #expect(!nativeShim.contains("border: 1px solid #E0E5DD"))
        #expect(!nativeShim.contains("border: 1px solid #D4DFE8"))
        #expect(!nativeShim.contains("background: #AAB5BE"))
        #expect(!nativeShim.contains("color: #F4F6F7"))
        #expect(!nativeShim.contains("border: 1px solid #CDD5CA"))
        #expect(!nativeShim.contains("color: #9CA6AD"))
        #expect(!nativeShim.contains("border: 1px solid #C8DED3"))
        #expect(!nativeShim.contains("QSplitter::handle { background: #D8DDD5; }"))
        #expect(!nativeShim.contains("statusLayout->setSpacing(8)"))
        #expect(!nativeShim.contains("statusDot->setFixedSize(9, 9)"))
        #expect(!nativeShim.contains("headerLayout->setSpacing(12)"))
        #expect(!nativeShim.contains("titleLayout->setSpacing(4)"))
        #expect(!nativeShim.contains("messageLayout->setSpacing(14)"))
        #expect(nativeShim.contains("const int composerPadding = intValue(style, \"composerPadding\", 18)"))
        #expect(nativeShim.contains("composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding)"))
        #expect(nativeShim.contains("composerLayout->setSpacing(intValue(style, \"composerSpacing\", 10))"))
        #expect(nativeShim.contains("promptRow->setSpacing(intValue(style, \"promptRowSpacing\", 12))"))
        #expect(nativeShim.contains("promptEditor->setMinimumHeight(intValue(style, \"composerMinHeight\", 74))"))
        #expect(nativeShim.contains("promptEditor->setMaximumHeight(intValue(style, \"composerMaxHeight\", 120))"))
        #expect(!nativeShim.contains("promptEditor->setFixedHeight(intValue(style, \"composerHeight\", 84))"))
        #expect(nativeShim.contains("selectedConversationMessages("))
        #expect(nativeShim.contains("QString modelStatusText(const QString &selectedModel)"))
        #expect(nativeShim.contains("return QStringLiteral(\"Choose a local model to begin\")"))
        #expect(nativeShim.contains("modelStatusText(stringValue(payload, \"selectedModel\"))"))
        #expect(nativeShim.contains("currentTitle->setFixedWidth(headerTitleWidth)"))
        #expect(nativeShim.contains("modelStatus->setFixedWidth(headerTitleWidth)"))
        #expect(nativeShim.contains("QString messageRoleTitle(const QString &role)"))
        #expect(nativeShim.contains("return QStringLiteral(\"You\")"))
        #expect(nativeShim.contains("return QStringLiteral(\"Enchanted\")"))
        #expect(nativeShim.contains("return QStringLiteral(\"System\")"))
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
        #expect(nativeShim.contains("QString promptCardPrefix()"))
        #expect(nativeShim.contains("new QPushButton(QStringLiteral(\"%1%2\").arg(promptCardPrefix(), prompt))"))
        #expect(!nativeShim.contains("layout->setContentsMargins(26, 26, 26, 26)"))
        #expect(!nativeShim.contains("promptList->setSpacing(10)"))
        #expect(!nativeShim.contains("button->setMinimumHeight(48)"))
        #expect(!nativeShim.contains("button->setFixedWidth(620)"))
        #expect(!nativeShim.contains("padding: 9px 12px"))
        #expect(!nativeShim.contains("border-radius: 7px; padding: 7px;"))
        #expect(!nativeShim.contains("padding: 2px 6px"))
        #expect(!nativeShim.contains("emptyState->setMaximumWidth(680)"))
        #expect(!nativeShim.contains("role.toUpper()"))
        #expect(macOSRootView.contains("Text(\"No models detected\")"))
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
        #expect(macOSRootView.contains("Text(\"No saved chats yet\")"))
        #expect(macOSRootView.contains("Text(\"Start a chat and it will be saved locally.\")"))
        #expect(macOSRootView.contains("Button(\"Delete chat\")"))
        #expect(macOSRootView.contains("model.deleteSelectedConversation()"))
        #expect(macOSRootView.contains("Button(\"Clear all\")"))
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
        #expect(macOSRootView.contains(".cornerRadius(8)"))
        #expect(macOSRootView.contains(".cornerRadius(10)"))
        #expect(macOSMarkdownRendering.contains(".cornerRadius(7)"))
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
        #expect(macOSRootView.contains("?? \"New conversation\""))
        #expect(nativeShim.contains("QStringLiteral(\"New conversation\")"))
        #expect(!nativeShim.contains("QuillUI backend parity"))
        #expect(macOSRootView.contains("Text(\"Attachments\")"))
        #expect(macOSRootView.contains("Text(\"Attach\")"))
        #expect(macOSRootView.contains("Button(\"Clear\")"))
        #expect(macOSRootView.contains("Text(model.isLoading ? \"Stop\" : \"Send\")"))
        #expect(macOSRootView.contains(".background(model.isLoading ? QuillColors.warning : QuillColors.primary)"))
        #expect(macOSRootView.contains(".dropDestination(for: URL.self)"))
        #expect(macOSRootView.contains("model.addAttachments(urls: urls)"))
        #expect(macOSRootView.contains("model.isAttachmentDropTargeted = isTargeted"))
        #expect(imageAttachmentSource.contains("\"Describe this image.\""))
        #expect(imageAttachmentSource.contains("[Attached images]"))
        #expect(nativeSupport.contains("inline bool jsonBoolValue("))
        #expect(nativeShim.contains("stringValue(payload, \"attachTitle\", QStringLiteral(\"Attach\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"clearAttachmentsTitle\", QStringLiteral(\"Clear\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"attachmentsTitle\", QStringLiteral(\"Attachments\"))"))
        #expect(nativeShim.contains("\"attachmentDefaultPrompt\""))
        #expect(nativeShim.contains("QStringLiteral(\"Describe this image.\")"))
        #expect(nativeShim.contains("\"attachmentSummaryTitle\""))
        #expect(nativeShim.contains("QStringLiteral(\"[Attached images]\")"))
        #expect(nativeShim.contains("QPushButton *clearAttachmentsButton"))
        #expect(nativeShim.contains("QString attachmentDisplayContent("))
        #expect(nativeShim.contains("QStringList normalizedAttachmentPaths("))
        #expect(nativeShim.contains("QStringList attachmentPathsFromMimeData(const QMimeData *mimeData)"))
        #expect(nativeShim.contains("QString attachmentSummaryForPaths("))
        #expect(nativeShim.contains("QString formattedAttachmentByteCount(qint64 byteCount)"))
        #expect(nativeShim.contains("QString attachmentDisplaySize(const QString &rawPath)"))
        #expect(nativeShim.contains("#include <QMimeData>"))
        #expect(nativeShim.contains("#include <QStringList>"))
        #expect(nativeShim.contains("class AttachmentDropFrame final : public QFrame"))
        #expect(nativeShim.contains("setAcceptDrops(true)"))
        #expect(nativeShim.contains("attachmentPath->setAcceptDrops(false)"))
        #expect(nativeShim.contains("mimeData->urls()"))
        #expect(nativeShim.contains("url.toLocalFile()"))
        #expect(nativeShim.contains("QFrame#dropTarget { background: %1; border: 1px solid %2; border-radius: %5; }"))
        #expect(nativeShim.contains("QFrame#dropTarget[dragActive=\"true\"]"))
        #expect(nativeShim.contains("QSplitter::handle { background: %4; }"))
        #expect(nativeShim.contains("QStringList pendingAttachmentPaths"))
        #expect(nativeShim.contains("QScrollArea *attachmentScrollArea"))
        #expect(nativeShim.contains("QHBoxLayout *attachmentChipListLayout"))
        #expect(nativeShim.contains("QPushButton *removeAttachmentButton"))
        #expect(nativeShim.contains("removeAttachmentButton->setObjectName(QStringLiteral(\"chipRemoveButton\"))"))
        #expect(runtime.contains("attachmentRemoveButtonWidth: 28"))
        #expect(nativeShim.contains("removeAttachmentButton->setFixedWidth(intValue(style, \"attachmentRemoveButtonWidth\", 28))"))
        #expect(!nativeShim.contains("removeAttachmentButton->setFixedWidth(28)"))
        #expect(nativeShim.contains("pendingAttachmentPaths.removeAll(path)"))
        #expect(nativeShim.contains("QTimer::singleShot(0, attachmentTray, renderAttachmentTray)"))
        #expect(nativeShim.contains("clearLayout(attachmentChipListLayout)"))
        #expect(nativeShim.contains("boolValue(payload, \"isLoading\", false)"))
        #expect(nativeShim.contains("stringValue(payload, \"stopTitle\", QStringLiteral(\"Stop\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"stoppingStatus\", QStringLiteral(\"Stopping...\"))"))
        #expect(nativeShim.contains("sendButton->setProperty(\"loading\", isLoading)"))
        #expect(nativeShim.contains("sendButton->setText(isLoading ? stopTitle : sendTitle)"))
        #expect(runtime.contains("composerSendButtonMinWidth: 86"))
        #expect(nativeShim.contains("sendButton->setMinimumWidth(intValue(style, \"composerSendButtonMinWidth\", 86))"))
        #expect(!nativeShim.contains("sendButton->setMinimumWidth(86)"))
        #expect(nativeShim.contains("QPushButton#sendButton[loading=\"true\"]"))
        #expect(nativeShim.contains("const bool hasPendingAttachments = !pendingAttachmentPaths.isEmpty()"))
        #expect(nativeShim.contains("clearAttachmentsButton->setEnabled(hasTrimmedText(attachmentPath) || hasPendingAttachments)"))
        #expect(nativeShim.contains("sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || hasPendingAttachments)"))
        #expect(nativeShim.contains("statusText->setText(stoppingStatus)"))
        #expect(nativeShim.contains("refreshButton->setEnabled(!isLoading)"))
        #expect(nativeShim.contains("modelStatus->setText(modelStatusText(model))"))
        #expect(nativeShim.contains("std::function<bool(const QString &, const QString &, const QString &, const QStringList &)> requestHistoryAction"))
        #expect(nativeShim.contains("QStringLiteral(\"sendMessage\"),"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"messageText\"), trimmedMessageText)"))
        #expect(nativeShim.contains("action.insert(QStringLiteral(\"attachmentPaths\"), encodedAttachmentPaths)"))
        #expect(nativeShim.contains("attachmentSummaryForPaths(pendingAttachmentPaths)"))
        #expect(nativeShim.contains("pendingAttachmentPaths = normalizedAttachmentPaths(pendingAttachmentPaths)"))
        #expect(nativeShim.contains("dropTarget->setDropHandler"))
        #expect(nativeShim.contains("pendingAttachmentPaths.append(path)"))
        #expect(nativeShim.contains("appendComposerMessage(promptEditor->toPlainText())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"newConversation\"), QString(), QString(), QStringList())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"deleteConversation\"), deletedConversationID, QString(), QStringList())"))
        #expect(nativeShim.contains("requestHistoryAction(QStringLiteral(\"deleteAllConversations\"), QString(), QString(), QStringList())"))
        #expect(runtime.contains("OllamaClient(baseURL: endpoint).chat("))
        #expect(runtime.contains("context.insert(ChatMessage("))
        #expect(runtime.contains("role: .assistant"))
        #expect(runtime.contains("Ollama returned an empty response."))
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
}

private enum CoreContractMatrixTestError: Error {
    case packageRootNotFound
}

private let enchantedEmptyConversationPrompts: [String] = [
    "Summarize the tradeoffs in moving a SwiftUI app to Linux.",
    "Draft a private local assistant workflow for a small team.",
    "Explain how Ollama model selection should work in a desktop app.",
    "Write a checklist for shipping an open-source Swift package."
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
    ByteCountCase(byteCount: 1_073_741_824, expected: "1.0 GB")
] + (1...32).map { index in
    ByteCountCase(byteCount: Int64(index * 1024), expected: "\(index).0 KB")
}

private let imageExtensionCases: [ImageExtensionCase] = [
    ImageExtensionCase(fileExtension: "gif", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "heic", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "jpeg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "jpg", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "png", mediaType: "image/png"),
    ImageExtensionCase(fileExtension: "webp", mediaType: "image/webp"),
    ImageExtensionCase(fileExtension: "GIF", mediaType: "image/gif"),
    ImageExtensionCase(fileExtension: "HEIC", mediaType: "image/heic"),
    ImageExtensionCase(fileExtension: "JPEG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "JPG", mediaType: "image/jpeg"),
    ImageExtensionCase(fileExtension: "PNG", mediaType: "image/png"),
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
