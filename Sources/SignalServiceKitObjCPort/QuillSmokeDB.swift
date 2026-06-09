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
