import XCTest
@testable import TrustedRouter

final class TypedMessageTests: XCTestCase {

    func testUserConvenienceProducesExpectedJSON() throws {
        let m = ChatMessage.user("hello")
        let data = try JSONEncoder().encode(m)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"role\":\"user\""))
        XCTAssertTrue(str.contains("\"content\":\"hello\""))
        XCTAssertFalse(str.contains("name"), "name shouldn't serialize when nil")
    }

    func testToolMessageSerializesSnakeCaseToolCallId() throws {
        let m = ChatMessage.tool(callId: "call_42", content: #"{"ok":true}"#)
        let data = try JSONEncoder().encode(m)
        let str = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(str.contains("\"tool_call_id\":\"call_42\""))
        XCTAssertTrue(str.contains("\"role\":\"tool\""))
    }

    func testChatMessageDecodesSnakeCase() throws {
        let json = #"{"role":"tool","content":"ok","tool_call_id":"call_1"}"#
        let m = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertEqual(m.role, "tool")
        XCTAssertEqual(m.toolCallId, "call_1")
    }

    func testSystemAndAssistantConveniencesAreSymmetric() {
        XCTAssertEqual(ChatMessage.system("S").role, "system")
        XCTAssertEqual(ChatMessage.assistant("A").role, "assistant")
        XCTAssertEqual(ChatMessage.user("U").role, "user")
    }
}
