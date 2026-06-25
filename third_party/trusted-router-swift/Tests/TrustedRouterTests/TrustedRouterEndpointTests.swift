import Foundation
import XCTest
@testable import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Mocking Infrastructure

class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var mockData: Data?
    nonisolated(unsafe) static var mockResponse: HTTPURLResponse?
    nonisolated(unsafe) static var mockError: Error?
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            self.client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            if let handler = MockURLProtocol.requestHandler {
                let (response, data) = try handler(request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            } else {
                if let response = MockURLProtocol.mockResponse {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = MockURLProtocol.mockData {
                    self.client?.urlProtocol(self, didLoad: data)
                }
            }
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A simple byte-level async sequence for testing.
struct SimpleAsyncBytes: AsyncSequence {
    typealias Element = UInt8
    let data: Data
    
    func makeAsyncIterator() -> Iterator {
        Iterator(data: data)
    }
    
    struct Iterator: AsyncIteratorProtocol {
        let data: Data
        var index = 0
        mutating func next() async throws -> UInt8? {
            guard index < data.count else { return nil }
            let byte = data[index]
            index += 1
            return byte
        }
    }
}

// MARK: - Tests

final class TrustedRouterEndpointTests: XCTestCase {
    var router: TrustedRouter!
    var session: URLSession!

    override func setUpWithError() throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)

        router = try TrustedRouter(options: TrustedRouterOptions(
            apiKey: "test_key",
            baseUrl: "https://test.local/v1",
            urlSession: session,
            workspaceId: "test_workspace"
        ))
    }

    // MARK: - Metadata Endpoints

    func testModelsEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://test.local/v1/models")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = """
            {"data": [{"id": "model-1", "owned_by": "quill"}]}
            """.data(using: .utf8)!
            return (response, json)
        }

        let response = try await router.models()
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "model-1")
    }
    
    func testProvidersEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/providers")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, "{\"data\": [{\"id\": \"openai\"}]}".data(using: .utf8)!)
        }
        let res = try await router.providers()
        XCTAssertEqual(res.data.first?.id, "openai")
    }

    func testCreditsEndpoint() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/credits")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, "{\"balance\": 10.5, \"currency\": \"USD\"}".data(using: .utf8)!)
        }
        let res = try await router.credits()
        XCTAssertEqual(res.balance, 10.5)
        XCTAssertEqual(res.currency, "USD")
    }

    // MARK: - Chat & Messages

    func testChatCompletions() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!
            let sseData = "data: {\"id\": \"chat-1\", \"object\": \"chat.completion.chunk\", \"choices\": [{\"index\": 0, \"delta\": {\"role\": \"assistant\", \"content\": \"Hello\"}}]}\n\ndata: {\"id\": \"chat-1\", \"object\": \"chat.completion.chunk\", \"choices\": [{\"index\": 0, \"delta\": {\"content\": \" world\"}, \"finish_reason\": \"stop\"}]}\n\n"
            return (response, sseData.data(using: .utf8)!)
        }

        let result = try await router.chatCompletions(messages: [["role": "user", "content": "Hi"]])
        XCTAssertEqual(result.id, "chat-1")
        XCTAssertEqual(result.choices.first?.message.content, "Hello world")
    }

    func testEmbeddings() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/embeddings")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = "{\"object\": \"list\", \"data\": [{\"index\": 0, \"embedding\": [0.1, 0.2]}], \"model\": \"text-emb\"}"
            return (response, json.data(using: .utf8)!)
        }
        let res = try await router.embeddings(model: "text-emb", input: "hello")
        XCTAssertEqual(res.model, "text-emb")
        XCTAssertEqual(res.data.first?.embedding, [0.1, 0.2])
    }

    // MARK: - Broadcast Destinations

    func testGetBroadcastDestinations() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/broadcast/destinations")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, "{\"data\": [{\"id\": \"dest-1\", \"type\": \"webhook\"}]}".data(using: .utf8)!)
        }
        let res = try await router.broadcastDestinations()
        XCTAssertEqual(res.data.first?.id, "dest-1")
    }

    func testCreateBroadcastDestination() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (response, "{\"id\": \"new-dest\", \"type\": \"slack\"}".data(using: .utf8)!)
        }
        let res = try await router.createBroadcastDestination(type: "slack", name: "Slack Dest")
        XCTAssertEqual(res.id, "new-dest")
        XCTAssertEqual(res.type, "slack")
    }

    // MARK: - Error Handling & Retries

    func testRateLimitErrorWithRetryAfter() async throws {
        var callCount = 0
        MockURLProtocol.requestHandler = { request in
            callCount += 1
            if callCount == 1 {
                let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "0.1"])!
                return (response, "{\"error\": {\"message\": \"Too many requests\"}}".data(using: .utf8)!)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (response, "{\"balance\": 5.0, \"currency\": \"USD\"}".data(using: .utf8)!)
            }
        }

        let res: CreditsResponse = try await router.credits()
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(res.balance, 5.0)
    }

    func testPermissionDeniedError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = "{\"error\": {\"message\": \"No access\"}}"
            return (response, json.data(using: .utf8)!)
        }

        do {
            _ = try await router.models()
            XCTFail("Should have thrown")
        } catch TrustedRouterError.permissionDenied(_, let message, _) {
            XCTAssertEqual(message, "No access")
        } catch {
            XCTFail("Threw wrong error: \(error)")
        }
    }
}
