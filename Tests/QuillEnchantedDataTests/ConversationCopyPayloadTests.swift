import Foundation
import QuillEnchantedData
import QuillEnchantedShared
import Testing

@Suite("Enchanted conversation copy payload")
struct ConversationCopyPayloadTests {
    @Test("plain text matches genuine Copy Chat format")
    func plainTextMatchesGenuineCopyChatFormat() throws {
        let payload = EnchantedConversationCopyPayload(messages: [
            .init(role: ChatRole.user.rawValue, content: "Visit https://example.com/a/b?x=1"),
            .init(role: ChatRole.assistant.rawValue, content: "Line one\nLine two")
        ])

        #expect(payload.plainTextString() == """
        User: Visit https://example.com/a/b?x=1

        Assistant: Line one
        Line two
        """)
        let copiedString = try payload.string(json: false)
        #expect(copiedString == payload.plainTextString())
    }

    @Test("JSON matches genuine Copy Chat as JSON format")
    func jsonMatchesGenuineCopyChatAsJSONFormat() throws {
        let payload = EnchantedConversationCopyPayload(messages: [
            .init(role: ChatRole.user.rawValue, content: "Visit https://example.com/a/b?x=1"),
            .init(role: ChatRole.assistant.rawValue, content: "Line one\nLine two")
        ])

        let jsonString = try payload.jsonString()
        let copiedString = try payload.string(json: true)

        #expect(jsonString == #"[{"role":"user","content":"Visit https://example.com/a/b?x=1"},{"role":"assistant","content":"Line one\nLine two"}]"#)
        #expect(copiedString == jsonString)
    }

    @Test("payload can be created from stored chat messages")
    func payloadCanBeCreatedFromStoredChatMessages() {
        let createdAt = Date(timeIntervalSince1970: 1_717_000_000)
        let payload = EnchantedConversationCopyPayload(chatMessages: [
            ChatMessage(
                id: "message-1",
                conversationID: "conversation-1",
                role: .system,
                content: "Stay concise.",
                createdAt: createdAt
            )
        ])

        #expect(payload.messages == [
            .init(role: "system", content: "Stay concise.")
        ])
        #expect(payload.isEmpty == false)
    }
}
