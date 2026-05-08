import Testing
@testable import QuillEnchantedCore

@Suite("Ollama stream parser")
struct OllamaStreamParserTests {
    @Test("extracts streamed message content")
    func extractsContent() throws {
        let line = #"{"message":{"role":"assistant","content":"Hello"},"done":false}"#
        #expect(try OllamaStreamParser.parseLine(line) == .content("Hello"))
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
