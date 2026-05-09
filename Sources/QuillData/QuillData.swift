import Foundation
@_exported import GRDB

public protocol PersistentModel: Codable {}

public protocol QuillTableMappable {
    associatedtype TableStruct: Codable, Sendable, Identifiable, FetchableRecord, PersistableRecord
    static var createTableSQL: String { get }
    static var tableName: String { get }
    func toTableStruct() -> TableStruct
    func update(from tableStruct: TableStruct)
    static func fromTableStruct(_ tableStruct: TableStruct) -> Self
    static func fetchPersistentModels(_ db: Database, sql: String) throws -> [any PersistentModel]
}

public extension QuillTableMappable where Self: PersistentModel {
    static func fetchPersistentModels(_ db: Database, sql: String) throws -> [any PersistentModel] {
        let records: [TableStruct] = try TableStruct.fetchAll(db, sql: sql)
        return records.map { fromTableStruct($0) }
    }
}

@attached(peer)
public macro Attribute(_ options: AttributeOption...) = #externalMacro(module: "QuillDataMacros", type: "QuillAttributeMacro")

@attached(peer)
public macro Relationship(
    _ options: RelationshipOption...,
    deleteRule: RelationshipOption? = nil,
    inverse: AnyKeyPath? = nil
) = #externalMacro(module: "QuillDataMacros", type: "QuillRelationshipMacro")

public enum AttributeOption { case unique, externalStorage }
public enum RelationshipOption { case nullify, cascade }
public extension RelationshipOption { static func deleteRule(_ rule: RelationshipOption) -> RelationshipOption { rule } }

@attached(member, names: named(TableStruct), named(createTableSQL), named(tableName), named(fromTableStruct), arbitrary)
@attached(extension, conformances: PersistentModel, QuillTableMappable)
public macro QuillModel() = #externalMacro(module: "QuillDataMacros", type: "QuillModelMacro")

@freestanding(expression)
public macro QuillPredicate<Model: PersistentModel>(_ closure: (Model) -> Bool) -> Predicate<Model> = #externalMacro(module: "QuillDataMacros", type: "QuillPredicateMacro")

public struct Schema {
    public var models: [any PersistentModel.Type]
    public init(_ models: [any PersistentModel.Type]) {
        self.models = models
    }
}

public final class ModelContainer: @unchecked Sendable {
    let store: QuillDataSQLiteStore
    public init(for schema: Schema, configurations: [ModelConfiguration] = []) throws {
        let configuration = configurations.first ?? ModelConfiguration(schema: schema)
        self.store = try QuillDataSQLiteStore(configuration: configuration)
        try store.migrate(schema)
    }
}

public protocol ModelActor: Actor {}

public struct ModelExecutor: Sendable {
    public let modelContext: ModelContext
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
}

public typealias DefaultSerialModelExecutor = ModelExecutor

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
        self.sortBy = sortBy
        self.fetchLimit = fetchLimit
    }

    public init(
        filter: @escaping (Model) throws -> Bool,
        sortBy: [SortDescriptor<Model>] = [],
        fetchLimit: Int? = nil
    ) {
        self.filter = filter
        self.sortBy = sortBy
        self.fetchLimit = fetchLimit
    }
}

public struct Predicate<Model: PersistentModel>: Sendable {
    private let body: @Sendable (Model) throws -> Bool
    public let sqlFilter: String?

    public init(_ body: @escaping @Sendable (Model) throws -> Bool) {
        self.body = body
        self.sqlFilter = nil
    }

    public init(sqlFilter: String, _ body: @escaping @Sendable (Model) throws -> Bool) {
        self.body = body
        self.sqlFilter = sqlFilter
    }

    public func evaluate(_ model: Model) throws -> Bool {
        try body(model)
    }
}

public struct ModelConfiguration {
    public var schema: Schema?
    public var url: URL?
    public var isStoredInMemoryOnly: Bool

    public init(
        schema: Schema? = nil,
        url: URL? = nil,
        isStoredInMemoryOnly: Bool = false
    ) {
        self.schema = schema
        self.url = url
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }
}

public enum QuillDataError: Error, CustomStringConvertible {
    case openFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)
    case sqlite(String)
    case unsupportedPredicate(String)
    case contextOperationFailed([String])

    public var description: String {
        switch self {
        case .openFailed(let message): return "Failed to open QuillData store: \(message)"
        case .encodeFailed(let message): return "Failed to encode model: \(message)"
        case .decodeFailed(let message): return "Failed to decode model: \(message)"
        case .sqlite(let message): return "SQLite error: \(message)"
        case .unsupportedPredicate(let message): return message
        case .contextOperationFailed(let messages): return messages.joined(separator: "\n")
        }
    }
}

final class QuillDataSQLiteStore: @unchecked Sendable {
    private let database: any DatabaseWriter

    init(configuration: ModelConfiguration) throws {
        if configuration.isStoredInMemoryOnly {
            self.database = try DatabaseQueue()
        } else {
            let url = try configuration.url ?? Self.defaultURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            self.database = try DatabaseQueue(path: url.path)
        }
    }

    func migrate(_ schema: Schema) throws {
        try database.write { db in
            for modelType in schema.models {
                if let mappable = modelType as? any QuillTableMappable.Type {
                    try db.execute(sql: mappable.createTableSQL)
                }
            }
        }
    }

    func upsert<Model: PersistentModel>(_ model: Model) throws {
        if let mappable = model as? any QuillTableMappable {
            try database.write { db in
                try upsertColumnar(mappable, in: db)
            }
        }
    }

    private func upsertColumnar(_ mappable: any QuillTableMappable, in db: Database) throws {
        try upsertHelper(mappable.toTableStruct(), in: db)
    }

    private func upsertHelper<T: PersistableRecord>(_ tableStruct: T, in db: Database) throws {
        try tableStruct.insert(db)
    }

    func fetchAll<Model: PersistentModel>(_ model: Model.Type, filter: String? = nil) throws -> [Model] {
        guard let mappable = model as? any QuillTableMappable.Type else { return [] }
        return try database.read { db in
            let sql = filter != nil ? "SELECT * FROM \(mappable.tableName) WHERE \(filter!)" : "SELECT * FROM \(mappable.tableName)"
            let records = try mappable.fetchPersistentModels(db, sql: sql)
            return records.compactMap { $0 as? Model }
        }
    }

    func deleteAll<Model: PersistentModel>(_ model: Model.Type, filter: String? = nil) throws {
        guard let mappable = model as? any QuillTableMappable.Type else { return }
        try database.write { db in
            let sql = filter != nil ? "DELETE FROM \(mappable.tableName) WHERE \(filter!)" : "DELETE FROM \(mappable.tableName)"
            try db.execute(sql: sql)
        }
    }

    func delete<Model: PersistentModel>(_ model: Model) throws {
        guard let mappable = model as? any QuillTableMappable else { return }
        try database.write { db in
            _ = try mappable.toTableStruct().delete(db)
        }
    }

    private static func defaultURL() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        let home = environment["QUILLDATA_HOME"] ?? environment["HOME"]
        let baseURL = home.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = baseURL.appendingPathComponent(".quilldata/default.sqlite")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }
}

public final class ModelContext: @unchecked Sendable {
    private let container: ModelContainer
    private let lock = NSRecursiveLock()
    private var recordedErrors: [Error] = []
    private var changed = false

    public var autosaveEnabled = true
    public var hasChanges: Bool { lock.withLock { changed || !recordedErrors.isEmpty } }

    public init(_ container: ModelContainer) { self.container = container }

    public func insert<Model: PersistentModel>(_ model: Model) {
        lock.withLock {
            do { try container.store.upsert(model); markChanged() }
            catch { recordedErrors.append(error) }
        }
    }

    public func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        try lock.withLock {
            let filter = descriptor.predicate?.sqlFilter
            var result = try container.store.fetchAll(Model.self, filter: filter)
            if let closureFilter = descriptor.filter {
                result = try result.filter { try closureFilter($0) }
            }
            var sortedResult = result
            if !descriptor.sortBy.isEmpty {
                sortedResult.sort { lhs, rhs in
                    Self.compare(lhs, rhs, using: descriptor.sortBy)
                }
            }
            if let fetchLimit = descriptor.fetchLimit {
                sortedResult = fetchLimit <= 0 ? [] : Array(sortedResult.prefix(fetchLimit))
            }
            return sortedResult
        }
    }

    public func delete<Model: PersistentModel>(_ model: Model) {
        lock.withLock {
            do { try container.store.delete(model); markChanged() }
            catch { recordedErrors.append(error) }
        }
    }

    public func delete<Model: PersistentModel>(model: Model.Type, where predicate: Predicate<Model>? = nil) throws {
        try lock.withLock {
            if let sqlFilter = predicate?.sqlFilter {
                try container.store.deleteAll(Model.self, filter: sqlFilter)
            } else if let predicate {
                let matchingModels = try container.store.fetchAll(Model.self).filter { try predicate.evaluate($0) }
                for model in matchingModels {
                    try container.store.delete(model)
                }
            } else {
                try container.store.deleteAll(Model.self)
            }
            markChanged()
        }
    }

    public func save() throws {
        try lock.withLock {
            let errors = recordedErrors
            recordedErrors.removeAll()
            if !errors.isEmpty { throw QuillDataError.contextOperationFailed(errors.map { $0.localizedDescription }) }
            changed = false
        }
    }

    private func markChanged() { changed = true }

    private static func compare<Model>(
        _ lhs: Model,
        _ rhs: Model,
        using descriptors: [SortDescriptor<Model>]
    ) -> Bool {
        for descriptor in descriptors {
            let comparison = compareValues(
                lhs[keyPath: descriptor.keyPath],
                rhs[keyPath: descriptor.keyPath]
            )
            guard comparison != .orderedSame else { continue }
            switch descriptor.order {
            case .forward:
                return comparison == .orderedAscending
            case .reverse:
                return comparison == .orderedDescending
            }
        }
        return false
    }

    private static func compareValues(_ lhs: Any, _ rhs: Any) -> ComparisonResult {
        let left = unwrapOptional(lhs)
        let right = unwrapOptional(rhs)

        switch (left, right) {
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        case let (left?, right?):
            if let comparison = compareKnownValues(left, right) {
                return comparison
            }
            let leftDescription = String(describing: left)
            let rightDescription = String(describing: right)
            if leftDescription == rightDescription { return .orderedSame }
            return leftDescription < rightDescription ? .orderedAscending : .orderedDescending
        }
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private static func compareKnownValues(_ lhs: Any, _ rhs: Any) -> ComparisonResult? {
        switch (lhs, rhs) {
        case let (lhs as String, rhs as String):
            return compareComparable(lhs, rhs)
        case let (lhs as Date, rhs as Date):
            return compareComparable(lhs, rhs)
        case let (lhs as UUID, rhs as UUID):
            return compareComparable(lhs.uuidString, rhs.uuidString)
        case let (lhs as Bool, rhs as Bool):
            return compareComparable(lhs ? 1 : 0, rhs ? 1 : 0)
        case let (lhs as Int, rhs as Int):
            return compareComparable(lhs, rhs)
        case let (lhs as Double, rhs as Double):
            return compareComparable(lhs, rhs)
        default:
            return nil
        }
    }

    private static func compareComparable<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }
}

public struct SortDescriptor<Model: PersistentModel> {
    public let keyPath: PartialKeyPath<Model>
    public let order: SortOrder
    public init<Value>(_ keyPath: KeyPath<Model, Value>, order: SortOrder = .forward) {
        self.keyPath = keyPath
        self.order = order
    }
}

public enum SortOrder { case forward, reverse }
