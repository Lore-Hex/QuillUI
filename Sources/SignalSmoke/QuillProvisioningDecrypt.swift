//
// Provisioning-envelope DECRYPT path + a self-contained crypto round-trip
// self-test for the QuillOS Signal smoke (Track B).
//
// In real secondary-device linking, the primary (the phone running Signal)
// encrypts a `ProvisionMessage` to the secondary's one-time ephemeral cipher
// public key (the `pub_key` we put in the `sgnl://linkdevice` URL / QR), wraps
// the ciphertext in a `ProvisionEnvelope` proto together with the primary's own
// one-time cipher public key, and sends it down our provisioning socket. The
// secondary then ECDH-agrees with the envelope's `publicKey`, HKDF-derives the
// AES/HMAC keys, decrypts, and parses the `ProvisionMessage`.
//
// This mirrors the upstream Signal-iOS app exactly. See
//   .upstream/signal-ios/Signal/Provisioning/ProvisioningSocketManager.swift
// `DecryptableProvisionEnvelope.decrypt()`:
//
//   let envelope = try ProvisioningMessage.Envelope(serializedData: encryptedEnvelope)
//   let data = try cipher.decrypt(data: envelope.body, theirPublicKey: try PublicKey(envelope.publicKey))
//   return try ProvisioningMessage(plaintext: data)
//
// So `didReceiveEnvelope` delivers a *serialized ProvisionEnvelope proto*, NOT
// an already-unwrapped body. `quillDecryptProvisionEnvelope` below implements
// the same three steps for the `LinkingProvisioningMessage` case.
//
// NO network and NO account are touched here. `quillProvisioningRoundTripSelfTest`
// is a fully self-contained encrypt->wrap->decrypt->parse loopback over in-memory
// keys, exercising the real `ProvisioningCipher` + `LinkingProvisioningMessage`
// crypto end to end.
//
import Foundation
import LibSignalClient
import SignalServiceKit

/// Decrypt a serialized `ProvisioningProtoProvisionEnvelope` (as delivered by
/// libsignal's `didReceiveEnvelope`) into a parsed `LinkingProvisioningMessage`.
///
/// - Parameters:
///   - envelope: the raw bytes of a serialized `ProvisionEnvelope` proto.
///   - ourKeyPair: OUR one-time ephemeral provisioning keypair (the one whose
///     public key was advertised in the `sgnl://linkdevice` URL / QR). Its
///     private key performs the ECDH agreement against the primary's public key
///     carried inside the envelope.
func quillDecryptProvisionEnvelope(
    _ envelope: Data,
    ourKeyPair: IdentityKeyPair
) throws -> LinkingProvisioningMessage {
    // Step 1: unwrap the outer ProvisionEnvelope proto (publicKey + body).
    let proto = try ProvisioningProtoProvisionEnvelope(serializedData: envelope)

    // The envelope's publicKey is the PRIMARY's (sender's) one-time cipher
    // public key; we ECDH-agree against it with our private key.
    let theirPublicKey = try PublicKey(proto.publicKey)

    // Step 2: decrypt the body with our ephemeral keypair's ProvisioningCipher.
    let cipher = ProvisioningCipher(ourKeyPair: ourKeyPair)
    let plaintext = try cipher.decrypt(data: proto.body, theirPublicKey: theirPublicKey)

    // Step 3: parse the inner ProvisionMessage proto.
    return try LinkingProvisioningMessage(plaintext: plaintext)
}

/// Fully self-contained round-trip self-test of the provisioning crypto. No
/// network, no account, no Signal server. Generates two ephemeral keypairs
/// ("primary" sender, "our" secondary recipient), builds a minimal-but-valid
/// `ProvisionMessage`, encrypts+wraps it exactly as a primary would, then runs
/// it back through `quillDecryptProvisionEnvelope` and asserts the parsed
/// fields match what was put in.
func quillProvisioningRoundTripSelfTest() -> String {
    do {
        // --- Identities ---------------------------------------------------
        // OUR secondary-device ephemeral provisioning keypair. Its public key
        // is what we would advertise in the QR; its private key decrypts.
        let ourKeyPair = IdentityKeyPair.generate()
        // The PRIMARY's one-time cipher keypair. In real life this is generated
        // by the phone; here we stand in for it so we can encrypt.
        let primaryKeyPair = IdentityKeyPair.generate()

        // --- Payload fields ----------------------------------------------
        // ACI/PNI identity keypairs that the primary would hand to the new
        // linked device (distinct from the *cipher* keypairs above).
        let aciIdentityKeyPair = IdentityKeyPair.generate()
        let pniIdentityKeyPair = IdentityKeyPair.generate()

        let aciUUID = UUID()
        let pniUUID = UUID()
        let phoneNumber = "+15555550100"
        let provisioningCode = "abc"

        // 32-byte profile key.
        let profileKey = Aes256Key()
        // A valid AccountEntropyPool (root key). LinkingProvisioningMessage.init
        // prefers AEP over a bare master key, so set both via the AEP.
        let aep = AccountEntropyPool()
        // A valid media-root backup key (correct length, libsignal-generated).
        let mrbkBackupKey = BackupKey.generateRandom()

        // --- Build the ProvisionMessage proto (mirrors
        //     LinkingProvisioningMessage.buildEncryptedMessageBody) ---------
        let messageBuilder = ProvisioningProtoProvisionMessage.builder(
            aciIdentityKeyPublic: aciIdentityKeyPair.publicKey.serialize(),
            aciIdentityKeyPrivate: aciIdentityKeyPair.privateKey.serialize(),
            pniIdentityKeyPublic: pniIdentityKeyPair.publicKey.serialize(),
            pniIdentityKeyPrivate: pniIdentityKeyPair.privateKey.serialize(),
            provisioningCode: provisioningCode,
            profileKey: profileKey.keyData
        )
        messageBuilder.setUserAgent(LinkingProvisioningMessage.Constants.userAgent)
        messageBuilder.setReadReceipts(true)
        messageBuilder.setProvisioningVersion(LinkingProvisioningMessage.Constants.provisioningVersion)
        messageBuilder.setNumber(phoneNumber)
        // ACI is read back via Aci.parseFrom(serviceIdBinary:) which expects the
        // 16-byte raw UUID; PNI is read back via UUID(data:) + Pni(fromUUID:).
        // Both are the raw 16-byte UUID, exactly as SSK's own builder writes them.
        messageBuilder.setAciBinary(aciUUID.data)
        messageBuilder.setPniBinary(pniUUID.data)
        // Root key: provide the AccountEntropyPool (and its derived master key).
        messageBuilder.setAccountEntropyPool(aep.rawString)
        messageBuilder.setMasterKey(aep.getMasterKey().rawData)
        // Media root backup key (required by init).
        messageBuilder.setMediaRootBackupKey(mrbkBackupKey.serialize())

        let plaintext = try messageBuilder.buildSerializedData()

        // --- Encrypt + wrap exactly as a primary would --------------------
        // ProvisioningCipher.encrypt(data:theirPublicKey:) encrypts FROM the
        // cipher's ourKeyPair TO theirPublicKey. The primary encrypts to OUR
        // public key, so the sender cipher is keyed on the primary's keypair.
        let senderCipher = ProvisioningCipher(ourKeyPair: primaryKeyPair)
        let body = try senderCipher.encrypt(plaintext, theirPublicKey: ourKeyPair.publicKey)

        let envelopeBuilder = ProvisioningProtoProvisionEnvelope.builder(
            publicKey: primaryKeyPair.publicKey.serialize(),
            body: body
        )
        let envelope = try envelopeBuilder.buildSerializedData()

        // --- Decrypt back through the real path ---------------------------
        let parsed = try quillDecryptProvisionEnvelope(envelope, ourKeyPair: ourKeyPair)

        // --- Assertions ---------------------------------------------------
        guard parsed.phoneNumber == phoneNumber else {
            return "round-trip FAILED: phoneNumber mismatch (\(parsed.phoneNumber) != \(phoneNumber))"
        }
        guard parsed.aci.rawUUID == aciUUID else {
            return "round-trip FAILED: aci mismatch (\(parsed.aci.rawUUID) != \(aciUUID))"
        }
        guard parsed.pni.rawUUID == pniUUID else {
            return "round-trip FAILED: pni mismatch (\(parsed.pni.rawUUID) != \(pniUUID))"
        }
        guard parsed.provisioningCode == provisioningCode else {
            return "round-trip FAILED: provisioningCode mismatch"
        }
        guard parsed.profileKey.keyData == profileKey.keyData else {
            return "round-trip FAILED: profileKey mismatch"
        }
        guard parsed.aciIdentityKeyPair.publicKey.serialize() == aciIdentityKeyPair.publicKey.serialize() else {
            return "round-trip FAILED: aciIdentityKeyPair mismatch"
        }
        guard case .accountEntropyPool(let parsedAep) = parsed.rootKey, parsedAep.rawString == aep.rawString else {
            return "round-trip FAILED: rootKey (accountEntropyPool) mismatch"
        }

        return "provisioning decrypt round-trip OK: aci=\(parsed.aci.rawUUID.uuidString) number=\(parsed.phoneNumber) provisioningCode set"
    } catch {
        return "round-trip FAILED: \(error)"
    }
}
