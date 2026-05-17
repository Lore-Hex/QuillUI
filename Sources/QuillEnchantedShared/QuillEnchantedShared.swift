import Foundation

public struct EnchantedPrompt: Codable, Equatable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case title
        case kind
        case systemImage
    }

    public enum Kind: String, Codable, Equatable, Hashable, Sendable {
        case question
        case action

        public var systemImage: String {
            switch self {
            case .question:
                return "questionmark.circle"
            case .action:
                return "lightbulb.circle"
            }
        }

        public init(systemImage: String) {
            let normalized = systemImage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.contains("questionmark") {
                self = .question
            } else {
                self = .action
            }
        }
    }

    public var title: String
    public var kind: Kind
    public var systemImage: String

    public init(title: String, kind: Kind) {
        self.init(title: title, kind: kind, systemImage: kind.systemImage)
    }

    public init(title: String, systemImage: String) {
        self.init(title: title, kind: Kind(systemImage: systemImage), systemImage: systemImage)
    }

    private init(title: String, kind: Kind, systemImage: String) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decode(String.self, forKey: .title)

        if let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) {
            let systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? kind.systemImage
            self.init(title: title, kind: kind, systemImage: systemImage)
        } else {
            let systemImage = try container.decodeIfPresent(String.self, forKey: .systemImage) ?? Kind.action.systemImage
            self.init(title: title, systemImage: systemImage)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
        try container.encode(systemImage, forKey: .systemImage)
    }
}

public enum EnchantedPromptCatalog {
    public static let questionIconName = EnchantedPrompt.Kind.question.systemImage
    public static let actionIconName = EnchantedPrompt.Kind.action.systemImage

    public static let emptyConversationPrompts = [
        EnchantedPrompt(title: "How to center div in HTML?", kind: .question),
        EnchantedPrompt(title: "How to do personal taxes in USA?", kind: .question),
        EnchantedPrompt(title: "Explain supercomputers like I'm five years old", kind: .action),
        EnchantedPrompt(
            title: "Write a text message asking a friend to be my plus-one at a wedding",
            kind: .action
        )
    ]

    public static let emptyConversationTitles = emptyConversationPrompts.map(\.title)

    public static func systemImage(forTitle title: String) -> String {
        emptyConversationPrompts.first { $0.title == title }?.systemImage ?? actionIconName
    }
}

public enum EnchantedCopy {
    public static let windowTitle = "Quill Enchanted"
    public static let appTitle = "Enchanted"
    public static let sidebarSubtitle = "QuillUI Linux preview"
    public static let newChatTitle = "New chat"
    public static let endpointLabel = "Ollama endpoint"
    public static let defaultEndpoint = "http://localhost:11434"
    public static let modelLabel = "Model"
    public static let noModelsTitle = "No models detected"
    public static let chooseLocalModelStatus = "Choose a local model to begin"
    public static let usingModelStatusPrefix = "Using"

    public static func usingModel(_ modelName: String) -> String {
        "\(usingModelStatusPrefix) \(modelName)"
    }

    public static let conversationsTitle = "Conversations"
    public static let deleteChatTitle = "Delete chat"
    public static let clearAllTitle = "Clear all"
    public static let refreshModelsTitle = "Refresh models"
    public static let completionsTitle = "Completions"
    public static let shortcutsTitle = "Shortcuts"
    public static let settingsTitle = "Settings"
    public static let completionsPanelSubtitle = "Prompt completions use the shared Enchanted profile."
    public static let shortcutsPanelSubtitle = "Keyboard shortcuts use the shared QuillKit shortcut surface."
    public static let settingsPanelSubtitle = "Refresh models, choose a local model, or clear history from this sidebar."
    public static let dropTargetTitle = "Drop image files to attach"
    public static let attachmentPlaceholder = "Image path or drop files here"
    public static let attachTitle = "Attach"
    public static let clearAttachmentsTitle = "Clear"
    public static let attachmentsTitle = "Attachments"
    public static let attachmentsClearedStatus = "Attachments cleared"
    public static let removeAttachmentTooltip = "Remove attachment"
    public static let attachmentDefaultPrompt = "Describe this image."
    public static let attachmentDefaultPromptPlural = "Describe these images."
    public static let attachmentSummaryTitle = "[Attached images]"
    public static let composerPlaceholder = "Ask a local model..."
    public static let sendTitle = "Send"
    public static let stopTitle = "Stop"
    public static let emptyHistoryTitle = "No saved chats yet"
    public static let emptyHistorySubtitle = "Start a chat and it will be saved locally."
    public static let emptyStateTitle = "Ask your local model"
    public static let emptyStateSubtitle = "This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history."
    public static let userRoleLabel = "You"
    public static let assistantRoleLabel = "Enchanted"
    public static let systemRoleLabel = "System"
    public static let newConversationTitle = "New conversation"
    public static let noMessagesYet = "No messages yet"
    public static let systemLaunchMessage = "You are chatting with a local Ollama model in Enchanted."
    public static let readyStatus = "Ready"
    public static let readyForLocalInferenceStatus = "Ready for local inference"
    public static let checkingOllamaStatus = "Checking Ollama..."
    public static let noOllamaModelsStatus = "No Ollama models found"
    public static let connectedStatus = "Connected"
    public static let startOllamaStatus = "Start Ollama or edit endpoint."
    public static let stoppingStatus = "Stopping..."
    public static let stoppedStatus = "Stopped"
    public static let conversationDeletedStatus = "Conversation deleted"
    public static let historyClearedStatus = "History cleared"
    public static let messageEmptyStatus = "Message is empty"
    public static let unsupportedActionStatus = "Unsupported action"
    public static let openingStreamStatus = "Opening stream..."
    public static let streamingResponseStatus = "Streaming response..."
    public static let emptyOllamaResponse = "(Ollama returned an empty response.)"
    public static let conversationPersistenceUnavailableStatus = "Conversation persistence is unavailable."
    public static let messageUnavailableStatus = "Message is no longer available."
    public static let conversationTrimmedStatus = "Conversation trimmed"
    public static let noConversationSelectedStatus = "No conversation selected"
    public static let imageReadyStatusSingular = "1 image ready to send"
    public static let imageReadyStatusPluralUnit = "images ready to send"

    public static func imageReadyStatus(count: Int) -> String {
        count == 1 ? imageReadyStatusSingular : "\(count) \(imageReadyStatusPluralUnit)"
    }

    public static func couldNotCreateConversationStatus(_ message: String) -> String {
        "Could not create conversation: \(message)"
    }

    public static func couldNotTrimConversationStatus(_ message: String) -> String {
        "Could not trim conversation: \(message)"
    }

    public static func couldNotDeleteConversationStatus(_ message: String) -> String {
        "Could not delete conversation: \(message)"
    }

    public static func couldNotClearHistoryStatus(_ message: String) -> String {
        "Could not clear history: \(message)"
    }

    public static func couldNotLoadConversationsStatus(_ message: String) -> String {
        "Could not load conversations: \(message)"
    }

    public static func couldNotLoadMessagesStatus(_ message: String) -> String {
        "Could not load messages: \(message)"
    }

    public static func couldNotUpdateHistoryStatus(_ message: String) -> String {
        "Could not update history: \(message)"
    }
}

public enum EnchantedPalette {
    public static let canvasColor = "#FBFBFD"
    public static let sidebarColor = "#F5F5F7"
    public static let sidebarSelectedColor = "#E8E8ED"
    public static let cardColor = "#FFFFFF"
    public static let cardQuietColor = "#F4F4F6"
    public static let hairlineColor = "#D8D8DE"
    public static let textColor = "#1D1D1F"
    public static let secondaryTextColor = "#6E6E73"
    public static let accentColor = "#4285F4"
    public static let destructiveColor = "#B42318"
    public static let successColor = "#34C759"
    public static let warningColor = "#FF9F0A"
    public static let dropTargetColor = "#EAF2FF"
    public static let selectedMutedColor = "#FFFFFF"
    public static let headerColor = EnchantedPalette.canvasColor
    public static let primaryColor = EnchantedPalette.accentColor
    public static let systemColor = EnchantedPalette.sidebarSelectedColor
    public static let inkColor = EnchantedPalette.textColor
    public static let mutedColor = EnchantedPalette.secondaryTextColor
    public static let quoteRuleColor = EnchantedPalette.hairlineColor
    public static let codeBlockColor = EnchantedPalette.cardQuietColor
    public static let dividerColor = EnchantedPalette.hairlineColor
    public static let cardBorderColor = EnchantedPalette.hairlineColor
    public static let messageBorderColor = EnchantedPalette.hairlineColor
    public static let controlBorderColor = EnchantedPalette.hairlineColor
    public static let dropTargetBorderColor = EnchantedPalette.accentColor
    public static let disabledButtonBackgroundColor = EnchantedPalette.hairlineColor
    public static let disabledButtonForegroundColor = EnchantedPalette.secondaryTextColor
    public static let disabledTextColor = EnchantedPalette.secondaryTextColor
}

public enum EnchantedVisualMetrics {
    public static let minimumWindowWidth = 980
    public static let minimumWindowHeight = 680
    public static let defaultWindowWidth = 1180
    public static let defaultWindowHeight = 760
    public static let sidebarWidth = 300
    public static let sidebarIdealWidth = 330
    public static let sidebarMaxWidth = 360
    public static let detailWidth = defaultWindowWidth - sidebarWidth
    public static let sidebarPadding = 18
    public static let sidebarSpacing = 14
    public static let sidebarTitleSpacing = 4
    public static let sidebarControlGroupSpacing = 7
    public static let statusRowSpacing = 8
    public static let statusTextWidth = 240
    public static let statusDotSize = 9
    public static let statusDotRadius = 9
    public static let headerTitleWidth = 560
    public static let headerSpacing = 12
    public static let headerTitleSpacing = 4
    public static let headerPadding = 18
    public static let contentPadding = 22
    public static let loadingRowSpacing = 8
    public static let loadingTopPadding = 8
    public static let loadingSpinnerSize = 16
    public static let promptButtonWidth = 620
    public static let promptButtonMinHeight = 48
    public static let emptyStateMaxWidth = 680
    public static let emptyStatePadding = 26
    public static let emptyStateSpacing = 18
    public static let emptyStateHeaderSpacing = 8
    public static let promptListSpacing = 10
    public static let promptButtonIconSpacing = 10
    public static let promptButtonTextWidthInset = 80
    public static let promptButtonPadding = 12
    public static let promptButtonRadius = 8
    public static let primaryButtonPadding = 12
    public static let primaryButtonIconSpacing = 8
    public static let primaryButtonVerticalPadding = primaryButtonPadding
    public static let primaryButtonHorizontalPadding = primaryButtonPadding
    public static let primaryButtonRadius = 8
    public static let actionButtonIconSpacing = 6
    public static let actionButtonIconSize = 16
    public static let secondaryButtonVerticalPadding = 7
    public static let secondaryButtonHorizontalPadding = 10
    public static let secondaryButtonRadius = 7
    public static let controlPadding = 7
    public static let controlRadius = 7
    public static let dropTargetPadding = 8
    public static let dropTargetRadius = 8
    public static let conversationListSpacing = 8
    public static let conversationActionsSpacing = 8
    public static let conversationRowPadding = 11
    public static let conversationRowSpacing = 5
    public static let conversationRowRadius = 8
    public static let conversationListItemRadius = 8
    public static let conversationListItemVerticalMargin = 2
    public static let conversationListItemPadding = 8
    public static let emptyHistoryPadding = 12
    public static let emptyHistorySpacing = 8
    public static let emptyHistoryRadius = 8
    public static let attachmentChipPadding = 8
    public static let attachmentChipSpacing = 8
    public static let attachmentChipTextSpacing = 2
    public static let attachmentChipRadius = 8
    public static let attachmentRemoveButtonWidth = 28
    public static let chipRemoveButtonVerticalPadding = 2
    public static let chipRemoveButtonHorizontalPadding = 6
    public static let attachmentTraySpacing = 7
    public static let attachmentTrayChipSpacing = 8
    public static let attachmentInputHorizontalPadding = 10
    public static let attachmentInputVerticalPadding = 7
    public static let attachmentInputSpacing = 8
    public static let messageMaxWidth = 680
    public static let messageSpacing = 14
    public static let messageBubbleRowSpacing = 10
    public static let messageBubblePadding = 13
    public static let messageBubbleSpacing = 7
    public static let messageBubbleRadius = 10
    public static let markdownBlockSpacing = 9
    public static let markdownListItemSpacing = 8
    public static let markdownNumberWidth = 26
    public static let markdownQuoteSpacing = 9
    public static let markdownQuoteRuleWidth = 3
    public static let markdownQuoteRuleRadius = 1
    public static let markdownQuoteVerticalPadding = 2
    public static let markdownCodeBlockSpacing = 7
    public static let markdownCodeBlockPadding = 10
    public static let markdownCodeBlockRadius = 7
    public static let composerMinWidth = 620
    public static let composerMaxWidth = 840
    public static let composerPadding = 18
    public static let composerSpacing = 10
    public static let composerEditorRadius = 8
    public static let promptRowSpacing = 12
    public static let composerSendButtonMinWidth = 86
    public static let composerMinHeight = 74
    public static let composerMaxHeight = 120
}

public enum EnchantedTypography {
    public static let rootFontSize = 14
    public static let appTitleFontSize = 26
    public static let appTitleFontWeight = 700
    public static let captionFontSize = 12
    public static let sectionTitleFontSize = 15
    public static let sectionTitleFontWeight = 700
    public static let currentTitleFontSize = 20
    public static let currentTitleFontWeight = 650
    public static let messageBodyFontSize = 14
    public static let markdownHeading1FontSize = 17
    public static let markdownHeading2FontSize = 15
    public static let markdownHeadingFontSize = 14
    public static let markdownHeadingFontWeight = 650
    public static let markdownCodeLanguageFontSize = 11
    public static let markdownCodeFontSize = 13
    public static let attachmentNameFontSize = 12
    public static let attachmentSizeFontSize = 11
    public static let conversationTitleFontSize = 15
    public static let conversationTitleFontWeight = 700
    public static let conversationPreviewFontSize = 12
    public static let warningTextFontSize = 12
    public static let chipRemoveButtonFontWeight = 700
}
