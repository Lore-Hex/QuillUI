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
