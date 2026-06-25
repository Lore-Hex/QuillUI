import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(Security)
import Security
#endif

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

// MARK: - PKCE

/// A PKCE (Proof Key for Code Exchange, RFC 7636) verifier/challenge pair.
///
/// Mirrors the JS SDK's `createOAuthPkcePair`: the verifier is
/// `base64url(32 random bytes)` and the challenge is
/// `base64url(SHA256(verifier))` with method `"S256"`.
public struct PKCEChallenge: Sendable, Equatable {
    /// The high-entropy `code_verifier` kept by the client and sent to
    /// `/auth/keys` during exchange. Never put this in the authorize URL.
    public let codeVerifier: String
    /// The `code_challenge` derived from the verifier (S256). Safe to put
    /// in the authorize URL.
    public let codeChallenge: String
    /// Always `"S256"` for the challenges this type produces.
    public let codeChallengeMethod: String

    public init(codeVerifier: String, codeChallenge: String, codeChallengeMethod: String = "S256") {
        self.codeVerifier = codeVerifier
        self.codeChallenge = codeChallenge
        self.codeChallengeMethod = codeChallengeMethod
    }

    /// Generate a fresh S256 PKCE pair. The verifier is 32 random bytes,
    /// base64url-encoded; the challenge is the base64url SHA-256 of the
    /// verifier's ASCII bytes (no padding), matching the JS SDK.
    ///
    /// - Parameter codeVerifier: Optional pre-chosen verifier (mainly for
    ///   tests / determinism). When `nil`, a cryptographically random one is
    ///   generated.
    public static func generate(codeVerifier: String? = nil) -> PKCEChallenge {
        let verifier = codeVerifier ?? OAuthCrypto.randomBase64URL(byteLength: 32)
        let challenge = OAuthCrypto.sha256Base64URL(verifier)
        return PKCEChallenge(codeVerifier: verifier, codeChallenge: challenge, codeChallengeMethod: "S256")
    }
}

/// Generate a random opaque `state` value (16 random bytes, base64url) used
/// to bind the authorize redirect to this client and defeat CSRF. Mirrors the
/// JS SDK's `randomOAuthState`.
public func randomOAuthState(byteLength: Int = 16) -> String {
    OAuthCrypto.randomBase64URL(byteLength: byteLength)
}

// MARK: - Crypto helpers (portable: Apple + Linux)

/// Internal crypto primitives shared by PKCE/state generation. Uses
/// `SecRandomCopyBytes` where available (Apple platforms) and a secure
/// system RNG fallback on Linux, plus CryptoKit/swift-crypto SHA-256.
enum OAuthCrypto {
    /// Fill `count` bytes with cryptographically-secure randomness.
    static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        #if canImport(Security)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return bytes
        }
        // Fall through to the system RNG if Security ever fails.
        #endif
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count {
            bytes[i] = UInt8.random(in: UInt8.min...UInt8.max, using: &rng)
        }
        return bytes
    }

    /// `byteLength` random bytes, base64url-encoded with padding stripped.
    static func randomBase64URL(byteLength: Int) -> String {
        base64URLEncode(Data(randomBytes(byteLength)))
    }

    /// base64url(SHA256(utf8(text))) with padding stripped — the S256
    /// transform applied to a PKCE verifier.
    static func sha256Base64URL(_ text: String) -> String {
        base64URLEncode(Data(sha256(Array(text.utf8))))
    }

    /// SHA-256 of `message`. Uses CryptoKit on Apple platforms; falls back to
    /// a small pure-Swift implementation on Linux (the package carries zero
    /// dependencies, so swift-crypto isn't available there).
    static func sha256(_ message: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(message)))
        #else
        return SHA256Pure.digest(message)
        #endif
    }

    /// Standard base64 → base64url: `+`→`-`, `/`→`_`, strip trailing `=`.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

#if !canImport(CryptoKit)
/// Minimal, dependency-free SHA-256 (FIPS 180-4). Only compiled on platforms
/// without CryptoKit (i.e. Linux) so the SDK can keep its zero-dependency
/// promise while still computing PKCE S256 challenges everywhere.
enum SHA256Pure {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]

        // Pre-processing (padding).
        var msg = message
        let bitLength = UInt64(message.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0x00) }
        for i in stride(from: 56, through: 0, by: -8) {
            msg.append(UInt8((bitLength >> UInt64(i)) & 0xff))
        }

        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

        // Process each 512-bit chunk.
        for chunkStart in stride(from: 0, to: msg.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = chunkStart + i * 4
                w[i] = (UInt32(msg[j]) << 24) | (UInt32(msg[j + 1]) << 16)
                     | (UInt32(msg[j + 2]) << 8) | UInt32(msg[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }

            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]

            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }

            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }

        var out = [UInt8]()
        out.reserveCapacity(32)
        for value in h {
            out.append(UInt8((value >> 24) & 0xff))
            out.append(UInt8((value >> 16) & 0xff))
            out.append(UInt8((value >> 8) & 0xff))
            out.append(UInt8(value & 0xff))
        }
        return out
    }
}
#endif

// MARK: - OAuth models

/// Verified identity attached to a delegated key, as returned by
/// `/auth/keys` (`identity`) and embedded in `/auth/userinfo`.
public struct OAuthIdentity: Codable, Sendable, Equatable {
    public var sub: String
    public var email: String?
    public var emailVerified: Bool?
    public var walletAddress: String?

    enum CodingKeys: String, CodingKey {
        case sub, email
        case emailVerified = "email_verified"
        case walletAddress = "wallet_address"
    }

    public init(sub: String, email: String? = nil, emailVerified: Bool? = nil, walletAddress: String? = nil) {
        self.sub = sub
        self.email = email
        self.emailVerified = emailVerified
        self.walletAddress = walletAddress
    }
}

/// Result of exchanging an authorization `code` for a delegated key.
/// Mirrors the `/auth/keys` response: `{ key, user_id, identity, data }`.
public struct OAuthToken: Codable, Sendable, Equatable {
    /// The delegated key, e.g. `"sk-tr-v1-..."`. Use as the Bearer token for
    /// subsequent gateway calls (including `/auth/userinfo`).
    public var key: String
    /// The owning user id, when the backend includes one.
    public var userId: String?
    /// Verified identity (`sub`/`email`/…), or `nil` for anonymous keys.
    public var identity: OAuthIdentity?

    enum CodingKeys: String, CodingKey {
        case key
        case userId = "user_id"
        case identity
        // `data` intentionally omitted: it's an opaque grab-bag the typed
        // model doesn't need to surface. Decoding ignores unknown keys.
    }

    public init(key: String, userId: String? = nil, identity: OAuthIdentity? = nil) {
        self.key = key
        self.userId = userId
        self.identity = identity
    }
}

/// The `data` payload returned by `GET /auth/userinfo`.
public struct UserInfo: Codable, Sendable, Equatable {
    public var sub: String
    public var email: String?
    public var emailVerified: Bool?
    public var walletAddress: String?
    public var workspaceId: String?
    /// ISO-8601 creation timestamp string (the backend returns a string here,
    /// not an epoch number).
    public var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case sub, email
        case emailVerified = "email_verified"
        case walletAddress = "wallet_address"
        case workspaceId = "workspace_id"
        case createdAt = "created_at"
    }

    public init(
        sub: String,
        email: String? = nil,
        emailVerified: Bool? = nil,
        walletAddress: String? = nil,
        workspaceId: String? = nil,
        createdAt: String? = nil
    ) {
        self.sub = sub
        self.email = email
        self.emailVerified = emailVerified
        self.walletAddress = walletAddress
        self.workspaceId = workspaceId
        self.createdAt = createdAt
    }
}

/// Envelope for `GET /auth/userinfo`: `{ "data": { ... } }`.
public struct UserInfoResponse: Codable, Sendable, Equatable {
    public var data: UserInfo
    public init(data: UserInfo) { self.data = data }
}

// MARK: - Authorize URL

/// Build the browser-redirect authorize URL for the TrustedRouter OAuth flow.
///
/// Matches the JS SDK's `oauthAuthorizeUrl` exactly: TrustedRouter uses
/// `callback_url` (NOT `redirect_uri`), there is no `client_id`/`response_type`/
/// `scope`, and the `state` is *embedded into* `callback_url` rather than sent
/// as its own top-level param. Only parameters that are set are included.
///
/// - Parameters:
///   - baseURL: API base, defaulting to the SDK default. Trailing slashes are
///     trimmed before joining `"/auth"`.
///   - callbackURL: REQUIRED redirect target. After approval the backend
///     redirects to `callbackURL?code=...&user_id=...` (plus the embedded
///     `state`).
///   - codeChallenge: PKCE S256 challenge.
///   - codeChallengeMethod: defaults to `"S256"` when a challenge is supplied.
///   - state: opaque CSRF token; embedded into `callback_url` when present.
/// - Throws: `TrustedRouterError.internalError` if `callbackURL` is missing/
///   invalid, or if a method is given without a challenge.
public func oauthAuthorizeURL(
    baseURL: String = TrustedRouterConstants.defaultAPIBaseURL,
    callbackURL: String,
    codeChallenge: String? = nil,
    codeChallengeMethod: String? = nil,
    keyLabel: String? = nil,
    limit: String? = nil,
    usageLimitType: String? = nil,
    expiresAt: String? = nil,
    spawnAgent: String? = nil,
    spawnCloud: String? = nil,
    state: String? = nil
) throws -> URL {
    if callbackURL.isEmpty {
        throw TrustedRouterError.internalError("callbackURL is required")
    }
    let method = codeChallengeMethod ?? (codeChallenge != nil ? "S256" : nil)
    if method != nil && codeChallenge == nil {
        throw TrustedRouterError.internalError("codeChallenge is required when codeChallengeMethod is set")
    }

    // Trim trailing slashes off the base, the same way the client does.
    var trimmedBase = baseURL
    while trimmedBase.hasSuffix("/") { trimmedBase.removeLast() }

    guard var components = URLComponents(string: "\(trimmedBase)/auth") else {
        throw TrustedRouterError.internalError("invalid baseURL: \(baseURL)")
    }

    // Embed state into the callback URL (matches JS `callbackUrlWithState`).
    let effectiveCallback = try state.map { try embedState($0, into: callbackURL) } ?? callbackURL

    var items: [URLQueryItem] = [URLQueryItem(name: "callback_url", value: effectiveCallback)]
    if let codeChallenge { items.append(URLQueryItem(name: "code_challenge", value: codeChallenge)) }
    if let method { items.append(URLQueryItem(name: "code_challenge_method", value: method)) }
    if let keyLabel { items.append(URLQueryItem(name: "key_label", value: keyLabel)) }
    if let limit { items.append(URLQueryItem(name: "limit", value: limit)) }
    if let usageLimitType { items.append(URLQueryItem(name: "usage_limit_type", value: usageLimitType)) }
    if let expiresAt { items.append(URLQueryItem(name: "expires_at", value: expiresAt)) }
    if let spawnAgent { items.append(URLQueryItem(name: "spawn_agent", value: spawnAgent)) }
    if let spawnCloud { items.append(URLQueryItem(name: "spawn_cloud", value: spawnCloud)) }

    components.queryItems = items
    guard let url = components.url else {
        throw TrustedRouterError.internalError("could not build authorize URL")
    }
    return url
}

/// Set/replace the `state` query param on `callbackURL`, mirroring the JS
/// `callbackUrlWithState`.
private func embedState(_ state: String, into callbackURL: String) throws -> String {
    guard var components = URLComponents(string: callbackURL) else {
        throw TrustedRouterError.internalError("invalid callbackURL: \(callbackURL)")
    }
    var items = components.queryItems ?? []
    items.removeAll { $0.name == "state" }
    items.append(URLQueryItem(name: "state", value: state))
    components.queryItems = items
    guard let result = components.url?.absoluteString else {
        throw TrustedRouterError.internalError("could not embed state into callbackURL")
    }
    return result
}

// MARK: - Exchange + userinfo (build on ALL platforms, incl. Linux)

/// Exchange an authorization `code` (plus the PKCE `code_verifier` kept from
/// the authorize step) for a delegated key.
///
/// `POST {baseURL}/auth/keys` with body `{code, code_verifier?, code_challenge_method?}`
/// and **no** Authorization header (public client). Mirrors the JS SDK's
/// `exchangeOAuthKey`.
public func exchangeOAuthKey(
    code: String,
    codeVerifier: String? = nil,
    codeChallengeMethod: String? = nil,
    baseURL: String = TrustedRouterConstants.defaultAPIBaseURL,
    urlSession: URLSession = .shared
) async throws -> OAuthToken {
    if code.isEmpty {
        throw TrustedRouterError.internalError("code is required")
    }
    // Public-client exchange: an empty apiKey suppresses the Authorization
    // header in the client's header builder.
    let client = try TrustedRouter(options: .init(apiKey: "", baseUrl: baseURL, urlSession: urlSession))
    var body: [String: Any] = ["code": code]
    if let codeVerifier { body["code_verifier"] = codeVerifier }
    if let codeChallengeMethod { body["code_challenge_method"] = codeChallengeMethod }
    return try await client.request(method: "POST", path: "/auth/keys", body: body)
}

/// Fetch the verified identity for `apiKey` (a delegated key).
///
/// `GET {baseURL}/auth/userinfo` with `Authorization: Bearer <apiKey>`.
/// Returns the inner `data` payload. Mirrors the JS SDK's `userInfo`.
public func fetchUserInfo(
    apiKey: String,
    baseURL: String = TrustedRouterConstants.defaultAPIBaseURL,
    urlSession: URLSession = .shared
) async throws -> UserInfo {
    if apiKey.isEmpty {
        throw TrustedRouterError.internalError("apiKey is required")
    }
    let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL, urlSession: urlSession))
    let envelope: UserInfoResponse = try await client.request(method: "GET", path: "/auth/userinfo")
    return envelope.data
}

// MARK: - High-level interactive helper (Apple platforms only)

#if canImport(AuthenticationServices)

/// High-level browser OAuth helper built on `ASWebAuthenticationSession`.
///
/// This is what Lore (macOS/iOS) uses: it generates PKCE, opens the authorize
/// URL in a system browser sheet, captures the redirect to your custom scheme,
/// validates `state`, and exchanges the `code` for an `OAuthToken`.
///
/// Linux builds (QuillUI cross-platform) get the pure PKCE/exchange/userinfo
/// functions above; this interactive helper is compiled only where
/// `AuthenticationServices` exists.
@available(macOS 10.15, iOS 13.0, tvOS 16.0, *)
@MainActor
public final class TrustedRouterOAuth {
    public let baseURL: String
    public let urlSession: URLSession

    /// Optional defaults forwarded into the authorize URL.
    public var keyLabel: String?
    public var limit: String?
    public var usageLimitType: String?
    public var expiresAt: String?
    public var spawnAgent: String?
    public var spawnCloud: String?

    public init(
        baseURL: String = TrustedRouterConstants.defaultAPIBaseURL,
        urlSession: URLSession = .shared,
        keyLabel: String? = nil,
        limit: String? = nil,
        usageLimitType: String? = nil,
        expiresAt: String? = nil,
        spawnAgent: String? = nil,
        spawnCloud: String? = nil
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.keyLabel = keyLabel
        self.limit = limit
        self.usageLimitType = usageLimitType
        self.expiresAt = expiresAt
        self.spawnAgent = spawnAgent
        self.spawnCloud = spawnCloud
    }

    /// Run the full interactive OAuth flow and return the delegated key +
    /// identity.
    ///
    /// - Parameters:
    ///   - callbackURL: Your redirect target, e.g. `"lore://oauth-callback"`.
    ///     The custom scheme is extracted and handed to
    ///     `ASWebAuthenticationSession` as the `callbackURLScheme`.
    ///   - presentationContextProvider: Anchors the auth sheet to a window
    ///     (required on macOS / iPad). The SDK keeps only a weak reference.
    ///   - prefersEphemeralWebBrowserSession: When `true`, the session does
    ///     not share cookies with Safari (forces a fresh login).
    public func authenticate(
        callbackURL: String,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding? = nil,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> OAuthToken {
        let pkce = PKCEChallenge.generate()
        let state = randomOAuthState()

        let authorizeURL = try oauthAuthorizeURL(
            baseURL: baseURL,
            callbackURL: callbackURL,
            codeChallenge: pkce.codeChallenge,
            codeChallengeMethod: pkce.codeChallengeMethod,
            keyLabel: keyLabel,
            limit: limit,
            usageLimitType: usageLimitType,
            expiresAt: expiresAt,
            spawnAgent: spawnAgent,
            spawnCloud: spawnCloud,
            state: state
        )

        guard let scheme = URL(string: callbackURL)?.scheme else {
            throw TrustedRouterError.internalError("callbackURL must include a scheme: \(callbackURL)")
        }

        let redirectURL = try await presentSession(
            authorizeURL: authorizeURL,
            callbackScheme: scheme,
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )

        let (code, returnedState) = try Self.parseCallback(redirectURL)
        guard returnedState == state else {
            throw TrustedRouterError.internalError("OAuth state mismatch (possible CSRF); aborting exchange")
        }

        return try await exchangeOAuthKey(
            code: code,
            codeVerifier: pkce.codeVerifier,
            codeChallengeMethod: pkce.codeChallengeMethod,
            baseURL: baseURL,
            urlSession: urlSession
        )
    }

    /// Convenience: authenticate, then fetch userinfo with the new key.
    public func authenticateAndFetchUserInfo(
        callbackURL: String,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding? = nil,
        prefersEphemeralWebBrowserSession: Bool = false
    ) async throws -> (token: OAuthToken, userInfo: UserInfo) {
        let token = try await authenticate(
            callbackURL: callbackURL,
            presentationContextProvider: presentationContextProvider,
            prefersEphemeralWebBrowserSession: prefersEphemeralWebBrowserSession
        )
        let info = try await fetchUserInfo(apiKey: token.key, baseURL: baseURL, urlSession: urlSession)
        return (token, info)
    }

    /// Parse the redirect URL the backend sent us, pulling out `code` (and the
    /// echoed `state`). Internal visibility so tests can exercise it without a
    /// live browser; `nonisolated` because it touches no actor state.
    nonisolated static func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TrustedRouterError.internalError("invalid OAuth callback URL")
        }
        let items = components.queryItems ?? []
        if let errorItem = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value
            throw TrustedRouterError.internalError("OAuth error: \(errorItem)\(desc.map { " — \($0)" } ?? "")")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw TrustedRouterError.internalError("OAuth callback missing 'code'")
        }
        let state = items.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    private func presentSession(
        authorizeURL: URL,
        callbackScheme: String,
        presentationContextProvider: ASWebAuthenticationPresentationContextProviding?,
        prefersEphemeralWebBrowserSession: Bool
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: TrustedRouterError.internalError("OAuth session failed: \(error.localizedDescription)"))
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: TrustedRouterError.internalError("OAuth session returned no callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
            if !session.start() {
                continuation.resume(throwing: TrustedRouterError.internalError("could not start ASWebAuthenticationSession"))
            }
        }
    }
}

#endif
