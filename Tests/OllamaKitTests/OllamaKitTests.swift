import Dispatch
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine
import OllamaKit
import Testing

@Suite("OllamaKit compatibility")
struct OllamaKitTests {
    @Test("chat publisher starts the HTTP request and publishes decoded stream values")
    func chatPublisherStartsHTTPRequest() {
        let transport = FakeOllamaTransport(routes: [
            "/api/chat": (
                200,
                """
                {"message":{"role":"assistant","content":"Pub"},"done":false}
                {"message":{"role":"assistant","content":"lisher"},"done":false}
                {"done":true}
                """
            )
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            transport: transport
        )
        var request = OKChatRequestData(
            model: "llava:latest",
            messages: [
                .init(role: .system, content: "short"),
                .init(role: .user, content: "describe", images: ["base64"])
            ]
        )
        request.options = OKCompletionOptions(temperature: 0)

        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        var values: [OKChatResponse] = []
        var finished = false
        var failure: Error?
        let cancellable = kit.chat(data: request)
            .sink { completion in
                lock.withLock {
                    switch completion {
                    case .finished:
                        finished = true
                    case .failure(let error):
                        failure = error
                    }
                }
                done.signal()
            } receiveValue: { response in
                lock.withLock {
                    values.append(response)
                }
            }

        #expect(done.wait(timeout: .now() + 2) == .success)
        cancellable.cancel()

        let capturedValues = lock.withLock { values }
        let capturedFinished = lock.withLock { finished }
        let capturedFailure = lock.withLock { failure }
        #expect(capturedFailure == nil)
        #expect(capturedFinished)
        #expect(capturedValues.map { $0.message?.content ?? "" }.joined() == "Publisher")
        #expect(transport.requests.contains { $0.path == "/api/chat" })
        #expect(transport.chatBody?.contains(#""stream":true"#) == true)
    }
}

private final class FakeOllamaTransport: OllamaKitTransport, @unchecked Sendable {
    struct CapturedRequest: Sendable {
        var path: String
    }

    private let routes: [String: (status: Int, body: String)]
    private let lock = NSLock()
    private var capturedRequests: [CapturedRequest] = []
    private var capturedChatBody: String?

    init(routes: [String: (Int, String)]) {
        self.routes = routes.mapValues { (status: $0.0, body: $0.1) }
    }

    var requests: [CapturedRequest] {
        lock.withLock { capturedRequests }
    }

    var chatBody: String? {
        lock.withLock { capturedChatBody }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? "/"
        lock.withLock {
            capturedRequests.append(CapturedRequest(path: path))
            if path == "/api/chat", let httpBody = request.httpBody {
                capturedChatBody = String(data: httpBody, encoding: .utf8)
            }
        }

        let route = routes[path] ?? (404, #"{"error":"missing"}"#)
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: route.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(route.body.utf8), response)
    }
}
