import Foundation
import QuillEnchantedData

enum EnchantedConversationCopyPayload {
    static func plainText(from messages: [ChatMessage]) -> String {
        messages
            .map { "\($0.role.rawValue.capitalized): \($0.content)" }
            .joined(separator: "\n\n")
    }

    static func json(from messages: [ChatMessage]) -> String? {
        let jsonArray = messages.map {
            MessagePayload(role: $0.role.rawValue, content: $0.content)
        }
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.withoutEscapingSlashes]

        guard let jsonData = try? jsonEncoder.encode(jsonArray) else {
            return nil
        }
        return String(data: jsonData, encoding: .utf8)
    }

    static func string(from messages: [ChatMessage], json: Bool) -> String? {
        guard !messages.isEmpty else { return nil }
        return json ? Self.json(from: messages) : Self.plainText(from: messages)
    }

    private struct MessagePayload: Encodable {
        var role: String
        var content: String
    }
}
