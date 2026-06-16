// MobileCoin SDK account surface -- SignalUI's
// Payments/MobileCoinAPI+Configuration.swift builds an `AccountKey` from a
// mnemonic + fog parameters (`AccountKey.make`), and the rest of the payments
// cluster passes `PublicAddress` values around (profile payment addresses,
// QR/base58 rendering, `MobileCoinClient.make(accountKey:config:)`).
//
// Inert on Linux: the real SDK derives ristretto view/spend keys via SLIP-0010
// and serializes addresses as protobuf. The shim performs no key derivation;
// the "public address" is a deterministic placeholder blob so values can be
// constructed, carried around, and compared, but never spend or receive funds.

import Foundation

public struct AccountKey: Equatable, Hashable {
    public let fogReportUrl: String
    public let fogReportId: String
    public let fogAuthoritySpki: Data

    /// Real SDK: the address derived from the account's view/spend public
    /// keys. Shim: a deterministic placeholder derived from the make() inputs.
    public let publicAddress: PublicAddress

    public static func make(
        mnemonic: String,
        fogReportUrl: String,
        fogReportId: String,
        fogAuthoritySpki: Data,
        accountIndex: UInt32
    ) -> Result<AccountKey, InvalidInputError> {
        guard !mnemonic.isEmpty else {
            return .failure(InvalidInputError("mnemonic must not be empty"))
        }
        // NOT a key derivation -- just a stable, unique-per-account stand-in.
        let placeholder = Data("mc-linux-shim-address|\(accountIndex)|\(fogReportUrl)|\(mnemonic)".utf8)
        return .success(
            AccountKey(
                fogReportUrl: fogReportUrl,
                fogReportId: fogReportId,
                fogAuthoritySpki: fogAuthoritySpki,
                publicAddress: PublicAddress(unchecked: placeholder)
            )
        )
    }
}

public struct PublicAddress: Equatable, Hashable {
    /// Real SDK: the protobuf serialization of the address. Shim: the bytes
    /// are carried verbatim and never parsed.
    public let serializedData: Data

    public init?(serializedData: Data) {
        // Real SDK validates the protobuf; the shim only rejects the
        // obviously-invalid empty blob.
        guard !serializedData.isEmpty else {
            return nil
        }
        self.serializedData = serializedData
    }

    /// Module-internal escape hatch for shim-synthesized addresses.
    init(unchecked serializedData: Data) {
        self.serializedData = serializedData
    }
}
