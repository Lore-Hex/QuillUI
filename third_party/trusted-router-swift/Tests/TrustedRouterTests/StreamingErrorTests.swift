import XCTest
@testable import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Streaming endpoints that 4xx/5xx out before any SSE frames are sent
/// should surface the server's actual error body, not a generic message.
final class StreamingErrorTests: XCTestCase {

    func testChatCompletionsChunks401ContainsServerMessage() async throws {
        ErrorBodyProtocol.scripted = (401, #"{"error":{"message":"bad api key"}}"#)
        let router = try TrustedRouter(options: makeOptions())
        do {
            _ = try await router.chatCompletionsChunks(
                messages: [["role": "user", "content": "hi"]]
            )
            XCTFail("expected authentication error")
        } catch TrustedRouterError.authentication(let code, let msg, _) {
            XCTAssertEqual(code, 401)
            XCTAssertEqual(msg, "bad api key",
                           "the server-side message must propagate through the streaming error path")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testResponsesEvents403ContainsServerMessage() async throws {
        ErrorBodyProtocol.scripted = (403, #"{"error":{"message":"workspace lacks billing"}}"#)
        let router = try TrustedRouter(options: makeOptions())
        do {
            _ = try await router.responsesEvents(input: "hi")
            XCTFail("expected permissionDenied")
        } catch TrustedRouterError.permissionDenied(_, let msg, _) {
            XCTAssertEqual(msg, "workspace lacks billing")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    private func makeOptions() -> TrustedRouterOptions {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [ErrorBodyProtocol.self]
        return TrustedRouterOptions(
            apiKey: "key",
            baseUrl: "https://test.local/v1",
            urlSession: URLSession(configuration: cfg),
            maxRetries: 0
        )
    }
}

private final class ErrorBodyProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var scripted: (Int, String) = (500, "")
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (code, body) = Self.scripted
        let resp = HTTPURLResponse(url: request.url!, statusCode: code,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
