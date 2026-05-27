import Foundation
import QuillEnchantedShared
import QuillUI
#if canImport(SwiftUI)
import SwiftUI
#endif

private func enchantedSystemImageName(_ systemImage: String) -> String {
    QuillSystemSymbol.compatibleName(systemImage)
}

@MainActor
public struct EnchantedRootView: View {
    @StateObject private var model = EnchantedModel()
    @AppStorage("quill.enchanted.ollamaEndpoint") private var endpoint = EnchantedCopy.defaultEndpoint

    public init() {}

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            let useReferenceSize = ProcessInfo.processInfo.environment["QUILLUI_ENCHANTED_REFERENCE_MODE"] == "1"
            let width = useReferenceSize ? 1114.0 : nil
            let height = useReferenceSize ? 749.0 : nil

            let content = HStack(spacing: 0) {
                sidebar
                    .frame(width: CGFloat(EnchantedVisualMetrics.sidebarWidth))
                    .background(QuillColors.sidebar)

                Divider()

                chatSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(QuillColors.canvas)
            }
            .font(.system(size: CGFloat(EnchantedTypography.rootFontSize)))

            let finalView = content
                .onAppear {
                    model.boot(endpoint: endpoint)
                }
                .onChange(of: endpoint) { _, value in
                    model.configureEndpoint(value)
                }

            if useReferenceSize {
                return AnyView(finalView
                    .frame(width: 1114, height: 721)
                    .frame(
                        minWidth: 1114,
                        minHeight: 721
                    ))
            } else {
                return AnyView(finalView
                    .frame(
                        minWidth: CGFloat(EnchantedVisualMetrics.minimumWindowWidth),
                        minHeight: CGFloat(EnchantedVisualMetrics.minimumWindowHeight)
                    ))
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarSpacing)) {
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarTitleSpacing)) {
                Text(EnchantedCopy.appTitle)
                    .font(.system(size: CGFloat(EnchantedTypography.appTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.appTitleFontWeight)))
                    .foregroundColor(QuillColors.ink)
                Text(EnchantedCopy.sidebarSubtitle)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(QuillColors.muted)
            }

            Button(action: model.newConversation) {
                HStack(spacing: CGFloat(EnchantedVisualMetrics.primaryButtonIconSpacing)) {
                    Image(systemName: enchantedSystemImageName(EnchantedIcon.newConversation))
                    Text(EnchantedCopy.newChatTitle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(CGFloat(EnchantedVisualMetrics.primaryButtonPadding))
                .background(QuillColors.primary)
                .foregroundColor(.white)
                .cornerRadius(CGFloat(EnchantedVisualMetrics.primaryButtonRadius))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(EnchantedCopy.newChatTitle)
            .help(EnchantedCopy.newChatTitle)

            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarControlGroupSpacing)) {
                Text(EnchantedCopy.endpointLabel)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(QuillColors.muted)
                TextField(EnchantedCopy.defaultEndpoint, text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(EnchantedCopy.endpointLabel)
                    .help(EnchantedCopy.endpointLabel)
            }

            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.sidebarControlGroupSpacing)) {
                Text(EnchantedCopy.modelLabel)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(QuillColors.muted)
                if model.models.isEmpty {
                    Text(EnchantedCopy.noModelsTitle)
                        .font(.system(size: CGFloat(EnchantedTypography.warningTextFontSize)))
                        .foregroundColor(QuillColors.warning)
                } else {
                    Picker(EnchantedCopy.modelLabel, selection: modelSelection) {
                        ForEach(model.models) { ollamaModel in
                            Text(ollamaModel.name).tag(ollamaModel.name)
                        }
                    }
                    .accessibilityLabel(EnchantedCopy.modelLabel)
                    .help(EnchantedCopy.modelLabel)
                }
            }

            HStack(spacing: CGFloat(EnchantedVisualMetrics.statusRowSpacing)) {
                statusDot
                Text(model.status)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(QuillColors.muted)
                    .frame(width: CGFloat(EnchantedVisualMetrics.statusTextWidth), alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(model.status)
            .help(model.status)

            Divider()

            Text(EnchantedCopy.conversationsTitle)
                .font(.system(size: CGFloat(EnchantedTypography.sectionTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.sectionTitleFontWeight)))
                .foregroundColor(QuillColors.ink)

            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.conversationListSpacing)) {
                    if model.conversations.isEmpty {
                        emptyHistory
                    } else {
                        ForEach(model.conversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: conversation.id == model.selectedConversationID
                            ) {
                                model.select(conversation)
                            }
                        }
                    }
                }
            }

            HStack(spacing: CGFloat(EnchantedVisualMetrics.conversationActionsSpacing)) {
                Button {
                    model.deleteSelectedConversation()
                } label: {
                    HStack(spacing: CGFloat(EnchantedVisualMetrics.actionButtonIconSpacing)) {
                        Image(systemName: enchantedSystemImageName(EnchantedIcon.deleteChat))
                        Text(EnchantedCopy.deleteChatTitle)
                    }
                }
                .disabled(model.selectedConversationID == nil)
                .accessibilityLabel(EnchantedCopy.deleteChatTitle)
                .help(EnchantedCopy.deleteChatTitle)

                Button {
                    model.deleteAllConversations()
                } label: {
                    HStack(spacing: CGFloat(EnchantedVisualMetrics.actionButtonIconSpacing)) {
                        Image(systemName: enchantedSystemImageName(EnchantedIcon.clearAll))
                        Text(EnchantedCopy.clearAllTitle)
                    }
                }
                .disabled(model.conversations.isEmpty)
                .accessibilityLabel(EnchantedCopy.clearAllTitle)
                .help(EnchantedCopy.clearAllTitle)
            }
            .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
        }
        .padding(CGFloat(EnchantedVisualMetrics.sidebarPadding))
    }

    private var chatSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            chatHeader
                .padding(CGFloat(EnchantedVisualMetrics.headerPadding))
                .frame(
                    minHeight: CGFloat(EnchantedVisualMetrics.headerHeight),
                    idealHeight: CGFloat(EnchantedVisualMetrics.headerHeight),
                    maxHeight: CGFloat(EnchantedVisualMetrics.headerHeight)
                )
                .quillGTKSizeRequest(height: EnchantedVisualMetrics.headerHeight)
                .background(QuillColors.header)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.messageSpacing)) {
                    if model.messages.isEmpty {
                        EmptyConversationView { prompt in
                            model.startSend(prompt)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(model.messages) { message in
                            MessageBubble(
                                message: message,
                                isEditing: message.id == model.editingMessageID,
                                editMessage: { message in
                                    model.editMessage(message)
                                },
                                cancelEdit: model.cancelMessageEdit
                            )
                        }
                    }

                    if model.isLoading {
                        HStack(spacing: CGFloat(EnchantedVisualMetrics.loadingRowSpacing)) {
                            ProgressView()
                            Text(model.status)
                                .foregroundColor(QuillColors.muted)
                        }
                        .padding(.top, CGFloat(EnchantedVisualMetrics.loadingTopPadding))
                        .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    }
                }
                .padding(CGFloat(EnchantedVisualMetrics.contentPadding))
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            composer
                .padding(CGFloat(EnchantedVisualMetrics.composerPadding))
                .frame(
                    minWidth: CGFloat(EnchantedVisualMetrics.composerMinWidth),
                    maxWidth: CGFloat(EnchantedVisualMetrics.composerMaxWidth)
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .background(QuillColors.header)
        }
    }

    private var chatHeader: some View {
        HStack(spacing: CGFloat(EnchantedVisualMetrics.headerSpacing)) {
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.headerTitleSpacing)) {
                Text(currentTitle)
                    .font(.system(size: CGFloat(EnchantedTypography.currentTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.currentTitleFontWeight)))
                    .foregroundColor(QuillColors.ink)
                    .frame(width: CGFloat(EnchantedVisualMetrics.headerTitleWidth), alignment: .leading)
                    .accessibilityLabel(currentTitle)
                    .help(currentTitle)
                Text(modelStatusText)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(QuillColors.muted)
                    .frame(width: CGFloat(EnchantedVisualMetrics.headerTitleWidth), alignment: .leading)
                    .accessibilityLabel(modelStatusText)
                    .help(modelStatusText)
            }

            Spacer()

            Button {
                let model = model
                Task {
                    await model.refreshModels()
                }
            } label: {
                HStack(spacing: CGFloat(EnchantedVisualMetrics.actionButtonIconSpacing)) {
                    Image(systemName: enchantedSystemImageName(EnchantedIcon.refreshModels))
                    Text(EnchantedCopy.refreshModelsTitle)
                }
            }
            .disabled(model.isLoading)
            .accessibilityLabel(EnchantedCopy.refreshModelsTitle)
            .help(EnchantedCopy.refreshModelsTitle)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.composerSpacing)) {
            if selectedModelSupportsImages, model.isAttachmentDropTargeted {
                HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentInputSpacing)) {
                    Image(systemName: enchantedSystemImageName(EnchantedIcon.dropTarget))
                    Text(EnchantedCopy.dropTargetTitle)
                }
                .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                .foregroundColor(QuillColors.primary)
                .padding(CGFloat(EnchantedVisualMetrics.dropTargetPadding))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillColors.dropTarget)
                .cornerRadius(CGFloat(EnchantedVisualMetrics.dropTargetRadius))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(EnchantedCopy.dropTargetTitle)
                .help(EnchantedCopy.dropTargetTitle)
            }

            if !model.pendingImageAttachments.isEmpty {
                attachmentTray
            }

            if selectedModelSupportsImages {
                HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentInputSpacing)) {
                    TextField(EnchantedCopy.attachmentPlaceholder, text: attachmentPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(EnchantedCopy.attachmentPlaceholder)
                        .help(EnchantedCopy.attachmentPlaceholder)

                    Button(action: {
                        model.addAttachmentPath()
                    }) {
                        HStack(spacing: CGFloat(EnchantedVisualMetrics.actionButtonIconSpacing)) {
                            Image(systemName: enchantedSystemImageName(EnchantedIcon.attach))
                            Text(EnchantedCopy.attachTitle)
                        }
                    }
                    .disabled(!hasAttachmentPathCandidates)
                    .accessibilityLabel(EnchantedCopy.attachTitle)
                    .help(EnchantedCopy.attachTitle)

                    Button(EnchantedCopy.clearAttachmentsTitle) {
                        model.clearAttachments()
                    }
                    .disabled(model.pendingImageAttachments.isEmpty && !hasAttachmentPathCandidates)
                    .accessibilityLabel(EnchantedCopy.clearAttachmentsTitle)
                    .help(EnchantedCopy.clearAttachmentsTitle)
                }
            }

            HStack(alignment: .bottom, spacing: CGFloat(EnchantedVisualMetrics.promptRowSpacing)) {
                TextEditor(text: composerText)
                    .frame(
                        minHeight: CGFloat(EnchantedVisualMetrics.composerMinHeight),
                        maxHeight: CGFloat(EnchantedVisualMetrics.composerMaxHeight)
                    )
                    .background(.white)
                    .cornerRadius(CGFloat(EnchantedVisualMetrics.composerEditorRadius))
                    .accessibilityLabel(EnchantedCopy.composerPlaceholder)
                    .help(EnchantedCopy.composerPlaceholder)

                Button(action: {
                    if model.isLoading {
                        model.stopGenerating()
                    } else {
                        model.startComposerMessage()
                    }
                }) {
                    HStack(spacing: CGFloat(EnchantedVisualMetrics.actionButtonIconSpacing)) {
                        Image(systemName: enchantedSystemImageName(model.isLoading ? EnchantedIcon.stop : EnchantedIcon.send))
                        Text(sendActionTitle)
                    }
                    .padding(CGFloat(EnchantedVisualMetrics.primaryButtonPadding))
                    .background(model.isLoading ? QuillColors.warning : QuillColors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(CGFloat(EnchantedVisualMetrics.primaryButtonRadius))
                }
                .buttonStyle(.plain)
                .disabled(sendDisabled)
                .accessibilityLabel(sendActionTitle)
                .help(sendActionTitle)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard selectedModelSupportsImages else { return false }
            model.addAttachments(urls: urls)
            return true
        } isTargeted: { isTargeted in
            model.isAttachmentDropTargeted = selectedModelSupportsImages && isTargeted
        }
    }

    private var currentTitle: String {
        model.conversations.first(where: { $0.id == model.selectedConversationID })?.title ?? EnchantedCopy.newConversationTitle
    }

    private var modelStatusText: String {
        model.selectedModel.isEmpty ? EnchantedCopy.chooseLocalModelStatus : EnchantedCopy.usingModel(model.selectedModel)
    }

    private var sendActionTitle: String {
        model.isLoading ? EnchantedCopy.stopTitle : EnchantedCopy.sendTitle
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { model.selectedModel },
            set: { model.selectModel(named: $0) }
        )
    }

    private var composerText: Binding<String> {
        Binding(
            get: { model.composerText },
            set: { model.composerText = $0 }
        )
    }

    private var attachmentPath: Binding<String> {
        Binding(
            get: { model.attachmentPath },
            set: { model.attachmentPath = $0 }
        )
    }

    private var selectedModelSupportsImages: Bool {
        model.selectedModelSupportsImages
    }

    private var sendDisabled: Bool {
        if model.isLoading { return false }
        return model.composerText.quillTrimmedNonEmpty == nil && model.pendingImageAttachments.isEmpty
    }

    private var hasAttachmentPathCandidates: Bool {
        !PendingImageAttachment.attachmentPathCandidates(from: model.attachmentPath).isEmpty
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.attachmentTraySpacing)) {
            Text(EnchantedCopy.attachmentsTitle)
                .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                .foregroundColor(QuillColors.muted)
                .accessibilityLabel(EnchantedCopy.attachmentsTitle)
            ScrollView(.horizontal) {
                HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentTrayChipSpacing)) {
                    ForEach(model.pendingImageAttachments) { attachment in
                        AttachmentChip(attachment: attachment) {
                            model.removeAttachment(id: attachment.id)
                        }
                    }
                }
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(model.models.isEmpty ? QuillColors.warning : QuillColors.success)
            .frame(
                width: CGFloat(EnchantedVisualMetrics.statusDotSize),
                height: CGFloat(EnchantedVisualMetrics.statusDotSize)
            )
    }

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.emptyHistorySpacing)) {
            Text(EnchantedCopy.emptyHistoryTitle)
                .font(.system(size: CGFloat(EnchantedTypography.sectionTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.sectionTitleFontWeight)))
                .foregroundColor(QuillColors.ink)
            Text(EnchantedCopy.emptyHistorySubtitle)
                .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                .foregroundColor(QuillColors.muted)
        }
        .padding(CGFloat(EnchantedVisualMetrics.emptyHistoryPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QuillColors.card)
        .cornerRadius(CGFloat(EnchantedVisualMetrics.emptyHistoryRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(EnchantedCopy.emptyHistoryTitle)
        .accessibilityValue(EnchantedCopy.emptyHistorySubtitle)
        .help(EnchantedCopy.emptyHistorySubtitle)
    }
}

private struct ConversationRow: View {
    var conversation: ConversationSummary
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.conversationRowSpacing)) {
                Text(conversation.title)
                    .font(.system(size: CGFloat(EnchantedTypography.conversationTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.conversationTitleFontWeight)))
                    .foregroundColor(isSelected ? .white : QuillColors.ink)
                    .lineLimit(1)
                if !conversation.lastMessage.isEmpty {
                    Text(conversation.lastMessage)
                        .font(.system(size: CGFloat(EnchantedTypography.conversationPreviewFontSize)))
                        .foregroundColor(isSelected ? QuillColors.selectedMuted : QuillColors.muted)
                        .lineLimit(2)
                }
            }
            .padding(CGFloat(EnchantedVisualMetrics.conversationRowPadding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? QuillColors.primary : QuillColors.card)
            .cornerRadius(CGFloat(EnchantedVisualMetrics.conversationRowRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(conversation.title)
        .accessibilityValue(conversation.lastMessage)
        .help(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        conversation.lastMessage.isEmpty ? conversation.title : "\(conversation.title)\n\(conversation.lastMessage)"
    }
}

private struct EmptyConversationView: View {
    var send: (String) -> Void

    private let prompts = EnchantedPromptCatalog.visibleEmptyConversationPrompts

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.emptyStateSpacing)) {
            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.emptyStateHeaderSpacing)) {
                Text(EnchantedCopy.emptyStateTitle)
                    .font(.system(size: CGFloat(EnchantedTypography.currentTitleFontSize), weight: enchantedFontWeight(EnchantedTypography.currentTitleFontWeight)))
                    .foregroundColor(QuillColors.ink)
                if !EnchantedCopy.emptyStateSubtitle.isEmpty {
                    Text(EnchantedCopy.emptyStateSubtitle)
                        .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                        .foregroundColor(QuillColors.muted)
                        .frame(width: CGFloat(EnchantedVisualMetrics.promptButtonWidth), alignment: .leading)
                }
            }

            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.promptListSpacing)) {
                ForEach(prompts, id: \.title) { prompt in
                    Button(action: { send(prompt.title) }) {
                        HStack(spacing: CGFloat(EnchantedVisualMetrics.promptButtonIconSpacing)) {
                            Image(systemName: enchantedSystemImageName(prompt.systemImage))
                            Text(prompt.title)
                                .frame(
                                    width: CGFloat(EnchantedVisualMetrics.promptButtonWidth - EnchantedVisualMetrics.promptButtonTextWidthInset),
                                    alignment: .leading
                                )
                        }
                        .padding(CGFloat(EnchantedVisualMetrics.promptButtonPadding))
                        .frame(width: CGFloat(EnchantedVisualMetrics.promptButtonWidth), alignment: .leading)
                        .background(QuillColors.card)
                        .cornerRadius(CGFloat(EnchantedVisualMetrics.promptButtonRadius))
                    }
                    .buttonStyle(.plain)
                    .frame(width: CGFloat(EnchantedVisualMetrics.promptButtonWidth), alignment: .leading)
                    .accessibilityLabel(prompt.title)
                    .help(prompt.title)
                }
            }
        }
        .padding(CGFloat(EnchantedVisualMetrics.emptyStatePadding))
        .frame(maxWidth: CGFloat(EnchantedVisualMetrics.emptyStateMaxWidth), alignment: .leading)
    }
}

private struct MessageBubble: View {
    var message: ChatMessage
    var isEditing: Bool
    var editMessage: (ChatMessage) -> Void
    var cancelEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CGFloat(EnchantedVisualMetrics.messageBubbleRowSpacing)) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.messageBubbleSpacing)) {
                Text(label)
                    .font(.system(size: CGFloat(EnchantedTypography.captionFontSize)))
                    .foregroundColor(labelColor)
                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: CGFloat(EnchantedTypography.messageBodyFontSize)))
                        .foregroundColor(textColor)
                        .lineSpacing(3)
                } else {
                    MarkdownMessageView(markdown: message.content, foregroundColor: textColor)
                }
            }
            .padding(CGFloat(EnchantedVisualMetrics.messageBubblePadding))
            .frame(maxWidth: CGFloat(EnchantedVisualMetrics.messageMaxWidth), alignment: .leading)
            .background(backgroundColor)
            .cornerRadius(CGFloat(EnchantedVisualMetrics.messageBubbleRadius))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(EnchantedVisualMetrics.messageBubbleRadius))
                    .stroke(
                        isEditing ? editingBorderColor : Color.clear,
                        lineWidth: CGFloat(EnchantedVisualMetrics.messageEditBorderWidth)
                    )
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityValue(message.content)
            .help(accessibilitySummary)
            .contextMenu {
                Button(action: copyMessageContent) {
                    Label(
                        EnchantedCopy.copyMessageTitle,
                        systemImage: enchantedSystemImageName(EnchantedIcon.copyMessage)
                    )
                }
                if message.role == .user {
                    Button(action: editMessageContent) {
                        Label(
                            EnchantedCopy.editMessageTitle,
                            systemImage: enchantedSystemImageName(EnchantedIcon.editMessage)
                        )
                    }
                    if isEditing {
                        Button(action: cancelEdit) {
                            Label(
                                EnchantedCopy.unselectMessageTitle,
                                systemImage: enchantedSystemImageName(EnchantedIcon.editMessage)
                            )
                        }
                    }
                }
            }

            if message.role != .user {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private func copyMessageContent() {
        EnchantedClipboard.setString(message.content)
    }

    private func editMessageContent() {
        editMessage(message)
    }

    private var label: String {
        switch message.role {
        case .user:
            return EnchantedCopy.userRoleLabel
        case .assistant:
            return EnchantedCopy.assistantRoleLabel
        case .system:
            return EnchantedCopy.systemRoleLabel
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return QuillColors.primary
        case .assistant:
            return QuillColors.card
        case .system:
            return QuillColors.system
        }
    }

    private var labelColor: Color {
        message.role == .user ? QuillColors.selectedMuted : QuillColors.muted
    }

    private var textColor: Color {
        message.role == .user ? .white : QuillColors.ink
    }

    private var editingBorderColor: Color {
        message.role == .user ? .white : QuillColors.primary
    }

    private var accessibilitySummary: String {
        "\(label)\n\(message.content)"
    }
}

enum QuillColors {
    static var canvas: Color { Color(hex: EnchantedPalette.canvasColor) }
    static var sidebar: Color { Color(hex: EnchantedPalette.sidebarColor) }
    static var header: Color { Color(hex: EnchantedPalette.headerColor) }
    static var card: Color { Color(hex: EnchantedPalette.cardColor) }
    static var primary: Color { Color(hex: EnchantedPalette.primaryColor) }
    static var success: Color { Color(hex: EnchantedPalette.successColor) }
    static var warning: Color { Color(hex: EnchantedPalette.warningColor) }
    static var system: Color { Color(hex: EnchantedPalette.systemColor) }
    static var ink: Color { Color(hex: EnchantedPalette.inkColor) }
    static var muted: Color { Color(hex: EnchantedPalette.mutedColor) }
    static var selectedMuted: Color { Color(hex: EnchantedPalette.selectedMutedColor) }
    static var quoteRule: Color { Color(hex: EnchantedPalette.quoteRuleColor) }
    static var codeBlock: Color { Color(hex: EnchantedPalette.codeBlockColor) }
    static var dropTarget: Color { Color(hex: EnchantedPalette.dropTargetColor) }
}

private struct AttachmentChip: View {
    var attachment: PendingImageAttachment
    var remove: () -> Void

    var body: some View {
        HStack(spacing: CGFloat(EnchantedVisualMetrics.attachmentChipSpacing)) {
            Image(systemName: enchantedSystemImageName(EnchantedIcon.attachment))
                .foregroundColor(QuillColors.primary)

            VStack(alignment: .leading, spacing: CGFloat(EnchantedVisualMetrics.attachmentChipTextSpacing)) {
                Text(attachment.filename)
                    .font(.system(size: CGFloat(EnchantedTypography.attachmentNameFontSize)))
                    .foregroundColor(QuillColors.ink)
                    .lineLimit(1)
                Text(attachment.formattedByteCount)
                    .font(.system(size: CGFloat(EnchantedTypography.attachmentSizeFontSize)))
                    .foregroundColor(QuillColors.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(attachment.filename)
            .accessibilityValue(attachment.formattedByteCount)
            .help(accessibilitySummary)

            Button(action: remove) {
                Image(systemName: enchantedSystemImageName(EnchantedIcon.removeAttachment))
                    .foregroundColor(QuillColors.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(EnchantedCopy.removeAttachmentTooltip)
            .help(EnchantedCopy.removeAttachmentTooltip)
        }
        .padding(CGFloat(EnchantedVisualMetrics.attachmentChipPadding))
        .background(QuillColors.card)
        .cornerRadius(CGFloat(EnchantedVisualMetrics.attachmentChipRadius))
    }

    private var accessibilitySummary: String {
        "\(attachment.filename)\n\(attachment.formattedByteCount)"
    }
}
