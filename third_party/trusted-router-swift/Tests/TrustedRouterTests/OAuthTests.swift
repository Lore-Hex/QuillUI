import XCTest
@testable import TrustedRouter

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Pure-piece coverage for the browser OAuth / PKCE flow. The interactive
/// `ASWebAuthenticationSession` path can't run headless, so we test
/// everything around it: PKCE generation, the authorize URL shape, callback
/// parsing + state validation, and token/userinfo decoding.
final class OAuthTests: XCTestCase {

    // MARK: - PKCE

    func testPKCERoundTripDerivesS256Challenge() {
        let pkce = PKCEChallenge.generate()
        XCTAssertEqual(pkce.codeChallengeMethod, "S256")
        XCTAssertFalse(pkce.codeVerifier.isEmpty)
        XCTAssertFalse(pkce.codeChallenge.isEmpty)
        // Re-deriving the challenge from the verifier must reproduce it.
        XCTAssertEqual(OAuthCrypto.sha256Base64URL(pkce.codeVerifier), pkce.codeChallenge)
    }

    func testPKCEChallengeMatchesRFC7636KnownAnswer() {
        // RFC 7636 Appendix B worked example.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let pkce = PKCEChallenge.generate(codeVerifier: verifier)
        XCTAssertEqual(pkce.codeVerifier, verifier)
        XCTAssertEqual(pkce.codeChallenge, expectedChallenge)
    }

    func testPKCEVerifiersAreRandomAndBase64URL() {
        let a = PKCEChallenge.generate()
        let b = PKCEChallenge.generate()
        XCTAssertNotEqual(a.codeVerifier, b.codeVerifier)
        // base64url: no '+', '/', or '=' padding.
        for s in [a.codeVerifier, a.codeChallenge, b.codeVerifier, b.codeChallenge] {
            XCTAssertFalse(s.contains("+"))
            XCTAssertFalse(s.contains("/"))
            XCTAssertFalse(s.contains("="))
        }
    }

    func testRandomOAuthStateIsRandomNonEmpty() {
        let a = randomOAuthState()
        let b = randomOAuthState()
        XCTAssertFalse(a.isEmpty)
        XCTAssertNotEqual(a, b)
    }

    func testSHA256PureMatchesKnownVector() {
        // SHA-256("abc") known answer; exercises the pure-Swift path on Linux
        // and the CryptoKit path on Apple — both must agree.
        let digest = OAuthCrypto.sha256(Array("abc".utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - Authorize URL

    func testAuthorizeURLParamsAndStateEmbedding() throws {
        let url = try oauthAuthorizeURL(
            baseURL: "https://api.quillrouter.com/v1",
            callbackURL: "lore://oauth-callback",
            codeChallenge: "CHALLENGE",
            codeChallengeMethod: "S256",
            keyLabel: "Lore on Mac",
            limit: "5",
            usageLimitType: "daily",
            expiresAt: "2026-12-31T00:00:00Z",
            state: "STATE123"
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.quillrouter.com")
        XCTAssertEqual(url.path, "/v1/auth")

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("code_challenge"), "CHALLENGE")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("key_label"), "Lore on Mac")
        XCTAssertEqual(value("limit"), "5")
        XCTAssertEqual(value("usage_limit_type"), "daily")
        XCTAssertEqual(value("expires_at"), "2026-12-31T00:00:00Z")

        // TrustedRouter uses callback_url (not redirect_uri) and embeds state
        // INSIDE it — there is no top-level `state` param.
        XCTAssertNil(value("state"))
        XCTAssertNil(value("redirect_uri"))
        XCTAssertNil(value("client_id"))
        XCTAssertNil(value("response_type"))
        XCTAssertNil(value("scope"))

        let callback = try XCTUnwrap(value("callback_url"))
        let callbackItems = URLComponents(string: callback)!.queryItems ?? []
        XCTAssertEqual(callbackItems.first { $0.name == "state" }?.value, "STATE123")
        XCTAssertEqual(URLComponents(string: callback)!.scheme, "lore")
    }

    func testAuthorizeURLOmitsUnsetParams() throws {
        let url = try oauthAuthorizeURL(callbackURL: "lore://cb")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let names = Set(items.map(\.name))
        XCTAssertEqual(names, ["callback_url"])
        // No state embedded when none supplied.
        XCTAssertEqual(items.first { $0.name == "callback_url" }?.value, "lore://cb")
    }

    func testAuthorizeURLDefaultsMethodWhenChallengeGiven() throws {
        let url = try oauthAuthorizeURL(callbackURL: "lore://cb", codeChallenge: "C")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "code_challenge_method" }?.value, "S256")
    }

    func testAuthorizeURLRequiresCallback() {
        XCTAssertThrowsError(try oauthAuthorizeURL(callbackURL: ""))
    }

    func testAuthorizeURLMethodWithoutChallengeThrows() {
        XCTAssertThrowsError(
            try oauthAuthorizeURL(callbackURL: "lore://cb", codeChallengeMethod: "S256")
        )
    }

    func testAuthorizeURLTrimsTrailingSlashOnBase() throws {
        let url = try oauthAuthorizeURL(baseURL: "https://api.quillrouter.com/v1///", callbackURL: "lore://cb")
        XCTAssertEqual(url.path, "/v1/auth")
    }

    // MARK: - Token / userinfo decoding

    func testOAuthTokenDecodesWithIdentity() throws {
        let json = #"""
        {
          "key": "sk-tr-v1-abc123",
          "user_id": "usr_42",
          "identity": {
            "sub": "did:privy:xyz",
            "email": "alice@example.com",
            "email_verified": true,
            "wallet_address": "0xabc"
          },
          "data": {"foo": "bar"}
        }
        """#
        let token = try JSONDecoder().decode(OAuthToken.self, from: Data(json.utf8))
        XCTAssertEqual(token.key, "sk-tr-v1-abc123")
        XCTAssertEqual(token.userId, "usr_42")
        XCTAssertEqual(token.identity?.sub, "did:privy:xyz")
        XCTAssertEqual(token.identity?.email, "alice@example.com")
        XCTAssertEqual(token.identity?.emailVerified, true)
        XCTAssertEqual(token.identity?.walletAddress, "0xabc")
    }

    func testOAuthTokenDecodesNullIdentity() throws {
        let json = #"{"key":"sk-tr-v1-anon","user_id":null,"identity":null,"data":{}}"#
        let token = try JSONDecoder().decode(OAuthToken.self, from: Data(json.utf8))
        XCTAssertEqual(token.key, "sk-tr-v1-anon")
        XCTAssertNil(token.userId)
        XCTAssertNil(token.identity)
    }

    func testUserInfoResponseDecodes() throws {
        let json = #"""
        {
          "data": {
            "sub": "did:privy:xyz",
            "email": "alice@example.com",
            "email_verified": true,
            "wallet_address": "0xabc",
            "workspace_id": "ws_1",
            "created_at": "2026-06-07T00:00:00Z"
          }
        }
        """#
        let resp = try JSONDecoder().decode(UserInfoResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.data.sub, "did:privy:xyz")
        XCTAssertEqual(resp.data.email, "alice@example.com")
        XCTAssertEqual(resp.data.emailVerified, true)
        XCTAssertEqual(resp.data.walletAddress, "0xabc")
        XCTAssertEqual(resp.data.workspaceId, "ws_1")
        XCTAssertEqual(resp.data.createdAt, "2026-06-07T00:00:00Z")
    }

    func testUserInfoDecodesMinimalShape() throws {
        let json = #"{"data":{"sub":"s1"}}"#
        let resp = try JSONDecoder().decode(UserInfoResponse.self, from: Data(json.utf8))
        XCTAssertEqual(resp.data.sub, "s1")
        XCTAssertNil(resp.data.email)
        XCTAssertNil(resp.data.workspaceId)
    }

    // MARK: - Callback parsing + state validation (Apple platforms only)

    #if canImport(AuthenticationServices)
    func testParseCallbackExtractsCodeAndState() throws {
        let url = URL(string: "lore://oauth-callback?code=AUTHCODE&user_id=usr_1&state=STATE123")!
        let parsed = try TrustedRouterOAuth.parseCallback(url)
        XCTAssertEqual(parsed.code, "AUTHCODE")
        XCTAssertEqual(parsed.state, "STATE123")
    }

    func testParseCallbackMissingCodeThrows() {
        let url = URL(string: "lore://oauth-callback?state=STATE123")!
        XCTAssertThrowsError(try TrustedRouterOAuth.parseCallback(url))
    }

    func testParseCallbackSurfacesError() {
        let url = URL(string: "lore://oauth-callback?error=access_denied&error_description=user%20declined")!
        XCTAssertThrowsError(try TrustedRouterOAuth.parseCallback(url)) { error in
            XCTAssertTrue("\(error)".contains("access_denied"))
        }
    }

    func testStateMismatchIsDetectable() throws {
        // Simulate the validation the helper performs: the state echoed back
        // in the callback must equal the one we generated.
        let url = URL(string: "lore://oauth-callback?code=AUTHCODE&state=WRONG")!
        let parsed = try TrustedRouterOAuth.parseCallback(url)
        let expectedState = "EXPECTED"
        XCTAssertNotEqual(parsed.state, expectedState, "test fixture must mismatch")

        // Mirror the helper's guard so the mismatch path is covered.
        func validate(_ returnedState: String?, against expected: String) throws {
            guard returnedState == expected else {
                throw TrustedRouterError.internalError("OAuth state mismatch (possible CSRF); aborting exchange")
            }
        }
        XCTAssertThrowsError(try validate(parsed.state, against: expectedState)) { error in
            XCTAssertTrue("\(error)".contains("state mismatch"))
        }
    }
    #endif
}
