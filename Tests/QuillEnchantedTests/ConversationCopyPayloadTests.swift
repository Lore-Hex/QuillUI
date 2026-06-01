import Foundation
import Testing
@testable import QuillEnchantedCore

@Suite("Enchanted conversation copy payloads")
struct ConversationCopyPayloadTests {
    @Test("formats sample conversation as plain text and JSON")
    func formatsSampleConversationCopyPayloads() throws {
        let conversationID = "sample-conversation"
        let messages = [
            ChatMessage(
                id: "user-message",
                conversationID: conversationID,
                role: .user,
                content: "How many quarks are in the Standard Model?",
                createdAt: Date(timeIntervalSince1970: 10)
            ),
            ChatMessage(
                id: "assistant-message",
                conversationID: conversationID,
                role: .assistant,
                content: "There are 6 quarks, each with an antiparticle.",
                createdAt: Date(timeIntervalSince1970: 20)
            )
        ]

        let plainText = EnchantedConversationCopyPayload.plainText(from: messages)
        #expect(plainText.contains("User: How many quarks are in the Standard Model?"))
        #expect(plainText.contains("Assistant: There are 6 quarks, each with an antiparticle."))

        let json = try #require(EnchantedConversationCopyPayload.json(from: messages))
        #expect(json.contains("How many quarks are in the Standard Model?"))
        #expect(json.contains("There are 6 quarks, each with an antiparticle."))

        let decoded = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        )
        #expect(decoded == [
            [
                "role": "user",
                "content": "How many quarks are in the Standard Model?"
            ],
            [
                "role": "assistant",
                "content": "There are 6 quarks, each with an antiparticle."
            ]
        ])
    }
}
