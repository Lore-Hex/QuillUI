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

    @Test("detects image-capable Ollama model families", arguments: imageModelSupportCases)
    func imageModelSupportContracts(testCase: ModelImageSupportCase) {
        #expect(testCase.modelName.quillLikelySupportsImages == testCase.supportsImages)
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

    @Test("empty conversation prompt catalog mirrors upstream samples")
    func emptyConversationPromptCatalogMirrorsUpstreamSamples() {
        let expectedKinds: [EnchantedPrompt.Kind] = [
            .action,
            .action,
            .question,
            .question,
            .action,
            .action,
            .action,
            .question,
            .question,
            .action,
            .question
        ]

        #expect(EnchantedPromptCatalog.emptyConversationPrompts.map(\.title) == enchantedEmptyConversationPrompts)
        #expect(EnchantedPromptCatalog.emptyConversationPrompts.map(\.kind) == expectedKinds)
        #expect(EnchantedPromptCatalog.emptyConversationTitles == enchantedEmptyConversationPrompts)
        #expect(EnchantedPromptCatalog.emptyConversationVisiblePromptCount == 4)
        #expect(EnchantedPromptCatalog.visibleEmptyConversationPrompts.map(\.title) == Array(enchantedEmptyConversationPrompts.prefix(4)))
        #expect(EnchantedPromptCatalog.visibleEmptyConversationPrompts.map(\.kind) == Array(expectedKinds.prefix(4)))
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
        let enchantedModelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedModel.swift"),
            encoding: .utf8
        )
        let sharedPrompts = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedShared/QuillEnchantedShared.swift"),
            encoding: .utf8
        )
        let upstreamSidebar = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Sidebar/SidebarView.swift"),
            encoding: .utf8
        )
        let upstreamMessageList = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/MessageListVIew.swift"),
            encoding: .utf8
        )
        let upstreamChatMessageView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/ChatMessages/ChatMessageView.swift"),
            encoding: .utf8
        )
        let upstreamReadingAloudView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/ReadingAloudView.swift"),
            encoding: .utf8
        )
        let upstreamCodeBlockView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/ChatMessages/CodeBlockView.swift"),
            encoding: .utf8
        )
        let upstreamMarkdownColours = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/ChatMessages/MarkdownColours.swift"),
            encoding: .utf8
        )
        let upstreamRecorderView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/Recorder/RecordingView.swift"),
            encoding: .utf8
        )
        let upstreamOptionsMenuView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/OptionsMenuView.swift"),
            encoding: .utf8
        )
        let upstreamRemovableImage = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/RemovableImage.swift"),
            encoding: .utf8
        )
        let upstreamModelSelectorView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/ModelSelectorView.swift"),
            encoding: .utf8
        )
        let upstreamMacOSChatView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Chat/ChatView_macOS.swift"),
            encoding: .utf8
        )
        let upstreamMacOSToolbarView = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Chat/Components/ToolbarView_macOS.swift"),
            encoding: .utf8
        )
        let upstreamMacOSDragAndDrop = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Components/DragAndDrop.swift"),
            encoding: .utf8
        )
        let upstreamInputFields = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Chat/Components/InputFields_macOS.swift"),
            encoding: .utf8
        )
        let upstreamHeader = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Chat/Components/Header.swift"),
            encoding: .utf8
        )
        let upstreamConversationHistoryList = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Sidebar/Components/ConversationHistoryListView.swift"),
            encoding: .utf8
        )
        let upstreamCompletionsEditor = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/CompletionsEditor/CompletionsEditorView.swift"),
            encoding: .utf8
        )
        let upstreamCompletionPanel = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Components/CompletionPanelView.swift"),
            encoding: .utf8
        )
        let upstreamSettings = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/Shared/Settings/SettingsView.swift"),
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
            "completions: EnchantedIcon.completions",
            "shortcuts: EnchantedIcon.shortcuts",
            "settings: EnchantedIcon.settings",
            "refreshModels: EnchantedIcon.refreshModels",
            "deleteChat: EnchantedIcon.deleteChat",
            "clearAll: EnchantedIcon.clearAll",
            "copyMessage: EnchantedIcon.copyMessage",
            "editMessage: EnchantedIcon.editMessage",
            "imagePreviewFallback: EnchantedIcon.imagePreviewFallback",
            "unavailableModel: EnchantedIcon.unavailableModel",
            "send: EnchantedIcon.send",
            "stop: EnchantedIcon.stop",
            "removeAttachment: EnchantedIcon.removeAttachment",
            "var systemImage: String",
            "self.systemImage = prompt.systemImage",
            "icons: .shared"
        ] {
            expectContains(runtime, needle)
        }

        for needle in [
            "public enum EnchantedIcon",
            "public static let newConversation = \"square.and.pencil\"",
            "public static let attach = \"folder.badge.plus\"",
            "public static let dropTarget = \"photo\"",
            "public static let attachment = \"folder\"",
            "public static let completions = \"textformat.abc\"",
            "public static let shortcuts = \"keyboard.fill\"",
            "public static let settings = \"gearshape.fill\"",
            "public static let refreshModels = \"arrow.clockwise\"",
            "public static let deleteChat = \"trash\"",
            "public static let clearAll = \"trash\"",
            "public static let imagePreviewFallback = \"photo.fill\"",
            "public static let unavailableModel = \"waveform\"",
            "public static let send = \"arrow.forward.circle.fill\"",
            "public static let stop = \"square.fill\"",
            "public static let copyMessage = \"doc.on.doc\"",
            "public static let editMessage = \"pencil\"",
            "public static let removeAttachment = \"xmark.circle.fill\""
        ] {
            expectContains(sharedPrompts, needle)
        }

        #expect(EnchantedIcon.completions == "textformat.abc")
        #expect(EnchantedIcon.shortcuts == "keyboard.fill")
        #expect(EnchantedIcon.dropTarget == "photo")
        #expect(EnchantedIcon.clearAll == "trash")
        #expect(EnchantedIcon.imagePreviewFallback == "photo.fill")
        #expect(EnchantedIcon.unavailableModel == "waveform")
        #expect(EnchantedIcon.copyMessage == "doc.on.doc")
        #expect(EnchantedIcon.editMessage == "pencil")
        #expect(EnchantedCopy.copyMessageTitle == "Copy")
        #expect(EnchantedCopy.editMessageTitle == "Edit")
        #expect(EnchantedCopy.unselectMessageTitle == "Unselect")

        for needle in [
            "SidebarButton(title: \"Completions\", image: \"textformat.abc\"",
            "SidebarButton(title: \"Shortcuts\", image: \"keyboard.fill\"",
            "SidebarButton(title: \"Settings\", image: \"gearshape.fill\""
        ] {
            expectContains(upstreamSidebar, needle)
        }
        for needle in [
            "Label(\"Copy\", systemImage: \"doc.on.doc\")",
            "Label(\"Select Text\", systemImage: \"selection.pin.in.out\")",
            "Label(\"Read Aloud\", systemImage: \"speaker.wave.3.fill\")",
            "Label(\"Edit\", systemImage: \"pencil\")",
            "Label(\"Unselect\", systemImage: \"pencil\")"
        ] {
            expectContains(upstreamMessageList, needle)
        }
        for needle in [
            "Image(systemName: \"doc.on.doc\")",
            "Image(systemName: \"speaker.wave.2.fill\")",
            "Image(systemName: \"speaker.slash.fill\")",
            "Image(systemName: \"pencil\")"
        ] {
            expectContains(upstreamChatMessageView, needle)
        }
        for needle in [
            "Image(systemName: \"speaker.wave.3\")",
            "Image(systemName: \"stop.fill\")"
        ] {
            expectContains(upstreamReadingAloudView, needle)
        }
        expectContains(upstreamCodeBlockView, "Image(systemName: \"doc.on.doc\")")
        expectContains(upstreamMarkdownColours, "Image(systemName: configuration.isCompleted ? \"checkmark.square.fill\" : \"square\")")
        for needle in [
            "Image(systemName: \"square.fill\")",
            "Image(systemName: \"waveform\")"
        ] {
            expectContains(upstreamRecorderView, needle)
        }
        expectContains(upstreamOptionsMenuView, "Image(systemName: \"ellipsis\")")
        expectContains(upstreamRemovableImage, "Image(systemName: \"x.circle.fill\")")
        expectContains(upstreamModelSelectorView, "Image(systemName: \"chevron.down\")")
        expectContains(upstreamMacOSChatView, "Image(systemName: \"sidebar.left\")")
        expectContains(upstreamMacOSToolbarView, "Image(systemName: \"square.and.pencil\")")
        expectContains(upstreamMacOSDragAndDrop, "Image(systemName: \"\(EnchantedIcon.dropTarget)\")")
        expectContains(upstreamMacOSDragAndDrop, "Text(\"\(EnchantedCopy.dropTargetTitle)\")")
        for needle in [
            "SimpleFloatingButton(systemImage: \"photo.fill\"",
            "SimpleFloatingButton(systemImage: \"square.fill\"",
            "SimpleFloatingButton(systemImage: \"paperplane.fill\""
        ] {
            expectContains(upstreamInputFields, needle)
        }
        expectContains(upstreamHeader, "Image(systemName: \"line.3.horizontal\")")
        expectContains(upstreamHeader, "Image(systemName: \"square.and.pencil\")")
        expectContains(upstreamCompletionPanel, "Image(systemName: \"space\")")
        expectContains(upstreamSettings, "Label(\"Vibrations\", systemImage: \"water.waves\")")
        expectContains(upstreamSettings, "Label(\"Appearance\", systemImage: \"sun.max\")")
        expectContains(upstreamSettings, "Label(\"Voice\", systemImage: \"waveform\")")
        expectContains(upstreamConversationHistoryList, "Label(\"Delete daily conversations\", systemImage: \"trash\")")
        expectContains(upstreamConversationHistoryList, "Label(\"Delete\", systemImage: \"trash\")")
        expectContains(upstreamCompletionsEditor, "Image(systemName: \"pencil\")")
        expectContains(upstreamCompletionsEditor, "Image(systemName: \"xmark\")")

        for needle in [
            "private func enchantedSystemImageName(_ systemImage: String) -> String",
            "QuillSystemSymbol.compatibleName(systemImage)",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.newConversation))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.refreshModels))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.deleteChat))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.clearAll))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.attach))",
            "Image(systemName: enchantedSystemImageName(model.isLoading ? EnchantedIcon.stop : EnchantedIcon.send))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.dropTarget))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.attachment))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.removeAttachment))",
            "enchantedSystemImageName(EnchantedIcon.editMessage)"
        ] {
            expectContains(macOSRootView, needle)
        }

        for needle in [
            "MessageBubble(\n                                message: message,",
            "isEditing: message.id == model.editingMessageID",
            "cancelEdit: model.cancelMessageEdit",
            ".overlay(",
            "EnchantedVisualMetrics.messageEditBorderWidth",
            ".contextMenu {",
            "Button(action: copyMessageContent)",
            "EnchantedCopy.copyMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.copyMessage)",
            "if message.role == .user {",
            "Button(action: editMessageContent)",
            "EnchantedCopy.editMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.editMessage)",
            "if isEditing {",
            "Button(action: cancelEdit)",
            "EnchantedCopy.unselectMessageTitle",
            "private func copyMessageContent()",
            "EnchantedClipboard.setString(message.content)",
            "private func editMessageContent()",
            "editMessage(message)"
        ] {
            expectContains(macOSRootView, needle)
        }

        for needle in [
            "@Published public var editingMessageID: String?",
            "public func editMessage(_ message: ChatMessage)",
            "public func cancelMessageEdit()",
            "guard message.role == .user else { return }",
            "composerText = message.content",
            "editingMessageID = message.id",
            "trimmingMessageID: draft.trimmingMessageID",
            "let trimmingMessageID = editingMessageID",
            "editingMessageID = nil",
            "return (prompt, attachments, trimmingMessageID)"
        ] {
            expectContains(enchantedModelSource, needle)
        }

        for needle in [
            "QString requiredIconName(const QJsonObject &icons, const char *key)",
            "requiredStringValue(icons, key).trimmed()",
            "QIcon systemImageIcon(const QString &systemImage)",
            "QIcon newConversationButtonIcon(const QJsonObject &icons)",
            "QIcon attachButtonIcon(const QJsonObject &icons)",
            "QIcon unavailableModelButtonIcon(const QJsonObject &icons)",
            "QIcon dropTargetIcon(const QJsonObject &icons)",
            "QIcon attachmentChipIcon(const QJsonObject &icons)",
            "QIcon utilityButtonIcon(const QJsonObject &icons, const char *key)",
            "QIcon refreshModelsButtonIcon(const QJsonObject &icons)",
            "QIcon deleteChatButtonIcon(const QJsonObject &icons)",
            "QIcon clearAllButtonIcon(const QJsonObject &icons)",
            "QIcon copyMessageActionIcon(const QJsonObject &icons)",
            "QIcon editMessageActionIcon(const QJsonObject &icons)",
            "QIcon sendButtonIcon(const QJsonObject &icons, bool isLoading)",
            "QIcon removeAttachmentButtonIcon(const QJsonObject &icons)",
            "systemImageIcon(requiredIconName(icons, \"newConversation\"))",
            "systemImageIcon(requiredIconName(icons, \"attach\"))",
            "systemImageIcon(requiredIconName(icons, \"unavailableModel\"))",
            "systemImageIcon(requiredIconName(icons, \"dropTarget\"))",
            "systemImageIcon(requiredIconName(icons, \"attachment\"))",
            "systemImageIcon(requiredIconName(icons, key))",
            "systemImageIcon(requiredIconName(icons, \"refreshModels\"))",
            "systemImageIcon(requiredIconName(icons, \"deleteChat\"))",
            "systemImageIcon(requiredIconName(icons, \"clearAll\"))",
            "systemImageIcon(requiredIconName(icons, \"copyMessage\"))",
            "systemImageIcon(requiredIconName(icons, \"editMessage\"))",
            "systemImageIcon(requiredIconName(icons, \"removeAttachment\"))",
            "QJsonObject icons = payloadObject(payload, \"icons\")",
            "icons = payloadObject(payload, \"icons\")",
            "newConversationButtonIcon(icons),",
            "unavailableModelButton->setIcon(unavailableModelButtonIcon(icons))",
            "attachButtonIcon(icons),\n        attachTitle,\n        QStringLiteral(\"attachButtonIcon\"),",
            "auto configureUtilityButton = [&](QPushButton *button, const QString &title, const char *iconKey)",
            "utilityButtonIcon(icons, iconKey),",
            "QStringLiteral(\"utilityButtonIcon\")",
            "QStringLiteral(\"utilityButtonText\")",
            "configureUtilityButton(completionsButton, payloadString(payload, \"completionsTitle\"), \"completions\")",
            "configureUtilityButton(shortcutsButton, payloadString(payload, \"shortcutsTitle\"), \"shortcuts\")",
            "configureUtilityButton(settingsButton, payloadString(payload, \"settingsTitle\"), \"settings\")",
            "dropTargetIcon(icons),\n        QStringLiteral(\"dropTargetIcon\"),\n        style",
            "attachmentChipIcon(icons),\n                QStringLiteral(\"attachmentChipIcon\"),\n                style",
            "removeAttachmentButton->setIcon(removeAttachmentButtonIcon(icons))",
            "updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle, style)",
            "QStringLiteral(\"document-new-symbolic\")",
            "QStringLiteral(\"folder-new-symbolic\")",
            "QStringLiteral(\"folder-symbolic\")",
            "normalized.contains(QStringLiteral(\"sidebar.left\"))",
            "QStringLiteral(\"view-sidebar-symbolic\")",
            "normalized.contains(QStringLiteral(\"line.3.horizontal\"))",
            "QStringLiteral(\"open-menu-symbolic\")",
            "normalized.contains(QStringLiteral(\"xmark.circle\"))",
            "normalized.contains(QStringLiteral(\"x.circle\"))",
            "normalized == QStringLiteral(\"xmark\")",
            "QStringLiteral(\"window-close-symbolic\")",
            "normalized.contains(QStringLiteral(\"pencil\"))",
            "QStringLiteral(\"document-edit-symbolic\")",
            "normalized.contains(QStringLiteral(\"checkmark.square\"))",
            "QStringLiteral(\"checkbox-checked-symbolic\")",
            "normalized == QStringLiteral(\"square\")",
            "QStringLiteral(\"checkbox-symbolic\")",
            "normalized.contains(QStringLiteral(\"stop.fill\"))",
            "QStringLiteral(\"process-stop-symbolic\")",
            "normalized.contains(QStringLiteral(\"speaker.slash\"))",
            "QStringLiteral(\"audio-volume-muted-symbolic\")",
            "normalized.contains(QStringLiteral(\"speaker.wave\"))",
            "QStringLiteral(\"audio-volume-high-symbolic\")",
            "QStringLiteral(\"go-next-symbolic\")",
            "normalized.contains(QStringLiteral(\"arrow.clockwise\"))",
            "QStringLiteral(\"view-refresh-symbolic\")",
            "normalized.contains(QStringLiteral(\"trash\"))",
            "QStringLiteral(\"user-trash-symbolic\")",
            "normalized.contains(QStringLiteral(\"doc.on.doc\"))",
            "QStringLiteral(\"edit-copy-symbolic\")",
            "normalized.contains(QStringLiteral(\"selection.pin\"))",
            "QStringLiteral(\"edit-select-all-symbolic\")",
            "normalized.contains(QStringLiteral(\"doc.text\"))",
            "QStringLiteral(\"text-x-generic-symbolic\")",
            "normalized.contains(QStringLiteral(\"curlybraces\"))",
            "QStringLiteral(\"applications-development-symbolic\")",
            "normalized.contains(QStringLiteral(\"ellipsis\"))",
            "QStringLiteral(\"view-more-symbolic\")",
            "normalized.contains(QStringLiteral(\"chevron.down\"))",
            "QStringLiteral(\"pan-down-symbolic\")",
            "normalized.contains(QStringLiteral(\"checkmark\"))",
            "QStringLiteral(\"emblem-ok-symbolic\")",
            "normalized.contains(QStringLiteral(\"paperplane\"))",
            "QStringLiteral(\"mail-send-symbolic\")",
            "normalized.contains(QStringLiteral(\"photo\"))",
            "QStringLiteral(\"image-x-generic-symbolic\")",
            "normalized.contains(QStringLiteral(\"water.waves\"))",
            "QStringLiteral(\"preferences-desktop-sound-symbolic\")",
            "normalized.contains(QStringLiteral(\"sun.max\"))",
            "QStringLiteral(\"weather-clear-symbolic\")",
            "normalized.contains(QStringLiteral(\"waveform\"))",
            "QStringLiteral(\"audio-input-microphone-symbolic\")",
            "normalized.contains(QStringLiteral(\"info.circle\"))",
            "normalized.contains(QStringLiteral(\"link\"))",
            "QStringLiteral(\"insert-link-symbolic\")",
            "normalized.contains(QStringLiteral(\"textformat\"))",
            "QStringLiteral(\"accessories-text-editor-symbolic\")",
            "normalized == QStringLiteral(\"space\")",
            "normalized.contains(QStringLiteral(\"keyboard\"))",
            "QStringLiteral(\"input-keyboard-symbolic\")",
            "normalized.contains(QStringLiteral(\"gearshape\"))",
            "normalized == QStringLiteral(\"gear\")",
            "normalized.contains(QStringLiteral(\"gear.\"))",
            "QStringLiteral(\"preferences-system-symbolic\")",
            "QStyle::SP_FileIcon",
            "QStyle::SP_FileDialogNewFolder",
            "QStyle::SP_DirIcon",
            "QStyle::SP_DialogCloseButton",
            "QStyle::SP_MediaStop",
            "QStyle::SP_MediaPlay",
            "QStyle::SP_BrowserReload",
            "QStyle::SP_TrashIcon",
            "QStyle::SP_TitleBarMenuButton",
            "QStyle::SP_TitleBarNormalButton",
            "QStyle::SP_ArrowDown",
            "QStyle::SP_DialogApplyButton",
            "QStyle::SP_CommandLink",
            "QStyle::SP_FileDialogDetailedView",
            "QStyle::SP_ComputerIcon",
            "QStyle::SP_DesktopIcon",
            "QStyle::SP_MessageBoxInformation"
        ] {
            expectContains(nativeShim, needle)
        }

        for needle in [
            "QString iconName(const QJsonObject &icons, const char *key, const QString &fallback)",
            "iconName(icons,",
            "QIcon newChatButtonIcon()",
            "QIcon completionsButtonIcon()",
            "QIcon shortcutsButtonIcon()",
            "QIcon settingsButtonIcon()",
            "QLabel *dropTargetIconLabel = new QLabel()",
            "dropTargetIcon().pixmap(dropTargetIconSize, dropTargetIconSize)",
            "new QPushButton(QStringLiteral(\"x\"))"
        ] {
            expectDoesNotContain(nativeShim, needle)
        }
    }

    @Test("Enchanted GTK shell stays on the macOS visual contract")
    func enchantedGTKShellStaysOnMacOSVisualContract() throws {
        let appMain = try packageSource("Sources/QuillEnchanted/main.swift")
        let coreApp = try packageSource("Sources/QuillEnchantedCore/EnchantedApp.swift")
        let rootView = try packageSource("Sources/QuillEnchantedCore/EnchantedRootView.swift")
        let clipboard = try packageSource("Sources/QuillEnchantedCore/EnchantedClipboard.swift")
        let shared = try packageSource("Sources/QuillEnchantedShared/QuillEnchantedShared.swift")

        for needle in [
            "import QuillEnchantedCore",
            "import QuillUI",
            "QuillApp.run(QuillEnchantedApp.self)"
        ] {
            expectContains(appMain, needle)
        }

        for needle in [
            "import QuillEnchantedShared",
            "QuillAppWindow.scene(",
            "EnchantedCopy.windowTitle",
            "width: Double(EnchantedVisualMetrics.defaultWindowWidth)",
            "height: Double(EnchantedVisualMetrics.defaultWindowHeight)",
            "EnchantedRootView()"
        ] {
            expectContains(coreApp, needle)
        }

        for needle in [
            "public enum EnchantedCopy",
            "public enum EnchantedIcon",
            "public enum EnchantedPalette",
            "public enum EnchantedVisualMetrics",
            "public enum EnchantedTypography"
        ] {
            expectContains(shared, needle)
        }
        expectContains(shared, "public static let windowTitle = \"Enchanted\"")
        expectContains(shared, "public static let emptyStateTitle = appTitle")
        expectContains(shared, "public static let emptyStateSubtitle = \"\"")
        expectContains(shared, "public static let sidebarSubtitle = \"Local AI conversations\"")
        expectContains(shared, "public static let copyMessageTitle = \"Copy\"")
        expectContains(shared, "public static let editMessageTitle = \"Edit\"")
        expectContains(shared, "public static let unselectMessageTitle = \"Unselect\"")
        expectContains(shared, "public static let copyMessage = \"doc.on.doc\"")
        expectContains(shared, "public static let editMessage = \"pencil\"")
        expectDoesNotContain(shared, "Quill Enchanted")
        expectDoesNotContain(shared, "QuillUI Linux preview")
        expectContains(shared, "public static let unreachableOllamaMessage = \"Ollama is unreachable. Go to Settings and update your Ollama API endpoint. \"")

        for needle in [
            "import QuillEnchantedShared",
            "QuillMainActorView.assumeIsolated",
            "EnchantedCopy.defaultEndpoint",
            "EnchantedCopy.appTitle",
            "EnchantedCopy.sidebarSubtitle",
            "EnchantedCopy.endpointLabel",
            "EnchantedCopy.modelLabel",
            "EnchantedCopy.noModelsTitle",
            "EnchantedCopy.chooseLocalModelStatus",
            "EnchantedCopy.refreshModelsTitle",
            "EnchantedCopy.attachmentPlaceholder",
            "EnchantedCopy.emptyStateTitle",
            "EnchantedCopy.emptyStateSubtitle",
            "EnchantedPromptCatalog.visibleEmptyConversationPrompts",
            "private func enchantedSystemImageName(_ systemImage: String) -> String",
            "QuillSystemSymbol.compatibleName(systemImage)",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.newConversation))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.refreshModels))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.clearAll))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.attach))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.dropTarget))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.attachment))",
            "Image(systemName: enchantedSystemImageName(EnchantedIcon.removeAttachment))",
            "enchantedSystemImageName(EnchantedIcon.editMessage)",
            "Image(systemName: enchantedSystemImageName(model.isLoading ? EnchantedIcon.stop : EnchantedIcon.send))",
            "Color(hex: EnchantedPalette.canvasColor)",
            "Color(hex: EnchantedPalette.sidebarColor)",
            "Color(hex: EnchantedPalette.headerColor)",
            "Color(hex: EnchantedPalette.cardColor)",
            "Color(hex: EnchantedPalette.primaryColor)",
            "Color(hex: EnchantedPalette.successColor)",
            "Color(hex: EnchantedPalette.warningColor)",
            "Color(hex: EnchantedPalette.systemColor)",
            "Color(hex: EnchantedPalette.inkColor)",
            "Color(hex: EnchantedPalette.mutedColor)",
            "Color(hex: EnchantedPalette.selectedMutedColor)",
            "Color(hex: EnchantedPalette.dropTargetColor)",
            "EnchantedVisualMetrics.minimumWindowWidth",
            "EnchantedVisualMetrics.minimumWindowHeight",
            "EnchantedVisualMetrics.sidebarWidth",
            "EnchantedVisualMetrics.sidebarPadding",
            "EnchantedVisualMetrics.sidebarSpacing",
            "EnchantedVisualMetrics.sidebarTitleSpacing",
            "EnchantedVisualMetrics.sidebarControlGroupSpacing",
            "EnchantedVisualMetrics.headerPadding",
            "EnchantedVisualMetrics.headerSpacing",
            "EnchantedVisualMetrics.headerTitleSpacing",
            "EnchantedVisualMetrics.headerTitleWidth",
            "EnchantedVisualMetrics.contentPadding",
            "EnchantedVisualMetrics.statusRowSpacing",
            "EnchantedVisualMetrics.statusTextWidth",
            "EnchantedVisualMetrics.statusDotSize",
            "EnchantedVisualMetrics.loadingRowSpacing",
            "EnchantedVisualMetrics.loadingTopPadding",
            "EnchantedVisualMetrics.composerMinWidth",
            "EnchantedVisualMetrics.composerMaxWidth",
            "EnchantedVisualMetrics.composerMinHeight",
            "EnchantedVisualMetrics.composerMaxHeight",
            "EnchantedVisualMetrics.composerPadding",
            "EnchantedVisualMetrics.composerSpacing",
            "EnchantedVisualMetrics.composerEditorRadius",
            "EnchantedVisualMetrics.promptRowSpacing",
            "EnchantedVisualMetrics.messageMaxWidth",
            "EnchantedVisualMetrics.messageSpacing",
            "EnchantedVisualMetrics.messageBubbleRowSpacing",
            "EnchantedVisualMetrics.messageBubblePadding",
            "EnchantedVisualMetrics.messageBubbleSpacing",
            "EnchantedVisualMetrics.messageBubbleRadius",
            "EnchantedVisualMetrics.messageEditBorderWidth",
            "EnchantedVisualMetrics.conversationListSpacing",
            "EnchantedVisualMetrics.conversationActionsSpacing",
            "EnchantedVisualMetrics.conversationRowPadding",
            "EnchantedVisualMetrics.conversationRowSpacing",
            "EnchantedVisualMetrics.conversationRowRadius",
            "EnchantedVisualMetrics.emptyHistoryPadding",
            "EnchantedVisualMetrics.emptyHistorySpacing",
            "EnchantedVisualMetrics.emptyHistoryRadius",
            "EnchantedVisualMetrics.emptyStatePadding",
            "EnchantedVisualMetrics.emptyStateSpacing",
            "EnchantedVisualMetrics.emptyStateHeaderSpacing",
            "EnchantedVisualMetrics.emptyStateMaxWidth",
            "EnchantedVisualMetrics.promptListSpacing",
            "EnchantedVisualMetrics.promptButtonIconSpacing",
            "EnchantedVisualMetrics.promptButtonTextWidthInset",
            "EnchantedVisualMetrics.promptButtonWidth",
            "EnchantedVisualMetrics.promptButtonPadding",
            "EnchantedVisualMetrics.promptButtonRadius",
            "EnchantedVisualMetrics.primaryButtonPadding",
            "EnchantedVisualMetrics.primaryButtonIconSpacing",
            "EnchantedVisualMetrics.primaryButtonRadius",
            "EnchantedVisualMetrics.actionButtonIconSpacing",
            "EnchantedVisualMetrics.dropTargetPadding",
            "EnchantedVisualMetrics.dropTargetRadius",
            "EnchantedVisualMetrics.attachmentInputSpacing",
            "EnchantedVisualMetrics.attachmentTraySpacing",
            "EnchantedVisualMetrics.attachmentTrayChipSpacing",
            "EnchantedVisualMetrics.attachmentChipPadding",
            "EnchantedVisualMetrics.attachmentChipSpacing",
            "EnchantedVisualMetrics.attachmentChipTextSpacing",
            "EnchantedVisualMetrics.attachmentChipRadius",
            "EnchantedTypography.rootFontSize",
            "EnchantedTypography.appTitleFontSize",
            "EnchantedTypography.appTitleFontWeight",
            "EnchantedTypography.captionFontSize",
            "EnchantedTypography.sectionTitleFontSize",
            "EnchantedTypography.sectionTitleFontWeight",
            "EnchantedTypography.currentTitleFontSize",
            "EnchantedTypography.currentTitleFontWeight",
            "EnchantedTypography.messageBodyFontSize",
            "EnchantedTypography.attachmentNameFontSize",
            "EnchantedTypography.attachmentSizeFontSize",
            "EnchantedTypography.conversationTitleFontSize",
            "EnchantedTypography.conversationTitleFontWeight",
            "EnchantedTypography.conversationPreviewFontSize",
            "EnchantedTypography.warningTextFontSize",
            "weight: enchantedFontWeight(EnchantedTypography.appTitleFontWeight)",
            "weight: enchantedFontWeight(EnchantedTypography.sectionTitleFontWeight)",
            "weight: enchantedFontWeight(EnchantedTypography.currentTitleFontWeight)",
            "weight: enchantedFontWeight(EnchantedTypography.conversationTitleFontWeight)"
        ] {
            expectContains(rootView, needle)
        }

        for needle in [
            "Button(action: copyMessageContent)",
            "EnchantedCopy.copyMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.copyMessage)",
            "Button(action: editMessageContent)",
            "EnchantedCopy.editMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.editMessage)",
            "Button(action: cancelEdit)",
            "EnchantedCopy.unselectMessageTitle",
            "private func copyMessageContent()",
            "EnchantedClipboard.setString(message.content)",
            "private func editMessageContent()",
            "editMessage(message)"
        ] {
            expectContains(rootView, needle)
        }

        for needle in [
            "import QuillKit",
            "public enum EnchantedClipboard",
            "QuillClipboard.shared.setString(message)"
        ] {
            expectContains(clipboard, needle)
        }

        for backendSource in [
            appMain,
            coreApp,
            rootView
        ] {
            for forbidden in [
                "QuillEnchantedQtNativeRuntime",
                "CQuillQt6WidgetsShim",
                "QUILLUI_LINUX_BACKEND"
            ] {
                expectDoesNotContain(backendSource, forbidden)
            }
        }

        for forbidden in [
            "WindowGroup(",
            ".defaultSize(",
            ".defaultWindowSize("
        ] {
            expectDoesNotContain(coreApp, forbidden)
        }

        for forbidden in [
            "\"Quill Enchanted\"",
            "\"Ollama endpoint\"",
            "\"No models detected\"",
            "\"Ask a local model...\"",
            "\"Ask your local model\"",
            "\"This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.\"",
            "#FBFBFD",
            "#F5F5F7",
            "#E8E8ED",
            "#FFFFFF",
            "#F4F4F6",
            "#D8D8DE",
            "#1D1D1F",
            "#6E6E73",
            "#4285F4",
            "#B42318",
            "#34C759",
            "#FF9F0A",
            "#EAF2FF"
        ] {
            expectDoesNotContain(rootView, forbidden)
        }
    }

    @Test("QuillUI conversation history empty state mirrors Enchanted macOS")
    func quillConversationHistoryEmptyStateMirrorsEnchantedMacOS() throws {
        let controls = try packageSource("Sources/QuillUI/Controls.swift")
        guard let historyStart = controls.range(of: "public struct QuillConversationHistoryItem: Identifiable"),
              let nextSection = controls.range(of: "public struct QuillSidebarNavigationAction: Identifiable") else {
            Issue.record("Unable to locate QuillConversationHistoryList source")
            return
        }

        let historyList = String(controls[historyStart.lowerBound..<nextSection.lowerBound])
        expectContains(historyList, "emptyTitle: String = \"No saved chats yet\"")
        expectContains(historyList, "emptySubtitle: String = \"Start a chat and it will be saved locally.\"")
        expectContains(historyList, "if sortedItems.isEmpty")
        expectContains(historyList, "private var emptyHistory: some View")
        expectContains(historyList, "VStack(alignment: .leading, spacing: emptyHistorySpacing)")
        expectContains(historyList, "Text(emptyTitle)")
        expectContains(historyList, "Text(emptySubtitle)")
        expectContains(historyList, ".font(.system(size: emptyTitleFontSize, weight: emptyTitleFontWeight))")
        expectContains(historyList, ".font(.system(size: emptySubtitleFontSize))")
        expectContains(historyList, "private var emptyTitleFontSize: CGFloat { 15 }")
        expectContains(historyList, "private var emptySubtitleFontSize: CGFloat { 12 }")
        expectContains(historyList, "private var emptyTitleFontWeight: Font.Weight { .bold }")
        expectContains(historyList, "private var emptyHistoryPadding: CGFloat { 12 }")
        expectContains(historyList, "private var emptyHistorySpacing: CGFloat { 8 }")
        expectContains(historyList, "private var emptyHistoryCornerRadius: CGFloat { 8 }")
        expectContains(historyList, ".padding(emptyHistoryPadding)")
        expectContains(historyList, ".background(rowBackgroundColor)")
        expectContains(historyList, ".cornerRadius(emptyHistoryCornerRadius)")
        expectContains(historyList, ".accessibilityElement(children: .combine)")
        expectContains(historyList, ".accessibilityLabel(emptyTitle)")
        expectContains(historyList, ".accessibilityValue(emptySubtitle)")
        expectContains(historyList, ".help(emptySubtitle)")
        expectDoesNotContain(historyList, "No conversations yet")
        expectDoesNotContain(historyList, ".font(.caption)")
        expectDoesNotContain(historyList, ".padding(.top, 12)")
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
        let controlsSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillUI/Controls.swift"),
            encoding: .utf8
        )
        let upstreamMacOSChat = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Chat/ChatView_macOS.swift"),
            encoding: .utf8
        )
        let upstreamMacOSInputFields = try String(
            contentsOf: root.appendingPathComponent(".upstream/enchanted/Enchanted/UI/macOS/Chat/Components/InputFields_macOS.swift"),
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
        let enchantedClipboardSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedClipboard.swift"),
            encoding: .utf8
        )
        let enchantedModelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/QuillEnchantedCore/EnchantedModel.swift"),
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

        expectContains(manifest, ".init(product: \"quill-enchanted\", target: \"QuillEnchanted\", qtPath: \"Sources/QuillEnchantedQt\", qtRuntime: .enchantedQtNative)")
        expectContains(manifest, "path: \"Sources/QuillEnchantedQt\"")
        expectContains(manifest, "QuillEnchantedQtNativeRuntime")
        expectContains(manifest, "nativeQt: [\"QuillEnchantedQtNativeRuntime\"]")
        expectContains(manifest, ".define(\"QUILLUI_ENCHANTED_QT_NATIVE_BACKEND\")")
        expectContains(manifest, "name: \"QuillEnchantedShared\"")
        expectContains(manifest, "dependencies: [\"QuillEnchantedData\", \"QuillFoundation\"]")
        expectContains(manifest, "name: \"QuillEnchantedData\"")
        expectContains(manifest, "dependencies: [\"QuillData\"]")
        expectContains(manifest, "path: \"Sources/QuillEnchantedData\"")
        expectContains(manifest, "dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillEnchantedData\", \"QuillUI\", \"QuillFoundation\", \"QuillKit\"]")
        expectContains(manifest, "dependencies: [.target(name: \"QuillEnchantedShared\"), \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]")
        expectContains(manifest, "name: \"QuillEnchantedQtNativeRuntime\"")
        expectContains(manifest, "dependencies: [.target(name: \"QuillEnchantedShared\"), \"QuillEnchantedData\", \"CQuillQt6WidgetsShim\", \"QuillQtNativeRuntimeSupport\"]")
        expectContains(qtMain, "#if QUILLUI_ENCHANTED_QT_NATIVE_BACKEND")
        expectContains(qtMain, "QuillEnchantedQtNativeApp.run()")
        expectContains(qtMain, "QuillQtApp.run(QuillEnchantedQtApp.self)")
        expectContains(qtMain, "import QuillEnchantedShared")
        expectContains(qtMain, "EnchantedCopy.windowTitle")
        expectContains(qtMain, "width: Double(EnchantedVisualMetrics.defaultWindowWidth)")
        expectContains(qtMain, "height: Double(EnchantedVisualMetrics.defaultWindowHeight)")
        expectContains(coreApp, "width: Double(EnchantedVisualMetrics.defaultWindowWidth)")
        expectContains(coreApp, "height: Double(EnchantedVisualMetrics.defaultWindowHeight)")
        expectContains(upstreamSlice, "import QuillEnchantedShared")
        expectContains(upstreamSlice, "width: Double(EnchantedVisualMetrics.defaultWindowWidth)")
        expectContains(upstreamSlice, "height: Double(EnchantedVisualMetrics.defaultWindowHeight)")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.sidebarWidth")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.sidebarIdealWidth")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.sidebarMaxWidth")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.composerMinWidth")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.composerMaxWidth")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.composerPadding")
        expectContains(upstreamSlice, "EnchantedVisualMetrics.messageMaxWidth")
        expectContains(upstreamSlice, "EnchantedPalette.canvasColor")
        expectContains(upstreamSlice, "EnchantedPalette.sidebarColor")
        expectContains(upstreamSlice, "EnchantedPalette.sidebarSelectedColor")
        expectContains(upstreamSlice, "EnchantedPalette.cardQuietColor")
        expectContains(upstreamSlice, "EnchantedPalette.destructiveColor")
        expectContains(upstreamSlice, "EnchantedTypography.captionFontSize")
        expectContains(upstreamSlice, "EnchantedTypography.currentTitleFontSize")
        expectContains(upstreamSlice, "EnchantedTypography.messageBodyFontSize")
        expectContains(upstreamSlice, "EnchantedCopy.appTitle")
        expectContains(upstreamSlice, "QuillAppWindow.scene(\n            EnchantedCopy.windowTitle,")
        expectContains(upstreamSlice, "QuillChatEmptyState(brandTitle: EnchantedCopy.appTitle")
        expectContains(upstreamSlice, "message: EnchantedCopy.unreachableOllamaMessage")
        expectContains(upstreamSlice, "actionTitle: EnchantedCopy.settingsTitle")
        expectContains(upstreamSlice, "content: EnchantedCopy.systemLaunchMessage")
        expectDoesNotContain(upstreamSlice, "Quill is unreachable")
        expectDoesNotContain(upstreamSlice, "Quill API endpoint")
        expectDoesNotContain(upstreamSlice, "QuillUI is rendering this upstream-shaped chat slice on Linux.")
        expectContains(upstreamSlice, "weight: enchantedFontWeight(EnchantedTypography.sectionTitleFontWeight)")
        expectContains(upstreamSlice, "weight: enchantedFontWeight(EnchantedTypography.currentTitleFontWeight)")
        expectDoesNotContain(upstreamSlice, "\"Quill Enchanted Upstream Slice\"")
        expectDoesNotContain(upstreamSlice, "brandTitle: \"Quill\"")
        expectDoesNotContain(upstreamSlice, ".fontWeight(.semibold)")
        expectDoesNotContain(upstreamSlice, ".font(.caption)")
        expectDoesNotContain(upstreamSlice, ".font(.caption2)")
        expectDoesNotContain(upstreamSlice, ".font(.headline)")
        expectDoesNotContain(upstreamSlice, "Text(\"Quill Chat\")")
        expectDoesNotContain(upstreamSlice, ".font(.system(size: 14))")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#FBFBFD\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#F5F5F7\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#E8E8ED\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#F4F4F6\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#D8D8DE\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#1D1D1F\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#6E6E73\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#4285F4\")")
        expectDoesNotContain(upstreamSlice, "Color(hex: \"#B42318\")")
        expectContains(upstreamSlice, "EnchantedPromptCatalog.visibleEmptyConversationPrompts.map")
        expectDoesNotContain(upstreamSlice, "private let prompts = [")
        expectContains(upstreamSlice, "EnchantedCopy.attachmentDefaultPrompt")
        expectContains(runtime, "import QuillEnchantedData")
        expectContains(runtime, "import QuillEnchantedShared")
        expectContains(runtime, "imagePreviewFallback: EnchantedIcon.imagePreviewFallback")
        expectContains(runtime, "unavailableModel: EnchantedIcon.unavailableModel")
        expectContains(genericQtRuntime, "import QuillEnchantedShared")
        expectContains(genericQtRuntime, "minimumWidth: EnchantedVisualMetrics.minimumWindowWidth")
        expectContains(genericQtRuntime, "minimumHeight: EnchantedVisualMetrics.minimumWindowHeight")
        expectContains(genericQtRuntime, "defaultWidth: EnchantedVisualMetrics.defaultWindowWidth")
        expectContains(genericQtRuntime, "defaultHeight: EnchantedVisualMetrics.defaultWindowHeight")
        expectContains(genericQtRuntime, "sidebarWidth: EnchantedVisualMetrics.sidebarWidth")
        expectContains(genericQtRuntime, "detailWidth: EnchantedVisualMetrics.detailWidth")
        expectContains(genericQtRuntime, "rootFontSize: EnchantedTypography.rootFontSize")
        expectContains(genericQtRuntime, "appTitleFontSize: EnchantedTypography.appTitleFontSize")
        expectContains(genericQtRuntime, "appTitleFontWeight: EnchantedTypography.appTitleFontWeight")
        expectContains(genericQtRuntime, "captionFontSize: EnchantedTypography.captionFontSize")
        expectContains(genericQtRuntime, "sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize")
        expectContains(genericQtRuntime, "sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight")
        expectContains(genericQtRuntime, "currentTitleFontSize: EnchantedTypography.currentTitleFontSize")
        expectContains(genericQtRuntime, "currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight")
        expectContains(genericQtRuntime, "messageBodyFontSize: EnchantedTypography.messageBodyFontSize")
        expectContains(genericQtRuntime, "conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize")
        expectContains(genericQtRuntime, "conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight")
        expectContains(runtime, "EnchantedModelContext.default()")
        expectContains(runtime, "QuillEnchantedQtSnapshot.preview")
        expectContains(runtime, "QuillEnchantedQtSnapshot.persisted(")
        expectContains(runtime, "quill_enchanted_qt_run_app_json")
        expectContains(runtime, "quill_enchanted_qt_perform_action_json")
        expectContains(runtime, "quill_enchanted_qt_free_string")
        expectContains(sharedPrompts, "public enum EnchantedCopy")
        expectContains(runtime, "windowTitle: EnchantedCopy.windowTitle")
        expectContains(runtime, "sidebarTitle: EnchantedCopy.appTitle")
        expectContains(runtime, "sidebarSubtitle: EnchantedCopy.sidebarSubtitle")
        expectContains(runtime, "endpointLabel: EnchantedCopy.endpointLabel")
        expectContains(runtime, "modelLabel: EnchantedCopy.modelLabel")
        expectContains(runtime, "conversationsTitle: EnchantedCopy.conversationsTitle")
        expectContains(runtime, "noModelsTitle: EnchantedCopy.noModelsTitle")
        expectContains(runtime, "chooseLocalModelStatus: EnchantedCopy.chooseLocalModelStatus")
        expectContains(runtime, "usingModelStatusPrefix: EnchantedCopy.usingModelStatusPrefix")
        expectContains(runtime, "usingModelStatusSeparator: EnchantedCopy.usingModelStatusSeparator")
        expectContains(runtime, "deleteChatTitle: EnchantedCopy.deleteChatTitle")
        expectContains(runtime, "copyMessageTitle: EnchantedCopy.copyMessageTitle")
        expectContains(runtime, "editMessageTitle: EnchantedCopy.editMessageTitle")
        expectContains(runtime, "unselectMessageTitle: EnchantedCopy.unselectMessageTitle")
        expectContains(runtime, "copyMessage: EnchantedIcon.copyMessage")
        expectContains(runtime, "editMessage: EnchantedIcon.editMessage")
        expectContains(runtime, "clearAllTitle: EnchantedCopy.clearAllTitle")
        expectContains(runtime, "refreshModelsTitle: EnchantedCopy.refreshModelsTitle")
        expectContains(runtime, "completionsTitle: EnchantedCopy.completionsTitle")
        expectContains(runtime, "shortcutsTitle: EnchantedCopy.shortcutsTitle")
        expectContains(runtime, "settingsTitle: EnchantedCopy.settingsTitle")
        expectContains(runtime, "completionsStatus: EnchantedCopy.completionsStatus")
        expectContains(runtime, "shortcutsStatus: EnchantedCopy.shortcutsStatus")
        expectContains(runtime, "settingsStatus: EnchantedCopy.settingsStatus")
        expectContains(runtime, "completionsPanelSubtitle: EnchantedCopy.completionsPanelSubtitle")
        expectContains(runtime, "shortcutsPanelSubtitle: EnchantedCopy.shortcutsPanelSubtitle")
        expectContains(runtime, "settingsPanelSubtitle: EnchantedCopy.settingsPanelSubtitle")
        expectContains(runtime, "dropTargetTitle: EnchantedCopy.dropTargetTitle")
        expectDoesNotContain(runtime, "completionsStatus: EnchantedCopy.completionsTitle")
        expectDoesNotContain(runtime, "shortcutsStatus: EnchantedCopy.shortcutsTitle")
        expectDoesNotContain(runtime, "settingsStatus: EnchantedCopy.settingsTitle")
        expectContains(runtime, "newConversationButtonTitle: EnchantedCopy.newChatTitle")
        expectDoesNotContain(runtime, "newChatTitle: EnchantedCopy.newChatTitle")
        expectContains(runtime, "newConversationTitle: EnchantedCopy.newConversationTitle")
        expectDoesNotContain(runtime, "noMessagesYet: EnchantedCopy.noMessagesYet")
        expectContains(runtime, "self.lastMessage = summary.lastMessage")
        expectDoesNotContain(runtime, "summary.lastMessage.isEmpty ? EnchantedCopy.noMessagesYet : summary.lastMessage")
        expectContains(runtime, "attachTitle: EnchantedCopy.attachTitle")
        expectContains(runtime, "clearAttachmentsTitle: EnchantedCopy.clearAttachmentsTitle")
        expectContains(runtime, "attachmentsClearedStatus: EnchantedCopy.attachmentsClearedStatus")
        expectContains(runtime, "attachmentRemovedEmptyStatus: EnchantedCopy.attachmentRemovedEmptyStatus")
        expectDoesNotContain(runtime, "attachmentRemovedEmptyStatus: EnchantedCopy.readyStatus")
        expectContains(runtime, "removeAttachmentTooltip: EnchantedCopy.removeAttachmentTooltip")
        expectContains(runtime, "imageReadyStatusSingular: EnchantedCopy.imageReadyStatusSingular")
        expectContains(runtime, "imageReadyStatusPluralUnit: EnchantedCopy.imageReadyStatusPluralUnit")
        expectContains(runtime, "attachmentsTitle: EnchantedCopy.attachmentsTitle")
        expectContains(runtime, "attachmentDefaultPrompt: EnchantedCopy.attachmentDefaultPrompt")
        expectContains(runtime, "attachmentDefaultPromptPlural: EnchantedCopy.attachmentDefaultPromptPlural")
        expectContains(runtime, "attachmentSummaryTitle: EnchantedCopy.attachmentSummaryTitle")
        expectContains(runtime, "composerPlaceholder: EnchantedCopy.composerPlaceholder")
        expectContains(sharedPrompts, "public static let composerPlaceholder = \"Message\"")
        expectContains(upstreamMacOSInputFields, "TextField(\"Message\"")
        expectDoesNotContain(sharedPrompts, "public static let composerPlaceholder = \"Ask a local model...\"")
        for needle in [
            "attachmentMaxByteCount: PendingImageAttachment.maxByteCount",
            "supportedAttachmentExtensions: PendingImageAttachment.supportedExtensions.sorted()",
            "unsupportedAttachmentSuffix: EnchantedCopy.unsupportedAttachmentSuffix",
            "unreadableAttachmentPrefix: EnchantedCopy.unreadableAttachmentPrefix",
            "unreadableAttachmentSuffix: EnchantedCopy.unreadableAttachmentSuffix",
            "oversizedAttachmentMiddle: EnchantedCopy.oversizedAttachmentMiddle",
            "oversizedAttachmentSuffix: EnchantedCopy.oversizedAttachmentSuffix",
        ] {
            expectContains(runtime, needle)
        }
        expectContains(runtime, "sendTitle: EnchantedCopy.sendTitle")
        expectContains(runtime, "stopTitle: EnchantedCopy.stopTitle")
        expectContains(runtime, "stoppingStatus: EnchantedCopy.stoppingStatus")
        expectContains(runtime, "status: EnchantedCopy.readyForLocalInferenceStatus")
        expectContains(runtime, "endpoint: EnchantedCopy.defaultEndpoint")
        expectContains(runtime, "isLoading: false")
        expectContains(sharedPrompts, "public enum EnchantedPreviewFixture")
        expectContains(sharedPrompts, "public static let selectedModel = \"llama3.1:8b\"")
        expectContains(sharedPrompts, "public static let selectedConversationID = \"daily-brief\"")
        expectContains(sharedPrompts, "public static let launchConversationMessages")
        expectContains(sharedPrompts, "public static let attachmentConversationMessages")
        expectContains(runtime, "selectedModel: EnchantedPreviewFixture.selectedModel")
        expectContains(runtime, "selectedConversationID: EnchantedPreviewFixture.selectedConversationID")
        expectContains(runtime, "models: EnchantedPreviewFixture.models")
        expectContains(runtime, "emptyHistoryTitle: EnchantedCopy.emptyHistoryTitle")
        expectContains(runtime, "emptyHistorySubtitle: EnchantedCopy.emptyHistorySubtitle")
        expectContains(runtime, "emptyStateTitle: EnchantedCopy.emptyStateTitle")
        expectContains(runtime, "emptyStateSubtitle: EnchantedCopy.emptyStateSubtitle")
        expectContains(runtime, "userRoleLabel: EnchantedCopy.userRoleLabel")
        expectContains(runtime, "assistantRoleLabel: EnchantedCopy.assistantRoleLabel")
        expectContains(runtime, "systemRoleLabel: EnchantedCopy.systemRoleLabel")
        expectContains(runtime, "prompts: EnchantedPromptCatalog.visibleEmptyConversationPrompts.map(QuillEnchantedQtSnapshot.Prompt.init)")
        expectContains(runtime, "var messages: [Message]? = nil")
        expectContains(runtime, "conversations: EnchantedPreviewFixture.conversations.map { Conversation($0) }")
        expectContains(runtime, "messages: EnchantedPreviewFixture.messages.map { Message($0) }")
        expectDoesNotContain(runtime, "private static let launchConversationMessages")
        expectDoesNotContain(runtime, "messages: launchConversationMessages")
        expectDoesNotContain(runtime, "messages: attachmentConversationMessages")
        expectContains(runtime, "canvasColor: EnchantedPalette.canvasColor")
        expectContains(runtime, "warningColor: EnchantedPalette.warningColor")
        expectContains(runtime, "systemColor: EnchantedPalette.systemColor")
        expectContains(runtime, "quoteRuleColor: EnchantedPalette.quoteRuleColor")
        expectContains(runtime, "codeBlockColor: EnchantedPalette.codeBlockColor")
        expectContains(runtime, "dividerColor: EnchantedPalette.dividerColor")
        expectContains(runtime, "cardBorderColor: EnchantedPalette.cardBorderColor")
        expectContains(runtime, "messageBorderColor: EnchantedPalette.messageBorderColor")
        expectContains(runtime, "controlBorderColor: EnchantedPalette.controlBorderColor")
        expectDoesNotContain(runtime, "dropTargetBorderColor: EnchantedPalette.dropTargetBorderColor")
        expectContains(runtime, "disabledButtonBackgroundColor: EnchantedPalette.disabledButtonBackgroundColor")
        expectContains(runtime, "disabledButtonForegroundColor: EnchantedPalette.disabledButtonForegroundColor")
        expectContains(runtime, "disabledTextColor: EnchantedPalette.disabledTextColor")
        expectContains(runtime, "minimumWidth: EnchantedVisualMetrics.minimumWindowWidth")
        expectContains(runtime, "minimumHeight: EnchantedVisualMetrics.minimumWindowHeight")
        expectContains(runtime, "defaultWidth: EnchantedVisualMetrics.defaultWindowWidth")
        expectContains(runtime, "defaultHeight: EnchantedVisualMetrics.defaultWindowHeight")
        expectContains(runtime, "rootFontSize: EnchantedTypography.rootFontSize")
        expectContains(runtime, "appTitleFontSize: EnchantedTypography.appTitleFontSize")
        expectContains(runtime, "appTitleFontWeight: EnchantedTypography.appTitleFontWeight")
        expectContains(runtime, "captionFontSize: EnchantedTypography.captionFontSize")
        expectContains(runtime, "sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize")
        expectContains(runtime, "sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight")
        expectContains(runtime, "currentTitleFontSize: EnchantedTypography.currentTitleFontSize")
        expectContains(runtime, "currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight")
        expectContains(runtime, "messageBodyFontSize: EnchantedTypography.messageBodyFontSize")
        expectContains(runtime, "markdownHeading1FontSize: EnchantedTypography.markdownHeading1FontSize")
        expectContains(runtime, "markdownHeading2FontSize: EnchantedTypography.markdownHeading2FontSize")
        expectContains(runtime, "markdownHeadingFontSize: EnchantedTypography.markdownHeadingFontSize")
        expectContains(runtime, "markdownHeadingFontWeight: EnchantedTypography.markdownHeadingFontWeight")
        expectContains(runtime, "markdownCodeLanguageFontSize: EnchantedTypography.markdownCodeLanguageFontSize")
        expectContains(runtime, "markdownCodeFontSize: EnchantedTypography.markdownCodeFontSize")
        expectContains(runtime, "attachmentNameFontSize: EnchantedTypography.attachmentNameFontSize")
        expectContains(runtime, "attachmentSizeFontSize: EnchantedTypography.attachmentSizeFontSize")
        expectContains(runtime, "conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize")
        expectContains(runtime, "conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight")
        expectContains(runtime, "conversationPreviewFontSize: EnchantedTypography.conversationPreviewFontSize")
        expectContains(runtime, "warningTextFontSize: EnchantedTypography.warningTextFontSize")
        expectContains(runtime, "chipRemoveButtonFontWeight: EnchantedTypography.chipRemoveButtonFontWeight")
        expectContains(runtime, "sidebarWidth: EnchantedVisualMetrics.sidebarWidth")
        expectContains(runtime, "sidebarPadding: EnchantedVisualMetrics.sidebarPadding")
        expectContains(runtime, "sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing")
        expectContains(runtime, "sidebarTitleSpacing: EnchantedVisualMetrics.sidebarTitleSpacing")
        expectContains(runtime, "sidebarControlGroupSpacing: EnchantedVisualMetrics.sidebarControlGroupSpacing")
        expectContains(runtime, "statusRowSpacing: EnchantedVisualMetrics.statusRowSpacing")
        expectContains(runtime, "statusTextWidth: EnchantedVisualMetrics.statusTextWidth")
        expectContains(runtime, "statusDotSize: EnchantedVisualMetrics.statusDotSize")
        expectContains(runtime, "statusDotRadius: EnchantedVisualMetrics.statusDotRadius")
        expectContains(runtime, "conversationListSpacing: EnchantedVisualMetrics.conversationListSpacing")
        expectContains(runtime, "conversationRowPadding: EnchantedVisualMetrics.conversationRowPadding")
        expectContains(runtime, "conversationRowSpacing: EnchantedVisualMetrics.conversationRowSpacing")
        expectContains(runtime, "conversationRowRadius: EnchantedVisualMetrics.conversationRowRadius")
        expectContains(runtime, "conversationListItemRadius: EnchantedVisualMetrics.conversationListItemRadius")
        expectContains(runtime, "conversationListItemVerticalMargin: EnchantedVisualMetrics.conversationListItemVerticalMargin")
        expectContains(runtime, "conversationListItemPadding: EnchantedVisualMetrics.conversationListItemPadding")
        expectContains(runtime, "conversationActionsSpacing: EnchantedVisualMetrics.conversationActionsSpacing")
        expectContains(runtime, "attachmentChipPadding: EnchantedVisualMetrics.attachmentChipPadding")
        expectContains(runtime, "attachmentChipSpacing: EnchantedVisualMetrics.attachmentChipSpacing")
        expectContains(runtime, "attachmentChipTextSpacing: EnchantedVisualMetrics.attachmentChipTextSpacing")
        expectContains(runtime, "attachmentChipRadius: EnchantedVisualMetrics.attachmentChipRadius")
        expectContains(runtime, "attachmentTraySpacing: EnchantedVisualMetrics.attachmentTraySpacing")
        expectContains(runtime, "attachmentTrayChipSpacing: EnchantedVisualMetrics.attachmentTrayChipSpacing")
        expectDoesNotContain(runtime, "attachmentInputHorizontalPadding: EnchantedVisualMetrics.attachmentInputHorizontalPadding")
        expectDoesNotContain(runtime, "attachmentInputVerticalPadding: EnchantedVisualMetrics.attachmentInputVerticalPadding")
        expectContains(runtime, "attachmentInputSpacing: EnchantedVisualMetrics.attachmentInputSpacing")
        expectContains(runtime, "headerTitleWidth: EnchantedVisualMetrics.headerTitleWidth")
        expectContains(runtime, "headerSpacing: EnchantedVisualMetrics.headerSpacing")
        expectContains(runtime, "headerTitleSpacing: EnchantedVisualMetrics.headerTitleSpacing")
        expectContains(runtime, "headerPadding: EnchantedVisualMetrics.headerPadding")
        expectContains(runtime, "composerPadding: EnchantedVisualMetrics.composerPadding")
        expectContains(runtime, "composerSpacing: EnchantedVisualMetrics.composerSpacing")
        expectContains(runtime, "promptRowSpacing: EnchantedVisualMetrics.promptRowSpacing")
        expectContains(runtime, "composerMinWidth: EnchantedVisualMetrics.composerMinWidth")
        expectContains(runtime, "composerMaxWidth: EnchantedVisualMetrics.composerMaxWidth")
        expectContains(runtime, "composerMinHeight: EnchantedVisualMetrics.composerMinHeight")
        expectContains(runtime, "composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight")
        expectContains(runtime, "messageMaxWidth: EnchantedVisualMetrics.messageMaxWidth")
        expectContains(runtime, "contentPadding: EnchantedVisualMetrics.contentPadding")
        expectContains(runtime, "loadingRowSpacing: EnchantedVisualMetrics.loadingRowSpacing")
        expectContains(runtime, "loadingTopPadding: EnchantedVisualMetrics.loadingTopPadding")
        expectContains(runtime, "loadingSpinnerSize: EnchantedVisualMetrics.loadingSpinnerSize")
        expectContains(runtime, "messageSpacing: EnchantedVisualMetrics.messageSpacing")
        expectContains(runtime, "messageBubbleRowSpacing: EnchantedVisualMetrics.messageBubbleRowSpacing")
        expectContains(runtime, "messageBubblePadding: EnchantedVisualMetrics.messageBubblePadding")
        expectContains(runtime, "messageBubbleSpacing: EnchantedVisualMetrics.messageBubbleSpacing")
        expectContains(runtime, "messageBubbleRadius: EnchantedVisualMetrics.messageBubbleRadius")
        expectContains(runtime, "messageEditBorderWidth: EnchantedVisualMetrics.messageEditBorderWidth")
        expectContains(runtime, "markdownBlockSpacing: EnchantedVisualMetrics.markdownBlockSpacing")
        expectContains(runtime, "markdownListItemSpacing: EnchantedVisualMetrics.markdownListItemSpacing")
        expectContains(runtime, "markdownNumberWidth: EnchantedVisualMetrics.markdownNumberWidth")
        expectContains(runtime, "markdownQuoteSpacing: EnchantedVisualMetrics.markdownQuoteSpacing")
        expectContains(runtime, "markdownQuoteRuleWidth: EnchantedVisualMetrics.markdownQuoteRuleWidth")
        expectContains(runtime, "markdownQuoteRuleRadius: EnchantedVisualMetrics.markdownQuoteRuleRadius")
        expectContains(runtime, "markdownQuoteVerticalPadding: EnchantedVisualMetrics.markdownQuoteVerticalPadding")
        expectContains(runtime, "markdownCodeBlockSpacing: EnchantedVisualMetrics.markdownCodeBlockSpacing")
        expectContains(runtime, "markdownCodeBlockPadding: EnchantedVisualMetrics.markdownCodeBlockPadding")
        expectContains(runtime, "markdownCodeBlockRadius: EnchantedVisualMetrics.markdownCodeBlockRadius")
        expectContains(runtime, "emptyHistoryPadding: EnchantedVisualMetrics.emptyHistoryPadding")
        expectContains(runtime, "emptyHistorySpacing: EnchantedVisualMetrics.emptyHistorySpacing")
        expectContains(runtime, "emptyHistoryRadius: EnchantedVisualMetrics.emptyHistoryRadius")
        expectContains(runtime, "emptyStatePadding: EnchantedVisualMetrics.emptyStatePadding")
        expectContains(runtime, "emptyStateSpacing: EnchantedVisualMetrics.emptyStateSpacing")
        expectContains(runtime, "emptyStateHeaderSpacing: EnchantedVisualMetrics.emptyStateHeaderSpacing")
        expectContains(runtime, "emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth")
        expectContains(runtime, "promptListSpacing: EnchantedVisualMetrics.promptListSpacing")
        expectContains(runtime, "promptButtonIconSpacing: EnchantedVisualMetrics.promptButtonIconSpacing")
        expectContains(runtime, "promptButtonTextWidthInset: EnchantedVisualMetrics.promptButtonTextWidthInset")
        expectContains(runtime, "promptButtonMinHeight: EnchantedVisualMetrics.promptButtonMinHeight")
        expectContains(runtime, "promptButtonWidth: EnchantedVisualMetrics.promptButtonWidth")
        expectContains(runtime, "promptButtonPadding: EnchantedVisualMetrics.promptButtonPadding")
        expectContains(runtime, "promptButtonRadius: EnchantedVisualMetrics.promptButtonRadius")
        expectContains(runtime, "primaryButtonPadding: EnchantedVisualMetrics.primaryButtonPadding")
        expectContains(runtime, "primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding")
        expectContains(runtime, "primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding")
        expectContains(runtime, "primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius")
        expectContains(runtime, "primaryButtonIconSpacing: EnchantedVisualMetrics.primaryButtonIconSpacing")
        expectContains(runtime, "actionButtonIconSize: EnchantedVisualMetrics.actionButtonIconSize")
        expectContains(runtime, "actionButtonIconSpacing: EnchantedVisualMetrics.actionButtonIconSpacing")
        expectContains(runtime, "secondaryButtonVerticalPadding: EnchantedVisualMetrics.secondaryButtonVerticalPadding")
        expectContains(runtime, "secondaryButtonHorizontalPadding: EnchantedVisualMetrics.secondaryButtonHorizontalPadding")
        expectContains(runtime, "secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius")
        expectContains(runtime, "chipRemoveButtonVerticalPadding: EnchantedVisualMetrics.chipRemoveButtonVerticalPadding")
        expectContains(runtime, "chipRemoveButtonHorizontalPadding: EnchantedVisualMetrics.chipRemoveButtonHorizontalPadding")
        expectContains(runtime, "controlPadding: EnchantedVisualMetrics.controlPadding")
        expectContains(runtime, "controlRadius: EnchantedVisualMetrics.controlRadius")
        expectContains(runtime, "dropTargetPadding: EnchantedVisualMetrics.dropTargetPadding")
        expectContains(runtime, "dropTargetRadius: EnchantedVisualMetrics.dropTargetRadius")
        expectContains(runtime, "composerEditorRadius: EnchantedVisualMetrics.composerEditorRadius")
        expectContains(runtime, "context.insert(ConversationDraft(title: EnchantedCopy.newConversationTitle))")
        expectContains(runtime, "context.deleteConversation(id: conversationID)")
        expectContains(runtime, "context.deleteAllConversations()")
        expectContains(runtime, "var messageText: String?")
        expectContains(runtime, "var endpoint: String?")
        expectContains(runtime, "var selectedModel: String?")
        expectContains(runtime, "var models: [String]?")
        expectContains(runtime, "var attachmentPaths: [String]?")
        expectContains(runtime, "case \"sendMessage\":")
        expectContains(runtime, "case \"refreshModels\", \"configureEndpoint\":")
        expectContains(runtime, "case \"selectModel\":")
        expectContains(runtime, "OllamaClient(baseURL: endpoint).fetchModels()")
        expectContains(runtime, "context.updateConversationTitle(id: selectedConversationID, title: prompt.quillTitle())")
        expectContains(runtime, "var selectedConversationID = try existingConversationID(request.conversationID, context: context)")
        expectContains(runtime, "selectedConversationID: selectedConversationID,")
        expectDoesNotContain(runtime, "selectedConversationID: existingConversationID(request.conversationID, context: context),")
        expectContains(runtime, "let displayContent = PendingImageAttachment.displayContent(prompt: prompt, attachments: attachments)")
        expectContains(runtime, "content: displayContent")
        expectContains(runtime, "imagesForLastUserMessage: encodedImages")
        expectContains(runtime, "private static func imageAttachments(from rawPaths: [String]) throws -> [PendingImageAttachment]")
        expectContains(runtime, "var kind: String")
        expectContains(runtime, "self.kind = prompt.kind.rawValue")
        expectContains(sharedPrompts, "public struct EnchantedPrompt: Codable, Equatable, Hashable, Sendable")
        expectContains(sharedPrompts, "public enum Kind: String, Codable, Equatable, Hashable, Sendable")
        expectContains(sharedPrompts, "case question")
        expectContains(sharedPrompts, "case action")
        expectContains(sharedPrompts, "public init(title: String, kind: Kind)")
        expectContains(sharedPrompts, "public static let questionIconName = EnchantedPrompt.Kind.question.systemImage")
        expectContains(sharedPrompts, "public static let actionIconName = EnchantedPrompt.Kind.action.systemImage")
        expectContains(sharedPrompts, "kind: .question")
        expectContains(sharedPrompts, "kind: .action")
        expectContains(sharedPrompts, "public static let emptyConversationVisiblePromptCount = 4")
        expectContains(sharedPrompts, "public static let visibleEmptyConversationPrompts = Array(emptyConversationPrompts.prefix(emptyConversationVisiblePromptCount))")
        expectContains(sharedPrompts, "public static let emptyConversationTitles = emptyConversationPrompts.map(\\.title)")
        expectContains(sharedPrompts, "public enum EnchantedPalette")
        expectContains(sharedPrompts, "public static let canvasColor = \"#FBFBFD\"")
        expectContains(sharedPrompts, "public static let sidebarColor = \"#F5F5F7\"")
        expectContains(sharedPrompts, "public static let sidebarSelectedColor = \"#E8E8ED\"")
        expectContains(sharedPrompts, "public static let cardQuietColor = \"#F4F4F6\"")
        expectContains(sharedPrompts, "public static let hairlineColor = \"#D8D8DE\"")
        expectContains(sharedPrompts, "public static let textColor = \"#1D1D1F\"")
        expectContains(sharedPrompts, "public static let secondaryTextColor = \"#6E6E73\"")
        expectContains(sharedPrompts, "public static let accentColor = \"#4285F4\"")
        expectContains(sharedPrompts, "public static let destructiveColor = \"#B42318\"")
        expectContains(sharedPrompts, "public static let warningColor = \"#FF9F0A\"")
        expectContains(sharedPrompts, "public static let primaryColor = EnchantedPalette.accentColor")
        expectContains(sharedPrompts, "public static let codeBlockColor = EnchantedPalette.cardQuietColor")
        expectContains(sharedPrompts, "public enum EnchantedVisualMetrics")
        expectContains(sharedPrompts, "public static let minimumWindowWidth = 980")
        expectContains(sharedPrompts, "public static let minimumWindowHeight = 680")
        expectContains(sharedPrompts, "public static let defaultWindowWidth = 1180")
        expectContains(sharedPrompts, "public static let defaultWindowHeight = 760")
        expectContains(sharedPrompts, "public static let sidebarWidth = 300")
        expectContains(sharedPrompts, "public static let sidebarIdealWidth = 330")
        expectContains(sharedPrompts, "public static let sidebarMaxWidth = 360")
        expectContains(sharedPrompts, "public static let detailWidth = defaultWindowWidth - sidebarWidth")
        expectContains(sharedPrompts, "public static let sidebarPadding = 18")
        expectContains(sharedPrompts, "public static let sidebarSpacing = 14")
        expectContains(sharedPrompts, "public static let sidebarTitleSpacing = 4")
        expectContains(sharedPrompts, "public static let sidebarControlGroupSpacing = 7")
        expectContains(sharedPrompts, "public static let statusRowSpacing = 8")
        expectContains(sharedPrompts, "public static let statusTextWidth = 240")
        expectContains(sharedPrompts, "public static let statusDotSize = 9")
        expectContains(sharedPrompts, "public static let statusDotRadius = 9")
        expectContains(sharedPrompts, "public static let headerTitleWidth = 560")
        expectContains(sharedPrompts, "public static let headerSpacing = 12")
        expectContains(sharedPrompts, "public static let headerTitleSpacing = 4")
        expectContains(sharedPrompts, "public static let headerPadding = 18")
        expectContains(sharedPrompts, "public static let contentPadding = 22")
        expectContains(sharedPrompts, "public static let loadingRowSpacing = 8")
        expectContains(sharedPrompts, "public static let loadingTopPadding = 8")
        expectContains(sharedPrompts, "public static let loadingSpinnerSize = 16")
        expectContains(sharedPrompts, "public static let promptButtonWidth = 620")
        expectContains(sharedPrompts, "public static let promptButtonMinHeight = 48")
        expectContains(sharedPrompts, "public static let emptyStateMaxWidth = 680")
        expectContains(sharedPrompts, "public static let emptyStatePadding = 26")
        expectContains(sharedPrompts, "public static let emptyStateSpacing = 18")
        expectContains(sharedPrompts, "public static let emptyStateHeaderSpacing = 8")
        expectContains(sharedPrompts, "public static let promptListSpacing = 10")
        expectContains(sharedPrompts, "public static let promptButtonIconSpacing = 10")
        expectContains(sharedPrompts, "public static let promptButtonTextWidthInset = 80")
        expectContains(sharedPrompts, "public static let promptButtonPadding = 12")
        expectContains(sharedPrompts, "public static let promptButtonRadius = 8")
        expectContains(sharedPrompts, "public static let primaryButtonPadding = 12")
        expectContains(sharedPrompts, "public static let primaryButtonIconSpacing = 8")
        expectContains(sharedPrompts, "public static let primaryButtonVerticalPadding = primaryButtonPadding")
        expectContains(sharedPrompts, "public static let primaryButtonHorizontalPadding = primaryButtonPadding")
        expectContains(sharedPrompts, "public static let primaryButtonRadius = 8")
        expectContains(sharedPrompts, "public static let actionButtonIconSpacing = 6")
        expectContains(sharedPrompts, "public static let actionButtonIconSize = 16")
        expectContains(sharedPrompts, "public static let secondaryButtonVerticalPadding = 7")
        expectContains(sharedPrompts, "public static let secondaryButtonHorizontalPadding = 10")
        expectContains(sharedPrompts, "public static let secondaryButtonRadius = 7")
        expectContains(sharedPrompts, "public static let dropTargetPadding = 8")
        expectContains(sharedPrompts, "public static let dropTargetRadius = 8")
        expectContains(sharedPrompts, "public static let conversationListSpacing = 8")
        expectContains(sharedPrompts, "public static let conversationActionsSpacing = 8")
        expectContains(sharedPrompts, "public static let conversationRowPadding = 11")
        expectContains(sharedPrompts, "public static let conversationRowSpacing = 5")
        expectContains(sharedPrompts, "public static let conversationRowRadius = 8")
        expectContains(sharedPrompts, "public static let conversationListItemRadius = 8")
        expectContains(sharedPrompts, "public static let conversationListItemVerticalMargin = 2")
        expectContains(sharedPrompts, "public static let conversationListItemPadding = 8")
        expectContains(sharedPrompts, "public static let emptyHistoryPadding = 12")
        expectContains(sharedPrompts, "public static let emptyHistorySpacing = 8")
        expectContains(sharedPrompts, "public static let emptyHistoryRadius = 8")
        expectContains(sharedPrompts, "public static let attachmentChipPadding = 8")
        expectContains(sharedPrompts, "public static let attachmentChipSpacing = 8")
        expectContains(sharedPrompts, "public static let attachmentChipTextSpacing = 2")
        expectContains(sharedPrompts, "public static let attachmentChipRadius = 8")
        expectContains(sharedPrompts, "public static let attachmentRemoveButtonWidth = 28")
        expectContains(sharedPrompts, "public static let attachmentTraySpacing = 7")
        expectContains(sharedPrompts, "public static let attachmentTrayChipSpacing = 8")
        expectContains(sharedPrompts, "public static let attachmentInputHorizontalPadding = 10")
        expectContains(sharedPrompts, "public static let attachmentInputVerticalPadding = 7")
        expectContains(sharedPrompts, "public static let attachmentInputSpacing = 8")
        expectContains(sharedPrompts, "public static let messageMaxWidth = 680")
        expectContains(sharedPrompts, "public static let messageSpacing = 14")
        expectContains(sharedPrompts, "public static let messageBubbleRowSpacing = 10")
        expectContains(sharedPrompts, "public static let messageBubblePadding = 13")
        expectContains(sharedPrompts, "public static let messageBubbleSpacing = 7")
        expectContains(sharedPrompts, "public static let messageBubbleRadius = 10")
        expectContains(sharedPrompts, "public static let messageEditBorderWidth = 2")
        expectContains(sharedPrompts, "public static let markdownBlockSpacing = 9")
        expectContains(sharedPrompts, "public static let markdownListItemSpacing = 8")
        expectContains(sharedPrompts, "public static let markdownNumberWidth = 26")
        expectContains(sharedPrompts, "public static let markdownQuoteSpacing = 9")
        expectContains(sharedPrompts, "public static let markdownQuoteRuleWidth = 3")
        expectContains(sharedPrompts, "public static let markdownQuoteRuleRadius = 1")
        expectContains(sharedPrompts, "public static let markdownQuoteVerticalPadding = 2")
        expectContains(sharedPrompts, "public static let markdownCodeBlockSpacing = 7")
        expectContains(sharedPrompts, "public static let markdownCodeBlockPadding = 10")
        expectContains(sharedPrompts, "public static let markdownCodeBlockRadius = 7")
        expectContains(sharedPrompts, "public static let composerMinWidth = 620")
        expectContains(sharedPrompts, "public static let composerMaxWidth = 800")
        expectContains(upstreamMacOSChat, ".frame(maxWidth: 800)")
        expectContains(sharedPrompts, "public static let composerPadding = 18")
        expectContains(sharedPrompts, "public static let composerSpacing = 10")
        expectContains(sharedPrompts, "public static let promptRowSpacing = 12")
        expectContains(sharedPrompts, "public static let composerSendButtonMinWidth = 86")
        expectContains(sharedPrompts, "public static let composerMinHeight = 74")
        expectContains(sharedPrompts, "public static let composerMaxHeight = 120")
        expectContains(sharedPrompts, "public enum EnchantedTypography")
        expectContains(sharedPrompts, "public static let rootFontSize = 14")
        expectContains(sharedPrompts, "public static let appTitleFontSize = 26")
        expectContains(sharedPrompts, "public static let chipRemoveButtonFontWeight = 700")
        expectContains(macOSRootView, "EnchantedVisualMetrics.sidebarWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.sidebarPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.sidebarSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.sidebarTitleSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.sidebarControlGroupSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.minimumWindowWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.minimumWindowHeight")
        expectContains(macOSRootView, "EnchantedVisualMetrics.headerTitleWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.headerSpacing")
        expectContains(macOSRootView, "HStack(spacing: CGFloat(EnchantedVisualMetrics.headerSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.headerTitleSpacing")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.headerTitleSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.headerPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.statusRowSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.statusTextWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.statusDotSize")
        expectContains(macOSRootView, "EnchantedVisualMetrics.contentPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.loadingRowSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.loadingTopPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptButtonWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyStateMaxWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyStatePadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyStateSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyStateHeaderSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptListSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptButtonIconSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptButtonTextWidthInset")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptButtonPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptButtonRadius")
        expectContains(macOSRootView, "Image(systemName: enchantedSystemImageName(prompt.systemImage))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.primaryButtonPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.primaryButtonIconSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.primaryButtonRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.actionButtonIconSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.dropTargetPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.dropTargetRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.conversationListSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.conversationActionsSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.conversationRowPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.conversationRowSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.conversationRowRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyHistoryPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyHistorySpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.emptyHistoryRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentChipPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentChipSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentChipTextSpacing")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.attachmentChipTextSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentChipRadius")
        expectContains(macOSRootView, "EnchantedTypography.rootFontSize")
        expectContains(macOSRootView, "EnchantedTypography.appTitleFontSize")
        expectContains(macOSRootView, "EnchantedTypography.captionFontSize")
        expectContains(macOSRootView, "EnchantedTypography.sectionTitleFontSize")
        expectContains(macOSRootView, "EnchantedTypography.currentTitleFontSize")
        expectContains(macOSRootView, "EnchantedTypography.messageBodyFontSize")
        expectContains(macOSRootView, "EnchantedTypography.attachmentNameFontSize")
        expectContains(macOSRootView, "EnchantedTypography.attachmentSizeFontSize")
        expectContains(macOSRootView, "EnchantedTypography.conversationTitleFontSize")
        expectContains(macOSRootView, "EnchantedTypography.conversationPreviewFontSize")
        expectContains(macOSRootView, "EnchantedTypography.warningTextFontSize")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentTraySpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentTrayChipSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.attachmentInputSpacing")
        expectComponentSplitCount(
            macOSRootView,
            separatedBy: "HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentInputSpacing))",
            count: 3
        )
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageMaxWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageSpacing")
        expectContains(macOSRootView, ".frame(maxWidth: .infinity, alignment: .leading)")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageBubbleRowSpacing")
        expectContains(macOSRootView, "HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.messageBubbleRowSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageBubblePadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageBubbleSpacing")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.messageBubbleSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageBubbleRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageEditBorderWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerPadding")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerSpacing")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerEditorRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.promptRowSpacing")
        expectContains(macOSRootView, "HStack(alignment: .bottom, spacing: CGFloat(EnchantedVisualMetrics.promptRowSpacing))")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerMinWidth")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerMaxWidth")
        expectContains(macOSRootView, ".frame(maxWidth: .infinity, alignment: .center)")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerMinHeight")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerMaxHeight")
        for prompt in enchantedEmptyConversationPrompts {
            expectContains(sharedPrompts, prompt)
        }
        expectContains(sharedOllama, "public struct OllamaClient: Sendable")
        expectContains(sharedOllama, "LocalizedError")
        expectContains(sharedOllama, "public var errorDescription: String?")
        expectContains(sharedOllama, "public enum OllamaStreamParser")
        expectContains(runtime, "private final class AsyncResultBox<Value: Sendable>")
        expectContains(runtime, "private static func waitForAsync<Value: Sendable>")
        expectContains(header, "quill_enchanted_qt_run_app_json")
        expectContains(header, "quill_enchanted_qt_action_callback")
        expectContains(header, "quill_enchanted_qt_free_string_callback")
        expectContains(nativeShim, "#include \"QuillQtWidgetsSupport.hpp\"")
        expectContains(nativeShim, "#include <QJsonDocument>")
        expectContains(nativeShim, "using PromptAction = std::function<void(const QString &)>;")
        expectContains(nativeShim, "QJsonObject actionSnapshot(")
        expectContains(nativeShim, "quill_enchanted_qt_action_callback actionCallback")
        expectContains(nativeShim, "quill_enchanted_qt_free_string_callback freeString")
        expectContains(nativeShim, "#include <QRegularExpression>")
        expectContains(nativeShim, "#include <QSignalBlocker>")
        expectContains(nativeShim, "QComboBox")
        expectContains(nativeShim, "QListWidget")
        expectContains(nativeShim, "QPlainTextEdit")
        expectContains(nativeShim, "class LoadingSpinner final : public QWidget")
        expectContains(nativeShim, "QScrollArea")
        expectContains(nativeShim, "using QuillQtWidgets::scrollAreaToBottomLater;")
        expectContains(nativeShim, "auto scrollTranscriptToBottom = [scrollArea]()")
        expectContains(nativeShim, "scrollAreaToBottomLater(scrollArea)")
        expectContains(nativeShim, "scrollTranscriptToBottom();")
        let requiredQtStyleColors = [
            "canvasColor",
            "inkColor",
            "sidebarColor",
            "headerColor",
            "cardColor",
            "primaryColor",
            "systemColor",
            "mutedColor",
            "selectedMutedColor",
            "warningColor",
            "successColor",
            "dropTargetColor",
            "quoteRuleColor",
            "codeBlockColor",
            "dividerColor",
            "cardBorderColor",
            "messageBorderColor",
            "controlBorderColor",
            "disabledButtonBackgroundColor",
            "disabledButtonForegroundColor",
            "disabledTextColor",
        ]
        for colorToken in requiredQtStyleColors {
            expectContains(nativeShim, "styleValue(style, \"\(colorToken)\")")
        }
        expectContains(nativeShim, "promptRow->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "promptRow->addWidget(promptEditor, 1, Qt::AlignBottom)")
        expectDoesNotContain(nativeShim, "promptRow->addWidget(promptEditor, 1);")
        expectContains(nativeShim, "promptRow->addWidget(sendButton, 0, Qt::AlignBottom)")
        expectDoesNotContain(nativeShim, "promptRow->addWidget(sendButton);")
        expectContains(nativeShim, "const int sidebarWidth = styleInt(style, \"sidebarWidth\")")
        expectContains(nativeShim, "sidebar->setMinimumWidth(sidebarWidth)")
        expectContains(nativeShim, "sidebar->setMaximumWidth(sidebarWidth)")
        expectContains(nativeShim, "const int sidebarPadding = styleInt(style, \"sidebarPadding\")")
        expectContains(nativeShim, "sidebarLayout->setContentsMargins(sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding)")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarSpacing))")
        expectContains(nativeShim, "sidebarLayout->setSpacing(styleInt(style, \"sidebarSpacing\"));\n    sidebarLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "QWidget *sidebarTitleBlock = new QWidget()")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarTitleSpacing))")
        expectContains(nativeShim, "sidebarTitleLayout->setSpacing(styleInt(style, \"sidebarTitleSpacing\"));\n    sidebarTitleLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "void addSidebarField(\n    QVBoxLayout *layout,\n    const QString &title,\n    QWidget *field,\n    const QJsonObject &style\n)")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarControlGroupSpacing))")
        expectContains(nativeShim, "groupLayout->setSpacing(styleInt(style, \"sidebarControlGroupSpacing\"));\n    groupLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "field->setAccessibleName(title);\n    field->setAccessibleDescription(title);\n    field->setToolTip(title);\n    field->setStatusTip(title)")
        expectContains(nativeShim, "const QString initialStatus = payloadString(payload, \"status\")")
        expectContains(nativeShim, "auto updateStatusAccessibility = [&](const QString &status)")
        expectContains(nativeShim, "statusDot->setAccessibleName(status)")
        expectContains(nativeShim, "statusDot->setAccessibleDescription(status)")
        expectContains(nativeShim, "statusText->setAccessibleName(status)")
        expectContains(nativeShim, "statusText->setAccessibleDescription(status)")
        expectContains(nativeShim, "auto setStatusText = [&](const QString &status)")
        expectContains(nativeShim, "updateStatusAccessibility(status)")
        expectContains(nativeShim, "QString conversationID(const QJsonObject &conversation)")
        expectContains(nativeShim, "QString conversationTitle(const QJsonObject &conversation)")
        expectContains(nativeShim, "QString conversationLastMessage(const QJsonObject &conversation)")
        expectContains(nativeShim, "QString accessibilitySummary(const QString &title, const QString &detail)")
        expectContains(nativeShim, "return title + QStringLiteral(\"\\n\") + trimmedDetail")
        expectContains(nativeShim, "QString messageRole(const QJsonObject &message)")
        expectContains(nativeShim, "QString messageContent(const QJsonObject &message)")
        expectContains(nativeShim, "QFrame *conversationRowWidget(\n    const QJsonObject &conversation,\n    const QJsonObject &style\n)")
        expectContains(nativeShim, "const QString titleText = conversationTitle(conversation)")
        expectContains(nativeShim, "const QString rowSummary = accessibilitySummary(titleText, previewText)")
        expectContains(nativeShim, "row->setAccessibleName(titleText);\n    row->setAccessibleDescription(rowSummary);\n    row->setToolTip(rowSummary);\n    row->setStatusTip(rowSummary)")
        expectContains(nativeShim, "const int conversationRowPadding = styleInt(style, \"conversationRowPadding\")")
        expectContains(nativeShim, "const int conversationRowSpacing = styleInt(style, \"conversationRowSpacing\")")
        expectContains(nativeShim, "layout->setContentsMargins(\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding,\n        conversationRowPadding\n    )")
        expectContains(nativeShim, "layout->setSpacing(conversationRowSpacing)")
        expectContains(nativeShim, "conversationTitle(conversation)")
        expectContains(nativeShim, "QLabel *title = label(titleText, QStringLiteral(\"conversationTitle\"))")
        expectContains(macOSRootView, ".lineLimit(1)")
        expectContains(nativeShim, "title->setWordWrap(false)")
        expectContains(nativeShim, "title->setToolTip(rowSummary);\n    title->setStatusTip(rowSummary)")
        expectContains(nativeShim, "const QString previewText = conversationLastMessage(conversation)")
        expectDoesNotContain(nativeShim, "stringValue(conversation, \"title\", newConversationTitle)")
        expectDoesNotContain(nativeShim, "stringValue(conversation, \"lastMessage\", noMessagesYet)")
        expectContains(nativeShim, "if (!previewText.isEmpty())")
        expectContains(nativeShim, "QLabel *preview = label(previewText, QStringLiteral(\"conversationPreview\"))")
        expectContains(macOSRootView, ".lineLimit(2)")
        expectContains(nativeShim, "preview->setWordWrap(true)")
        expectContains(nativeShim, "preview->setMaximumHeight(preview->fontMetrics().lineSpacing() * 2)")
        expectContains(nativeShim, "preview->setToolTip(rowSummary);\n        preview->setStatusTip(rowSummary)")
        expectContains(nativeShim, "QWidget *rowWidget = conversationRowWidget(")
        expectContains(nativeShim, "const QSize rowSizeHint = rowWidget->sizeHint()")
        expectContains(nativeShim, "item->setSizeHint(QSize(0, rowSizeHint.height()))")
        expectDoesNotContain(nativeShim, "QSize(260, rowWidget->sizeHint().height())")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(11, 9, 11, 9)")
        expectContains(nativeShim, "conversationActions->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "const int conversationActionsSpacing = styleInt(style, \"conversationActionsSpacing\")")
        expectContains(nativeShim, "conversationActions->setSpacing(conversationActionsSpacing)")
        expectContains(nativeShim, "sidebarBottomNavigationLayout->setSpacing(conversationActionsSpacing)")
        expectDoesNotContain(nativeShim, "conversationActions->setSpacing(8)")
        expectContains(nativeShim, "const int attachmentChipPadding = styleInt(style, \"attachmentChipPadding\")")
        expectContains(nativeShim, "attachmentChipLayout->setContentsMargins(\n                attachmentChipPadding,\n                attachmentChipPadding,\n                attachmentChipPadding,\n                attachmentChipPadding\n            )")
        expectContains(nativeShim, "attachmentChipLayout->setSpacing(styleInt(style, \"attachmentChipSpacing\"))")
        expectContains(nativeShim, "attachmentTextLayout->setSpacing(styleInt(style, \"attachmentChipTextSpacing\"))")
        expectContains(nativeShim, "attachmentTextLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "const QString attachmentNameText = attachmentDisplayName(path)")
        expectContains(nativeShim, "const QString attachmentSummary = accessibilitySummary(attachmentNameText, displaySize)")
        expectContains(nativeShim, "attachmentChip->setAccessibleName(attachmentNameText)")
        expectContains(nativeShim, "attachmentChip->setAccessibleDescription(attachmentSummary)")
        expectContains(nativeShim, "attachmentChip->setToolTip(attachmentSummary)")
        expectContains(nativeShim, "attachmentChip->setStatusTip(attachmentSummary)")
        expectContains(macOSRootView, "Text(attachment.filename)\n                    .font(.system(size: CGFloat(EnchantedTypography.attachmentNameFontSize)))\n                    .foregroundColor(QuillColors.ink)\n                    .lineLimit(1)")
        expectContains(nativeShim, "QLabel *attachmentName = label(attachmentNameText, QStringLiteral(\"attachmentName\"));\n            attachmentName->setWordWrap(false)")
        expectContains(nativeShim, "QLabel *attachmentSize = label(displaySize, QStringLiteral(\"attachmentSize\"));\n                attachmentSize->setWordWrap(false)")
        expectDoesNotContain(nativeShim, "attachmentChipLayout->setContentsMargins(10, 7, 8, 7)")
        expectDoesNotContain(nativeShim, "attachmentTextLayout->setSpacing(2)")
        expectContains(nativeShim, "attachmentTrayLayout->setSpacing(styleInt(style, \"attachmentTraySpacing\"))")
        expectContains(nativeShim, "attachmentChipListLayout->setSpacing(styleInt(style, \"attachmentTrayChipSpacing\"))")
        expectDoesNotContain(nativeShim, "attachmentTrayLayout->setSpacing(7)")
        expectDoesNotContain(nativeShim, "attachmentChipListLayout->setSpacing(8)")
        expectContains(nativeShim, "QVBoxLayout *dropTargetLayout = new QVBoxLayout(dropTarget)")
        expectContains(nativeShim, "dropTargetLayout->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "const int attachmentInputSpacing = styleInt(style, \"attachmentInputSpacing\")")
        expectContains(nativeShim, "dropTargetLayout->setSpacing(attachmentInputSpacing)")
        expectContains(nativeShim, "QFrame *dropHint = QuillQtWidgets::frame(QStringLiteral(\"dropTargetHint\"))")
        expectContains(nativeShim, "const int dropTargetPadding = styleInt(style, \"dropTargetPadding\")")
        expectContains(nativeShim, "dropHintLayout->setContentsMargins(\n        dropTargetPadding,\n        dropTargetPadding,\n        dropTargetPadding,\n        dropTargetPadding\n    )")
        expectContains(nativeShim, "dropHintLayout->setSpacing(attachmentInputSpacing)")
        expectContains(nativeShim, "dropHintLayout->addWidget(dropTargetIconLabel, 0, Qt::AlignVCenter)")
        expectContains(nativeShim, "dropHintLayout->addWidget(dropTargetLabel, 0, Qt::AlignVCenter)")
        expectContains(nativeShim, "dropLayout->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "dropLayout->setSpacing(attachmentInputSpacing)")
        expectContains(nativeShim, "dropLayout->addWidget(attachmentPath, 1, Qt::AlignVCenter)")
        expectContains(nativeShim, "dropLayout->addWidget(attachButton, 0, Qt::AlignVCenter)")
        expectContains(nativeShim, "dropLayout->addWidget(clearAttachmentsButton, 0, Qt::AlignVCenter)")
        expectDoesNotContain(nativeShim, "const int attachmentInputHorizontalPadding = styleInt(style, \"attachmentInputHorizontalPadding\")")
        expectDoesNotContain(nativeShim, "const int attachmentInputVerticalPadding = styleInt(style, \"attachmentInputVerticalPadding\")")
        expectDoesNotContain(nativeShim, "dropHintLayout->addWidget(dropTargetIconLabel);")
        expectDoesNotContain(nativeShim, "dropHintLayout->addWidget(dropTargetLabel);")
        expectDoesNotContain(nativeShim, "dropLayout->addWidget(attachmentPath, 1);")
        expectDoesNotContain(nativeShim, "dropLayout->addWidget(attachButton);")
        expectDoesNotContain(nativeShim, "dropLayout->addWidget(clearAttachmentsButton);")
        expectDoesNotContain(nativeShim, "dropLayout->setContentsMargins(10, 7, 10, 7)")
        expectDoesNotContain(nativeShim, "dropLayout->setSpacing(8)")
        expectContains(nativeShim, "const int headerTitleWidth = styleInt(style, \"headerTitleWidth\")")
        expectContains(nativeShim, "const int statusRowSpacing = styleInt(style, \"statusRowSpacing\")")
        expectContains(nativeShim, "statusLayout->setSpacing(statusRowSpacing)")
        expectContains(nativeShim, "const int statusTextWidth = styleInt(style, \"statusTextWidth\")")
        expectContains(nativeShim, "statusText->setFixedWidth(statusTextWidth)")
        expectContains(nativeShim, "const int statusDotSize = styleInt(style, \"statusDotSize\")")
        expectContains(nativeShim, "statusDot->setFixedSize(statusDotSize, statusDotSize)")
        expectContains(nativeShim, "const int headerSpacing = styleInt(style, \"headerSpacing\")")
        expectContains(nativeShim, "headerLayout->setSpacing(headerSpacing)")
        expectContains(nativeShim, "headerLayout->addWidget(refreshButton, 0, Qt::AlignVCenter)")
        expectDoesNotContain(nativeShim, "headerLayout->addWidget(refreshButton);")
        expectContains(nativeShim, "const int headerPadding = styleInt(style, \"headerPadding\")")
        expectContains(nativeShim, "headerLayout->setContentsMargins(headerPadding, headerPadding, headerPadding, headerPadding)")
        expectContains(nativeShim, "titleLayout->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "const int headerTitleSpacing = styleInt(style, \"headerTitleSpacing\")")
        expectContains(nativeShim, "titleLayout->setSpacing(headerTitleSpacing)")
        expectContains(nativeShim, "titleLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "const int messageSpacing = styleInt(style, \"messageSpacing\")")
        expectContains(nativeShim, "messageLayout->setSpacing(messageSpacing)")
        expectContains(nativeShim, "messageLayout->setAlignment(Qt::AlignTop)")
        expectContains(nativeShim, "const int contentPadding = styleInt(style, \"contentPadding\")")
        expectContains(nativeShim, "messageLayout->setContentsMargins(contentPadding, contentPadding, contentPadding, contentPadding)")
        expectContains(nativeShim, "QWidget *loadingRowWidget(const QString &status, const QJsonObject &style)")
        expectContains(nativeShim, "layout->setContentsMargins(0, styleInt(style, \"loadingTopPadding\"), 0, 0)")
        expectContains(nativeShim, "layout->setSpacing(styleInt(style, \"loadingRowSpacing\"))")
        expectContains(nativeShim, "const int spinnerSize = styleInt(style, \"loadingSpinnerSize\")")
        expectContains(nativeShim, "setFixedSize(spinnerSize, spinnerSize)")
        expectContains(nativeShim, "QObject::connect(&timer, &QTimer::timeout, this, [this]()")
        expectContains(nativeShim, "rotationDegrees = (rotationDegrees + 30) % 360")
        expectContains(nativeShim, "QPainter painter(this)")
        expectContains(nativeShim, "layout->addWidget(new LoadingSpinner(style), 0, Qt::AlignVCenter)")
        expectContains(nativeShim, "layout->addWidget(label(status, QStringLiteral(\"caption\")), 0, Qt::AlignVCenter)")
        expectContains(nativeShim, "messageLayout->addWidget(loadingRowWidget(status, style))")
        expectContains(nativeShim, "const int messageBubbleRowSpacing = styleInt(style, \"messageBubbleRowSpacing\")")
        expectContains(nativeShim, "row->setSpacing(messageBubbleRowSpacing)")
        expectContains(nativeShim, "copyMessageTitle,\n        editMessageTitle,\n        unselectMessageTitle,\n        editingMessageID,\n        editMessage,\n        cancelEdit\n    ), 0, Qt::AlignTop)")
        expectContains(nativeShim, "const int messageMaxWidth = styleInt(style, \"messageMaxWidth\")")
        expectContains(nativeShim, "bubble->setMaximumWidth(messageMaxWidth)")
        expectContains(nativeShim, "const int messageBubblePadding = styleInt(style, \"messageBubblePadding\")")
        expectContains(nativeShim, "const int messageBubbleSpacing = styleInt(style, \"messageBubbleSpacing\")")
        expectContains(nativeShim, "layout->setContentsMargins(\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding,\n        messageBubblePadding\n    )")
        expectContains(nativeShim, "layout->setSpacing(messageBubbleSpacing)")
        expectContains(nativeShim, "layout->setSpacing(messageBubbleSpacing);\n    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "const int emptyStatePadding = styleInt(style, \"emptyStatePadding\")")
        expectContains(nativeShim, "layout->setContentsMargins(\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding,\n        emptyStatePadding\n    )")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.emptyStateSpacing))")
        expectContains(nativeShim, "layout->setSpacing(styleInt(style, \"emptyStateSpacing\"));\n    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(macOSRootView, "VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.emptyStateHeaderSpacing))")
        expectContains(macOSRootView, "if !EnchantedCopy.emptyStateSubtitle.isEmpty")
        expectContains(nativeShim, "headerLayout->setSpacing(styleInt(style, \"emptyStateHeaderSpacing\"));\n    headerLayout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "subtitleLabel->setFixedWidth(promptButtonWidth)")
        expectContains(nativeShim, "subtitleLabel->setVisible(!subtitle.trimmed().isEmpty())")
        expectContains(nativeShim, "headerLayout->addWidget(subtitleLabel)")
        expectContains(nativeShim, "promptList->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "promptList->setSpacing(styleInt(style, \"promptListSpacing\"))")
        expectContains(nativeShim, "const int promptButtonWidth = styleInt(style, \"promptButtonWidth\")")
        expectContains(nativeShim, "const int promptButtonIconSpacing = styleInt(style, \"promptButtonIconSpacing\")")
        expectContains(nativeShim, "const int promptButtonTextWidth = promptButtonWidth - styleInt(style, \"promptButtonTextWidthInset\")")
        expectContains(nativeShim, "const int promptButtonPadding = styleInt(style, \"promptButtonPadding\")")
        expectContains(nativeShim, "const int promptButtonMinHeight = styleInt(style, \"promptButtonMinHeight\")")
        expectContains(nativeShim, "buttonLayout->setContentsMargins(\n            promptButtonPadding,\n            promptButtonPadding,\n            promptButtonPadding,\n            promptButtonPadding\n        )")
        expectContains(nativeShim, "buttonLayout->setSpacing(promptButtonIconSpacing)")
        expectContains(nativeShim, "QLabel *promptIcon = iconLabel(promptButtonIcon(systemImage), QStringLiteral(\"promptButtonIcon\"), style)")
        expectContains(nativeShim, "QLabel *promptText = label(prompt, QStringLiteral(\"promptButtonText\"))")
        expectContains(nativeShim, "promptText->setFixedWidth(promptButtonTextWidth > 0 ? promptButtonTextWidth : 0)")
        expectContains(nativeShim, "button->setAccessibleName(prompt)")
        expectContains(nativeShim, "button->setAccessibleDescription(prompt)")
        expectContains(nativeShim, "button->setToolTip(prompt)")
        expectContains(nativeShim, "button->setStatusTip(prompt)")
        expectContains(nativeShim, "button->setMinimumHeight(promptButtonMinHeight)")
        expectContains(nativeShim, "button->setFixedWidth(promptButtonWidth)")
        expectContains(nativeShim, "buttonLayout->addWidget(promptIcon, 0, Qt::AlignVCenter)")
        expectDoesNotContain(nativeShim, "buttonLayout->setContentsMargins(0, 0, 0, 0)")
        expectDoesNotContain(nativeShim, "buttonLayout->addWidget(promptIcon, 0, Qt::AlignTop)")
        expectContains(nativeShim, "emptyState->setMaximumWidth(styleInt(style, \"emptyStateMaxWidth\"))")
        expectContains(nativeShim, "messageLayout->addWidget(emptyState, 0, Qt::AlignLeft | Qt::AlignTop)")
        expectDoesNotContain(nativeShim, "messageLayout->addWidget(emptyState);")
        expectContains(nativeShim, "const QString primaryButtonVerticalPadding = stylePixels(style, \"primaryButtonVerticalPadding\")")
        expectContains(nativeShim, "const QString primaryButtonHorizontalPadding = stylePixels(style, \"primaryButtonHorizontalPadding\")")
        expectContains(nativeShim, "const QString primaryButtonRadius = stylePixels(style, \"primaryButtonRadius\")")
        expectContains(nativeShim, "const QString secondaryButtonVerticalPadding = stylePixels(style, \"secondaryButtonVerticalPadding\")")
        expectContains(nativeShim, "const QString secondaryButtonHorizontalPadding = stylePixels(style, \"secondaryButtonHorizontalPadding\")")
        expectContains(nativeShim, "const QString secondaryButtonRadius = stylePixels(style, \"secondaryButtonRadius\")")
        expectContains(nativeShim, "const QString promptButtonPadding = stylePixels(style, \"promptButtonPadding\")")
        expectContains(nativeShim, "const QString promptButtonRadius = stylePixels(style, \"promptButtonRadius\")")
        expectContains(nativeShim, "const QString chipRemoveButtonVerticalPadding = stylePixels(style, \"chipRemoveButtonVerticalPadding\")")
        expectContains(nativeShim, "const QString chipRemoveButtonHorizontalPadding = stylePixels(style, \"chipRemoveButtonHorizontalPadding\")")
        expectContains(nativeShim, "const QString controlPadding = stylePixels(style, \"controlPadding\")")
        expectContains(nativeShim, "const QString controlRadius = stylePixels(style, \"controlRadius\")")
        expectContains(nativeShim, "const QString composerEditorRadius = stylePixels(style, \"composerEditorRadius\")")
        expectContains(nativeShim, "const QString conversationRowRadius = stylePixels(style, \"conversationRowRadius\")")
        expectContains(nativeShim, "const QString conversationListItemRadius = stylePixels(style, \"conversationListItemRadius\")")
        expectContains(nativeShim, "const QString conversationListItemVerticalMargin = stylePixels(style, \"conversationListItemVerticalMargin\")")
        expectContains(nativeShim, "const QString conversationListItemPadding = stylePixels(style, \"conversationListItemPadding\")")
        expectContains(nativeShim, "list->setSpacing(styleInt(style, \"conversationListSpacing\"))")
        expectContains(nativeShim, "layout->setSpacing(conversationRowSpacing);\n    layout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "const QString emptyHistoryRadius = stylePixels(style, \"emptyHistoryRadius\")")
        expectContains(nativeShim, "const QString messageBubbleRadius = stylePixels(style, \"messageBubbleRadius\")")
        expectContains(nativeShim, "const QString attachmentChipRadius = stylePixels(style, \"attachmentChipRadius\")")
        expectContains(nativeShim, "const QString markdownQuoteRuleRadius = stylePixels(style, \"markdownQuoteRuleRadius\")")
        expectContains(nativeShim, "const QString markdownCodeBlockRadius = stylePixels(style, \"markdownCodeBlockRadius\")")
        expectContains(nativeShim, "const QString dropTargetRadius = stylePixels(style, \"dropTargetRadius\")")
        expectContains(nativeShim, "const QString rootFontSize = stylePixels(style, \"rootFontSize\")")
        expectContains(nativeShim, "const QString appTitleFontSize = stylePixels(style, \"appTitleFontSize\")")
        expectContains(nativeShim, "const QString appTitleFontWeight = QString::number(styleInt(style, \"appTitleFontWeight\"))")
        expectContains(nativeShim, "const QString captionFontSize = stylePixels(style, \"captionFontSize\")")
        expectContains(nativeShim, "const QString sectionTitleFontSize = stylePixels(style, \"sectionTitleFontSize\")")
        expectContains(nativeShim, "const QString sectionTitleFontWeight = QString::number(styleInt(style, \"sectionTitleFontWeight\"))")
        expectContains(nativeShim, "const QString currentTitleFontSize = stylePixels(style, \"currentTitleFontSize\")")
        expectContains(nativeShim, "const QString currentTitleFontWeight = QString::number(styleInt(style, \"currentTitleFontWeight\"))")
        expectContains(nativeShim, "const QString messageBodyFontSize = stylePixels(style, \"messageBodyFontSize\")")
        expectContains(nativeShim, "const QString markdownHeading1FontSize = stylePixels(style, \"markdownHeading1FontSize\")")
        expectContains(nativeShim, "const QString markdownHeading2FontSize = stylePixels(style, \"markdownHeading2FontSize\")")
        expectContains(nativeShim, "const QString markdownHeadingFontSize = stylePixels(style, \"markdownHeadingFontSize\")")
        expectContains(nativeShim, "const QString markdownHeadingFontWeight = QString::number(styleInt(style, \"markdownHeadingFontWeight\"))")
        expectContains(nativeShim, "const QString markdownCodeLanguageFontSize = stylePixels(style, \"markdownCodeLanguageFontSize\")")
        expectContains(nativeShim, "const QString markdownCodeFontSize = stylePixels(style, \"markdownCodeFontSize\")")
        expectContains(nativeShim, "const QString attachmentNameFontSize = stylePixels(style, \"attachmentNameFontSize\")")
        expectContains(nativeShim, "const QString attachmentSizeFontSize = stylePixels(style, \"attachmentSizeFontSize\")")
        expectContains(nativeShim, "const QString conversationTitleFontSize = stylePixels(style, \"conversationTitleFontSize\")")
        expectContains(nativeShim, "const QString conversationTitleFontWeight = QString::number(styleInt(style, \"conversationTitleFontWeight\"))")
        expectContains(nativeShim, "const QString conversationPreviewFontSize = stylePixels(style, \"conversationPreviewFontSize\")")
        expectContains(nativeShim, "const QString warningTextFontSize = stylePixels(style, \"warningTextFontSize\")")
        expectContains(nativeShim, "const QString chipRemoveButtonFontWeight = QString::number(styleInt(style, \"chipRemoveButtonFontWeight\"))")
        expectContains(nativeShim, "const QString messageEditBorderWidth = stylePixels(style, \"messageEditBorderWidth\")")
        expectContains(nativeShim, "QWidget#enchantedRoot { background: %1; color: %2; font-size: %3; }")
        expectContains(nativeShim, "QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }")
        expectContains(nativeShim, "QLabel#caption, QLabel#fieldLabel, QLabel#statusText, QLabel#messageRole { color: %5; font-size: %6; }")
        expectContains(nativeShim, "QFrame#sidebar { background: %1; border-right: 1px solid %2; }")
        expectContains(nativeShim, "QLabel#messageUserRole { color: %3; font-size: %4; }")
        expectContains(nativeShim, "QFrame#emptyHistory, QFrame#sidebarUtilityPanel { background: %1; border: 1px solid %2; border-radius: %3; }")
        expectContains(nativeShim, "QFrame#messageAssistant { background: %1; border: 1px solid %2; border-radius: %4; }")
        expectContains(nativeShim, "QFrame#messageSystem { background: %5; border: 1px solid %6; border-radius: %4; }")
        expectContains(nativeShim, "QFrame#messageUser { background: %7; border: 1px solid %6; border-radius: %4; }")
        expectContains(nativeShim, "QFrame#messageUser[editing=\"true\"] { border: %2 solid %1; }")
        expectContains(nativeShim, "QFrame#attachmentChip { background: %1; border: 1px solid %2; border-radius: %8; }")
        expectContains(nativeShim, "QPushButton#primaryButton, QPushButton#sendButton { background: %1; color: white; border: 0; border-radius: %2; padding: %3 %4; text-align: left; }")
        expectContains(nativeShim, "QPushButton#sendButton:disabled { background: %6; color: %7; }")
        expectContains(nativeShim, "QPushButton#secondaryButton { background: transparent; color: %1; border: 1px solid %2; border-radius: %3; padding: %4 %5; text-align: left; }")
        expectContains(nativeShim, "QPushButton#secondaryButton:disabled { color: %6; border: 1px solid %7; }")
        expectContains(nativeShim, "QLabel#attachButtonIcon, QLabel#attachButtonText, QLabel#utilityButtonIcon, QLabel#utilityButtonText, QLabel#refreshButtonIcon, QLabel#refreshButtonText, QLabel#deleteButtonIcon, QLabel#deleteButtonText, QLabel#clearAllButtonIcon, QLabel#clearAllButtonText { color: %1; font-size: %8; }")
        expectContains(nativeShim, "QLabel#attachButtonIcon:disabled, QLabel#attachButtonText:disabled, QLabel#utilityButtonIcon:disabled, QLabel#utilityButtonText:disabled, QLabel#refreshButtonIcon:disabled, QLabel#refreshButtonText:disabled, QLabel#deleteButtonIcon:disabled, QLabel#deleteButtonText:disabled, QLabel#clearAllButtonIcon:disabled, QLabel#clearAllButtonText:disabled { color: %6; }")
        expectContains(nativeShim, "QPushButton#chipRemoveButton { background: transparent; color: %1; border: 0; padding: %2 %3; font-weight: %4; }")
        expectContains(nativeShim, "QPushButton#promptButton { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; text-align: left; }")
        expectContains(nativeShim, "QLabel#promptButtonIcon, QLabel#promptButtonText { color: %2; font-size: %6; }")
        expectContains(nativeShim, "QLineEdit, QComboBox { background: %1; color: %2; border: 1px solid %3; border-radius: %4; padding: %5; }")
        expectContains(nativeShim, "QPlainTextEdit { background: %1; color: %2; border: 0; border-radius: %6; padding: %5; }")
        expectDoesNotContain(nativeShim, "QPlainTextEdit { background: %1; color: %2; border: 1px solid %3; border-radius: %6; padding: %5; }")
        expectDoesNotContain(nativeShim, "font-size: 14px;")
        expectDoesNotContain(nativeShim, "font-size: 12px;")
        expectDoesNotContain(nativeShim, "font-weight: 700;")
        expectContains(genericQtHost, "const QString rootFontSize = cssPixels(style, \"rootFontSize\", 14)")
        expectContains(genericQtHost, "const QString appTitleFontSize = cssPixels(style, \"appTitleFontSize\", 26)")
        expectContains(genericQtHost, "const QString appTitleFontWeight = QString::number(intValue(style, \"appTitleFontWeight\", 700))")
        expectContains(genericQtHost, "const QString captionFontSize = cssPixels(style, \"captionFontSize\", 12)")
        expectContains(genericQtHost, "const QString sectionTitleFontSize = cssPixels(style, \"sectionTitleFontSize\", 15)")
        expectContains(genericQtHost, "const QString sectionTitleFontWeight = QString::number(intValue(style, \"sectionTitleFontWeight\", 700))")
        expectContains(genericQtHost, "const QString currentTitleFontSize = cssPixels(style, \"currentTitleFontSize\", 20)")
        expectContains(genericQtHost, "const QString currentTitleFontWeight = QString::number(intValue(style, \"currentTitleFontWeight\", 650))")
        expectContains(genericQtHost, "const QString messageBodyFontSize = cssPixels(style, \"messageBodyFontSize\", 14)")
        expectContains(genericQtHost, "const QString conversationTitleFontSize = cssPixels(style, \"conversationTitleFontSize\", 15)")
        expectContains(genericQtHost, "const QString conversationTitleFontWeight = QString::number(intValue(style, \"conversationTitleFontWeight\", 700))")
        expectContains(genericQtHost, "QWidget#genericRoot { background: %1; color: %2; font-size: %3; }")
        expectContains(genericQtHost, "QLabel#appTitle { color: %1; font-size: %2; font-weight: %3; }")
        expectContains(genericQtHost, "QLabel#bodyText, QLabel#messageText { color: %1; font-size: %2; line-height: 140%; }")
        expectDoesNotContain(genericQtHost, "font-size: 14px;")
        expectDoesNotContain(genericQtHost, "font-size: 12px;")
        expectDoesNotContain(genericQtHost, "font-size: 25px;")
        expectDoesNotContain(genericQtHost, "font-size: 22px;")
        expectDoesNotContain(genericQtHost, "font-weight: 700;")
        expectDoesNotContain(nativeShim, "#F6F7F2")
        expectDoesNotContain(nativeShim, "#EEF1EA")
        expectDoesNotContain(nativeShim, "#FBFCF7")
        expectDoesNotContain(nativeShim, "#315B7D")
        expectDoesNotContain(nativeShim, "#B86A31")
        expectDoesNotContain(nativeShim, "#8AA5B7")
        expectDoesNotContain(nativeShim, "#EEF3F4")
        expectDoesNotContain(nativeShim, "#D8DDD5")
        expectDoesNotContain(nativeShim, "#CDD5CA")
        expectDoesNotContain(nativeShim, "#AAB5BE")
        expectDoesNotContain(nativeShim, "statusLayout->setSpacing(8)")
        expectDoesNotContain(nativeShim, "statusText->setFixedWidth(240)")
        expectDoesNotContain(nativeShim, "statusDot->setFixedSize(9, 9)")
        expectDoesNotContain(nativeShim, "headerLayout->setSpacing(12)")
        expectDoesNotContain(nativeShim, "titleLayout->setSpacing(4)")
        expectDoesNotContain(nativeShim, "messageLayout->setSpacing(14)")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(0, 8, 0, 0)")
        expectDoesNotContain(nativeShim, "layout->setSpacing(8)")
        expectDoesNotContain(nativeShim, "setFixedSize(16, 16)")
        expectContains(nativeShim, "const int composerPadding = styleInt(style, \"composerPadding\")")
        expectContains(nativeShim, "composerContent->setMinimumWidth(styleInt(style, \"composerMinWidth\"))")
        expectContains(nativeShim, "composerContent->setMaximumWidth(styleInt(style, \"composerMaxWidth\"))")
        expectContains(nativeShim, "composerLayout->setContentsMargins(composerPadding, composerPadding, composerPadding, composerPadding)")
        expectContains(nativeShim, "composerLayout->setSpacing(styleInt(style, \"composerSpacing\"))")
        expectContains(nativeShim, "composerBandLayout->addWidget(composerContent, 0, Qt::AlignHCenter)")
        expectContains(nativeShim, "promptRow->setSpacing(styleInt(style, \"promptRowSpacing\"))")
        expectContains(nativeShim, "promptRow->addWidget(promptEditor, 1, Qt::AlignBottom)")
        expectDoesNotContain(nativeShim, "promptRow->addWidget(promptEditor, 1);")
        expectContains(nativeShim, "promptEditor->setMinimumHeight(styleInt(style, \"composerMinHeight\"))")
        expectContains(nativeShim, "promptEditor->setMaximumHeight(styleInt(style, \"composerMaxHeight\"))")
        expectDoesNotContain(nativeShim, "promptEditor->setFixedHeight(styleInt(style, \"composerHeight\"))")
        expectContains(nativeShim, "selectedConversationMessages(")
        expectContains(sharedPrompts, "public static let usingModelStatusPrefix = \"Using\"")
        expectContains(sharedPrompts, "public static let usingModelStatusSeparator = \" \"")
        expectContains(sharedPrompts, "\"\\(usingModelStatusPrefix)\\(usingModelStatusSeparator)\\(modelName)\"")
        expectContains(sharedPrompts, "public static let removeAttachmentTooltip = \"Remove attachment\"")
        expectContains(sharedPrompts, "public static let attachmentRemovedEmptyStatus = readyStatus")
        expectContains(sharedPrompts, "public static let completionsStatus = completionsTitle")
        expectContains(sharedPrompts, "public static let shortcutsStatus = shortcutsTitle")
        expectContains(sharedPrompts, "public static let settingsStatus = settingsTitle")
        expectContains(sharedPrompts, "public static let completionsPanelSubtitle = \"Prompt completions use the shared Enchanted profile.\"")
        expectContains(sharedPrompts, "public static let shortcutsPanelSubtitle = \"Keyboard shortcuts use the shared QuillKit shortcut surface.\"")
        expectContains(sharedPrompts, "public static let settingsPanelSubtitle = \"Refresh models, choose a local model, or clear history from this sidebar.\"")
        expectContains(sharedPrompts, "public static let imageReadyStatusSingular = \"1 image ready to send\"")
        expectContains(sharedPrompts, "public static let imageReadyStatusPluralUnit = \"images ready to send\"")
        expectContains(sharedPrompts, "count == 1 ? imageReadyStatusSingular : \"\\(count) \\(imageReadyStatusPluralUnit)\"")
        expectContains(nativeShim, "QString payloadString(const QJsonObject &payload, const char *key)")
        expectContains(nativeShim, "const QString chooseLocalModelStatus = payloadString(payload, \"chooseLocalModelStatus\")")
        expectContains(nativeShim, "const QString usingModelStatusPrefix = payloadString(payload, \"usingModelStatusPrefix\")")
        expectContains(nativeShim, "const QString usingModelStatusSeparator = payloadString(payload, \"usingModelStatusSeparator\")")
        expectContains(nativeShim, "const QString newConversationButtonTitle = payloadString(payload, \"newConversationButtonTitle\")")
        expectDoesNotContain(nativeShim, "chooseLocalModelStatus\", QStringLiteral(\"Choose a local model to begin\")")
        expectDoesNotContain(nativeShim, "usingModelStatusPrefix\", QStringLiteral(\"Using\")")
        expectDoesNotContain(nativeShim, "usingModelStatusSeparator\", QStringLiteral(\" \")")
        expectDoesNotContain(nativeShim, "\"newChatTitle\", QStringLiteral(\"New chat\")")
        expectContains(nativeShim, "app.setApplicationName(payloadString(payload, \"windowTitle\"))")
        expectContains(nativeShim, "window.setWindowTitle(payloadString(payload, \"windowTitle\"))")
        expectContains(nativeShim, "payloadString(payload, \"sidebarTitle\")")
        expectContains(nativeShim, "payloadString(payload, \"sidebarSubtitle\")")
        expectContains(nativeShim, "payloadString(payload, \"endpointLabel\")")
        expectContains(nativeShim, "const QString modelLabel = payloadString(payload, \"modelLabel\")")
        expectContains(nativeShim, "const QString noModelsTitle = payloadString(payload, \"noModelsTitle\")")
        expectContains(nativeShim, "QLabel *noModelsNotice = label(\n        noModelsTitle,\n        QStringLiteral(\"warningText\")\n    )")
        expectContains(nativeShim, "noModelsNotice->setAccessibleName(noModelsTitle);\n    noModelsNotice->setAccessibleDescription(noModelsTitle);\n    noModelsNotice->setToolTip(noModelsTitle);\n    noModelsNotice->setStatusTip(noModelsTitle)")
        expectContains(nativeShim, "auto updateModelPickerAccessibility = [&]()")
        expectContains(nativeShim, "const QString selectedModelText = modelPicker->currentText().trimmed()")
        expectContains(nativeShim, "const QString modelValue = selectedModelText.isEmpty() ? modelLabel : selectedModelText")
        expectContains(nativeShim, "modelPicker->setAccessibleName(modelLabel)")
        expectContains(nativeShim, "modelPicker->setAccessibleDescription(modelValue)")
        expectContains(nativeShim, "modelPicker->setToolTip(modelValue)")
        expectContains(nativeShim, "modelPicker->setStatusTip(modelValue)")
        expectContains(nativeShim, "noModelsNotice->setVisible(!hasModels);\n        updateModelPickerAccessibility();")
        expectContains(nativeShim, "addSidebarField(\n        sidebarLayout,\n        modelLabel,\n        modelPicker,\n        style\n    );\n    updateModelPickerAccessibility();")
        expectContains(nativeShim, "QObject::connect(modelPicker, &QComboBox::currentTextChanged, [&](const QString &model) {\n        updateModelPickerAccessibility();\n        const QString updatedModelStatus = modelStatusText(model, chooseLocalModelStatus, usingModelStatusPrefix, usingModelStatusSeparator);")
        expectContains(nativeShim, "payloadString(payload, \"conversationsTitle\")")
        expectContains(nativeShim, "const QString deleteChatTitle = payloadString(payload, \"deleteChatTitle\")")
        expectContains(nativeShim, "const QString copyMessageTitle = payloadString(payload, \"copyMessageTitle\")")
        expectContains(nativeShim, "const QString editMessageTitle = payloadString(payload, \"editMessageTitle\")")
        expectContains(nativeShim, "const QString unselectMessageTitle = payloadString(payload, \"unselectMessageTitle\")")
        expectContains(nativeShim, "using MessageEditAction = std::function<void(const QString &, const QString &)>;")
        expectContains(nativeShim, "using MessageCancelEditAction = std::function<void()>;")
        expectContains(nativeShim, "#include <QClipboard>")
        expectContains(nativeShim, "#include <QMenu>")
        expectContains(nativeShim, "QString messageID(const QJsonObject &message)")
        expectContains(nativeShim, "return requiredStringValue(message, \"id\")")
        expectContains(nativeShim, "void installMessageContextMenuRecursively(")
        expectContains(nativeShim, "widget->setContextMenuPolicy(Qt::CustomContextMenu)")
        expectContains(nativeShim, "QMenu menu(anchor)")
        expectContains(nativeShim, "menu.setObjectName(QStringLiteral(\"message.contextMenu\"))")
        expectContains(nativeShim, "menu.setAccessibleName(copyMessageTitle);\n    menu.setAccessibleDescription(copyMessageTitle)")
        expectContains(nativeShim, "void applyActionAccessibility(QAction *action, const QString &title, const QString &objectName)")
        expectContains(nativeShim, "action->setObjectName(objectName);\n    action->setToolTip(title);\n    action->setStatusTip(title);\n    action->setWhatsThis(title)")
        expectContains(nativeShim, "menu.setToolTipsVisible(true)")
        expectContains(nativeShim, "QAction *copyAction = menu.addAction(copyMessageTitle)")
        expectContains(nativeShim, "copyAction->setIcon(copyMessageActionIcon(icons))")
        expectContains(nativeShim, "applyActionAccessibility(copyAction, copyMessageTitle, QStringLiteral(\"message.copy\"))")
        expectContains(nativeShim, "if (isEditableMessageRole(role))")
        expectContains(nativeShim, "QAction *editAction = menu.addAction(editMessageTitle)")
        expectContains(nativeShim, "editAction->setIcon(editMessageActionIcon(icons))")
        expectContains(nativeShim, "applyActionAccessibility(editAction, editMessageTitle, QStringLiteral(\"message.edit\"))")
        expectContains(nativeShim, "editMessage(id, content)")
        expectContains(nativeShim, "QAction *unselectAction = menu.addAction(unselectMessageTitle)")
        expectContains(nativeShim, "unselectAction->setIcon(editMessageActionIcon(icons))")
        expectContains(nativeShim, "applyActionAccessibility(unselectAction, unselectMessageTitle, QStringLiteral(\"message.unselect\"))")
        expectContains(nativeShim, "cancelEdit()")
        expectContains(nativeShim, "promptEditor->setPlainText(message)")
        expectContains(nativeShim, "promptEditor->setFocus(Qt::OtherFocusReason)")
        expectContains(nativeShim, "QString editingMessageID;")
        expectContains(nativeShim, "std::function<void()> rerenderCurrentMessages;")
        expectContains(nativeShim, "editingMessageID = messageID")
        expectContains(nativeShim, "bubble->setProperty(\n        \"editing\",\n        isEditableMessageRole(role) && !editingMessageID.isEmpty() && id == editingMessageID\n    )")
        expectContains(nativeShim, "rerenderCurrentMessages = [&]()")
        expectContains(nativeShim, "message.insert(QStringLiteral(\"id\"), QStringLiteral(\"local-user-message\"))")
        expectContains(nativeShim, "QClipboard *clipboard = QApplication::clipboard()")
        expectContains(nativeShim, "clipboard->setText(content)")
        expectContains(nativeShim, "installMessageContextMenuRecursively(\n        bubble,\n        id,\n        role,\n        content,\n        icons,\n        copyMessageTitle,\n        editMessageTitle,\n        unselectMessageTitle,\n        editingMessageID,\n        editMessage,\n        cancelEdit\n    )")
        expectContains(nativeShim, "QPushButton *deleteButton = new QPushButton()")
        expectContains(nativeShim, "QIcon deleteChatButtonIcon(const QJsonObject &icons)")
        expectContains(nativeShim, "systemImageIcon(requiredIconName(icons, \"deleteChat\"))")
        expectContains(nativeShim, "addIconTextButtonContent(\n        deleteButton,\n        deleteChatButtonIcon(icons),\n        deleteChatTitle,\n        QStringLiteral(\"deleteButtonIcon\"),\n        QStringLiteral(\"deleteButtonText\"),\n        \"actionButtonIconSpacing\",")
        expectContains(nativeShim, "const QString clearAllTitle = payloadString(payload, \"clearAllTitle\")")
        expectContains(nativeShim, "QPushButton *clearAllButton = new QPushButton()")
        expectContains(nativeShim, "addIconTextButtonContent(\n        clearAllButton,\n        clearAllButtonIcon(icons),\n        clearAllTitle,\n        QStringLiteral(\"clearAllButtonIcon\"),\n        QStringLiteral(\"clearAllButtonText\"),\n        \"actionButtonIconSpacing\",")
        expectDoesNotContain(nativeShim, "new QPushButton(payloadString(payload, \"clearAllTitle\"))")
        expectContains(nativeShim, "QPushButton *completionsButton = new QPushButton()")
        expectContains(nativeShim, "configureUtilityButton(completionsButton, payloadString(payload, \"completionsTitle\"), \"completions\")")
        expectContains(nativeShim, "QPushButton *shortcutsButton = new QPushButton()")
        expectContains(nativeShim, "configureUtilityButton(shortcutsButton, payloadString(payload, \"shortcutsTitle\"), \"shortcuts\")")
        expectContains(nativeShim, "QPushButton *settingsButton = new QPushButton()")
        expectContains(nativeShim, "configureUtilityButton(settingsButton, payloadString(payload, \"settingsTitle\"), \"settings\")")
        expectContains(nativeShim, "const QString refreshModelsTitle = payloadString(payload, \"refreshModelsTitle\")")
        expectContains(nativeShim, "QPushButton *refreshButton = new QPushButton()")
        expectContains(nativeShim, "refreshModelsButtonIcon(icons),")
        expectContains(nativeShim, "QStringLiteral(\"refreshButtonIcon\")")
        expectContains(nativeShim, "QStringLiteral(\"refreshButtonText\")")
        expectContains(nativeShim, "refreshButton->setAccessibleName(refreshModelsTitle);\n    refreshButton->setAccessibleDescription(refreshModelsTitle);\n    refreshButton->setToolTip(refreshModelsTitle);\n    refreshButton->setStatusTip(refreshModelsTitle)")
        expectDoesNotContain(nativeShim, "windowTitle\", QStringLiteral(\"Quill Enchanted\")")
        expectDoesNotContain(nativeShim, "sidebarTitle\", QStringLiteral(\"Enchanted\")")
        expectDoesNotContain(nativeShim, "sidebarSubtitle\", QStringLiteral(\"QuillUI Linux preview\")")
        expectDoesNotContain(nativeShim, "endpointLabel\", QStringLiteral(\"Ollama endpoint\")")
        expectDoesNotContain(nativeShim, "modelLabel\", QStringLiteral(\"Model\")")
        expectDoesNotContain(nativeShim, "conversationsTitle\", QStringLiteral(\"Conversations\")")
        expectDoesNotContain(nativeShim, "deleteChatTitle\", QStringLiteral(\"Delete chat\")")
        expectDoesNotContain(nativeShim, "copyMessageTitle\", QStringLiteral(\"Copy\")")
        expectDoesNotContain(nativeShim, "new QPushButton(deleteChatTitle)")
        expectDoesNotContain(nativeShim, "completionsTitle\", QStringLiteral(\"Completions\")")
        expectDoesNotContain(nativeShim, "shortcutsTitle\", QStringLiteral(\"Shortcuts\")")
        expectDoesNotContain(nativeShim, "settingsTitle\", QStringLiteral(\"Settings\")")
        expectDoesNotContain(nativeShim, "refreshModelsTitle\", QStringLiteral(\"Refresh models\")")
        expectContains(nativeShim, "QPushButton *newConversationButton = new QPushButton()")
        expectContains(nativeShim, "addIconTextButtonContent(")
        expectContains(nativeShim, "QLabel#primaryButtonIcon, QLabel#primaryButtonText, QLabel#sendButtonIcon, QLabel#sendButtonText { color: white; font-size: %1; }")
        expectContains(nativeShim, "QLabel#sendButtonIcon:disabled, QLabel#sendButtonText:disabled { color: %2; }")
        expectContains(nativeShim, "payloadString(payload, \"completionsPanelSubtitle\")")
        expectContains(nativeShim, "payloadString(payload, \"shortcutsPanelSubtitle\")")
        expectContains(nativeShim, "payloadString(payload, \"settingsPanelSubtitle\")")
        expectContains(nativeShim, "payloadString(payload, \"completionsStatus\")")
        expectContains(nativeShim, "payloadString(payload, \"shortcutsStatus\")")
        expectContains(nativeShim, "payloadString(payload, \"settingsStatus\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Prompt completions use the shared Enchanted profile.\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Keyboard shortcuts use the shared QuillKit shortcut surface.\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Refresh models, choose a local model, or clear history from this sidebar.\")")
        expectContains(nativeShim, "const QString newConversationTitle = payloadString(payload, \"newConversationTitle\")")
        expectDoesNotContain(nativeShim, "const QString noMessagesYet = payloadString(payload, \"noMessagesYet\")")
        expectContains(nativeShim, "const QString userRoleLabel = payloadString(payload, \"userRoleLabel\")")
        expectContains(nativeShim, "const QString assistantRoleLabel = payloadString(payload, \"assistantRoleLabel\")")
        expectContains(nativeShim, "const QString systemRoleLabel = payloadString(payload, \"systemRoleLabel\")")
        expectDoesNotContain(nativeShim, "newConversationTitle\", QStringLiteral(\"New conversation\")")
        expectDoesNotContain(nativeShim, "noMessagesYet\", QStringLiteral(\"No messages yet\")")
        expectDoesNotContain(nativeShim, "userRoleLabel\", QStringLiteral(\"You\")")
        expectDoesNotContain(nativeShim, "assistantRoleLabel\", QStringLiteral(\"Enchanted\")")
        expectDoesNotContain(nativeShim, "systemRoleLabel\", QStringLiteral(\"System\")")
        expectContains(nativeShim, "QString modelStatusText(\n    const QString &selectedModel,\n    const QString &chooseLocalModelStatus,\n    const QString &usingModelStatusPrefix,\n    const QString &usingModelStatusSeparator\n)")
        expectContains(nativeShim, "return chooseLocalModelStatus")
        expectContains(nativeShim, "return usingModelStatusPrefix + usingModelStatusSeparator + trimmedModel")
        expectDoesNotContain(nativeShim, "return QStringLiteral(\"%1 %2\").arg(usingModelStatusPrefix, trimmedModel)")
        expectContains(nativeShim, "modelStatusText(payloadString(payload, \"selectedModel\"), chooseLocalModelStatus, usingModelStatusPrefix, usingModelStatusSeparator)")
        expectContains(nativeShim, "currentTitle->setFixedWidth(headerTitleWidth)")
        expectContains(nativeShim, "modelStatus->setFixedWidth(headerTitleWidth)")
        expectContains(nativeShim, "auto updateHeaderTitleAccessibility = [&](const QString &title)")
        expectContains(nativeShim, "currentTitle->setAccessibleName(title);\n        currentTitle->setAccessibleDescription(title);\n        currentTitle->setToolTip(title);\n        currentTitle->setStatusTip(title)")
        expectContains(nativeShim, "auto updateModelStatusAccessibility = [&](const QString &status)")
        expectContains(nativeShim, "modelStatus->setAccessibleName(status);\n        modelStatus->setAccessibleDescription(status);\n        modelStatus->setToolTip(status);\n        modelStatus->setStatusTip(status)")
        expectContains(nativeShim, "updateHeaderTitleAccessibility(currentTitle->text())")
        expectContains(nativeShim, "updateModelStatusAccessibility(modelStatus->text())")
        expectContains(nativeShim, "QString messageRoleTitle(\n    const QString &role,\n    const QString &userRoleLabel,\n    const QString &assistantRoleLabel,\n    const QString &systemRoleLabel\n)")
        expectContains(nativeShim, "return userRoleLabel")
        expectContains(nativeShim, "return assistantRoleLabel")
        expectContains(nativeShim, "return systemRoleLabel")
        expectContains(nativeShim, "messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel)")
        expectContains(nativeShim, "const QString title = messageRoleTitle(role, userRoleLabel, assistantRoleLabel, systemRoleLabel)")
        expectContains(nativeShim, "const QString summary = accessibilitySummary(title, content)")
        expectContains(nativeShim, "bubble->setAccessibleName(title);\n    bubble->setAccessibleDescription(summary);\n    bubble->setToolTip(summary);\n    bubble->setStatusTip(summary)")
        expectContains(nativeShim, "enum class MarkdownBlockKind")
        expectContains(nativeShim, "QString cleanMarkdownInline(QString text)")
        expectContains(nativeShim, "QList<MarkdownBlock> parseMarkdownBlocks(const QString &markdown)")
        expectContains(nativeShim, "QLabel#markdownHeading1")
        expectContains(nativeShim, "QFrame#markdownQuoteRule")
        expectContains(nativeShim, "QFrame#markdownCodeBlock")
        expectContains(nativeShim, "QFrame#markdownQuoteRule { background: %1; border-radius: %3; }")
        expectContains(nativeShim, "QFrame#markdownCodeBlock { background: %2; border-radius: %4; }")
        expectContains(nativeShim, ".arg(quoteRule, codeBlock, markdownQuoteRuleRadius, markdownCodeBlockRadius)")
        expectContains(nativeShim, "const int markdownListItemSpacing = styleInt(style, \"markdownListItemSpacing\")")
        expectContains(nativeShim, "const int markdownNumberWidth = styleInt(style, \"markdownNumberWidth\")")
        expectContains(nativeShim, "layout->setSpacing(markdownListItemSpacing)")
        expectContains(nativeShim, "markerLabel->setFixedWidth(markdownNumberWidth)")
        expectContains(nativeShim, "const int verticalPadding = styleInt(style, \"markdownQuoteVerticalPadding\")")
        expectContains(nativeShim, "layout->setContentsMargins(0, verticalPadding, 0, verticalPadding)")
        expectContains(nativeShim, "const int markdownQuoteSpacing = styleInt(style, \"markdownQuoteSpacing\")")
        expectContains(nativeShim, "const int markdownQuoteRuleWidth = styleInt(style, \"markdownQuoteRuleWidth\")")
        expectContains(nativeShim, "layout->setSpacing(markdownQuoteSpacing)")
        expectContains(nativeShim, "rule->setFixedWidth(markdownQuoteRuleWidth)")
        expectContains(nativeShim, "const int codeBlockPadding = styleInt(style, \"markdownCodeBlockPadding\")")
        expectContains(nativeShim, "layout->setContentsMargins(codeBlockPadding, codeBlockPadding, codeBlockPadding, codeBlockPadding)")
        expectContains(nativeShim, "const int markdownCodeBlockSpacing = styleInt(style, \"markdownCodeBlockSpacing\")")
        expectContains(nativeShim, "layout->setSpacing(markdownCodeBlockSpacing)")
        expectContains(nativeShim, "QWidget *markdownMessageWidget(const QString &markdown, const QJsonObject &style)")
        expectContains(nativeShim, "const int markdownBlockSpacing = styleInt(style, \"markdownBlockSpacing\")")
        expectContains(nativeShim, "layout->setContentsMargins(0, 0, 0, 0)")
        expectContains(nativeShim, "layout->setSpacing(markdownBlockSpacing)")
        expectContains(nativeShim, "addMarkdownBlocks(layout, markdown, style)")
        expectContains(nativeShim, "const QString content = messageContent(message)")
        expectContains(nativeShim, "layout->addWidget(markdownMessageWidget(content, style))")
        expectDoesNotContain(nativeShim, "stringValue(message, \"role\", QStringLiteral(\"assistant\"))")
        expectDoesNotContain(nativeShim, "markdownMessageWidget(stringValue(message, \"content\"), style)")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(10, 10, 10, 10)")
        expectDoesNotContain(nativeShim, "layout->setSpacing(7)")
        expectDoesNotContain(nativeShim, "layout->setSpacing(9)")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(0, 2, 0, 2)")
        expectDoesNotContain(nativeShim, "rule->setFixedWidth(3)")
        expectDoesNotContain(nativeShim, "? 26 : 14")
        expectContains(nativeShim, "role == QStringLiteral(\"user\") ? QStringLiteral(\"messageUserRole\") : QStringLiteral(\"messageRole\")")
        expectDoesNotContain(nativeShim, "border-radius: 10px;")
        expectDoesNotContain(nativeShim, "border-radius: 8px;")
        expectDoesNotContain(nativeShim, "border-radius: 7px;")
        expectDoesNotContain(nativeShim, "border-radius: 1px;")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(13, 13, 13, 13)")
        expectContains(nativeShim, "QIcon promptButtonIcon(const QString &systemImage)")
        expectContains(nativeShim, "QJsonObject requiredPromptObject(const QJsonValue &value)")
        expectContains(nativeShim, "return requiredObjectValue(value, \"prompts[]\")")
        expectContains(nativeShim, "QString promptTitle(const QJsonObject &prompt)")
        expectContains(nativeShim, "const QString title = requiredStringValue(prompt, \"title\")")
        expectContains(nativeShim, "failRequiredPayloadField(\"title\", \"non-empty string\")")
        expectContains(nativeShim, "const QString normalized = systemImage.trimmed().toLower()")
        expectContains(nativeShim, "const QString systemImage = requiredStringValue(prompt, \"systemImage\").trimmed()")
        expectContains(nativeShim, "failRequiredPayloadField(\"systemImage\", \"non-empty string\")")
        expectDoesNotContain(nativeShim, "QString stringValue(")
        expectDoesNotContain(nativeShim, "QString promptTitle(const QJsonValue &value)")
        expectDoesNotContain(nativeShim, "return stringValue(value.toObject(), \"title\")")
        expectDoesNotContain(nativeShim, "const QString prompt = promptTitle(value)")
        expectDoesNotContain(nativeShim, "const QString systemImage = promptSystemImage(value)")
        expectDoesNotContain(nativeShim, "if (prompt.isEmpty())")
        expectDoesNotContain(nativeShim, "QString promptKind(const QJsonValue &value)")
        expectDoesNotContain(nativeShim, "return stringValue(value.toObject(), \"kind\").trimmed().toLower()")
        expectDoesNotContain(nativeShim, "if (kind == QStringLiteral(\"question\"))")
        expectDoesNotContain(nativeShim, "return QStringLiteral(\"questionmark.circle\")")
        expectDoesNotContain(nativeShim, "if (kind == QStringLiteral(\"action\"))")
        expectDoesNotContain(nativeShim, "return QStringLiteral(\"lightbulb.circle\")")
        expectContains(nativeShim, "QStringLiteral(\"help-about-symbolic\")")
        expectContains(nativeShim, "QStringLiteral(\"dialog-information-symbolic\")")
        expectContains(nativeShim, "QStringLiteral(\"starred-symbolic\")")
        expectContains(nativeShim, "QStyle::SP_DialogYesButton")
        expectContains(nativeShim, "QLabel *iconLabel(const QIcon &icon, const QString &objectName, const QJsonObject &style)")
        expectContains(nativeShim, "QLabel *promptIcon = iconLabel(promptButtonIcon(systemImage), QStringLiteral(\"promptButtonIcon\"), style)")
        expectContains(nativeShim, "QLabel *promptText = label(prompt, QStringLiteral(\"promptButtonText\"))")
        expectDoesNotContain(nativeShim, "promptCardPrefix()")
        expectDoesNotContain(nativeShim, "new QPushButton(QStringLiteral(\"%1%2\").arg(promptCardPrefix(), prompt))")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(26, 26, 26, 26)")
        expectDoesNotContain(nativeShim, "promptList->setSpacing(10)")
        expectDoesNotContain(nativeShim, "button->setMinimumHeight(48)")
        expectDoesNotContain(nativeShim, "button->setFixedWidth(620)")
        expectDoesNotContain(nativeShim, "padding: 9px 12px")
        expectDoesNotContain(nativeShim, "border-radius: 7px; padding: 7px;")
        expectDoesNotContain(nativeShim, "padding: 2px 6px")
        expectDoesNotContain(nativeShim, "emptyState->setMaximumWidth(680)")
        expectDoesNotContain(nativeShim, "role.toUpper()")
        expectContains(macOSRootView, "Text(EnchantedCopy.noModelsTitle)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.noModelsTitle)")
        expectContains(upstreamSlice, ".help(EnchantedCopy.noModelsTitle)")
        expectContains(nativeShim, "payloadString(payload, \"noModelsTitle\")")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"noModelsTitle\", QStringLiteral(\"No models detected\"))")
        expectContains(nativeShim, "models.isEmpty() ? QStringLiteral(\"statusDotWarning\") : QStringLiteral(\"statusDot\")")
        expectContains(nativeShim, "QFrame#statusDot, QFrame#statusDotWarning")
        expectContains(nativeShim, "const QString statusDotSize = stylePixels(style, \"statusDotSize\")")
        expectContains(nativeShim, "const QString statusDotRadius = stylePixels(style, \"statusDotRadius\")")
        expectContains(nativeShim, "QFrame#statusDot, QFrame#statusDotWarning { min-width: %1; max-width: %1; min-height: %1; max-height: %1; border-radius: %2; }")
        expectDoesNotContain(nativeShim, "min-width: 9px; max-width: 9px; min-height: 9px; max-height: 9px; border-radius: 4px;")
        expectContains(nativeShim, ".arg(statusDotSize, statusDotRadius, success, warning, canvas, warningTextFontSize)")
        expectContains(nativeShim, "populateModelPicker(models, payloadString(payload, \"selectedModel\"))")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"endpoint\"), endpointField->text().trimmed())")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"selectedModel\"), currentModel)")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"models\"), currentModelList(modelPicker))")
        expectContains(nativeShim, "QObject::connect(endpointField, &QLineEdit::editingFinished")
        expectContains(nativeShim, "QObject::connect(refreshButton, &QPushButton::clicked")
        expectContains(macOSRootView, "Text(EnchantedCopy.emptyHistoryTitle)")
        expectContains(macOSRootView, "Text(EnchantedCopy.emptyHistorySubtitle)")
        expectContains(macOSRootView, "Image(systemName: enchantedSystemImageName(EnchantedIcon.deleteChat))")
        expectContains(macOSRootView, "Text(EnchantedCopy.deleteChatTitle)")
        expectContains(macOSRootView, "model.deleteSelectedConversation()")
        expectContains(macOSRootView, "Image(systemName: enchantedSystemImageName(EnchantedIcon.clearAll))")
        expectContains(macOSRootView, "Text(EnchantedCopy.clearAllTitle)")
        expectContains(macOSRootView, "model.deleteAllConversations()")
        expectContains(nativeShim, "payloadString(payload, \"clearAllTitle\")")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"clearAllTitle\", QStringLiteral(\"Clear all\"))")
        expectContains(nativeShim, "QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle, const QJsonObject &style)")
        expectContains(nativeShim, "const int emptyHistoryPadding = styleInt(style, \"emptyHistoryPadding\")")
        expectContains(nativeShim, "const int emptyHistorySpacing = styleInt(style, \"emptyHistorySpacing\")")
        expectContains(nativeShim, "const QString cardSummary = accessibilitySummary(title, subtitle)")
        expectContains(nativeShim, "card->setAccessibleName(title);\n    card->setAccessibleDescription(cardSummary);\n    card->setToolTip(cardSummary);\n    card->setStatusTip(cardSummary)")
        expectContains(nativeShim, "layout->setContentsMargins(\n        emptyHistoryPadding,\n        emptyHistoryPadding,\n        emptyHistoryPadding,\n        emptyHistoryPadding\n    )")
        expectContains(nativeShim, "layout->setSpacing(emptyHistorySpacing)")
        expectContains(nativeShim, "layout->setAlignment(Qt::AlignTop | Qt::AlignLeft)")
        expectContains(nativeShim, "const int sidebarUtilityPadding = emptyHistoryPadding")
        expectContains(nativeShim, "sidebarUtilityLayout->setSpacing(emptyHistorySpacing)")
        expectContains(nativeShim, "emptyHistoryWidget(\n        payloadString(payload, \"emptyHistoryTitle\"),\n        payloadString(payload, \"emptyHistorySubtitle\"),\n        style\n    )")
        expectDoesNotContain(nativeShim, "QFrame *emptyHistoryWidget(const QString &title, const QString &subtitle)")
        expectDoesNotContain(nativeShim, "layout->setContentsMargins(12, 12, 12, 12)")
        expectDoesNotContain(nativeShim, "layout->setSpacing(8)")
        expectContains(nativeShim, "payloadString(payload, \"emptyHistoryTitle\")")
        expectContains(nativeShim, "payloadString(payload, \"emptyHistorySubtitle\")")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"emptyHistoryTitle\", QStringLiteral(\"No saved chats yet\"))")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"emptyHistorySubtitle\", QStringLiteral(\"Start a chat and it will be saved locally.\"))")
        expectContains(macOSRootView, ".foregroundColor(isSelected ? .white : QuillColors.ink)")
        expectContains(macOSRootView, ".foregroundColor(isSelected ? QuillColors.selectedMuted : QuillColors.muted)")
        expectContains(macOSRootView, ".background(isSelected ? QuillColors.primary : QuillColors.card)")
        expectContains(macOSRootView, "EnchantedVisualMetrics.composerEditorRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageBubbleRadius")
        expectContains(macOSRootView, "EnchantedVisualMetrics.messageEditBorderWidth")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownBlockSpacing")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownListItemSpacing")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownNumberWidth")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownQuoteSpacing")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownQuoteRuleWidth")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownQuoteVerticalPadding")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownCodeBlockSpacing")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownCodeBlockPadding")
        expectContains(macOSMarkdownRendering, "EnchantedVisualMetrics.markdownCodeBlockRadius")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.messageBodyFontSize")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownHeading1FontSize")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownHeading2FontSize")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownHeadingFontSize")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownHeadingFontWeight")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownCodeLanguageFontSize")
        expectContains(macOSMarkdownRendering, "EnchantedTypography.markdownCodeFontSize")
        expectContains(macOSMarkdownRendering, "weight: enchantedFontWeight(EnchantedTypography.markdownHeadingFontWeight)")
        expectDoesNotContain(macOSMarkdownRendering, "weight: .semibold")
        expectContains(nativeShim, "QListWidget#conversationList::item { border-radius: %1; margin: %2 0; padding: %3; }")
        expectContains(nativeShim, "QFrame#conversationRow { background: %3; border-radius: %6; }")
        expectContains(nativeShim, "QFrame#conversationRow[active=\"true\"] { background: %5; }")
        expectContains(nativeShim, "QLabel#conversationTitle[active=\"true\"] { color: white; }")
        expectContains(nativeShim, "QLabel#conversationTitle { color: %2; font-size: %7; font-weight: %8; }")
        expectContains(nativeShim, "QLabel#conversationPreview { color: %4; font-size: %9; }")
        expectContains(nativeShim, "QLabel#conversationPreview[active=\"true\"] { color: %1; }")
        expectDoesNotContain(nativeShim, "QLabel#conversationPreview { color: %5; font-size: %9; }")
        expectContains(nativeShim, "void updateConversationSelectionStyles(QListWidget *list)")
        expectContains(nativeShim, "widget->setProperty(\"active\", isSelected)")
        expectContains(macOSRootView, "?? EnchantedCopy.newConversationTitle")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"New conversation\")")
        expectDoesNotContain(nativeShim, "QuillUI backend parity")
        expectContains(macOSRootView, "Text(EnchantedCopy.attachmentsTitle)")
        expectContains(macOSRootView, "Text(EnchantedCopy.attachTitle)")
        expectContains(macOSRootView, "Button(EnchantedCopy.clearAttachmentsTitle)")
        expectContains(macOSRootView, "private var hasAttachmentPathCandidates: Bool")
        expectContains(macOSRootView, "PendingImageAttachment.attachmentPathCandidates(from: model.attachmentPath)")
        expectContains(macOSRootView, "private var selectedModelSupportsImages: Bool")
        expectContains(macOSRootView, "model.selectedModelSupportsImages")
        expectContains(enchantedModelSource, "public var selectedModelSupportsImages: Bool")
        expectContains(enchantedModelSource, "models.first(where: { $0.name == selectedModel })?.name.quillLikelySupportsImages ?? false")
        expectContains(enchantedModelSource, "guard selectedModelSupportsImages else { return false }")
        expectContains(enchantedModelSource, "private func discardUnsupportedImageAttachmentsIfNeeded()")
        expectContains(macOSRootView, "set: { model.selectModel(named: $0) }")
        expectContains(macOSRootView, "private var sendActionTitle: String")
        expectContains(macOSRootView, "Text(sendActionTitle)")
        expectContains(macOSRootView, ".accessibilityLabel(EnchantedCopy.endpointLabel)")
        expectContains(macOSRootView, ".accessibilityLabel(EnchantedCopy.modelLabel)")
        expectContains(macOSRootView, ".accessibilityLabel(EnchantedCopy.attachmentPlaceholder)")
        expectContains(macOSRootView, ".accessibilityLabel(EnchantedCopy.composerPlaceholder)")
        expectContains(macOSRootView, ".accessibilityLabel(sendActionTitle)")
        expectContains(macOSRootView, ".accessibilityLabel(EnchantedCopy.removeAttachmentTooltip)")
        expectContains(macOSRootView, ".accessibilityLabel(attachment.filename)")
        expectContains(macOSRootView, ".accessibilityValue(attachment.formattedByteCount)")
        expectContains(macOSRootView, "Text(conversation.lastMessage)")
        expectContains(macOSRootView, ".font(.system(size: CGFloat(EnchantedTypography.conversationPreviewFontSize)))")
        expectContains(macOSRootView, ".accessibilityLabel(conversation.title)")
        expectContains(macOSRootView, ".accessibilityValue(conversation.lastMessage)")
        expectContains(macOSRootView, ".accessibilityLabel(label)")
        expectContains(macOSRootView, ".accessibilityValue(message.content)")
        expectContains(macOSRootView, ".accessibilityElement(children: .combine)")
        for needle in [
            "Button(action: copyMessageContent)",
            "EnchantedCopy.copyMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.copyMessage)",
            "Button(action: editMessageContent)",
            "EnchantedCopy.editMessageTitle",
            "enchantedSystemImageName(EnchantedIcon.editMessage)",
            "Button(action: cancelEdit)",
            "EnchantedCopy.unselectMessageTitle",
            "private func copyMessageContent()",
            "private func editMessageContent()",
            "editMessage(message)",
            "EnchantedClipboard.setString(message.content)"
        ] {
            expectContains(macOSRootView, needle)
        }

        for needle in [
            "import QuillKit",
            "public enum EnchantedClipboard",
            "QuillClipboard.shared.setString(message)"
        ] {
            expectContains(enchantedClipboardSource, needle)
        }

        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.modelLabel)")
        expectContains(upstreamSlice, ".accessibilityValue(selectedModel?.name ?? EnchantedCopy.modelLabel)")
        expectContains(upstreamSlice, ".help(selectedModel?.name ?? EnchantedCopy.modelLabel)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.newChatTitle)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.composerPlaceholder)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.attachTitle)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.stopTitle)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.sendTitle)")
        expectContains(upstreamSlice, ".accessibilityLabel(EnchantedCopy.removeAttachmentTooltip)")
        expectContains(upstreamSlice, ".accessibilityLabel(attachment.filename)")
        expectContains(upstreamSlice, ".accessibilityValue(attachment.formattedByteCount)")
        expectContains(upstreamSlice, ".accessibilityLabel(messageAccessibilityLabel(message))")
        expectContains(upstreamSlice, ".accessibilityValue(message.content)")
        expectContains(upstreamSlice, ".accessibilityElement(children: .combine)")
        for needle in [
            "EnchantedClipboard.setString(message.content)",
            "EnchantedCopy.copyMessageTitle",
            "QuillSystemSymbol.compatibleName(EnchantedIcon.copyMessage)",
            "Button(\"Edit\") {\n                                        editMessage = message",
            "MenuItem(\"Edit\") {\n                                        editMessage = message"
        ] {
            expectContains(upstreamSlice, needle)
        }

        expectContains(upstreamSlice, "self.lastMessage = conversation.lastMessage")
        expectContains(upstreamSlice, "lastMessage: $0.lastMessage")
        expectContains(controlsSource, "let lastMessage = lastMessagePreview(for: item)")
        expectContains(controlsSource, "VStack(alignment: .leading, spacing: rowTextSpacing)")
        expectContains(controlsSource, ".font(.system(size: rowFontSize))")
        expectContains(controlsSource, "Text(lastMessage)")
        expectContains(controlsSource, ".font(.system(size: rowPreviewFontSize))")
        expectContains(controlsSource, ".padding(rowPadding)")
        expectContains(controlsSource, ".cornerRadius(rowCornerRadius)")
        expectContains(controlsSource, "VStack(alignment: .leading, spacing: listSpacing)")
        expectContains(controlsSource, "ForEach(sortedItems) { item in")
        expectContains(controlsSource, "private var listSpacing: CGFloat { 8 }")
        expectContains(controlsSource, "private var sortedItems: [QuillConversationHistoryItem]")
        expectContains(controlsSource, "items.sorted { $0.updatedAt > $1.updatedAt }")
        expectContains(controlsSource, "private var rowFontSize: CGFloat { 15 }")
        expectContains(controlsSource, "private var rowPreviewFontSize: CGFloat { 12 }")
        expectContains(controlsSource, "private var rowPadding: CGFloat { 11 }")
        expectContains(controlsSource, "private var rowTextSpacing: CGFloat { 5 }")
        expectContains(controlsSource, "private var rowCornerRadius: CGFloat { 8 }")
        expectDoesNotContain(controlsSource, "QuillConversationHistorySection")
        expectDoesNotContain(controlsSource, "ForEach(sections)")
        expectDoesNotContain(controlsSource, "Text(section.title)")
        expectDoesNotContain(controlsSource, "private static func sectionTitle")
        expectDoesNotContain(controlsSource, "selectionIndicatorTopPadding")
        expectDoesNotContain(controlsSource, "rowHorizontalPadding")
        expectDoesNotContain(controlsSource, "rowVerticalPadding")
        expectDoesNotContain(controlsSource, "rowMinHeight")
        expectDoesNotContain(controlsSource, "QuillDesktopChromeStyle.selectedRowCornerRadius")
        expectContains(controlsSource, "private var rowBackgroundColor: Color { Color(hex: \"#FFFFFF\") }")
        expectContains(controlsSource, "private var selectedRowBackgroundColor: Color { Color(hex: \"#4285F4\") }")
        expectContains(controlsSource, "private var rowTitleColor: Color { Color(hex: \"#1D1D1F\") }")
        expectContains(controlsSource, "private var selectedRowTitleColor: Color { Color(hex: \"#FFFFFF\") }")
        expectContains(controlsSource, "private var rowPreviewColor: Color { Color(hex: \"#6E6E73\") }")
        expectContains(controlsSource, "private var selectedRowPreviewColor: Color { Color(hex: \"#FFFFFF\") }")
        expectContains(controlsSource, ".foregroundColor(isSelected ? selectedRowTitleColor : rowTitleColor)")
        expectContains(controlsSource, ".foregroundColor(isSelected ? selectedRowPreviewColor : rowPreviewColor)")
        expectContains(controlsSource, ".background(isSelected ? selectedRowBackgroundColor : rowBackgroundColor)")
        expectContains(controlsSource, ".accessibilityLabel(item.title)")
        expectContains(controlsSource, ".accessibilityValue(item.lastMessage)")
        expectContains(controlsSource, ".help(accessibilitySummary(for: item))")
        expectContains(macOSRootView, ".background(model.isLoading ? QuillColors.warning : QuillColors.primary)")
        expectContains(macOSRootView, ".dropDestination(for: URL.self)")
        expectContains(macOSRootView, "guard selectedModelSupportsImages else { return false }")
        expectContains(macOSRootView, "model.addAttachments(urls: urls)")
        expectContains(macOSRootView, "model.isAttachmentDropTargeted = selectedModelSupportsImages && isTargeted")
        expectContains(imageAttachmentSource, "EnchantedCopy.attachmentDefaultPrompt")
        expectContains(imageAttachmentSource, "EnchantedCopy.attachmentSummaryTitle")
        for needle in [
            "public static let unsupportedAttachmentSuffix = \" is not a supported image attachment.\"",
            "public static let unreadableAttachmentPrefix = \"Could not read image attachment at \"",
            "public static let unreadableAttachmentSuffix = \".\"",
            "public static let oversizedAttachmentMiddle = \" is too large to attach (\"",
            "public static let oversizedAttachmentSuffix = \").\"",
            "public static func unsupportedAttachmentStatus(_ name: String) -> String",
            "public static func unreadableAttachmentStatus(_ path: String) -> String",
            "public static func oversizedAttachmentStatus(_ name: String, formattedByteCount: String) -> String",
        ] {
            expectContains(sharedPrompts, needle)
        }
        for needle in [
            "EnchantedCopy.unsupportedAttachmentStatus(name)",
            "EnchantedCopy.unreadableAttachmentStatus(path)",
            "EnchantedCopy.oversizedAttachmentStatus(",
            "formattedByteCount: PendingImageAttachment.formatByteCount(byteCount)",
        ] {
            expectContains(imageAttachmentSource, needle)
        }
        expectContains(nativeSupport, "inline bool jsonBoolValue(")
        for needle in [
            "const QString attachmentPlaceholder = payloadString(payload, \"attachmentPlaceholder\")",
            "attachmentPath->setAccessibleName(attachmentPlaceholder)",
            "attachmentPath->setAccessibleDescription(attachmentPlaceholder)",
            "attachmentPath->setToolTip(attachmentPlaceholder)",
            "attachmentPath->setStatusTip(attachmentPlaceholder)",
            "unavailableModelButton->setAccessibleName(modelLabel)",
            "unavailableModelButton->setAccessibleDescription(chooseLocalModelStatus)",
            "unavailableModelButton->setToolTip(chooseLocalModelStatus)",
            "unavailableModelButton->setStatusTip(chooseLocalModelStatus)",
            "payloadString(payload, \"attachTitle\")",
            "attachButton->setAccessibleName(attachTitle)",
            "attachButton->setAccessibleDescription(attachTitle)",
            "attachButton->setToolTip(attachTitle)",
            "attachButton->setStatusTip(attachTitle)",
            "const QString clearAttachmentsTitle = payloadString(payload, \"clearAttachmentsTitle\")",
            "clearAttachmentsButton->setAccessibleName(clearAttachmentsTitle)",
            "clearAttachmentsButton->setAccessibleDescription(clearAttachmentsTitle)",
            "clearAttachmentsButton->setToolTip(clearAttachmentsTitle)",
            "clearAttachmentsButton->setStatusTip(clearAttachmentsTitle)",
            "payloadString(payload, \"attachmentsClearedStatus\")",
            "payloadString(payload, \"attachmentRemovedEmptyStatus\")",
            "payloadString(payload, \"attachmentsTitle\")",
            "payloadString(payload, \"attachmentDefaultPrompt\")",
            "payloadString(payload, \"attachmentDefaultPromptPlural\")",
            "payloadString(payload, \"attachmentSummaryTitle\")",
            "QPushButton *clearAttachmentsButton = new QPushButton(clearAttachmentsTitle)",
            "QString attachmentDefaultPromptForCount(",
            "QString attachmentDisplayContent(",
            "QStringList normalizedAttachmentPaths(",
            "QStringList attachmentPathCandidatesFromInput(const QString &rawText)",
            "addPendingAttachmentPaths(rawPaths)",
            "QStringList attachmentCandidatePathsFromMimeData(",
            "const QMimeData *mimeData,",
            "const QStringList &supportedExtensions",
            "QString attachmentSummaryForPaths(",
            "QString formattedAttachmentByteCount(qint64 byteCount)",
            "QString attachmentDisplaySize(const QString &rawPath)",
            "#include <QDir>",
            "#include <QMimeData>",
            "#include <QStringList>",
            "struct AttachmentValidationPolicy",
            "requiredIntValue(payload, \"attachmentMaxByteCount\")",
            "requiredStringListValue(payload, \"supportedAttachmentExtensions\")",
            "requiredStringValue(payload, \"unsupportedAttachmentSuffix\")",
            "requiredStringValue(payload, \"unreadableAttachmentPrefix\")",
            "requiredStringValue(payload, \"unreadableAttachmentSuffix\")",
            "requiredStringValue(payload, \"oversizedAttachmentMiddle\")",
            "requiredStringValue(payload, \"oversizedAttachmentSuffix\")",
            "struct AttachmentPathValidation",
            "QString normalizedAttachmentPath(const QString &rawPath)",
            "QDir::homePath()",
            "AttachmentPathValidation validatedAttachmentPaths(",
            "const QStringList &rawPaths,",
            "const AttachmentValidationPolicy &policy",
            "const AttachmentPathValidation validation = validatedAttachmentPaths(rawPaths, attachmentPolicy)",
            "dropTarget->setSupportedAttachmentExtensions(attachmentPolicy.supportedExtensions)",
            "formattedAttachmentByteCount(byteCount)",
            "setStatusText(validation.lastError)",
            "const QString displaySize = attachmentDisplaySize(path)",
            "QStringLiteral(\"- %1 (%2)\").arg(displayName, displaySize)",
        ] {
            expectContains(nativeShim, needle)
        }
        expectDoesNotContain(nativeShim, "unavailableModelButton->setAccessibleName(chooseLocalModelStatus)")
        expectDoesNotContain(nativeShim, "clearAttachmentsButtonIcon")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"clearAttachmentsButtonIcon\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"clearAttachmentsButtonText\")")
        expectDoesNotContain(nativeShim, "addIconTextButtonContent(\n        clearAttachmentsButton,")
        for needle in [
            "QStringLiteral(\"Image path or drop files here\")",
            "stringValue(payload, \"attachTitle\", QStringLiteral(\"Attach\"))",
            "stringValue(payload, \"clearAttachmentsTitle\", QStringLiteral(\"Clear\"))",
            "QStringLiteral(\"Attachments cleared\")",
            "QStringLiteral(\"Ready\")",
            "stringValue(payload, \"attachmentsTitle\", QStringLiteral(\"Attachments\"))",
            "QStringLiteral(\"Describe this image.\")",
            "QStringLiteral(\"Describe these images.\")",
            "QStringLiteral(\"[Attached images]\")",
            "const qint64 attachmentMaxByteCount = 20 * 1024 * 1024",
            "QStringList supportedAttachmentExtensions()",
            "QStringLiteral(\"%1 is not a supported image attachment.\")",
            "QStringLiteral(\"Could not read image attachment at %1.\")",
            "QStringLiteral(\"%1 is too large to attach (%2).\")",
            "QStringLiteral(\"TB\")",
        ] {
            expectDoesNotContain(nativeShim, needle)
        }
        for needle in [
            "public static let maxByteCount: Int64 = 20 * 1024 * 1024",
            "public static let supportedExtensions: Set<String> = [\"gif\", \"heic\", \"jpeg\", \"jpg\", \"png\", \"tif\", \"tiff\", \"webp\"]",
            "case \"tif\", \"tiff\":",
            "return \"image/tiff\"",
            "case .unsupportedFileType(let name):",
            "case .unreadableFile(let path):",
            "case .fileTooLarge(let name, let byteCount):",
            "public static func attachmentPathCandidates(from rawPaths: String) -> [String]",
            "public static func fileURLs(from rawPaths: String) -> [URL]",
            "public static func fileURL(from rawPath: String) -> URL?",
            "public static func attachmentSummary(for attachments: [PendingImageAttachment]) -> String",
            "public static func formatByteCount(_ byteCount: Int64) -> String",
        ] {
            expectContains(imageAttachmentSource, needle)
        }
        expectContains(nativeShim, "class AttachmentDropFrame final : public QFrame")
        expectContains(nativeShim, "setAcceptDrops(true)")
        expectContains(nativeShim, "attachmentPath->setAcceptDrops(false)")
        expectContains(nativeShim, "mimeData->urls()")
        expectContains(nativeShim, "url.toLocalFile()")
        expectContains(nativeShim, "attachmentCandidatePathsFromMimeData(\n            event->mimeData(),")
        expectContains(nativeShim, "supportedAttachmentExtensions\n        )")
        expectContains(macOSRootView, "if selectedModelSupportsImages, model.isAttachmentDropTargeted")
        expectContains(macOSRootView, "if selectedModelSupportsImages {\n                HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentInputSpacing))")
        expectContains(macOSRootView, "Text(EnchantedCopy.dropTargetTitle)")
        expectContains(nativeShim, "QFrame#dropTarget { background: transparent; border: 0; }")
        expectContains(nativeShim, "QFrame#dropTarget[dragActive=\"true\"]")
        expectContains(nativeShim, "QFrame#dropTargetHint { background: %1; border: 0; border-radius: %4; }")
        expectDoesNotContain(nativeShim, "QFrame#dropTargetHint { background: %1; border: 1px solid %2; border-radius: %5; }")
        expectContains(nativeShim, "QLabel#dropTargetIcon, QLabel#dropTargetLabel { color: %2; font-size: %5; }")
        expectDoesNotContain(nativeShim, "\n        QLabel#dropTargetLabel { color: %2; font-size: %5; }")
        expectContains(nativeShim, "QSplitter::handle { background: %3; }")
        expectContains(nativeShim, "void setDropHint(QWidget *hint)")
        expectContains(nativeShim, "dropHint->setVisible(property(\"dragActive\").toBool())")
        expectContains(nativeShim, "void resetDragState()")
        expectContains(nativeShim, "dropHint->setVisible(active)")
        expectContains(nativeShim, "const QString dropTargetTitle = payloadString(payload, \"dropTargetTitle\")")
        expectContains(nativeShim, "dropTarget->setAccessibleName(dropTargetTitle)")
        expectContains(nativeShim, "dropTarget->setAccessibleDescription(dropTargetTitle)")
        expectContains(nativeShim, "dropTarget->setToolTip(dropTargetTitle)")
        expectContains(nativeShim, "dropTarget->setStatusTip(dropTargetTitle)")
        expectContains(nativeShim, "dropHint->setAccessibleName(dropTargetTitle)")
        expectContains(nativeShim, "dropHint->setAccessibleDescription(dropTargetTitle)")
        expectContains(nativeShim, "dropHint->setToolTip(dropTargetTitle)")
        expectContains(nativeShim, "dropHint->setStatusTip(dropTargetTitle)")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"dropTargetTitle\", QStringLiteral(\"Drop image files to attach\"))")
        expectContains(runtime, "dropTargetTitle: EnchantedCopy.dropTargetTitle")
        expectContains(nativeShim, "QStringList pendingAttachmentPaths")
        expectContains(nativeShim, "QScrollArea *attachmentScrollArea")
        expectContains(nativeShim, "QHBoxLayout *attachmentChipListLayout")
        expectContains(nativeShim, "QPushButton *removeAttachmentButton")
        expectContains(nativeShim, "removeAttachmentButton->setObjectName(QStringLiteral(\"chipRemoveButton\"))")
        expectContains(nativeShim, "QLabel *attachmentIcon = iconLabel(")
        expectContains(nativeShim, "attachmentChipLayout->addWidget(attachmentIcon)")
        expectContains(nativeShim, "applyButtonIconSize(removeAttachmentButton, style)")
        expectContains(nativeShim, "removeAttachmentButton->setToolTip(removeAttachmentTooltip)")
        expectContains(nativeShim, "removeAttachmentButton->setAccessibleName(removeAttachmentTooltip)")
        expectContains(nativeShim, "removeAttachmentButton->setAccessibleDescription(removeAttachmentTooltip)")
        expectContains(nativeShim, "removeAttachmentButton->setStatusTip(removeAttachmentTooltip)")
        expectContains(runtime, "attachmentRemoveButtonWidth: EnchantedVisualMetrics.attachmentRemoveButtonWidth")
        expectContains(nativeShim, "removeAttachmentButton->setFixedWidth(styleInt(style, \"attachmentRemoveButtonWidth\"))")
        expectDoesNotContain(nativeShim, "removeAttachmentButton->setFixedWidth(28)")
        expectContains(nativeShim, "pendingAttachmentPaths.removeAll(path)")
        expectContains(nativeShim, "? attachmentRemovedEmptyStatus")
        expectContains(nativeShim, "attachmentReadyStatus(\n                            pendingAttachmentPaths.count(),\n                            imageReadyStatusSingular,\n                            imageReadyStatusPluralUnit\n                        )")
        expectContains(nativeShim, "attachmentReadyStatus(\n            pendingAttachmentPaths.count(),\n            imageReadyStatusSingular,\n            imageReadyStatusPluralUnit\n        )")
        expectDoesNotContain(nativeShim, ": attachmentReadyStatus(pendingAttachmentPaths.count())")
        expectContains(nativeShim, "QTimer::singleShot(0, attachmentTray, renderAttachmentTray)")
        expectContains(nativeShim, "clearLayout(attachmentChipListLayout)")
        expectContains(nativeShim, "bool payloadBool(const QJsonObject &payload, const char *key)")
        expectContains(nativeShim, "payloadBool(payload, \"isLoading\")")
        expectContains(nativeShim, "QJsonObject payloadObject(const QJsonObject &payload, const char *key)")
        expectContains(nativeShim, "const QJsonObject style = payloadObject(payload, \"style\")")
        expectContains(nativeShim, "QJsonObject icons = payloadObject(payload, \"icons\")")
        expectContains(nativeShim, "\n        icons = payloadObject(payload, \"icons\")")
        expectContains(nativeShim, "QJsonArray payloadArray(const QJsonObject &payload, const char *key)")
        expectContains(nativeShim, "QJsonArray models = payloadArray(payload, \"models\")")
        expectContains(nativeShim, "QJsonArray conversations = payloadArray(payload, \"conversations\")")
        expectContains(nativeShim, "QJsonArray fallbackMessages = payloadArray(payload, \"messages\")")
        expectContains(nativeShim, "const QJsonArray prompts = payloadArray(payload, \"prompts\")")
        expectContains(nativeShim, "\n        models = payloadArray(payload, \"models\")")
        expectContains(nativeShim, "\n        conversations = payloadArray(payload, \"conversations\")")
        expectContains(nativeShim, "\n        fallbackMessages = payloadArray(payload, \"messages\")")
        expectContains(nativeShim, "payloadString(payload, \"sendTitle\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Send\")")
        expectContains(nativeShim, "payloadString(payload, \"stopTitle\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Stop\")")
        expectContains(nativeShim, "payloadString(payload, \"stoppingStatus\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Stopping...\")")
        expectContains(nativeShim, "payloadString(payload, \"removeAttachmentTooltip\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Remove attachment\")")
        expectContains(nativeShim, "payloadString(payload, \"imageReadyStatusSingular\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"1 image ready to send\")")
        expectContains(nativeShim, "payloadString(payload, \"imageReadyStatusPluralUnit\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"images ready to send\")")
        expectContains(nativeShim, "#include <QIcon>")
        expectContains(nativeShim, "#include <QPixmap>")
        expectContains(nativeShim, "#include <QStyle>")
        expectContains(nativeShim, "QIcon themedActionIcon(")
        expectContains(macOSRootView, "EnchantedVisualMetrics.primaryButtonIconSpacing")
        expectContains(nativeShim, "int buttonIconSize(const QJsonObject &style)")
        expectContains(nativeShim, "return styleInt(style, \"actionButtonIconSize\")")
        expectContains(nativeShim, "void applyButtonIconSize(QPushButton *button, const QJsonObject &style)")
        expectContains(nativeShim, "const int iconSize = buttonIconSize(style)")
        expectContains(nativeShim, "button->setIconSize(QSize(iconSize, iconSize))")
        expectContains(nativeShim, "layout->setSpacing(styleInt(style, spacingKey))")
        expectContains(nativeShim, "\"primaryButtonIconSpacing\"")
        expectContains(nativeShim, "\"primaryButtonVerticalPadding\"")
        expectContains(nativeShim, "\"primaryButtonHorizontalPadding\"")
        expectContains(nativeShim, "addIconTextButtonContent(\n        attachButton,\n        attachButtonIcon(icons),\n        attachTitle,\n        QStringLiteral(\"attachButtonIcon\"),\n        QStringLiteral(\"attachButtonText\"),\n        \"actionButtonIconSpacing\",")
        expectContains(nativeShim, "addIconTextButtonContent(\n        sendButton,\n        sendButtonIcon(icons, isLoading),\n        isLoading ? stopTitle : sendTitle,\n        QStringLiteral(\"sendButtonIcon\"),\n        QStringLiteral(\"sendButtonText\"),\n        \"actionButtonIconSpacing\",")
        expectContains(nativeShim, "void updateSendButtonPresentation(")
        expectContains(nativeShim, "updateSendButtonPresentation(sendButton, icons, isLoading, sendTitle, stopTitle, style)")
        expectContains(nativeShim, "button->setProperty(\"loading\", isLoading)")
        expectContains(nativeShim, "button->setText(QString())")
        expectContains(nativeShim, "QLabel *buttonText = button->findChild<QLabel *>(textObjectName)")
        expectContains(nativeShim, "buttonText->setText(title)")
        expectComponentSplitCount(nativeShim, separatedBy: "button->setProperty(\"loading\", isLoading)", count: 2)
        expectComponentSplitCount(nativeShim, separatedBy: "button->setText(QString())", count: 2)
        expectContains(runtime, "composerSendButtonMinWidth: EnchantedVisualMetrics.composerSendButtonMinWidth")
        expectContains(nativeShim, "sendButton->setMinimumWidth(styleInt(style, \"composerSendButtonMinWidth\"))")
        expectDoesNotContain(nativeShim, "sendButton->setMinimumWidth(86)")
        expectContains(nativeShim, "QPushButton#sendButton[loading=\"true\"]")
        expectContains(runtime, "var selectedModelSupportsImages: Bool")
        expectContains(runtime, "selectedModelSupportsImages: EnchantedPreviewFixture.selectedModel.quillLikelySupportsImages")
        expectContains(runtime, "snapshot.selectedModelSupportsImages = snapshot.models.contains(snapshot.selectedModel) && snapshot.selectedModel.quillLikelySupportsImages")
        expectContains(runtime, "let selectedModelAllowsAttachments = models.contains(effectiveSelectedModel) && effectiveSelectedModel.quillLikelySupportsImages")
        expectContains(runtime, "let attachments = selectedModelAllowsAttachments ? try imageAttachments(from: request.attachmentPaths ?? []) : []")
        expectContains(nativeShim, "bool modelLikelySupportsImages(const QString &modelName)")
        expectContains(nativeShim, "likelyVisionGemma3Model")
        expectContains(nativeShim, "lowercasedName.contains(QStringLiteral(\"qwen3-vl\"))")
        expectContains(nativeShim, "lowercasedName.contains(QStringLiteral(\"mistral-small3.2\"))")
        expectContains(nativeShim, "bool selectedModelSupportsImages(QComboBox *modelPicker, const QJsonObject &payload)")
        expectContains(nativeShim, "const bool hasPendingAttachments = !pendingAttachmentPaths.isEmpty()")
        expectContains(nativeShim, "bool hasAttachmentPathCandidates(const QLineEdit *field)")
        expectContains(nativeShim, "const bool hasAttachmentPathInput = hasAttachmentPathCandidates(attachmentPath)")
        expectContains(nativeShim, "const bool imageAttachmentsAvailable = selectedModelSupportsImages(modelPicker, payload)")
        expectContains(nativeShim, "attachmentInputRow->setVisible(imageAttachmentsAvailable)")
        expectContains(nativeShim, "attachmentPath->setVisible(imageAttachmentsAvailable)")
        expectContains(nativeShim, "unavailableModelButton->setVisible(false)")
        expectContains(nativeShim, "attachButton->setVisible(imageAttachmentsAvailable)")
        expectContains(nativeShim, "clearAttachmentsButton->setVisible(imageAttachmentsAvailable)")
        expectContains(nativeShim, "dropTarget->setAcceptDrops(imageAttachmentsAvailable)")
        expectContains(nativeShim, "if (!imageAttachmentsAvailable) {\n            dropTarget->resetDragState();\n        }")
        expectContains(nativeShim, "dropTarget->setVisible(imageAttachmentsAvailable || hasPendingAttachments)")
        expectContains(nativeShim, "if (!imageAttachmentsAvailable && dropHint != nullptr)")
        expectContains(nativeShim, "attachButton->setEnabled(imageAttachmentsAvailable && hasAttachmentPathInput)")
        expectContains(nativeShim, "clearAttachmentsButton->setEnabled(imageAttachmentsAvailable && (hasAttachmentPathInput || hasPendingAttachments))")
        expectDoesNotContain(nativeShim, "showUnavailableModelButton")
        expectContains(macOSRootView, "if !model.pendingImageAttachments.isEmpty")
        expectContains(nativeShim, "dropTargetLayout->addWidget(dropHint);\n\n    QFrame *attachmentTray")
        expectContains(nativeShim, "attachmentTray->setVisible(false);\n    dropTargetLayout->addWidget(attachmentTray);\n\n    QWidget *attachmentInputRow = new QWidget();\n    QHBoxLayout *dropLayout = new QHBoxLayout(attachmentInputRow)")
        expectContains(nativeShim, "dropTargetLayout->addWidget(attachmentInputRow)")
        expectDoesNotContain(nativeShim, "dropTargetLayout->addLayout(dropLayout);\n    composerLayout->addWidget(dropTarget);\n\n    QFrame *attachmentTray")
        expectContains(nativeShim, "sendButton->setEnabled(isLoading || hasTrimmedText(promptEditor) || hasPendingAttachments)")
        expectContains(nativeShim, "if (!selectedModelSupportsImages(modelPicker, payload)) {\n            return;\n        }\n\n        addPendingAttachmentPaths(paths)")
        expectContains(nativeShim, "auto attachPendingPath = [&]() {\n        if (!selectedModelSupportsImages(modelPicker, payload))")
        expectContains(nativeShim, "setStatusText(stoppingStatus)")
        expectContains(nativeShim, "clearAttachmentState(attachmentsClearedStatus)")
        expectContains(nativeShim, "clearAttachmentState(QString())")
        expectDoesNotContain(nativeShim, "discardUnsupportedAttachmentState")
        expectContains(nativeShim, "refreshButton->setEnabled(!isLoading)")
        expectContains(nativeShim, "isLoading = payloadBool(payload, \"isLoading\")")
        expectContains(nativeShim, "refreshStyle(sendButton)")
        expectContains(nativeShim, "refreshStyle(sendButton);\n        updateComposerControlState()")
        expectContains(nativeShim, "setStatusText(payloadString(payload, \"status\"));\n        refreshButton->setEnabled(!isLoading)")
        expectContains(nativeShim, "const QString updatedCurrentTitle = selectedConversationTitle(\n            conversations,\n            selectedID,\n            newConversationTitle\n        );\n        currentTitle->setText(updatedCurrentTitle);\n        updateHeaderTitleAccessibility(updatedCurrentTitle)")
        expectContains(nativeShim, "currentTitle->setText(newConversationTitle);\n        updateHeaderTitleAccessibility(newConversationTitle)")
        expectContains(nativeShim, "const QString updatedModelStatus = modelStatusText(model, chooseLocalModelStatus, usingModelStatusPrefix, usingModelStatusSeparator);\n        modelStatus->setText(updatedModelStatus);\n        updateModelStatusAccessibility(updatedModelStatus);\n        if (!selectedModelSupportsImages(modelPicker, payload)) {\n            clearAttachmentState(QString());\n        } else {\n            updateComposerControlState();\n        }")
        expectContains(nativeShim, "std::function<bool(const QString &, const QString &, const QString &, const QString &, const QStringList &)> requestHistoryAction")
        expectContains(nativeShim, "QStringLiteral(\"sendMessage\"),")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"messageText\"), trimmedMessageText)")
        expectContains(nativeShim, "const QString trimmingMessageID = editingMessageID")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"trimmingMessageID\"), trimmedTrimmingMessageID)")
        expectContains(nativeShim, "action.insert(QStringLiteral(\"attachmentPaths\"), encodedAttachmentPaths)")
        expectContains(nativeShim, "attachmentSummaryForPaths(pendingAttachmentPaths)")
        expectContains(nativeShim, "pendingAttachmentPaths = normalizedAttachmentPaths(pendingAttachmentPaths)")
        expectContains(nativeShim, "dropTarget->setDropHandler")
        expectContains(nativeShim, "pendingAttachmentPaths.append(path)")
        expectContains(nativeShim, "auto attachPendingPath = [&]()")
        expectContains(nativeShim, "QObject::connect(attachButton, &QPushButton::clicked, attachPendingPath)")
        expectContains(nativeShim, "QObject::connect(attachmentPath, &QLineEdit::returnPressed, attachPendingPath)")
        expectContains(nativeShim, "appendComposerMessage(promptEditor->toPlainText())")
        expectContains(nativeShim, "requestHistoryAction(QStringLiteral(\"newConversation\"), QString(), QString(), QString(), QStringList())")
        expectContains(nativeShim, "requestHistoryAction(QStringLiteral(\"deleteConversation\"), deletedConversationID, QString(), QString(), QStringList())")
        expectContains(nativeShim, "requestHistoryAction(QStringLiteral(\"deleteAllConversations\"), QString(), QString(), QString(), QStringList())")
        expectContains(runtime, "var trimmingMessageID: String?")
        expectContains(runtime, "trimmingMessageID: request.trimmingMessageID?.quillTrimmedNonEmpty")
        expectContains(runtime, "try context.deleteMessages(in: selectedConversationID, from: trimmingMessageID)")
        expectContains(runtime, "OllamaClient(baseURL: endpoint).chat(")
        expectContains(runtime, "context.insert(ChatMessage(")
        expectContains(runtime, "role: .assistant")
        expectContains(runtime, "EnchantedAssistantResponseFinalizer.finalContent(from: assistantReply)")
        #expect(runtime.components(separatedBy: "existingConversationID(request.conversationID, context: context)").count == 2)
        expectContains(nativeShim, "void removeConversationRow(QListWidget *list, int row)")
        expectContains(nativeShim, "deleteButton->setEnabled(conversationList->currentItem() != nullptr)")
        expectContains(nativeShim, "const bool hasConversations = conversationList->count() > 0")
        expectContains(nativeShim, "clearAllButton->setEnabled(hasConversations)")
        expectContains(nativeShim, "conversationList->setVisible(hasConversations)")
        expectContains(nativeShim, "emptyHistory->setVisible(!hasConversations)")
        expectContains(nativeShim, "conversationList->setCurrentRow(-1)")
        expectContains(nativeShim, "updateConversationSelectionStyles(conversationList)")
        expectContains(nativeShim, "QObject::connect(deleteButton, &QPushButton::clicked")
        expectContains(nativeShim, "removeConversationRow(conversationList, deletedRow)")
        expectContains(nativeShim, "QObject::connect(clearAllButton, &QPushButton::clicked")
        expectContains(nativeShim, "conversationList->clear()")
        expectContains(nativeShim, "QObject::connect(clearAttachmentsButton, &QPushButton::clicked")
        expectContains(nativeShim, "QObject::connect(promptEditor, &QPlainTextEdit::textChanged")
        expectContains(nativeShim, "const QString composerPlaceholder = payloadString(payload, \"composerPlaceholder\")")
        expectContains(nativeShim, "promptEditor->setAccessibleName(composerPlaceholder)")
        expectContains(nativeShim, "promptEditor->setAccessibleDescription(composerPlaceholder)")
        expectContains(nativeShim, "promptEditor->setToolTip(composerPlaceholder)")
        expectContains(nativeShim, "promptEditor->setStatusTip(composerPlaceholder)")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Ask a local model...\")")
        expectContains(nativeShim, "payloadString(payload, \"emptyStateTitle\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"Ask your local model\")")
        expectContains(nativeShim, "payloadString(payload, \"emptyStateSubtitle\")")
        expectDoesNotContain(nativeShim, "QStringLiteral(\"This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.\")")
        expectContains(nativeShim, "promptAction(prompt)")
        expectContains(nativeShim, "appendComposerMessage(promptEditor->toPlainText())")
        expectContains(nativeShim, "renderMessageSet(selectedMessages)")
        expectContains(nativeShim, "renderMessages(")
        expectContains(nativeShim, "QObject::connect(sendButton")
        expectContains(nativeSupport, "inline void clearLayout(QLayout *layout)")
        expectContains(nativeSupport, "inline bool parseJsonObjectPayload(")
        expectContains(nativeSupport, "inline bool jsonBoolValue(")
        expectContains(nativeSupport, "inline QByteArray executableNameBytes(")
        expectContains(nativeSupport, "inline QSize minimumWindowSize(")
        expectContains(nativeSupport, "inline QSize defaultWindowSize(")
        expectContains(nativeSupport, "inline void scrollAreaToBottomLater(QScrollArea *scrollArea)")
        expectContains(nativeSupport, "QScrollBar *scrollBar = scrollArea->verticalScrollBar()")
        expectContains(nativeSupport, "scrollBar->setValue(scrollBar->maximum())")
        expectContains(nativeSupport, "%s: invalid payload JSON at offset %lld: %s\\n")
        expectContains(nativeShim, "parseJsonObjectPayload(")
        expectContains(nativeShim, "QuillQtWidgets::executableNameBytes(argc, argv, \"quill-enchanted-qt\")")
        expectContains(nativeShim, "executableName.constData()")
        expectContains(nativeShim, "requiredWindowSize(payload, \"minimumWidth\", \"minimumHeight\")")
        expectContains(nativeShim, "clampedDefaultWindowSize(payload, minimumWindowSize)")
        expectDoesNotContain(nativeShim, "QSize resolvedMinimumWindowSize")
        expectDoesNotContain(nativeShim, "QSize resolvedDefaultWindowSize")
        expectContains(nativeShim, "QString stylePixels(const QJsonObject &style, const char *key)")
        expectContains(nativeShim, "int styleInt(const QJsonObject &style, const char *key)")
        expectDoesNotContain(nativeShim, "stringValue(payload, \"")
        expectDoesNotContain(nativeShim, "boolValue(payload, \"")
        expectDoesNotContain(nativeShim, "objectValue(payload, \"")
        expectDoesNotContain(nativeShim, "arrayValue(payload, \"")
        expectDoesNotContain(nativeShim, "intValue(style, \"")
        expectDoesNotContain(nativeShim, "cssPixels(style, \"")
        expectDoesNotContain(nativeShim, "styleValue(style, \"canvasColor\",")
        expectDoesNotContain(nativeShim, "QuillQtWidgets::minimumWindowSize(payload")
        expectDoesNotContain(nativeShim, "QuillQtWidgets::defaultWindowSize(payload")
        expectContains(nativeShim, "clearLayout(messageLayout)")
        expectDoesNotContain(nativeShim, "void clearLayout(QLayout *layout)")
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

    private func packageSource(_ path: String) throws -> String {
        let root = try packageRoot()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func expectContains(_ source: String, _ needle: String) {
        #expect(source.contains(needle))
    }

    private func expectDoesNotContain(_ source: String, _ needle: String) {
        #expect(!source.contains(needle))
    }

    private func expectComponentSplitCount(
        _ source: String,
        separatedBy separator: String,
        count expectedCount: Int
    ) {
        #expect(source.components(separatedBy: separator).count == expectedCount)
    }
}

private enum CoreContractMatrixTestError: Error {
    case packageRootNotFound
}

private let enchantedEmptyConversationPrompts: [String] = [
    "Give me phrases to learn in a new language",
    "Act like Mowgli from The Jungle Book and answer questions",
    "How to center div in HTML?",
    "What's unique about Go programming language?",
    "Give 10 gift ideas for best friend",
    "Write a text message asking a friend to be my plus-one at a wedding",
    "Explain supercomputers like I'm five years old",
    "How to do personal taxes in USA?",
    "What are the largest cities in USA in population? Give a table",
    "Give me ideas about New Years resolutions",
    "What is bubble sort? Write example in python"
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

struct ModelImageSupportCase: Sendable {
    var modelName: String
    var supportsImages: Bool
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

private let imageModelSupportCases: [ModelImageSupportCase] = [
    ModelImageSupportCase(modelName: "llava:latest", supportsImages: true),
    ModelImageSupportCase(modelName: "llama3.2-vision:latest", supportsImages: true),
    ModelImageSupportCase(modelName: "qwen2.5vl:7b", supportsImages: true),
    ModelImageSupportCase(modelName: "qwen2.5-vl:7b", supportsImages: true),
    ModelImageSupportCase(modelName: "qwen3-vl:8b", supportsImages: true),
    ModelImageSupportCase(modelName: "medgemma:4b", supportsImages: true),
    ModelImageSupportCase(modelName: "mistral-small3.2:latest", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3:latest", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3:4b", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3:12b", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3:27b", supportsImages: true),
    ModelImageSupportCase(modelName: "gemma3:1b", supportsImages: false),
    ModelImageSupportCase(modelName: "gemma3:270m", supportsImages: false),
    ModelImageSupportCase(modelName: "llama3.2:latest", supportsImages: false)
]

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

private let streamContentCases: [TextCase] =
    (0..<70).map { index in
        let content = "chunk-\(index)"
        return TextCase(
            input: #"{"message":{"role":"assistant","content":"\#(content)"},"done":false}"#,
            expected: content
        )
    }
    + (0..<70).map { index in
        let content = "response-\(index)"
        return TextCase(
            input: #"{"response":"\#(content)","done":false}"#,
            expected: content
        )
    }
    + (0..<20).map { index in
        let content = "sse-\(index)"
        return TextCase(
            input: #"data: {"message":{"role":"assistant","content":"\#(content)"},"done":false}"#,
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
