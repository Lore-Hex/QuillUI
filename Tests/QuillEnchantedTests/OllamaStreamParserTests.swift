import Testing
@testable import QuillEnchantedCore

@Suite("Ollama stream parser")
struct OllamaStreamParserTests {
    @Test("extracts streamed message content")
    func extractsContent() throws {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
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

    @Test("ignores empty lines")
    func ignoresEmptyLines() throws {
        #expect(try OllamaStreamParser.parseLine("   ") == nil)
    }
}
