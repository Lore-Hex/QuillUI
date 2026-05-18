import Foundation
import QuillEnchantedCore
import QuillEnchantedShared
import QuillUI
#if canImport(SwiftUI)
import UniformTypeIdentifiers
#endif

// Adapted as a buildable Linux slice from Enchanted's Apache-2.0 upstream UI shape:
// ChatView_macOS.swift, InputFields_macOS.swift, EmptyConversaitonView.swift,
// and SimpleFloatingButton.swift at gluonfield/enchanted commit 2f82ee2.

struct ConversationSD: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var updatedAt = Date()

    init(id: String = UUID().uuidString, title: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }

    init(_ conversation: ConversationSummary) {
        self.id = conversation.id
        self.title = conversation.title
        self.updatedAt = conversation.updatedAt
    }

    static let sample = [
        ConversationSD(title: "Auto-config test: reply with one short phrase confirming you got this.", updatedAt: daysAgo(3, rank: 0)),
        ConversationSD(title: "say one short word", updatedAt: daysAgo(3, rank: 1)),
        ConversationSD(title: "say hi in one word", updatedAt: daysAgo(3, rank: 2)),
        ConversationSD(title: "Write a text message asking a friend to be my plus-one at a wedding", updatedAt: daysAgo(4, rank: 0)),
        ConversationSD(title: "Give me phrases to learn in a new language", updatedAt: daysAgo(7, rank: 0)),
        ConversationSD(title: "How to center div in HTML?", updatedAt: daysAgo(7, rank: 1))
    ]

    private static func daysAgo(_ days: Int, rank: Int) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return Calendar.current.date(byAdding: .second, value: -rank, to: day) ?? day
    }
}

struct MessageSD: Identifiable, Hashable, Sendable {
    var id: String
    var role: String
    var content: String
    var createdAt = Date()

    init(id: String = UUID().uuidString, role: String, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    init(_ message: ChatMessage) {
        self.id = message.id
        self.role = message.role.rawValue
        self.content = message.content
        self.createdAt = message.createdAt
    }

    static let sample = [
        MessageSD(role: "assistant", content: EnchantedCopy.systemLaunchMessage)
    ]
}

struct LanguageModelSD: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var supportsImages: Bool

    init(id: String? = nil, name: String, supportsImages: Bool) {
        self.id = id ?? name
        self.name = name
        self.supportsImages = supportsImages
    }

    init(_ model: OllamaModel) {
        self.id = model.name
        self.name = model.name
        self.supportsImages = model.name.quillLikelySupportsImages
    }

    static let sample = [
        LanguageModelSD(name: "llava:latest", supportsImages: true),
        LanguageModelSD(name: "llama3.2:latest", supportsImages: false)
    ]
}

enum ConversationState: Sendable {
    case completed
    case loading
}

struct SelectedImageAttachment: Identifiable {
    var attachment: PendingImageAttachment
    var preview: Image

    var id: String { attachment.id }
}

private enum EnchantedTheme {
    static var canvas: Color { Color(hex: EnchantedPalette.canvasColor) }
    static var sidebar: Color { Color(hex: EnchantedPalette.sidebarColor) }
    static var sidebarSelected: Color { Color(hex: EnchantedPalette.sidebarSelectedColor) }
    static var card: Color { Color(hex: EnchantedPalette.cardColor) }
    static var cardQuiet: Color { Color(hex: EnchantedPalette.cardQuietColor) }
    static var hairline: Color { Color(hex: EnchantedPalette.hairlineColor) }
    static var text: Color { Color(hex: EnchantedPalette.textColor) }
    static var secondaryText: Color { Color(hex: EnchantedPalette.secondaryTextColor) }
    static var accent: Color { Color(hex: EnchantedPalette.accentColor) }
    static var destructive: Color { Color(hex: EnchantedPalette.destructiveColor) }
}

private extension String {
    var upstreamTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func upstreamTitle(maxLength: Int = 44) -> String {
        let normalized = split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New conversation" }
        if trimmed.count <= maxLength { return trimmed }
        let prefixLength = max(1, maxLength - 3)
        return String(trimmed.prefix(prefixLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct UpstreamSliceApp: App {
    var body: some Scene {
        QuillAppWindow.scene(
            EnchantedCopy.windowTitle,
            width: Double(EnchantedVisualMetrics.defaultWindowWidth),
            height: Double(EnchantedVisualMetrics.defaultWindowHeight)
        ) {
            UpstreamSliceRoot()
        }
    }
}

@MainActor
struct UpstreamSliceRoot: View {
    @StateObject private var model = EnchantedModel()
    @State private var selectedSampleConversationID: String?
    @AppStorage("quill.enchanted.ollamaEndpoint") private var endpoint = "http://localhost:11434"

    private var hasStoredConversations: Bool {
        !model.conversations.isEmpty
    }

    private var conversations: [ConversationSD] {
        let storedConversations = model.conversations.map(ConversationSD.init)
        return storedConversations.isEmpty ? ConversationSD.sample : storedConversations
    }

    private var selectedSampleConversation: ConversationSD? {
        guard !hasStoredConversations else { return nil }
        let selectedID = selectedSampleConversationID
            ?? EnchantedInitialSelection.selectedConversationID(in: ConversationSD.sample)
        guard let selectedID else { return nil }
        return ConversationSD.sample.first { $0.id == selectedID }
    }

    private var selectedConversation: ConversationSD? {
        if let selectedSampleConversation {
            return selectedSampleConversation
        }

        guard let selectedConversationID = model.selectedConversationID else { return nil }
        return model.conversations.first { $0.id == selectedConversationID }.map(ConversationSD.init)
    }

    private var messages: [MessageSD] {
        if selectedSampleConversation != nil {
            return MessageSD.sample
        }

        return model.messages.map(MessageSD.init)
    }

    private var modelsList: [LanguageModelSD] {
        model.models.map(LanguageModelSD.init)
    }

    private var selectedModel: LanguageModelSD? {
        modelsList.first { $0.name == model.selectedModel }
    }

    nonisolated var body: some View {
        QuillMainActorView.assumeIsolated {
            ChatView(
                endpoint: $endpoint,
                selectedConversation: selectedConversation,
                conversations: conversations,
                messages: messages,
                modelsList: modelsList,
                onNewConversationTap: {
                    selectedSampleConversationID = nil
                    model.newConversation()
                },
                onRefreshModels: {
                    let model = model
                    Task {
                        await model.refreshModels()
                    }
                },
                onSendMessageTap: { prompt, _, attachment, trimmingMessageId in
                    let attachments = attachment.map { [$0] } ?? []
                    model.startSend(prompt, attachments: attachments, trimmingMessageID: trimmingMessageId)
                },
                onConversationTap: { conversation in
                    if let selected = model.conversations.first(where: { $0.id == conversation.id }) {
                        selectedSampleConversationID = nil
                        model.select(selected)
                    } else {
                        selectedSampleConversationID = conversation.id
                    }
                },
                conversationState: model.isLoading ? .loading : .completed,
                onStopGenerateTap: {
                    model.stopGenerating()
                },
                reachable: !model.models.isEmpty,
                statusMessage: model.status,
                modelSupportsImages: selectedModel?.supportsImages ?? false,
                selectedModel: selectedModel,
                onSelectModel: { model in
                    self.model.selectModel(named: model?.name)
                },
                onConversationDelete: { conversation in
                    if let selected = model.conversations.first(where: { $0.id == conversation.id }) {
                        model.delete(selected)
                    } else if selectedSampleConversationID == conversation.id {
                        selectedSampleConversationID = nil
                    }
                },
                onDeleteAllConversations: {
                    selectedSampleConversationID = nil
                    model.deleteAllConversations()
                },
                canDeleteAllConversations: !model.conversations.isEmpty,
                onAttachmentError: { message in
                    model.status = message
                },
                userInitials: "Q"
            )
            .onAppear {
                model.boot(endpoint: endpoint)
            }
            .onChange(of: endpoint) { _, value in
                model.configureEndpoint(value)
            }
        }
    }
}

struct ChatView: View {
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @Binding var endpoint: String
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var messages: [MessageSD]
    var modelsList: [LanguageModelSD]
    var onNewConversationTap: () -> Void
    var onRefreshModels: () -> Void
    var onSendMessageTap: (_ prompt: String, _ model: LanguageModelSD, _ attachment: PendingImageAttachment?, _ trimmingMessageId: String?) -> Void
    var onConversationTap: (_ conversation: ConversationSD) -> Void
    var conversationState: ConversationState
    var onStopGenerateTap: () -> Void
    var reachable: Bool
    var statusMessage: String
    var modelSupportsImages: Bool
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onConversationDelete: (_ conversation: ConversationSD) -> Void
    var onDeleteAllConversations: () -> Void
    var canDeleteAllConversations: Bool
    var onAttachmentError: (_ message: String) -> Void
    var userInitials: String

    @State private var message = ""
    @State private var editMessage: MessageSD?
    @FocusState private var isFocusedInput: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                endpoint: $endpoint,
                selectedConversation: selectedConversation,
                conversations: conversations,
                onNewConversationTap: onNewConversationTap,
                modelsList: modelsList,
                selectedModel: selectedModel,
                onSelectModel: onSelectModel,
                onRefreshModels: onRefreshModels,
                onConversationTap: onConversationTap,
                onConversationDelete: onConversationDelete,
                onDeleteAllConversations: onDeleteAllConversations,
                canDeleteAllConversations: canDeleteAllConversations
            )
            .navigationSplitViewColumnWidth(
                min: CGFloat(EnchantedVisualMetrics.sidebarWidth),
                ideal: CGFloat(EnchantedVisualMetrics.sidebarIdealWidth),
                max: CGFloat(EnchantedVisualMetrics.sidebarMaxWidth)
            )
        } detail: {
            VStack(alignment: .center, spacing: 0) {
                HeaderView(
                    selectedModel: selectedModel,
                    modelsList: modelsList,
                    onSelectModel: onSelectModel,
                    onNewConversationTap: onNewConversationTap,
                    onRefreshModels: onRefreshModels,
                    onDeleteAllConversations: onDeleteAllConversations,
                    canDeleteAllConversations: canDeleteAllConversations
                )

                Divider()

                ScrollView {
                    if selectedConversation != nil {
                        MessageListView(messages: messages, editMessage: $editMessage, userInitials: userInitials)
                    } else {
                        EmptyConversaitonView { selectedMessage in
                            if let selectedModel {
                                onSendMessageTap(selectedMessage, selectedModel, nil, nil)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !reachable && selectedConversation != nil {
                    QuillStatusBanner(
                        message: EnchantedCopy.unreachableOllamaMessage,
                        actionTitle: EnchantedCopy.settingsTitle
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                InputFieldsView(
                    message: $message,
                    conversationState: conversationState,
                    onStopGenerateTap: onStopGenerateTap,
                    selectedModel: selectedModel,
                    modelSupportsImages: modelSupportsImages,
                    onSendMessageTap: onSendMessageTap,
                    onAttachmentError: onAttachmentError,
                    editMessage: $editMessage
                )
                .padding(CGFloat(EnchantedVisualMetrics.composerPadding))
                .frame(
                    minWidth: CGFloat(EnchantedVisualMetrics.composerMinWidth),
                    maxWidth: CGFloat(EnchantedVisualMetrics.composerMaxWidth)
                )
            }
            .background(EnchantedTheme.canvas)
        }
        .onChange(of: editMessage) { _, newMessage in
            if let newMessage {
                message = newMessage.content
                isFocusedInput = true
            }
        }
    }
}

struct SidebarView: View {
    @Binding var endpoint: String
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onNewConversationTap: () -> Void
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onRefreshModels: () -> Void
    var onConversationTap: (_ conversation: ConversationSD) -> Void
    var onConversationDelete: (_ conversation: ConversationSD) -> Void
    var onDeleteAllConversations: () -> Void
    var canDeleteAllConversations: Bool
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuillConversationHistoryList(
                items: historyItems,
                selectedID: selectedConversation?.id
            ) { item in
                if let conversation = conversations.first(where: { $0.id == item.id }) {
                    onConversationTap(conversation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Spacer()

            Divider()

            if showSettings {
                UpstreamSettingsPanel(
                    modelsList: modelsList,
                    selectedModel: selectedModel,
                    onSelectModel: onSelectModel,
                    onRefreshModels: onRefreshModels,
                    onDeleteAllConversations: onDeleteAllConversations,
                    canDeleteAllConversations: canDeleteAllConversations
                )
            }

            QuillSidebarBottomNavigation(actions: [
                QuillSidebarNavigationAction(title: EnchantedCopy.completionsTitle, systemImage: EnchantedIcon.completions) {},
                QuillSidebarNavigationAction(title: EnchantedCopy.shortcutsTitle, systemImage: EnchantedIcon.shortcuts) {},
                QuillSidebarNavigationAction(title: EnchantedCopy.settingsTitle, systemImage: EnchantedIcon.settings) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showSettings.toggle()
                    }
                }
            ])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(EnchantedTheme.sidebar)
    }

    private var historyItems: [QuillConversationHistoryItem] {
        conversations.map {
            QuillConversationHistoryItem(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
        }
    }
}

struct UpstreamSettingsPanel: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onRefreshModels: () -> Void
    var onDeleteAllConversations: () -> Void
    var canDeleteAllConversations: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(EnchantedCopy.modelLabel)
                    .font(
                        .system(
                            size: CGFloat(EnchantedTypography.captionFontSize),
                            weight: enchantedFontWeight(EnchantedTypography.sectionTitleFontWeight)
                        )
                    )
                    .foregroundColor(EnchantedTheme.text)
                Spacer()
                Button(EnchantedCopy.refreshModelsTitle) {
                    onRefreshModels()
                }
                .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
            }

            if modelsList.isEmpty {
                Text(EnchantedCopy.noModelsTitle)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleModels) { model in
                        Button(action: { onSelectModel(model) }) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(model.id == selectedModel?.id ? EnchantedTheme.accent : EnchantedTheme.hairline)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                                        .lineLimit(1)
                                    if model.supportsImages {
                                        Text("Vision")
                                            .font(.system(size: CGFloat(EnchantedTypography.attachmentSizeFontSize)))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(model.id == selectedModel?.id ? EnchantedTheme.sidebarSelected : EnchantedTheme.card)
                            .cornerRadius(7)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Button(EnchantedCopy.clearAllTitle) {
                onDeleteAllConversations()
            }
            .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
            .foregroundColor(EnchantedTheme.destructive)
            .disabled(!canDeleteAllConversations)
        }
        .padding(10)
        .background(EnchantedTheme.card)
        .cornerRadius(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(EnchantedTheme.hairline, lineWidth: 1)
        }
    }

    private var visibleModels: [LanguageModelSD] {
        Array(modelsList[0..<min(modelsList.count, 6)])
    }
}

struct HeaderView: View {
    var selectedModel: LanguageModelSD?
    var modelsList: [LanguageModelSD]
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onNewConversationTap: () -> Void
    var onRefreshModels: () -> Void
    var onDeleteAllConversations: () -> Void
    var canDeleteAllConversations: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(EnchantedCopy.appTitle)
                .font(
                    .system(
                        size: CGFloat(EnchantedTypography.currentTitleFontSize),
                        weight: enchantedFontWeight(EnchantedTypography.currentTitleFontWeight)
                    )
                )
                .foregroundColor(EnchantedTheme.text)

            Spacer()

            Button(action: {
                guard !modelsList.isEmpty else {
                    onSelectModel(nil)
                    return
                }
                let currentIndex = modelsList.firstIndex { $0.id == selectedModel?.id } ?? -1
                let nextIndex = (currentIndex + 1) % modelsList.count
                onSelectModel(modelsList[nextIndex])
            }) {
                Text(selectedModel?.name ?? EnchantedCopy.modelLabel)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(EnchantedTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(EnchantedTheme.cardQuiet)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            QuillFloatingIconButton(systemImage: EnchantedIcon.newConversation, action: onNewConversationTap)

            QuillMenuButton(actions: [
                QuillMenuAction(title: EnchantedCopy.newChatTitle, systemImage: EnchantedIcon.newConversation, action: onNewConversationTap),
                QuillMenuAction(title: EnchantedCopy.refreshModelsTitle, systemImage: EnchantedIcon.refreshModels, action: onRefreshModels),
                .divider(id: "history-divider"),
                QuillMenuAction(
                    title: EnchantedCopy.clearAllTitle,
                    systemImage: "trash",
                    isDisabled: !canDeleteAllConversations,
                    action: onDeleteAllConversations
                )
            ])
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(EnchantedTheme.canvas)
    }
}

struct MessageListView: View {
    var messages: [MessageSD]
    @Binding var editMessage: MessageSD?
    var userInitials: String

    var body: some View {
        ScrollViewReader { _ in
            VStack(alignment: .leading, spacing: 12) {
                ForEach(messages) { message in
                    HStack(alignment: .top, spacing: 10) {
                        Text(message.role == "user" ? userInitials : "E")
                            .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                            .frame(width: 28, height: 28)
                            .background(message.role == "user" ? EnchantedTheme.accent : EnchantedTheme.sidebarSelected)
                            .foregroundColor(message.role == "user" ? .white : .primary)
                            .cornerRadius(14)

                        messageBody(message)
                            .padding(12)
                            .frame(maxWidth: CGFloat(EnchantedVisualMetrics.messageMaxWidth), alignment: .leading)
                            .background(message.role == "user" ? EnchantedTheme.cardQuiet : EnchantedTheme.card)
                            .cornerRadius(8)
                            .contextMenu {
                                if message.role == "user" {
#if canImport(SwiftUI)
                                    Button("Edit") {
                                        editMessage = message
                                    }
#else
                                    MenuItem("Edit") {
                                        editMessage = message
                                    }
#endif
                                }
                            }
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func messageBody(_ message: MessageSD) -> some View {
        if message.role == "assistant" || message.role == "system" {
            MarkdownMessageView(markdown: message.content, foregroundColor: EnchantedTheme.text)
        } else {
            Text(message.content)
                .foregroundColor(EnchantedTheme.text)
                .lineSpacing(3)
        }
    }
}

struct EmptyConversaitonView: View {
    var sendPrompt: (String) -> Void

    private var prompts: [QuillPrompt] {
        EnchantedPromptCatalog.visibleEmptyConversationPrompts.map {
            QuillPrompt(title: $0.title, systemImage: $0.systemImage)
        }
    }

    var body: some View {
        QuillChatEmptyState(brandTitle: EnchantedCopy.appTitle, prompts: prompts, columns: 4) { prompt in
            sendPrompt(prompt.title)
        }
    }
}

struct InputFieldsView: View {
    @Binding var message: String
    var conversationState: ConversationState
    var onStopGenerateTap: () -> Void
    var selectedModel: LanguageModelSD?
    var modelSupportsImages: Bool
    var onSendMessageTap: (_ prompt: String, _ model: LanguageModelSD, _ attachment: PendingImageAttachment?, _ trimmingMessageId: String?) -> Void
    var onAttachmentError: (_ message: String) -> Void
    @Binding var editMessage: MessageSD?

    @State private var selectedImage: SelectedImageAttachment?
    @State private var fileDropActive = false
    @State private var fileSelectingActive = false
    @FocusState private var isFocusedInput: Bool

    private func sendMessage() {
        guard let selectedModel, message.upstreamTrimmedNonEmpty != nil || selectedImage != nil else { return }
        onSendMessageTap(
            message.upstreamTrimmedNonEmpty ?? EnchantedCopy.attachmentDefaultPrompt,
            selectedModel,
            selectedImage?.attachment,
            editMessage?.id
        )
        withAnimation {
            editMessage = nil
            selectedImage = nil
            message = ""
            isFocusedInput = false
        }
    }

    private func stageImportedImage(url: URL) {
        do {
            let attachment = try PendingImageAttachment.stagedCopy(from: url)
            selectedImage = SelectedImageAttachment(
                attachment: attachment,
                preview: previewImage(for: attachment)
            )
        } catch {
            onAttachmentError(error.localizedDescription)
        }
    }

    private func stageDroppedImage(data: Data) {
        do {
            let attachment = try PendingImageAttachment.stagedData(data)
            selectedImage = SelectedImageAttachment(
                attachment: attachment,
                preview: Image(data: data)
            )
        } catch {
            onAttachmentError(error.localizedDescription)
        }
    }

    private func previewImage(for attachment: PendingImageAttachment) -> Image {
        if let data = try? Data(contentsOf: attachment.fileURL) {
            return Image(data: data)
        }
        return Image(systemName: QuillSystemSymbol.compatibleName("photo.fill"))
    }

    var body: some View {
        HStack(spacing: 20) {
            if let selectedImage {
                RemovableImage(image: selectedImage.preview) {
                    self.selectedImage = nil
                }
            }

            ZStack(alignment: .trailing) {
                TextField(EnchantedCopy.composerPlaceholder, text: $message.animation(.easeOut(duration: 0.3)), axis: .vertical)
                    .focused($isFocusedInput)
                    .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .clipped()
                    .textFieldStyle(.plain)
                    .onSubmit {
                        sendMessage()
                    }
                    .allowsHitTesting(!fileDropActive)
                    .padding(.trailing, 86)

                HStack(spacing: 10) {
                    if selectedModel == nil {
                        QuillFloatingIconButton(systemImage: "waveform") {}
                            .disabled(true)
                    } else {
                        QuillFloatingIconButton(systemImage: EnchantedIcon.attach) {
                            fileSelectingActive.toggle()
                        }
                        .disabled(!modelSupportsImages)
                        .fileImporter(
                            isPresented: $fileSelectingActive,
                            allowedContentTypes: [.png, .jpeg, .tiff],
                            onCompletion: { result in
                                if case .success(let url) = result,
                                   url.startAccessingSecurityScopedResource() {
                                    defer { url.stopAccessingSecurityScopedResource() }
                                    stageImportedImage(url: url)
                                }
                            }
                        )

                        switch conversationState {
                        case .loading:
                            QuillFloatingIconButton(systemImage: EnchantedIcon.stop, action: onStopGenerateTap)
                        case .completed:
                            QuillFloatingIconButton(systemImage: EnchantedIcon.send) {
                                sendMessage()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(EnchantedTheme.card)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(EnchantedTheme.hairline, lineWidth: 1)
        }
        .overlay {
            if fileDropActive {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(EnchantedTheme.accent, lineWidth: 2)
            }
        }
        .onDrop(of: [.image], isTargeted: $fileDropActive.animation()) { providers in
            guard let provider = providers.first else { return false }
#if os(Linux)
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                if let data {
                    stageDroppedImage(data: data)
                }
            }
#else
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                if let data {
                    Task { @MainActor in
                        stageDroppedImage(data: data)
                    }
                }
            }
#endif
            return true
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isFocusedInput = true
        }
    }
}

struct RemovableImage: View {
    var image: Image
    var onClick: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            image
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onClick) {
                Image(systemName: QuillSystemSymbol.compatibleName(EnchantedIcon.removeAttachment))
                    .foregroundColor(EnchantedTheme.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

QuillApp.run(UpstreamSliceApp.self)
