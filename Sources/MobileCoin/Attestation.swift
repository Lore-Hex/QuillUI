// MobileCoin SDK attestation surface -- SignalUI's
// Payments/MobileCoinAPI+Configuration.swift builds per-environment
// `MobileCoin.Attestation` values (consensus / fog-view / fog-ledger /
// fog-report) from hardcoded MRENCLAVE / MRSIGNER measurements via
// `Attestation.MrEnclave.make(...)` / `Attestation.MrSigner.make(...)`.
//
// Inert on Linux: payments never reach a MobileCoin consensus node from
// QuillOS, so the config is only constructed and carried around. The real SDK
// validates measurement lengths (32 bytes) in `make`; the shim accepts any
// input and always succeeds -- the values are never handed to an enclave
// verifier here.

import Foundation

public struct Attestation: Equatable, Hashable {
    public struct MrEnclave: Equatable, Hashable {
        public let mrEnclave: Data
        public let allowedConfigAdvisories: [String]
        public let allowedHardeningAdvisories: [String]

        public static func make(
            mrEnclave: Data,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> Result<MrEnclave, InvalidInputError> {
            .success(
                MrEnclave(
                    mrEnclave: mrEnclave,
                    allowedConfigAdvisories: allowedConfigAdvisories,
                    allowedHardeningAdvisories: allowedHardeningAdvisories
                )
            )
        }
    }

    public struct MrSigner: Equatable, Hashable {
        public let mrSigner: Data
        public let productId: UInt16
        public let minimumSecurityVersion: UInt16
        public let allowedConfigAdvisories: [String]
        public let allowedHardeningAdvisories: [String]

        public static func make(
            mrSigner: Data,
            productId: UInt16,
            minimumSecurityVersion: UInt16,
            allowedConfigAdvisories: [String] = [],
            allowedHardeningAdvisories: [String] = []
        ) -> Result<MrSigner, InvalidInputError> {
            .success(
                MrSigner(
                    mrSigner: mrSigner,
                    productId: productId,
                    minimumSecurityVersion: minimumSecurityVersion,
                    allowedConfigAdvisories: allowedConfigAdvisories,
                    allowedHardeningAdvisories: allowedHardeningAdvisories
                )
            )
        }
    }

    public let mrEnclaves: [MrEnclave]
    public let mrSigners: [MrSigner]

    public init(mrEnclaves: [MrEnclave] = [], mrSigners: [MrSigner] = []) {
        self.mrEnclaves = mrEnclaves
        self.mrSigners = mrSigners
    }
}

/// The real SDK's input-validation error type, returned by the `make`
/// factories above (where the Linux shim never actually fails).
public struct InvalidInputError: Error, Equatable, CustomStringConvertible {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "Invalid input: \(reason)" }
}
