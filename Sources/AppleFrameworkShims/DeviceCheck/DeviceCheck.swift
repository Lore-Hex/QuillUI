//
// QuillUI Linux shim for Apple's `DeviceCheck` framework.
//
// SignalServiceKit's TestFlight-entitlement / App Attest flow asks
// DCAppAttestService to generate + attest a hardware key and sign assertions.
// App Attest is hardware-backed iOS-only attestation with no Linux equivalent,
// so this is INERT: the service reports NOT supported and every operation throws
// `DCError(.featureUnsupported)` -- which the caller maps to AppAttestError.
// notSupported and degrades gracefully. HONEST STATUS: App Attest is unavailable
// on Linux (the TestFlight entitlement path cannot complete).
//
import Foundation

/// Mirrors Apple's `DCError` (a stored-NSError struct on iOS). SSK catches it as
/// `catch let dcError as DCError` and switches on `dcError.code`.
public struct DCError: Error, Sendable {
    public enum Code: Int, Sendable {
        case unknownSystemFailure = 0
        case featureUnsupported = 1
        case invalidInput = 2
        case invalidKey = 3
        case serverUnavailable = 4
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
}

public final class DCAppAttestService: @unchecked Sendable {
    public static let shared = DCAppAttestService()
    public init() {}

    /// App Attest needs Secure Enclave hardware attestation -> never supported on Linux.
    public var isSupported: Bool { false }

    public func generateKey() async throws -> String {
        throw DCError(.featureUnsupported)
    }
    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        throw DCError(.featureUnsupported)
    }
    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        throw DCError(.featureUnsupported)
    }
}

/// Device-token attestation (the other half of DeviceCheck). Also inert: a real
/// device token requires Apple's attestation service. Present for source-compat.
public final class DCDevice: @unchecked Sendable {
    public static let current = DCDevice()
    public init() {}
    public var isSupported: Bool { false }
    public func generateToken() async throws -> Data {
        throw DCError(.featureUnsupported)
    }
}
