// Self-contained: deliberately does NOT depend on QuillShims (which would drag
// QuillData→GRDB + the whole UIKit/WebKit shim graph into the conformance build).
// The only thing PrivateDataConfirmation needs from `import LocalAuthentication`
// is the LAContext/LAPolicy/LAError surface below, all built on Foundation alone.
#if os(Linux)
import Foundation

// LocalAuthentication shadow — a compile-faithful Linux surface for the slice of
// Apple's LocalAuthentication framework WireGuard touches. There is no biometric /
// passcode backend on Linux, so this exists purely so source like WireGuard's
// `PrivateDataConfirmation` (which gates revealing a tunnel's private/pre-shared key
// behind `LAContext`) recompiles unmodified. Behaviourally the stub always reports
// "cannot evaluate / not authenticated", so the protected reveal simply never fires —
// the safe default for an environment with no local-auth hardware.

/// The authentication policy passed to `LAContext`. WireGuard uses
/// `.deviceOwnerAuthentication` (passcode-or-biometric).
public enum LAPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
}

/// LocalAuthentication's error type. Modelled as a `CustomNSError` struct (as on
/// Apple) so the framework's idiomatic `someNSError as? LAError` reverse-bridge —
/// which `PrivateDataConfirmation` performs on `canEvaluatePolicy`'s out-error — is
/// a valid cast on Linux too.
public struct LAError: Error, CustomNSError {
    public enum Code: Int, Sendable {
        case authenticationFailed = -1
        case userCancel = -2
        case userFallback = -3
        case systemCancel = -4
        case passcodeNotSet = -5
        case biometryNotAvailable = -6
        case biometryNotEnrolled = -7
        case biometryLockout = -8
    }

    public let code: Code
    public init(_ code: Code) { self.code = code }

    public static var errorDomain: String { "com.apple.LocalAuthentication" }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }
}

/// The authentication context. Compile-faithful stub: with no local-auth backend,
/// `canEvaluatePolicy` reports unavailable (clearing the out-error) and
/// `evaluatePolicy` denies, so callers fall through to their not-authenticated path.
open class LAContext {
    public init() {}

    /// Reports whether `policy` can be evaluated. Always `false` on Linux; clears the
    /// out-error so the caller's `error as? LAError` yields `nil` (→ no special-case).
    @discardableResult
    open func canEvaluatePolicy(_ policy: LAPolicy, error: inout NSError?) -> Bool {
        error = nil
        return false
    }

    /// Evaluates `policy`, invoking `reply` with the result. Always denies on Linux.
    open func evaluatePolicy(_ policy: LAPolicy,
                             localizedReason: String,
                             reply: @escaping (Bool, Error?) -> Void) {
        reply(false, LAError(.authenticationFailed))
    }
}
#endif
