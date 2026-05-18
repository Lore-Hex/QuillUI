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

private let quillLikelyImageModelNameNeedles = [
    "llava",
    "vision",
    "bakllava",
    "moondream",
    "minicpm-v",
    "qwen2.5vl",
    "qwen2.5-vl",
    "qwen2-vl",
    "qwen3-vl",
    "qwen-vl",
    "medgemma",
    "mistral-small3.1",
    "mistral-small3.2"
]

public extension String {
    var quillTrimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var quillLikelySupportsImages: Bool {
        let lowercasedName = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowercasedName.quillLikelyIsVisionGemma3Model
            || quillLikelyImageModelNameNeedles.contains { lowercasedName.contains($0) }
    }

    func quillTitle(maxLength: Int = 44) -> String {
        let normalized = split(whereSeparator: \.isNewline).joined(separator: " ")
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New conversation" }
        if trimmed.count <= maxLength { return trimmed }
        let prefixLength = max(1, maxLength - 3)
        return String(trimmed.prefix(prefixLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private var quillLikelyIsVisionGemma3Model: Bool {
        guard self == "gemma3" || hasPrefix("gemma3:") else { return false }
        let components = split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return true }
        let tag = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return true }
        return tag == "latest" || tag.hasPrefix("4b") || tag.hasPrefix("12b") || tag.hasPrefix("27b")
    }
}
