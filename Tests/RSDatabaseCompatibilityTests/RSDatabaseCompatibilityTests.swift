import Foundation
import RSDatabase
import RSDatabaseObjC
import Testing

@Suite("RSDatabase/FMDB compatibility")
struct RSDatabaseCompatibilityTests {

    @Test func swiftStringPathProducesContiguousUTF8ForAllContent() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        #expect(database.executeUpdate("CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)", withArgumentsIn: []))

        for (index, value) in Self.testInputs.enumerated() {
            #expect(database.executeUpdate("INSERT INTO t (id, s) VALUES (?, ?)", withArgumentsIn: [index, value]))
        }

        let resultSet = try #require(database.executeQuery("SELECT id, s FROM t ORDER BY id", withArgumentsIn: []))
        defer {
            resultSet.close()
        }

        var rowsRead = 0
        while resultSet.next() {
            let index = Int(resultSet.int(forColumn: "id"))
            let value = try #require(resultSet.swiftString(forColumn: "s"))
            #expect(value == Self.testInputs[index])
            #expect(value.isContiguousUTF8)
            rowsRead += 1
        }
        #expect(rowsRead == Self.testInputs.count)
    }

    @Test func swiftStringHandlesSQLNullAndEmpty() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        #expect(database.executeUpdate("CREATE TABLE t (id INTEGER PRIMARY KEY, s TEXT)", withArgumentsIn: []))
        #expect(database.executeUpdate("INSERT INTO t (id, s) VALUES (0, NULL)", withArgumentsIn: []))
        #expect(database.executeUpdate("INSERT INTO t (id, s) VALUES (1, '')", withArgumentsIn: []))

        let resultSet = try #require(database.executeQuery("SELECT id, s FROM t ORDER BY id", withArgumentsIn: []))
        defer {
            resultSet.close()
        }

        #expect(resultSet.next())
        #expect(resultSet.swiftString(forColumn: "s") == nil)
        #expect(resultSet.string(forColumn: "s") == nil)

        #expect(resultSet.next())
        #expect(resultSet.swiftString(forColumn: "s") == "")
        #expect(resultSet.string(forColumn: "s") == "")
    }

    @Test func typedAccessorsRoundTripCommonNetNewsWireValues() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        let date = Date(timeIntervalSince1970: 1_722_345_678)
        let data = Data([0, 1, 2, 255])
        #expect(database.executeUpdate("""
            CREATE TABLE t (
                id INTEGER PRIMARY KEY,
                title TEXT,
                unread INTEGER,
                score REAL,
                payload BLOB,
                arrived REAL,
                missing TEXT
            )
            """, withArgumentsIn: []))
        let optionalMissing: String? = nil
        #expect(database.executeUpdate(
            "INSERT INTO t (id, title, unread, score, payload, arrived, missing) VALUES (?, ?, ?, ?, ?, ?, ?)",
            withArgumentsIn: [7, "Feed item", true, 4.25, data, date, optionalMissing as Any]
        ))

        let resultSet = try #require(database.executeQuery("SELECT * FROM t", withArgumentsIn: []))
        defer {
            resultSet.close()
        }
        #expect(resultSet.next())
        #expect(resultSet.longLongInt(forColumn: "id") == 7)
        #expect(resultSet.string(forColumn: "title") == "Feed item")
        #expect(resultSet.bool(forColumn: "unread"))
        #expect(resultSet.double(forColumn: "score") == 4.25)
        #expect(resultSet.data(forColumn: "payload") == data)
        #expect(resultSet.date(forColumn: "arrived") == date)
        #expect(resultSet.object(forColumnName: "missing") == nil)
        #expect(resultSet.columnIsNull("missing"))
        #expect(!resultSet.columnIsNull("title"))
        #expect(resultSet.columnIsNull("doesNotExist"))
        #expect(resultSet.columnNameToIndexMap?["title"] != nil)
    }

    @Test func databaseExtrasInsertUpdateDeleteAndCount() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        #expect(database.executeStatements("CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT, unread INTEGER);"))
        database.insertRow(["id": "a", "title": "One", "unread": false], insertType: .normal, tableName: "items")
        database.insertRow(["id": "a", "title": "Two", "unread": true], insertType: .orReplace, tableName: "items")
        database.insertRow(["id": "a", "title": "Ignored", "unread": false], insertType: .orIgnore, tableName: "items")

        #expect(database.count(sql: "SELECT COUNT(*) FROM items;", parameters: [], tableName: "items") == 1)
        var resultSet = try #require(database.selectRowsWhere(key: "id", equalsAnyValue: ["a"], tableName: "items"))
        #expect(resultSet.next())
        #expect(resultSet.swiftString(forColumn: "title") == "Two")
        #expect(resultSet.bool(forColumn: "unread"))
        resultSet.close()

        database.updateRowsWithValue(false, valueKey: "unread", whereKey: "id", equals: "a", tableName: "items")
        resultSet = try #require(database.rs_selectSingleRowWhereKey("id", equalsValue: "a", tableName: "items"))
        #expect(resultSet.next())
        #expect(!resultSet.bool(forColumn: "unread"))
        resultSet.close()

        #expect(database.rs_rowExistsWithValue("a", forKey: "id", tableName: "items"))
        database.deleteRowsWhere(key: "id", equals: "a", tableName: "items")
        #expect(database.rs_tableIsEmpty("items"))
    }

    @Test func singleColumnHelpersMatchObjCSelectorShape() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        #expect(database.executeStatements("CREATE TABLE items (title TEXT);"))
        #expect(database.executeUpdate("INSERT INTO items (title) VALUES (?), (?)", withArgumentsIn: ["One", "Two"]))
        let resultSet = try #require(database.rs_selectColumnWithKey("title", tableName: "items"))
        #expect(resultSet.rs_setForSingleColumnResultSet() == Set(["One", "Two"]))
    }

    @Test func stringSQLHelpersMatchObjCSelectorShape() {
        #expect(NSString.rs_SQLValueList(withPlaceholders: 0) == nil)
        #expect(NSString.rs_SQLValueList(withPlaceholders: 3) == "(?, ?, ?)")
        #expect(NSString.rs_SQLKeysList(with: ["feedURL", "feedID"]) == "(feedURL, feedID)")
        #expect(NSString.rs_SQLKeyPlaceholderPairs(withKeys: ["feedURL", "feedID"]) == "feedURL=?, feedID=?")
    }

    @Test func databaseTableHelpersHandleEmptyInputsAndColumnLookup() throws {
        struct ItemsTable: DatabaseTable {
            let name = "items"
        }

        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        let table = ItemsTable()
        #expect(database.executeStatements("CREATE TABLE items (id TEXT PRIMARY KEY, title TEXT);"))
        table.insertRow(["id": "a", "title": "One"], insertType: .normal, in: database)
        #expect(table.containsColumn("title", in: database))
        #expect(!table.containsColumn("missing", in: database))
        #expect(table.selectRowsWhere(key: "id", inValues: [], in: database) == nil)
        table.deleteRowsWhere(key: "id", equalsAnyValue: [], in: database)
        #expect(table.numberWithSQLAndParameters("SELECT COUNT(*) FROM items;", [], in: database) == 1)
    }

    @Test func fmDatabaseColumnExistsMatchesFMDBSelectorShape() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }

        #expect(database.executeStatements("CREATE TABLE feedSettings (feedID TEXT PRIMARY KEY, lastResponseCode INTEGER);"))
        #expect(database.columnExists("lastResponseCode", inTableWithName: "feedSettings"))
        #expect(database.columnExists("lastresponsecode", inTableWithName: "feedSettings"))
        #expect(!database.columnExists("missing", inTableWithName: "feedSettings"))
        #expect(!database.columnExists("lastResponseCode", inTableWithName: "missing"))
    }

    @Test func transactionsRollbackAndCommit() throws {
        let database = try #require(FMDatabase(path: ":memory:"))
        #expect(database.open())
        defer {
            database.close()
        }
        #expect(database.executeStatements("CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT);"))

        #expect(database.beginTransaction())
        #expect(database.executeUpdate("INSERT INTO items (title) VALUES (?)", withArgumentsIn: ["discard"]))
        #expect(database.rollback())
        #expect(database.count(sql: "SELECT COUNT(*) FROM items;", parameters: [], tableName: "items") == 0)

        #expect(database.beginTransaction())
        #expect(database.executeUpdate("INSERT INTO items (title) VALUES (?)", withArgumentsIn: ["keep"]))
        #expect(database.commit())
        #expect(database.lastInsertRowId() == 1)
        #expect(database.changes() == 1)
        #expect(database.count(sql: "SELECT COUNT(*) FROM items;", parameters: [], tableName: "items") == 1)
    }

    @Test func databaseQueueSerializesSyncAndAsyncAccess() async throws {
        let path = NSTemporaryDirectory() + "/rsdatabase-\(UUID().uuidString).sqlite"
        defer {
            try? FileManager.default.removeItem(atPath: path)
        }
        let queue = DatabaseQueue(databasePath: path)
        queue.runCreateStatements("CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT);")

        queue.runInTransactionSync { database in
            database.executeUpdate("INSERT INTO items (title) VALUES (?)", withArgumentsIn: ["sync"])
        }

        await withCheckedContinuation { continuation in
            queue.runInDatabase { database in
                database.executeUpdate("INSERT INTO items (title) VALUES (?)", withArgumentsIn: ["async"])
                continuation.resume()
            }
        }

        queue.runInDatabaseSync { database in
            #expect(database.count(sql: "SELECT COUNT(*) FROM items;", parameters: [], tableName: "items") == 2)
            #expect(database.tableExists("items"))
        }
    }

    private static let testInputs: [String] = [
        "Hello World",
        "Cafe \u{00E9}",
        "Launch day \u{1F680}",
        "Long mixed body " + String(repeating: "x", count: 2048)
    ]
}
