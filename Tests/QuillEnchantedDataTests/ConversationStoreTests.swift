import Foundation
import Testing
@testable import QuillEnchantedData

// Salvaged from the deleted QuillEnchantedTests target (reimpl retirement,
// epic #188). These exercise the kept, load-bearing QuillEnchantedData
// persistence layer (QuillDataConversationStore + legacy SQLiteConversationStore)
// that backs the real-source quill-chat-linux path — so the coverage must
// survive the Core deletion. The only change is the import: it used to ride
// QuillEnchantedCore's re-exports; it now imports QuillEnchantedData directly.
@Suite("Conversation stores")
struct ConversationStoreTests {
    @Test("persists conversations and messages through QuillData")
    func persistsConversationHistoryWithQuillData() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try QuillDataConversationStore(url: url)
        let conversation = try store.insertConversation(title: "Port Enchanted")
        try store.insertMessage(ChatMessage(conversationID: conversation.id, role: .user, content: "Hello"))
        try store.insertMessage(ChatMessage(conversationID: conversation.id, role: .assistant, content: "Hi there"))

        let conversations = try store.fetchConversations()
        #expect(conversations.count == 1)
        #expect(conversations[0].title == "Port Enchanted")
        #expect(conversations[0].lastMessage == "Hi there")

        let messages = try store.fetchMessages(for: conversation.id)
        #expect(messages.map(\.content) == ["Hello", "Hi there"])
    }

    @Test("trims QuillData messages from the edited message onward")
    func trimsQuillDataConversationSuffix() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try QuillDataConversationStore(url: url)
        let conversation = try store.insertConversation(title: "Edit flow")
        let first = ChatMessage(
            id: "first",
            conversationID: conversation.id,
            role: .user,
            content: "Original context",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let edited = ChatMessage(
            id: "edited",
            conversationID: conversation.id,
            role: .user,
            content: "Question to edit",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let reply = ChatMessage(
            id: "reply",
            conversationID: conversation.id,
            role: .assistant,
            content: "Old reply",
            createdAt: Date(timeIntervalSince1970: 30)
        )

        try store.insertMessage(first)
        try store.insertMessage(edited)
        try store.insertMessage(reply)
        try store.deleteMessages(in: conversation.id, from: edited.id)

        let messages = try store.fetchMessages(for: conversation.id)
        #expect(messages.map(\.id) == ["first"])
        #expect(try store.fetchConversations()[0].lastMessage == "Original context")
    }

    @Test("persists conversations and messages")
    func persistsConversationHistory() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteConversationStore(url: url)
        let conversation = try store.createConversation(title: "Port Enchanted")
        try store.append(ChatMessage(conversationID: conversation.id, role: .user, content: "Hello"))
        try store.append(ChatMessage(conversationID: conversation.id, role: .assistant, content: "Hi there"))

        let conversations = try store.loadConversations()
        #expect(conversations.count == 1)
        #expect(conversations[0].title == "Port Enchanted")
        #expect(conversations[0].lastMessage == "Hi there")

        let messages = try store.loadMessages(conversationID: conversation.id)
        #expect(messages.map(\.content) == ["Hello", "Hi there"])
    }

    @Test("legacy SQLite store trims messages from the edited message onward")
    func trimsSQLiteConversationSuffix() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try SQLiteConversationStore(url: url)
        let conversation = try store.createConversation(title: "Edit flow")
        let first = ChatMessage(
            id: "first",
            conversationID: conversation.id,
            role: .user,
            content: "Original context",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        let edited = ChatMessage(
            id: "edited",
            conversationID: conversation.id,
            role: .user,
            content: "Question to edit",
            createdAt: Date(timeIntervalSince1970: 20)
        )
        let reply = ChatMessage(
            id: "reply",
            conversationID: conversation.id,
            role: .assistant,
            content: "Old reply",
            createdAt: Date(timeIntervalSince1970: 30)
        )

        try store.append(first)
        try store.append(edited)
        try store.append(reply)
        try store.trimMessages(conversationID: conversation.id, from: edited.id)

        let messages = try store.loadMessages(conversationID: conversation.id)
        #expect(messages.map(\.id) == ["first"])
        #expect(try store.loadConversations()[0].lastMessage == "Original context")
    }

    @Test("builds compact titles")
    func titleCompaction() {
        let title = "  Explain how to build a SwiftUI compatibility layer for Linux desktop apps with GTK4  "
            .quillTitle(maxLength: 32)
        #expect(title == "Explain how to build a SwiftU...")
    }

    private func temporarySQLiteURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }
}
