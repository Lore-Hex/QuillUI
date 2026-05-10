import Foundation

public protocol ConversationPersistence: AnyObject {
    func fetchConversations() throws -> [ConversationSummary]
    func fetchMessages(for conversationID: String) throws -> [ChatMessage]
    @discardableResult func insertConversation(title: String) throws -> ConversationSummary
    func updateConversationTitle(id: String, title: String) throws
    func insertMessage(_ message: ChatMessage) throws
    func deleteMessages(in conversationID: String, from messageID: String) throws
    func deleteConversation(id: String) throws
    func deleteAllConversations() throws
    func save() throws
}

public struct ConversationDraft: Equatable, Sendable {
    public var title: String

    public init(title: String) {
        self.title = title
    }
}

public final class EnchantedModelContext: @unchecked Sendable {
    private let persistence: any ConversationPersistence

    public init(persistence: any ConversationPersistence) {
        self.persistence = persistence
    }

    public static func sqlite(url: URL) throws -> EnchantedModelContext {
        try EnchantedModelContext(persistence: SQLiteConversationStore(url: url))
    }

    public static func quillData(url: URL) throws -> EnchantedModelContext {
        try EnchantedModelContext(persistence: QuillDataConversationStore(url: url))
    }

    public static func `default`() throws -> EnchantedModelContext {
        try quillData(url: QuillDataConversationStore.defaultURL())
    }

    public func fetchConversations() throws -> [ConversationSummary] {
        try persistence.fetchConversations()
    }

    public func fetchMessages(for conversationID: String) throws -> [ChatMessage] {
        try persistence.fetchMessages(for: conversationID)
    }

    @discardableResult
    public func insert(_ draft: ConversationDraft) throws -> ConversationSummary {
        let conversation = try persistence.insertConversation(title: draft.title)
        try save()
        return conversation
    }

    public func insert(_ message: ChatMessage) throws {
        try persistence.insertMessage(message)
        try save()
    }

    public func deleteMessages(in conversationID: String, from messageID: String) throws {
        try persistence.deleteMessages(in: conversationID, from: messageID)
        try save()
    }

    public func update(_ conversation: ConversationSummary, title: String) throws {
        try updateConversationTitle(id: conversation.id, title: title)
    }

    public func updateConversationTitle(id: String, title: String) throws {
        try persistence.updateConversationTitle(id: id, title: title)
        try save()
    }

    public func delete(_ conversation: ConversationSummary) throws {
        try deleteConversation(id: conversation.id)
    }

    public func deleteConversation(id: String) throws {
        try persistence.deleteConversation(id: id)
        try save()
    }

    public func deleteAllConversations() throws {
        try persistence.deleteAllConversations()
        try save()
    }

    public func save() throws {
        try persistence.save()
    }
}

// SQLiteConversationStore is now a typealias for QuillDataConversationStore
// (see SQLiteConversationStore.swift). The latter already conforms to
// ConversationPersistence directly, so the extension previously defined here
// has been removed to avoid invalid-redeclaration errors.
