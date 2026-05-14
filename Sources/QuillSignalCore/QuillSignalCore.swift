import Foundation
import QuillUI
import QuillChatKit

/// Quill Signal fixtures-only conversation shell.
///
/// Upstream `signalapp/Signal-iOS` is a UIKit + libsignal /
/// RingRTC / GRDB stack that isn't SwiftPM-friendly. The
/// chat-app shape (sidebar of conversations + message timeline
/// + composer) is reproducible against a tiny local fixture
/// model and proves the QuillUI compat layer carries Signal's
/// view idioms even before the encrypted-storage and protocol
/// work lands.
///
/// Each `Conversation` owns a stable array of `Message`s. Selecting
/// a sidebar row updates the right-pane timeline. Bubble +
/// sidebar-row + timeline chrome lives in `QuillChatKit`; this
/// file only owns the fixture model and send path.
@MainActor
public struct QuillSignalContentView: View {
    @State private var conversations = QuillSignalFixtures.conversations
    @State private var selectedID: Conversation.ID? = QuillSignalFixtures.conversations.first?.id
    @State private var draft = ""

    public init() {}

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            ChatSplitShell(
                title: "Quill Signal",
                threads: conversations,
                selectedID: $selectedID,
                draft: $draft,
                placeholder: "Select a conversation",
                onSend: send
            )
        }
    }

    private func send() {
        ChatDraft.sendMessage(
            from: &draft,
            toID: selectedID,
            in: &conversations
        ) { body in
            Message(sender: "Me", body: body, fromSelf: true)
        }
    }
}

// MARK: - Fixture model

public struct Message: ChatMessage {
    public let id: UUID
    public let sender: String
    public let body: String
    public let fromSelf: Bool
    public let timestamp: Date?

    public init(
        id: UUID = UUID(),
        sender: String,
        body: String,
        fromSelf: Bool,
        timestamp: Date? = Date()
    ) {
        self.id = id
        self.sender = sender
        self.body = body
        self.fromSelf = fromSelf
        self.timestamp = timestamp
    }
}

public struct Conversation: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var messages: [Message]

    public init(id: UUID = UUID(), name: String, messages: [Message]) {
        self.id = id
        self.name = name
        self.messages = messages
    }
}

extension Conversation: ChatThread {
    public var title: String { name }
    public var preview: String { messages.last?.body ?? "" }
}

public enum QuillSignalFixtures {
    public static let conversations: [Conversation] = [
        Conversation(
            name: "Family",
            messages: [
                Message(sender: "Mom", body: "Don't forget Sunday dinner.", fromSelf: false),
                Message(sender: "Me", body: "I'll bring dessert.", fromSelf: true),
                Message(sender: "Mom", body: "❤️", fromSelf: false),
            ]
        ),
        Conversation(
            name: "Coworker",
            messages: [
                Message(sender: "Jamie", body: "PR ready for review.", fromSelf: false),
                Message(sender: "Me", body: "Looking now.", fromSelf: true),
            ]
        ),
        Conversation(
            name: "Notes To Self",
            messages: [
                Message(sender: "Me", body: "Pick up groceries on the way home.", fromSelf: true),
            ]
        ),
    ]
}
