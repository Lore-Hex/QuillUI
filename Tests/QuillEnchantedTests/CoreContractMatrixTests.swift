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
        let runtime = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedQtNativeRuntime/QuillEnchantedQtNativeRuntime.swift"),
            encoding: .utf8
        )
        let macOSRootView = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedRootView.swift"),
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
        #expect(manifest.contains("name: \"QuillEnchantedQtNativeRuntime\""))
        #expect(manifest.contains("dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillEnchantedData\", \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]"))
        #expect(qtMain.contains("#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND"))
        #expect(qtMain.contains("QuillEnchantedQtNativeApp.run()"))
        #expect(qtMain.contains("QuillQtApp.run(QuillEnchantedQtApp.self)"))
        #expect(runtime.contains("import QuillEnchantedData"))
        #expect(runtime.contains("import QuillEnchantedShared"))
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
        #expect(runtime.contains("headerTitleWidth: 560"))
        #expect(runtime.contains("composerPadding: 18"))
        #expect(runtime.contains("composerSpacing: 10"))
        #expect(runtime.contains("promptRowSpacing: 12"))
        #expect(runtime.contains("composerMinHeight: 74"))
        #expect(runtime.contains("composerMaxHeight: 120"))
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
        #expect(nativeShim.contains("intValue(style, \"sidebarWidth\", 300)"))
        #expect(nativeShim.contains("intValue(style, \"headerTitleWidth\", 560)"))
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
        #expect(nativeShim.contains(".arg(quoteRule, codeBlock)"))
        #expect(nativeShim.contains("layout->setContentsMargins(10, 10, 10, 10)"))
        #expect(nativeShim.contains("layout->setSpacing(7)"))
        #expect(nativeShim.contains("QWidget *markdownMessageWidget(const QString &markdown)"))
        #expect(nativeShim.contains("layout->setContentsMargins(0, 0, 0, 0)"))
        #expect(nativeShim.contains("layout->setSpacing(9)"))
        #expect(nativeShim.contains("addMarkdownBlocks(layout, markdown)"))
        #expect(nativeShim.contains("layout->addWidget(markdownMessageWidget(stringValue(message, \"content\")))"))
        #expect(nativeShim.contains("role == QStringLiteral(\"user\") ? QStringLiteral(\"messageUserRole\") : QStringLiteral(\"messageRole\")"))
        #expect(nativeShim.contains("QFrame#messageSystem { background: %7;"))
        #expect(nativeShim.contains("QFrame#messageUser { background: %6;"))
        #expect(nativeShim.contains("border-radius: 10px;"))
        #expect(nativeShim.contains("layout->setContentsMargins(13, 13, 13, 13)"))
        #expect(nativeShim.contains("QString promptCardPrefix()"))
        #expect(nativeShim.contains("new QPushButton(QStringLiteral(\"%1%2\").arg(promptCardPrefix(), prompt))"))
        #expect(nativeShim.contains("button->setFixedWidth(620)"))
        #expect(!nativeShim.contains("role.toUpper()"))
        #expect(macOSRootView.contains("Text(\"No models detected\")"))
        #expect(nativeShim.contains("stringValue(payload, \"noModelsTitle\", QStringLiteral(\"No models detected\"))"))
        #expect(nativeShim.contains("models.isEmpty() ? QStringLiteral(\"statusDotWarning\") : QStringLiteral(\"statusDot\")"))
        #expect(nativeShim.contains("QFrame#statusDot, QFrame#statusDotWarning"))
        #expect(nativeShim.contains(".arg(selected, ink, card, success, warning, dropTarget, canvas, primary)"))
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
        #expect(nativeShim.contains("emptyHistoryWidget("))
        #expect(nativeShim.contains("stringValue(payload, \"emptyHistoryTitle\", QStringLiteral(\"No saved chats yet\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"emptyHistorySubtitle\", QStringLiteral(\"Start a chat and it will be saved locally.\"))"))
        #expect(macOSRootView.contains(".foregroundColor(isSelected ? .white : QuillColors.ink)"))
        #expect(macOSRootView.contains(".background(isSelected ? QuillColors.primary : QuillColors.card)"))
        #expect(nativeShim.contains("QFrame#conversationRow[active=\"true\"] { background: %8; }"))
        #expect(nativeShim.contains("QLabel#conversationTitle[active=\"true\"] { color: white; }"))
        #expect(nativeShim.contains("QLabel#conversationPreview[active=\"true\"] { color: %1; }"))
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
        #expect(nativeShim.contains("QFrame#dropTarget[dragActive=\"true\"]"))
        #expect(nativeShim.contains("QStringList pendingAttachmentPaths"))
        #expect(nativeShim.contains("QScrollArea *attachmentScrollArea"))
        #expect(nativeShim.contains("QHBoxLayout *attachmentChipListLayout"))
        #expect(nativeShim.contains("QPushButton *removeAttachmentButton"))
        #expect(nativeShim.contains("removeAttachmentButton->setObjectName(QStringLiteral(\"chipRemoveButton\"))"))
        #expect(nativeShim.contains("pendingAttachmentPaths.removeAll(path)"))
        #expect(nativeShim.contains("QTimer::singleShot(0, attachmentTray, renderAttachmentTray)"))
        #expect(nativeShim.contains("clearLayout(attachmentChipListLayout)"))
        #expect(nativeShim.contains("boolValue(payload, \"isLoading\", false)"))
        #expect(nativeShim.contains("stringValue(payload, \"stopTitle\", QStringLiteral(\"Stop\"))"))
        #expect(nativeShim.contains("stringValue(payload, \"stoppingStatus\", QStringLiteral(\"Stopping...\"))"))
        #expect(nativeShim.contains("sendButton->setProperty(\"loading\", isLoading)"))
        #expect(nativeShim.contains("sendButton->setText(isLoading ? stopTitle : sendTitle)"))
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
