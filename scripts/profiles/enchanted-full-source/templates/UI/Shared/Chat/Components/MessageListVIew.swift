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

    func onReadAloud(_ message: String) {
        Task {
            await speechSynthesizer.speak(text: message)
        }
    }

    func stopReadingAloud() {
        Task {
            await speechSynthesizer.stopSpeaking()
        }
    }

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
        var actions = [
            QuillMenuAction.copyText(message.content)
        ]

#if os(iOS) || os(visionOS)
        actions.append(QuillMenuAction(title: "Select Text", systemImage: "selection.pin.in.out") {
            messageSelected = message
        })
        actions.append(QuillMenuAction(title: "Read Aloud", systemImage: "speaker.wave.3.fill") {
            onReadAloud(message.content)
        })
#endif

        if message.role == "user" {
            actions.append(.edit {
                withAnimation { editMessage = message }
            })
        }

        if editMessage?.id == message.id {
            actions.append(.unselect {
                withAnimation { editMessage = nil }
            })
        }

        return actions
    }
}
