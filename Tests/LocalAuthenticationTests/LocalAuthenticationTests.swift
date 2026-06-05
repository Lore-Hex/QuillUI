import Foundation
import Testing
import LocalAuthentication

/// Surface tests for the LocalAuthentication shadow (Sources/LocalAuthenticationShim)
/// added so WireGuard's PrivateDataConfirmation recompiles on Linux. The shim has no
/// auth backend, so the contract is: canEvaluatePolicy → false, evaluatePolicy → deny,
/// and the framework's `someNSError as? LAError` reverse-bridge stays a valid cast.
@Suite("LocalAuthentication shadow — PrivateDataConfirmation dependencies")
struct LocalAuthenticationShadowTests {
    #if os(Linux)
    @Test("canEvaluatePolicy reports unavailable and clears the out-error")
    func canEvaluatePolicyIsUnavailable() {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        #expect(ok == false)
        #expect(error == nil)
    }

    @Test("the out-error `as? LAError` reverse-bridge compiles and yields nil here")
    func outErrorReverseBridgeCastCompiles() {
        // This mirrors PrivateDataConfirmation exactly: it casts canEvaluatePolicy's
        // NSError? out-error to LAError to special-case .passcodeNotSet. The shim
        // clears the error, so the cast yields nil — but it must remain a VALID cast.
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        let laError = error as? LAError
        #expect(laError == nil)
    }

    @Test("LAError.Code carries the cases PrivateDataConfirmation checks")
    func laErrorCodes() {
        #expect(LAError.Code.passcodeNotSet != LAError.Code.authenticationFailed)
        let err = LAError(.passcodeNotSet)
        #expect(err.code == .passcodeNotSet)
        #expect(err.errorCode == LAError.Code.passcodeNotSet.rawValue)
    }

    @Test("evaluatePolicy denies (success == false) with no auth backend")
    func evaluatePolicyDenies() async {
        let context = LAContext()
        let granted: Bool = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "test") { success, _ in
                continuation.resume(returning: success)
            }
        }
        #expect(granted == false)
    }
    #endif

    @Test("suite is present on all platforms")
    func suitePresent() {
        #expect(Bool(true))
    }
}
