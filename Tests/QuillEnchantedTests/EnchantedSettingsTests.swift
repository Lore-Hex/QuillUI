import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import QuillEnchantedCore

@Suite("Enchanted settings")
struct EnchantedSettingsTests {
    @Test("system prompt and bearer token persist through the shared settings keys")
    func settingsPersistenceRoundTrip() throws {
        let suiteName = "quill.enchanted.settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let stored = EnchantedSettingsSnapshot(
            endpoint: "https://quill.local.lorehex.co",
            systemPrompt: "Answer tersely.",
            bearerToken: "local-key",
            pingInterval: "15"
        )
        stored.save(to: defaults)

        #expect(defaults.string(forKey: EnchantedSettingsStorage.systemPromptKey) == "Answer tersely.")
        #expect(defaults.string(forKey: EnchantedSettingsStorage.bearerTokenKey) == "local-key")
        #expect(defaults.string(forKey: EnchantedSettingsStorage.pingIntervalKey) == "15")
        #expect(EnchantedSettingsSnapshot.load(from: defaults) == stored)
    }

    @Test("ping interval parser defaults invalid values and disables non-positive values")
    func pingIntervalParsing() {
        #expect(EnchantedPingInterval.refreshDelayNanoseconds(from: "5") == 5_000_000_000)
        #expect(EnchantedPingInterval.refreshDelayNanoseconds(from: " 0.25 ") == 250_000_000)
        #expect(EnchantedPingInterval.refreshDelayNanoseconds(from: "not-a-number") == 5_000_000_000)
        #expect(EnchantedPingInterval.refreshDelayNanoseconds(from: "0") == nil)
        #expect(EnchantedPingInterval.refreshDelayNanoseconds(from: "-1") == nil)
    }

    @Test("Ollama requests include bearer authorization and system prompt")
    func requestIncludesBearerAuthorizationAndSystemPrompt() throws {
        let client = try OllamaClient(baseURL: "http://localhost:11434/", bearerToken: " local-key ")
        let fetchRequest = client.makeFetchModelsRequest()
        #expect(fetchRequest.value(forHTTPHeaderField: "Authorization") == "Bearer local-key")

        let chatRequest = try client.makeChatRequest(
            model: "llama3",
            messages: [
                ChatMessage(conversationID: "conversation", role: .user, content: "Hello")
            ],
            systemPrompt: "Answer tersely.",
            stream: true
        )

        #expect(chatRequest.url?.absoluteString == "http://localhost:11434/api/chat")
        #expect(chatRequest.value(forHTTPHeaderField: "Authorization") == "Bearer local-key")
        #expect(chatRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(chatRequest.httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(object["messages"] as? [[String: Any]])

        #expect(object["model"] as? String == "llama3")
        #expect(object["stream"] as? Bool == true)
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == ChatRole.system.rawValue)
        #expect(messages[0]["content"] as? String == "Answer tersely.")
        #expect(messages[1]["role"] as? String == ChatRole.user.rawValue)
        #expect(messages[1]["content"] as? String == "Hello")
    }
}
