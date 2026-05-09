import Foundation
import Dispatch
import QuillData
import Testing

@Suite("QuillData SwiftData-shaped compatibility")
struct QuillDataTests {
    @Test("inserts fetches sorts filters updates and deletes persistent models")
    func modelContextLifecycle() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([TodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        let low = TodoItem(title: "Low", priority: 1)
        let high = TodoItem(title: "High", priority: 5)

        context.insert(low)
        context.insert(high)
        #expect(context.hasChanges)
        try context.save()
        #expect(context.hasChanges == false)

        let highPriority = try context.fetch(FetchDescriptor<TodoItem>(
            filter: { $0.priority >= 2 },
            sortBy: [SortDescriptor(\TodoItem.priority, order: .reverse)]
        ))

        #expect(highPriority.map { $0.title } == ["High"])

        high.title = "Very high"
        try context.save()

        let sorted = try context.fetch(FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\TodoItem.priority, order: .reverse)]
        ))

        #expect(sorted.map { $0.title } == ["Very high", "Low"])

        context.delete(high)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TodoItem>()).map { $0.title } == ["Low"])

        try context.delete(model: TodoItem.self)
        #expect(try context.fetch(FetchDescriptor<TodoItem>()).isEmpty)
    }

    @Test("evaluates Foundation predicates for value models")
    func valuePredicateLifecycle() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        context.insert(ValueTodoItem(title: "Skip", priority: 1))
        context.insert(ValueTodoItem(title: "Keep", priority: 3))

        let items = try context.fetch(FetchDescriptor<ValueTodoItem>(
            predicate: #QuillPredicate { $0.priority > 1 }
        ))

        #expect(items.map { $0.title } == ["Keep"])
    }

    @Test("applies chained sort descriptors before fetch limits")
    func chainedSortsAndFetchLimits() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        context.insert(ValueTodoItem(id: UUID(), title: "Beta", priority: 3))
        context.insert(ValueTodoItem(id: UUID(), title: "Alpha", priority: 3))
        context.insert(ValueTodoItem(id: UUID(), title: "Gamma", priority: 1))
        context.insert(ValueTodoItem(id: UUID(), title: "Delta", priority: 2))

        let firstThree = try context.fetch(FetchDescriptor<ValueTodoItem>(
            sortBy: [
                SortDescriptor(\.priority, order: .reverse),
                SortDescriptor(\.title, order: .forward)
            ],
            fetchLimit: 3
        ))

        #expect(firstThree.map { $0.title } == ["Alpha", "Beta", "Delta"])

        let noItems = try context.fetch(FetchDescriptor<ValueTodoItem>(
            sortBy: [SortDescriptor(\.title)],
            fetchLimit: -10
        ))
        #expect(noItems.isEmpty)
    }

    @Test("delete where removes only predicate matches")
    func deleteWherePredicateKeepsNonMatches() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        context.insert(ValueTodoItem(title: "Keep low", priority: 1))
        context.insert(ValueTodoItem(title: "Delete high", priority: 5))
        context.insert(ValueTodoItem(title: "Delete higher", priority: 7))

        try context.delete(model: ValueTodoItem.self, where: #QuillPredicate { $0.priority >= 5 })

        let remaining = try context.fetch(FetchDescriptor<ValueTodoItem>(
            sortBy: [SortDescriptor(\.title)]
        ))
        #expect(remaining.map { $0.title } == ["Keep low"])
    }

    @Test("delete all untracks class-backed models before later saves")
    func deleteAllUntracksClassBackedModels() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([TodoItem.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))
        let item = TodoItem(title: "Tracked", priority: 1)
        context.insert(item)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(fetched.count == 1)

        try context.delete(model: TodoItem.self)
        item.title = "Resurrected"
        fetched[0].title = "Also resurrected"
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TodoItem>()).isEmpty)
    }

    @Test("upsert replaces existing rows with the same model id")
    func upsertReplacesSameID() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)
        let id = UUID()

        context.insert(ValueTodoItem(id: id, title: "Draft", priority: 1))
        context.insert(ValueTodoItem(id: id, title: "Final", priority: 9))

        let models = try context.fetch(FetchDescriptor<ValueTodoItem>())
        #expect(models.map { $0.title } == ["Final"])
        #expect(models.map(\.priority) == [9])
    }

    @Test("file-backed containers persist across new contexts")
    func fileBackedContainersPersistAcrossContexts() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            let context = ModelContext(container)
            context.insert(ValueTodoItem(title: "Persisted", priority: 4))
        }

        let reloadedContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let reloadedContext = ModelContext(reloadedContainer)

        #expect(try reloadedContext.fetch(FetchDescriptor<ValueTodoItem>()).map { $0.title } == ["Persisted"])
    }

    @Test("in-memory containers do not share rows")
    func inMemoryContainersAreIsolated() throws {
        let schema = Schema([ValueTodoItem.self])
        let first = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))
        let second = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ))

        first.insert(ValueTodoItem(title: "Only first", priority: 1))

        #expect(try first.fetch(FetchDescriptor<ValueTodoItem>()).count == 1)
        #expect(try second.fetch(FetchDescriptor<ValueTodoItem>()).isEmpty)
    }

    @Test("class-backed models support closure filters for compatibility queries")
    func classBackedModelsSupportClosureFilters() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([TodoItem.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))
        context.insert(TodoItem(title: "Low", priority: 1))
        context.insert(TodoItem(title: "High", priority: 3))

        let matches = try context.fetch(FetchDescriptor<TodoItem>(
            filter: { $0.priority > 1 },
            sortBy: [SortDescriptor(\.title)]
        ))

        #expect(matches.map { $0.title } == ["High"])
    }

    @Test("QuillPredicate supports class-backed relationship lookups")
    func classBackedQuillPredicateRelationshipLookup() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([PredicateConversation.self, PredicateMessage.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))
        let selectedID = UUID()
        let selected = PredicateConversation(id: selectedID, createdAt: Date(timeIntervalSince1970: 10))
        let other = PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 20))

        context.insert(selected)
        context.insert(other)
        context.insert(PredicateMessage(content: "Second", createdAt: Date(timeIntervalSince1970: 40), conversation: selected))
        context.insert(PredicateMessage(content: "Other", createdAt: Date(timeIntervalSince1970: 30), conversation: other))
        context.insert(PredicateMessage(content: "First", createdAt: Date(timeIntervalSince1970: 20), conversation: selected))

        let predicate = #QuillPredicate<PredicateMessage> { $0.conversation?.id == selectedID }
        let messages = try context.fetch(FetchDescriptor<PredicateMessage>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt)]
        ))

        #expect(messages.map { $0.content } == ["First", "Second"])
    }

    @Test("inserting a class-backed relationship persists the related root model")
    func classBackedRelationshipInsertCascadesRootModel() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([PredicateConversation.self, PredicateMessage.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))
        let conversation = PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 70))
        let message = PredicateMessage(
            content: "How to center div in HTML?",
            createdAt: Date(timeIntervalSince1970: 80),
            conversation: conversation
        )
        let conversationID = conversation.id

        context.insert(message)
        try context.save()

        let conversations = try context.fetch(FetchDescriptor<PredicateConversation>())
        #expect(conversations.map(\.id) == [conversation.id])

        let messages = try context.fetch(FetchDescriptor<PredicateMessage>(
            predicate: #QuillPredicate { $0.conversation?.id == conversationID }
        ))
        #expect(messages.map(\.content) == ["How to center div in HTML?"])
    }

    @Test("QuillPredicate delete supports class-backed date ranges")
    func classBackedQuillPredicateDeleteRange() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([PredicateConversation.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))

        context.insert(PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 10)))
        context.insert(PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 20)))
        context.insert(PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 30)))

        let dayStart = Date(timeIntervalSince1970: 15)
        let dayEnd = Date(timeIntervalSince1970: 25)
        try context.delete(
            model: PredicateConversation.self,
            where: #QuillPredicate<PredicateConversation> { $0.createdAt >= dayStart && $0.createdAt <= dayEnd }
        )

        let remaining = try context.fetch(FetchDescriptor<PredicateConversation>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        #expect(remaining.map(\.createdAt.timeIntervalSince1970) == [10, 30])
    }

    @Test("fetching class-backed models marks context changed for app saveChanges extensions")
    func classBackedFetchMarksPotentialChanges() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([TodoItem.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))
        context.insert(TodoItem(title: "Original", priority: 1))
        try context.save()
        #expect(context.hasChanges == false)

        let fetched = try context.fetch(FetchDescriptor<TodoItem>())
        #expect(context.hasChanges)
        fetched[0].title = "Edited"
        try context.save()

        #expect(try context.fetch(FetchDescriptor<TodoItem>()).map { $0.title } == ["Edited"])
    }

    @Test("supports SwiftData-style attribute wrappers on codable classes")
    func attributeWrapperPersistsValues() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([WrappedModel.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let context = ModelContext(container)

        context.insert(WrappedModel(slug: "ollama", enabled: true))
        try context.save()

        let models = try context.fetch(FetchDescriptor<WrappedModel>())
        #expect(models.map(\.slug) == ["ollama"])
        #expect(models[0].enabled)
    }

    @Test("optional SwiftData-style attributes and relationships default to nil")
    func optionalAttributeAndRelationshipDefaults() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([OptionalWrapperModel.self, PredicateConversation.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))

        let empty = OptionalWrapperModel(name: "empty")
        #expect(empty.image == nil)
        #expect(empty.conversation == nil)

        let conversation = PredicateConversation(id: UUID(), createdAt: Date(timeIntervalSince1970: 40))
        let filled = OptionalWrapperModel(name: "filled")
        filled.image = Data([1, 2, 3])
        filled.conversation = conversation
        context.insert(empty)
        context.insert(filled)
        try context.save()

        let models = try context.fetch(FetchDescriptor<OptionalWrapperModel>(
            sortBy: [SortDescriptor(\.name)]
        ))
        #expect(models.map(\.name) == ["empty", "filled"])
        #expect(models[0].image == nil)
        #expect(models[0].conversation == nil)
        #expect(models[1].image == Data([1, 2, 3]))
        #expect(models[1].conversation?.id == conversation.id)
    }

    @Test("models without explicit id fall back to stable name identity")
    func nameBackedIdentityUpserts() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([NamedModel.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))

        context.insert(NamedModel(name: "llama3.2:latest", enabled: false))
        context.insert(NamedModel(name: "llama3.2:latest", enabled: true))

        let models = try context.fetch(FetchDescriptor<NamedModel>())
        #expect(models.count == 1)
        #expect(models.first?.enabled == true)
    }

    @Test("relationship wrappers encode and decode nested values")
    func relationshipWrapperPersistsNestedValues() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([FolderModel.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))

        context.insert(FolderModel(name: "Inbox", items: [
            ValueTodoItem(title: "One", priority: 1),
            ValueTodoItem(title: "Two", priority: 2)
        ]))

        let folders = try context.fetch(FetchDescriptor<FolderModel>())
        #expect(folders.map(\.name) == ["Inbox"])
        #expect(folders[0].items.map { $0.title } == ["One", "Two"])
    }

    @Test("nonthrowing inserts surface persistence errors on save")
    func insertRecordsErrorsUntilSave() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([FailingModel.self])
        let context = try ModelContext(ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        ))

        context.insert(FailingModel())

        do {
            try context.save()
            Issue.record("save() should surface the encode failure captured by insert(_:)")
        } catch QuillDataError.contextOperationFailed(let messages) {
            #expect(messages.isEmpty == false)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        try context.save()
        #expect(try context.fetch(FetchDescriptor<FailingModel>()).isEmpty)
    }

    @Test("shared SQLite stores serialize concurrent context writes")
    func sharedStoresSerializeConcurrentContextWrites() throws {
        let url = temporarySQLiteURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([ValueTodoItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: url)]
        )
        let queue = DispatchQueue(label: "quilldata.concurrent-writes", attributes: .concurrent)
        let group = DispatchGroup()
        let count = 40

        for index in 0..<count {
            group.enter()
            queue.async {
                defer { group.leave() }
                let context = ModelContext(container)
                context.insert(ValueTodoItem(title: "Item \(index)", priority: index))
                try? context.save()
            }
        }

        #expect(group.wait(timeout: .now() + .seconds(5)) == .success)

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<ValueTodoItem>())
        #expect(items.count == count)
    }

    private func temporarySQLiteURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }
}

private final class TodoItem: PersistentModel, Equatable {
    var id: UUID
    var title: String
    var priority: Int

    init(id: UUID = UUID(), title: String, priority: Int) {
        self.id = id
        self.title = title
        self.priority = priority
    }

    static func == (lhs: TodoItem, rhs: TodoItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.priority == rhs.priority
    }
}

private struct ValueTodoItem: PersistentModel, Equatable {
    var id: UUID = UUID()
    var title: String
    var priority: Int
}

private final class WrappedModel: PersistentModel {
    @Attribute(.unique) var slug: String
    @Attribute var enabled: Bool

    var id: String { slug }

    init(slug: String, enabled: Bool) {
        self.slug = slug
        self.enabled = enabled
    }
}

private final class FolderModel: PersistentModel {
    var id = UUID()
    var name: String
    @Relationship var items: [ValueTodoItem]

    init(name: String, items: [ValueTodoItem]) {
        self.name = name
        self.items = items
    }
}

private final class NamedModel: PersistentModel {
    var name: String
    var enabled: Bool

    init(name: String, enabled: Bool) {
        self.name = name
        self.enabled = enabled
    }
}

private final class PredicateConversation: PersistentModel, Identifiable {
    var id: UUID
    var createdAt: Date

    init(id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

private final class PredicateMessage: PersistentModel, Identifiable {
    var id = UUID()
    var content: String
    var createdAt: Date
    @Relationship var conversation: PredicateConversation?

    init(content: String, createdAt: Date, conversation: PredicateConversation? = nil) {
        self.content = content
        self.createdAt = createdAt
        self.conversation = conversation
    }
}

private final class OptionalWrapperModel: PersistentModel {
    var name: String
    @Attribute(.externalStorage) var image: Data?
    @Relationship(deleteRule: .nullify) var conversation: PredicateConversation?

    init(name: String) {
        self.name = name
    }
}

private struct FailingModel: PersistentModel {
    var id = UUID()

    init() {}

    init(from decoder: Decoder) throws {
        self.id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        throw FailingModelError.encode
    }
}

private enum FailingModelError: Error {
    case encode
}
