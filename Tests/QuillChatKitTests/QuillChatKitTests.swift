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
        #expect(row.title == "Mom")
        #expect(row.preview == "see you soon")
    }

    @Test("ChatRow records non-zero unread badge")
    func chatRowCarriesUnread() {
        let row = ChatRow(title: "DevOps", preview: "Build 1 ok", unread: 3)
        #expect(row.unread == 3)
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

    @Test("ChatBubble holds the message it was initialized with")
    func chatBubbleHoldsMessage() {
        let msg = Fake(id: UUID(), sender: "Me", body: "hello", fromSelf: true)
        let bubble = ChatBubble(msg)
        #expect(bubble.message.id == msg.id)
        #expect(bubble.message.fromSelf)
    }
}
