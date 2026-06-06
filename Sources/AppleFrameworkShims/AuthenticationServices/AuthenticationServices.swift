//
// QuillUI Linux shim for Apple's `AuthenticationServices` (the ASWebAuthentication
// subset SignalServiceKit's PayPal donation flow uses).
//
// ASWebAuthenticationSession drives an OAuth-style web flow in a system browser
// sheet. There's no such sheet on Linux, so this is INERT: `start()` returns
// false (the session never begins) and the completion handler never fires. PayPal
// donations via the web-auth flow are therefore UNAVAILABLE on Linux. HONEST
// STATUS: the web-auth session never starts.
//
import Foundation

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

    public init(url: URL, callbackURLScheme: String?, completionHandler: @escaping CompletionHandler) {}

    /// Inert: no system web-auth sheet on Linux -> the session never starts and
    /// the completion handler is never invoked.
    @discardableResult public func start() -> Bool { false }
    public func cancel() {}
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
