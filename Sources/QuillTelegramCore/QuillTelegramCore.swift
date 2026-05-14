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
    @State private var chats: [Chat]
    @State private var selectedFolder: String
    @State private var selectedChatID: Chat.ID?
    @State private var draft: String

    public init() {
        let chats = QuillTelegramFixtures.chats
        _chats = State(initialValue: chats)
        _selectedFolder = State(initialValue: TelegramFolderFilter.all)
        _selectedChatID = State(initialValue: QuillTelegramInitialSelection.selectedChatID(in: chats) ?? chats.first?.id)
        _draft = State(initialValue: "")
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            ChatSplitShell(
                title: "Quill Telegram",
                threads: visibleChats,
                selectedID: $selectedChatID,
                draft: $draft,
                placeholder: "Select a chat",
                sidebarAccessory: {
                    folderControls
                },
                onSend: send
            )
        }
    }

    private var folders: [String] { TelegramFolderFilter.allFolderNames }

    private var visibleChats: [Chat] {
        TelegramFolderFilter.apply(chats, folder: selectedFolder)
    }

    private var folderControls: some View {
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
    }

    private func send() {
        ChatDraft.sendMessage(
            from: &draft,
            toID: selectedChatID,
            in: &chats
        ) { body in
            TGMessage(sender: "Me", body: body, fromSelf: true)
        }
    }
}

public enum QuillTelegramInitialSelection {
    public static let environmentKeys = [
        "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START",
        ChatInitialSelection.sharedEnvironmentKey
    ]

    public static func selectedChatID(
        in chats: [Chat],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Chat.ID? {
        ChatInitialSelection.selectedID(
            in: chats,
            environmentKeys: environmentKeys,
            environment: environment
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
    /// Sentinel folder name that means "no filter — show every
    /// chat regardless of folder". Pulled out so the `apply` body
    /// and the `allFolderNames` row stay in agreement; a typo on
    /// either side previously meant an unfilterable / unselectable
    /// pill.
    public static let all = "All"

    public static let allFolderNames: [String] = [all, "Personal", "Work"]

    public static func apply(_ chats: [Chat], folder: String) -> [Chat] {
        guard folder != all else { return chats }
        return chats.filter { $0.folder == folder }
    }
}

// MARK: - Fixture model

public struct TGMessage: ChatMessage {
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

extension Chat: ChatThread {
    public var preview: String { messages.last?.body ?? "" }
    public var unreadCount: Int { unread }
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
