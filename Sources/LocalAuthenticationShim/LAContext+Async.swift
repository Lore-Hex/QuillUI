// Async overload of LAContext.evaluatePolicy for the Linux LocalAuthentication shim.
//
// Apple's LocalAuthentication framework ships, via the Swift concurrency overlay,
// an `async throws` form of `evaluatePolicy(_:localizedReason:)` in addition to
// the completion-handler form. SignalServiceKit's LocalDeviceAuthentication.swift
// calls the async form. The base shim only declares the callback form, so this
// file adds the async overload, bridging to that callback via
// withCheckedThrowingContinuation exactly as the Apple overlay does. LAContext is
// an `open class`, so an extension method is fine.
//
#if os(Linux)
import Foundation

public extension LAContext {
    /// Async-throws bridge to the callback-based `evaluatePolicy`, mirroring the
    /// concurrency overlay's `evaluatePolicy(_:localizedReason:) async throws -> Bool`.
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            self.evaluatePolicy(policy, localizedReason: localizedReason) { success, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: success)
                }
            }
        }
    }
}
#endif
