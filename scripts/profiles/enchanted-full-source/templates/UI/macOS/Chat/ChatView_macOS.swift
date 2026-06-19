#if os(macOS) || os(Linux) || os(visionOS)
import SwiftUI
import QuillUI

struct ChatView: View {
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var messages: [MessageSD]
    var modelsList: [LanguageModelSD]
    var onMenuTap: () -> Void
    var onNewConversationTap: () -> Void
    var onSendMessageTap: (_ prompt: String, _ model: LanguageModelSD, _ image: Image?, _ trimmingMessageId: String?) -> Void
    var onConversationTap: (_ conversation: ConversationSD) -> Void
    var conversationState: ConversationState
    var onStopGenerateTap: () -> Void
    var reachable: Bool
    var modelSupportsImages: Bool
    var selectedModel: LanguageModelSD?
    var onSelectModel: (_ model: LanguageModelSD?) -> Void
    var onConversationDelete: (_ conversation: ConversationSD) -> Void
    var onDeleteDailyConversations: (_ date: Date) -> Void
    var userInitials: String
    var copyChat: (_ json: Bool) -> Void
    @State private var copySource = QuillChatCopySource<MessageSD>()

    var body: some View {
        let _ = copySource.update(messages)
        QuillModelConversationChatScaffold(
            title: "Enchanted",
            conversations: conversations,
            selectedConversationID: selectedConversation?.id.uuidString,
            models: modelsList,
            selectedModelID: selectedModel?.name,
            promptSource: SamplePrompts.samples,
            reachable: reachable,
            settingsFocusedValue: \.showSettings,
            onNewConversation: onNewConversationTap,
            editContent: \.content,
            conversationID: { $0.id.uuidString },
            conversationTitle: \.name,
            conversationUpdatedAt: \.updatedAt,
            conversationDateTitle: { $0.daysAgoString() },
            onSettings: { Task { Haptics.shared.mediumTap() } },
            onSelectConversation: onConversationTap,
            onDeleteConversation: onConversationDelete,
            onDeleteDailyConversations: onDeleteDailyConversations,
            modelID: \.name,
            modelName: \.prettyName,
            modelVersion: \.prettyVersion,
            onSelectModel: { onSelectModel($0) },
            copyChat: copyVisibleChat,
            promptID: \.id,
            promptTitle: \.prompt,
            promptSystemImage: { $0.type.icon },
            sendPrompt: QuillPrompt.selectedModelSender(
                selectedModel: selectedModel,
                onSend: onSendMessageTap
            )
        ) { editMessage in
            MessageListView(
                messages: messages,
                conversationState: conversationState,
                userInitials: userInitials,
                editMessage: editMessage
            )
        } composer: { message, editMessage in
            InputFieldsView(
                message: message,
                conversationState: conversationState,
                onStopGenerateTap: onStopGenerateTap,
                selectedModel: selectedModel,
                onSendMessageTap: onSendMessageTap,
                editMessage: editMessage
            )
        } settings: {
            Settings()
        } completions: {
            CompletionsEditor()
        } shortcuts: {
            KeyboardShortcutsDemo()
        }
    }

    private func copyVisibleChat(_ json: Bool) {
        copySource.copy(asJSON: json, role: \.role, content: \.content, fallback: copyChat)
    }
}
#endif
