import Foundation
import Testing
@testable import QuillTelegramCore
import QuillChatKit

@Suite("QuillTelegramCore folder filter + fixtures")
struct QuillTelegramCoreTests {

    private static func chat(_ title: String, folder: String, unread: Int = 0) -> Chat {
        Chat(title: title, folder: folder, unread: unread, messages: [])
    }

    // MARK: - TelegramFolderFilter

    @Test("filter returns all chats unchanged for the \"All\" folder")
    func filterAllReturnsEverything() {
        let chats = [
            Self.chat("a", folder: "Personal"),
            Self.chat("b", folder: "Work"),
            Self.chat("c", folder: "Personal"),
        ]
        let result = TelegramFolderFilter.apply(chats, folder: "All")
        #expect(result.count == 3)
        #expect(result.map(\.title) == ["a", "b", "c"])
    }

    @Test("filter narrows to chats whose folder matches the selection")
    func filterByFolder() {
        let chats = [
            Self.chat("a", folder: "Personal"),
            Self.chat("b", folder: "Work"),
            Self.chat("c", folder: "Personal"),
            Self.chat("d", folder: "Work", unread: 2),
        ]
        let personal = TelegramFolderFilter.apply(chats, folder: "Personal")
        let work = TelegramFolderFilter.apply(chats, folder: "Work")
        #expect(personal.map(\.title) == ["a", "c"])
        #expect(work.map(\.title) == ["b", "d"])
    }

    @Test("filter for an unknown folder returns an empty list")
    func filterUnknownFolderEmpty() {
        let chats = [
            Self.chat("a", folder: "Personal"),
            Self.chat("b", folder: "Work"),
        ]
        #expect(TelegramFolderFilter.apply(chats, folder: "Archive").isEmpty)
    }

    @Test("filter preserves chat order within the matching folder")
    func filterPreservesOrder() {
        let chats = (1...5).map { Self.chat("c\($0)", folder: $0.isMultiple(of: 2) ? "Work" : "Personal") }
        let personal = TelegramFolderFilter.apply(chats, folder: "Personal")
        #expect(personal.map(\.title) == ["c1", "c3", "c5"])
    }

    @Test("allFolderNames is the three the sidebar pills paint")
    func folderListExact() {
        #expect(TelegramFolderFilter.allFolderNames == ["All", "Personal", "Work"])
    }

    @Test("Chat routes through QuillChatKit sidebar summaries")
    func chatIsChatListItem() {
        let chat = Chat(
            title: "DevOps Channel",
            folder: "Work",
            unread: 3,
            messages: [
                TGMessage(sender: "@deploybot", body: "Build 4129 succeeded.", fromSelf: false),
                TGMessage(sender: "@deploybot", body: "Canary healthy.", fromSelf: false),
            ]
        )
        let item = Self.chatListItem(chat)

        #expect(item.title == "DevOps Channel")
        #expect(item.preview == "Canary healthy.")
        #expect(item.unreadCount == 3)
    }

    // MARK: - Fixture invariants

    @Test("Fixture chats cover both Personal and Work folders")
    func fixturesCoverBothFolders() {
        let folders = Set(QuillTelegramFixtures.chats.map(\.folder))
        #expect(folders == ["Personal", "Work"])
    }

    @Test("Every fixture chat carries at least one message")
    func fixtureChatsNonEmpty() {
        for chat in QuillTelegramFixtures.chats {
            #expect(!chat.messages.isEmpty, "\(chat.title) has no messages")
        }
    }

    @Test("Fixture chat folders are all members of allFolderNames")
    func fixtureFoldersValid() {
        let valid = Set(TelegramFolderFilter.allFolderNames)
        for chat in QuillTelegramFixtures.chats {
            #expect(valid.contains(chat.folder), "\(chat.folder) is not in the pill row")
        }
    }

    @Test("Fixture chat ids are unique across the chat list")
    func fixtureChatIDsUnique() {
        let ids = QuillTelegramFixtures.chats.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("\"All\" folder filter on the fixture returns every chat")
    func fixtureAllFolderReturnsAll() {
        let all = TelegramFolderFilter.apply(QuillTelegramFixtures.chats, folder: "All")
        #expect(all.count == QuillTelegramFixtures.chats.count)
    }

    @Test("Initial selection uses Telegram key before shared chat fallback")
    func initialSelectionUsesTelegramKeyBeforeSharedFallback() {
        let chats = QuillTelegramFixtures.chats

        #expect(QuillTelegramInitialSelection.environmentKeys == [
            "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START",
            ChatInitialSelection.sharedEnvironmentKey
        ])
        #expect(QuillTelegramInitialSelection.selectedChatID(
            in: chats,
            environment: [
                "QUILLUI_TELEGRAM_SELECTED_THREAD_INDEX_ON_START": "1",
                ChatInitialSelection.sharedEnvironmentKey: "2"
            ]
        ) == chats[1].id)
        #expect(QuillTelegramInitialSelection.selectedChatID(
            in: chats,
            environment: [ChatInitialSelection.sharedEnvironmentKey: "3"]
        ) == chats[3].id)
    }

    private static func chatListItem<Item: ChatListItem>(_ item: Item) -> Item {
        item
    }
}
