import Foundation
import QuillEnchantedData
import QuillFoundation

public struct EnchantedConversationCopyPayload: Equatable, Sendable {
    public struct Message: Codable, Equatable, Hashable, Sendable {
        private enum CodingKeys: String, CodingKey {
            case role
            case content
        }

        public var role: String
        public var content: String

        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }

        public init(_ message: ChatMessage) {
            self.init(role: message.role.rawValue, content: message.content)
        }
    }

    public var messages: [Message]

    public init(messages: [Message]) {
        self.messages = messages
    }

    public init(chatMessages: [ChatMessage]) {
        self.init(messages: chatMessages.map(Message.init))
    }

    public var isEmpty: Bool {
        messages.isEmpty
    }

    public func plainTextString() -> String {
        messages
            .map { "\($0.role.capitalized): \($0.content)" }
            .joined(separator: "\n\n")
    }

    public func jsonString() throws -> String {
        // JSONEncoder does not preserve key order on Linux corelibs-foundation
        // (it emitted "content" before "role"), so assemble each object manually
        // to guarantee genuine Enchanted's role-then-content order. Each value is
        // still encoded via JSONEncoder for correct string escaping.
        func encoded(_ value: String) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        }
        let objects = try messages.map { message in
            "{\"role\":\(try encoded(message.role)),\"content\":\(try encoded(message.content))}"
        }
        return "[\(objects.joined(separator: ","))]"
    }

    public func string(json: Bool) throws -> String {
        if json {
            return try jsonString()
        }
        return plainTextString()
    }
}

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
        ),
        EnchantedPrompt(title: "Give me phrases to learn in a new language", kind: .action),
        EnchantedPrompt(title: "Act like Mowgli from The Jungle Book and answer questions", kind: .action),
        EnchantedPrompt(title: "What's unique about Go programming language?", kind: .question),
        EnchantedPrompt(title: "Give 10 gift ideas for best friend", kind: .action),
        EnchantedPrompt(
            title: "What are the largest cities in USA in population? Give a table",
            kind: .question
        ),
        EnchantedPrompt(title: "Give me ideas about New Years resolutions", kind: .action),
        EnchantedPrompt(title: "What is bubble sort? Write example in python", kind: .question)
    ]

    public static let emptyConversationVisiblePromptCount = 4
    public static let visibleEmptyConversationPrompts = Array(emptyConversationPrompts.prefix(emptyConversationVisiblePromptCount))
    public static let emptyConversationTitles = emptyConversationPrompts.map(\.title)

    public static func systemImage(forTitle title: String) -> String {
        emptyConversationPrompts.first { $0.title == title }?.systemImage ?? actionIconName
    }
}

public enum EnchantedIcon {
    public static let newConversation = "square.and.pencil"
    public static let attach = "folder.badge.plus"
    public static let dropTarget = "photo"
    public static let attachment = "folder"
    public static let completions = "textformat.abc"
    public static let shortcuts = "keyboard.fill"
    public static let settings = "gearshape.fill"
    public static let refreshModels = "arrow.clockwise"
    public static let deleteChat = "trash"
    public static let clearAll = "trash"
    public static let copyMessage = "doc.on.doc"
    public static let editMessage = "pencil"
    public static let imagePreviewFallback = "photo.fill"
    public static let unavailableModel = "waveform"
    public static let send = "arrow.forward.circle.fill"
    public static let stop = "square.fill"
    public static let removeAttachment = "xmark.circle.fill"
    public static let appearance = "sun.max"
}

public enum EnchantedCopy {
    public static let windowTitle = "Enchanted"
    public static let appTitle = "Enchanted"
    public static let sidebarSubtitle = "Local AI conversations"
    public static let newChatTitle = "New chat"
    public static let quillSectionTitle = "Quill"
    public static let endpointLabel = "Quill API endpoint"
    public static let systemPromptLabel = "System prompt"
    public static let bearerTokenLabel = "Bearer Token"
    public static let pingIntervalLabel = "Ping Interval (seconds)"
    public static let appSectionTitle = "APP"
    public static let appearanceLabel = "Appearance"
    public static let appearanceSystemOption = "System"
    public static let appearanceLightOption = "Light"
    public static let appearanceDarkOption = "Dark"
    public static let initialsLabel = "Initials"
    public static let defaultUserInitials = "Q"
    public static let defaultEndpoint = "http://localhost:11434"
    public static let modelLabel = "Model"
    public static let noModelsTitle = "No models detected"
    public static let chooseLocalModelStatus = "Choose a local model to begin"
    public static let usingModelStatusPrefix = "Using"
    public static let usingModelStatusSeparator = " "

    public static func usingModel(_ modelName: String) -> String {
        "\(usingModelStatusPrefix)\(usingModelStatusSeparator)\(modelName)"
    }

    public static let conversationsTitle = "Conversations"
    public static let deleteChatTitle = "Delete chat"
    public static let deleteDailyConversationsTitle = "Delete daily conversations"
    public static let todayTitle = "Today"
    public static let yesterdayTitle = "Yesterday"
    public static let daysAgoSuffix = "days ago"
    public static let clearAllTitle = "Clear All Data"
    public static let deleteAllConversationsConfirmationTitle = "Delete All Conversations?"
    public static let deleteAllConversationsConfirmTitle = "Delete"
    public static let cancelTitle = "Cancel"
    public static let copyChatTitle = "Copy Chat"
    public static let copyChatAsJSONTitle = "Copy Chat as JSON"
    public static let copyMessageTitle = "Copy"
    public static let editMessageTitle = "Edit"
    public static let unselectMessageTitle = "Unselect"
    public static let refreshModelsTitle = "Refresh models"
    public static let completionsTitle = "Completions"
    public static let shortcutsTitle = "Shortcuts"
    public static let settingsTitle = "Settings"
    public static let completionsStatus = completionsTitle
    public static let shortcutsStatus = shortcutsTitle
    public static let settingsStatus = settingsTitle
    public static let completionsPanelSubtitle = "Prompt completions use the shared Enchanted profile."
    public static let shortcutsPanelSubtitle = "Keyboard shortcuts use the shared QuillKit shortcut surface."
    public static let settingsPanelSubtitle = "Refresh models, choose a local model, or clear history from this sidebar."
    public static let dropTargetTitle = "Drop your image here"
    public static let attachmentPlaceholder = "Image path or drop files here"
    public static let attachTitle = "Attach"
    public static let clearAttachmentsTitle = "Clear"
    public static let attachmentsTitle = "Attachments"
    public static let readyStatus = "Ready"
    public static let attachmentsClearedStatus = "Attachments cleared"
    public static let attachmentRemovedEmptyStatus = readyStatus
    public static let removeAttachmentTooltip = "Remove attachment"
    public static let attachmentDefaultPrompt = "Describe this image."
    public static let attachmentDefaultPromptPlural = "Describe these images."
    public static let attachmentSummaryTitle = "[Attached images]"
    public static let unsupportedAttachmentSuffix = " is not a supported image attachment."
    public static let unreadableAttachmentPrefix = "Could not read image attachment at "
    public static let unreadableAttachmentSuffix = "."
    public static let oversizedAttachmentMiddle = " is too large to attach ("
    public static let oversizedAttachmentSuffix = ")."
    public static let composerPlaceholder = "Message"
    public static let sendTitle = "Send"
    public static let stopTitle = "Stop"
    public static let emptyHistoryTitle = "No saved chats yet"
    public static let emptyHistorySubtitle = "Start a chat and it will be saved locally."
    public static let emptyStateTitle = appTitle
    public static let emptyStateSubtitle = ""
    public static let userRoleLabel = "You"
    public static let assistantRoleLabel = "Enchanted"
    public static let systemRoleLabel = "System"
    public static let newConversationTitle = "New conversation"
    public static let noMessagesYet = "No messages yet"
    public static let systemLaunchMessage = "You are chatting with a local Ollama model in Enchanted."
    public static let readyForLocalInferenceStatus = "Ready for local inference"
    public static let checkingOllamaStatus = "Checking Ollama..."
    public static let unreachableOllamaMessage = "Ollama is unreachable. Go to Settings and update your Ollama API endpoint. "
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

    public static func unsupportedAttachmentStatus(_ name: String) -> String {
        "\(name)\(unsupportedAttachmentSuffix)"
    }

    public static func unreadableAttachmentStatus(_ path: String) -> String {
        "\(unreadableAttachmentPrefix)\(path)\(unreadableAttachmentSuffix)"
    }

    public static func oversizedAttachmentStatus(_ name: String, formattedByteCount: String) -> String {
        "\(name)\(oversizedAttachmentMiddle)\(formattedByteCount)\(oversizedAttachmentSuffix)"
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

public enum EnchantedAppearance: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system:
            return EnchantedCopy.appearanceSystemOption
        case .light:
            return EnchantedCopy.appearanceLightOption
        case .dark:
            return EnchantedCopy.appearanceDarkOption
        }
    }
}

public struct EnchantedConversationDayGroup: Identifiable, Hashable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var conversations: [ConversationSummary]

    public init(date: Date, conversations: [ConversationSummary]) {
        self.date = date
        self.conversations = conversations
    }
}

public enum EnchantedConversationHistory {
    public static func groups(
        conversations: [ConversationSummary],
        calendar: Calendar = .current
    ) -> [EnchantedConversationDayGroup] {
        Dictionary(grouping: conversations) { conversation in
            calendar.startOfDay(for: conversation.updatedAt)
        }
        .map { date, conversations in
            EnchantedConversationDayGroup(date: date, conversations: conversations)
        }
        .sorted { $0.date > $1.date }
    }

    public static func relativeDayTitle(
        for date: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let day = calendar.startOfDay(for: date)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let daysAgo = calendar.dateComponents([.day], from: day, to: referenceDay).day ?? 0

        switch daysAgo {
        case ...0:
            return EnchantedCopy.todayTitle
        case 1:
            return EnchantedCopy.yesterdayTitle
        default:
            return "\(daysAgo) \(EnchantedCopy.daysAgoSuffix)"
        }
    }
}

public enum EnchantedAssistantResponseFinalizer {
    public static func finalContent(from ollamaResponse: String) -> String {
        ollamaResponse.isEmpty ? EnchantedCopy.emptyOllamaResponse : ollamaResponse
    }
}

public enum EnchantedSettingsStorage {
    public static let endpointKey = "quill.enchanted.ollamaEndpoint"
    public static let systemPromptKey = "quill.enchanted.systemPrompt"
    public static let bearerTokenKey = "quill.enchanted.ollamaBearerToken"
    public static let pingIntervalKey = "quill.enchanted.pingInterval"
    public static let appearanceKey = "quill.enchanted.colorScheme"
    public static let userInitialsKey = "quill.enchanted.appUserInitials"

    public static let defaultSystemPrompt = ""
    public static let defaultBearerToken = ""
    public static let defaultPingInterval = "5"
    public static let defaultAppearance = EnchantedAppearance.system
    public static let defaultUserInitials = EnchantedCopy.defaultUserInitials
}

public struct EnchantedSettingsSnapshot: Equatable, Sendable {
    public var endpoint: String
    public var systemPrompt: String
    public var bearerToken: String
    public var pingInterval: String
    public var appearance: EnchantedAppearance
    public var userInitials: String

    public init(
        endpoint: String = EnchantedCopy.defaultEndpoint,
        systemPrompt: String = EnchantedSettingsStorage.defaultSystemPrompt,
        bearerToken: String = EnchantedSettingsStorage.defaultBearerToken,
        pingInterval: String = EnchantedSettingsStorage.defaultPingInterval,
        appearance: EnchantedAppearance = EnchantedSettingsStorage.defaultAppearance,
        userInitials: String = EnchantedSettingsStorage.defaultUserInitials
    ) {
        self.endpoint = endpoint
        self.systemPrompt = systemPrompt
        self.bearerToken = bearerToken
        self.pingInterval = pingInterval
        self.appearance = appearance
        self.userInitials = userInitials
    }

    public static func load(from defaults: UserDefaults = .standard) -> EnchantedSettingsSnapshot {
        EnchantedSettingsSnapshot(
            endpoint: defaults.string(forKey: EnchantedSettingsStorage.endpointKey) ?? EnchantedCopy.defaultEndpoint,
            systemPrompt: defaults.string(forKey: EnchantedSettingsStorage.systemPromptKey)
                ?? EnchantedSettingsStorage.defaultSystemPrompt,
            bearerToken: defaults.string(forKey: EnchantedSettingsStorage.bearerTokenKey)
                ?? EnchantedSettingsStorage.defaultBearerToken,
            pingInterval: defaults.string(forKey: EnchantedSettingsStorage.pingIntervalKey)
                ?? EnchantedSettingsStorage.defaultPingInterval,
            appearance: defaults.string(forKey: EnchantedSettingsStorage.appearanceKey)
                .flatMap(EnchantedAppearance.init(rawValue:))
                ?? EnchantedSettingsStorage.defaultAppearance,
            userInitials: defaults.string(forKey: EnchantedSettingsStorage.userInitialsKey)
                ?? EnchantedSettingsStorage.defaultUserInitials
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(endpoint, forKey: EnchantedSettingsStorage.endpointKey)
        defaults.set(systemPrompt, forKey: EnchantedSettingsStorage.systemPromptKey)
        defaults.set(bearerToken, forKey: EnchantedSettingsStorage.bearerTokenKey)
        defaults.set(pingInterval, forKey: EnchantedSettingsStorage.pingIntervalKey)
        defaults.set(appearance.rawValue, forKey: EnchantedSettingsStorage.appearanceKey)
        defaults.set(userInitials, forKey: EnchantedSettingsStorage.userInitialsKey)
    }
}

public enum EnchantedPingInterval {
    public static let defaultSeconds: TimeInterval = 5

    public static func seconds(from rawValue: String) -> TimeInterval {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = TimeInterval(trimmed), seconds.isFinite else {
            return defaultSeconds
        }
        return seconds > 0 ? seconds : .infinity
    }

    public static func refreshDelayNanoseconds(from rawValue: String) -> UInt64? {
        let seconds = seconds(from: rawValue)
        guard seconds.isFinite else { return nil }
        let maxSeconds = TimeInterval(UInt64.max) / 1_000_000_000
        guard seconds < maxSeconds else { return UInt64.max }
        return max(UInt64((seconds * 1_000_000_000).rounded(.toNearestOrAwayFromZero)), 1)
    }
}

public enum EnchantedPreviewFixture {
    public struct Message: Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var role: String
        public var content: String

        public init(id: String, role: String, content: String) {
            self.id = id
            self.role = role
            self.content = content
        }
    }

    public struct Conversation: Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var lastMessage: String
        public var messages: [Message]

        public init(id: String, title: String, lastMessage: String, messages: [Message]) {
            self.id = id
            self.title = title
            self.lastMessage = lastMessage
            self.messages = messages
        }
    }

    public static let selectedModel = "llama3.1:8b"
    public static let selectedConversationID = "daily-brief"
    public static let models = [
        "llama3.1:8b",
        "mistral:7b",
        "qwen2.5-coder:7b"
    ]

    public static let launchConversationMessages = [
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

    public static let localModelConversationMessages = [
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

    public static let attachmentConversationMessages = [
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

    public static let conversations = [
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
    ]

    public static let messages = launchConversationMessages
}

/// Backend-neutral startup selection policy for Enchanted conversation lists.
///
/// The SwiftUI/GTK app shell, Qt native runtime, and upstream-shaped slice all
/// need the same deterministic row-selection behavior during Linux smoke tests.
/// Keeping this in the shared Enchanted layer prevents each backend from
/// reimplementing environment parsing, ordering, and clamp rules.
public enum EnchantedInitialSelection {
    public static let selectedConversationIndexEnvironmentKeys = [
        "QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START",
        "QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"
    ]

    public static func selectedConversationIndex(
        count: Int,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int? {
        guard count > 0,
              let requestedIndex = QuillInitialSelection.index(
                environmentKeys: selectedConversationIndexEnvironmentKeys,
                environment: environment
              )
        else { return nil }

        return min(max(requestedIndex, 0), count - 1)
    }

    public static func selectedConversationID<Item: Identifiable>(
        in items: [Item],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Item.ID? {
        QuillInitialSelection.selectedID(
            in: items,
            environmentKeys: selectedConversationIndexEnvironmentKeys,
            environment: environment
        )
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
    public static let messageUserBubbleColor = "#007AFF"
    public static let messageAssistantBubbleColor = "#F6F6F6"
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
    public static let systemPromptEditorMinHeight = 100
    public static let statusRowSpacing = 8
    public static let statusTextWidth = 240
    public static let statusDotSize = 9
    public static let statusDotRadius = 9
    public static let headerTitleWidth = 560
    public static let headerHeight = 102
    public static let headerSpacing = 12
    public static let headerTitleSpacing = 4
    public static let headerPadding = 18
    public static let contentPadding = 22
    public static let loadingRowSpacing = 8
    public static let loadingTopPadding = 8
    public static let loadingSpinnerSize = 16
    public static let promptButtonWidth = 620
    public static let promptButtonMinHeight = 48
    public static let emptyStateMaxWidth = 760
    public static let emptyStatePadding = 26
    public static let emptyStateSpacing = 18
    public static let emptyStateHeaderSpacing = 8
    public static let promptListSpacing = 10
    // Genuine native Enchanted empty state: a single HORIZONTAL ROW of 4 narrow
    // prompt cards (text top-left, "?" icon bottom-right). cardWidth < 400 selects
    // QuillPromptGrid's narrow card layout; the cards fill their flexible columns.
    public static let promptGridColumns = 4
    public static let promptGridSpacing = 15
    public static let promptCardWidth = 160
    public static let promptCardHeight = 128
    public static let promptGridWidth = promptCardWidth * promptGridColumns + promptGridSpacing * (promptGridColumns - 1)
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
    // Genuine native Enchanted shows the selected conversation with a small leading
    // dot (ConversationHistoryListView uses a ~6pt Circle), not a filled row. We use 8
    // so the dot stays robustly detectable by the cross-backend screenshot gate.
    public static let conversationSelectionDotSize = 8
    public static let conversationDayGroupSpacing = 17
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
    public static let messageBubbleHorizontalPadding = 12
    public static let messageBubbleVerticalPadding = 8
    public static let messageBubbleSpacing = 7
    public static let messageBubbleRadius = 16
    public static let messageEditBorderWidth = 2
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
    public static let composerMaxWidth = 800
    public static let composerPadding = 18
    public static let composerSpacing = 10
    // Genuine native composer is a short, fully-rounded pill (single line at
    // rest, growing to composerMaxHeight while typing). radius == minHeight/2.
    public static let composerEditorRadius = 23
    public static let promptRowSpacing = 12
    public static let composerSendButtonMinWidth = 86
    public static let composerMinHeight = 46
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
    // Genuine native Enchanted empty-state wordmark: a large, THIN-weight
    // gradient title centered above the prompt row. Genuine renders it as
    // Font.system(size: 46, weight: .thin) (EmptyConversaitonView.swift). Size
    // 46 + weight 100 (→ .thin via enchantedFontWeight) match that exactly;
    // the prior 52/500 read as a heavier .regular.
    public static let emptyStateWordmarkFontSize = 46
    public static let emptyStateWordmarkFontWeight = 100
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
    public static let conversationDayHeaderFontSize = 14
    public static let conversationDayHeaderFontWeight = 650
    public static let conversationPreviewFontSize = 12
    public static let warningTextFontSize = 12
    public static let chipRemoveButtonFontWeight = 700
}
