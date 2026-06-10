//
// QuillRegistration.swift -- Track B (real Signal-iOS on QuillOS/Linux)
//
// Build (and SELF-TEST, with NO network send) the verify-secondary-device
// registration request body that a freshly-linked secondary device PUTs to
// `v1/devices/link`.
//
// This mirrors the EXACT body shape assembled by the real upstream:
//   .upstream/signal-ios/.../Provisioning/ProvisioningRequestFactory.swift
//     verifySecondaryDeviceRequest(...)
// whose parameters dict is:
//   {
//     "verificationCode": <provisioningCode>,
//     "accountAttributes": <AccountAttributes-as-JSON>,
//     "aciSignedPreKey":      <signedPreKeyRequestParameters>,
//     "pniSignedPreKey":      <signedPreKeyRequestParameters>,
//     "aciPqLastResortPreKey":<pqPreKeyRequestParameters>,
//     "pniPqLastResortPreKey":<pqPreKeyRequestParameters>,
//     // "apnToken" OMITTED (we fetch messages manually)
//   }
//
// The prekey param dicts mirror OWSRequestFactory.signedPreKeyRequestParameters
// / pqPreKeyRequestParameters EXACTLY:
//   { "keyId": UInt32,
//     "publicKey": base64-no-pad(pub.serialize()),
//     "signature": base64-no-pad(sig) }
// using `Data.base64EncodedStringWithoutPadding()` -- the same SSK helper the
// real factory uses (plain base64, no padding; NOT url-safe -- the upstream
// wire format is standard base64-without-padding).
//
// We build the EC signed prekey and the Kyber LAST-RESORT prekey from
// LibSignalClient PRIMITIVES (PrivateKey.generate / KEMKeyPair.generate +
// identityKeyPair.privateKey.generateSignature(...)), NOT the DB-coupled
// SignedPreKeyStoreImpl / KyberPreKeyStoreImpl. We then route the records
// through the same param-builders so the output is byte-identical to upstream.
//
// NO network. NO account. NO database.
//

import Foundation
import LibSignalClient
import SignalServiceKit

// MARK: - Codable mirrors of the wire body

/// Mirrors OWSRequestFactory.signedPreKeyRequestParameters /
/// pqPreKeyRequestParameters: { keyId, publicKey, signature }.
private struct QuillPreKeyParams: Codable {
    let keyId: UInt32
    let publicKey: String   // base64-no-pad of pub.serialize()
    let signature: String   // base64-no-pad of the signature

    /// EC signed prekey -> mirrors `signedPreKeyRequestParameters`.
    init(signedPreKey record: LibSignalClient.SignedPreKeyRecord) throws {
        self.keyId = record.id
        self.publicKey = try record.publicKey().serialize().base64EncodedStringWithoutPadding()
        self.signature = record.signature.base64EncodedStringWithoutPadding()
    }

    /// Kyber last-resort prekey -> mirrors `pqPreKeyRequestParameters`.
    init(pqPreKey record: LibSignalClient.KyberPreKeyRecord) throws {
        self.keyId = record.id
        self.publicKey = try record.publicKey().serialize().base64EncodedStringWithoutPadding()
        self.signature = record.signature.base64EncodedStringWithoutPadding()
    }
}

/// Mirrors the `parameters` dict of `verifySecondaryDeviceRequest`. `apnToken`
/// is intentionally absent (manual message fetch). `accountAttributes` reuses
/// the real `AccountAttributes` Codable, so its CodingKeys (fetchesMessages,
/// registrationId, pniRegistrationId, name, capabilities, ...) match the wire.
private struct QuillVerifySecondaryDeviceBody: Codable {
    let verificationCode: String
    let accountAttributes: AccountAttributes
    let aciSignedPreKey: QuillPreKeyParams
    let pniSignedPreKey: QuillPreKeyParams
    let aciPqLastResortPreKey: QuillPreKeyParams
    let pniPqLastResortPreKey: QuillPreKeyParams
}

// MARK: - Prekey generation from LibSignalClient primitives

/// Generate an EC signed prekey from primitives, signed by `identityKeyPair`.
/// signature = identityKeyPair.privateKey.generateSignature(message: pub.serialize()).
private func quillGenerateSignedPreKey(
    signedBy identityKeyPair: IdentityKeyPair,
    timestamp: UInt64
) throws -> LibSignalClient.SignedPreKeyRecord {
    // Prekey IDs are 24-bit (matches upstream PreKeyId.random() =
    // UInt32.random(in: 1..<0x1000000)); the Signal server rejects IDs >= 0x1000000.
    let keyId = UInt32.random(in: 1..<0x100_0000)
    let privateKey = PrivateKey.generate()
    let publicKey = privateKey.publicKey
    let signature = identityKeyPair.privateKey.generateSignature(message: publicKey.serialize())
    return try LibSignalClient.SignedPreKeyRecord(
        id: keyId,
        timestamp: timestamp,
        privateKey: privateKey,
        signature: signature
    )
}

/// Generate a Kyber LAST-RESORT prekey from primitives, signed by
/// `identityKeyPair`. signature = identityKeyPair.privateKey.generateSignature(
/// message: kemKeyPair.publicKey.serialize()).
private func quillGenerateKyberLastResortPreKey(
    signedBy identityKeyPair: IdentityKeyPair,
    timestamp: UInt64
) throws -> LibSignalClient.KyberPreKeyRecord {
    // 24-bit prekey ID (see quillGenerateSignedPreKey); server rejects >= 0x1000000.
    let keyId = UInt32.random(in: 1..<0x100_0000)
    let keyPair = KEMKeyPair.generate()
    let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
    return try LibSignalClient.KyberPreKeyRecord(
        id: keyId,
        timestamp: timestamp,
        keyPair: keyPair,
        signature: signature
    )
}

// MARK: - Real-input body builder (single source of truth)

/// The fields the live link flow extracts from the decrypted
/// `LinkingProvisioningMessage` (plus the registration IDs and the
/// already-encrypted device name) and feeds into the verify-secondary body.
/// The self-test below builds this with throwaway values; the live flow
/// (QuillLiveLink.swift) builds it from REAL decrypted material.
struct QuillLinkInputs {
    /// The provisioning code from the decrypted message (-> "verificationCode").
    let verificationCode: String
    /// ACI identity keypair the primary handed us (signs the ACI prekeys + the
    /// encrypted device name).
    let aciIdentityKeyPair: IdentityKeyPair
    /// PNI identity keypair (signs the PNI prekeys).
    let pniIdentityKeyPair: IdentityKeyPair
    /// 32-byte profile key (derives the unidentifiedAccessKey).
    let profileKey: Aes256Key
    /// 14-bit ACI/PNI registration IDs (we generate these locally).
    let aciRegistrationId: UInt32
    let pniRegistrationId: UInt32
    /// Output of `OWSDeviceNames.encryptDeviceName(plaintext:identityKeyPair:)`
    /// for our chosen device name, encrypted to the ACI identity. nil in the
    /// self-test (which omits the device name).
    let encryptedDeviceName: Data?
}

/// Assemble + JSON-encode the verify-secondary-device request body from real
/// inputs, byte-shape-identical to upstream
/// `ProvisioningRequestFactory.verifySecondaryDeviceRequest`. Generates fresh
/// per-identity EC signed prekeys + Kyber last-resort prekeys signed by the
/// provided ACI/PNI identity keypairs. NO network is touched here -- this only
/// builds the body; the caller performs the PUT.
func quillBuildVerifySecondaryDeviceBody(_ inputs: QuillLinkInputs) throws -> Data {
    // A shared timestamp for all generated records (epoch millis).
    let nowMillis = UInt64(Date().timeIntervalSince1970 * 1000)

    // --- (1) Per-identity EC signed prekeys + Kyber last-resort, signed by
    //         the REAL ACI/PNI identity keypairs -------------------------------
    let aciSignedPreKeyRecord = try quillGenerateSignedPreKey(
        signedBy: inputs.aciIdentityKeyPair, timestamp: nowMillis)
    let pniSignedPreKeyRecord = try quillGenerateSignedPreKey(
        signedBy: inputs.pniIdentityKeyPair, timestamp: nowMillis)
    let aciKyberLastResortRecord = try quillGenerateKyberLastResortPreKey(
        signedBy: inputs.aciIdentityKeyPair, timestamp: nowMillis)
    let pniKyberLastResortRecord = try quillGenerateKyberLastResortPreKey(
        signedBy: inputs.pniIdentityKeyPair, timestamp: nowMillis)

    // --- (2) AccountAttributes -------------------------------------------------
    // unidentifiedAccessKey = base64(SMKUDAccessKey(profileKey)); name =
    // base64(encryptedDeviceName) when present (mirrors makeAccountAttributes,
    // which base64-encodes the OWSDeviceNames output before assigning `.name`).
    let udAccessKey = SMKUDAccessKey(profileKey: inputs.profileKey)
    let accountAttributes = AccountAttributes(
        isManualMessageFetchEnabled: true,
        registrationId: inputs.aciRegistrationId,
        pniRegistrationId: inputs.pniRegistrationId,
        unidentifiedAccessKey: udAccessKey.keyData.base64EncodedString(),
        unrestrictedUnidentifiedAccess: false,
        reglockToken: nil,
        registrationRecoveryPassword: nil,
        encryptedDeviceName: inputs.encryptedDeviceName?.base64EncodedString(),
        discoverableByPhoneNumber: .nobody,
        capabilities: AccountAttributes.Capabilities(hasSVRBackups: false)
    )

    // --- (3) Assemble + JSON-encode the verify-secondary body ------------------
    let body = QuillVerifySecondaryDeviceBody(
        verificationCode: inputs.verificationCode,
        accountAttributes: accountAttributes,
        aciSignedPreKey: try QuillPreKeyParams(signedPreKey: aciSignedPreKeyRecord),
        pniSignedPreKey: try QuillPreKeyParams(signedPreKey: pniSignedPreKeyRecord),
        aciPqLastResortPreKey: try QuillPreKeyParams(pqPreKey: aciKyberLastResortRecord),
        pniPqLastResortPreKey: try QuillPreKeyParams(pqPreKey: pniKyberLastResortRecord)
    )
    return try JSONEncoder().encode(body)
}

// MARK: - Self-test

/// Fully self-contained: generates fresh ACI/PNI identities, random
/// registration IDs, and a dummy provisioning code / profile key, then builds +
/// JSON-encodes the verify-secondary-device body via the SAME builder the live
/// flow uses. NO network is touched.
func quillBuildLinkRequestSelfTest() -> String {
    do {
        let inputs = QuillLinkInputs(
            verificationCode: "dummy-provisioning-code",
            aciIdentityKeyPair: IdentityKeyPair.generate(),
            pniIdentityKeyPair: IdentityKeyPair.generate(),
            profileKey: Aes256Key(),
            // Signal registration IDs are 14-bit (1...0x3FFF); generate in-range.
            aciRegistrationId: UInt32.random(in: 1...0x3FFF),
            pniRegistrationId: UInt32.random(in: 1...0x3FFF),
            encryptedDeviceName: nil
        )
        let data = try quillBuildVerifySecondaryDeviceBody(inputs)
        return "REGISTER: built link request: aci+pni signed prekeys + 2 kyber last-resort, regIds set, body=\(data.count) bytes"
    } catch {
        return "REGISTER build FAILED: \(error)"
    }
}
