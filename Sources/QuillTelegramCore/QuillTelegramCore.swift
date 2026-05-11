import Foundation
import QuillUI
import QuillChatKit

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
/// timeline in the detail pane. Bubble + sidebar-row + timeline
/// chrome lives in `QuillChatKit`; this file owns the fixture
/// model, the folder filter, and the unread-badge logic.
@MainActor
public struct QuillTelegramContentView: View {
    @State private var chats = QuillTelegramFixtures.chats
    @State private var selectedFolder = "All"
    @State private var selectedChatID: Chat.ID? = QuillTelegramFixtures.chats.first?.id
    @State private var draft = ""

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var folders: [String] { TelegramFolderFilter.allFolderNames }

    private var visibleChats: [Chat] {
        TelegramFolderFilter.apply(chats, folder: selectedFolder)
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
                        ChatRow(
                            title: chat.title,
                            preview: chat.messages.last?.body ?? "",
                            unread: chat.unread
                        )
                    }
                }
            }
        }
    }

    private var detail: some View {
        Group {
            if let chat = currentChat {
                ChatPane(
                    title: chat.title,
                    messages: chat.messages,
                    draft: $draft,
                    onSend: send
                )
            } else {
                Text("Select a chat")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var currentChat: Chat? {
        guard let id = selectedChatID else { return nil }
        return visibleChats.first(where: { $0.id == id })
    }

    private func send() {
        guard let body = ChatDraft.consume(&draft),
              let id = selectedChatID,
              let idx = chats.firstIndex(where: { $0.id == id })
        else { return }
        chats[idx].messages.append(
            TGMessage(sender: "Me", body: body, fromSelf: true)
        )
    }
}

// MARK: - Folder filter

/// Telegram organizes chats into folders. The pill row in the
/// sidebar surfaces three: "All" (no filter) plus "Personal" and
/// "Work" (each shows only chats whose `folder` matches). Pulled
/// out as a static helper so the filter logic is unit-testable
/// without touching the view.
public enum TelegramFolderFilter {
    public static let allFolderNames: [String] = ["All", "Personal", "Work"]

    public static func apply(_ chats: [Chat], folder: String) -> [Chat] {
        guard folder != "All" else { return chats }
        return chats.filter { $0.folder == folder }
    }
}

// MARK: - Fixture model

public struct TGMessage: ChatMessage {
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
