import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

// MARK: - Loopback (desktop / cross-platform) OAuth flow

/// A cross-platform "loopback redirect" OAuth helper for GUI toolkits that are
/// **not** native AppKit/UIKit — QuillUI/GTK, Electron, CLIs, etc. — and so
/// cannot use `ASWebAuthenticationSession` (see `TrustedRouterOAuth`).
///
/// The flow:
/// 1. The caller asks for `authorizeURL` (which lazily builds a fresh PKCE pair
///    + `state` and a `callback_url=http://localhost:3000/callback`).
/// 2. The **app** opens that URL in the system browser (the SDK never shells
///    out to a browser itself — keeping it dependency-free and testable).
/// 3. The app calls `waitForCallback()`, which binds a minimal one-shot HTTP
///    listener on `127.0.0.1:3000`, accepts a single `GET /callback?code=&state=`,
///    validates `state`, replies with a tiny "signed in" HTML page, then
///    exchanges the `code` for an ``OAuthToken`` and returns it.
///
/// Built purely on POSIX sockets (`Glibc` on Linux, `Darwin` on macOS) — **no**
/// `Network.framework`, **no** `AuthenticationServices` — so it compiles and
/// runs everywhere the SDK does.
///
/// Port `3000` on `127.0.0.1`/`localhost` is allowlisted by the TrustedRouter
/// backend for exactly this loopback use.
public actor OAuthLoopback {
    /// The fixed loopback port the backend allowlists for desktop flows.
    public static let port: UInt16 = 3000
    /// The fixed loopback callback URL used for desktop flows.
    public static let callbackURL = "http://localhost:3000/callback"
    /// The request path the listener answers (everything else 404s).
    public static let callbackPath = "/callback"

    public let baseURL: String
    public let urlSession: URLSession

    /// Optional defaults forwarded into the authorize URL (mirrors
    /// `TrustedRouterOAuth`).
    public let keyLabel: String?
    public let limit: String?
    public let usageLimitType: String?
    public let expiresAt: String?

    /// The PKCE pair + state for the in-flight authorization. Generated lazily
    /// the first time `authorizeURL` is requested so a single instance maps to
    /// a single round-trip.
    private var pkce: PKCEChallenge?
    private var state: String?

    public init(
        baseURL: String = TrustedRouterConstants.defaultAPIBaseURL,
        urlSession: URLSession = .shared,
        keyLabel: String? = nil,
        limit: String? = nil,
        usageLimitType: String? = nil,
        expiresAt: String? = nil
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.keyLabel = keyLabel
        self.limit = limit
        self.usageLimitType = usageLimitType
        self.expiresAt = expiresAt
    }

    /// Build (once) and return the authorize URL the app should open in the
    /// system browser. Lazily generates the PKCE pair + `state` so that the
    /// same values are validated/used by `waitForCallback()`.
    public func authorizeURL() throws -> URL {
        let pkce = currentPKCE()
        let state = currentState()
        return try oauthAuthorizeURL(
            baseURL: baseURL,
            callbackURL: Self.callbackURL,
            codeChallenge: pkce.codeChallenge,
            codeChallengeMethod: pkce.codeChallengeMethod,
            keyLabel: keyLabel,
            limit: limit,
            usageLimitType: usageLimitType,
            expiresAt: expiresAt,
            state: state
        )
    }

    private func currentPKCE() -> PKCEChallenge {
        if let pkce { return pkce }
        let fresh = PKCEChallenge.generate()
        pkce = fresh
        return fresh
    }

    private func currentState() -> String {
        if let state { return state }
        let fresh = randomOAuthState()
        state = fresh
        return fresh
    }

    /// Bind a one-shot HTTP listener on `127.0.0.1:3000`, accept a single
    /// `GET /callback?code=&state=`, validate `state`, reply with a small
    /// "signed in" page, then exchange the `code` for an ``OAuthToken``.
    ///
    /// - Parameter timeout: How long to wait for the browser redirect before
    ///   giving up (default 300s). The accept loop is interruptible by
    ///   Swift-concurrency cancellation.
    /// - Throws: ``TrustedRouterError/internalError(_:)`` on socket failure,
    ///   timeout, a callback carrying an `error`, a missing `code`, or a
    ///   `state` mismatch (possible CSRF).
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> OAuthToken {
        // Ensure PKCE/state exist even if the caller never read `authorizeURL`
        // (e.g. they built the URL themselves) — though the normal path reads
        // it first.
        let pkce = currentPKCE()
        let expectedState = currentState()

        let request = try await Self.receiveOneCallback(
            port: Self.port,
            expectedPath: Self.callbackPath,
            timeout: timeout
        )

        let (code, returnedState) = try Self.parseRequestLine(request)
        guard returnedState == expectedState else {
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

    /// Convenience: open nothing, just run `waitForCallback` then fetch
    /// userinfo with the freshly-issued key.
    public func waitForCallbackAndFetchUserInfo(
        timeout: TimeInterval = 300
    ) async throws -> (token: OAuthToken, userInfo: UserInfo) {
        let token = try await waitForCallback(timeout: timeout)
        let info = try await fetchUserInfo(apiKey: token.key, baseURL: baseURL, urlSession: urlSession)
        return (token, info)
    }

    // MARK: - Pure request-line parsing (unit-testable, no sockets)

    /// Extract `code` and `state` from an HTTP request *line*, e.g.
    /// `"GET /callback?code=X&state=Y HTTP/1.1"`. Pure and side-effect-free so
    /// it can be unit-tested without binding a real socket.
    ///
    /// Surfaces an OAuth `error` (with optional `error_description`) the same
    /// way `TrustedRouterOAuth.parseCallback` does, and throws when `code` is
    /// absent.
    nonisolated static func parseRequestLine(_ requestLine: String) throws -> (code: String, state: String?) {
        // "GET /callback?code=X&state=Y HTTP/1.1" → middle token is the target.
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            throw TrustedRouterError.internalError("malformed HTTP request line")
        }
        let target = String(parts[1]) // "/callback?code=X&state=Y"

        // Build an absolute URL so URLComponents reliably parses the query.
        // The host is irrelevant — we only read query items.
        guard let components = URLComponents(string: "http://localhost" + target) else {
            throw TrustedRouterError.internalError("could not parse OAuth callback request target")
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

    // MARK: - Minimal POSIX HTTP listener

    /// HTML shown in the browser tab once the redirect is captured.
    static let signedInHTML = """
    <!doctype html><html><head><meta charset="utf-8"><title>Signed in</title>\
    <style>body{font-family:-apple-system,system-ui,sans-serif;background:#0b0d12;color:#e6e8ee;\
    display:flex;align-items:center;justify-content:center;height:100vh;margin:0}\
    .card{text-align:center}h1{font-size:22px;margin:0 0 8px}p{color:#9aa1ad;margin:0}</style></head>\
    <body><div class="card"><h1>Signed in with TrustedRouter</h1>\
    <p>You can close this tab and return to the app.</p></div></body></html>
    """

    /// The raw HTTP response written back to the browser after a successful
    /// `/callback` hit.
    static func successResponse() -> String {
        let body = signedInHTML
        let bytes = body.utf8.count
        return "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(bytes)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
            + body
    }

    /// A small 404 for any path other than `/callback` (e.g. the browser's
    /// `/favicon.ico` probe), so the loop keeps waiting for the real redirect.
    static func notFoundResponse() -> String {
        let body = "Not found"
        return "HTTP/1.1 404 Not Found\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
            + body
    }

    /// Bind `127.0.0.1:<port>`, accept connections until one targets
    /// `expectedPath`, and return that connection's HTTP request line. Replies
    /// 404 (and keeps listening) for any other path. Runs the blocking socket
    /// work off the actor on a detached task, racing a timeout and honoring
    /// cooperative cancellation.
    nonisolated static func receiveOneCallback(
        port: UInt16,
        expectedPath: String,
        timeout: TimeInterval
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try blockingReceiveOneCallback(port: port, expectedPath: expectedPath)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TrustedRouterError.internalError("timed out waiting for OAuth callback on 127.0.0.1:\(port)")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TrustedRouterError.internalError("OAuth loopback listener produced no result")
            }
            return result
        }
    }

    /// The blocking POSIX socket implementation. Opens a listening socket,
    /// accepts clients in a loop, reads the request line, and — on a match —
    /// writes the success page and returns the request line; otherwise writes a
    /// 404 and keeps accepting. Closes every descriptor it owns.
    nonisolated static func blockingReceiveOneCallback(
        port: UInt16,
        expectedPath: String
    ) throws -> String {
        #if canImport(Glibc) || canImport(Darwin)
        let listenFD = socket(AF_INET, sockStreamType, 0)
        guard listenFD >= 0 else {
            throw TrustedRouterError.internalError("could not create loopback socket (errno \(errno))")
        }
        defer { closeFD(listenFD) }

        // SO_REUSEADDR so a quick retry after a previous flow doesn't hit
        // TIME_WAIT.
        var reuse: Int32 = 1
        _ = setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        // 127.0.0.1 — loopback only, never exposed off-box.
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockAddrPtr in
                bind(listenFD, sockAddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw TrustedRouterError.internalError("could not bind 127.0.0.1:\(port) (errno \(errno)); is another sign-in in progress?")
        }
        guard listen(listenFD, 4) == 0 else {
            throw TrustedRouterError.internalError("could not listen on 127.0.0.1:\(port) (errno \(errno))")
        }

        while true {
            try Task.checkCancellation()
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                throw TrustedRouterError.internalError("accept() failed on loopback socket (errno \(errno))")
            }
            defer { closeFD(clientFD) }

            let requestLine = readRequestLine(clientFD)
            guard let requestLine, !requestLine.isEmpty else {
                // Empty/garbled connection (some browsers pre-connect); keep
                // waiting for the real GET.
                continue
            }

            // Only treat /callback hits as the redirect; 404 the rest
            // (favicon probes, etc.) and keep listening.
            let target = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let path = target.split(separator: "?").first.map(String.init) ?? target
            if path == expectedPath {
                writeAll(clientFD, successResponse())
                return requestLine
            } else {
                writeAll(clientFD, notFoundResponse())
                continue
            }
        }
        #else
        throw TrustedRouterError.internalError("OAuthLoopback requires POSIX sockets (Glibc/Darwin); unavailable on this platform")
        #endif
    }

    #if canImport(Glibc) || canImport(Darwin)
    /// Read up to the end of the HTTP request line (first CRLF) from `fd`.
    /// We only need the request line — headers/body are ignored.
    private static func readRequestLine(_ fd: Int32) -> String? {
        var collected = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 1024)
        // Cap total bytes so a misbehaving client can't make us spin forever.
        while collected.count < 8192 {
            let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { break }
            collected.append(contentsOf: buffer[0..<n])
            // Stop as soon as we have the request line (terminated by CRLF or LF).
            if let nl = collected.firstIndex(of: 0x0A) {
                let lineBytes = collected[..<nl]
                let trimmed = lineBytes.last == 0x0D ? lineBytes.dropLast() : lineBytes[...]
                return String(decoding: Array(trimmed), as: UTF8.self)
            }
        }
        if collected.isEmpty { return nil }
        return String(decoding: collected, as: UTF8.self)
    }

    /// Write `text` fully to `fd`, looping over partial writes.
    private static func writeAll(_ fd: Int32, _ text: String) {
        let bytes = Array(text.utf8)
        var offset = 0
        bytes.withUnsafeBytes { raw in
            let base = raw.baseAddress!
            while offset < bytes.count {
                let n = send(fd, base.advanced(by: offset), bytes.count - offset, 0)
                if n <= 0 { break }
                offset += n
            }
        }
    }

    /// Close a descriptor on whichever libc is present.
    private static func closeFD(_ fd: Int32) {
        #if canImport(Glibc)
        _ = Glibc.close(fd)
        #elseif canImport(Darwin)
        _ = Darwin.close(fd)
        #endif
    }
    #endif
}

// MARK: - SOCK_STREAM portability shim

#if canImport(Glibc) || canImport(Darwin)
/// `SOCK_STREAM` is an enum on Linux's Glibc import (`Int32(SOCK_STREAM.rawValue)`)
/// but a plain `Int32` on Darwin. This computed property papers over that so
/// `socket(...)` reads the same on both platforms.
private var sockStreamType: Int32 {
    #if canImport(Glibc)
    return Int32(SOCK_STREAM.rawValue)
    #else
    return SOCK_STREAM
    #endif
}
#endif
