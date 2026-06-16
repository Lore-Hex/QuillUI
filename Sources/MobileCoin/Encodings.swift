// MobileCoin SDK address-encoding surface -- SignalUI's
// Payments/MobileCoinAPI.swift renders public addresses with
// `Base58Coder.encode(_:)`, parses user-pasted strings with
// `Base58Coder.decode(_:)` (switching over `.publicAddress` / default), and
// parses `mob://` URLs with `MobUri.decode(uri:)` (switching over
// `.publicAddress` / `.paymentRequest` / `.transferPayload`).
//
// Inert on Linux: the real SDK encodes a checksummed protobuf in Base58Check.
// The shim round-trips the raw serialized-address bytes through base64
// instead (deterministic + reversible against itself), so a shim-encoded
// string decodes back to the same address but is NOT interchangeable with a
// real MobileCoin base58 string. `mob://` URI parsing always fails honestly.

import Foundation

public enum Base58Coder {
    public static func encode(_ publicAddress: PublicAddress) -> String {
        // NOT Base58Check -- see header.
        publicAddress.serializedData.base64EncodedString()
    }

    public static func decode(_ encodedString: String) -> Base58DecodingResult? {
        guard
            let data = Data(base64Encoded: encodedString),
            let publicAddress = PublicAddress(serializedData: data)
        else {
            return nil
        }
        return .publicAddress(publicAddress)
    }
}

public enum Base58DecodingResult {
    case publicAddress(PublicAddress)
    case paymentRequest(PaymentRequest)
    case transferPayload(TransferPayload)
}

public enum MobUri {
    public enum Payload {
        case publicAddress(PublicAddress)
        case paymentRequest(PaymentRequest)
        case transferPayload(TransferPayload)
    }

    /// Real SDK: parses a `mob://` URI into one of the payloads above. The
    /// shim cannot decode the embedded Base58Check payload, so parsing always
    /// fails; SignalUI converts this to a PaymentsError and treats the URL as
    /// not-a-public-address.
    public static func decode(uri: String) -> Result<Payload, InvalidInputError> {
        .failure(InvalidInputError("mob:// URI decoding is unavailable on Linux"))
    }
}

public struct PaymentRequest {
    public let publicAddress: PublicAddress
    public let value: UInt64?
    public let memo: String?

    public init(publicAddress: PublicAddress, value: UInt64? = nil, memo: String? = nil) {
        self.publicAddress = publicAddress
        self.value = value
        self.memo = memo
    }
}

/// Opaque "gift code" payload; SignalUI only pattern-matches its presence
/// (and rejects it), so the shim carries no fields.
public struct TransferPayload {
    public init() {}
}
