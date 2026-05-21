import Testing
@testable import QuillEnchantedCore

@Suite("Ollama stream parser")
struct OllamaStreamParserTests {
    @Test("extracts streamed message content")
    func extractsContent() throws {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hello"))
    }

    @Test("extracts streamed message content without role metadata")
    func extractsContentWithoutRoleMetadata() throws {
        let line = #"{"message":{"content":"Hello"},"done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hello"))
    }

    @Test("extracts top-level response content")
    func extractsFallbackResponseContent() throws {
        let line = #"{"response":"Hello from response","done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hello from response"))
    }

    @Test("preserves whitespace-only streamed response chunks")
    func preservesWhitespaceResponseChunks() throws {
        let line = #"{"response":" ","done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content(" "))
    }

    @Test("prefers message content over fallback response content")
    func prefersMessageContent() throws {
        let line = #"{"message":{"role":"assistant","content":"chat"},"response":"fallback","done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("chat"))
    }

    @Test("recognizes done chunks")
    func recognizesDone() throws {
        let line = #"{"done":true}"#
        #expect(try OllamaStreamParser.parseLine(line) == .done)
    }

    @Test("recognizes done sentinels from SSE bridges")
    func recognizesSSEDoneSentinels() throws {
        #expect(try OllamaStreamParser.parseLine("[DONE]") == .done)
        #expect(try OllamaStreamParser.parseLine("data: [DONE]") == .done)
    }

    @Test("extracts server error chunks")
    func extractsServerErrorChunks() throws {
        let line = #"{"error":"model \"llama3\" not found"}"#
        #expect(try OllamaStreamParser.parseLine(line) == .error(#"model "llama3" not found"#))
    }

    @Test("extracts server error chunks from SSE bridges")
    func extractsSSEServerErrorChunks() throws {
        let line = #"data: {"error":"model \"llama3\" not found"}"#
        #expect(try OllamaStreamParser.parseLine(line) == .error(#"model "llama3" not found"#))
    }

    @Test("ignores metadata-only chunks")
    func ignoresMetadataOnlyChunks() throws {
        let line = #"{"created_at":"2026-05-20T00:00:00Z","done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == nil)
    }

    @Test("extracts streamed message content from SSE bridges")
    func extractsSSEContent() throws {
        let line = #"data: {"message":{"role":"assistant","content":"Hello"},"done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hello"))
    }

    @Test("preserves whitespace-only response chunks from SSE bridges")
    func preservesSSEResponseWhitespaceChunks() throws {
        let line = #"data: {"response":" ","done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content(" "))
    }

    @Test("ignores empty SSE bridge frames")
    func ignoresEmptySSEBridgeFrames() throws {
        #expect(try OllamaStreamParser.parseLine("data:   ") == nil)
        #expect(try OllamaStreamParser.parseLine(": keepalive") == nil)
    }

    @Test("trims surrounding stream whitespace")
    func trimsSurroundingStreamWhitespace() throws {
        let line = "\r\n  " + #"{"message":{"role":"assistant","content":"Hi"},"done":false}"# + "  \r\n"
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hi"))
    }

    @Test("ignores empty lines")
    func ignoresEmptyLines() throws {
        #expect(try OllamaStreamParser.parseLine("   ") == nil)
    }

    @Test("extracts non-stream message content")
    func extractsNonStreamMessageContent() throws {
        let body = #"{"message":{"role":"assistant","content":"Hello"},"done":true}"#
        #expect(try parseChatResponse(body) == "Hello")
    }

    @Test("extracts non-stream message content without role metadata")
    func extractsNonStreamMessageContentWithoutRoleMetadata() throws {
        let body = #"{"message":{"content":"Hello"},"done":true}"#
        #expect(try parseChatResponse(body) == "Hello")
    }

    @Test("extracts non-stream fallback response content")
    func extractsNonStreamFallbackResponseContent() throws {
        let body = #"{"response":"Hello from response","done":true}"#
        #expect(try parseChatResponse(body) == "Hello from response")
    }

    @Test("preserves whitespace-only non-stream content")
    func preservesWhitespaceOnlyNonStreamContent() throws {
        let body = #"{"message":{"role":"assistant","content":" "},"done":true}"#
        #expect(try parseChatResponse(body) == " ")
    }

    @Test("prefers non-stream message content over fallback response content")
    func prefersNonStreamMessageContent() throws {
        let body = #"{"message":{"role":"assistant","content":"chat"},"response":"fallback","done":true}"#
        #expect(try parseChatResponse(body) == "chat")
    }

    @Test("ignores metadata-only non-stream responses")
    func ignoresMetadataOnlyNonStreamResponses() throws {
        let body = #"{"created_at":"2026-05-20T00:00:00Z","done":true}"#
        #expect(try parseChatResponse(body) == "")
    }

    @Test("extracts non-stream server error responses")
    func extractsNonStreamServerErrorResponses() throws {
        let body = #"{"error":"model \"llama3\" not found"}"#

        do {
            _ = try parseChatResponse(body)
            Issue.record("Expected a server error")
        } catch OllamaClientError.server(let status, let message) {
            #expect(status == 500)
            #expect(message == #"model "llama3" not found"#)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("rejects malformed non-stream JSON")
    func rejectsMalformedNonStreamJSON() throws {
        do {
            _ = try parseChatResponse("{not-json")
            Issue.record("Expected a malformed response error")
        } catch OllamaClientError.malformedResponse(let body) {
            #expect(body.contains("not-json"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func parseChatResponse(_ json: String) throws -> String {
        let data = try #require(json.data(using: .utf8))
        return try OllamaChatResponseParser.parse(data)
    }
}

@Suite("Enchanted assistant response finalizer")
struct EnchantedAssistantResponseFinalizerTests {
    @Test("preserves exact non-empty Ollama payloads")
    func preservesExactNonEmptyOllamaPayloads() {
        #expect(EnchantedAssistantResponseFinalizer.finalContent(from: " ") == " ")
        #expect(EnchantedAssistantResponseFinalizer.finalContent(from: "\n") == "\n")
        #expect(EnchantedAssistantResponseFinalizer.finalContent(from: "  hello  ") == "  hello  ")
    }

    @Test("maps only truly empty Ollama payloads to fallback copy")
    func mapsOnlyTrulyEmptyOllamaPayloadsToFallbackCopy() {
        #expect(EnchantedAssistantResponseFinalizer.finalContent(from: "") == EnchantedCopy.emptyOllamaResponse)
    }
}
