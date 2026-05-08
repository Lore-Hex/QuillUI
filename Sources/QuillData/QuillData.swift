import CSQLite
import Foundation

public protocol PersistentModel: Codable, Identifiable where ID: Codable, ID: Hashable {}

public struct Schema {
    public var models: [any PersistentModel.Type]

    public init(_ models: [any PersistentModel.Type]) {
        self.models = models
    }
}

public struct ModelConfiguration {
    public var schema: Schema?
    public var url: URL?
    public var isStoredInMemoryOnly: Bool

    public init(schema: Schema? = nil, url: URL? = nil, isStoredInMemoryOnly: Bool = false) {
        self.schema = schema
        self.url = url
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }
}

public final class ModelContainer: @unchecked Sendable {
    let store: QuillDataSQLiteStore

    public init(for schema: Schema, configurations: [ModelConfiguration] = []) throws {
        let configuration = configurations.first ?? ModelConfiguration(schema: schema)
        self.store = try QuillDataSQLiteStore(configuration: configuration)
    }
}

public struct FetchDescriptor<Model: PersistentModel> {
    public var predicate: Predicate<Model>?
    public var filter: ((Model) throws -> Bool)?
    public var sortBy: [SortDescriptor<Model>]
    public var fetchLimit: Int?

    public init(
        predicate: Predicate<Model>? = nil,
        sortBy: [SortDescriptor<Model>] = [],
        fetchLimit: Int? = nil
    ) {
        self.predicate = predicate
        self.filter = nil
        self.sortBy = sortBy
        self.fetchLimit = fetchLimit
    }

    public init(
        filter: @escaping (Model) throws -> Bool,
        sortBy: [SortDescriptor<Model>] = [],
        fetchLimit: Int? = nil
    ) {
        self.predicate = nil
        self.filter = filter
        self.sortBy = sortBy
        self.fetchLimit = fetchLimit
    }
}

public final class ModelContext: @unchecked Sendable {
    private let container: ModelContainer
    private let lock = NSRecursiveLock()
    private var trackedModels: [ObjectIdentifier: TrackedModel] = [:]
    private var recordedErrors: [Error] = []

    public var autosaveEnabled = true

    public init(_ container: ModelContainer) {
        self.container = container
    }

    public func insert<Model: PersistentModel>(_ model: Model) {
        track(model)
        do {
            try container.store.upsert(model)
        } catch {
            record(error)
        }
    }

    public func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        var models = try container.store.fetchAll(Model.self)

        if let predicate = descriptor.predicate {
            guard !(Model.self is AnyObject.Type) else {
                throw QuillDataError.unsupportedPredicate(
                    "Foundation #Predicate cannot safely evaluate class-backed models in QuillData's JSON-row backend yet. Use FetchDescriptor(filter:) for compatibility queries."
                )
            }
            models = try models.filter { model in
                try predicate.evaluate(model)
            }
        }

        if let filter = descriptor.filter {
            models = try models.filter(filter)
        }

        if !descriptor.sortBy.isEmpty {
            models.sort { lhs, rhs in
                for sortDescriptor in descriptor.sortBy {
                    switch sortDescriptor.compare(lhs, rhs) {
                    case .orderedAscending:
                        return true
                    case .orderedDescending:
                        return false
                    case .orderedSame:
                        continue
                    }
                }
                return false
            }
        }

        if let fetchLimit = descriptor.fetchLimit {
            models = Array(models.prefix(max(fetchLimit, 0)))
        }

        models.forEach(track)
        return models
    }

    public func delete<Model: PersistentModel>(_ model: Model) {
        do {
            try container.store.delete(model)
            untrack(model)
        } catch {
            record(error)
        }
    }

    public func delete<Model: PersistentModel>(model: Model.Type) throws {
        try container.store.deleteAll(Model.self)
        untrackAll(Model.self)
    }

    public func delete<Model: PersistentModel>(model: Model.Type, where predicate: Predicate<Model>) throws {
        let matches = try fetch(FetchDescriptor<Model>(predicate: predicate))
        for match in matches {
            try container.store.delete(match)
            untrack(match)
        }
    }

    public func save() throws {
        let errors = lock.withLock { () -> [Error] in
            let errors = recordedErrors
            recordedErrors.removeAll()
            return errors
        }
        if !errors.isEmpty {
            throw QuillDataError.contextOperationFailed(errors.map { error in
                error.localizedDescription
            })
        }

        let models = lock.withLock {
            Array(trackedModels.values)
        }
        for saveTrackedModel in models {
            try saveTrackedModel.save()
        }
    }

    public func saveChanges() throws {
        try save()
    }

    private func track<Model: PersistentModel>(_ model: Model) {
        guard Mirror(reflecting: model).displayStyle == .class else { return }
        let object = model as AnyObject
        let modelType = String(reflecting: Model.self)
        let modelID = String(describing: model.id)
        lock.withLock {
            if trackedModels.values.contains(where: { $0.modelType == modelType && $0.modelID == modelID }) {
                return
            }
            trackedModels[ObjectIdentifier(object)] = TrackedModel(
                modelType: modelType,
                modelID: modelID,
                save: { [weak object] in
                    guard let model = object as? Model else { return }
                    try self.container.store.upsert(model)
                }
            )
        }
    }

    private func untrack<Model: PersistentModel>(_ model: Model) {
        guard Mirror(reflecting: model).displayStyle == .class else { return }
        let modelType = String(reflecting: Model.self)
        let modelID = String(describing: model.id)
        lock.withLock {
            trackedModels = trackedModels.filter { _, trackedModel in
                trackedModel.modelType != modelType || trackedModel.modelID != modelID
            }
        }
    }

    private func untrackAll<Model: PersistentModel>(_ model: Model.Type) {
        let modelType = String(reflecting: Model.self)
        lock.withLock {
            trackedModels = trackedModels.filter { _, trackedModel in
                trackedModel.modelType != modelType
            }
        }
    }

    private func record(_ error: Error) {
        lock.withLock {
            recordedErrors.append(error)
        }
    }

    private struct TrackedModel {
        var modelType: String
        var modelID: String
        var save: () throws -> Void
    }
}

public protocol ModelExecutor {}

public struct DefaultSerialModelExecutor: ModelExecutor {
    public init(modelContext: ModelContext) {}
}

public protocol ModelActor: Actor {
    var modelContainer: ModelContainer { get }
    var modelExecutor: any ModelExecutor { get }
}

@propertyWrapper
public struct Attribute<Value: Codable>: Codable {
    public enum Option: Sendable {
        case unique
        case externalStorage
    }

    private var storage: Value?
    public var option: Option?

    public var wrappedValue: Value {
        get {
            guard let storage else {
                preconditionFailure("QuillData attribute was read before being initialized.")
            }
            return storage
        }
        set {
            storage = newValue
        }
    }

    public init() {
        self.storage = nil
        self.option = nil
    }

    public init(_ option: Option) {
        self.storage = nil
        self.option = option
    }

    public init(wrappedValue: Value) {
        self.storage = wrappedValue
        self.option = nil
    }

    public init(wrappedValue: Value, _ option: Option) {
        self.storage = wrappedValue
        self.option = option
    }

    public init(from decoder: Decoder) throws {
        storage = try Value(from: decoder)
        option = nil
    }

    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

@propertyWrapper
public struct Relationship<Value: Codable>: Codable {
    public enum DeleteRule: Sendable {
        case cascade
        case nullify
        case noAction
    }

    public var wrappedValue: Value
    public var deleteRule: DeleteRule

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
        self.deleteRule = .nullify
    }

    public init(wrappedValue: Value, deleteRule: DeleteRule) {
        self.wrappedValue = wrappedValue
        self.deleteRule = deleteRule
    }

    public init<Root, Inverse>(
        wrappedValue: Value,
        deleteRule: DeleteRule = .nullify,
        inverse: KeyPath<Root, Inverse>? = nil
    ) {
        self.wrappedValue = wrappedValue
        self.deleteRule = deleteRule
    }

    public init(from decoder: Decoder) throws {
        wrappedValue = try Value(from: decoder)
        deleteRule = .nullify
    }

    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

public enum QuillDataError: Error, LocalizedError {
    case openFailed(String)
    case sqlite(String)
    case encodeFailed(String)
    case decodeFailed(String)
    case unsupportedPredicate(String)
    case contextOperationFailed([String])

    public var errorDescription: String? {
        switch self {
        case .openFailed(let message),
             .sqlite(let message),
             .encodeFailed(let message),
             .decodeFailed(let message),
             .unsupportedPredicate(let message):
            return message
        case .contextOperationFailed(let messages):
            return messages.joined(separator: "\n")
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class QuillDataSQLiteStore: @unchecked Sendable {
    private let lock = NSLock()
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: ModelConfiguration) throws {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        let path: String
        if configuration.isStoredInMemoryOnly {
            path = ":memory:"
        } else {
            let url = try configuration.url ?? Self.defaultURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            path = url.path
        }

        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open failure"
            throw QuillDataError.openFailed(message)
        }

        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert<Model: PersistentModel>(_ model: Model) throws {
        try lock.withLock {
            let data: Data
            do {
                data = try encoder.encode(model)
            } catch {
                throw QuillDataError.encodeFailed(error.localizedDescription)
            }

            try execute(
                """
                INSERT INTO quilldata_records (model_type, model_id, json, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(model_type, model_id)
                DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at
                """,
                bindings: [
                    .text(modelType(Model.self)),
                    .text(modelID(model)),
                    .blob(data),
                    .double(Date().timeIntervalSince1970)
                ]
            )
        }
    }

    func fetchAll<Model: PersistentModel>(_ model: Model.Type) throws -> [Model] {
        try lock.withLock {
            let statement = try Statement(
                db: db,
                sql: """
                SELECT json
                FROM quilldata_records
                WHERE model_type = ?
                ORDER BY updated_at ASC
                """
            )
            try statement.bind(modelType(Model.self), at: 1)

            var models: [Model] = []
            while try statement.step() {
                do {
                    models.append(try decoder.decode(Model.self, from: statement.data(at: 0)))
                } catch {
                    throw QuillDataError.decodeFailed(error.localizedDescription)
                }
            }
            return models
        }
    }

    func delete<Model: PersistentModel>(_ model: Model) throws {
        try lock.withLock {
            try execute(
                "DELETE FROM quilldata_records WHERE model_type = ? AND model_id = ?",
                bindings: [.text(modelType(Model.self)), .text(modelID(model))]
            )
        }
    }

    func deleteAll<Model: PersistentModel>(_ model: Model.Type) throws {
        try lock.withLock {
            try execute(
                "DELETE FROM quilldata_records WHERE model_type = ?",
                bindings: [.text(modelType(Model.self))]
            )
        }
    }

    private static func defaultURL() throws -> URL {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".quilldata", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.sqlite")
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS quilldata_records (
                model_type TEXT NOT NULL,
                model_id TEXT NOT NULL,
                json BLOB NOT NULL,
                updated_at REAL NOT NULL,
                PRIMARY KEY(model_type, model_id)
            )
            """,
            bindings: []
        )
    }

    private func modelType<Model: PersistentModel>(_ model: Model.Type) -> String {
        String(reflecting: Model.self)
    }

    private func modelID<Model: PersistentModel>(_ model: Model) -> String {
        String(describing: model.id)
    }

    private enum BindingValue {
        case blob(Data)
        case double(Double)
        case text(String)
    }

    private func execute(_ sql: String, bindings: [BindingValue]) throws {
        let statement = try Statement(db: db, sql: sql)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .blob(let data):
                try statement.bind(data, at: index)
            case .double(let value):
                try statement.bind(value, at: index)
            case .text(let value):
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
            throw QuillDataError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite prepare failed")
        }
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ data: Data, at index: Int32) throws {
        try data.withUnsafeBytes { bytes in
            let result = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), sqliteTransient)
            guard result == SQLITE_OK else {
                throw QuillDataError.sqlite(errorMessage)
            }
        }
    }

    func bind(_ value: Double, at index: Int32) throws {
        let result = sqlite3_bind_double(statement, index, value)
        guard result == SQLITE_OK else {
            throw QuillDataError.sqlite(errorMessage)
        }
    }

    func bind(_ value: String, at index: Int32) throws {
        let result = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        guard result == SQLITE_OK else {
            throw QuillDataError.sqlite(errorMessage)
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
            throw QuillDataError.sqlite(errorMessage)
        }
    }

    func data(at index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, index) else { return Data() }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite statement failed"
    }
}
