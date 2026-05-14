#if os(Linux)
import CQuillQt6WidgetsShim
import Foundation
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
    var newChatTitle: String
    var deleteChatTitle: String
    var clearAllTitle: String
    var refreshModelsTitle: String
    var attachmentPlaceholder: String
    var composerPlaceholder: String
    var sendTitle: String
    var status: String
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
        newChatTitle: "New chat",
        deleteChatTitle: "Delete chat",
        clearAllTitle: "Clear all",
        refreshModelsTitle: "Refresh models",
        attachmentPlaceholder: "Image path or drop files here",
        composerPlaceholder: "Ask a local model...",
        sendTitle: "Send",
        status: "Ready for local inference",
        endpoint: "http://localhost:11434",
        selectedModel: "llama3.1:8b",
        selectedConversationID: "parity-brief",
        models: [
            "llama3.1:8b",
            "mistral:7b",
            "qwen2.5-coder:7b"
        ],
        conversations: [
            Conversation(
                id: "parity-brief",
                title: "QuillUI backend parity",
                lastMessage: "Compare the GTK and Qt Enchanted shells."
            ),
            Conversation(
                id: "local-models",
                title: "Local model setup",
                lastMessage: "Keep endpoint and model controls visible."
            ),
            Conversation(
                id: "attachments",
                title: "Image attachment flow",
                lastMessage: "Preserve attachment affordances in native hosts."
            )
        ],
        messages: [
            Message(
                id: "system-1",
                role: "system",
                content: "You are chatting with a local Ollama model through QuillUI."
            ),
            Message(
                id: "user-1",
                role: "user",
                content: "Show the Enchanted layout that Qt needs to match."
            ),
            Message(
                id: "assistant-1",
                role: "assistant",
                content: "The Qt shell keeps the 300px sidebar, conversation list, model picker, transcript, attachment row, and composer controls aligned with the GTK preview."
            )
        ],
        prompts: [
            "Summarize the current conversation",
            "Explain this screenshot",
            "Draft a migration plan"
        ],
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
    private static let selectedConversationIndexEnvironmentKey = "QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START"

    private static func launchSnapshot() -> QuillEnchantedQtSnapshot {
        var snapshot = QuillEnchantedQtSnapshot.preview
        guard
            let rawValue = ProcessInfo.processInfo.environment[selectedConversationIndexEnvironmentKey],
            let requestedIndex = Int(rawValue),
            !snapshot.conversations.isEmpty
        else {
            return snapshot
        }

        let boundedIndex = min(max(requestedIndex, 0), snapshot.conversations.count - 1)
        snapshot.selectedConversationID = snapshot.conversations[boundedIndex].id
        return snapshot
    }

    public static func run() -> Never {
        QuillQtNativeRuntimeSupport.runEncodedPayload(
            launchSnapshot(),
            executableName: "quill-enchanted-qt"
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
