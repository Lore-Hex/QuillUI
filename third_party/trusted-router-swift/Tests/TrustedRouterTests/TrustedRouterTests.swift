import XCTest
@testable import TrustedRouter

final class TrustedRouterTests: XCTestCase {
    
    func testRegionBaseUrl() throws {
        XCTAssertEqual(try regionBaseUrl(region: "us-central1"), "https://api.quillrouter.com/v1")
        XCTAssertEqual(try regionBaseUrl(region: "europe-west4"), "https://api-europe-west4.quillrouter.com/v1")
        
        XCTAssertThrowsError(try regionBaseUrl(region: "invalid-region")) { error in
            if case let TrustedRouterError.internalError(msg) = error {
                XCTAssertTrue(msg.contains("unknown TrustedRouter region"))
            } else {
                XCTFail("Expected internalError")
            }
        }
    }
    
    func testTrustedRouterInitialization() throws {
        let router = try TrustedRouter(options: TrustedRouterOptions(apiKey: "test-api-key"))
        XCTAssertEqual(router.apiKey, "test-api-key")
        XCTAssertEqual(router.baseUrl, "https://api.quillrouter.com/v1")
        
        let routerWithRegion = try TrustedRouter(options: TrustedRouterOptions(region: "europe-west4"))
        XCTAssertEqual(routerWithRegion.baseUrl, "https://api-europe-west4.quillrouter.com/v1")
        
        XCTAssertThrowsError(try TrustedRouter(options: TrustedRouterOptions(baseUrl: "http://example.com", region: "us-central1"))) { error in
            if case let TrustedRouterError.internalError(msg) = error {
                XCTAssertEqual(msg, "pass region OR baseUrl, not both")
            } else {
                XCTFail("Expected internalError")
            }
        }
    }
    
    func testHeadersAndMethod() async throws {
        // Since testing URLSession requires mocking, we can at least assert that
        // the client behaves properly when instantiating the request.
        let router = try TrustedRouter(options: TrustedRouterOptions(apiKey: "test-key", workspaceId: "ws-123"))
        
        XCTAssertEqual(router.apiKey, "test-key")
        XCTAssertEqual(router.workspaceId, "ws-123")
    }
}
