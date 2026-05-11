import Foundation
import QuillUI

/// Quill Telegram fixtures-only chat shell.
///
/// Upstream `Telegram-iOS` / `Telegram-Swift` is a massive
/// project with bespoke MTProto / TDLib / SwiftSignalKit
/// dependencies that aren't SwiftPM-friendly. The chat-app
/// shape (folder-grouped chat list + message timeline +
/// composer) is reproducible against a small local fixture
/// model — same approach Signal/IceCubes used before their
/// real backends landed.
///
/// Three folders ("All", "Personal", "Work") each carrying a
/// set of `Chat` rows; selecting a chat shows its message
/// timeline in the detail pane.
@MainActor
public struct QuillTelegramContentView: View {
    @State private var selectedFolder = "All"
    @State private var selectedChatID: Chat.ID? = QuillTelegramFixtures.chats.first?.id

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var folders: [String] { ["All", "Personal", "Work"] }

    private var visibleChats: [Chat] {
        if selectedFolder == "All" { return QuillTelegramFixtures.chats }
        return QuillTelegramFixtures.chats.filter { $0.folder == selectedFolder }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quill Telegram")
                .font(.title2).bold()
                .padding(14)

            // Folder pills
            HStack(spacing: 8) {
                ForEach(folders, id: \.self) { folder in
                    Button {
                        selectedFolder = folder
                    } label: {
                        Text(folder)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                folder == selectedFolder
                                    ? Color.blue.opacity(0.2)
                                    : Color.gray.opacity(0.12)
                            )
                            .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            List {
                ForEach(visibleChats) { chat in
                    Button {
                        selectedChatID = chat.id
                    } label: {
                        chatRow(chat)
                    }
                }
            }
        }
    }

    private func chatRow(_ chat: Chat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(chat.title).font(.headline).lineLimit(1)
                Spacer()
                if chat.unread > 0 {
                    Text("\(chat.unread)")
                        .font(.caption2).bold()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            Text(chat.messages.last?.body ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var detail: some View {
        Group {
            if let chat = currentChat {
                conversationView(chat)
            } else {
                Text("Select a chat")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func conversationView(_ chat: Chat) -> some View {
        VStack(spacing: 0) {
            Text(chat.title)
                .font(.title2).bold()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(chat.messages) { message in
                        messageBubble(message)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func messageBubble(_ message: TGMessage) -> some View {
        VStack(alignment: message.fromSelf ? .trailing : .leading, spacing: 2) {
            Text(message.body)
                .padding(10)
                .background(message.fromSelf ? Color.blue.opacity(0.18) : Color.gray.opacity(0.18))
                .cornerRadius(12)
            Text(message.sender)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: message.fromSelf ? .trailing : .leading)
    }

    private var currentChat: Chat? {
        guard let id = selectedChatID else { return nil }
        return visibleChats.first(where: { $0.id == id })
    }
}

// MARK: - Fixture model

public struct TGMessage: Identifiable, Hashable, Sendable {
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

public struct Chat: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var folder: String
    public var unread: Int
    public var messages: [TGMessage]

    public init(id: UUID = UUID(), title: String, folder: String, unread: Int, messages: [TGMessage]) {
        self.id = id
        self.title = title
        self.folder = folder
        self.unread = unread
        self.messages = messages
    }
}

public enum QuillTelegramFixtures {
    public static let chats: [Chat] = [
        Chat(title: "Family", folder: "Personal", unread: 0, messages: [
            TGMessage(sender: "Dad", body: "Are you coming to the BBQ?", fromSelf: false),
            TGMessage(sender: "Me", body: "On my way.", fromSelf: true),
        ]),
        Chat(title: "DevOps Channel", folder: "Work", unread: 3, messages: [
            TGMessage(sender: "@deploybot", body: "Build 4129 succeeded.", fromSelf: false),
            TGMessage(sender: "@deploybot", body: "Rollout to canary at 10%.", fromSelf: false),
            TGMessage(sender: "@deploybot", body: "Canary healthy after 30m.", fromSelf: false),
        ]),
        Chat(title: "Saved Messages", folder: "Personal", unread: 0, messages: [
            TGMessage(sender: "Me", body: "Remember to renew passport.", fromSelf: true),
        ]),
        Chat(title: "Standup Crew", folder: "Work", unread: 1, messages: [
            TGMessage(sender: "Priya", body: "Done with the auth refactor.", fromSelf: false),
            TGMessage(sender: "Me", body: "Nice — testing the PR now.", fromSelf: true),
        ]),
    ]
}
