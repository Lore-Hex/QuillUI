import Foundation
import QuillData

public final class QuillDataConversationStore: ConversationPersistence {
    private let context: ModelContext

    public static func defaultURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["QUILLDATA_HOME"] ?? environment["HOME"]
        let homeURL = home.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let baseURL = homeURL
            .appendingPathComponent(".quillui", isDirectory: true)
            .appendingPathComponent("enchanted", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("enchanted-quilldata.sqlite")
    }

    public init(url: URL) throws {
        let schema = Schema([
            QuillDataConversationRecord.self,
            QuillDataMessageRecord.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        self.context = ModelContext(container)
        self.context.autosaveEnabled = false
    }

    public func fetchConversations() throws -> [ConversationSummary] {
        let records = try context.fetch(FetchDescriptor<QuillDataConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))

        return try records.map { record in
            let lastMessage = try fetchMessages(for: record.id).last?.content ?? ""
            return record.summary(lastMessage: lastMessage)
        }
    }

    public func fetchMessages(for conversationID: String) throws -> [ChatMessage] {
        try context.fetch(FetchDescriptor<QuillDataMessageRecord>(
            filter: { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        .map(\.message)
    }

    @discardableResult
    public func insertConversation(title: String) throws -> ConversationSummary {
        let record = QuillDataConversationRecord(title: title)
        context.insert(record)
        try save()
        return record.summary(lastMessage: "")
    }

    @discardableResult
    public func createConversation(title: String) throws -> ConversationSummary {
        try insertConversation(title: title)
    }

    public func updateConversationTitle(id: String, title: String) throws {
        guard var record = try conversationRecord(id: id) else { return }
        record.title = title
        record.updatedAt = Date()
        context.insert(record)
        try save()
    }

    public func insertMessage(_ message: ChatMessage) throws {
        context.insert(QuillDataMessageRecord(message))
        if var conversation = try conversationRecord(id: message.conversationID) {
            conversation.updatedAt = message.createdAt
            context.insert(conversation)
        }
        try save()
    }

    public func append(_ message: ChatMessage) throws {
        try insertMessage(message)
    }

    public func loadConversations() throws -> [ConversationSummary] {
        try fetchConversations()
    }

    public func loadMessages(conversationID: String) throws -> [ChatMessage] {
        try fetchMessages(for: conversationID)
    }

    public func deleteMessages(in conversationID: String, from messageID: String) throws {
        let messages = try context.fetch(FetchDescriptor<QuillDataMessageRecord>(
            filter: { $0.conversationID == conversationID },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        guard let trimIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }

        for message in messages[trimIndex...] {
            context.delete(message)
        }

        if var conversation = try conversationRecord(id: conversationID) {
            let remainingMessages = messages[..<trimIndex]
            conversation.updatedAt = remainingMessages.last?.createdAt ?? Date()
            context.insert(conversation)
        }

        try save()
    }

    public func trimMessages(conversationID: String, from messageID: String) throws {
        try deleteMessages(in: conversationID, from: messageID)
    }

    public func deleteConversation(id: String) throws {
        let messages = try context.fetch(FetchDescriptor<QuillDataMessageRecord>(
            filter: { $0.conversationID == id }
        ))
        for message in messages {
            context.delete(message)
        }
        if let conversation = try conversationRecord(id: id) {
            context.delete(conversation)
        }
        try save()
    }

    public func deleteAllConversations() throws {
        try context.delete(model: QuillDataMessageRecord.self)
        try context.delete(model: QuillDataConversationRecord.self)
        try save()
    }

    public func save() throws {
        try context.save()
    }

    private func conversationRecord(id: String) throws -> QuillDataConversationRecord? {
        try context.fetch(FetchDescriptor<QuillDataConversationRecord>(
            filter: { $0.id == id },
            fetchLimit: 1
        ))
        .first
    }
}

private struct QuillDataConversationRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillEnchantedCore.QuillDataConversationRecord"

    var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, title: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func summary(lastMessage: String) -> ConversationSummary {
        ConversationSummary(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessage: lastMessage
        )
    }
}

private struct QuillDataMessageRecord: PersistentModel, QuillDataStableModelName {
    static let quillDataStableModelName = "QuillEnchantedCore.QuillDataMessageRecord"

    var id: String
    var conversationID: String
    var role: ChatRole
    var content: String
    var createdAt: Date

    init(_ message: ChatMessage) {
        self.id = message.id
        self.conversationID = message.conversationID
        self.role = message.role
        self.content = message.content
        self.createdAt = message.createdAt
    }

    var message: ChatMessage {
        ChatMessage(
            id: id,
            conversationID: conversationID,
            role: role,
            content: content,
            createdAt: createdAt
        )
    }
}
