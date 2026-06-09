import CSQLite
import Foundation

public enum RSDatabaseInsertType: Int, Sendable {
    case normal
    case orReplace
    case orIgnore
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class FMDatabase: @unchecked Sendable {
    public var traceExecution = false
    public var checkedOut = false
    public var crashOnErrors = false
    public var logsErrors = true
    public var cachedStatements = [String: OpaquePointer]()

    private let path: String
    private var handle: OpaquePointer?
    private var shouldCacheStatements = false
    private var lastSQLiteCode: Int32 = SQLITE_OK

    public static func database(withPath path: String?) -> FMDatabase? {
        FMDatabase(path: path)
    }

    public init?(path: String?) {
        self.path = path.flatMap { $0.isEmpty ? nil : $0 } ?? ":memory:"
    }

    deinit {
        _ = close()
    }

    @discardableResult
    public func open() -> Bool {
        guard handle == nil else {
            return true
        }
        var opened: OpaquePointer?
        let code = path.withCString { sqlite3_open($0, &opened) }
        lastSQLiteCode = code
        guard code == SQLITE_OK else {
            if let opened {
                sqlite3_close(opened)
            }
            return false
        }
        handle = opened
        return true
    }

    @discardableResult
    public func close() -> Bool {
        cachedStatements.values.forEach { sqlite3_finalize($0) }
        cachedStatements.removeAll()
        guard let handle else {
            return true
        }
        let code = sqlite3_close(handle)
        lastSQLiteCode = code
        if code == SQLITE_OK {
            self.handle = nil
            return true
        }
        return false
    }

    public func databasePath() -> String? {
        path
    }

    public func setShouldCacheStatements(_ value: Bool) {
        shouldCacheStatements = value
    }

    @discardableResult
    public func executeStatements(_ sql: String) -> Bool {
        guard open(), let handle else {
            return false
        }
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        lastSQLiteCode = code
        return code == SQLITE_OK
    }

    @discardableResult
    public func executeUpdate(_ sql: String, withArgumentsIn arguments: [Any]? = nil) -> Bool {
        guard let statement = prepare(sql) else {
            return false
        }
        defer {
            sqlite3_finalize(statement)
        }
        guard bind(arguments ?? [], to: statement) else {
            return false
        }
        let code = sqlite3_step(statement)
        lastSQLiteCode = code
        return code == SQLITE_DONE || code == SQLITE_ROW
    }

    public func executeQuery(_ sql: String, withArgumentsIn arguments: [Any]? = nil) -> FMResultSet? {
        guard let statement = prepare(sql) else {
            return nil
        }
        guard bind(arguments ?? [], to: statement) else {
            sqlite3_finalize(statement)
            return nil
        }
        return FMResultSet(statement: statement, database: self, query: sql)
    }

    @discardableResult
    public func beginTransaction() -> Bool {
        executeUpdate("begin exclusive transaction;", withArgumentsIn: nil)
    }

    @discardableResult
    public func commit() -> Bool {
        executeUpdate("commit transaction;", withArgumentsIn: nil)
    }

    @discardableResult
    public func rollback() -> Bool {
        executeUpdate("rollback transaction;", withArgumentsIn: nil)
    }

    public func lastInsertRowId() -> Int64 {
        guard let handle else {
            return 0
        }
        return sqlite3_last_insert_rowid(handle)
    }

    public func changes() -> Int32 {
        guard let handle else {
            return 0
        }
        return sqlite3_changes(handle)
    }

    public func tableExists(_ tableName: String) -> Bool {
        let sql = "select name from sqlite_master where type = 'table' and lower(name) = lower(?) limit 1;"
        guard let resultSet = executeQuery(sql, withArgumentsIn: [tableName]) else {
            return false
        }
        defer {
            resultSet.close()
        }
        return resultSet.next()
    }

    public func columnExists(_ columnName: String, inTableWithName tableName: String) -> Bool {
        let sql = "pragma table_info(\(Self.quotedIdentifier(tableName)));"
        guard let resultSet = executeQuery(sql, withArgumentsIn: []) else {
            return false
        }
        defer {
            resultSet.close()
        }
        while resultSet.next() {
            if resultSet.string(forColumn: "name")?.caseInsensitiveCompare(columnName) == .orderedSame {
                return true
            }
        }
        return false
    }

    public func lastErrorMessage() -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else {
            return "not an error"
        }
        return String(cString: message)
    }

    public func lastErrorCode() -> Int32 {
        guard let handle else {
            return lastSQLiteCode
        }
        return sqlite3_errcode(handle)
    }

    public func hadError() -> Bool {
        let code = lastErrorCode()
        return code != SQLITE_OK && code != SQLITE_ROW && code != SQLITE_DONE
    }

    public func lastError() -> NSError {
        NSError(
            domain: "FMDatabase",
            code: Int(lastErrorCode()),
            userInfo: [NSLocalizedDescriptionKey: lastErrorMessage()]
        )
    }

    @discardableResult
    public func rs_deleteRowsWhereKey(_ key: String, inValues values: [Any], tableName: String) -> Bool {
        guard !values.isEmpty else {
            return true
        }
        let placeholders = Self.placeholders(values.count)
        return executeUpdate("delete from \(tableName) where \(key) in (\(placeholders));", withArgumentsIn: values)
    }

    @discardableResult
    public func rs_deleteRowsWhereKey(_ key: String, equalsValue value: Any, tableName: String) -> Bool {
        executeUpdate("delete from \(tableName) where \(key) = ?;", withArgumentsIn: [value])
    }

    public func rs_selectRowsWhereKey(_ key: String, inValues values: [Any], tableName: String) -> FMResultSet? {
        guard !values.isEmpty else {
            return nil
        }
        let placeholders = Self.placeholders(values.count)
        return executeQuery("select * from \(tableName) where \(key) in (\(placeholders));", withArgumentsIn: values)
    }

    public func rs_selectRowsWhereKey(_ key: String, equalsValue value: Any, tableName: String) -> FMResultSet? {
        executeQuery("select * from \(tableName) where \(key) = ?;", withArgumentsIn: [value])
    }

    public func rs_selectSingleRowWhereKey(_ key: String, equalsValue value: Any, tableName: String) -> FMResultSet? {
        executeQuery("select * from \(tableName) where \(key) = ? limit 1;", withArgumentsIn: [value])
    }

    public func rs_selectAllRows(_ tableName: String) -> FMResultSet? {
        executeQuery("select * from \(tableName);", withArgumentsIn: [])
    }

    public func rs_selectColumn(withKey key: String, tableName: String) -> FMResultSet? {
        executeQuery("select \(key) from \(tableName);", withArgumentsIn: [])
    }

    public func rs_selectColumnWithKey(_ key: String, tableName: String) -> FMResultSet? {
        rs_selectColumn(withKey: key, tableName: tableName)
    }

    public func rs_rowExistsWithValue(_ value: Any, forKey key: String, tableName: String) -> Bool {
        guard let resultSet = executeQuery("select 1 from \(tableName) where \(key) = ? limit 1;", withArgumentsIn: [value]) else {
            return false
        }
        defer {
            resultSet.close()
        }
        return resultSet.next()
    }

    public func rs_tableIsEmpty(_ tableName: String) -> Bool {
        guard let resultSet = executeQuery("select 1 from \(tableName) limit 1;", withArgumentsIn: []) else {
            return true
        }
        defer {
            resultSet.close()
        }
        return !resultSet.next()
    }

    @discardableResult
    public func rs_updateRows(with dictionary: [String: Any], whereKey key: String, equalsValue value: Any, tableName: String) -> Bool {
        guard !dictionary.isEmpty else {
            return true
        }
        let assignments = dictionary.keys.sorted().map { "\($0) = ?" }.joined(separator: ", ")
        let values = dictionary.keys.sorted().map { dictionary[$0] as Any } + [value]
        return executeUpdate("update \(tableName) set \(assignments) where \(key) = ?;", withArgumentsIn: values)
    }

    @discardableResult
    public func rs_updateRows(with dictionary: [String: Any], whereKey key: String, inValues keyValues: [Any], tableName: String) -> Bool {
        guard !dictionary.isEmpty, !keyValues.isEmpty else {
            return true
        }
        let sortedKeys = dictionary.keys.sorted()
        let assignments = sortedKeys.map { "\($0) = ?" }.joined(separator: ", ")
        let placeholders = Self.placeholders(keyValues.count)
        let values = sortedKeys.map { dictionary[$0] as Any } + keyValues
        return executeUpdate("update \(tableName) set \(assignments) where \(key) in (\(placeholders));", withArgumentsIn: values)
    }

    @discardableResult
    public func rs_updateRows(withValue value: Any, valueKey: String, whereKey key: String, inValues keyValues: [Any], tableName: String) -> Bool {
        guard !keyValues.isEmpty else {
            return true
        }
        let placeholders = Self.placeholders(keyValues.count)
        return executeUpdate(
            "update \(tableName) set \(valueKey) = ? where \(key) in (\(placeholders));",
            withArgumentsIn: [value] + keyValues
        )
    }

    @discardableResult
    public func rs_insertRow(with dictionary: [String: Any], insertType: RSDatabaseInsertType, tableName: String) -> Bool {
        guard !dictionary.isEmpty else {
            return false
        }
        let keys = dictionary.keys.sorted()
        let columns = keys.joined(separator: ", ")
        let placeholders = Self.placeholders(keys.count)
        let verb: String
        switch insertType {
        case .normal:
            verb = "insert"
        case .orReplace:
            verb = "insert or replace"
        case .orIgnore:
            verb = "insert or ignore"
        }
        return executeUpdate(
            "\(verb) into \(tableName) (\(columns)) values (\(placeholders));",
            withArgumentsIn: keys.map { dictionary[$0] as Any }
        )
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard open(), let handle else {
            return nil
        }
        var statement: OpaquePointer?
        let code = sql.withCString { sqlite3_prepare_v2(handle, $0, -1, &statement, nil) }
        lastSQLiteCode = code
        guard code == SQLITE_OK else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        return statement
    }

    private func bind(_ arguments: [Any], to statement: OpaquePointer) -> Bool {
        for (offset, argument) in arguments.enumerated() {
            let code = bind(argument, to: statement, at: Int32(offset + 1))
            lastSQLiteCode = code
            guard code == SQLITE_OK else {
                return false
            }
        }
        return true
    }

    private func bind(_ argument: Any, to statement: OpaquePointer, at index: Int32) -> Int32 {
        guard let argument = Self.unwrapOptional(argument) else {
            return sqlite3_bind_null(statement, index)
        }
        switch argument {
        case let value as NSNull:
            _ = value
            return sqlite3_bind_null(statement, index)
        case let value as Bool:
            return sqlite3_bind_int(statement, index, value ? 1 : 0)
        case let value as Int:
            return sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as Int8:
            return sqlite3_bind_int(statement, index, Int32(value))
        case let value as Int16:
            return sqlite3_bind_int(statement, index, Int32(value))
        case let value as Int32:
            return sqlite3_bind_int(statement, index, value)
        case let value as Int64:
            return sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as UInt:
            return sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as UInt8:
            return sqlite3_bind_int(statement, index, Int32(value))
        case let value as UInt16:
            return sqlite3_bind_int(statement, index, Int32(value))
        case let value as UInt32:
            return sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        case let value as UInt64:
            return sqlite3_bind_int64(statement, index, sqlite3_int64(bitPattern: value))
        case let value as Float:
            return sqlite3_bind_double(statement, index, Double(value))
        case let value as Double:
            return sqlite3_bind_double(statement, index, value)
        case let value as Date:
            return sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        case let value as Data:
            if value.isEmpty {
                var byte: UInt8 = 0
                return withUnsafeBytes(of: &byte) {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, 0, sqliteTransient)
                }
            }
            return value.withUnsafeBytes {
                sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(value.count), sqliteTransient)
            }
        case let value as URL:
            return bind(value.absoluteString, to: statement, at: index)
        case let value as String:
            return value.withCString {
                sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
            }
        case let value as NSString:
            return bind(value as String, to: statement, at: index)
        case let value as NSNumber:
            let objCType = String(cString: value.objCType)
            if objCType == "c" || objCType == "B" {
                return sqlite3_bind_int(statement, index, value.boolValue ? 1 : 0)
            }
            if objCType == "f" || objCType == "d" {
                return sqlite3_bind_double(statement, index, value.doubleValue)
            }
            return sqlite3_bind_int64(statement, index, value.int64Value)
        default:
            return bind(String(describing: argument), to: statement, at: index)
        }
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }
        return mirror.children.first?.value
    }
}

public final class FMResultSet: @unchecked Sendable {
    public let query: String
    public var columnNameToIndexMap: [String: Int32]?

    private var statement: OpaquePointer?
    private weak var database: FMDatabase?
    private var hasCurrentRow = false

    init(statement: OpaquePointer, database: FMDatabase, query: String) {
        self.statement = statement
        self.database = database
        self.query = query
        self.columnNameToIndexMap = Self.makeColumnMap(statement)
    }

    deinit {
        close()
    }

    public func close() {
        if let statement {
            sqlite3_finalize(statement)
            self.statement = nil
        }
        hasCurrentRow = false
    }

    @discardableResult
    public func next() -> Bool {
        guard let statement else {
            return false
        }
        let code = sqlite3_step(statement)
        if code == SQLITE_ROW {
            hasCurrentRow = true
            return true
        }
        hasCurrentRow = false
        if code == SQLITE_DONE {
            close()
        }
        return false
    }

    public func nextWithError(_ error: UnsafeMutablePointer<NSError?>?) -> Bool {
        let didAdvance = next()
        if !didAdvance, let database, database.hadError() {
            error?.pointee = database.lastError()
        }
        return didAdvance
    }

    public func hasAnotherRow() -> Bool {
        hasCurrentRow
    }

    public func columnCount() -> Int32 {
        guard let statement else {
            return 0
        }
        return sqlite3_column_count(statement)
    }

    public func columnIndex(forName columnName: String) -> Int32 {
        columnNameToIndexMap?[columnName.lowercased()] ?? -1
    }

    public func columnIndexForName(_ columnName: String) -> Int32 {
        columnIndex(forName: columnName)
    }

    public func columnName(forIndex columnIdx: Int32) -> String? {
        guard let statement, columnIdx >= 0, columnIdx < columnCount(), let name = sqlite3_column_name(statement, columnIdx) else {
            return nil
        }
        return String(cString: name)
    }

    public func columnNameForIndex(_ columnIdx: Int32) -> String? {
        columnName(forIndex: columnIdx)
    }

    public func int(forColumn columnName: String) -> Int32 {
        int(forColumnIndex: columnIndex(forName: columnName))
    }

    public func int(forColumnIndex columnIdx: Int32) -> Int32 {
        guard let statement, isValid(columnIdx) else {
            return 0
        }
        return sqlite3_column_int(statement, columnIdx)
    }

    public func long(forColumn columnName: String) -> Int {
        long(forColumnIndex: columnIndex(forName: columnName))
    }

    public func long(forColumnIndex columnIdx: Int32) -> Int {
        Int(longLongInt(forColumnIndex: columnIdx))
    }

    public func longLongInt(forColumn columnName: String) -> Int64 {
        longLongInt(forColumnIndex: columnIndex(forName: columnName))
    }

    public func longLongInt(forColumnIndex columnIdx: Int32) -> Int64 {
        guard let statement, isValid(columnIdx) else {
            return 0
        }
        return Int64(sqlite3_column_int64(statement, columnIdx))
    }

    public func unsignedLongLongInt(forColumn columnName: String) -> UInt64 {
        unsignedLongLongInt(forColumnIndex: columnIndex(forName: columnName))
    }

    public func unsignedLongLongInt(forColumnIndex columnIdx: Int32) -> UInt64 {
        UInt64(bitPattern: longLongInt(forColumnIndex: columnIdx))
    }

    public func bool(forColumn columnName: String) -> Bool {
        bool(forColumnIndex: columnIndex(forName: columnName))
    }

    public func bool(forColumnIndex columnIdx: Int32) -> Bool {
        int(forColumnIndex: columnIdx) != 0
    }

    public func double(forColumn columnName: String) -> Double {
        double(forColumnIndex: columnIndex(forName: columnName))
    }

    public func double(forColumnIndex columnIdx: Int32) -> Double {
        guard let statement, isValid(columnIdx) else {
            return 0
        }
        return sqlite3_column_double(statement, columnIdx)
    }

    public func string(forColumn columnName: String) -> String? {
        string(forColumnIndex: columnIndex(forName: columnName))
    }

    public func string(forColumnIndex columnIdx: Int32) -> String? {
        guard let statement, isValid(columnIdx), sqlite3_column_type(statement, columnIdx) != SQLITE_NULL else {
            return nil
        }
        guard let cString = sqlite3_column_text(statement, columnIdx) else {
            return nil
        }
        return String(cString: cString)
    }

    public func date(forColumn columnName: String) -> Date? {
        date(forColumnIndex: columnIndex(forName: columnName))
    }

    public func date(forColumnIndex columnIdx: Int32) -> Date? {
        guard let statement, isValid(columnIdx), sqlite3_column_type(statement, columnIdx) != SQLITE_NULL else {
            return nil
        }
        return Date(timeIntervalSince1970: double(forColumnIndex: columnIdx))
    }

    public func data(forColumn columnName: String) -> Data? {
        data(forColumnIndex: columnIndex(forName: columnName))
    }

    public func data(forColumnIndex columnIdx: Int32) -> Data? {
        guard let statement, isValid(columnIdx), sqlite3_column_type(statement, columnIdx) != SQLITE_NULL else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, columnIdx))
        guard count > 0 else {
            return Data()
        }
        guard let bytes = sqlite3_column_blob(statement, columnIdx) else {
            return nil
        }
        return Data(bytes: bytes, count: count)
    }

    public func dataNoCopy(forColumn columnName: String) -> Data? {
        data(forColumn: columnName)
    }

    public func dataNoCopy(forColumnIndex columnIdx: Int32) -> Data? {
        data(forColumnIndex: columnIdx)
    }

    public func object(forColumnName columnName: String) -> Any? {
        object(forColumnIndex: columnIndex(forName: columnName))
    }

    public func object(forColumnIndex columnIdx: Int32) -> Any? {
        guard let statement, isValid(columnIdx) else {
            return nil
        }
        switch sqlite3_column_type(statement, columnIdx) {
        case SQLITE_INTEGER:
            return longLongInt(forColumnIndex: columnIdx)
        case SQLITE_FLOAT:
            return double(forColumnIndex: columnIdx)
        case SQLITE_TEXT:
            return string(forColumnIndex: columnIdx)
        case SQLITE_BLOB:
            return data(forColumnIndex: columnIdx)
        case SQLITE_NULL:
            return nil
        default:
            return nil
        }
    }

    public func columnIsNull(_ columnName: String) -> Bool {
        columnIsNull(columnIndex(forName: columnName))
    }

    public func columnIsNull(_ columnIdx: Int32) -> Bool {
        guard let statement, isValid(columnIdx) else {
            return true
        }
        return sqlite3_column_type(statement, columnIdx) == SQLITE_NULL
    }

    public func kvcMagic(_ columnName: String) -> Any? {
        object(forColumnName: columnName)
    }

    private static func makeColumnMap(_ statement: OpaquePointer) -> [String: Int32] {
        var map = [String: Int32]()
        let count = sqlite3_column_count(statement)
        for index in 0..<count {
            if let name = sqlite3_column_name(statement, index) {
                map[String(cString: name).lowercased()] = index
            }
        }
        return map
    }

    private func isValid(_ columnIdx: Int32) -> Bool {
        guard let statement else {
            return false
        }
        return columnIdx >= 0 && columnIdx < sqlite3_column_count(statement)
    }
}

public extension FMResultSet {
    func rs_arrayForSingleColumnResultSet() -> [Any] {
        var values = [Any]()
        while next() {
            if let value = object(forColumnIndex: 0) {
                values.append(value)
            }
        }
        close()
        return values
    }

    func rs_setForSingleColumnResultSet() -> Set<AnyHashable> {
        Set(rs_arrayForSingleColumnResultSet().compactMap { $0 as? AnyHashable })
    }
}

public extension NSString {
    static func rs_SQLValueList(withPlaceholders count: UInt) -> String? {
        guard count > 0 else {
            return nil
        }
        return "(\(Array(repeating: "?", count: Int(count)).joined(separator: ", ")))"
    }

    static func rs_SQLKeysList(with keys: [Any]) -> String {
        "(\(keys.map { String(describing: $0) }.joined(separator: ", ")))"
    }

    static func rs_SQLKeyPlaceholderPairs(withKeys keys: [Any]) -> String {
        keys.map { "\(String(describing: $0))=?" }.joined(separator: ", ")
    }
}
