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

    @State private var message = ""
    @State private var editMessage: MessageSD?
    @FocusState private var isFocusedInput: Bool

    private var modelMenuActions: [QuillMenuAction] {
        if modelsList.isEmpty {
            return [
                QuillMenuAction(title: "No models available", isDisabled: true) {}
            ]
        }

        return modelsList.map { model in
            let title = model.prettyVersion.isEmpty ? model.prettyName : "\(model.prettyName) \(model.prettyVersion)"
            let icon = selectedModel?.name == model.name ? "checkmark" : nil
            return QuillMenuAction(id: model.name, title: title, systemImage: icon) {
                onSelectModel(model)
            }
        }
    }

    private var optionsMenuActions: [QuillMenuAction] {
        [
            QuillMenuAction(title: "Copy Chat", systemImage: "doc.on.doc") {
                copyChat(false)
            },
            QuillMenuAction(title: "Copy Chat as JSON", systemImage: "curlybraces") {
                copyChat(true)
            }
        ]
    }

    var body: some View {
        QuillDesktopChatScaffold(
            title: "Enchanted",
            sidebarWidth: 320,
            composerWidth: 800,
            hasSelection: selectedConversation != nil,
            showsStatus: !reachable
        ) {
            SidebarView(
                selectedConversation: selectedConversation,
                conversations: conversations,
                onConversationTap: onConversationTap,
                onConversationDelete: onConversationDelete,
                onDeleteDailyConversations: onDeleteDailyConversations,
                onNewConversationTap: onNewConversationTap
            )
        } toolbar: {
            QuillDesktopChatToolbar(
                modelActions: modelMenuActions,
                optionsActions: optionsMenuActions,
                onNewConversation: onNewConversationTap
            )
        } selectedContent: {
            MessageListView(
                messages: messages,
                conversationState: conversationState,
                userInitials: userInitials,
                editMessage: $editMessage
            )
        } emptyContent: {
            EmptyConversaitonView(sendPrompt: sendPrompt)
        } statusContent: {
            UnreachableAPIView()
        } composer: {
            InputFieldsView(
                message: $message,
                conversationState: conversationState,
                onStopGenerateTap: onStopGenerateTap,
                selectedModel: selectedModel,
                onSendMessageTap: onSendMessageTap,
                editMessage: $editMessage
            )
        }
        .onChange(of: editMessage, initial: false) { _, newMessage in
            if let newMessage = newMessage {
                message = newMessage.content
                isFocusedInput = true
            }
        }
    }

    private func sendPrompt(_ selectedMessage: String) {
        if let selectedModel = selectedModel {
            onSendMessageTap(selectedMessage, selectedModel, nil, nil)
        }
    }
}
#endif
