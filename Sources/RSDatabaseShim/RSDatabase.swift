import Foundation
@_exported import RSDatabaseObjC

public typealias DatabaseResult = Result<FMDatabase, Error>
// Upstream NetNewsWire (2026-06) hands the database directly to the block;
// the older DatabaseResult-based shape is kept above for source back-compat.
public typealias DatabaseBlock = @Sendable (FMDatabase) -> Void
public typealias DatabaseCompletionBlock = @Sendable (Error?) -> Void
public typealias DatabaseDictionary = [String: Any]

public extension DatabaseResult {
    var database: FMDatabase? {
        switch self {
        case .success(let database):
            return database
        case .failure:
            return nil
        }
    }

    var error: Error? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

public final class DatabaseQueue: @unchecked Sendable {
    private let database: FMDatabase
    private let serialDispatchQueue: DispatchQueue

    public init(databasePath: String) {
        self.serialDispatchQueue = DispatchQueue(label: "DatabaseQueue (Serial) - \(databasePath)")
        self.database = FMDatabase.openAndSetUpDatabase(path: databasePath)
    }

    public func runInDatabaseSync(_ databaseBlock: DatabaseBlock) {
        serialDispatchQueue.sync {
            databaseBlock(database)
        }
    }

    public func runInDatabase(_ databaseBlock: @escaping DatabaseBlock) {
        serialDispatchQueue.async {
            databaseBlock(self.database)
        }
    }

    public func runInTransactionSync(_ databaseBlock: @escaping DatabaseBlock) {
        serialDispatchQueue.sync {
            self.database.beginTransaction()
            databaseBlock(self.database)
            self.database.commit()
        }
    }

    public func runInTransaction(_ databaseBlock: @escaping DatabaseBlock) {
        serialDispatchQueue.async {
            self.database.beginTransaction()
            databaseBlock(self.database)
            self.database.commit()
        }
    }

    public func runCreateStatements(_ statements: String) {
        runInDatabaseSync { database in
            database.runCreateStatements(statements)
        }
    }

    public func vacuum() async {
        await withCheckedContinuation { continuation in
            runInDatabase { database in
                database.vacuum()
                continuation.resume()
            }
        }
    }
}

public protocol DatabaseTable {
    var name: String { get }
}

public extension DatabaseTable {
    func selectRowsWhere(key: String, equals value: Any, in database: FMDatabase) -> FMResultSet? {
        database.rs_selectRowsWhereKey(key, equalsValue: value, tableName: name)
    }

    func selectRowsWhere(key: String, inValues values: [Any], in database: FMDatabase) -> FMResultSet? {
        guard !values.isEmpty else {
            return nil
        }
        return database.rs_selectRowsWhereKey(key, inValues: values, tableName: name)
    }

    func deleteRowsWhere(key: String, equalsAnyValue values: [Any], in database: FMDatabase) {
        guard !values.isEmpty else {
            return
        }
        database.rs_deleteRowsWhereKey(key, inValues: values, tableName: name)
    }

    func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, matches: [Any], database: FMDatabase) {
        database.rs_updateRows(withValue: value, valueKey: valueKey, whereKey: whereKey, inValues: matches, tableName: name)
    }

    func updateRowsWithDictionary(_ dictionary: DatabaseDictionary, whereKey: String, matches: Any, database: FMDatabase) {
        database.rs_updateRows(with: dictionary, whereKey: whereKey, equalsValue: matches, tableName: name)
    }

    func insertRows(_ dictionaries: [DatabaseDictionary], insertType: RSDatabaseInsertType, in database: FMDatabase) {
        dictionaries.forEach { database.rs_insertRow(with: $0, insertType: insertType, tableName: name) }
    }

    func insertRow(_ rowDictionary: DatabaseDictionary, insertType: RSDatabaseInsertType, in database: FMDatabase) {
        insertRows([rowDictionary], insertType: insertType, in: database)
    }

    func numberWithSQLAndParameters(_ sql: String, _ parameters: [Any], in database: FMDatabase) -> Int {
        guard let resultSet = database.executeQuery(sql, withArgumentsIn: parameters), resultSet.next() else {
            return 0
        }
        defer {
            resultSet.close()
        }
        return Int(resultSet.int(forColumnIndex: 0))
    }

    func containsColumn(_ columnName: String, in database: FMDatabase) -> Bool {
        guard let resultSet = database.executeQuery("select * from \(name) limit 1;", withArgumentsIn: nil) else {
            return false
        }
        defer {
            resultSet.close()
        }
        return resultSet.columnNameToIndexMap?[columnName.lowercased()] != nil
    }
}

public extension FMResultSet {
    func intWithCountResult() -> Int? {
        guard next() else {
            return nil
        }
        let count = Int(long(forColumnIndex: 0))
        close()
        return count
    }

    func compactMap<T>(_ completion: (_ row: FMResultSet) -> T?) -> [T] {
        var objects = [T]()
        while next() {
            if let object = completion(self) {
                objects.append(object)
            }
        }
        close()
        return objects
    }

    func mapToSet<T>(_ completion: (_ row: FMResultSet) -> T?) -> Set<T> {
        Set(compactMap(completion))
    }

    func swiftString(forColumn columnName: String) -> String? {
        guard let data = dataNoCopy(forColumn: columnName) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    func swiftString(forColumnIndex columnIdx: Int32) -> String? {
        guard let data = dataNoCopy(forColumnIndex: columnIdx) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public extension FMDatabase {
    static func openAndSetUpDatabase(path: String) -> FMDatabase {
        let database = FMDatabase(path: path)!
        database.open()
        database.executeStatements("PRAGMA journal_mode = DELETE;")
        database.executeStatements("PRAGMA synchronous = 1;")
        database.setShouldCacheStatements(true)
        return database
    }

    func executeUpdateInTransaction(_ sql: String, withArgumentsIn parameters: [Any]? = nil) {
        beginTransaction()
        guard executeUpdate(sql, withArgumentsIn: parameters) else {
            rollback()
            return
        }
        commit()
    }

    func vacuum() {
        executeStatements("vacuum;")
    }

    func vacuumIfNeeded(daysBetweenVacuums: Int = RSDatabaseInfoTable.defaultDaysBetweenVacuums) {
        RSDatabaseInfoTable.createTableIfNeeded(database: self)
        if let lastVacuumDate = RSDatabaseInfoTable.lastVacuumDate(database: self) {
            let secondsBetweenVacuums = TimeInterval(daysBetweenVacuums) * 24 * 60 * 60
            if Date().timeIntervalSince(lastVacuumDate) < secondsBetweenVacuums {
                return
            }
        }
        vacuum()
        RSDatabaseInfoTable.setLastVacuumDate(Date(), database: self)
    }

    func runCreateStatements(_ statements: String) {
        statements.enumerateLines { line, _ in
            if line.lowercased().hasPrefix("create") {
                self.executeStatements(line)
            }
        }
    }

    func insertRows(_ dictionaries: [DatabaseDictionary], insertType: RSDatabaseInsertType, tableName: String) {
        dictionaries.forEach { insertRow($0, insertType: insertType, tableName: tableName) }
    }

    func insertRow(_ dictionary: DatabaseDictionary, insertType: RSDatabaseInsertType, tableName: String) {
        rs_insertRow(with: dictionary, insertType: insertType, tableName: tableName)
    }

    func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, equalsAnyValue values: [Any], tableName: String) {
        rs_updateRows(withValue: value, valueKey: valueKey, whereKey: whereKey, inValues: values, tableName: tableName)
    }

    func updateRowsWithValue(_ value: Any, valueKey: String, whereKey: String, equals match: Any, tableName: String) {
        updateRowsWithValue(value, valueKey: valueKey, whereKey: whereKey, equalsAnyValue: [match], tableName: tableName)
    }

    func updateRowsWithDictionary(_ dictionary: [String: Any], whereKey: String, equals value: Any, tableName: String) {
        rs_updateRows(with: dictionary, whereKey: whereKey, equalsValue: value, tableName: tableName)
    }

    func deleteRowsWhere(key: String, equalsAnyValue values: [Any], tableName: String) {
        rs_deleteRowsWhereKey(key, inValues: values, tableName: tableName)
    }

    func deleteRowsWhere(key: String, equals value: Any, tableName: String) {
        rs_deleteRowsWhereKey(key, equalsValue: value, tableName: tableName)
    }

    func selectRowsWhere(key: String, equalsAnyValue values: [Any], tableName: String) -> FMResultSet? {
        rs_selectRowsWhereKey(key, inValues: values, tableName: tableName)
    }

    func count(sql: String, parameters: [Any]?, tableName: String) -> Int? {
        guard let resultSet = executeQuery(sql, withArgumentsIn: parameters) else {
            return nil
        }
        return resultSet.intWithCountResult()
    }
}

public enum RSDatabaseInfoTable {
    public static let tableName = "RSDatabaseInfo"
    public static let defaultDaysBetweenVacuums = 13

    private static let keyColumn = "key"
    private static let valueColumn = "value"
    private static let lastVacuumDateKey = "lastVacuumDate"

    static func createTableIfNeeded(database: FMDatabase) {
        database.executeStatements("CREATE TABLE IF NOT EXISTS \(tableName) (\(keyColumn) TEXT PRIMARY KEY NOT NULL, \(valueColumn));")
    }

    static func lastVacuumDate(database: FMDatabase) -> Date? {
        guard let resultSet = database.executeQuery(
            "SELECT \(valueColumn) FROM \(tableName) WHERE \(keyColumn) = ?;",
            withArgumentsIn: [lastVacuumDateKey]
        ) else {
            return nil
        }
        defer {
            resultSet.close()
        }
        guard resultSet.next() else {
            return nil
        }
        return Date(timeIntervalSince1970: resultSet.double(forColumn: valueColumn))
    }

    static func setLastVacuumDate(_ date: Date, database: FMDatabase) {
        database.executeUpdate(
            "INSERT OR REPLACE INTO \(tableName) (\(keyColumn), \(valueColumn)) VALUES (?, ?);",
            withArgumentsIn: [lastVacuumDateKey, date.timeIntervalSince1970]
        )
    }
}
