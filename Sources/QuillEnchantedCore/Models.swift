import Foundation

public enum ChatRole: String, Codable, CaseIterable, Hashable, Sendable {
    case system
    case user
    case assistant
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var conversationID: String
    public var role: ChatRole
    public var content: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        conversationID: String,
        role: ChatRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.conversationID = conversationID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct ConversationSummary: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastMessage: String

    public init(
        id: String = UUID().uuidString,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastMessage: String = ""
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessage = lastMessage
    }
}

public struct OllamaModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

extension String {
    var quillTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func quillTitle(maxLength: Int = 44) -> String {
        let normalized = split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New conversation" }
        if trimmed.count <= maxLength { return trimmed }
        let prefixLength = max(1, maxLength - 3)
        return String(trimmed.prefix(prefixLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
