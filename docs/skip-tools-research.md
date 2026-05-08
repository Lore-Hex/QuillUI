# Skip Tools Research Notes

Skip is the closest public proof point for QuillUI's goal: preserve SwiftUI-oriented source while targeting a non-Apple native UI toolkit.

## Current Status

- Skip is now free and open source, after previously requiring paid licensing for many commercial users.
- Skip's Android UI output is native Jetpack Compose, not a web view or custom drawing engine.
- Skip supports two module modes:
  - Skip Lite: Swift source is transpiled to Kotlin.
  - Skip Fuse: Swift source is compiled natively for Android with generated JNI bridging.
- SkipUI is a SwiftUI reimplementation for Android backed by Jetpack Compose.
- SkipModel bridges observable Swift model patterns into Compose's state model.

Primary references:

- https://skip.dev/
- https://skip.dev/docs/architecture/
- https://skip.dev/docs/modes/
- https://skip.dev/docs/modules/skip-ui/
- https://skip.dev/docs/modules/skip-model/
- https://skip.dev/blog/skip-is-free/
- https://github.com/skiptools/skip
- https://github.com/skiptools/skip-ui

## Lessons For QuillUI

### Build-time tooling matters

A library shim alone will not get close enough to SwiftUI compatibility. Skip uses a SwiftPM/Xcode build plugin and a CLI pipeline to inspect targets, process resources, generate platform build files, and produce diagnostics.

QuillUI should grow a `quill` CLI or SwiftPM plugin that can:

- inspect SwiftPM targets,
- report unsupported SwiftUI/SwiftData APIs,
- generate Linux app scaffolding,
- process resources,
- run Linux GTK smoke tests,
- maintain a compatibility report for each app.

### Use native widgets, but expose escape hatches

Skip's core bet is native SwiftUI on Apple and native Compose on Android. QuillUI should keep the equivalent position: SwiftUI on Apple and GTK/libadwaita/SwiftOpenUI on Linux.

But Skip also exposes Compose escape hatches for unsupported UI. QuillUI needs the same:

- `GtkView` or `AdwaitaView` for raw Linux UI embedding.
- A clean boundary for platform-specific code.
- Documented fallback patterns when SwiftUI parity is not realistic.

### Compatibility needs explicit modes

Skip's Lite/Fuse split is useful. QuillUI should define its own modes:

- `library` mode: import `QuillUI` and compile against SwiftOpenUI/GTK with minimal tooling.
- `compat` mode: optional generated/facade modules for closer source compatibility.
- `native` mode: deeper Linux integration and generated wrappers/macros for app stores, packaging, resources, and data.

### Do not hide unsupported APIs

Skip publishes supported API status and gives users ways around missing pieces. QuillUI needs an explicit support matrix for:

- SwiftUI views/modifiers,
- environment values,
- property wrappers,
- navigation,
- file import/drop,
- menus/commands,
- SwiftData/QuillData.

The matrix should be generated or at least tested against real sample apps.

### QuillData is necessary

Skip has model/observation support, but SwiftData remains a hard category because SwiftData depends on Apple macros/runtime behavior. QuillData should become a first-class sibling to QuillUI, not an Enchanted adapter.

The current QuillData JSON-row backend is the compatibility fallback. The future native backend should lower supported models/predicates into SQLiteData/GRDB-style tables.

### Partner angle

Skip is not a direct Linux desktop solution, but it is a plausible ally or reference implementation:

- They have already built SwiftUI-to-native-toolkit compatibility infrastructure.
- They helped move native Swift on Android forward.
- QuillUI could potentially align on shared SwiftUI compatibility tests, Swift package conventions, and model/observation abstractions.

The strategic difference: Skip targets Android/Compose. QuillUI targets Linux desktop/GTK/libadwaita and should optimize for desktop conventions, packaging, files, menus, windows, and local-first data.

## Immediate QuillUI Backlog Changes

- Keep Enchanted as a benchmark, but stop growing Enchanted-only shims.
- Add a QuillUI compatibility matrix.
- Add a `QuillUIBackend` boundary and document GTK escape hatches.
- Continue QuillData as reusable SwiftData-shaped infrastructure.
- Add a future `quill doctor` command that reports app-specific gaps before porting work starts.
