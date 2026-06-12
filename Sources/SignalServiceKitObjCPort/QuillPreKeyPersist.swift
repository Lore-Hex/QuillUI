//
// QuillPreKeyPersist -- one-time prekey GENERATION + PERSISTENCE for the
// QuillOS linked device (Track B "fully provisioned" step).
//
// After a secondary device links (PUT v1/devices/link carries only the SIGNED
// prekeys + Kyber LAST-RESORT prekeys), upstream Signal-iOS immediately uploads
// ONE-TIME prekeys for both identities so other clients can fetch full prekey
// bundles and open brand-new sessions to this device:
//   PreKeyManager.rotateOneTimePreKeysForRegistration ->
//   PreKeyTaskManager.createOneTimePreKeys(identity:, auth:) ->
//     targets [.oneTimePreKey, .oneTimePqPreKey] ->
//   OWSRequestFactory.registerPrekeysRequest -> PUT v2/keys[?identity=pni]
//
// This file does the GENERATE + PERSIST half INSIDE the SignalServiceKit
// module, reusing the REAL upstream machinery (not mirrors):
//   - PreKeyId.nextPreKeyIds          (24-bit sequential IDs from a random start)
//   - PreKeyStoreImpl                 (EC one-time: 100 keys, counter persisted in
//                                      the real metadata collection)
//   - KyberPreKeyStoreImpl            (Kyber one-time: 100 keys, signed by the
//                                      identity key, counter persisted)
//   - PreKeyStore/PreKeyStoreForIdentity.upsertPreKeyRecord
//                                     (INSERT OR REPLACE into the real `PreKey`
//                                      GRDB table, correct namespace + isOneTime)
// so the PRIVATE halves land exactly where a real SSK receive path
// (PreKeyStoreForIdentity: LibSignalClient.PreKeyStore/KyberPreKeyStore
// loadPreKey/loadKyberPreKey) will look for them when an inbound X3DH/PQXDH
// session arrives. The allocation counters are persisted too, so future
// rotations continue the sequence exactly like upstream.
//
// The function returns the ready-to-PUT JSON bodies for ACI and PNI, mirroring
// OWSRequestFactory.registerPrekeysRequest for a one-time-only upload:
//   { "preKeys":   [ { keyId, publicKey } ],                 // NO signature
//     "pqPreKeys": [ { keyId, publicKey, signature } ] }
// with base64EncodedStringWithoutPadding(), the same SSK helper upstream uses.
// (signedPreKey / pqLastResortPreKey are intentionally ABSENT: they were
// registered in the v1/devices/link body, matching upstream's post-link call
// which targets only the one-time keys.)
//
// NO network here. The caller (SignalSmoke/QuillPreKeyUpload.swift) performs
// the authenticated PUTs; nothing in this file touches any account.
//
import Foundation
import GRDB
import LibSignalClient

// Codable mirrors of OWSRequestFactory.preKeyRequestParameters /
// pqPreKeyRequestParameters for the one-time upload body.
private struct QuillOneTimeECParams: Codable {
    let keyId: UInt32
    let publicKey: String   // base64-no-pad(pub.serialize()) -- one-time EC has NO signature
}
private struct QuillOneTimePQParams: Codable {
    let keyId: UInt32
    let publicKey: String
    let signature: String
}
private struct QuillOneTimeUploadBody: Codable {
    let preKeys: [QuillOneTimeECParams]
    let pqPreKeys: [QuillOneTimePQParams]
}

/// Generate 100 one-time EC prekeys + 100 one-time Kyber prekeys PER IDENTITY
/// via the real upstream stores, persist the private halves (and allocation
/// counters) into the real `PreKey` table / metadata collections in the DB at
/// `path`, and return the JSON bodies to PUT to v2/keys (ACI) and
/// v2/keys?identity=pni (PNI).
public func quillGenerateAndPersistOneTimePreKeys(
    path: String,
    aciIdentityKeyPair: IdentityKeyPair,
    pniIdentityKeyPair: IdentityKeyPair
) throws -> (aciBody: Data, pniBody: Data, summary: String) {
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    let q = try DatabaseQueue(path: path, configuration: c)
    // Idempotent; the linked-account DB has already been migrated by
    // quillPersistLinkedAccount, but a standalone self-test DB has not.
    // PRECONDITION: an AppContext is already installed (the schema migrator
    // reads it). Both call sites guarantee this: the self-test runs after
    // FAITHFUL PERSIST and the live flow runs after quillPersistLinkedAccount,
    // each of which installs QuillSmokeAppContext. We deliberately do NOT
    // install here -- a second SetCurrentAppContext would be the riskier path.
    try GRDBSchemaMigrator.quillRunSchemaMigrations(on: q)

    let preKeyStore = PreKeyStore()
    let now = Date()

    func generateForIdentity(
        _ identity: OWSIdentity,
        identityKeyPair: IdentityKeyPair,
        tx: DBWriteTransaction
    ) throws -> Data {
        // --- one-time EC prekeys: real allocator (persists the counter in the
        // real metadata collection) + real generator, 100 keys, no signature ---
        let ecImpl = PreKeyStoreImpl(for: identity, preKeyStore: preKeyStore)
        let ecIds = ecImpl.allocatePreKeyIds(tx: tx)
        let ecRecords = PreKeyStoreImpl.generatePreKeyRecords(forPreKeyIds: ecIds)
        ecImpl.storePreKeyRecords(ecRecords, tx: tx)

        // --- one-time Kyber prekeys: real allocator + real generator (signed by
        // the identity private key), 100 keys, isLastResort: false ---
        let kyberImpl = KyberPreKeyStoreImpl(
            for: identity,
            dateProvider: { now },
            preKeyStore: preKeyStore
        )
        let pqIds = kyberImpl.allocatePreKeyIds(count: 100, tx: tx)
        let pqRecords = kyberImpl.generatePreKeyRecords(
            forPreKeyIds: pqIds,
            signedBy: identityKeyPair.privateKey
        )
        kyberImpl.storePreKeyRecords(pqRecords, isLastResort: false, tx: tx)

        // --- the upload body, mirroring registerPrekeysRequest exactly ---
        let body = QuillOneTimeUploadBody(
            preKeys: try ecRecords.map {
                QuillOneTimeECParams(
                    keyId: $0.id,
                    publicKey: try $0.publicKey().serialize().base64EncodedStringWithoutPadding()
                )
            },
            pqPreKeys: try pqRecords.map {
                QuillOneTimePQParams(
                    keyId: $0.id,
                    publicKey: try $0.publicKey().serialize().base64EncodedStringWithoutPadding(),
                    signature: $0.signature.base64EncodedStringWithoutPadding()
                )
            }
        )
        return try JSONEncoder().encode(body)
    }

    var aciBody = Data()
    var pniBody = Data()
    try q.write { db in
        let tx = DBWriteTransaction(database: db)
        defer { tx.finalizeTransaction() }
        aciBody = try generateForIdentity(.aci, identityKeyPair: aciIdentityKeyPair, tx: tx)
        pniBody = try generateForIdentity(.pni, identityKeyPair: pniIdentityKeyPair, tx: tx)
    }
    let summary = "generated+persisted 100 EC + 100 Kyber one-time prekeys per identity (real PreKey table + counters)"
    return (aciBody, pniBody, summary)
}

/// Count the persisted one-time prekeys in the real `PreKey` table (per
/// namespace), for the runtime self-test: after a generate+persist round,
/// expect 200 one-time EC (namespace 0) + 200 one-time Kyber (namespace 1)
/// across the two identities. Also proves the rows REOPEN from disk.
public func quillCountOneTimePreKeys(path: String) throws -> (ec: Int, pq: Int) {
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    let q = try DatabaseQueue(path: path, configuration: c)
    return try q.read { db in
        let ec = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM PreKey WHERE namespace = 0 AND isOneTime = 1") ?? 0
        let pq = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM PreKey WHERE namespace = 1 AND isOneTime = 1") ?? 0
        return (ec, pq)
    }
}
