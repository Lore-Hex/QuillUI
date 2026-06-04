import Foundation
import Testing
@testable import QuillChatKit

@MainActor
@Suite("QuillChatKit primitives")
struct QuillChatKitTests {
    struct Fake: ChatMessage {
        let id: UUID
        let sender: String
        let body: String
        let fromSelf: Bool
    }

    struct Summary: ChatListItem {
        let id: UUID
        let title: String
        let preview: String
        let unreadCount: Int
    }

    struct QuietSummary: ChatListItem {
        let id: UUID
        let title: String
        let preview: String
    }

    struct Timed: ChatMessage {
        let id: UUID
        let sender: String
        let body: String
        let fromSelf: Bool
        let timestamp: Date?
    }

    @Test("ChatMessage refinement carries identity + sender/body/fromSelf")
    func chatMessageShape() {
        let id = UUID()
        let mine = Fake(id: id, sender: "Me", body: "hi", fromSelf: true)
        let theirs = Fake(id: UUID(), sender: "Alex", body: "yo", fromSelf: false)

        #expect(mine.id == id)
        #expect(mine.fromSelf)
        #expect(!theirs.fromSelf)
        #expect(theirs.sender == "Alex")
        #expect(mine.body == "hi")
    }

    @Test("ChatMessage is Hashable so apps can use it as a List selection")
    func chatMessageIsHashable() {
        let id = UUID()
        let a = Fake(id: id, sender: "Me", body: "a", fromSelf: true)
        let b = Fake(id: id, sender: "Me", body: "a", fromSelf: true)
        let c = Fake(id: UUID(), sender: "Me", body: "a", fromSelf: true)
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test("ChatRow accepts unread = 0 by default")
    func chatRowDefaultsUnreadToZero() {
        let row = ChatRow(title: "Mom", preview: "see you soon")
        #expect(row.unread == 0)
        #expect(!row.selected)
        #expect(row.title == "Mom")
        #expect(row.preview == "see you soon")
    }

    @Test("ChatRow records non-zero unread badge and selection")
    func chatRowCarriesUnreadAndSelection() {
        let row = ChatRow(title: "DevOps", preview: "Build 1 ok", unread: 3, selected: true)
        #expect(row.unread == 3)
        #expect(row.selected)
    }

    @Test("ChatListItem defaults unread count to zero")
    func chatListItemDefaultsUnreadToZero() {
        let item = QuietSummary(id: UUID(), title: "Family", preview: "Dinner?")
        #expect(item.unreadCount == 0)
    }

    @Test("ChatSidebarList carries item summaries and appearance")
    func chatSidebarListCarriesInputs() {
        let appearance = ChatAppearance(unreadBadgeCornerRadius: 4, rowVerticalPadding: 9)
        let item = Summary(
            id: UUID(),
            title: "DevOps",
            preview: "Canary healthy",
            unreadCount: 3
        )
        let list = ChatSidebarList(items: [item], appearance: appearance) { _ in }

        #expect(list.items.count == 1)
        #expect(list.items[0].title == "DevOps")
        #expect(list.items[0].preview == "Canary healthy")
        #expect(list.items[0].unreadCount == 3)
        #expect(list.appearance.rowVerticalPadding == 9)
        #expect(list.appearance.unreadBadgeCornerRadius == 4)
        #expect(list.selectedID == nil)
    }

    @Test("ChatSidebarList carries selected row identity")
    func chatSidebarListCarriesSelectedID() {
        let id = UUID()
        let item = Summary(
            id: id,
            title: "DevOps",
            preview: "Canary healthy",
            unreadCount: 3
        )
        let list = ChatSidebarList(items: [item], selectedID: id) { _ in }

        #expect(list.selectedID == id)
    }

    @Test("ChatSidebar carries standard title, items, appearance, and no accessory by default")
    func chatSidebarCarriesStandardShellInputs() {
        let item = Summary(
            id: UUID(),
            title: "Family",
            preview: "Dinner?",
            unreadCount: 0
        )
        let sidebar = ChatSidebar(title: "Quill Signal", items: [item]) { _ in }

        #expect(sidebar.title == "Quill Signal")
        #expect(sidebar.items.count == 1)
        #expect(sidebar.items[0].title == "Family")
        #expect(sidebar.selectedID == nil)
        #expect(sidebar.appearance.bubbleCornerRadius == ChatAppearance.standard.bubbleCornerRadius)
    }

    @Test("ChatSidebar carries app-specific accessory controls")
    func chatSidebarCarriesAccessory() {
        let appearance = ChatAppearance(rowVerticalPadding: 11)
        let item = Summary(
            id: UUID(),
            title: "DevOps",
            preview: "Canary healthy",
            unreadCount: 3
        )
        let sidebar = ChatSidebar(title: "Quill Telegram", items: [item], appearance: appearance) {
            ChatSelectionPlaceholder("Folders")
        } onSelect: { _ in }

        #expect(sidebar.title == "Quill Telegram")
        #expect(sidebar.items[0].unreadCount == 3)
        #expect(sidebar.appearance.rowVerticalPadding == 11)
    }

    @Test("ChatInitialSelection reads ordered keys and clamps to valid rows")
    func chatInitialSelectionReadsOrderedKeysAndClamps() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        ]
        let items = [
            Summary(id: ids[0], title: "Family", preview: "Dinner?", unreadCount: 0),
            Summary(id: ids[1], title: "DevOps", preview: "Canary healthy", unreadCount: 3),
            Summary(id: ids[2], title: "Saved", preview: "Passport", unreadCount: 0)
        ]

        #expect(ChatInitialSelection.sharedEnvironmentKey == "QUILLUI_CHAT_SELECTED_THREAD_INDEX_ON_START")
        #expect(ChatInitialSelection.index(environmentKeys: ["missing"], environment: [:]) == nil)
        #expect(ChatInitialSelection.index(environmentKeys: ["bad", "row"], environment: ["bad": "x", "row": "2"]) == 2)
        #expect(ChatInitialSelection.selectedID(in: items, environmentKeys: ["row"], environment: ["row": "1"]) == ids[1])
        #expect(ChatInitialSelection.selectedID(in: items, environmentKeys: ["row"], environment: ["row": "-9"]) == ids[0])
        #expect(ChatInitialSelection.selectedID(in: items, environmentKeys: ["row"], environment: ["row": "99"]) == ids[2])
        #expect(ChatInitialSelection.selectedID(in: items, environmentKeys: ["row"], environment: ["row": ""]) == nil)
    }

    @Test("ChatSplitShell carries reusable split-view state")
    func chatSplitShellCarriesReusableSplitViewState() {
        let thread = GenericThread(
            id: UUID(),
            title: "Inbox",
            messages: [
                Fake(id: UUID(), sender: "Me", body: "hello", fromSelf: true)
            ]
        )
        let appearance = ChatAppearance(rowVerticalPadding: 12, composerPadding: 18)
        let shell = ChatSplitShell(
            title: "Quill Signal",
            threads: [thread],
            selectedID: .constant(thread.id),
            draft: .constant("draft"),
            placeholder: "Select a conversation",
            composerPlaceholder: "Reply",
            sendTitle: "Post",
            appearance: appearance,
            onSend: { }
        )

        #expect(shell.title == "Quill Signal")
        #expect(shell.threads.map(\.id) == [thread.id])
        #expect(shell.placeholder == "Select a conversation")
        #expect(shell.composerPlaceholder == "Reply")
        #expect(shell.sendTitle == "Post")
        #expect(shell.appearance.rowVerticalPadding == 12)
        #expect(shell.appearance.composerPadding == 18)
    }

    @Test("ChatSelectionPlaceholder carries empty-state copy")
    func chatSelectionPlaceholderCarriesTitle() {
        let placeholder = ChatSelectionPlaceholder("Select a chat")
        #expect(placeholder.title == "Select a chat")
    }

    @Test("ChatAppearance standard preserves the shared shell layout tokens")
    func chatAppearanceStandardLayoutTokens() {
        let appearance = ChatAppearance.standard

        #expect(appearance.bubbleCornerRadius == 12)
        #expect(appearance.unreadBadgeCornerRadius == 8)
        #expect(appearance.selectedRowCornerRadius == 8)
        #expect(appearance.bubblePadding == 10)
        #expect(appearance.rowVerticalPadding == 4)
        #expect(appearance.timelinePadding == 16)
        #expect(appearance.messageSpacing == 10)
        #expect(appearance.composerPadding == 10)
    }

    @Test("ChatAppearance standard aliases the desktop profile")
    func chatAppearanceStandardAliasesDesktopProfile() {
        #expect(ChatInteractionProfile.allCases == [.desktop, .touch])
        #expect(ChatAppearance.standard.bubblePadding == ChatAppearance.desktop.bubblePadding)
        #expect(ChatAppearance.standard.composerPadding == ChatAppearance.standard(for: .desktop).composerPadding)
        #expect(ChatAppearance.standard.timelinePadding == ChatAppearance.standard(for: .desktop).timelinePadding)
    }

    @Test("ChatAppearance touch profile expands hit targets")
    func chatAppearanceTouchProfileExpandsDensity() {
        let desktop = ChatAppearance.standard(for: .desktop)
        let touch = ChatAppearance.standard(for: .touch)

        #expect(touch.bubblePadding > desktop.bubblePadding)
        #expect(touch.rowVerticalPadding > desktop.rowVerticalPadding)
        #expect(touch.timelinePadding > desktop.timelinePadding)
        #expect(touch.messageSpacing > desktop.messageSpacing)
        #expect(touch.composerPadding > desktop.composerPadding)
    }

    @Test("ChatAppearance exposes platform default density without UIKit or AppKit")
    func chatAppearancePlatformDefaultUsesHostDensity() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        #expect(ChatInteractionProfile.platformDefault == .touch)
        #expect(ChatAppearance.platformDefault.bubblePadding == ChatAppearance.touch.bubblePadding)
        #else
        #expect(ChatInteractionProfile.platformDefault == .desktop)
        #expect(ChatAppearance.platformDefault.bubblePadding == ChatAppearance.desktop.bubblePadding)
        #endif
    }

    @Test("ChatRow accepts custom appearance without changing row data")
    func chatRowCarriesAppearance() {
        let appearance = ChatAppearance(unreadBadgeCornerRadius: 3, rowVerticalPadding: 7)
        let row = ChatRow(title: "DevOps", preview: "Build 1 ok", unread: 3, appearance: appearance)

        #expect(row.title == "DevOps")
        #expect(row.preview == "Build 1 ok")
        #expect(row.unread == 3)
        #expect(row.appearance.rowVerticalPadding == 7)
        #expect(row.appearance.unreadBadgeCornerRadius == 3)
    }

    @Test("ChatTimeline preserves message order")
    func chatTimelinePreservesOrder() {
        let messages = [
            Fake(id: UUID(), sender: "A", body: "1", fromSelf: false),
            Fake(id: UUID(), sender: "Me", body: "2", fromSelf: true),
            Fake(id: UUID(), sender: "A", body: "3", fromSelf: false),
        ]
        let timeline = ChatTimeline(title: "Thread", messages: messages)
        #expect(timeline.messages.count == 3)
        #expect(timeline.messages.map(\.body) == ["1", "2", "3"])
        #expect(timeline.title == "Thread")
    }

    @Test("ChatTimeline accepts custom appearance")
    func chatTimelineCarriesAppearance() {
        let appearance = ChatAppearance(timelinePadding: 22, messageSpacing: 6)
        let timeline = ChatTimeline<Fake>(title: "Thread", messages: [], appearance: appearance)

        #expect(timeline.appearance.timelinePadding == 22)
        #expect(timeline.appearance.messageSpacing == 6)
    }

    @Test("ChatTimeline can initialize from a generic chat thread")
    func chatTimelineInitializesFromThread() {
        let thread = GenericThread(
            id: UUID(),
            title: "Inbox",
            messages: [
                Fake(id: UUID(), sender: "Me", body: "hello", fromSelf: true)
            ]
        )
        let timeline = ChatTimeline(thread: thread, appearance: .touch)

        #expect(timeline.title == "Inbox")
        #expect(timeline.messages.map(\.body) == ["hello"])
        #expect(timeline.appearance.bubblePadding == ChatAppearance.touch.bubblePadding)
    }

    @Test("ChatBubble holds the message it was initialized with")
    func chatBubbleHoldsMessage() {
        let msg = Fake(id: UUID(), sender: "Me", body: "hello", fromSelf: true)
        let bubble = ChatBubble(msg)
        #expect(bubble.message.id == msg.id)
        #expect(bubble.message.fromSelf)
    }

    @Test("ChatBubble accepts custom appearance")
    func chatBubbleCarriesAppearance() {
        let msg = Fake(id: UUID(), sender: "Me", body: "hello", fromSelf: true)
        let appearance = ChatAppearance(bubbleCornerRadius: 5, bubblePadding: 18)
        let bubble = ChatBubble(msg, appearance: appearance)

        #expect(bubble.appearance.bubbleCornerRadius == 5)
        #expect(bubble.appearance.bubblePadding == 18)
    }

    @Test("ChatDraft.isSendable rejects empty + whitespace-only drafts")
    func chatDraftRejectsEmpty() {
        #expect(ChatDraft.isSendable("") == false)
        #expect(ChatDraft.isSendable("   ") == false)
        #expect(ChatDraft.isSendable("\n\t  \n") == false)
    }

    @Test("ChatDraft.isSendable accepts drafts with any non-whitespace")
    func chatDraftAcceptsContent() {
        #expect(ChatDraft.isSendable("hi"))
        #expect(ChatDraft.isSendable("  hi  "))
        #expect(ChatDraft.isSendable("hi\n"))
        #expect(ChatDraft.isSendable("👋"))
    }

    @Test("ChatDraft.trimmed strips leading + trailing whitespace and newlines")
    func chatDraftTrims() {
        #expect(ChatDraft.trimmed("  hello  ") == "hello")
        #expect(ChatDraft.trimmed("\n\nhello\n") == "hello")
        #expect(ChatDraft.trimmed("hi there") == "hi there")
        #expect(ChatDraft.trimmed("") == "")
    }

    @Test("ChatPane carries title + messages + placeholder unchanged")
    func chatPaneCarriesInputs() {
        let messages = [
            Fake(id: UUID(), sender: "Me", body: "hi", fromSelf: true),
        ]
        let pane = ChatPane(
            title: "Family",
            messages: messages,
            draft: .constant(""),
            placeholder: "Type something…",
            onSend: { }
        )
        #expect(pane.title == "Family")
        #expect(pane.messages.count == 1)
        #expect(pane.messages[0].body == "hi")
        #expect(pane.placeholder == "Type something…")
    }

    @Test("ChatPane defaults placeholder to \"Message\"")
    func chatPaneDefaultPlaceholder() {
        let pane: ChatPane<Fake> = ChatPane(
            title: "x",
            messages: [],
            draft: .constant(""),
            onSend: { }
        )
        #expect(pane.placeholder == "Message")
    }

    @Test("ChatComposer carries send title and appearance")
    func chatComposerCarriesCustomSendChrome() {
        let appearance = ChatAppearance(composerPadding: 18)
        let composer = ChatComposer(
            placeholder: "Reply",
            sendTitle: "Post",
            appearance: appearance,
            draft: .constant(""),
            onSend: { }
        )

        #expect(composer.placeholder == "Reply")
        #expect(composer.sendTitle == "Post")
        #expect(composer.appearance.composerPadding == 18)
    }

    @Test("ChatPane carries send title and appearance")
    func chatPaneCarriesCustomSendChrome() {
        let appearance = ChatAppearance(timelinePadding: 24, composerPadding: 18)
        let pane: ChatPane<Fake> = ChatPane(
            title: "x",
            messages: [],
            draft: .constant(""),
            placeholder: "Reply",
            sendTitle: "Post",
            appearance: appearance,
            onSend: { }
        )

        #expect(pane.placeholder == "Reply")
        #expect(pane.sendTitle == "Post")
        #expect(pane.appearance.composerPadding == 18)
        #expect(pane.appearance.timelinePadding == 24)
    }

    @Test("ChatPane can initialize from a generic chat thread")
    func chatPaneInitializesFromThread() {
        let thread = GenericThread(
            id: UUID(),
            title: "Inbox",
            messages: [
                Fake(id: UUID(), sender: "Alex", body: "ping", fromSelf: false)
            ]
        )
        let pane = ChatPane(
            thread: thread,
            draft: .constant(""),
            placeholder: "Reply",
            sendTitle: "Post",
            appearance: .touch,
            onSend: { }
        )

        #expect(pane.title == "Inbox")
        #expect(pane.messages.map(\.body) == ["ping"])
        #expect(pane.placeholder == "Reply")
        #expect(pane.sendTitle == "Post")
        #expect(pane.appearance.composerPadding == ChatAppearance.touch.composerPadding)
    }

    @Test("ChatDraft.consume returns trimmed body + clears source when sendable")
    func chatDraftConsumeOnSendable() {
        var draft = "  hello world  "
        let body = ChatDraft.consume(&draft)
        #expect(body == "hello world")
        #expect(draft == "")
    }

    @Test("ChatDraft.consume returns nil + leaves source unchanged when empty")
    func chatDraftConsumeOnEmpty() {
        var draft = "   \n\t  "
        let original = draft
        let body = ChatDraft.consume(&draft)
        #expect(body == nil)
        #expect(draft == original)
    }

    @Test("ChatDraft.consume is idempotent on empty drafts")
    func chatDraftConsumeIdempotentOnEmpty() {
        var draft = ""
        #expect(ChatDraft.consume(&draft) == nil)
        #expect(ChatDraft.consume(&draft) == nil)
        #expect(draft == "")
    }

    // MARK: - ChatMessage.timestamp

    /// Concrete type that carries a timestamp — exercises the
    /// override path. `Fake` (defined at the top of the suite)
    /// has no timestamp field and exercises the protocol-extension
    /// default.
    struct Timestamped: ChatMessage {
        let id: UUID
        let sender: String
        let body: String
        let fromSelf: Bool
        let timestamp: Date?
    }

    @Test("ChatMessage.timestamp protocol extension defaults to nil")
    func chatMessageTimestampDefaultsToNil() {
        let msg = Fake(id: UUID(), sender: "Me", body: "hi", fromSelf: true)
        #expect(msg.timestamp == nil)
    }

    @Test("ChatMessage conformances that supply a timestamp surface it via the protocol")
    func chatMessageTimestampOverrideSurfaces() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let msg: any ChatMessage = Timestamped(
            id: UUID(), sender: "Me", body: "hi", fromSelf: true, timestamp: when
        )
        #expect(msg.timestamp == when)
    }

    @Test("ChatTimestampFormatter returns a non-empty short-time string")
    func chatTimestampFormatterReturnsTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let formatted = ChatTimestampFormatter.formatted(date)
        #expect(!formatted.isEmpty)
        // Short time output never contains a year. Regardless of
        // locale this catches a regression to .medium / .full styles.
        #expect(!formatted.contains("2023") && !formatted.contains("2024"))
    }

    @Test("needsDaySeparator: first message and day changes need a divider")
    func needsDaySeparatorLogic() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let t0 = Date(timeIntervalSince1970: 1_000_000_000)
        let sameDay = t0.addingTimeInterval(3600)         // +1h, same UTC day
        let nextDay = t0.addingTimeInterval(48 * 3600)    // +2 days, different day
        #expect(ChatTimestampFormatter.needsDaySeparator(prev: nil, current: t0, calendar: cal))
        #expect(!ChatTimestampFormatter.needsDaySeparator(prev: t0, current: nil, calendar: cal))
        #expect(!ChatTimestampFormatter.needsDaySeparator(prev: t0, current: sameDay, calendar: cal))
        #expect(ChatTimestampFormatter.needsDaySeparator(prev: t0, current: nextDay, calendar: cal))
    }

    @Test("timelineRows inserts dividers before the first message and on day changes")
    func timelineRowsStructure() {
        // Same-instant rows are always the same calendar day; +2 days is always a
        // different one — so this structure check is timezone-robust.
        let t0 = Date(timeIntervalSince1970: 1_000_000_000)
        let sameDay = t0.addingTimeInterval(60)
        let nextDay = t0.addingTimeInterval(48 * 3600)
        let msgs = [
            Timed(id: UUID(), sender: "A", body: "1", fromSelf: false, timestamp: t0),
            Timed(id: UUID(), sender: "A", body: "2", fromSelf: false, timestamp: sameDay),
            Timed(id: UUID(), sender: "B", body: "3", fromSelf: true, timestamp: nextDay),
        ]
        let kinds = ChatTimestampFormatter.timelineRows(msgs).map { row -> String in
            if case .separator = row { return "sep" }
            return "msg"
        }
        #expect(kinds == ["sep", "msg", "msg", "sep", "msg"])
    }

    @Test("timelineRows emits no divider for timestamp-less messages")
    func timelineRowsNoTimestamps() {
        let msgs = [
            Timed(id: UUID(), sender: "A", body: "1", fromSelf: false, timestamp: nil),
            Timed(id: UUID(), sender: "B", body: "2", fromSelf: true, timestamp: nil),
        ]
        let kinds = ChatTimestampFormatter.timelineRows(msgs).map { row -> String in
            if case .separator = row { return "sep" }
            return "msg"
        }
        #expect(kinds == ["msg", "msg"])
    }

    // MARK: - ChatDraft.sendMessage

    /// A toy conversation type for testing the generic
    /// sendMessage helper without dragging in Signal's or
    /// Telegram's concrete chat models.
    struct Thread: Identifiable {
        let id: UUID
        var messages: [Fake]
    }

    struct GenericThread: ChatThread {
        let id: UUID
        let title: String
        var messages: [Fake]

        var preview: String { messages.last?.body ?? "" }
    }

    @Test("sendMessage overload appends through ChatThread.messages")
    func sendMessageUsesChatThreadStorage() {
        let id = UUID()
        var threads = [GenericThread(id: id, title: "Inbox", messages: [])]
        var draft = "  ship it  "

        let sent = ChatDraft.sendMessage(
            from: &draft,
            toID: id,
            in: &threads
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(sent)
        #expect(draft == "")
        #expect(threads[0].preview == "ship it")
        #expect(threads[0].messages.count == 1)
    }

    @Test("sendMessage appends the trimmed draft + clears it when id matches")
    func sendMessageHappyPath() {
        let id = UUID()
        var threads = [Thread(id: id, messages: [])]
        var draft = "  hi  "

        let sent = ChatDraft.sendMessage(
            from: &draft,
            toID: id,
            in: &threads,
            messagesAt: \.messages
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(sent)
        #expect(draft == "")
        #expect(threads[0].messages.count == 1)
        #expect(threads[0].messages[0].body == "hi")
    }

    @Test("sendMessage returns false + leaves state untouched when draft empty")
    func sendMessageEmptyDraftIsNoOp() {
        let id = UUID()
        var threads = [Thread(id: id, messages: [])]
        var draft = "   "
        let snapshot = draft

        let sent = ChatDraft.sendMessage(
            from: &draft,
            toID: id,
            in: &threads,
            messagesAt: \.messages
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(sent == false)
        #expect(draft == snapshot)
        #expect(threads[0].messages.isEmpty)
    }

    @Test("sendMessage returns false when id is nil")
    func sendMessageNilIDIsNoOp() {
        var threads = [Thread(id: UUID(), messages: [])]
        var draft = "hi"

        let sent = ChatDraft.sendMessage(
            from: &draft,
            toID: nil,
            in: &threads,
            messagesAt: \.messages
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(sent == false)
        #expect(draft == "hi")
        #expect(threads[0].messages.isEmpty)
    }

    @Test("sendMessage returns false when id doesn't match any item")
    func sendMessageUnknownIDIsNoOp() {
        var threads = [Thread(id: UUID(), messages: [])]
        var draft = "hi"

        let sent = ChatDraft.sendMessage(
            from: &draft,
            toID: UUID(), // a different id
            in: &threads,
            messagesAt: \.messages
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(sent == false)
        #expect(draft == "hi")
        #expect(threads[0].messages.isEmpty)
    }

    @Test("sendMessage appends to the right thread when multiple are present")
    func sendMessageRoutesByID() {
        let targetID = UUID()
        var threads = [
            Thread(id: UUID(), messages: []),
            Thread(id: targetID, messages: []),
            Thread(id: UUID(), messages: []),
        ]
        var draft = "hello"

        _ = ChatDraft.sendMessage(
            from: &draft,
            toID: targetID,
            in: &threads,
            messagesAt: \.messages
        ) { body in
            Fake(id: UUID(), sender: "Me", body: body, fromSelf: true)
        }

        #expect(threads[0].messages.isEmpty)
        #expect(threads[1].messages.count == 1)
        #expect(threads[1].messages[0].body == "hello")
        #expect(threads[2].messages.isEmpty)
    }
}
