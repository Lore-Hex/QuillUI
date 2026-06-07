import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Combine
import OllamaKit
import Testing

@Suite("OllamaKit compatibility")
struct OllamaKitTests {
    @Test("chat publisher starts the HTTP request and publishes decoded stream values", .timeLimit(.minutes(1)))
    func chatPublisherStartsHTTPRequest() async throws {
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

        // Await the publisher's completion deterministically rather than racing a
        // fixed wall-clock deadline. Under the full parallel `swift test` suite on
        // a few-core CI runner, the unstructured Task that runs `performChat` can
        // be scheduled later than a 2-second poll would tolerate, which made this
        // test fail in CI even though the publisher itself is correct (it passes
        // in isolation and under load). Awaiting the real completion is robust to
        // scheduler pressure; the `.timeLimit` trait is a safety net so a genuine
        // stall fails cleanly instead of hanging the job.
        let lock = NSLock()
        var values: [OKChatResponse] = []
        var cancellables = Set<AnyCancellable>()
        let outcome: Result<Void, Error> = await withCheckedContinuation { continuation in
            var resumed = false
            kit.chat(data: request)
                .sink(receiveCompletion: { completion in
                    let result: Result<Void, Error>? = lock.withLock {
                        guard !resumed else { return nil }
                        resumed = true
                        switch completion {
                        case .finished: return .success(())
                        case .failure(let error): return .failure(error)
                        }
                    }
                    if let result { continuation.resume(returning: result) }
                }, receiveValue: { response in
                    lock.withLock { values.append(response) }
                })
                .store(in: &cancellables)
        }

        // `withExtendedLifetime` keeps the subscription alive across the await.
        withExtendedLifetime(cancellables) {
            if case .failure(let error) = outcome {
                Issue.record("chat publisher completed with failure: \(error)")
            }
        }

        let capturedValues = lock.withLock { values }
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
