import Foundation
// Don't `@_exported import GRDB` — GRDB.DatabaseQueue / DatabaseError
// would then leak into every module that auto-imports QuillShims,
// conflicting with NetNewsWire upstream's RSDatabase.DatabaseQueue /
// DatabaseError. QuillData consumers that need GRDB should `import GRDB`
// explicitly.
import GRDB

public protocol PersistentModel: Codable {}

extension PersistentModel {
    public var databaseValue: DatabaseValue {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return .null }
        return data.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> Self? {
        guard let data = Data.fromDatabaseValue(dbValue) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(Self.self, from: data)
    }
}

extension PersistentModel {
    public static func decode(from data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }
}

extension Array: @retroactive DatabaseValueConvertible where Element: Codable {
    public var databaseValue: DatabaseValue {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else { return .null }
        return data.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> [Element]? {
        guard let data = Data.fromDatabaseValue(dbValue) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode([Element].self, from: data)
    }
}

extension Array: @retroactive SQLExpressible where Element: Codable {}
extension Array: @retroactive StatementBinding where Element: Codable {}

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
    private static let genericTablePrefix = "_quilldata_json_"

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
                } else {
                    try Self.createGenericTable(for: modelType, in: db)
                    try Self.migrateUnstablePrivateContextGenericTables(for: modelType, in: db)
                }
            }
        }
    }

    func upsert<Model: PersistentModel>(_ model: Model) throws {
        try upsertAny(model)
    }

    func upsertAny(_ model: any PersistentModel) throws {
        try database.write { db in
            var visited: Set<String> = []
            try upsert(model, in: db, visited: &visited)
        }
    }

    private func upsert(
        _ model: any PersistentModel,
        in db: Database,
        visited: inout Set<String>
    ) throws {
        let payload = try Self.encode(model)
        let tableName = Self.storageTableName(for: model)
        let identity = Self.identity(for: model, encodedPayload: payload)
        let visitedKey = "\(tableName):\(identity)"
        guard visited.insert(visitedKey).inserted else { return }

        for relatedModel in Self.classBackedRelatedModels(in: model) {
            try upsert(relatedModel, in: db, visited: &visited)
        }

        if let mappable = model as? any QuillTableMappable {
            try upsertColumnar(mappable, in: db)
        } else {
            try upsertGeneric(model, payload: payload, identity: identity, in: db)
        }
    }

    private func upsertColumnar(_ mappable: any QuillTableMappable, in db: Database) throws {
        try upsertHelper(mappable.toTableStruct(), in: db)
    }

    private func upsertHelper<T: PersistableRecord>(_ tableStruct: T, in db: Database) throws {
        try tableStruct.insert(db)
    }

    func fetchAll<Model: PersistentModel>(_ model: Model.Type, filter: String? = nil) throws -> [Model] {
        guard let mappable = model as? any QuillTableMappable.Type else {
            return try fetchGeneric(model)
        }
        return try database.read { db in
            let sql = filter != nil ? "SELECT * FROM \(mappable.tableName) WHERE \(filter!)" : "SELECT * FROM \(mappable.tableName)"
            let records = try mappable.fetchPersistentModels(db, sql: sql)
            return records.compactMap { $0 as? Model }
        }
    }

    func deleteAll<Model: PersistentModel>(_ model: Model.Type, filter: String? = nil) throws {
        guard let mappable = model as? any QuillTableMappable.Type else {
            guard filter == nil else {
                throw QuillDataError.unsupportedPredicate("SQL predicates are not supported for JSON-backed \(model)")
            }
            try database.write { db in
                try db.execute(sql: "DELETE FROM \(Self.quotedIdentifier(Self.genericTableName(for: model)))")
            }
            return
        }
        try database.write { db in
            let sql = filter != nil ? "DELETE FROM \(mappable.tableName) WHERE \(filter!)" : "DELETE FROM \(mappable.tableName)"
            try db.execute(sql: sql)
        }
    }

    func delete<Model: PersistentModel>(_ model: Model) throws {
        guard let mappable = model as? any QuillTableMappable else {
            let payload = try Self.encode(model)
            let identity = Self.identity(for: model, encodedPayload: payload)
            try database.write { db in
                try db.execute(
                    sql: "DELETE FROM \(Self.quotedIdentifier(Self.genericTableName(for: type(of: model)))) WHERE id = ?",
                    arguments: [identity]
                )
            }
            return
        }
        try database.write { db in
            _ = try mappable.toTableStruct().delete(db)
        }
    }

    func supportsSQLFilters<Model: PersistentModel>(_ model: Model.Type) -> Bool {
        model is any QuillTableMappable.Type
    }

    func identity<Model: PersistentModel>(for model: Model) throws -> String {
        try Self.identity(for: model, encodedPayload: Self.encode(model))
    }

    func encodedPayload(for model: any PersistentModel) throws -> Data {
        try Self.encode(model)
    }

    private func fetchGeneric<Model: PersistentModel>(_ model: Model.Type) throws -> [Model] {
        try database.read { db in
            let tableName = Self.quotedIdentifier(Self.genericTableName(for: model))
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM \(tableName) ORDER BY rowid")
            return try rows.map { row in
                let payload: Data = row["payload"]
                do {
                    return try JSONDecoder().decode(Model.self, from: payload)
                } catch {
                    throw QuillDataError.decodeFailed("\(model): \(error)")
                }
            }
        }
    }

    private func upsertGeneric(
        _ model: any PersistentModel,
        payload: Data,
        identity: String,
        in db: Database
    ) throws {
        let tableName = Self.quotedIdentifier(Self.genericTableName(for: type(of: model)))
        try Self.createGenericTable(for: type(of: model), in: db)
        try db.execute(
            sql: "INSERT OR REPLACE INTO \(tableName) (id, payload) VALUES (?, ?)",
            arguments: [identity, payload]
        )
    }

    private static func createGenericTable(
        for modelType: any PersistentModel.Type,
        in db: Database
    ) throws {
        let tableName = quotedIdentifier(genericTableName(for: modelType))
        try db.execute(sql: """
        CREATE TABLE IF NOT EXISTS \(tableName) (
            id TEXT PRIMARY KEY ON CONFLICT REPLACE,
            payload BLOB NOT NULL
        )
        """)
    }

    private static func storageTableName(for model: any PersistentModel) -> String {
        if let mappable = type(of: model) as? any QuillTableMappable.Type {
            return mappable.tableName
        }
        return genericTableName(for: type(of: model))
    }

    static func genericTableName(for modelType: any PersistentModel.Type) -> String {
        let rawName = stableGenericModelName(for: modelType)
        let sanitizedName = rawName.map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        return genericTablePrefix + String(sanitizedName)
    }

    static func normalizedGenericTableName(_ tableName: String) -> String {
        tableName.replacingOccurrences(
            of: #"__unknown_context_at__[A-Za-z0-9]+__"#,
            with: "_",
            options: .regularExpression
        )
    }

    private static func stableGenericModelName(for modelType: any PersistentModel.Type) -> String {
        String(reflecting: modelType).replacingOccurrences(
            of: #"\.\(unknown context at [^)]+\)"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func migrateUnstablePrivateContextGenericTables(
        for modelType: any PersistentModel.Type,
        in db: Database
    ) throws {
        let targetTableName = genericTableName(for: modelType)
        let legacyTableNames = try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE ?",
            arguments: ["\(genericTablePrefix)%unknown_context_at%"]
        )

        for legacyTableName in legacyTableNames
        where legacyTableName != targetTableName && normalizedGenericTableName(legacyTableName) == targetTableName {
            try db.execute(sql: """
            INSERT OR IGNORE INTO \(quotedIdentifier(targetTableName)) (id, payload)
            SELECT id, payload FROM \(quotedIdentifier(legacyTableName))
            """)
        }
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func encode(_ model: any PersistentModel) throws -> Data {
        do {
            return try JSONEncoder().encode(model)
        } catch {
            throw QuillDataError.encodeFailed("\(type(of: model)): \(error)")
        }
    }

    private static func identity(
        for model: any PersistentModel,
        encodedPayload payload: Data
    ) -> String {
        if let identity = mirroredIdentity(in: model, preferredNames: ["id", "slug", "name"]) {
            return identity
        }
        return "payload:\(payload.base64EncodedString())"
    }

    private static func mirroredIdentity(
        in value: Any,
        preferredNames: [String]
    ) -> String? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let currentMirror = mirror {
            for child in currentMirror.children {
                guard
                    let label = child.label,
                    preferredNames.contains(label),
                    let identity = identityString(unwrapOptional(child.value))
                else { continue }
                return "\(label):\(identity)"
            }
            mirror = currentMirror.superclassMirror
        }
        return nil
    }

    private static func identityString(_ value: Any?) -> String? {
        guard let value else { return nil }
        switch value {
        case let value as UUID:
            return value.uuidString
        case let value as String:
            return value
        case let value as Date:
            return String(value.timeIntervalSince1970)
        case let value as Bool:
            return value ? "true" : "false"
        case let value as Int:
            return String(value)
        case let value as Int64:
            return String(value)
        case let value as Double:
            return String(value)
        case let value as Float:
            return String(value)
        case let value as Data:
            return value.base64EncodedString()
        default:
            return String(describing: value)
        }
    }

    private static func classBackedRelatedModels(in model: any PersistentModel) -> [any PersistentModel] {
        var relatedModels: [any PersistentModel] = []
        var mirror: Mirror? = Mirror(reflecting: model)
        while let currentMirror = mirror {
            for child in currentMirror.children {
                relatedModels.append(contentsOf: classBackedPersistentModels(in: child.value))
            }
            mirror = currentMirror.superclassMirror
        }
        return relatedModels
    }

    private static func classBackedPersistentModels(in value: Any) -> [any PersistentModel] {
        guard let value = unwrapOptional(value) else { return [] }
        if let model = value as? any PersistentModel,
           Mirror(reflecting: model).displayStyle == .class {
            return [model]
        }

        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .collection, .set:
            return mirror.children.flatMap { classBackedPersistentModels(in: $0.value) }
        default:
            return []
        }
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
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
    private struct TrackedModelKey: Hashable {
        let typeID: ObjectIdentifier
        let identity: String
    }

    private struct TrackedModel {
        let objectID: ObjectIdentifier
        let typeID: ObjectIdentifier
        let identity: String
        let model: any PersistentModel
        let trackedPayload: Data
        let order: Int

        var key: TrackedModelKey {
            TrackedModelKey(typeID: typeID, identity: identity)
        }
    }

    private struct TrackedSaveCandidate {
        let model: TrackedModel
        let isChanged: Bool
    }

    private struct ClassBackedTrackingInfo {
        let objectID: ObjectIdentifier
        let typeID: ObjectIdentifier
        let identity: String
        let payload: Data

        var key: TrackedModelKey {
            TrackedModelKey(typeID: typeID, identity: identity)
        }
    }

    private let container: ModelContainer
    private let lock = NSRecursiveLock()
    private var recordedErrors: [Error] = []
    private var trackedModels: [ObjectIdentifier: TrackedModel] = [:]
    private var trackedModelObjectIDsByKey: [TrackedModelKey: ObjectIdentifier] = [:]
    private var nextTrackingOrder = 0
    private var changed = false

    public var autosaveEnabled = true
    public var hasChanges: Bool { lock.withLock { changed || !recordedErrors.isEmpty } }

    public init(_ container: ModelContainer) { self.container = container }

    public func insert<Model: PersistentModel>(_ model: Model) {
        lock.withLock {
            do {
                try container.store.upsert(model)
                trackIfClassBacked(model)
                markChanged()
            }
            catch { recordedErrors.append(error) }
        }
    }

    public func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
        try lock.withLock {
            let filter = container.store.supportsSQLFilters(Model.self) ? descriptor.predicate?.sqlFilter : nil
            var result = try container.store.fetchAll(Model.self, filter: filter)
            result = result.map { canonicalClassBackedModel(for: $0) }
            if let predicate = descriptor.predicate {
                result = try result.filter { try predicate.evaluate($0) }
            }
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
            var trackedClassBackedModel = false
            for model in sortedResult {
                trackedClassBackedModel = trackIfClassBacked(model) || trackedClassBackedModel
            }
            if trackedClassBackedModel {
                markChanged()
            }
            return sortedResult
        }
    }

    public func delete<Model: PersistentModel>(_ model: Model) {
        lock.withLock {
            do {
                try container.store.delete(model)
                untrack(model)
                markChanged()
            }
            catch { recordedErrors.append(error) }
        }
    }

    public func delete<Model: PersistentModel>(model: Model.Type, where predicate: Predicate<Model>? = nil) throws {
        try lock.withLock {
            if let predicate {
                let matchingModels = try container.store.fetchAll(Model.self).filter { try predicate.evaluate($0) }
                for model in matchingModels {
                    try container.store.delete(model)
                    untrack(model)
                }
            } else {
                try container.store.deleteAll(Model.self)
                untrackAll(Model.self)
            }
            markChanged()
        }
    }

    public func save() throws {
        try lock.withLock {
            let errors = recordedErrors
            recordedErrors.removeAll()
            if !errors.isEmpty { throw QuillDataError.contextOperationFailed(errors.map { $0.localizedDescription }) }
            for trackedModel in try trackedModelsForSave() {
                try container.store.upsertAny(trackedModel.model)
            }
            changed = false
        }
    }

    private func markChanged() { changed = true }

    @discardableResult
    private func trackIfClassBacked<Model: PersistentModel>(_ model: Model) -> Bool {
        guard let trackingInfo = classBackedTrackingInfo(for: model) else { return false }
        storeTrackedModel(model, trackingInfo: trackingInfo, replacingExistingIdentity: true)
        return true
    }

    private func canonicalClassBackedModel<Model: PersistentModel>(for model: Model) -> Model {
        guard let trackingInfo = classBackedTrackingInfo(for: model) else { return model }
        if let objectID = trackedModelObjectIDsByKey[trackingInfo.key],
           let trackedModel = trackedModels[objectID],
           let canonicalModel = trackedModel.model as? Model {
            return canonicalModel
        }
        storeTrackedModel(model, trackingInfo: trackingInfo, replacingExistingIdentity: false)
        return model
    }

    private func storeTrackedModel<Model: PersistentModel>(
        _ model: Model,
        trackingInfo: ClassBackedTrackingInfo,
        replacingExistingIdentity: Bool
    ) {
        nextTrackingOrder += 1
        let trackedModel = TrackedModel(
            objectID: trackingInfo.objectID,
            typeID: trackingInfo.typeID,
            identity: trackingInfo.identity,
            model: model,
            trackedPayload: trackingInfo.payload,
            order: nextTrackingOrder
        )

        if replacingExistingIdentity,
           let existingObjectID = trackedModelObjectIDsByKey[trackedModel.key],
           existingObjectID != trackedModel.objectID {
            removeTrackedObject(existingObjectID)
        }

        trackedModels[trackedModel.objectID] = trackedModel
        trackedModelObjectIDsByKey[trackedModel.key] = trackedModel.objectID
    }

    private func classBackedTrackingInfo<Model: PersistentModel>(for model: Model) -> ClassBackedTrackingInfo? {
        guard let objectID = Self.classObjectIdentifier(for: model) else { return nil }
        let payload = (try? container.store.encodedPayload(for: model)) ?? Data()
        let identity = (try? container.store.identity(for: model)) ?? String(describing: objectID)
        return ClassBackedTrackingInfo(
            objectID: objectID,
            typeID: ObjectIdentifier(Model.self),
            identity: identity,
            payload: payload
        )
    }

    private func trackedModelsForSave() throws -> [TrackedModel] {
        var candidates: [TrackedModelKey: TrackedSaveCandidate] = [:]
        for trackedModel in trackedModels.values {
            let currentPayload = try container.store.encodedPayload(for: trackedModel.model)
            let candidate = TrackedSaveCandidate(
                model: trackedModel,
                isChanged: currentPayload != trackedModel.trackedPayload
            )
            guard let existing = candidates[trackedModel.key] else {
                candidates[trackedModel.key] = candidate
                continue
            }
            if Self.shouldReplaceTrackedSaveCandidate(existing, with: candidate) {
                candidates[trackedModel.key] = candidate
            }
        }
        return candidates.values.map(\.model)
    }

    private static func shouldReplaceTrackedSaveCandidate(
        _ existing: TrackedSaveCandidate,
        with candidate: TrackedSaveCandidate
    ) -> Bool {
        if existing.isChanged != candidate.isChanged {
            return candidate.isChanged
        }
        return candidate.model.order > existing.model.order
    }

    private func untrack<Model: PersistentModel>(_ model: Model) {
        if let objectID = Self.classObjectIdentifier(for: model) {
            removeTrackedObject(objectID)
        }
        guard let identity = try? container.store.identity(for: model) else { return }
        let key = TrackedModelKey(typeID: ObjectIdentifier(Model.self), identity: identity)
        if let objectID = trackedModelObjectIDsByKey[key] {
            removeTrackedObject(objectID)
        }
    }

    private func untrackAll<Model: PersistentModel>(_ model: Model.Type) {
        let typeID = ObjectIdentifier(model)
        let objectIDs = trackedModels.values.compactMap { trackedModel in
            trackedModel.typeID == typeID ? trackedModel.objectID : nil
        }
        for objectID in objectIDs {
            removeTrackedObject(objectID)
        }
    }

    private func removeTrackedObject(_ objectID: ObjectIdentifier) {
        guard let removedModel = trackedModels.removeValue(forKey: objectID) else { return }
        if trackedModelObjectIDsByKey[removedModel.key] == objectID {
            trackedModelObjectIDsByKey.removeValue(forKey: removedModel.key)
        }
    }

    private static func classObjectIdentifier<Model: PersistentModel>(for model: Model) -> ObjectIdentifier? {
        guard Mirror(reflecting: model).displayStyle == .class else { return nil }
        return ObjectIdentifier(model as AnyObject)
    }

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
