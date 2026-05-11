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
/// file only owns the fixture model + the split-view glue.
@MainActor
public struct QuillSignalContentView: View {
    @State private var conversations = QuillSignalFixtures.conversations
    @State private var selectedID: Conversation.ID? = QuillSignalFixtures.conversations.first?.id

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quill Signal")
                .font(.title2).bold()
                .padding(14)

            List {
                ForEach(conversations) { conversation in
                    Button {
                        selectedID = conversation.id
                    } label: {
                        ChatRow(
                            title: conversation.name,
                            preview: conversation.messages.last?.body ?? ""
                        )
                    }
                }
            }
        }
    }

    private var detail: some View {
        Group {
            if let conversation = currentConversation {
                ChatTimeline(title: conversation.name, messages: conversation.messages)
            } else {
                Text("Select a conversation")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var currentConversation: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first(where: { $0.id == selectedID })
    }
}

// MARK: - Fixture model

public struct Message: ChatMessage {
    public let id: UUID
    public let sender: String
    public let body: String
    public let fromSelf: Bool

    public init(id: UUID = UUID(), sender: String, body: String, fromSelf: Bool) {
        self.id = id
        self.sender = sender
        self.body = body
        self.fromSelf = fromSelf
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
