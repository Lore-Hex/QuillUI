@_exported import QuillData

#if os(Linux)
import SwiftOpenUI

private func makeDefaultModelContext() -> ModelContext {
    let schema = Schema([])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}

private struct ModelContextKey: EnvironmentKey {
    static let defaultValue = makeDefaultModelContext()
}

public extension EnvironmentValues {
    var modelContext: ModelContext {
        get { self[ModelContextKey.self] }
        set { self[ModelContextKey.self] = newValue }
    }
}

public extension ModelContainer {
    convenience init(
        for model: any PersistentModel.Type,
        configurations: ModelConfiguration...
    ) throws {
        try self.init(for: Schema([model]), configurations: configurations)
    }

    convenience init(
        for models: [any PersistentModel.Type],
        configurations: [ModelConfiguration] = []
    ) throws {
        try self.init(for: Schema(models), configurations: configurations)
    }
}

public extension View {
    func modelContainer(_ container: ModelContainer) -> Self {
        _ = container
        return self
    }

    func modelContainer(for models: [any PersistentModel.Type]) -> Self {
        _ = models
        return self
    }
}

@propertyWrapper
public struct Query<Model: PersistentModel>: AnyStateStorageProvider {
    private let descriptor: FetchDescriptor<Model>
    public let storage: StateStorage<[Model]>

    public init() {
        descriptor = FetchDescriptor<Model>()
        storage = StateStorage([])
    }

    public init<Value>(
        sort keyPath: KeyPath<Model, Value>,
        order: SortOrder = .forward
    ) {
        descriptor = FetchDescriptor<Model>(sortBy: [SortDescriptor(keyPath, order: order)])
        storage = StateStorage([])
    }

    public var wrappedValue: [Model] {
        get {
            let context = getCurrentEnvironment().modelContext
            return (try? context.fetch(descriptor)) ?? storage.value
        }
        nonmutating set { storage.setValue(newValue) }
    }

    public var projectedValue: Binding<[Model]> {
        Binding(get: { wrappedValue }, set: { storage.setValue($0) })
    }

    public var anyStorage: AnyStateStorage { storage }
}
#endif
