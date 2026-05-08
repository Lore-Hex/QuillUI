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
- `QuillPredicate`
- `PersistentModel`
- `@Attribute`
- `@Relationship`
- `ModelActor`/`ModelExecutor` placeholders

This backend is slower than a schema-native SQLiteData/GRDB implementation because it stores each model as encoded JSON and performs filtering/sorting in Swift. That is acceptable for the first compatibility layer because it lets app ports keep the `ModelContext` style while QuillData develops the faster backend.

## Current Compatibility

Works now:

- Codable `PersistentModel` classes and structs with stable `id`, `name`, or `slug` values.
- `ModelContext.insert`, `fetch`, `delete`, `delete(model:)`, `save`, and `hasChanges`.
- Foundation `SortDescriptor`.
- Foundation `#Predicate` for value models.
- Closure filters for class models through `FetchDescriptor(filter:)`.
- `QuillPredicate`, a class-safe closure predicate used by the generated Linux lowering path for SwiftData `#Predicate` call sites.
- SwiftData-style `@Attribute(.unique)` and optional `@Attribute(.externalStorage)` syntax for stored properties.
- SwiftData-style optional `@Relationship` declarations with no explicit default value.
- Class-backed identity-map tracking for fetched objects, so app-defined `saveChanges()` extensions that check `hasChanges` can persist later mutations.
- `scripts/lower-swiftdata-for-quilldata.sh`, which creates a generated source copy that lowers `@Model`, `@Transient`, and `#Predicate<T>` into QuillData-compatible Swift without editing app sources.
- `scripts/generated-enchanted-core-check.sh`, which proves that Enchanted's real model/store/service core can compile as generated Linux source after QuillData lowering plus a small generated identity/actor-hop shim.

In-repo consumer:

- Enchanted now defaults to `QuillDataConversationStore`, which implements its `ConversationPersistence` surface with `ModelContext` instead of the earlier app-specific SQLite schema.

Important gaps:

- `@Model` is a Swift macro. QuillData does not yet provide a compiler macro, so the current near-zero-change path is a generated Linux source copy rather than direct compilation of the pristine files.
- `@Observable` and some main-actor callback hops are also macro/runtime-shaped Apple conveniences. The current generated Enchanted core check removes `@Observable` and marshals OpenCombine sink callbacks to `MainActor` in generated source; a production build plugin should own those transformations.
- Foundation `#Predicate` can trap before QuillData sees it when built against plain class models outside SwiftData's macro/runtime path. The lowering script rewrites those call sites to `QuillPredicate`; direct hand ports can also use `QuillPredicate` or `FetchDescriptor(filter:)`.
- Relationships currently encode as model fields; delete rules and inverse maintenance are not schema-native yet.
- There is no `@Query` observation layer yet.
- Migrations are limited to the generic row table.

## SQLiteData Direction

The next backend should use SQLiteData/GRDB-style table generation for models that opt into a schema-native path. The intended layering is:

1. Keep the current JSON-row backend as the broad compatibility fallback.
2. Promote the current source-lowering script into a QuillData macro or SwiftPM build plugin for source-compatible model declarations.
3. Lower supported `FetchDescriptor`/predicate/sort cases into SQLite queries.
4. Keep falling back to the JSON-row backend for unsupported model shapes until the native path catches up.
