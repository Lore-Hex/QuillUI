#if os(Linux)
import CQuillQt6WidgetsShim
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
    var newChatTitle: String
    var deleteChatTitle: String
    var clearAllTitle: String
    var refreshModelsTitle: String
    var attachmentPlaceholder: String
    var attachTitle: String
    var clearAttachmentsTitle: String
    var attachmentsTitle: String
    var attachmentDefaultPrompt: String
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
    }

    struct Message: Codable, Sendable {
        var id: String
        var role: String
        var content: String
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
        var sidebarWidth: Int
        var headerPadding: Int
        var contentPadding: Int
        var composerHeight: Int
        var messageMaxWidth: Int
    }

    private static let launchConversationMessages = [
        Message(
            id: "system-1",
            role: "system",
            content: "You are chatting with a local Ollama model in Enchanted."
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
        windowTitle: "Quill Enchanted",
        minimumWidth: 980,
        minimumHeight: 680,
        defaultWidth: 1180,
        defaultHeight: 760,
        sidebarTitle: "Enchanted",
        sidebarSubtitle: "QuillUI Linux preview",
        endpointLabel: "Ollama endpoint",
        modelLabel: "Model",
        conversationsTitle: "Conversations",
        noModelsTitle: "No models detected",
        newChatTitle: "New chat",
        deleteChatTitle: "Delete chat",
        clearAllTitle: "Clear all",
        refreshModelsTitle: "Refresh models",
        attachmentPlaceholder: "Image path or drop files here",
        attachTitle: "Attach",
        clearAttachmentsTitle: "Clear",
        attachmentsTitle: "Attachments",
        attachmentDefaultPrompt: "Describe this image.",
        attachmentSummaryTitle: "[Attached images]",
        composerPlaceholder: "Ask a local model...",
        sendTitle: "Send",
        stopTitle: "Stop",
        stoppingStatus: "Stopping...",
        status: "Ready for local inference",
        isLoading: false,
        emptyHistoryTitle: "No saved chats yet",
        emptyHistorySubtitle: "Start a chat and it will be saved locally.",
        emptyStateTitle: "Ask your local model",
        emptyStateSubtitle: "This is the first QuillUI Enchanted checkpoint: local Swift UI, Ollama chat, and QuillData history.",
        endpoint: "http://localhost:11434",
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
            canvasColor: "#F6F7F2",
            sidebarColor: "#EEF1EA",
            headerColor: "#FBFCF7",
            cardColor: "#FFFFFF",
            primaryColor: "#315B7D",
            successColor: "#2F8F64",
            warningColor: "#B86A31",
            systemColor: "#E8EDF3",
            inkColor: "#172026",
            mutedColor: "#6C747C",
            selectedMutedColor: "#DDEBFA",
            quoteRuleColor: "#8AA5B7",
            codeBlockColor: "#EEF3F4",
            dropTargetColor: "#E1F0EA",
            sidebarWidth: 300,
            headerPadding: 18,
            contentPadding: 22,
            composerHeight: 84,
            messageMaxWidth: 680
        )
    )
}

public enum QuillEnchantedQtNativeApp {
    private static let selectedConversationIndexEnvironmentKeys = [
        "QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START",
        "QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"
    ]

    private static func launchSnapshot() -> QuillEnchantedQtSnapshot {
        var snapshot = QuillEnchantedQtSnapshot.preview
        guard let boundedIndex = selectedConversationIndexOverride(count: snapshot.conversations.count) else {
            return snapshot
        }

        snapshot.selectedConversationID = snapshot.conversations[boundedIndex].id
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
                payloadPointer
            )
        }
    }
}
#endif
