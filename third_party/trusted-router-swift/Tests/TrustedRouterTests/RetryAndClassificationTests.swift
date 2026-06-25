import XCTest
@testable import TrustedRouter

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Status-code → `TrustedRouterError` classification, and the retry loop's
/// honoring of Retry-After + exponential backoff.
final class RetryAndClassificationTests: XCTestCase {

    private var router: TrustedRouter!

    override func setUpWithError() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SequenceProtocol.self]
        SequenceProtocol.reset()
        router = try TrustedRouter(options: .init(
            apiKey: "test_key",
            baseUrl: "https://test.local/v1",
            urlSession: URLSession(configuration: config),
            maxRetries: 2
        ))
    }

    func test401MapsToAuthentication() async {
        SequenceProtocol.scripted = [(401, #"{"error":{"message":"bad key"}}"#, nil)]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected auth error")
        } catch TrustedRouterError.authentication(let code, let msg, _) {
            XCTAssertEqual(code, 401)
            XCTAssertEqual(msg, "bad key")
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test403MapsToPermissionDenied() async {
        SequenceProtocol.scripted = [(403, #"{"error":{"message":"forbidden"}}"#, nil)]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected permission error")
        } catch TrustedRouterError.permissionDenied(let code, _, _) {
            XCTAssertEqual(code, 403)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test404MapsToNotFound() async {
        SequenceProtocol.scripted = [(404, #"{"error":{"message":"gone"}}"#, nil)]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected notFound")
        } catch TrustedRouterError.notFound { /* expected */ }
        catch { XCTFail("wrong error: \(error)") }
    }

    func test501MapsToEndpointNotSupportedAfterRetriesExhaust() async {
        // 501 is in the retryable band (≥ 500) so it gets retried; after
        // maxRetries=2 → 3 attempts, the final attempt classifies.
        SequenceProtocol.scripted = Array(repeating: (501, "", nil as String?), count: 5)
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected endpointNotSupported")
        } catch TrustedRouterError.endpointNotSupported { /* expected */ }
        catch { XCTFail("wrong error: \(error)") }
    }

    func test400Range4xxMapsToBadRequest() async {
        SequenceProtocol.scripted = [(400, #"{"error":{"message":"bad"}}"#, nil)]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected badRequest")
        } catch TrustedRouterError.badRequest { /* expected */ }
        catch { XCTFail("wrong error: \(error)") }
    }

    func test429MapsToRateLimitAndCarriesRetryAfter() async throws {
        // Five attempts: maxRetries=2 means we should try at most 3 times.
        // Script enough 429s that retries don't recover — confirm rate-limit
        // surfaces with the Retry-After honored.
        SequenceProtocol.scripted = Array(
            repeating: (429, "rate limited", "1"),
            count: 5
        ).map { ($0.0, $0.1, $0.2) }
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected rateLimit")
        } catch TrustedRouterError.rateLimit(_, _, _, let retryAfter) {
            XCTAssertEqual(retryAfter, 1.0)
        } catch { XCTFail("wrong error: \(error)") }
    }

    func test500IsRetriedAndCanSucceed() async throws {
        // First two attempts 503, third returns success — must be retried.
        SequenceProtocol.scripted = [
            (503, #"{"error":{"message":"down"}}"#, nil),
            (503, #"{"error":{"message":"still down"}}"#, nil),
            (200, #"{}"#, nil),
        ]
        let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
        XCTAssertEqual(SequenceProtocol.served, 3, "should have made all three attempts")
    }

    func test4xxOutsideKnownCodesDoesNotRetry() async {
        // 422 isn't in the retryable set (only 429 and ≥500). Should fail-fast.
        SequenceProtocol.scripted = [
            (422, #"{"error":{"message":"unprocessable"}}"#, nil),
            (200, #"{}"#, nil),
        ]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected badRequest")
        } catch TrustedRouterError.badRequest {
            XCTAssertEqual(SequenceProtocol.served, 1, "must not retry 422")
        } catch { XCTFail("wrong error: \(error)") }
    }

    func testGenericErrorMessageFallbackUsesStringBody() async {
        SequenceProtocol.scripted = [(400, "plain string error", nil)]
        do {
            let _: EmptyResponse = try await router.request(method: "GET", path: "/x")
            XCTFail("expected error")
        } catch TrustedRouterError.badRequest(_, let msg, _) {
            XCTAssertEqual(msg, "plain string error")
        } catch { XCTFail("wrong error: \(error)") }
    }
}

/// URLProtocol that consumes a scripted list of responses, one per request.
/// Each entry is `(statusCode, body, retryAfterSeconds?)`.
private final class SequenceProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var scripted: [(Int, String, String?)] = []
    nonisolated(unsafe) static var served: Int = 0

    static func reset() {
        scripted = []
        served = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let idx = Self.served
        Self.served += 1
        let (code, body, retryAfter) = (idx < Self.scripted.count) ? Self.scripted[idx] : (500, "out of script", nil)
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        let resp = HTTPURLResponse(url: request.url!, statusCode: code,
                                   httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

