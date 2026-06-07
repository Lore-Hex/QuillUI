import SwiftUI

#if (os(macOS) || os(Linux))
import AppKit
import QuillUI
#endif

struct MessageListView: View {
    var messages: [MessageSD]
    var conversationState: ConversationState
    var userInitials: String
    @Binding var editMessage: MessageSD?
    @State private var messageSelected: MessageSD?
    @StateObject private var speechSynthesizer = SpeechSynthesizer.shared

    func onReadAloud(_ message: String) { Task { await speechSynthesizer.speak(text: message) } }

    func stopReadingAloud() { Task { await speechSynthesizer.stopSpeaking() } }

    var body: some View {
        QuillMessageList(
            messages: messages,
            scrollToken: messages.quillMessageListScrollToken(content: \.content),
            actions: contextMenuActions
        ) { message in
            ChatMessageView(
                message: message,
                showLoader: conversationState == .loading && messages.last == message,
                userInitials: userInitials,
                editMessage: $editMessage
            )
            .runningBorder(animated: message.id == editMessage?.id)
        } overlay: {
            ReadingAloudView(onStopTap: stopReadingAloud)
                .frame(maxWidth: 400)
                .showIf(speechSynthesizer.isSpeaking)
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)),
                    removal: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)))
                )
        }
#if os(iOS) || os(visionOS)
        .sheet(item: $messageSelected) { message in
            SelectTextSheet(message: message)
        }
#endif
    }

    private func contextMenuActions(for message: MessageSD) -> [QuillMenuAction] {
#if os(iOS) || os(visionOS)
        let selectTextAction: (() -> Void)? = { messageSelected = message }
        let readAloudAction: (() -> Void)? = { onReadAloud(message.content) }
#else
        let selectTextAction: (() -> Void)? = nil
        let readAloudAction: (() -> Void)? = nil
#endif

        return QuillMenuAction.chatMessageActions(
            content: message.content,
            isUserMessage: message.role == "user",
            isEditing: editMessage?.id == message.id,
            selectText: selectTextAction,
            readAloud: readAloudAction,
            onEdit: {
                withAnimation { editMessage = message }
            },
            onUnselect: {
                withAnimation { editMessage = nil }
            }
        )
    }
}
