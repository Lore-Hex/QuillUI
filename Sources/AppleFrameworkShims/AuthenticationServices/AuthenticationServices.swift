//
import Foundation
import QuillKit

/// On Apple this is `UIWindow` / `NSWindow`; here an opaque anchor (SSK only
/// references the providing protocol, it doesn't construct an anchor).
public final class ASPresentationAnchor: @unchecked Sendable {
    public init() {}
}

public protocol ASWebAuthenticationPresentationContextProviding: AnyObject {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
}

public final class ASWebAuthenticationSession: @unchecked Sendable {
    public typealias CompletionHandler = (URL?, (any Error)?) -> Void

    public weak var presentationContextProvider: ASWebAuthenticationPresentationContextProviding?
    public var prefersEphemeralWebBrowserSession: Bool = false

    private let url: URL
    private let callbackURLScheme: String?
    private let completionHandler: CompletionHandler
    private let lock = NSLock()
    private var active = false
    private var completed = false

    public init(url: URL, callbackURLScheme: String?, completionHandler: @escaping CompletionHandler) {
        self.url = url
        self.callbackURLScheme = callbackURLScheme?.lowercased()
        self.completionHandler = completionHandler
    }

    /// Starts a Linux desktop OAuth flow by opening the authorization URL via
    /// QuillKit's shared workspace opener. A desktop URL-scheme bridge can later
    /// deliver the callback with `handleCallbackURL(_:)`; tests/headless smokes
    /// may set `QUILLUI_WEB_AUTH_CALLBACK_URL` to inject that callback
    /// deterministically.
    @discardableResult public func start() -> Bool {
        let shouldStart = lock.withLock { () -> Bool in
            guard !completed, !active else {
                return false
            }
            active = true
            return true
        }
        guard shouldStart else {
            return false
        }

        Self.register(self)

        if let injected = Self.injectedCallbackURL(matching: callbackURLScheme) {
            complete(callbackURL: injected, error: nil)
            return true
        }

        if QuillWorkspace.open(url) {
            return true
        }

        Self.unregister(self)
        lock.withLock {
            active = false
        }
        return false
    }

    public func cancel() {
        complete(
            callbackURL: nil,
            error: ASWebAuthenticationSessionError(code: .canceledLogin)
        )
    }

    @discardableResult
    public static func handleCallbackURL(_ url: URL) -> Bool {
        guard let session = registry.lock.withLock({
            registry.sessions.reversed().first { $0.acceptsCallbackURL(url) }
        }) else {
            return false
        }
        return session.complete(callbackURL: url, error: nil)
    }

    private func acceptsCallbackURL(_ url: URL) -> Bool {
        let isActive = lock.withLock { active }
        guard let callbackURLScheme else {
            return isActive
        }
        return isActive && url.scheme?.lowercased() == callbackURLScheme
    }

    @discardableResult
    private func complete(callbackURL: URL?, error: (any Error)?) -> Bool {
        let shouldComplete = lock.withLock { () -> Bool in
            guard !completed else {
                return false
            }
            completed = true
            active = false
            return true
        }
        guard shouldComplete else {
            return false
        }

        Self.unregister(self)
        completionHandler(callbackURL, error)
        return true
    }

    private static func injectedCallbackURL(matching callbackURLScheme: String?) -> URL? {
        guard
            let raw = ProcessInfo.processInfo.environment["QUILLUI_WEB_AUTH_CALLBACK_URL"],
            let url = URL(string: raw)
        else {
            return nil
        }

        guard let callbackURLScheme else {
            return url
        }
        return url.scheme?.lowercased() == callbackURLScheme ? url : nil
    }

    private static func register(_ session: ASWebAuthenticationSession) {
        registry.lock.withLock {
            registry.sessions.append(session)
        }
    }

    private static func unregister(_ session: ASWebAuthenticationSession) {
        registry.lock.withLock {
            registry.sessions.removeAll { $0 === session }
        }
    }

    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var sessions: [ASWebAuthenticationSession] = []
    }

    private static let registry = Registry()
}

public struct ASWebAuthenticationSessionError: Error {
    public enum Code: Int, Sendable {
        case canceledLogin = 1
        case presentationContextNotProvided = 2
        case presentationContextInvalid = 3
    }
    public let code: Code
    public init(code: Code) { self.code = code }
}
