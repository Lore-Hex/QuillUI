import Foundation
import Testing
@testable import QuillSignalCore
import QuillChatKit

@Suite("QuillSignalCore fixtures + ChatMessage conformance")
struct QuillSignalCoreTests {

    // MARK: - Message identity + ChatMessage conformance

    @Test("Message assigns a fresh UUID per init() by default")
    func messageUniqueIDs() {
        let a = Message(sender: "Me", body: "hi", fromSelf: true)
        let b = Message(sender: "Me", body: "hi", fromSelf: true)
        #expect(a.id != b.id)
    }

    @Test("Message conforms to ChatMessage and routes through QuillChatKit")
    func messageIsAChatMessage() {
        // Compile-time + run-time conformance check.
        let msg: any ChatMessage = Message(sender: "Me", body: "hi", fromSelf: true)
        #expect(msg.sender == "Me")
        #expect(msg.body == "hi")
        #expect(msg.fromSelf)
    }

    // MARK: - Conversation invariants

    @Test("Conversation init assigns a fresh UUID by default")
    func conversationUniqueIDs() {
        let a = Conversation(name: "x", messages: [])
        let b = Conversation(name: "x", messages: [])
        #expect(a.id != b.id)
    }

    // MARK: - Fixture conversations

    @Test("Fixture conversations are non-empty so the sidebar always has rows")
    func fixtureConversationsNonEmpty() {
        #expect(!QuillSignalFixtures.conversations.isEmpty)
    }

    @Test("Every fixture conversation carries at least one message")
    func fixtureConversationsHaveMessages() {
        for conversation in QuillSignalFixtures.conversations {
            #expect(!conversation.messages.isEmpty, "\(conversation.name) has no messages")
        }
    }

    @Test("Every fixture conversation has a non-empty name")
    func fixtureConversationNames() {
        for conversation in QuillSignalFixtures.conversations {
            #expect(!conversation.name.isEmpty)
        }
    }

    @Test("Fixture conversation ids are unique across the fixture set")
    func fixtureConversationIDsUnique() {
        let ids = QuillSignalFixtures.conversations.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Fixture messages tagged fromSelf carry sender \"Me\"")
    func fixtureSelfMessagesUseMe() {
        for conversation in QuillSignalFixtures.conversations {
            for message in conversation.messages where message.fromSelf {
                #expect(message.sender == "Me", "self message in \(conversation.name) has sender \(message.sender)")
            }
        }
    }

    @Test("Fixture carries the three conversations named in CP89")
    func fixtureNamedConversations() {
        let names = QuillSignalFixtures.conversations.map(\.name)
        #expect(names.contains("Family"))
        #expect(names.contains("Coworker"))
        #expect(names.contains("Notes To Self"))
    }
}
