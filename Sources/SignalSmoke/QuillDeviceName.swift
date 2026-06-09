//
// QuillDeviceName.swift -- Track B device-name encryption self-test.
//
// A secondary (linked) device must send an ENCRYPTED device name in its
// registration. Signal-iOS encrypts the name with the account's (primary)
// identity keypair using an ephemeral-ECDH + HMAC-SHA256 + AES-CTR scheme,
// so the server stores only ciphertext and only devices holding the identity
// private key can read peer device names.
//
// This exercises the REAL SignalServiceKit.OWSDeviceNames end to end over an
// in-memory identity keypair:
//
//   encryptDeviceName(plaintext:identityKeyPair:) -> Data   (serialized
//       SignalIOSProtoDeviceName: ephemeralPublic + syntheticIv + ciphertext)
//   decryptDeviceName(protoData:identityKeyPair:) -> String
//
// Both are STATIC members of the `enum OWSDeviceNames` and `throws`. The key
// type is `LibSignalClient.IdentityKeyPair` (Curve25519), generated in-memory
// via `IdentityKeyPair.generate()` (non-throwing). NO network, NO account.
//
import Foundation
import LibSignalClient
import SignalServiceKit

/// Round-trips the device name "QuillOS" through the real OWSDeviceNames
/// encrypt/decrypt pair over a fresh in-memory identity keypair and asserts
/// the decrypted plaintext matches. Pure crypto: no network, no account.
func quillDeviceNameRoundTripSelfTest() -> String {
    let plaintext = "QuillOS"
    do {
        // The account/primary identity keypair the device name is encrypted to.
        let identityKeyPair = IdentityKeyPair.generate()

        // Encrypt -> serialized SignalIOSProtoDeviceName bytes.
        let encrypted = try OWSDeviceNames.encryptDeviceName(
            plaintext: plaintext,
            identityKeyPair: identityKeyPair
        )

        // Decrypt the proto bytes back with the same identity keypair.
        let decrypted = try OWSDeviceNames.decryptDeviceName(
            protoData: encrypted,
            identityKeyPair: identityKeyPair
        )

        guard decrypted == plaintext else {
            return "DEVICENAME mismatch: got \(decrypted)"
        }
        return "DEVICENAME: encrypt/decrypt round-trip OK (\(encrypted.count) bytes)"
    } catch {
        return "DEVICENAME FAILED: \(error)"
    }
}
