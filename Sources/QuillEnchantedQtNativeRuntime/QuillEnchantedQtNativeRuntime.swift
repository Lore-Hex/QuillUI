#if os(Linux)
import CQuillQt6WidgetsShim
import Dispatch
import Foundation
import Glibc
import QuillEnchantedData
import QuillEnchantedShared
import QuillQtNativeRuntimeSupport

struct QuillEnchantedQtSnapshot: Codable, Sendable {
    var windowTitle: String
    var minimumWidth: Int
    var minimumHeight: Int
    var defaultWidth: Int
    var defaultHeight: Int
    var sidebarTitle: String
    var sidebarSubtitle: String
    var endpointLabel: String
    var modelLabel: String
    var conversationsTitle: String
    var noModelsTitle: String
    var chooseLocalModelStatus: String
    var usingModelStatusPrefix: String
    var newChatTitle: String
    var newConversationTitle: String
    var noMessagesYet: String
    var deleteChatTitle: String
    var clearAllTitle: String
    var refreshModelsTitle: String
    var completionsTitle: String
    var shortcutsTitle: String
    var settingsTitle: String
    var completionsStatus: String
    var shortcutsStatus: String
    var settingsStatus: String
    var completionsPanelSubtitle: String
    var shortcutsPanelSubtitle: String
    var settingsPanelSubtitle: String
    var dropTargetTitle: String
    var attachmentPlaceholder: String
    var attachTitle: String
    var clearAttachmentsTitle: String
    var attachmentsClearedStatus: String
    var attachmentRemovedEmptyStatus: String
    var removeAttachmentTooltip: String
    var imageReadyStatusSingular: String
    var imageReadyStatusPluralUnit: String
    var attachmentsTitle: String
    var attachmentDefaultPrompt: String
    var attachmentDefaultPromptPlural: String
    var attachmentSummaryTitle: String
    var composerPlaceholder: String
    var sendTitle: String
    var stopTitle: String
    var stoppingStatus: String
    var status: String
    var isLoading: Bool
    var emptyHistoryTitle: String
    var emptyHistorySubtitle: String
    var emptyStateTitle: String
    var emptyStateSubtitle: String
    var userRoleLabel: String
    var assistantRoleLabel: String
    var systemRoleLabel: String
    var endpoint: String
    var selectedModel: String
    var selectedConversationID: String
    var models: [String]
    var conversations: [Conversation]
    var messages: [Message]
    var prompts: [String]
    var style: Style

    struct Conversation: Codable, Sendable {
        var id: String
        var title: String
        var lastMessage: String
        var messages: [Message]? = nil

        init(id: String, title: String, lastMessage: String, messages: [Message]? = nil) {
            self.id = id
            self.title = title
            self.lastMessage = lastMessage
            self.messages = messages
        }

        init(summary: ConversationSummary, messages: [Message]) {
            self.id = summary.id
            self.title = summary.title
            self.lastMessage = summary.lastMessage.isEmpty ? EnchantedCopy.noMessagesYet : summary.lastMessage
            self.messages = messages
        }
    }

    struct Message: Codable, Sendable {
        var id: String
        var role: String
        var content: String

        init(id: String, role: String, content: String) {
            self.id = id
            self.role = role
            self.content = content
        }

        init(_ message: ChatMessage) {
            self.id = message.id
            self.role = message.role.rawValue
            self.content = message.content
        }
    }

    struct Style: Codable, Sendable {
        var canvasColor: String
        var sidebarColor: String
        var headerColor: String
        var cardColor: String
        var primaryColor: String
        var successColor: String
        var warningColor: String
        var systemColor: String
        var inkColor: String
        var mutedColor: String
        var selectedMutedColor: String
        var quoteRuleColor: String
        var codeBlockColor: String
        var dropTargetColor: String
        var dividerColor: String
        var cardBorderColor: String
        var messageBorderColor: String
        var controlBorderColor: String
        var dropTargetBorderColor: String
        var disabledButtonBackgroundColor: String
        var disabledButtonForegroundColor: String
        var disabledTextColor: String
        var rootFontSize: Int
        var appTitleFontSize: Int
        var appTitleFontWeight: Int
        var captionFontSize: Int
        var sectionTitleFontSize: Int
        var sectionTitleFontWeight: Int
        var currentTitleFontSize: Int
        var currentTitleFontWeight: Int
        var messageBodyFontSize: Int
        var markdownHeading1FontSize: Int
        var markdownHeading2FontSize: Int
        var markdownHeadingFontSize: Int
        var markdownHeadingFontWeight: Int
        var markdownCodeLanguageFontSize: Int
        var markdownCodeFontSize: Int
        var attachmentNameFontSize: Int
        var attachmentSizeFontSize: Int
        var conversationTitleFontSize: Int
        var conversationTitleFontWeight: Int
        var conversationPreviewFontSize: Int
        var warningTextFontSize: Int
        var chipRemoveButtonFontWeight: Int
        var sidebarWidth: Int
        var sidebarPadding: Int
        var sidebarSpacing: Int
        var sidebarTitleSpacing: Int
        var sidebarControlGroupSpacing: Int
        var statusRowSpacing: Int
        var statusTextWidth: Int
        var statusDotSize: Int
        var statusDotRadius: Int
        var conversationListSpacing: Int
        var conversationRowPadding: Int
        var conversationRowSpacing: Int
        var conversationRowRadius: Int
        var conversationListItemRadius: Int
        var conversationListItemVerticalMargin: Int
        var conversationListItemPadding: Int
        var conversationActionsSpacing: Int
        var attachmentChipPadding: Int
        var attachmentChipSpacing: Int
        var attachmentChipTextSpacing: Int
        var attachmentChipRadius: Int
        var attachmentRemoveButtonWidth: Int
        var attachmentTraySpacing: Int
        var attachmentTrayChipSpacing: Int
        var attachmentInputSpacing: Int
        var headerTitleWidth: Int
        var headerSpacing: Int
        var headerTitleSpacing: Int
        var headerPadding: Int
        var contentPadding: Int
        var loadingRowSpacing: Int
        var loadingTopPadding: Int
        var loadingSpinnerSize: Int
        var messageSpacing: Int
        var messageBubbleRowSpacing: Int
        var messageBubblePadding: Int
        var messageBubbleSpacing: Int
        var messageBubbleRadius: Int
        var markdownBlockSpacing: Int
        var markdownListItemSpacing: Int
        var markdownNumberWidth: Int
        var markdownQuoteSpacing: Int
        var markdownQuoteRuleWidth: Int
        var markdownQuoteRuleRadius: Int
        var markdownQuoteVerticalPadding: Int
        var markdownCodeBlockSpacing: Int
        var markdownCodeBlockPadding: Int
        var markdownCodeBlockRadius: Int
        var emptyHistoryPadding: Int
        var emptyHistorySpacing: Int
        var emptyHistoryRadius: Int
        var emptyStatePadding: Int
        var emptyStateSpacing: Int
        var emptyStateHeaderSpacing: Int
        var emptyStateMaxWidth: Int
        var promptListSpacing: Int
        var promptButtonIconSpacing: Int
        var promptButtonTextWidthInset: Int
        var promptButtonMinHeight: Int
        var promptButtonWidth: Int
        var promptButtonPadding: Int
        var promptButtonRadius: Int
        var primaryButtonVerticalPadding: Int
        var primaryButtonHorizontalPadding: Int
        var primaryButtonRadius: Int
        var actionButtonIconSize: Int
        var secondaryButtonVerticalPadding: Int
        var secondaryButtonHorizontalPadding: Int
        var secondaryButtonRadius: Int
        var chipRemoveButtonVerticalPadding: Int
        var chipRemoveButtonHorizontalPadding: Int
        var controlPadding: Int
        var controlRadius: Int
        var dropTargetPadding: Int
        var dropTargetRadius: Int
        var composerPadding: Int
        var composerSpacing: Int
        var composerEditorRadius: Int
        var promptRowSpacing: Int
        var composerSendButtonMinWidth: Int
        var composerMinWidth: Int
        var composerMaxWidth: Int
        var composerMinHeight: Int
        var composerMaxHeight: Int
        var messageMaxWidth: Int
    }

    private static let launchConversationMessages = [
        Message(
            id: "system-1",
            role: "system",
            content: EnchantedCopy.systemLaunchMessage
        ),
        Message(
            id: "user-1",
            role: "user",
            content: "Turn my meeting notes into a short launch checklist."
        ),
        Message(
            id: "assistant-1",
            role: "assistant",
            content: "Confirm the owner, send the revised timeline, collect final screenshots, and ask design for approval before Friday."
        )
    ]

    private static let localModelConversationMessages = [
        Message(
            id: "local-user-1",
            role: "user",
            content: "What should I check before switching models for a longer draft?"
        ),
        Message(
            id: "local-assistant-1",
            role: "assistant",
            content: "Keep the endpoint reachable, choose the model with the right context window, and run a short prompt before pasting the full draft."
        )
    ]

    private static let attachmentConversationMessages = [
        Message(
            id: "attachment-user-1",
            role: "user",
            content: "Can you help turn this screenshot into release-note copy?"
        ),
        Message(
            id: "attachment-assistant-1",
            role: "assistant",
            content: "Use a concise caption, mention what changed, and keep the note focused on the user-facing setup flow."
        )
    ]

    static let preview = QuillEnchantedQtSnapshot(
        windowTitle: EnchantedCopy.windowTitle,
        minimumWidth: EnchantedVisualMetrics.minimumWindowWidth,
        minimumHeight: EnchantedVisualMetrics.minimumWindowHeight,
        defaultWidth: EnchantedVisualMetrics.defaultWindowWidth,
        defaultHeight: EnchantedVisualMetrics.defaultWindowHeight,
        sidebarTitle: EnchantedCopy.appTitle,
        sidebarSubtitle: EnchantedCopy.sidebarSubtitle,
        endpointLabel: EnchantedCopy.endpointLabel,
        modelLabel: EnchantedCopy.modelLabel,
        conversationsTitle: EnchantedCopy.conversationsTitle,
        noModelsTitle: EnchantedCopy.noModelsTitle,
        chooseLocalModelStatus: EnchantedCopy.chooseLocalModelStatus,
        usingModelStatusPrefix: EnchantedCopy.usingModelStatusPrefix,
        newChatTitle: EnchantedCopy.newChatTitle,
        newConversationTitle: EnchantedCopy.newConversationTitle,
        noMessagesYet: EnchantedCopy.noMessagesYet,
        deleteChatTitle: EnchantedCopy.deleteChatTitle,
        clearAllTitle: EnchantedCopy.clearAllTitle,
        refreshModelsTitle: EnchantedCopy.refreshModelsTitle,
        completionsTitle: EnchantedCopy.completionsTitle,
        shortcutsTitle: EnchantedCopy.shortcutsTitle,
        settingsTitle: EnchantedCopy.settingsTitle,
        completionsStatus: EnchantedCopy.completionsTitle,
        shortcutsStatus: EnchantedCopy.shortcutsTitle,
        settingsStatus: EnchantedCopy.settingsTitle,
        completionsPanelSubtitle: EnchantedCopy.completionsPanelSubtitle,
        shortcutsPanelSubtitle: EnchantedCopy.shortcutsPanelSubtitle,
        settingsPanelSubtitle: EnchantedCopy.settingsPanelSubtitle,
        dropTargetTitle: EnchantedCopy.dropTargetTitle,
        attachmentPlaceholder: EnchantedCopy.attachmentPlaceholder,
        attachTitle: EnchantedCopy.attachTitle,
        clearAttachmentsTitle: EnchantedCopy.clearAttachmentsTitle,
        attachmentsClearedStatus: EnchantedCopy.attachmentsClearedStatus,
        attachmentRemovedEmptyStatus: EnchantedCopy.readyStatus,
        removeAttachmentTooltip: EnchantedCopy.removeAttachmentTooltip,
        imageReadyStatusSingular: EnchantedCopy.imageReadyStatusSingular,
        imageReadyStatusPluralUnit: EnchantedCopy.imageReadyStatusPluralUnit,
        attachmentsTitle: EnchantedCopy.attachmentsTitle,
        attachmentDefaultPrompt: EnchantedCopy.attachmentDefaultPrompt,
        attachmentDefaultPromptPlural: EnchantedCopy.attachmentDefaultPromptPlural,
        attachmentSummaryTitle: EnchantedCopy.attachmentSummaryTitle,
        composerPlaceholder: EnchantedCopy.composerPlaceholder,
        sendTitle: EnchantedCopy.sendTitle,
        stopTitle: EnchantedCopy.stopTitle,
        stoppingStatus: EnchantedCopy.stoppingStatus,
        status: EnchantedCopy.readyForLocalInferenceStatus,
        isLoading: false,
        emptyHistoryTitle: EnchantedCopy.emptyHistoryTitle,
        emptyHistorySubtitle: EnchantedCopy.emptyHistorySubtitle,
        emptyStateTitle: EnchantedCopy.emptyStateTitle,
        emptyStateSubtitle: EnchantedCopy.emptyStateSubtitle,
        userRoleLabel: EnchantedCopy.userRoleLabel,
        assistantRoleLabel: EnchantedCopy.assistantRoleLabel,
        systemRoleLabel: EnchantedCopy.systemRoleLabel,
        endpoint: EnchantedCopy.defaultEndpoint,
        selectedModel: "llama3.1:8b",
        selectedConversationID: "daily-brief",
        models: [
            "llama3.1:8b",
            "mistral:7b",
            "qwen2.5-coder:7b"
        ],
        conversations: [
            Conversation(
                id: "daily-brief",
                title: "Launch checklist",
                lastMessage: "Four next steps before Friday.",
                messages: launchConversationMessages
            ),
            Conversation(
                id: "local-models",
                title: "Local model setup",
                lastMessage: "Pick the right model before drafting.",
                messages: localModelConversationMessages
            ),
            Conversation(
                id: "attachments",
                title: "Image attachment flow",
                lastMessage: "Turn a screenshot into release-note copy.",
                messages: attachmentConversationMessages
            )
        ],
        messages: launchConversationMessages,
        prompts: EnchantedPromptCatalog.emptyConversationTitles,
        style: Style(
            canvasColor: EnchantedPalette.canvasColor,
            sidebarColor: EnchantedPalette.sidebarColor,
            headerColor: EnchantedPalette.headerColor,
            cardColor: EnchantedPalette.cardColor,
            primaryColor: EnchantedPalette.primaryColor,
            successColor: EnchantedPalette.successColor,
            warningColor: EnchantedPalette.warningColor,
            systemColor: EnchantedPalette.systemColor,
            inkColor: EnchantedPalette.inkColor,
            mutedColor: EnchantedPalette.mutedColor,
            selectedMutedColor: EnchantedPalette.selectedMutedColor,
            quoteRuleColor: EnchantedPalette.quoteRuleColor,
            codeBlockColor: EnchantedPalette.codeBlockColor,
            dropTargetColor: EnchantedPalette.dropTargetColor,
            dividerColor: EnchantedPalette.dividerColor,
            cardBorderColor: EnchantedPalette.cardBorderColor,
            messageBorderColor: EnchantedPalette.messageBorderColor,
            controlBorderColor: EnchantedPalette.controlBorderColor,
            dropTargetBorderColor: EnchantedPalette.dropTargetBorderColor,
            disabledButtonBackgroundColor: EnchantedPalette.disabledButtonBackgroundColor,
            disabledButtonForegroundColor: EnchantedPalette.disabledButtonForegroundColor,
            disabledTextColor: EnchantedPalette.disabledTextColor,
            rootFontSize: EnchantedTypography.rootFontSize,
            appTitleFontSize: EnchantedTypography.appTitleFontSize,
            appTitleFontWeight: EnchantedTypography.appTitleFontWeight,
            captionFontSize: EnchantedTypography.captionFontSize,
            sectionTitleFontSize: EnchantedTypography.sectionTitleFontSize,
            sectionTitleFontWeight: EnchantedTypography.sectionTitleFontWeight,
            currentTitleFontSize: EnchantedTypography.currentTitleFontSize,
            currentTitleFontWeight: EnchantedTypography.currentTitleFontWeight,
            messageBodyFontSize: EnchantedTypography.messageBodyFontSize,
            markdownHeading1FontSize: EnchantedTypography.markdownHeading1FontSize,
            markdownHeading2FontSize: EnchantedTypography.markdownHeading2FontSize,
            markdownHeadingFontSize: EnchantedTypography.markdownHeadingFontSize,
            markdownHeadingFontWeight: EnchantedTypography.markdownHeadingFontWeight,
            markdownCodeLanguageFontSize: EnchantedTypography.markdownCodeLanguageFontSize,
            markdownCodeFontSize: EnchantedTypography.markdownCodeFontSize,
            attachmentNameFontSize: EnchantedTypography.attachmentNameFontSize,
            attachmentSizeFontSize: EnchantedTypography.attachmentSizeFontSize,
            conversationTitleFontSize: EnchantedTypography.conversationTitleFontSize,
            conversationTitleFontWeight: EnchantedTypography.conversationTitleFontWeight,
            conversationPreviewFontSize: EnchantedTypography.conversationPreviewFontSize,
            warningTextFontSize: EnchantedTypography.warningTextFontSize,
            chipRemoveButtonFontWeight: EnchantedTypography.chipRemoveButtonFontWeight,
            sidebarWidth: EnchantedVisualMetrics.sidebarWidth,
            sidebarPadding: EnchantedVisualMetrics.sidebarPadding,
            sidebarSpacing: EnchantedVisualMetrics.sidebarSpacing,
            sidebarTitleSpacing: EnchantedVisualMetrics.sidebarTitleSpacing,
            sidebarControlGroupSpacing: EnchantedVisualMetrics.sidebarControlGroupSpacing,
            statusRowSpacing: EnchantedVisualMetrics.statusRowSpacing,
            statusTextWidth: EnchantedVisualMetrics.statusTextWidth,
            statusDotSize: EnchantedVisualMetrics.statusDotSize,
            statusDotRadius: EnchantedVisualMetrics.statusDotRadius,
            conversationListSpacing: EnchantedVisualMetrics.conversationListSpacing,
            conversationRowPadding: EnchantedVisualMetrics.conversationRowPadding,
            conversationRowSpacing: EnchantedVisualMetrics.conversationRowSpacing,
            conversationRowRadius: EnchantedVisualMetrics.conversationRowRadius,
            conversationListItemRadius: EnchantedVisualMetrics.conversationListItemRadius,
            conversationListItemVerticalMargin: EnchantedVisualMetrics.conversationListItemVerticalMargin,
            conversationListItemPadding: EnchantedVisualMetrics.conversationListItemPadding,
            conversationActionsSpacing: EnchantedVisualMetrics.conversationActionsSpacing,
            attachmentChipPadding: EnchantedVisualMetrics.attachmentChipPadding,
            attachmentChipSpacing: EnchantedVisualMetrics.attachmentChipSpacing,
            attachmentChipTextSpacing: EnchantedVisualMetrics.attachmentChipTextSpacing,
            attachmentChipRadius: EnchantedVisualMetrics.attachmentChipRadius,
            attachmentRemoveButtonWidth: EnchantedVisualMetrics.attachmentRemoveButtonWidth,
            attachmentTraySpacing: EnchantedVisualMetrics.attachmentTraySpacing,
            attachmentTrayChipSpacing: EnchantedVisualMetrics.attachmentTrayChipSpacing,
            attachmentInputSpacing: EnchantedVisualMetrics.attachmentInputSpacing,
            headerTitleWidth: EnchantedVisualMetrics.headerTitleWidth,
            headerSpacing: EnchantedVisualMetrics.headerSpacing,
            headerTitleSpacing: EnchantedVisualMetrics.headerTitleSpacing,
            headerPadding: EnchantedVisualMetrics.headerPadding,
            contentPadding: EnchantedVisualMetrics.contentPadding,
            loadingRowSpacing: EnchantedVisualMetrics.loadingRowSpacing,
            loadingTopPadding: EnchantedVisualMetrics.loadingTopPadding,
            loadingSpinnerSize: EnchantedVisualMetrics.loadingSpinnerSize,
            messageSpacing: EnchantedVisualMetrics.messageSpacing,
            messageBubbleRowSpacing: EnchantedVisualMetrics.messageBubbleRowSpacing,
            messageBubblePadding: EnchantedVisualMetrics.messageBubblePadding,
            messageBubbleSpacing: EnchantedVisualMetrics.messageBubbleSpacing,
            messageBubbleRadius: EnchantedVisualMetrics.messageBubbleRadius,
            markdownBlockSpacing: EnchantedVisualMetrics.markdownBlockSpacing,
            markdownListItemSpacing: EnchantedVisualMetrics.markdownListItemSpacing,
            markdownNumberWidth: EnchantedVisualMetrics.markdownNumberWidth,
            markdownQuoteSpacing: EnchantedVisualMetrics.markdownQuoteSpacing,
            markdownQuoteRuleWidth: EnchantedVisualMetrics.markdownQuoteRuleWidth,
            markdownQuoteRuleRadius: EnchantedVisualMetrics.markdownQuoteRuleRadius,
            markdownQuoteVerticalPadding: EnchantedVisualMetrics.markdownQuoteVerticalPadding,
            markdownCodeBlockSpacing: EnchantedVisualMetrics.markdownCodeBlockSpacing,
            markdownCodeBlockPadding: EnchantedVisualMetrics.markdownCodeBlockPadding,
            markdownCodeBlockRadius: EnchantedVisualMetrics.markdownCodeBlockRadius,
            emptyHistoryPadding: EnchantedVisualMetrics.emptyHistoryPadding,
            emptyHistorySpacing: EnchantedVisualMetrics.emptyHistorySpacing,
            emptyHistoryRadius: EnchantedVisualMetrics.emptyHistoryRadius,
            emptyStatePadding: EnchantedVisualMetrics.emptyStatePadding,
            emptyStateSpacing: EnchantedVisualMetrics.emptyStateSpacing,
            emptyStateHeaderSpacing: EnchantedVisualMetrics.emptyStateHeaderSpacing,
            emptyStateMaxWidth: EnchantedVisualMetrics.emptyStateMaxWidth,
            promptListSpacing: EnchantedVisualMetrics.promptListSpacing,
            promptButtonIconSpacing: EnchantedVisualMetrics.promptButtonIconSpacing,
            promptButtonTextWidthInset: EnchantedVisualMetrics.promptButtonTextWidthInset,
            promptButtonMinHeight: EnchantedVisualMetrics.promptButtonMinHeight,
            promptButtonWidth: EnchantedVisualMetrics.promptButtonWidth,
            promptButtonPadding: EnchantedVisualMetrics.promptButtonPadding,
            promptButtonRadius: EnchantedVisualMetrics.promptButtonRadius,
            primaryButtonVerticalPadding: EnchantedVisualMetrics.primaryButtonVerticalPadding,
            primaryButtonHorizontalPadding: EnchantedVisualMetrics.primaryButtonHorizontalPadding,
            primaryButtonRadius: EnchantedVisualMetrics.primaryButtonRadius,
            actionButtonIconSize: EnchantedVisualMetrics.actionButtonIconSize,
            secondaryButtonVerticalPadding: EnchantedVisualMetrics.secondaryButtonVerticalPadding,
            secondaryButtonHorizontalPadding: EnchantedVisualMetrics.secondaryButtonHorizontalPadding,
            secondaryButtonRadius: EnchantedVisualMetrics.secondaryButtonRadius,
            chipRemoveButtonVerticalPadding: EnchantedVisualMetrics.chipRemoveButtonVerticalPadding,
            chipRemoveButtonHorizontalPadding: EnchantedVisualMetrics.chipRemoveButtonHorizontalPadding,
            controlPadding: EnchantedVisualMetrics.controlPadding,
            controlRadius: EnchantedVisualMetrics.controlRadius,
            dropTargetPadding: EnchantedVisualMetrics.dropTargetPadding,
            dropTargetRadius: EnchantedVisualMetrics.dropTargetRadius,
            composerPadding: EnchantedVisualMetrics.composerPadding,
            composerSpacing: EnchantedVisualMetrics.composerSpacing,
            composerEditorRadius: EnchantedVisualMetrics.composerEditorRadius,
            promptRowSpacing: EnchantedVisualMetrics.promptRowSpacing,
            composerSendButtonMinWidth: EnchantedVisualMetrics.composerSendButtonMinWidth,
            composerMinWidth: EnchantedVisualMetrics.composerMinWidth,
            composerMaxWidth: EnchantedVisualMetrics.composerMaxWidth,
            composerMinHeight: EnchantedVisualMetrics.composerMinHeight,
            composerMaxHeight: EnchantedVisualMetrics.composerMaxHeight,
            messageMaxWidth: EnchantedVisualMetrics.messageMaxWidth
        )
    )

    static func persisted(
        context: EnchantedModelContext,
        selectedConversationID requestedSelectedConversationID: String? = nil,
        status: String = EnchantedCopy.readyStatus,
        endpoint: String = preview.endpoint,
        selectedModel requestedSelectedModel: String? = nil,
        models requestedModels: [String]? = nil
    ) throws -> QuillEnchantedQtSnapshot {
        var snapshot = preview
        snapshot.endpoint = endpoint
        if let requestedModels {
            snapshot.models = requestedModels
        }
        if let requestedSelectedModel {
            snapshot.selectedModel = requestedSelectedModel
        }
        if !snapshot.models.isEmpty, !snapshot.models.contains(snapshot.selectedModel) {
            snapshot.selectedModel = snapshot.models.first ?? ""
        }
        let summaries = try context.fetchConversations()
        snapshot.conversations = try summaries.map { summary in
            let messages = try context.fetchMessages(for: summary.id).map(Message.init)
            return Conversation(summary: summary, messages: messages)
        }
        snapshot.selectedConversationID = requestedSelectedConversationID.flatMap { requestedID in
            snapshot.conversations.contains { $0.id == requestedID } ? requestedID : nil
        } ?? snapshot.conversations.first?.id ?? ""
        snapshot.status = status
        snapshot.syncSelectedMessages()
        return snapshot
    }

    mutating func selectConversation(at index: Int) {
        guard conversations.indices.contains(index) else { return }
        selectedConversationID = conversations[index].id
        syncSelectedMessages()
    }

    private mutating func syncSelectedMessages() {
        guard
            let selectedConversation = conversations.first(where: { $0.id == selectedConversationID }),
            let selectedMessages = selectedConversation.messages
        else {
            messages = []
            return
        }

        messages = selectedMessages
    }
}

private struct QuillEnchantedQtActionRequest: Decodable {
    var action: String
    var conversationID: String?
    var messageText: String?
    var attachmentPaths: [String]?
    var endpoint: String?
    var selectedModel: String?
    var models: [String]?
}

private final class AsyncResultBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<Value, Error>? {
        lock.lock()
        let result = result
        lock.unlock()
        return result
    }
}

private enum QuillEnchantedQtActionBridge {
    static func snapshot(for actionJSON: String?) -> QuillEnchantedQtSnapshot {
        do {
            let context = try EnchantedModelContext.default()
            guard let actionJSON else {
                return try QuillEnchantedQtSnapshot.persisted(context: context)
            }

            let request = try JSONDecoder().decode(
                QuillEnchantedQtActionRequest.self,
                from: Data(actionJSON.utf8)
            )
            var selectedConversationID = try existingConversationID(request.conversationID, context: context)
            var status = EnchantedCopy.readyStatus
            let endpoint = request.endpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? QuillEnchantedQtSnapshot.preview.endpoint
            var selectedModel = request.selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
            var models = request.models ?? QuillEnchantedQtSnapshot.preview.models

            switch request.action {
            case "newConversation":
                let conversation = try context.insert(ConversationDraft(title: EnchantedCopy.newConversationTitle))
                selectedConversationID = conversation.id
                status = EnchantedCopy.newConversationTitle
            case "deleteConversation":
                guard let conversationID = request.conversationID, !conversationID.isEmpty else {
                    status = EnchantedCopy.noConversationSelectedStatus
                    break
                }
                try context.deleteConversation(id: conversationID)
                status = EnchantedCopy.conversationDeletedStatus
            case "deleteAllConversations":
                try context.deleteAllConversations()
                status = EnchantedCopy.historyClearedStatus
            case "sendMessage":
                let attachments = try imageAttachments(from: request.attachmentPaths ?? [])
                guard let messageText = request.messageText?.quillTrimmedNonEmpty
                    ?? (attachments.isEmpty ? nil : PendingImageAttachment.defaultPrompt(for: attachments))
                else {
                    selectedConversationID = try existingConversationID(request.conversationID, context: context)
                    status = EnchantedCopy.messageEmptyStatus
                    break
                }

                let sendResult = try sendMessage(
                    messageText,
                    attachments: attachments,
                    selectedConversationID: existingConversationID(request.conversationID, context: context),
                    endpoint: endpoint,
                    selectedModel: selectedModel?.quillTrimmedNonEmpty ?? models.first?.quillTrimmedNonEmpty ?? "",
                    context: context
                )
                selectedConversationID = sendResult.conversationID
                status = sendResult.status
            case "refreshModels", "configureEndpoint":
                let refresh = refreshModels(
                    endpoint: endpoint,
                    selectedModel: selectedModel
                )
                models = refresh.models
                selectedModel = refresh.selectedModel
                status = refresh.status
            case "selectModel":
                status = selectedModel?.isEmpty == false ? EnchantedCopy.readyStatus : EnchantedCopy.chooseLocalModelStatus
            default:
                status = EnchantedCopy.unsupportedActionStatus
            }

            return try QuillEnchantedQtSnapshot.persisted(
                context: context,
                selectedConversationID: selectedConversationID,
                status: status,
                endpoint: endpoint,
                selectedModel: selectedModel,
                models: models
            )
        } catch {
            var snapshot = QuillEnchantedQtSnapshot.preview
            snapshot.status = EnchantedCopy.couldNotUpdateHistoryStatus(error.localizedDescription)
            return snapshot
        }
    }

    private static func existingConversationID(
        _ requestedID: String?,
        context: EnchantedModelContext
    ) throws -> String? {
        guard let requestedID = requestedID?.quillTrimmedNonEmpty else { return nil }
        let conversations = try context.fetchConversations()
        return conversations.contains { $0.id == requestedID } ? requestedID : nil
    }

    private static func sendMessage(
        _ messageText: String,
        attachments: [PendingImageAttachment] = [],
        selectedConversationID: String?,
        endpoint: String,
        selectedModel: String,
        context: EnchantedModelContext
    ) throws -> (conversationID: String, status: String) {
        let prompt = messageText
        let encodedImages = try attachments.map { try $0.base64EncodedContent() }
        let conversationID: String
        if let selectedConversationID {
            let currentMessages = try context.fetchMessages(for: selectedConversationID)
            if currentMessages.isEmpty {
                try context.updateConversationTitle(id: selectedConversationID, title: prompt.quillTitle())
            }
            conversationID = selectedConversationID
        } else {
            let conversation = try context.insert(ConversationDraft(title: prompt.quillTitle()))
            conversationID = conversation.id
        }

        let displayContent = PendingImageAttachment.displayContent(prompt: prompt, attachments: attachments)
        try context.insert(ChatMessage(conversationID: conversationID, role: .user, content: displayContent))
        let requestMessages = try context.fetchMessages(for: conversationID)
        do {
            let assistantReply = try fetchOllamaChatResponse(
                endpoint: endpoint,
                selectedModel: selectedModel,
                messages: requestMessages,
                imagesForLastUserMessage: encodedImages
            )
            let finalContent = assistantReply.quillTrimmedNonEmpty ?? EnchantedCopy.emptyOllamaResponse
            try context.insert(ChatMessage(
                conversationID: conversationID,
                role: .assistant,
                content: finalContent
            ))
            return (conversationID, EnchantedCopy.readyStatus)
        } catch {
            return (conversationID, error.localizedDescription)
        }
    }

    private static func imageAttachments(from rawPaths: [String]) throws -> [PendingImageAttachment] {
        try rawPaths.compactMap { PendingImageAttachment.fileURL(from: $0) }
            .map { try PendingImageAttachment(fileURL: $0) }
    }

    private static func refreshModels(
        endpoint: String,
        selectedModel: String?
    ) -> (models: [String], selectedModel: String, status: String) {
        do {
            let fetchedModels = try fetchOllamaModels(endpoint: endpoint).map(\.name)
            let resolvedSelection = selectedModel.flatMap { fetchedModels.contains($0) ? $0 : nil }
                ?? fetchedModels.first
                ?? ""
            return (
                fetchedModels,
                resolvedSelection,
                fetchedModels.isEmpty ? EnchantedCopy.noOllamaModelsStatus : EnchantedCopy.connectedStatus
            )
        } catch {
            return ([], selectedModel ?? "", EnchantedCopy.startOllamaStatus)
        }
    }

    private static func fetchOllamaModels(endpoint: String) throws -> [OllamaModel] {
        try waitForAsync {
            try await OllamaClient(baseURL: endpoint).fetchModels()
        }
    }

    private static func fetchOllamaChatResponse(
        endpoint: String,
        selectedModel: String,
        messages: [ChatMessage],
        imagesForLastUserMessage: [String]
    ) throws -> String {
        try waitForAsync {
            try await OllamaClient(baseURL: endpoint).chat(
                model: selectedModel,
                messages: messages,
                imagesForLastUserMessage: imagesForLastUserMessage
            )
        }
    }

    private static func waitForAsync<Value: Sendable>(
        _ operation: @Sendable @escaping () async throws -> Value
    ) throws -> Value {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<Value>()

        Task.detached {
            let response: Result<Value, Error>
            do {
                response = .success(try await operation())
            } catch {
                response = .failure(error)
            }
            box.store(response)
            semaphore.signal()
        }

        semaphore.wait()
        guard let result = box.load() else {
            throw OllamaClientError.streamingUnavailable("Ollama request finished without a response.")
        }
        return try result.get()
    }
}

private func encodedSnapshotPointer(_ snapshot: QuillEnchantedQtSnapshot) -> UnsafeMutablePointer<CChar>? {
    do {
        let payload = try QuillQtNativeRuntimeSupport.encodedPayloadString(snapshot)
        return payload.withCString { strdup($0) }
    } catch {
        return nil
    }
}

@_cdecl("quill_enchanted_qt_perform_action_json")
public func quill_enchanted_qt_perform_action_json(
    _ actionPointer: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let snapshot = QuillEnchantedQtActionBridge.snapshot(
        for: actionPointer.map { String(cString: $0) }
    )
    return encodedSnapshotPointer(snapshot)
}

@_cdecl("quill_enchanted_qt_free_string")
public func quill_enchanted_qt_free_string(_ pointer: UnsafeMutablePointer<CChar>?) {
    if let pointer {
        free(UnsafeMutableRawPointer(pointer))
    }
}

public enum QuillEnchantedQtNativeApp {
    private static let selectedConversationIndexEnvironmentKeys = [
        "QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START",
        "QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"
    ]

    private static func launchSnapshot() -> QuillEnchantedQtSnapshot {
        var snapshot: QuillEnchantedQtSnapshot
        do {
            snapshot = try QuillEnchantedQtSnapshot.persisted(context: EnchantedModelContext.default())
        } catch {
            snapshot = QuillEnchantedQtSnapshot.preview
            snapshot.status = EnchantedCopy.conversationPersistenceUnavailableStatus
        }

        guard let boundedIndex = selectedConversationIndexOverride(count: snapshot.conversations.count) else {
            return snapshot
        }

        snapshot.selectConversation(at: boundedIndex)
        return snapshot
    }

    private static func selectedConversationIndexOverride(count: Int) -> Int? {
        QuillQtNativeRuntimeSupport.boundedIndexOverride(
            environmentKeys: selectedConversationIndexEnvironmentKeys,
            count: count
        )
    }

    public static func run() -> Never {
        QuillQtNativeRuntimeSupport.runEncodedPayload(
            launchSnapshot(),
            executableName: QuillQtNativeRuntimeSupport.executableName(fallback: "quill-enchanted-qt")
        ) { payloadPointer in
            quill_enchanted_qt_run_app_json(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                payloadPointer,
                quill_enchanted_qt_perform_action_json,
                quill_enchanted_qt_free_string
            )
        }
    }
}
#endif
