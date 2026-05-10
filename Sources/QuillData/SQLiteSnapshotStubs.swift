// GRDB.swift's WALSnapshot calls four SQLite "snapshot" C functions that
// aren't always present in the SQLite that ships with macOS or the one
// pulled in by Homebrew. Provide weak no-op stubs at file scope here so
// that any target linking against QuillData (which transitively links
// GRDB) gets them for free, regardless of whether QuillShims is in the
// link graph.
//
// On Apple platforms only — Linux's libsqlite3 typically ships with these
// symbols, and adding stubs would cause duplicate-symbol errors.

#if os(macOS) || os(iOS) || os(visionOS)
import Foundation

@_cdecl("sqlite3_snapshot_cmp")
public func quill_sqlite3_snapshot_cmp() -> Int32 { 0 }

@_cdecl("sqlite3_snapshot_free")
public func quill_sqlite3_snapshot_free() {}

@_cdecl("sqlite3_snapshot_get")
public func quill_sqlite3_snapshot_get() -> Int32 { 0 }

@_cdecl("sqlite3_snapshot_open")
public func quill_sqlite3_snapshot_open() -> Int32 { 0 }
#endif
