import XCTest
@testable import TrustedRouter

/// Pin the JSON-key conventions for every typed model. Catches accidental
/// renames in `CodingKeys` (snake_case ↔ camelCase) and missing-field
/// regressions before they hit a real endpoint.
final class ModelDecodingTests: XCTestCase {

    func testModelInfoSnakeCaseOwnedBy() throws {
        let json = #"""
        {"id": "gpt-4o", "object": "model", "created": 1700000000, "owned_by": "openai"}
        """#
        let m = try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))
        XCTAssertEqual(m.id, "gpt-4o")
        XCTAssertEqual(m.ownedBy, "openai")
    }

    func testDataListGeneric() throws {
        let json = #"""
        {"data": [{"id": "a"}, {"id": "b"}]}
        """#
        let list = try JSONDecoder().decode(DataList<ProviderInfo>.self, from: Data(json.utf8))
        XCTAssertEqual(list.data.map(\.id), ["a", "b"])
    }

    func testCreditsResponseDouble() throws {
        let json = #"{"balance": 12.5, "currency": "USD"}"#
        let c = try JSONDecoder().decode(CreditsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(c.balance, 12.5)
        XCTAssertEqual(c.currency, "USD")
    }

    func testChatCompletionMapsSnakeCaseUsage() throws {
        let json = #"""
        {
          "id": "chat_1", "object": "chat.completion",
          "choices": [{"index": 0,
                       "message": {"role": "assistant", "content": "hi"},
                       "finish_reason": "stop"}],
          "usage": {"prompt_tokens": 100, "completion_tokens": 5, "total_tokens": 105}
        }
        """#
        let c = try JSONDecoder().decode(ChatCompletion.self, from: Data(json.utf8))
        XCTAssertEqual(c.id, "chat_1")
        XCTAssertEqual(c.choices.first?.message.content, "hi")
        XCTAssertEqual(c.choices.first?.finishReason, "stop")
        XCTAssertEqual(c.usage?.promptTokens, 100)
        XCTAssertEqual(c.usage?.totalTokens, 105)
    }

    func testChatCompletionChunkDeltaIsOptional() throws {
        let json = #"""
        {"id":"c1","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}
        """#
        let c = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
        XCTAssertEqual(c.choices.first?.delta?.role, "assistant")
        XCTAssertNil(c.choices.first?.delta?.content)
        XCTAssertNil(c.choices.first?.finishReason)
    }

    func testChatCompletionChunkEmptyChoices() throws {
        // The final "usage" chunk often arrives with empty choices.
        let json = #"{"id":"c1","object":"chat.completion.chunk","choices":[]}"#
        let c = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))
        XCTAssertTrue(c.choices.isEmpty)
    }

    func testEmbeddingResponse() throws {
        let json = #"""
        {"object":"list","model":"text-embedding-3-large",
         "data":[{"index":0,"object":"embedding","embedding":[0.1,0.2,0.3]}],
         "usage":{"prompt_tokens":5,"completion_tokens":0,"total_tokens":5}}
        """#
        let e = try JSONDecoder().decode(EmbeddingResponse.self, from: Data(json.utf8))
        XCTAssertEqual(e.model, "text-embedding-3-large")
        XCTAssertEqual(e.data.first?.embedding, [0.1, 0.2, 0.3])
        XCTAssertEqual(e.usage?.totalTokens, 5)
    }

    func testMessageResponseAnthropicShaped() throws {
        let json = #"""
        {"id":"msg_1","type":"message","role":"assistant",
         "content":[{"type":"text","text":"hi"}],
         "model":"claude-haiku-4-5","stop_reason":"end_turn",
         "usage":{"input_tokens":50,"output_tokens":10}}
        """#
        let m = try JSONDecoder().decode(MessageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(m.id, "msg_1")
        XCTAssertEqual(m.role, "assistant")
        XCTAssertEqual(m.stopReason, "end_turn")
        XCTAssertEqual(m.usage?.inputTokens, 50)
        XCTAssertEqual(m.usage?.outputTokens, 10)
        XCTAssertEqual(m.content.first?.text, "hi")
    }

    func testResponseObjectSnakeCaseCreatedAt() throws {
        let json = #"""
        {"id":"r_1","object":"response","created_at":1700000000,"status":"completed","model":"trustedrouter/auto"}
        """#
        let r = try JSONDecoder().decode(ResponseObject.self, from: Data(json.utf8))
        XCTAssertEqual(r.createdAt, 1700000000)
        XCTAssertEqual(r.status, "completed")
    }

    func testResponseInputTokens() throws {
        let json = #"{"input_tokens": 42, "total_tokens": 60}"#
        let t = try JSONDecoder().decode(ResponseInputTokens.self, from: Data(json.utf8))
        XCTAssertEqual(t.inputTokens, 42)
        XCTAssertEqual(t.totalTokens, 60)
    }

    func testBroadcastDestinationOptionalsHandled() throws {
        // Minimum shape: server may omit name/endpoint/method/enabled/include_content.
        let json = #"{"id": "b1", "type": "webhook"}"#
        let b = try JSONDecoder().decode(BroadcastDestination.self, from: Data(json.utf8))
        XCTAssertEqual(b.id, "b1")
        XCTAssertEqual(b.type, "webhook")
        XCTAssertNil(b.endpoint)
        XCTAssertNil(b.enabled)
        XCTAssertNil(b.includeContent)
    }

    func testEmptyResponseRoundTrips() throws {
        let json = "{}"
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResponse.self, from: Data(json.utf8)))
    }

    func testAuthSessionResponse() throws {
        let json = #"""
        {"authenticated":true,"user":{"id":"u_1","email":"alice@example.com"}}
        """#
        let s = try JSONDecoder().decode(AuthSessionResponse.self, from: Data(json.utf8))
        XCTAssertTrue(s.authenticated)
        XCTAssertEqual(s.user?.email, "alice@example.com")
    }

    func testActivityResponseDecodesMetadataDict() throws {
        let json = #"""
        {"activities":[
          {"id":"a1","created_at":1,"type":"req",
           "metadata":{"endpoint":"/v1/chat/completions","status":"200"}}
        ]}
        """#
        let a = try JSONDecoder().decode(ActivityResponse.self, from: Data(json.utf8))
        XCTAssertEqual(a.activities.first?.metadata?["endpoint"], "/v1/chat/completions")
    }

    func testCollectCompletionAggregatesContentDeltas() {
        // Cheap "no network" round-trip of the helper:
        // three delta chunks → one consolidated ChatCompletion with concatenated content.
        let chunks = [
            ChatCompletionChunk(
                id: "c1", object: nil, created: nil, model: "m",
                choices: [.init(index: 0, delta: .init(role: "assistant", content: "Hel"), finishReason: nil)]
            ),
            ChatCompletionChunk(
                id: "c1", object: nil, created: nil, model: "m",
                choices: [.init(index: 0, delta: .init(role: nil, content: "lo, "), finishReason: nil)]
            ),
            ChatCompletionChunk(
                id: "c1", object: nil, created: nil, model: "m",
                choices: [.init(index: 0, delta: .init(role: nil, content: "world."), finishReason: "stop")]
            ),
        ]
        let router = try! TrustedRouter(options: .init(apiKey: "x"))
        let full = router.collectCompletion(chunks: chunks)
        XCTAssertEqual(full.choices.first?.message.content, "Hello, world.")
        XCTAssertEqual(full.choices.first?.finishReason, "stop")
    }

    func testCollectCompletionFromEmptyChunks() {
        let router = try! TrustedRouter(options: .init(apiKey: "x"))
        let full = router.collectCompletion(chunks: [])
        XCTAssertEqual(full.choices.first?.message.content, "")
        XCTAssertEqual(full.choices.first?.finishReason, "stop")
    }
}
