# QuillData

QuillData is the Linux persistence compatibility layer for SwiftUI apps that use SwiftData.

The target shape is source-oriented compatibility:

```swift
#if os(Linux)
import QuillData
#else
import SwiftData
#endif
```

The first implementation is intentionally conservative. It provides a SwiftData-shaped API over a generic SQLite JSON-row store:

- `Schema`
- `ModelConfiguration`
- `ModelContainer`
- `ModelContext`
- `FetchDescriptor`
- `PersistentModel`
- `@Attribute`
- `@Relationship`
- `ModelActor`/`ModelExecutor` placeholders

This backend is slower than a schema-native SQLiteData/GRDB implementation because it stores each model as encoded JSON and performs filtering/sorting in Swift. That is acceptable for the first compatibility layer because it lets app ports keep the `ModelContext` style while QuillData develops the faster backend.

## Current Compatibility

Works now:

- Codable `PersistentModel` classes and structs with stable `id` values.
- `ModelContext.insert`, `fetch`, `delete`, `delete(model:)`, `save`, and `saveChanges`.
- Foundation `SortDescriptor`.
- Foundation `#Predicate` for value models.
- Closure filters for class models through `FetchDescriptor(filter:)`.
- SwiftData-style `@Attribute(.unique)` syntax for stored properties.

In-repo consumer:

- Enchanted now defaults to `QuillDataConversationStore`, which implements its `ConversationPersistence` surface with `ModelContext` instead of the earlier app-specific SQLite schema.

Important gaps:

- `@Model` is a Swift macro. QuillData does not yet provide a replacement macro, so current ports still need a small model declaration change.
- Foundation `#Predicate` can trap when evaluated against plain class models outside SwiftData's macro/runtime path. QuillData therefore rejects class-backed `Predicate` evaluation and provides `FetchDescriptor(filter:)` for the slow compatibility backend.
- Relationships currently encode as model fields; delete rules and inverse maintenance are not schema-native yet.
- There is no `@Query` observation layer yet.
- Migrations are limited to the generic row table.

## SQLiteData Direction

The next backend should use SQLiteData/GRDB-style table generation for models that opt into a schema-native path. The intended layering is:

1. Keep the current JSON-row backend as the broad compatibility fallback.
2. Add a QuillData macro or codegen path for source-compatible model declarations.
3. Lower supported `FetchDescriptor`/predicate/sort cases into SQLite queries.
4. Keep falling back to the JSON-row backend for unsupported model shapes until the native path catches up.
