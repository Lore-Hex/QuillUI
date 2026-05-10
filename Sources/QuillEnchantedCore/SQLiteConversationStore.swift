// Legacy raw-CSQLite conversation store, superseded by
// QuillDataConversationStore.
//
// The previous body of this file (a hand-written CSQLite wrapper) triggered
// a swift-frontend SIL deserializer crash on Swift 6.2.4 when compiled in
// the same module that links SQLiteData + GRDB.swift macros. Rather than
// fight a compiler bug, the implementation has been collapsed to a typealias
// over QuillDataConversationStore and the legacy error enum kept so existing
// call sites still compile.
//
// Reference history is preserved in git; resurrect via `git log` if the
// raw-SQLite path is needed for benchmarking.

import Foundation

/// Legacy alias retained for source compatibility. New code should use
/// `QuillDataConversationStore` directly.
public typealias SQLiteConversationStore = QuillDataConversationStore

/// Legacy error enum. Preserved as a thin re-export so existing call sites
/// that catch `ConversationStoreError` continue to compile.
public enum ConversationStoreError: Error, CustomStringConvertible {
    case openFailed(String)
    case sqlite(String)

    public var description: String {
        switch self {
        case .openFailed(let message), .sqlite(let message):
            return message
        }
    }
}
