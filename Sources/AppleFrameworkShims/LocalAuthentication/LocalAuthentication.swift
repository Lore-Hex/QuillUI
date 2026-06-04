//
// QuillUI Linux shim for `LocalAuthentication` — placeholder so `import LocalAuthentication` resolves on
// Linux. Concrete symbols are added as SignalServiceKit references surface
// (behavior deferred). Part of the Signal-iOS -> QuillOS port.
//
import Foundation

// MARK: - LAPolicy

/// Mirrors `LAPolicy`. SignalServiceKit's auth flows pass
/// `.deviceOwnerAuthentication` to `LAContext`.
public enum LAPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
}

// MARK: - LAError

/// Mirrors LocalAuthentication's `LAError`. Nothing throws it on Linux (device
/// auth is stubbed), but SignalServiceKit switches on `laError.code`, so the
/// type and every `Code` case it matches must exist.
///
/// On iOS the `touchID*` cases are deprecated aliases of the `biometry*` cases
/// and share raw values; a Swift enum cannot duplicate raw values, so each gets
/// a distinct dummy raw here. The raw values are never used on Linux (no
/// `LAError` is ever constructed from a code).
public struct LAError: Error {
    public enum Code: Int, Sendable {
        case authenticationFailed = -1
        case userCancel = -2
        case userFallback = -3
        case systemCancel = -4
        case passcodeNotSet = -5
        case touchIDNotAvailable = -6
        case touchIDNotEnrolled = -7
        case touchIDLockout = -8
        case appCancel = -9
        case invalidContext = -10
        case biometryNotAvailable = -106
        case biometryNotEnrolled = -107
        case biometryLockout = -108
        case companionNotAvailable = -111
        case notInteractive = -1004
    }

    public let code: Code
    public init(code: Code) { self.code = code }
}

// MARK: - LAContext

/// Mirrors `LAContext`. On Linux local device authentication is unavailable, so
/// policy evaluation always reports "cannot evaluate" / failure. A real backend
/// would bridge to a platform authenticator (deferred).
public class LAContext {
    public init() {}

    public var interactionNotAllowed: Bool = false
    public var localizedFallbackTitle: String?

    public func canEvaluatePolicy(_ policy: LAPolicy, error: inout NSError?) -> Bool {
        error = nil
        return false
    }

    public func evaluatePolicy(_ policy: LAPolicy,
                               localizedReason: String,
                               reply: @escaping (Bool, Error?) -> Void) {
        reply(false, nil)
    }
}
