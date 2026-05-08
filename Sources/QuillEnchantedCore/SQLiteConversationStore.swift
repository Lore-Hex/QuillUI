import CSQLite
import Foundation

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

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteConversationStore {
    private var db: OpaquePointer?

    public static func defaultURL() throws -> URL {
        let baseURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quillui", isDirectory: true)
            .appendingPathComponent("enchanted", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent("enchanted.sqlite")
    }

    public init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open failure"
            throw ConversationStoreError.openFailed(message)
        }
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    public func loadConversations() throws -> [ConversationSummary] {
        let sql = """
        SELECT c.id, c.title, c.created_at, c.updated_at,
               COALESCE((
                   SELECT m.content
                   FROM messages m
                   WHERE m.conversation_id = c.id
                   ORDER BY m.created_at DESC
                   LIMIT 1
               ), '') AS last_message
        FROM conversations c
        ORDER BY c.updated_at DESC
        """

        let statement = try Statement(db: db, sql: sql)
        var rows: [ConversationSummary] = []

        while try statement.step() {
            rows.append(
                ConversationSummary(
                    id: statement.text(at: 0),
                    title: statement.text(at: 1),
                    createdAt: Date(timeIntervalSince1970: statement.double(at: 2)),
                    updatedAt: Date(timeIntervalSince1970: statement.double(at: 3)),
                    lastMessage: statement.text(at: 4)
                )
            )
        }

        return rows
    }

    public func loadMessages(conversationID: String) throws -> [ChatMessage] {
        let sql = """
        SELECT id, conversation_id, role, content, created_at
        FROM messages
        WHERE conversation_id = ?
        ORDER BY created_at ASC
        """

        let statement = try Statement(db: db, sql: sql)
        try statement.bind(conversationID, at: 1)

        var rows: [ChatMessage] = []
        while try statement.step() {
            rows.append(
                ChatMessage(
                    id: statement.text(at: 0),
                    conversationID: statement.text(at: 1),
                    role: ChatRole(rawValue: statement.text(at: 2)) ?? .assistant,
                    content: statement.text(at: 3),
                    createdAt: Date(timeIntervalSince1970: statement.double(at: 4))
                )
            )
        }
        return rows
    }

    @discardableResult
    public func createConversation(title: String) throws -> ConversationSummary {
        let conversation = ConversationSummary(title: title)
        try execute(
            """
            INSERT INTO conversations (id, title, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            """,
            bindings: [
                .text(conversation.id),
                .text(conversation.title),
                .double(conversation.createdAt.timeIntervalSince1970),
                .double(conversation.updatedAt.timeIntervalSince1970)
            ]
        )
        return conversation
    }

    public func renameConversation(id: String, title: String) throws {
        try execute(
            "UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?",
            bindings: [.text(title), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    public func append(_ message: ChatMessage) throws {
        try execute(
            """
            INSERT INTO messages (id, conversation_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(message.id),
                .text(message.conversationID),
                .text(message.role.rawValue),
                .text(message.content),
                .double(message.createdAt.timeIntervalSince1970)
            ]
        )
        try execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            bindings: [.double(message.createdAt.timeIntervalSince1970), .text(message.conversationID)]
        )
    }

    public func trimMessages(conversationID: String, from messageID: String) throws {
        let messages = try loadMessages(conversationID: conversationID)
        guard let trimIndex = messages.firstIndex(where: { $0.id == messageID }) else { return }

        for message in messages[trimIndex...] {
            try execute("DELETE FROM messages WHERE id = ?", bindings: [.text(message.id)])
        }

        let remainingMessages = messages[..<trimIndex]
        let updatedAt = remainingMessages.last?.createdAt ?? Date()
        try execute(
            "UPDATE conversations SET updated_at = ? WHERE id = ?",
            bindings: [.double(updatedAt.timeIntervalSince1970), .text(conversationID)]
        )
    }

    public func deleteConversation(id: String) throws {
        try execute("DELETE FROM messages WHERE conversation_id = ?", bindings: [.text(id)])
        try execute("DELETE FROM conversations WHERE id = ?", bindings: [.text(id)])
    }

    public func deleteAll() throws {
        try execute("DELETE FROM messages", bindings: [])
        try execute("DELETE FROM conversations", bindings: [])
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """,
            bindings: []
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY NOT NULL,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                created_at REAL NOT NULL,
                FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
            )
            """,
            bindings: []
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at)",
            bindings: []
        )
    }

    private enum BindingValue {
        case text(String)
        case double(Double)
    }

    private func execute(_ sql: String, bindings: [BindingValue]) throws {
        let statement = try Statement(db: db, sql: sql)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let value):
                try statement.bind(value, at: index)
            case .double(let value):
                try statement.bind(value, at: index)
            }
        }
        _ = try statement.step()
    }
}

private final class Statement {
    private let db: OpaquePointer?
    private var statement: OpaquePointer?

    init(db: OpaquePointer?, sql: String) throws {
        self.db = db
        let result = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite prepare failed")
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: String, at index: Int32) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.sqlite(errorMessage)
        }
    }

    func bind(_ value: Double, at index: Int32) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw ConversationStoreError.sqlite(errorMessage)
        }
    }

    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw ConversationStoreError.sqlite(errorMessage)
        }
    }

    func text(at index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    func double(at index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite statement failed"
    }
}
