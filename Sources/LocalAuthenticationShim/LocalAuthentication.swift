// Shared LocalAuthentication Linux shim — serves BOTH WireGuard's
// PrivateDataConfirmation (key-reveal gate; needs LAContext/LAPolicy/LAError plus the
// idiomatic `someNSError as? LAError` reverse-bridge) AND SignalServiceKit's
// ScreenLock / OWSPaymentsLock / DeviceOwnerAuthenticationType (which need the full
// LAError.Code case set, LABiometryType + LAContext.biometryType, and a pointer-shaped
// canEvaluatePolicy that also accepts a literal `nil`).
//
// Self-contained: depends only on Foundation (NOT QuillFoundation / QuillShims) so the
// WireGuard conformance build stays lean. There is no biometric / passcode backend on
// Linux, so this is INERT: policy evaluation always reports "cannot evaluate" / denied —
// the safe default for an environment with no local-auth hardware. On macOS this target
// is gated out of Package.swift (the real framework is used); the `#if os(Linux)` here is
// belt-and-suspenders so the file is empty if it ever compiles on Apple.
#if os(Linux)
import Foundation
import QuillKit

/// The authentication policy passed to `LAContext`. WireGuard and SSK both pass
/// `.deviceOwnerAuthentication` (passcode-or-biometric).
public enum LAPolicy: Int, Sendable {
    case deviceOwnerAuthenticationWithBiometrics = 1
    case deviceOwnerAuthentication = 2
}

/// The biometry kind reported by `LAContext.biometryType`. None on Linux.
public enum LABiometryType: Int, Sendable {
    case none = 0
    case touchID = 1
    case faceID = 2
    case opticID = 4
}

/// LocalAuthentication's error type. Modelled as a `CustomNSError` struct (as on Apple)
/// so the framework's idiomatic `someNSError as? LAError` reverse-bridge — which both
/// WireGuard's PrivateDataConfirmation and SSK's `outcomeForLAError` perform on
/// canEvaluatePolicy's out-error — is a valid cast on Linux too.
///
/// On iOS the `touchID*` cases are deprecated aliases of the `biometry*` cases and share
/// raw values; a Swift enum cannot duplicate raw values, so each gets a distinct dummy
/// raw here. The raw values are never used on Linux (no `LAError` is ever constructed
/// from a code), so the exact numbers do not matter — only that every case SSK switches
/// on exists.
public struct LAError: Error, CustomNSError {
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
    public init(_ code: Code) { self.code = code }

    public static var errorDomain: String { "com.apple.LocalAuthentication" }
    public var errorCode: Int { code.rawValue }
    public var errorUserInfo: [String: Any] { [:] }
}

/// The authentication context. Compile-faithful inert stub: with no local-auth backend,
/// `canEvaluatePolicy` reports unavailable (clearing the out-error) and `evaluatePolicy`
/// denies, so callers fall through to their not-authenticated path.
open class LAContext {
    public init() {}

    public var interactionNotAllowed: Bool = false
    public var localizedFallbackTitle: String?
    public var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 0
    public var biometryType: LABiometryType {
        LABiometryType(QuillLocalAuthenticationService.shared.biometryType)
    }

    // `error` is NSErrorPointer-shaped (UnsafeMutablePointer<NSError?>?) rather than
    // `inout NSError?` so callers can pass BOTH `&authError` (ScreenLock / OWSPaymentsLock /
    // the LocalAuthenticationTests + PrivateDataConfirmation) and a literal `nil`
    // (DeviceOwnerAuthenticationType). An `inout NSError?` parameter would reject the
    // literal nil. Inert: always "cannot evaluate" on Linux.
    @discardableResult
    open func canEvaluatePolicy(_ policy: LAPolicy, error: UnsafeMutablePointer<NSError?>?) -> Bool {
        let result = QuillLocalAuthenticationService.shared.canEvaluatePolicy(
            QuillLocalAuthenticationPolicy(policy)
        )
        error?.pointee = result.error.map { LAError($0) as NSError }
        return result.canEvaluate
    }

    /// Evaluates `policy`, invoking `reply` with the configured compatibility result.
    open func evaluatePolicy(_ policy: LAPolicy,
                             localizedReason: String,
                             reply: @escaping (Bool, Error?) -> Void) {
        let result = QuillLocalAuthenticationService.shared.evaluatePolicy(
            QuillLocalAuthenticationPolicy(policy),
            localizedReason: localizedReason
        )
        reply(result.success, result.error.map(LAError.init))
    }
}

private extension QuillLocalAuthenticationPolicy {
    init(_ policy: LAPolicy) {
        switch policy {
        case .deviceOwnerAuthenticationWithBiometrics:
            self = .deviceOwnerAuthenticationWithBiometrics
        case .deviceOwnerAuthentication:
            self = .deviceOwnerAuthentication
        }
    }
}

private extension LABiometryType {
    init(_ biometryType: QuillBiometryType) {
        switch biometryType {
        case .none:
            self = .none
        case .touchID:
            self = .touchID
        case .faceID:
            self = .faceID
        case .opticID:
            self = .opticID
        }
    }
}

private extension LAError {
    init(_ code: QuillLocalAuthenticationErrorCode) {
        switch code {
        case .authenticationFailed:
            self.init(LAError.Code.authenticationFailed)
        case .userCancel:
            self.init(LAError.Code.userCancel)
        case .userFallback:
            self.init(LAError.Code.userFallback)
        case .systemCancel:
            self.init(LAError.Code.systemCancel)
        case .passcodeNotSet:
            self.init(LAError.Code.passcodeNotSet)
        case .biometryNotAvailable:
            self.init(LAError.Code.biometryNotAvailable)
        case .biometryNotEnrolled:
            self.init(LAError.Code.biometryNotEnrolled)
        case .biometryLockout:
            self.init(LAError.Code.biometryLockout)
        case .notInteractive:
            self.init(LAError.Code.notInteractive)
        }
    }
}
#endif
