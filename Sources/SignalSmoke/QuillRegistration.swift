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
    let keyId = UInt32.random(in: 1...0x7FFF_FFFF)
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
    let keyId = UInt32.random(in: 1...0x7FFF_FFFF)
    let keyPair = KEMKeyPair.generate()
    let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
    return try LibSignalClient.KyberPreKeyRecord(
        id: keyId,
        timestamp: timestamp,
        keyPair: keyPair,
        signature: signature
    )
}

// MARK: - Self-test

/// Fully self-contained: generates fresh ACI/PNI identities, per-identity EC
/// signed prekeys + Kyber last-resort prekeys, random registration IDs, and a
/// dummy provisioning code / profile key, then assembles + JSON-encodes the
/// verify-secondary-device body. NO network is touched.
func quillBuildLinkRequestSelfTest() -> String {
    do {
        // --- Identities the primary would have handed us -------------------
        let aciIdentityKeyPair = IdentityKeyPair.generate()
        let pniIdentityKeyPair = IdentityKeyPair.generate()

        // --- Dummy fields (stand in for the decrypted provisioning msg) ----
        let phoneNumber = "+15555550100"
        _ = phoneNumber  // used for auth on the real request; body itself omits it
        let provisioningCode = "dummy-provisioning-code"
        let profileKey = Aes256Key()  // 32-byte random profile key

        // A shared timestamp for all generated records (epoch millis).
        let nowMillis = UInt64(Date().timeIntervalSince1970 * 1000)

        // --- (1) Per-identity EC signed prekeys + Kyber last-resort --------
        let aciSignedPreKeyRecord = try quillGenerateSignedPreKey(
            signedBy: aciIdentityKeyPair, timestamp: nowMillis)
        let pniSignedPreKeyRecord = try quillGenerateSignedPreKey(
            signedBy: pniIdentityKeyPair, timestamp: nowMillis)
        let aciKyberLastResortRecord = try quillGenerateKyberLastResortPreKey(
            signedBy: aciIdentityKeyPair, timestamp: nowMillis)
        let pniKyberLastResortRecord = try quillGenerateKyberLastResortPreKey(
            signedBy: pniIdentityKeyPair, timestamp: nowMillis)

        // --- (2) Request-param dicts (keyId/publicKey/signature) -----------
        let aciSignedPreKey = try QuillPreKeyParams(signedPreKey: aciSignedPreKeyRecord)
        let pniSignedPreKey = try QuillPreKeyParams(signedPreKey: pniSignedPreKeyRecord)
        let aciPqLastResortPreKey = try QuillPreKeyParams(pqPreKey: aciKyberLastResortRecord)
        let pniPqLastResortPreKey = try QuillPreKeyParams(pqPreKey: pniKyberLastResortRecord)

        // --- (3) Two random registration IDs -------------------------------
        // Signal registration IDs are 14-bit (1...0x3FFF); generate in-range.
        let registrationId = UInt32.random(in: 1...0x3FFF)
        let pniRegistrationId = UInt32.random(in: 1...0x3FFF)

        // --- (4) AccountAttributes (fetchesMessages:true, name:nil) --------
        // unidentifiedAccessKey is derived from the profile key on the real
        // path; for the self-test we encode the base64 of the SMK UD access
        // key so the field shape is exercised. name (encryptedDeviceName) is
        // nil here -- it must be ACI-encrypted, which the self-test omits.
        let udAccessKey = SMKUDAccessKey(profileKey: profileKey)
        let accountAttributes = AccountAttributes(
            isManualMessageFetchEnabled: true,
            registrationId: registrationId,
            pniRegistrationId: pniRegistrationId,
            unidentifiedAccessKey: udAccessKey.keyData.base64EncodedString(),
            unrestrictedUnidentifiedAccess: false,
            reglockToken: nil,
            registrationRecoveryPassword: nil,
            encryptedDeviceName: nil,
            discoverableByPhoneNumber: .nobody,
            capabilities: AccountAttributes.Capabilities(hasSVRBackups: false)
        )

        // --- (5) Assemble + JSON-encode the verify-secondary body ----------
        let body = QuillVerifySecondaryDeviceBody(
            verificationCode: provisioningCode,
            accountAttributes: accountAttributes,
            aciSignedPreKey: aciSignedPreKey,
            pniSignedPreKey: pniSignedPreKey,
            aciPqLastResortPreKey: aciPqLastResortPreKey,
            pniPqLastResortPreKey: pniPqLastResortPreKey
        )

        let data = try JSONEncoder().encode(body)

        // --- (6) Report ----------------------------------------------------
        return "REGISTER: built link request: aci+pni signed prekeys + 2 kyber last-resort, regIds set, body=\(data.count) bytes"
    } catch {
        return "REGISTER build FAILED: \(error)"
    }
}
