import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Enchanted persistence context")
@MainActor
struct EnchantedPersistenceTests {
    @Test("inserts fetches updates and deletes through model context")
    func contextLifecycle() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        var conversation = try context.insert(ConversationDraft(title: "Draft title"))
        try context.insert(ChatMessage(conversationID: conversation.id, role: .user, content: "Hello"))

        var conversations = try context.fetchConversations()
        #expect(conversations.map(\.title) == ["Draft title"])
        #expect(conversations[0].lastMessage == "Hello")

        conversation = conversations[0]
        try context.update(conversation, title: "Renamed")
        conversations = try context.fetchConversations()
        #expect(conversations.map(\.title) == ["Renamed"])

        let messages = try context.fetchMessages(for: conversation.id)
        #expect(messages.map(\.content) == ["Hello"])

        try context.delete(conversations[0])
        #expect(try context.fetchConversations().isEmpty)
    }

    @Test("app model can use injected persistence context")
    func modelUsesInjectedContext() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        let model = EnchantedModel(endpoint: "http://localhost:11434", modelContext: context)
        model.newConversation()

        #expect(model.conversations.count == 1)
        #expect(model.selectedConversationID == model.conversations[0].id)
        #expect(model.status == EnchantedCopy.newConversationTitle)
    }

    @Test("app model exposes adapter operations needed by upstream-shaped views")
    func modelSupportsUpstreamSliceAdapterOperations() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        let first = try context.insert(ConversationDraft(title: "Keep"))
        let second = try context.insert(ConversationDraft(title: "Delete"))
        let model = EnchantedModel(endpoint: "http://localhost:11434", modelContext: context)

        model.boot()
        model.select(first)
        model.selectModel(named: "llava:latest")
        model.delete(second)

        #expect(model.selectedModel == "llava:latest")
        #expect(model.selectedConversationID == first.id)
        #expect(model.conversations.map(\.id) == [first.id])
    }

    @Test("app model trims a conversation from an edited user message")
    func modelTrimsConversationFromEditedMessage() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        let conversation = try context.insert(ConversationDraft(title: "Edit flow"))
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
        try context.insert(first)
        try context.insert(edited)
        try context.insert(reply)

        let model = EnchantedModel(endpoint: "http://localhost:11434", modelContext: context)
        model.select(conversation)

        #expect(model.trimConversation(from: edited.id))
        #expect(model.messages.map(\.id) == ["first"])
        #expect(model.conversations[0].lastMessage == "Original context")
    }

    @Test("app model exposes stop state for generation controls")
    func modelStopGenerationState() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let context = try EnchantedModelContext.quillData(url: url)
        let model = EnchantedModel(endpoint: "http://localhost:11434", modelContext: context)

        model.stopGenerating()
        #expect(model.status == "Ready")

        model.isLoading = true
        model.status = "Streaming response..."
        model.stopGenerating()
        #expect(model.status == "Stopping...")
    }

    @Test("initial selection helper reads ordered keys and clamps")
    func initialSelectionHelperReadsOrderedKeysAndClamps() {
        let items = [
            SelectionProbe(id: "first"),
            SelectionProbe(id: "second"),
            SelectionProbe(id: "third")
        ]

        #expect(
            EnchantedInitialSelection.selectedConversationIndex(
                count: items.count,
                environment: ["QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START": "1"]
            ) == 1
        )
        #expect(
            EnchantedInitialSelection.selectedConversationIndex(
                count: items.count,
                environment: ["QUILLUI_ENCHANTED_QT_SELECTED_CONVERSATION_INDEX_ON_START": "99"]
            ) == 2
        )
        #expect(
            EnchantedInitialSelection.selectedConversationID(
                in: items,
                environment: ["QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START": "-9"]
            ) == "first"
        )
        #expect(
            EnchantedInitialSelection.selectedConversationIndex(
                count: items.count,
                environment: ["QUILLUI_ENCHANTED_SELECTED_CONVERSATION_INDEX_ON_START": ""]
            ) == nil
        )
    }

    private func temporarySQLiteURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }

    private struct SelectionProbe: Identifiable {
        var id: String
    }
}
