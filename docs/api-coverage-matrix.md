# QuillUI API Coverage Matrix

Coverage labels mean:

- `compile`: source imports and representative calls compile on Linux.
- `behavior`: the compatibility layer performs useful runtime behavior.
- `native`: the behavior is backed by Linux desktop services or GTK instead of an in-memory or diagnostic fallback.
- `tested`: regression coverage exists in `Tests/`.

| Surface | Compile | Behavior | Native | Tested | Current Evidence | Next Fix |
| --- | --- | --- | --- | --- | --- | --- |
| SwiftUI facade | yes | partial | partial | yes | `SwiftUI` re-exports QuillUI on Linux; GTK smoke launches both apps. | Keep closing missing SwiftUI modifiers against real app imports. |
| Layout/navigation | yes | partial | partial | yes | `NavigationSplitView`, stacks, scroll, forms, sheets, and environment shims compile through SwiftOpenUI. | Add visual/snapshot coverage for split/sidebar/chat layouts. |
| Menus/toolbars/commands | yes | partial-real | partial | yes | Command/menu builders extract labels/actions/shortcuts, preserve disabled state for command items, and suppress disabled menu actions. | Map app menus to native GTK/libadwaita menus. |
| Forms/input styles | yes | partial-real | partial | yes | Picker, text field styles, keyboard hints, and autocorrection shims compile; grouped form styles now render with visible grouped padding/background. | Make text input hints affect GTK controls instead of diagnostics only. |
| File/drop APIs | yes | partial-real | partial | yes | `NSItemProvider`, `UTType`, `.fileImporter`, and `.onDrop` have tested file/data behavior and concrete SwiftOpenUI wrapper return types on Linux. | Replace command-dialog fallback with native GTK picker when available. |
| Visual effects/animation | yes | partial-real | partial | yes | Gradients reduce to visible colors; materials have visible fallbacks; shape masks map to `clipShape`; `symbolEffect` and matched geometry apply value-driven animations with diagnostics; symbolic image rendering and post-style image scale compile. | Implement exact GTK-backed symbol and matched-geometry effects where possible. |
| `@AppStorage` | yes | yes | yes | yes | Values persist through `UserDefaults` on Linux and bindings write through. | Add suite-isolated stores if tests need more process isolation. |
| QuillData/SwiftData shape | partial | partial-real | yes | yes | SQLite JSON-row store supports insert/fetch/delete/sort/predicate/upsert/relationships and now surfaces nonthrowing insert failures on `save()`. | Macro/source-compatible `@Model` strategy, schema/indexing, migrations, and relationship delete rules. |
| Combine | yes | mostly | mostly | yes | Linux `Combine` facade re-exports OpenCombine plus small compatibility shims for `AnyPublisher()`, `NotificationCenter.publisher`, and `Publishers.Merge`. | Audit IceCubes/NetNewsWire Combine usage against OpenCombine operators before adding local shims. |
| Foundation | yes | yes | yes | indirect | Linux uses Swift's official Foundation implementation via normal `import Foundation`. | Prefer Foundation APIs over custom shims whenever available. |
| Apple platform services | partial | fallback | no | yes | AppKit/UIKit/AVFoundation/Speech/Security/CoreGraphics/ServiceManagement/Carbon modules compile and record diagnostics or explicit unavailable state. | Add native Linux backends for clipboard, speech, shortcuts, key events, secret storage, updater, launch-at-login, and USB/device events. |
| Third-party UI packages | partial | partial-real | partial | yes | ActivityIndicatorView, MarkdownUI, Splash, Vortex, WrappingHStack, AsyncAlgorithms, and OllamaKit module shims compile; OllamaKit performs real HTTP-backed model, reachability, and streaming-chat requests; MarkdownUI/Splash cover Enchanted's theme, code-block, relative spacing, table, and syntax-highlighter contracts. | Add richer Markdown block rendering and audit the next target app's package imports. |
| Enchanted/Quill Chat app | partial | partial | partial | yes | Quill-inspired app and upstream-shaped slice run under GTK; real Quill Chat source is still untouched. | Replace the 797-line prototype slice with real source plus a tiny Linux entry point. |
| QA scripts | yes | yes | n/a | shell | Linux GTK smoke checks tests, builds, and Xvfb app survival using SwiftPM's active bin path; visual smoke checks screenshot nonblank; coverage summary reports QuillUI/QuillKit file-level coverage. | Add perceptual screenshot comparisons and CI-friendly no-sudo setup mode. |
