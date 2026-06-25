import XCTest
@testable import TrustedRouter

/// Unit coverage for the cross-platform loopback OAuth helper. The HTTP listener
/// itself binds a real socket, so we don't exercise it here (no live socket in a
/// unit test); instead we test the *pure* request-line parser and the
/// authorize-URL / state-validation logic the actor wraps.
final class OAuthLoopbackTests: XCTestCase {

    // MARK: - Request-line parsing (pure, no sockets)

    func testParseRequestLineExtractsCodeAndState() throws {
        let line = "GET /callback?code=AUTHCODE&state=STATE123 HTTP/1.1"
        let parsed = try OAuthLoopback.parseRequestLine(line)
        XCTAssertEqual(parsed.code, "AUTHCODE")
        XCTAssertEqual(parsed.state, "STATE123")
    }

    func testParseRequestLineIgnoresExtraQueryParams() throws {
        let line = "GET /callback?user_id=usr_1&code=ABC&state=XYZ&foo=bar HTTP/1.1"
        let parsed = try OAuthLoopback.parseRequestLine(line)
        XCTAssertEqual(parsed.code, "ABC")
        XCTAssertEqual(parsed.state, "XYZ")
    }

    func testParseRequestLinePercentDecodesValues() throws {
        // URLComponents decodes percent-escapes in queryItems.
        let line = "GET /callback?code=a%2Bb%2Fc&state=s%20t HTTP/1.1"
        let parsed = try OAuthLoopback.parseRequestLine(line)
        XCTAssertEqual(parsed.code, "a+b/c")
        XCTAssertEqual(parsed.state, "s t")
    }

    func testParseRequestLineCodeWithoutStateReturnsNilState() throws {
        let line = "GET /callback?code=ONLYCODE HTTP/1.1"
        let parsed = try OAuthLoopback.parseRequestLine(line)
        XCTAssertEqual(parsed.code, "ONLYCODE")
        XCTAssertNil(parsed.state)
    }

    func testParseRequestLineMissingCodeThrows() {
        let line = "GET /callback?state=STATE123 HTTP/1.1"
        XCTAssertThrowsError(try OAuthLoopback.parseRequestLine(line)) { error in
            XCTAssertTrue("\(error)".contains("missing 'code'"))
        }
    }

    func testParseRequestLineSurfacesOAuthError() {
        let line = "GET /callback?error=access_denied&error_description=user%20declined HTTP/1.1"
        XCTAssertThrowsError(try OAuthLoopback.parseRequestLine(line)) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("access_denied"))
            XCTAssertTrue(text.contains("user declined"))
        }
    }

    func testParseRequestLineMalformedThrows() {
        XCTAssertThrowsError(try OAuthLoopback.parseRequestLine("GET")) { error in
            XCTAssertTrue("\(error)".contains("malformed"))
        }
    }

    func testParseRequestLineHandlesRootCallbackNoQueryAsMissingCode() {
        // A bare GET /callback (no query) has no code → should throw.
        XCTAssertThrowsError(try OAuthLoopback.parseRequestLine("GET /callback HTTP/1.1"))
    }

    // MARK: - Authorize URL shape (uses the actor's lazy PKCE/state)

    func testAuthorizeURLUsesLoopbackCallbackWithPKCEAndState() async throws {
        let loopback = OAuthLoopback(
            baseURL: "https://api.quillrouter.com/v1",
            keyLabel: "Lore Games",
            limit: "5"
        )
        let url = try await loopback.authorizeURL()

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.quillrouter.com")
        XCTAssertEqual(url.path, "/v1/auth")

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertFalse((value("code_challenge") ?? "").isEmpty)
        XCTAssertEqual(value("key_label"), "Lore Games")
        XCTAssertEqual(value("limit"), "5")
        // No top-level state — TrustedRouter embeds it inside callback_url.
        XCTAssertNil(value("state"))

        let callback = try XCTUnwrap(value("callback_url"))
        let callbackComponents = URLComponents(string: callback)!
        XCTAssertEqual(callbackComponents.scheme, "http")
        XCTAssertEqual(callbackComponents.host, "localhost")
        XCTAssertEqual(callbackComponents.port, 3000)
        XCTAssertEqual(callbackComponents.path, "/callback")
        let embeddedState = callbackComponents.queryItems?.first { $0.name == "state" }?.value
        XCTAssertFalse((embeddedState ?? "").isEmpty)
    }

    func testAuthorizeURLIsStableAcrossCallsForOneInstance() async throws {
        // The PKCE pair + state are generated lazily ONCE so the URL the app
        // opens matches the state validated in waitForCallback.
        let loopback = OAuthLoopback()
        let first = try await loopback.authorizeURL()
        let second = try await loopback.authorizeURL()
        XCTAssertEqual(first, second)
    }

    func testLoopbackConstants() {
        XCTAssertEqual(OAuthLoopback.port, 3000)
        XCTAssertEqual(OAuthLoopback.callbackURL, "http://localhost:3000/callback")
        XCTAssertEqual(OAuthLoopback.callbackPath, "/callback")
    }

    // MARK: - HTTP response shaping (pure)

    func testSuccessResponseIsWellFormedHTTP() {
        let response = OAuthLoopback.successResponse()
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(response.contains("Content-Type: text/html"))
        XCTAssertTrue(response.contains("Signed in with TrustedRouter"))
        // Content-Length must match the body after the blank line.
        let parts = response.components(separatedBy: "\r\n\r\n")
        let body = parts.dropFirst().joined(separator: "\r\n\r\n")
        XCTAssertTrue(response.contains("Content-Length: \(body.utf8.count)"))
    }

    func testNotFoundResponseIs404() {
        let response = OAuthLoopback.notFoundResponse()
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    }
}
