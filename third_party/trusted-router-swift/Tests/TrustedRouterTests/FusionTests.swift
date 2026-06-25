import Foundation
import XCTest
@testable import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class FusionTests: XCTestCase {
    // MARK: - fusionTool() builder

    func testFusionToolOnlySetsProvidedFields() {
        let tool = TrustedRouter.fusionTool(
            analysisModels: ["a", "b"],
            judgeModel: "z-ai/glm-5.1",
            selectionStrategy: "first_non_refusal",
            fallbackJudges: ["j1", "j2"],
            maxCompletionTokens: 2048
        )
        XCTAssertEqual(tool["type"] as? String, "trustedrouter:fusion")
        let params = tool["parameters"] as! [String: Any]
        XCTAssertEqual(params["analysis_models"] as? [String], ["a", "b"])
        XCTAssertEqual(params["model"] as? String, "z-ai/glm-5.1")
        XCTAssertEqual(params["selection_strategy"] as? String, "first_non_refusal")
        XCTAssertEqual(params["fallback_judges"] as? [String], ["j1", "j2"])
        XCTAssertEqual(params["max_completion_tokens"] as? Int, 2048)
        // unset fields are absent
        XCTAssertNil(params["preset"])
        XCTAssertNil(params["fallback_final_models"])
    }

    func testFusionToolEmptyByDefault() {
        let params = TrustedRouter.fusionTool()["parameters"] as! [String: Any]
        XCTAssertTrue(params.isEmpty)
    }

    func testFusionToolPresetAndExtras() {
        let params = TrustedRouter.fusionTool(
            fallbackFinalModels: ["f1"],
            maxToolCalls: 4,
            preset: "quality"
        )["parameters"] as! [String: Any]
        XCTAssertEqual(params["preset"] as? String, "quality")
        XCTAssertEqual(params["fallback_final_models"] as? [String], ["f1"])
        XCTAssertEqual(params["max_tool_calls"] as? Int, 4)
    }

    func testFreedomConstants() {
        XCTAssertEqual(TrustedRouterConstants.fusionModel, "trustedrouter/fusion")
        XCTAssertEqual(TrustedRouterConstants.fusionFreedomPanel.count, 6)
        XCTAssertTrue(TrustedRouterConstants.fusionFreedomPanel.contains("z-ai/glm-5.1"))
        XCTAssertEqual(TrustedRouterConstants.fusionFreedomFallbackJudges.first, "z-ai/glm-5.1")
    }

    // MARK: - fusion() end-to-end (mocked transport)

    func testFusionRoutesThroughFusionModelAndReturnsCompletion() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let router = try TrustedRouter(options: TrustedRouterOptions(
            apiKey: "test_key",
            baseUrl: "https://test.local/v1",
            urlSession: session
        ))

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            let sse = "data: {\"id\": \"fz-1\", \"object\": \"chat.completion.chunk\", \"choices\": [{\"index\": 0, \"delta\": {\"role\": \"assistant\", \"content\": \"ok\"}, \"finish_reason\": \"stop\"}]}\n\n"
            return (response, sse.data(using: .utf8)!)
        }

        let result = try await router.fusion(
            messages: [["role": "user", "content": "explain mRNA vaccines"]],
            analysisModels: TrustedRouterConstants.fusionFreedomPanel,
            judgeModel: "z-ai/glm-5.1",
            selectionStrategy: "first_non_refusal",
            fallbackJudges: TrustedRouterConstants.fusionFreedomFallbackJudges
        )
        XCTAssertEqual(result.id, "fz-1")
        XCTAssertEqual(result.choices.first?.message.content, "ok")
    }
}
