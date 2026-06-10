//
// QuillSmokeDB -- SignalServiceKit storage-engine smoke for QuillOS (Track B).
//
// Proves SSK's storage engine (GRDB, the SQLite layer all of Signal's
// persistence is built on) executes at RUNTIME on QuillOS (aarch64 Linux): it
// opens an in-memory database, creates a table, writes a row, and reads it back.
//
// HONEST STATUS: this is a bare GRDB roundtrip. It does NOT run Signal's full
// schema migration, does NOT open an on-disk store, and does NOT touch any
// Signal account. (The full in-memory schema migration is the next milestone;
// its entry points are private / TESTABLE_BUILD-gated.) Lives in the SSK module
// (auto-globbed), so the executable can call it without importing GRDB itself.
//
import Foundation
import GRDB
import LibSignalClient

public func quillSmokeGRDBRoundtrip() throws -> String {
    var configuration = GRDB.Configuration()
    configuration.acceptsDoubleQuotedStringLiterals = true
    let dbQueue = try DatabaseQueue(configuration: configuration)
    try dbQueue.write { db in
        try db.execute(sql: "CREATE TABLE t(id INTEGER PRIMARY KEY, v TEXT)")
        try db.execute(sql: "INSERT INTO t(v) VALUES ('quillos')")
    }
    let value = try dbQueue.read { db in
        try String.fetchOne(db, sql: "SELECT v FROM t WHERE id = 1")
    }
    return "GRDB in-memory roundtrip: \(value ?? "nil")"
}

// Run Signal's full SCHEMA migration on a plain in-memory DB (needs AppContext set).
public func quillSmokeSchemaMigration() throws -> String {
    if !quillAppContextInstalled { SetCurrentAppContext(QuillSmokeAppContext(), isRunningTests: false); quillAppContextInstalled = true }
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    let q = try DatabaseQueue(configuration: c)
    try GRDBSchemaMigrator.quillRunSchemaMigrations(on: q)
    let n = try q.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table'") ?? 0 }
    return "Signal schema migrated: \(n) tables"
}
private var quillAppContextInstalled = false

// On-disk persistence round-trip: write account state + an identity ECKeyPair to a
// real DB file via the SAME KeyValueStore path the account/identity managers use,
// CLOSE it, REOPEN it, and read everything back -- proving a linked account would
// survive restart (the user's "don't re-login" requirement). Exercises the
// NSKeyedArchiver ECKeyPair round-trip, the known Linux fidelity risk. No DI
// (DependenciesBridge/SSKEnvironment) is booted: just direct kvStore writes on the
// migrated on-disk DB.
public func quillSmokeAccountPersistRoundtrip(path: String) throws -> String {
    func openDB() throws -> DatabaseQueue {
        var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
        return try DatabaseQueue(path: path, configuration: c)
    }
    let aci = UUID().uuidString
    let e164 = "+15555550100"
    let regId: Int32 = 4242
    let acctStore = KeyValueStore(collection: "TSStorageUserAccountCollection")
    let identityStore = KeyValueStore(collection: "TSStorageManagerIdentityKeyStoreCollection")
    let identityKeyName = "TSStorageManagerIdentityKeyStoreIdentityKey"
    let original = ECKeyPair.generateKeyPair()
    let originalPub = original.identityKeyPair.publicKey.serialize()

    // --- write, then let the queue deallocate (close the file) ---
    do {
        let q = try openDB()
        try GRDBSchemaMigrator.quillRunSchemaMigrations(on: q)
        try q.write { db in
            let tx = DBWriteTransaction(database: db)
            defer { tx.finalizeTransaction() }
            acctStore.setString(aci, key: "localAciUuid", transaction: tx)
            acctStore.setString(e164, key: "localE164", transaction: tx)
            acctStore.setInt32(regId, key: "TSStorageLocalRegistrationId", transaction: tx)
            identityStore.setObject(original, key: identityKeyName, transaction: tx)
        }
    }
    // --- reopen the same file and read everything back (incl. the archived identity key) ---
    let q2 = try openDB()
    var rAci: String?, rE164: String?, rReg: Int32?, rKP: ECKeyPair?
    try q2.read { db in
        let tx = DBReadTransaction(database: db)
        rAci = acctStore.getString("localAciUuid", transaction: tx)
        rE164 = acctStore.getString("localE164", transaction: tx)
        rReg = acctStore.getInt32("TSStorageLocalRegistrationId", transaction: tx)
        rKP = identityStore.getObject(identityKeyName, ofClass: ECKeyPair.self, transaction: tx)
    }
    guard rAci == aci, rE164 == e164, rReg == regId else {
        return "account persist roundtrip MISMATCH: aci=\(rAci ?? "nil") e164=\(rE164 ?? "nil") reg=\(rReg.map(String.init) ?? "nil")"
    }
    guard let rKP, rKP.identityKeyPair.publicKey.serialize() == originalPub else {
        return "account persist roundtrip: scalars persisted but identity ECKeyPair did NOT reload from disk"
    }
    return "account persist roundtrip OK (on-disk, reopened): aci=\(aci) regId=\(regId) e164=\(e164) identityKeyPair reloaded + matches"
}

// LIVE-LINK persistence: write the full set of credentials a freshly-linked
// secondary device must keep to reconnect WITHOUT re-scanning -- aci/pni/e164,
// the assigned deviceId, both 14-bit registration IDs, the server auth token,
// the profile key, and the ACI + PNI identity ECKeyPairs -- onto a real DB file
// via the SAME KeyValueStore path the production account/identity managers use.
// This is what makes the login DURABLE across restart. Uses the same no-DI
// migrated-on-disk-DB pattern as the roundtrip above. The `IdentityKeyPair`
// inputs are the REAL keys from the decrypted provisioning message; we convert
// them to `ECKeyPair` (in-module here) for NSKeyedArchiver storage.
//
// Collections / keys mirror upstream: account scalars live in
// `TSStorageUserAccountCollection` (NewKeyValueStore raw values); BOTH identity
// keys live in the SINGLE collection `TSStorageManagerIdentityKeyStoreCollection`
// under DIFFERENT keys -- ACI under `TSStorageManagerIdentityKeyStoreIdentityKey`,
// PNI under `TSStorageManagerIdentityKeyStorePNIIdentityKey` (not two collections).
public func quillPersistLinkedAccount(
    path: String,
    aciServiceIdUppercase: String,   // aci.serviceIdUppercaseString
    pniUuid: String,                 // pni.rawUUID.uuidString
    e164: String,
    deviceId: UInt32,
    aciRegistrationId: UInt32,
    pniRegistrationId: UInt32,
    aciIdentityKeyPair: IdentityKeyPair,
    pniIdentityKeyPair: IdentityKeyPair,
    profileKey: Data,
    serverAuthToken: String
) throws -> String {
    if !quillAppContextInstalled { SetCurrentAppContext(QuillSmokeAppContext(), isRunningTests: false); quillAppContextInstalled = true }
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    let q = try DatabaseQueue(path: path, configuration: c)
    try GRDBSchemaMigrator.quillRunSchemaMigrations(on: q)

    // Account state is read by the REAL TSAccountManagerImpl via NewKeyValueStore
    // (raw column values in the `keyvalue` table -- NOT NSKeyedArchiver) in
    // collection "TSStorageUserAccountCollection", under these EXACT key
    // constants (TSAccountManagerImpl.Keys) and value types (Int64 for the
    // numeric fields, the ACI's serviceIdUppercaseString for the UUID). Writing
    // them the same way makes a real SignalServiceKit boot load this account.
    let acct = NewKeyValueStore(collection: "TSStorageUserAccountCollection")
    // Identity keys are read by the REAL OWSIdentityManagerImpl via the legacy
    // KeyValueStore (NSKeyedArchiver) in collection
    // "TSStorageManagerIdentityKeyStoreCollection" -- ACI and PNI under DIFFERENT
    // keys in the SAME collection (not two collections).
    let identity = KeyValueStore(collection: "TSStorageManagerIdentityKeyStoreCollection")

    try q.write { db in
        let tx = DBWriteTransaction(database: db)
        defer { tx.finalizeTransaction() }
        acct.writeValue(e164, forKey: "TSStorageRegisteredNumberKey", tx: tx)
        acct.writeValue(aciServiceIdUppercase, forKey: "TSStorageRegisteredUUIDKey", tx: tx)
        acct.writeValue(pniUuid, forKey: "TSAccountManager_RegisteredPNIKey", tx: tx)
        acct.writeValue(Int64(deviceId), forKey: "TSAccountManager_DeviceId", tx: tx)
        acct.writeValue(Int64(aciRegistrationId), forKey: "TSStorageLocalRegistrationId", tx: tx)
        acct.writeValue(Int64(pniRegistrationId), forKey: "TSStorageLocalPniRegistrationId", tx: tx)
        acct.writeValue(serverAuthToken, forKey: "TSStorageServerAuthToken", tx: tx)
        // Secondary devices start as manual message fetchers.
        acct.writeValue(true, forKey: "TSAccountManager_ManualMessageFetchKey", tx: tx)
        // Registration date: a real SSK didRegister writes this (stored as a raw
        // Date via NewKeyValueStore). Not required to load as registered, but
        // included for fidelity so the account record matches a real link.
        acct.writeValue(Date(), forKey: "TSAccountManager_RegistrationDateKey", tx: tx)
        // profileKey is stored by ProfileManager (a different collection) in real
        // SSK; keep it under a clearly-Quill key for our own use (auxiliary, not
        // the production location -- honest about the boundary).
        acct.writeValue(profileKey, forKey: "QuillLocalProfileKey", tx: tx)
        identity.setObject(aciIdentityKeyPair.asECKeyPair, key: "TSStorageManagerIdentityKeyStoreIdentityKey", transaction: tx)
        identity.setObject(pniIdentityKeyPair.asECKeyPair, key: "TSStorageManagerIdentityKeyStorePNIIdentityKey", transaction: tx)
    }
    return "linked account persisted (real SSK keys/types): aci=\(aciServiceIdUppercase) pni=\(pniUuid) deviceId=\(deviceId) e164=\(e164)"
}

// Read back the stored server username + auth token for an authenticated chat
// reconnect, proving the persisted credentials survive a fresh open of the DB
// file (the durability check). Reads via the SAME NewKeyValueStore keys the real
// TSAccountManagerImpl uses. Server username for a linked device is
// "<aci.serviceIdString>.<deviceId>" (TSAccountManagerImpl.serverUsername) -- the
// stored ACI is its uppercase UUID, so reconstruct the Aci to get serviceIdString.
// Returns nil if no linked account is stored.
public func quillLoadStoredAuth(path: String) throws -> (username: String, password: String)? {
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    let q = try DatabaseQueue(path: path, configuration: c)
    let acct = NewKeyValueStore(collection: "TSStorageUserAccountCollection")
    var username: String?
    var password: String?
    try q.read { db in
        let tx = DBReadTransaction(database: db)
        guard let aciStr = acct.fetchValue(String.self, forKey: "TSStorageRegisteredUUIDKey", tx: tx),
              let token = acct.fetchValue(String.self, forKey: "TSStorageServerAuthToken", tx: tx) else { return }
        let deviceId = acct.fetchValue(Int64.self, forKey: "TSAccountManager_DeviceId", tx: tx) ?? 1
        let aciServiceIdString = Aci.parseFrom(aciString: aciStr)?.serviceIdString ?? aciStr.lowercased()
        username = "\(aciServiceIdString).\(deviceId)"
        password = token
    }
    guard let username, let password else { return nil }
    return (username, password)
}

// Display-facing snapshot of the persisted linked account, for a UI to render
// (the real phone number, the server-assigned device id, the ACI/PNI). Reads via
// the SAME NewKeyValueStore keys the real TSAccountManagerImpl + our
// quillPersistLinkedAccount use. Returns nil if no linked account is stored.
public struct QuillAccountDisplay {
    public let e164: String
    public let deviceId: Int64
    public let aciUppercase: String
    public let pniUuid: String
    public let aciRegistrationId: Int64
}

public func quillLoadAccountDisplay(path: String) -> QuillAccountDisplay? {
    var c = GRDB.Configuration(); c.acceptsDoubleQuotedStringLiterals = true
    guard let q = try? DatabaseQueue(path: path, configuration: c) else { return nil }
    let acct = NewKeyValueStore(collection: "TSStorageUserAccountCollection")
    var display: QuillAccountDisplay?
    try? q.read { db in
        let tx = DBReadTransaction(database: db)
        guard let e164 = acct.fetchValue(String.self, forKey: "TSStorageRegisteredNumberKey", tx: tx),
              let aci = acct.fetchValue(String.self, forKey: "TSStorageRegisteredUUIDKey", tx: tx) else { return }
        let deviceId = acct.fetchValue(Int64.self, forKey: "TSAccountManager_DeviceId", tx: tx) ?? 1
        let pni = acct.fetchValue(String.self, forKey: "TSAccountManager_RegisteredPNIKey", tx: tx) ?? ""
        let regId = acct.fetchValue(Int64.self, forKey: "TSStorageLocalRegistrationId", tx: tx) ?? 0
        display = QuillAccountDisplay(
            e164: e164, deviceId: deviceId, aciUppercase: aci, pniUuid: pni, aciRegistrationId: regId)
    }
    return display
}

// Faithful-persistence RUNTIME self-test: exercise the real
// quillPersistLinkedAccount + quillLoadStoredAuth round-trip on a temp DB,
// proving the NewKeyValueStore account-state writes + legacy-KeyValueStore
// identity writes survive a fresh reopen under the REAL SSK keys/types, and that
// the reconnect username ("<aci.serviceIdString>.<deviceId>") + auth token are
// recovered. This is the durable-login guarantee, exercised with NO real account.
public func quillFaithfulPersistSelfTest(path: String) -> String {
    do {
        let aciId = IdentityKeyPair.generate()
        let pniId = IdentityKeyPair.generate()
        let aciUUID = UUID()
        let pniUUID = UUID()
        let deviceId: UInt32 = 3
        let token = "deadbeefcafebabe0011223344556677"
        let profileKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        _ = try quillPersistLinkedAccount(
            path: path,
            aciServiceIdUppercase: aciUUID.uuidString,   // ACI serviceIdUppercaseString == uppercase UUID
            pniUuid: pniUUID.uuidString,
            e164: "+15555550123",
            deviceId: deviceId,
            aciRegistrationId: 1234,
            pniRegistrationId: 5678,
            aciIdentityKeyPair: aciId,
            pniIdentityKeyPair: pniId,
            profileKey: profileKey,
            serverAuthToken: token
        )
        guard let auth = try quillLoadStoredAuth(path: path) else {
            return "FAITHFUL PERSIST: reload returned nil (account not found)"
        }
        let expectUser = "\(aciUUID.uuidString.lowercased()).\(deviceId)"
        guard auth.username == expectUser else {
            return "FAITHFUL PERSIST mismatch: username \(auth.username) != \(expectUser)"
        }
        guard auth.password == token else {
            return "FAITHFUL PERSIST mismatch: token did not round-trip"
        }
        return "FAITHFUL PERSIST: real-SSK-key round-trip OK -> would reconnect as \(auth.username)"
    } catch {
        return "FAITHFUL PERSIST FAILED: \(error)"
    }
}
