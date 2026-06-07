//
//  Chat.swift
//  Enchanted
//

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

    private var modelMenuActions: [QuillMenuAction] {
        QuillMenuAction.selectableModels(
            modelsList,
            selectedID: selectedModel?.name,
            id: { $0.name },
            name: { $0.prettyName },
            version: { $0.prettyVersion },
            onSelect: onSelectModel
        )
    }

    private var optionsMenuActions: [QuillMenuAction] {
        QuillMenuAction.copyChatActions(copy: copyChat)
    }

    var body: some View {
        QuillEditableDesktopChatScaffold(
            title: "Enchanted",
            hasSelection: selectedConversation != nil,
            showsStatus: !reachable,
            modelActions: modelMenuActions,
            optionsActions: optionsMenuActions,
            onNewConversation: onNewConversationTap,
            editContent: { (message: MessageSD) in message.content }
        ) {
            SidebarView(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onConversationTap: onConversationTap,
                onConversationDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations
            )
        } selectedContent: { editMessage in
            MessageListView(
                messages: messages,
                conversationState: conversationState,
                userInitials: userInitials,
                editMessage: editMessage
            )
        } emptyContent: {
            QuillSelectedPromptEmptyState(
                brandTitle: "Quill",
                source: SamplePrompts.samples,
                id: { $0.id },
                title: { $0.prompt },
                systemImage: { $0.type.icon },
                sendPrompt: QuillPrompt.selectedModelSender(
                    selectedModel: selectedModel,
                    onSend: onSendMessageTap
                )
            )
        } statusContent: {
            QuillChatUnreachableBanner {
                Settings()
            }
            .frame(maxWidth: 1524)
        } composer: { message, editMessage in
            InputFieldsView(
                message: message,
                conversationState: conversationState,
                onStopGenerateTap: onStopGenerateTap,
                selectedModel: selectedModel,
                onSendMessageTap: onSendMessageTap,
                editMessage: editMessage
            )
        }
    }
}
#endif
