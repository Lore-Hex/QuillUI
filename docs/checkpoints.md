# QuillUI Checkpoints

Target app order is tracked in `docs/app-targets.md`: Enchanted first, IceCubes second, NetNewsWire third, then CodeEdit, Signal iOS, Telegram Swift, and IINA. WireGuard Apple is tracked as an opportunistic side target.

## Checkpoint 1: Local App Shell

Status: passing on macOS.

- `QuillUI` facade re-exports SwiftUI on Apple platforms and SwiftOpenUI on Linux.
- Linux `@AppStorage` shim supports primitive values and raw-representable enums.
- Linux shims now include `openURL`, `presentationMode`, `Button(role:)`, `TextField(axis:)`, `TextField(onCommit:)`, `Image(data:)`, `Image("resource")`, and `Binding.animation(...)`.
- `quill-enchanted` builds as a SwiftPM executable.
- The app has a split-view desktop chat layout, model picker, endpoint field, local conversation list, and composer.
- Ollama integration supports model discovery and streamed `/api/chat` responses with live assistant draft updates.
- Conversation history now defaults to QuillData at `~/.quillui/enchanted/enchanted-quilldata.sqlite`.
- Enchanted talks to a SwiftData-shaped persistence context with `fetch`, `insert`, `update`, `delete`, and `save` operations.
- Assistant and system chat bubbles render a portable Markdown subset: headings, paragraphs, lists, quotes, fenced code blocks, and readable links.
- The composer accepts Linux-safe image attachment stubs through typed file paths and dropped file URLs, shows removable attachment chips, and forwards base64 images to Ollama vision-capable models.
- Linux visual QA now has a repeatable screenshot script that launches the GTK app under Xvfb and verifies the captured window is nonblank.
- The upstream Enchanted audit runs against `gluonfield/enchanted` and records which APIs can stay near-source-compatible versus which need Linux adapters.
- Tests cover SQLite conversation/message persistence, the persistence context facade, Ollama stream parsing, Markdown parsing, image attachment validation, and Linux-only upstream compatibility shims.

## Checkpoint 2: Linux GTK Verification

Status: passing in Lima Ubuntu 24.04.

- Lima Ubuntu 24.04 VM config lives in `scripts/lima-ubuntu-swift.yaml`.
- Linux build script lives in `scripts/linux-gtk-check.sh`.
- Verified in a Lima Ubuntu 24.04 aarch64 VM with Swift 6.3.1: `swift test`, GTK build, and a 6-second Xvfb app-start smoke pass.

## Checkpoint 3: Enchanted Parity

Status: first upstream-shaped slice passing on macOS and Linux GTK.

- `quill-enchanted-upstream-slice` builds a selected desktop chat surface in the shape of upstream Enchanted: sidebar, header, model switcher, empty prompts, message list, composer, attachment preview, drop/file-import hooks, and context menus.
- QuillUI upstream compatibility shims now cover the first batch of SwiftUI/UniformTypeIdentifiers/AppKit-adjacent API used by that slice, including `NSItemProvider.loadDataRepresentation`, `UTType`, visual effects, button styles, file importer, drop targets, and security-scoped URL calls.
- `scripts/linux-gtk-check.sh` now validates both `quill-enchanted` and `quill-enchanted-upstream-slice` with Linux tests, GTK builds, and Xvfb process smokes.
- `scripts/linux-gtk-visual-check.sh` can capture either executable; the upstream slice has a nonblank 1180x760 GTK screenshot at `.qa/quill-enchanted-upstream-slice-gtk.png`.

## Checkpoint 4: Upstream Slice Core Wiring

Status: passing on macOS and Linux GTK.

- `quill-enchanted-upstream-slice` now depends on `QuillEnchantedCore` instead of sample-only state for the root app.
- The upstream-shaped sidebar, conversation list, model switcher, empty prompts, message list, and composer are backed by `EnchantedModel`, local conversation history, persisted endpoint storage, Ollama model discovery, and streamed Ollama sends.
- `EnchantedModel` exposes the small adapter operations needed by upstream-shaped views: deleting a specific conversation and selecting a model by name.
- The upstream slice now includes a visible Ollama endpoint field so its real adapter path can recover from an unreachable default endpoint.
- Regression tests cover the adapter operations required by the upstream-shaped target.
- Visual QA captured the core-wired upstream slice at `.qa/quill-enchanted-upstream-slice-core-endpoint-gtk.png`.

## Checkpoint 5: Upstream Slice Vision Attachments

Status: passing on macOS and Linux GTK.

- `PendingImageAttachment` can now stage imported file URLs and dropped image data into `~/.quillui/enchanted/attachments` before sending, so attachment reads do not depend on transient picker/drop access.
- The upstream-shaped composer stores both a preview `Image` and the real `PendingImageAttachment`, then sends the attachment through `EnchantedModel.send(prompt:attachments:)`.
- Attachment staging errors now flow back into the model status line instead of silently failing.
- Regression tests cover staged file imports and staged dropped image data.
- Visual QA captured the attachment-wired upstream slice at `.qa/quill-enchanted-upstream-slice-attachments-gtk.png`.

## Checkpoint 6: Markdown And Settings Surface

Status: passing on macOS and Linux GTK.

- `MarkdownMessageView` is now a public `QuillEnchantedCore` view so upstream-shaped targets can reuse the same portable Markdown renderer as the main app.
- The upstream-shaped message list now renders assistant/system messages with the portable Markdown fallback instead of flat `Text`, covering headings, lists, quotes, links, and fenced code blocks without pulling in MarkdownUI/Splash on Linux.
- The upstream-shaped sidebar now includes a Settings entry and a compact settings panel path for model refresh, model selection, and clearing conversation history, backed by the real `EnchantedModel`.
- Visual QA captured the updated upstream slice at `.qa/quill-enchanted-upstream-slice-markdown-settings-gtk.png`.

## Checkpoint 7: QuillData Library Pivot

Status: initial QuillData target passing locally.

- Added a reusable `QuillData` library product so SwiftData compatibility work moves out of Enchanted-specific code.
- The first backend is a conservative SQLite JSON-row store with SwiftData-shaped `Schema`, `ModelConfiguration`, `ModelContainer`, `ModelContext`, `FetchDescriptor`, `PersistentModel`, `@Attribute`, and `@Relationship` APIs.
- `ModelContext` supports insert, fetch, sort, closure filtering, delete, delete-all, save, and `saveChanges`, with class model tracking for mutation-before-save workflows.
- Foundation `#Predicate` is supported for value models; class-backed predicates are explicitly rejected for this slow backend because Foundation predicate evaluation can trap outside SwiftData's macro/runtime path.
- Documented the QuillData strategy and the future SQLiteData/schema-native backend path in `docs/quilldata.md`.

## Checkpoint 8: Enchanted On QuillData

Status: passing on macOS and Linux GTK.

- Added `QuillDataConversationStore`, a reusable `ConversationPersistence` implementation backed by the new QuillData `ModelContext`.
- Enchanted's default `EnchantedModelContext` now uses QuillData instead of the app-specific `SQLiteConversationStore`.
- The legacy `SQLiteConversationStore` remains available for regression coverage, but it is no longer the default app path and is not a migration requirement because the port has no existing Linux users.
- Enchanted persistence tests now exercise the QuillData path for insert, fetch, rename, delete, app model injection, and upstream-slice adapter operations.
- Linux GTK verification passed with QuillData included in the app/test graph.

## Checkpoint 9: Editable Message Trim Path

Status: passing on macOS and Linux GTK.

- Added a persistence-level message trimming operation that deletes the selected message and every later message in the same conversation.
- Wired the upstream-shaped edit flow so resending an edited user message trims stale assistant replies before sending the replacement prompt.
- QuillData is covered for the new edit-trim path; the legacy SQLite store keeps matching regression coverage only as a reference backend.
- Added model-level coverage for trimming a selected conversation from an edited user message.
- Linux GTK verification passed with 27 tests, both GTK products built, and both apps surviving the Xvfb smoke run.
- Visual QA captured the updated upstream slice at `.qa/quill-enchanted-upstream-slice-edit-trim-gtk.png`.

## Checkpoint 10: Generation Stop Control

Status: passing on macOS and Linux GTK.

- Added model-owned send task management so app surfaces can start generation through `EnchantedModel` instead of discarding local view tasks.
- Added `stopGenerating()` and cancellation checks in the streaming send loop so the Stop control has a real cancellation path.
- The primary Quill Enchanted surface now shows a Stop button during generation instead of a disabled Busy button.
- The upstream-shaped slice now routes its square Stop control to the model cancellation path.
- Added coverage for the model stop state used by toolbar/composer generation controls.
- Linux GTK verification passed with 28 tests, both GTK products built, and both apps surviving the Xvfb smoke run.

## Checkpoint 11: Reusable QuillUI Floating Icon Control

Status: passing on macOS and Linux GTK.

- Extracted the upstream-slice `SimpleFloatingButton` stand-in into reusable QuillUI API as `QuillFloatingIconButton`.
- Added `QuillGrowingButtonStyle` to QuillUI so pressed icon-button behavior is not Enchanted-specific.
- Updated the upstream-shaped composer to use the QuillUI control for attach, send, and stop actions.
- Added Linux compatibility coverage that instantiates the reusable control alongside file import/drop and visual-effect shims.
- Linux GTK verification passed with 28 tests, both GTK products built, and both apps surviving the Xvfb smoke run.

## Checkpoint 12: Reusable QuillUI Prompt List

Status: passing on macOS and Linux GTK.

- Added reusable `QuillPrompt` and `QuillPromptList` controls to QuillUI for empty states and suggested-action rows.
- Replaced the upstream-slice local `SamplePrompts` stand-in with `QuillPromptList`.
- Swapped the upstream-slice prompt icons to SwiftOpenUI-mapped symbols so the GTK build renders real icons instead of placeholder glyphs.
- Added Linux compatibility coverage that instantiates `QuillPromptList` alongside other upstream SwiftUI shims.
- Linux GTK verification passed with 28 tests, both GTK products built, and both apps surviving the Xvfb smoke run.
- Visual QA captured the updated upstream slice at `.qa/quill-enchanted-upstream-slice-prompt-list-gtk.png`.

## Checkpoint 13: Header More Menu And Contract Matrix

Status: passing on macOS and Linux GTK.

- Added reusable `QuillMenuAction` and `QuillMenuButton` controls to QuillUI.
- Wired a real upstream-slice header More menu for New Chat, Refresh Models, and Clear Conversations.
- Added Linux compatibility coverage that instantiates `QuillMenuButton` with menu items, dividers, and disabled actions.
- Added `CoreContractMatrixTests`, a parameterized regression matrix with 392 cases covering title compaction, Markdown inline cleanup, Markdown structural parsing, Ollama stream parsing, byte formatting, image media-type acceptance, unsupported image rejection, and attachment path normalization.
- macOS verification passed with 34 top-level tests plus the 392-case contract matrix.
- Linux GTK verification passed with 36 top-level tests plus the same 392-case contract matrix, both GTK products built, and both apps surviving the Xvfb smoke run.
- Visual QA captured the updated upstream slice at `.qa/quill-enchanted-upstream-slice-menu-contracts-gtk.png`.

## Checkpoint 14: Enchanted Visual Parity Pass

Status: passing on macOS and Linux GTK.

- Reworked the upstream-shaped Linux slice to read more like Enchanted on macOS: neutral sidebar, compact toolbar, centered Enchanted wordmark, four-card prompt empty state, and a wider pill composer.
- Added reusable `QuillPromptGrid` to QuillUI for Enchanted-style empty states instead of list-only suggested prompts.
- Added `QuillSystemSymbol.compatibleName(_:)` so upstream SF Symbol names such as `paperplane.fill`, `photo.fill`, and `lightbulb.circle` have GTK-safe fallbacks.
- Added deterministic prompt-card line breaking for SwiftOpenUI/GTK, where `Text` does not yet wrap like SwiftUI.
- macOS verification passed with 34 top-level tests plus the 392-case contract matrix.
- Linux GTK verification passed with 36 top-level tests plus the same 392-case contract matrix, both GTK products built, and both apps surviving the Xvfb smoke run.
- Visual QA captured the updated upstream slice at `.qa/quill-enchanted-upstream-slice-visual-parity-gtk.png`.

## Checkpoint 15: Live Quill Chat Reference And Coverage Audit

Status: passing on macOS and Linux GTK.

- Inspected the running `co.lorehex.quillchat` app directly instead of using the generic upstream Enchanted reference.
- Confirmed the live target surface: toolbar title `Quill Chat`, centered `Quill` wordmark, four prompt cards, date-grouped sidebar, bottom Completions/Shortcuts/Settings actions, pink unreachable banner, and rounded message composer.
- Added `scripts/audit-quill-chat.sh`, which audits the actual `/Users/jperla/claude/quill/clients/quill-chat` source for Swift files, LOC, imports, SwiftUI/SwiftData/platform API surfaces, prototype slice size, and app-side change budget.
- Moved more live-app UI pieces into reusable QuillUI controls: `QuillConversationHistoryList`, `QuillSidebarBottomNavigation`, `QuillStatusBanner`, and `QuillChatEmptyState`.
- Updated the Linux slice to use the live Quill Chat names, prompts, sidebar shape, unreachable banner, and empty state instead of the older Enchanted-branded approximation.
- Current audit baseline: 92 Swift files, 7,577 Swift LOC, clean Quill Chat working tree, 797-line prototype slice, and a target app-side compatibility shim budget of <= 100 lines.
- Current honest coverage status: not 100%. The blocked areas are still macro-level SwiftData drop-in support, Apple platform services, and several third-party UI/service packages.
- macOS `swift test` passed with 34 top-level tests plus the 392-case contract matrix.
- Linux GTK verification passed with 36 top-level tests plus the same 392-case contract matrix, both GTK products built, and both apps surviving the Xvfb smoke run.
- Visual QA captured the live-reference slice at `.qa/quill-chat-live-reference-slice-gtk.png`.

Next implementation slice:

- Replace the prototype slice with a source-compatibility harness against the real Quill Chat files, then drive app-side changes toward the <= 100-line budget.
- Close the next missing QuillUI API cluster before adding app-specific code: focused scene/openWindow compatibility, sheet/dialog/menu behavior, and the real GTK file picker/drag-drop path.

## Checkpoint 16: Compatibility Stub Reduction

Status: passing on macOS and Linux GTK.

- Replaced the old `NSItemProvider` data no-op with file/data representations, UTType conformance checks, extension-based file type detection, and real `loadDataRepresentation(for:)` callbacks.
- Wired SwiftUI-shaped `.onDrop(of:isTargeted:perform:)` to SwiftOpenUI's GTK `dropDestination(for: URL.self)`, including file type filtering and provider creation for dropped file URLs.
- Replaced the `.fileImporter` no-op with a deterministic importer path: test selection for regression coverage, `QUILLUI_FILE_IMPORTER_SELECTION` for scripted Linux runs, and desktop command fallbacks through `zenity`, `kdialog`, or `yad`.
- Added `focusedSceneValue` over SwiftOpenUI `focusedValue`, so Quill Chat's focused scene values can compile without an app-local shim.
- Added Linux compatibility for macOS-style system and asset colors used by Quill Chat: `Color(.label)`, `Color(.systemGray)`, `Color(.systemRed)`, `Color("label")`, `Color.grayCustom`, `Color.gray5Custom`, and related asset names.
- Improved visible fallbacks for `foregroundStyle`: color styles now map to `foregroundColor`, gradient styles degrade to a deterministic averaged color, and two-color foreground styles compile for Markdown checkbox rendering.
- Unknown custom SwiftUI `ButtonStyle`s now render as plain GTK buttons instead of falling back to default platform chrome; this keeps Enchanted's many `GrowingButton()` call sites closer to the macOS look while the exact pressed-scale animation remains a future SwiftOpenUI feature.
- Added more source-compatibility shims used by Quill Chat: `preferredColorScheme`, `PlainListStyle`/`listStyle`, Linux `PlatformImage`, a minimal `ImageRenderer`, and a fallback `KeyboardReadable` protocol.
- Added Linux-only regression coverage for file import validation, dropped-file data loading, system/asset color compatibility, two-color `foregroundStyle`, custom button style compilation, color-scheme/list-style modifiers, image renderer symbols, and `KeyboardReadable`.
- macOS `swift test` passed with 34 top-level tests plus the 392-case contract matrix.
- Linux GTK verification passed with 38 top-level tests plus the same 392-case contract matrix, both GTK products built, and both apps surviving the Xvfb smoke run.
- Remaining honest gaps: native GTK file picker integration, exact gradient text masking, `symbolEffect`, `matchedGeometryEffect`, macro-level SwiftData drop-in support, Apple platform services, and third-party package compatibility.

## Checkpoint 17: Command Menu Form Compatibility

Status: passing on macOS and Linux GTK.

- Added source-compatibility coverage for Quill Chat's real command/menu idioms: `CommandGroup(replacing:)`, `CommandGroup(after:)`, `.appSettings`, `.appInfo`, command `Button`s, disabled commands, and keyboard shortcut wrappers.
- Added SwiftUI-style `Menu { ... } label: { ... }` support with extraction for `Button`, disabled buttons, dividers, `ForEach`-built menu items, and generic fallback labels.
- Added toolbar and picker compatibility used by Quill Chat: `ToolbarItemGroup`, macOS/iOS placement aliases, `Picker(selection:content:label:)`, `.pickerStyle(.menu)`, and `Label { } icon: { }`.
- Added form/input shims for `Section(header:)`, `.formStyle(.grouped)`, `RoundedBorderTextFieldStyle`, `PlainTextFieldStyle`, text content type, autocorrection, keyboard type, and autocapitalization modifiers.
- Added `@Namespace`, `matchedGeometryEffect(id:in:)`, and `Material.ultraThickMaterial` fallbacks so animation-heavy and material-heavy source compiles without app-local edits.
- Added Linux-only regression coverage that instantiates the new command, menu, picker, form, toolbar, text-field, namespace, matched-geometry, and `onChange(of:initial:)` surface together.
- Updated the Quill Chat audit script to distinguish source-compatible partial-real surfaces from remaining native-behavior polish.
- macOS `swift test` passed with 34 top-level tests plus the 392-case contract matrix.
- Linux GTK verification passed with the same package graph, both GTK products built, and both apps surviving the Xvfb smoke run.
- Remaining honest gaps: exact native GTK menu presentation metadata, `symbolEffect`, exact matched-geometry animation, macro-level SwiftData drop-in support, Apple platform services, and third-party package compatibility.

## Checkpoint 18: QuillKit Platform Compatibility Layer

Status: passing on macOS and Linux GTK.

- Added a `QuillKit` library product for platform/service compatibility so QuillUI can stay focused on SwiftUI-shaped view APIs.
- Added Linux source-compatibility modules for `SwiftUI`, `SwiftData`, `UniformTypeIdentifiers`, `Combine`, `AppKit`, `UIKit`, `AVFoundation`, `Speech`, `KeyboardShortcuts`, `Magnet`, `PhotosUI`, `Security`, `ServiceManagement`, `Sparkle`, `ApplicationServices`, `CoreGraphics`, `Alamofire`, `ActivityIndicatorView`, `Vortex`, and `WrappingHStack`.
- Centralized reusable Linux service state in QuillKit: capability reporting, emulated clipboard storage, speech voice/synthesis hooks, launch-service state, trust/certificate placeholders, hotkey registration hooks, and accessibility status.
- Moved AppKit/UIKit pasteboard shims onto QuillKit's clipboard backend, AVFoundation speech shims onto QuillKit's speech backend, and ServiceManagement launch-item state onto QuillKit's launch-service backend.
- Added Linux import-module regression tests covering SwiftUI/SwiftData aliases, third-party UI shims, Apple service shims, Security/CoreGraphics/ApplicationServices/Alamofire shims, and Combine cancellation/timer compatibility.
- Fixed a structural source-compatibility trap introduced by the Linux `SwiftUI` alias: QuillUI's own internals now use OS checks instead of `canImport(SwiftUI)`, so app targets can import the shim without making QuillUI recursively import itself.
- Quill Chat itself remains untouched: the working tree at `/Users/jperla/claude/quill/clients/quill-chat` is still clean.
- macOS `swift test` passed with 34 tests in 7 suites plus the contract matrix.
- Linux `swift test` passed with 43 tests in 10 suites plus the contract matrix.
- Linux GTK verification passed: both GTK products built and both apps survived the Xvfb smoke run.
- Remaining honest gaps: native Linux implementations behind QuillKit for clipboard/secret-service/speech/global shortcuts/USB detection/updater behavior, `MarkdownUI`/`Splash` compatibility, macro-level SwiftData drop-in support, exact menu presentation, and exact animation behavior.

## Checkpoint 19: Quality Baseline Pass

Status: passing on macOS, Linux, GTK smoke, and GTK screenshot smoke.

- Audited the current QuillUI/QuillKit base for concurrency hazards, silent fallback behavior, weak Linux-only compile coverage, and warning noise.
- Added `QuillCompatibilityDiagnostics` so compatibility fallbacks record explicit diagnostic events instead of disappearing silently.
- Made QuillKit service state safer: type-aware clipboard string/data storage, lock-protected launch-service state, lock-protected speech state, and workspace opening through `xdg-open` on Linux.
- Moved AppKit/UIKit/Speech/CoreGraphics/Security fallback behavior onto diagnostics, so missing native Linux backends are visible during QA.
- Strengthened the Combine shim with idempotent `AnyCancellable`, `store(in:)`, `Just`, `Empty`, `Fail`, `PassthroughSubject`, and a real two-input `Publishers.Merge`.
- Removed the file importer's mutable static state by moving the test hook behind a locked `static let` box, which satisfies Linux Swift 6 concurrency checking.
- Replaced the QuillData uninitialized attribute `fatalError` with an explicit precondition failure.
- Added `QuillKitTests` for clipboard, diagnostics, and launch-service state, and expanded Linux compatibility-module tests for Combine subjects/merge.
- Added `scripts/patch-swiftopenui-gtk-css.sh` and wired it into GTK smoke scripts to remove unsupported GTK `object-fit` CSS from the pinned SwiftOpenUI checkout during reproducible Linux QA.
- The source/test hygiene scan for `nonisolated(unsafe)`, `fatalError`, `TODO`, `FIXME`, stub/no-op wording, and stray `print(` is clean.
- macOS `swift test` passed with 37 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux` passed with 47 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the Xvfb smoke run.
- GTK screenshot smoke passed for `quill-enchanted`: `.qa/quill-enchanted-gtk-quality.png` at 1180x760 with mean pixel value 62165.1.
- Quality grade after this pass: A- for the foundation. The remaining downgrade is product coverage, not local code hygiene: native Linux service backends, full MarkdownUI/Splash compatibility, macro-level SwiftData drop-in strategy, exact menus, and exact animation parity still need real implementation work.

## Checkpoint 20: Expanded Reuse Regression Suite

Status: passing on macOS, Linux, and full Linux GTK smoke.

- Added broad edge-case coverage for the reusable base: QuillData fetch/sort/limit/delete/upsert/persistence/relationship behavior, QuillKit clipboard/capability/speech/hotkey/trust behavior, AppStorage persistence/binding/raw-value behavior, upstream file/drop/UTType shims, and Linux compatibility modules.
- Fixed QuillData chained sorting so multi-sort fetch descriptors use a single ordered comparator instead of relying on repeated sort passes.
- Made process-wide fallback tests deterministic by serializing the AppStorage and Linux compatibility-module suites around `UserDefaults` and shared shim state.
- Added diagnostic fallback smoke coverage for Apple service modules through `AppleCompatibilitySmoke`, keeping direct UIKit/AppKit/AVFoundation/Speech/Security/CoreGraphics imports out of Swift Testing-generated Linux test files.
- macOS `swift test` passed with 49 top-level tests in 8 suites, including the large parameterized contract matrix.
- Linux `swift test --scratch-path .build-linux` passed with 69 top-level tests in 11 suites.
- Linux GTK verification passed: dependencies checked, both GTK products built, and both apps survived the 6-second Xvfb smoke run.
- `bash -n scripts/*.sh`, the source/test hygiene scan, and `scripts/audit-quill-chat.sh` are clean.
- Quill Chat itself remains untouched: the working tree at `/Users/jperla/claude/quill/clients/quill-chat` is still clean, and the prototype slice remains 797 lines of scaffolding rather than the intended final app-side port shape.
- Remaining honest gaps: native Linux service backends, full MarkdownUI/Splash compatibility, macro-level SwiftData source compatibility, exact GTK menus, exact animation parity, and broad app-by-app validation beyond the current Enchanted/Quill Chat slice.

## Checkpoint 21: Combine Behavior Upgrade

Status: passing on macOS, Linux, and full Linux GTK smoke.

- Upgraded the Linux `Combine` shim from compile-only timer/notification publishers to emitting publishers backed by `DispatchSourceTimer` and `NotificationCenter` observers.
- Made `PassthroughSubject` completion terminal: existing subscribers receive completion, later values are ignored, and late subscribers immediately receive the terminal completion.
- Added Linux regression tests for terminal subject completion and live timer/notification publisher emission.
- Kept cancellation idempotent and scoped: timer sources cancel through `AnyCancellable`, notification observers are removed on cancel, and subject subscriber cancellation still removes only that subscriber.
- macOS `swift test` still passed with 49 top-level tests in 8 suites.
- Linux GTK verification passed with 71 top-level tests in 11 suites, both GTK products built, and both apps surviving the 6-second Xvfb smoke run.
- `bash -n scripts/*.sh` and the source/test hygiene scan remain clean.
- Compatibility grade impact: the Combine surface moves from compile-only C+/B- toward B for app portability. Remaining Combine gaps include schedulers, operators beyond `map`/`merge`, demand/backpressure, `CurrentValueSubject`, `Published`, and richer async bridging.

## Checkpoint 22: OpenCombine And Coverage Baseline

Status: passing on macOS, Linux, and Linux GTK smoke.

- Replaced the local Linux `Combine` implementation with OpenCombine 0.14.0 re-exported from the `Combine` compatibility module.
- Kept only thin source-compatibility veneers around OpenCombine for spellings used by target apps: `AnyPublisher()`, `NotificationCenter.publisher(for:object:)`, and `Publishers.Merge`.
- Left Foundation as plain `import Foundation`, relying on Apple's swift-corelibs-foundation on Linux instead of creating a QuillKit wrapper for APIs already supplied by the official runtime.
- Hardened QuillData so nonthrowing `insert(_:)` and `delete(_:)` record persistence failures and surface them through `save()`, and added locking around context state plus the shared SQLite handle/encoder/decoder.
- Added QuillUI diagnostics for source-compatible fallback modifiers such as `symbolEffect`, `matchedGeometryEffect`, `mask`, text-input hints, form styles, custom button styles, and image rendering mode.
- Added `docs/api-coverage-matrix.md` as the current API coverage matrix for compile, behavior, native, and tested status across QuillUI, QuillKit, QuillData, Combine, platform services, third-party packages, and Enchanted.
- Added `scripts/coverage-summary.sh` and made GTK QA scripts faster by skipping apt when packages are present or `QUILLUI_SKIP_APT=1`; GTK smoke duration is now configurable with `QUILLUI_SMOKE_SECONDS`.
- macOS `swift test` and `swift test --enable-code-coverage` passed with 51 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux-cov --enable-code-coverage` passed with 74 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the Xvfb smoke run.
- Coverage baseline: Linux QuillUI 545/1458 lines (37.4%), Linux QuillKit 142/175 lines (81.1%); macOS QuillKit 121/135 lines (89.6%). macOS QuillUI reports 0/692 because the Linux compatibility shims are not compiled by the macOS test graph.
- `bash -n scripts/*.sh` and the source/test hygiene scan remain clean.
- Remaining long-term gap: true macro-level SwiftData drop-in and near-zero-change real Quill Chat source compilation remain the next major milestone, separate from this checkpoint's 1-4 fixes.

## Checkpoint 23: P1/P2 Fixes And 90% QuillUI Coverage

Status: passing on macOS and Linux, with Linux QuillUI coverage inside the 80-100% target band.

- Fixed the P1 QuillData delete-all resurrection bug: `ModelContext.delete(model:)` now untracks class-backed model instances after deleting all rows, so later mutation plus `save()` cannot reinsert deleted objects.
- Fixed the P1 Enchanted model actor-isolation issue by making `EnchantedModel` main-actor isolated and updating the Linux/macOS app entry points and upstream-shaped views to construct it through main-actor-safe paths.
- Fixed the P2 Combine merge demand bug: the local `Publishers.Merge` veneer now buffers values beyond current downstream demand, waits for both inputs before finishing, and cancels both upstream subscriptions deterministically.
- Fixed the P2 disabled menu behavior: disabled menu adapters now suppress item actions, command items preserve disabled state, and regression tests cover both paths.
- Replaced several compile-only visual fallbacks with visible approximations: shape masks map to `clipShape`, `symbolEffect` and `matchedGeometryEffect` apply value-driven animations with diagnostics, and grouped form styles render grouped padding/background.
- Made `.fileImporter` and `.onDrop` return concrete SwiftOpenUI wrapper types on Linux, which keeps caller source compatibility while letting tests exercise stored selection/drop closures directly.
- Added high-signal Linux tests that materialize nested SwiftOpenUI view trees and exercise menu, command, picker, file importer, drop, color, environment, task, form, mask, and visual-effect compatibility paths.
- Linux `swift test --scratch-path .build-linux` passed with 81 tests in 11 suites.
- Linux `swift test --scratch-path .build-linux-cov --enable-code-coverage` passed with 81 tests in 11 suites.
- Coverage after this pass: Linux QuillUI 1339/1488 lines (90.0%), functions 245/283 (86.6%), regions 374/457 (81.8%); Linux QuillKit 142/175 lines (81.1%), functions 50/56 (89.3%), regions 53/62 (85.5%).
- File-level Linux QuillUI coverage: `AppStorage.swift` 96.9%, `Compatibility.swift` 90.7%, `Controls.swift` 98.1%, `UpstreamCompatibility.swift` 80.0%.
- macOS `swift test` passed with 52 tests in 8 suites.
- `bash -n scripts/*.sh` passed.
- Remaining honest gaps are now native-depth rather than P1/P2 correctness: exact GTK/libadwaita menus, exact symbol/matched-geometry animation parity, native text-input hints, native Linux service backends, full MarkdownUI/Splash compatibility, and macro-level SwiftData source compatibility.

## Checkpoint 24: Empty-State Visual Parity Pass

Status: passing on macOS, Linux, and Linux GTK visual smoke.

- Tightened the upstream-shaped Quill Chat GTK empty state against the macOS reference: the sidebar now requests a 330px split-view column instead of the narrow default, matching the Mac layout proportions more closely at the 1180x760 smoke size.
- Hid the offline/reachability banner on the empty conversation state, so first launch keeps the clean Quill wordmark, prompt cards, and bottom composer layout. The warning remains available once a real conversation is selected.
- Refreshed the Quill Chat audit script's visual-effects row to reflect the current partial-real state: shape masks, `symbolEffect`, and `matchedGeometryEffect` now have visible approximations rather than being future compile-only work.
- Linux visual QA captured `.qa/heartbeat-gtk-visual-polish.png` for `quill-enchanted-upstream-slice`: 1180x760, mean pixel value 63496.4.
- macOS `swift test` passed with 52 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux` passed with 81 tests in 11 suites.
- `bash -n scripts/*.sh` and `scripts/audit-quill-chat.sh` passed.
- The `@preconcurrency View` bridge remains intentionally in place for the two main-actor app roots. Removing it fails Linux Swift 6 conformance isolation against SwiftOpenUI's currently nonisolated `View` protocol; the remaining warning is a backend/protocol isolation cleanup item, not an app correctness failure.

## Checkpoint 25: Enchanted MarkdownUI And Splash Compatibility

Status: passing on macOS and Linux.

- Added Linux compatibility targets and public products for `MarkdownUI` and `Splash`, closing two upstream Enchanted third-party import blockers.
- Implemented the Enchanted-used MarkdownUI surface: `Markdown`, `Theme` builder methods, `CodeBlockConfiguration`, block/table/task-list configuration types, Markdown text style declarations, relative spacing/padding/frame helpers, margin/table style modifiers, `CodeSyntaxHighlighter`, and `Text + Text` composition.
- Implemented the Enchanted-used Splash surface: `Theme.sunset`, `Theme.wwdc17`, token colors, `SyntaxHighlighter`, `OutputFormat`, `OutputBuilder`, and SwiftUI `Color` conversion from Splash colors.
- Added source-compatible `Color(rgba:)`, `Color(light:dark:)`, `.symbolRenderingMode(...)`, and generic-view `.imageScale(...)` fallbacks for Enchanted's Markdown theme and task-list marker styling.
- Added Linux regression tests that compile an Enchanted-shaped Markdown theme and Splash syntax highlighter contract, including headings, paragraphs, blockquotes, code blocks, task markers, tables, relative layout modifiers, and syntax-highlighted text.
- Fixed the Linux GTK QA scripts to use SwiftPM's current `--show-bin-path` instead of globbing `.build-linux/*/debug`, preventing stale macOS scratch binaries from being selected when the same checkout is tested from both macOS and the Linux VM.
- macOS `swift test` passed with 52 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux` passed with 82 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the Xvfb smoke run.
- `bash -n scripts/*.sh` passed.
- Remaining honest gaps: the real Enchanted source still is not the build input, SwiftData macro/source compatibility is still the biggest app-side blocker, and MarkdownUI/Splash behavior is simplified rather than full visual parity.

## Checkpoint 26: Enchanted Ollama And Prompt Dependencies

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added Linux compatibility targets and public products for `OllamaKit`, `AsyncAlgorithms`, and `Carbon`, closing the next real upstream Enchanted import blockers after MarkdownUI/Splash.
- Implemented the Enchanted-used `OllamaKit` surface with real HTTP-backed `models()`, `reachable()`, and streaming `chat(data:)` behavior, including bearer-token headers, `/api/tags`, `/api/version`, `/api/chat`, and newline-delimited Ollama response parsing.
- Added `OKModelsResponse`, `OKModelResponse`, `OKModelDetails`, `OKCompletionOptions`, `OKChatRequestData`, `OKChatRequestData.Message.Role`, and `OKChatResponse` contracts used by Enchanted's `OllamaService`, conversation store, and prompt completions view model.
- Added a minimal `AsyncAlgorithms.AsyncTimerSequence` compatibility type for the prompt panel timer loop and a `Carbon` import shell that reports explicit unavailable state on Linux.
- Added Linux regression tests covering Ollama model parsing, bearer-token propagation, chat request encoding, streamed response aggregation, `AsyncTimerSequence`, and the Carbon compatibility marker.
- macOS `swift test --disable-automatic-resolution` passed with 52 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux` passed with 85 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the 4-second Xvfb smoke run.
- `bash -n scripts/*.sh`, `git diff --check`, `scripts/audit-quill-chat.sh`, and `scripts/audit-upstream-enchanted.sh` passed.
- Remaining honest gaps: real Enchanted source is still not the build input, SwiftData macro/source compatibility remains the biggest app-side blocker, and native IOKit/USB device events are not implemented.

## Checkpoint 27: IOKit USB Import Shell

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added a Linux `IOKit` system-library compatibility target with a Clang module map and `IOKit.usb` submodule, covering `import IOKit` and `import IOKit.usb` at the module level.
- Added no-op IOKit USB/device symbols used by Quill Chat's macOS USB watcher surface: `io_object_t`, `io_iterator_t`, `IONotificationPortRef`, `IOServiceMatchingCallback`, `IONotificationPortCreate`, `IONotificationPortDestroy`, `IONotificationPortSetDispatchQueue`, `IOServiceAddMatchingNotification`, `IOIteratorNext`, `IOObjectRelease`, `kIOMainPortDefault`, `kIOFirstMatchNotification`, `kIOTerminatedNotification`, `kIOUSBDeviceClassName`, `kUSBVendorID`, and `kUSBProductID`.
- Added `QuillKitCapability.deviceEvents` so Linux device watching is tracked as a first-class platform-service gap instead of being hidden inside the app.
- Added Linux regression coverage for `IOKit`/`IOKit.usb` imports, constants, callback types, iterator calls, and explicit unsupported notification registration.
- macOS `swift test --disable-automatic-resolution` passed with 52 tests in 8 suites.
- Linux `swift test --scratch-path .build-linux` passed with 86 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the 4-second Xvfb smoke run.
- `bash -n scripts/*.sh`, `git diff --check`, `scripts/audit-quill-chat.sh`, and `scripts/audit-upstream-enchanted.sh` passed.
- Remaining honest gap: Darwin's `IONotificationPortSetDispatchQueue(..., DispatchQueue.main)` bridging does not exist in Linux C Dispatch, and real device-arrival behavior should be implemented with a native QuillKit udev/libusb backend.

## Checkpoint 28: QuillData Source-Shape Tightening

Status: passing on macOS, Linux, and Linux GTK smoke.

- Moved QuillData closer to SwiftData's source shape by removing the nonstandard built-in `ModelContext.saveChanges()` method that would collide with Enchanted's own `ModelContext` extension.
- Added `ModelContext.hasChanges`, which lets Enchanted's existing app-defined `saveChanges()` extension compile against QuillData.
- Relaxed `PersistentModel` so Codable models do not also need an explicit `Identifiable` conformance; the SQLite row identity now falls back through stable encoded `id`, `name`, or `slug` fields.
- Improved class-backed model tracking with an identity map, so fetched class instances replace duplicate decoded copies and later mutation plus `save()` persists the tracked object.
- Added regression tests for `hasChanges`, name-backed identity upserts, class-backed fetch/mutate/save behavior, and existing class filter/delete semantics.
- macOS verification passed: `swift test --disable-automatic-resolution` with 54 tests in 8 suites.
- Linux verification passed: `swift test --scratch-path .build-linux` with 88 tests in 11 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the 4-second Xvfb smoke run.
- `bash -n scripts/*.sh`, `git diff --check`, `scripts/audit-quill-chat.sh`, and `scripts/audit-upstream-enchanted.sh` passed.
- Remaining honest gap: Foundation `#Predicate` still cannot be used safely with plain class-backed models because it can trap before QuillData receives the descriptor. Enchanted's class `#Predicate` calls still need a macro/lowering strategy or small source rewrite to closure filters.

## Checkpoint 29: QuillData Generated SwiftData Lowering

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added `QuillPredicate`, a class-safe closure predicate with `FetchDescriptor(predicate:)` and `ModelContext.delete(model:where:)` overloads. This covers Enchanted's three class-backed `#Predicate` shapes without touching Foundation's unsafe class predicate evaluator.
- Added optional `@Attribute` and `@Relationship` defaults so SwiftData declarations like `@Attribute(.externalStorage) var image: Data?` and `@Relationship(deleteRule: .nullify) var model: LanguageModelSD?` compile and read back as `nil` before assignment.
- Added `scripts/lower-swiftdata-for-quilldata.sh`, which materializes a generated Linux source copy and rewrites `@Model` classes to `PersistentModel`, removes computed-property `@Transient`, and lowers `#Predicate<T>` to `QuillPredicate<T>`.
- Verified the lowering script against the real Quill Chat source: 92 Swift files were copied, all four SwiftData model classes gained `PersistentModel`, and all three class `#Predicate` call sites were lowered to `QuillPredicate`.
- Added regression tests for class relationship lookup predicates, date-range delete predicates, optional wrapper defaults, and the source-lowering script.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux verification passed: `swift test --scratch-path .build-linux` with 92 tests in 12 suites.
- Linux GTK verification passed: both GTK products built and both apps survived the 4-second Xvfb smoke run.
- `bash -n scripts/*.sh`, `git diff --check`, `scripts/audit-quill-chat.sh`, and `scripts/audit-upstream-enchanted.sh` passed.
- Remaining honest gap: this is still generated-source lowering, not a first-class Swift compiler macro or SwiftPM build plugin. The next step is to wire the generated source into a real Enchanted Linux build target instead of the current prototype slice.

## Checkpoint 30: Generated Enchanted Core Build

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added `scripts/generated-enchanted-core-check.sh`, a repeatable Linux-only source-compatibility harness that copies real upstream Enchanted `Models`, `Stores`, `SwiftData` models, selected `Services`, and the `ModelContext` extension into a generated SwiftPM executable.
- The harness runs `scripts/lower-swiftdata-for-quilldata.sh`, removes `@Observable` from generated source, adds generated identity/equality shims for SwiftData model classes, adds Linux image-rendering helper shims, and marshals OpenCombine sink callbacks back to `MainActor`.
- Verified the generated package against the real upstream Enchanted core: 18 Swift files are lowered and the `generated-enchanted-core` executable builds on Linux through the QuillUI `SwiftUI`, `SwiftData`, `Combine`, and `OllamaKit` compatibility products.
- Wired the generated real-source core check into `scripts/linux-gtk-check.sh` so normal Linux GTK QA now validates both the prototype GTK apps and the generated Enchanted core source.
- Updated the Quill Chat audit and API coverage matrix to distinguish the remaining prototype UI slice from the new real-source model/store/service compile harness.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux GTK verification passed: `swift test` with 92 tests in 12 suites, generated Enchanted core build, both GTK products built, and both apps survived the 4-second Xvfb smoke run.
- Remaining honest gap: the UI layer is still split between the prototype GTK slice and upstream SwiftUI files. The next milestone is expanding generated-source compilation to `UI/Shared` and `UI/macOS/Chat` so the prototype can shrink toward a tiny Linux entry point.

## Checkpoint 31: Generated Enchanted Chat Components Build

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added `scripts/generated-enchanted-chat-components-check.sh`, a repeatable Linux-only harness that copies 38 real upstream Enchanted Swift files covering core models/stores, selected services, shared chat message views, empty state, status, model picker, selected/removable images, options menu, reading-aloud UI, simple floating buttons, Markdown, and Splash syntax highlighting.
- Expanded QuillUI's SwiftUI compatibility surface for the shared chat UI: `FocusState`, `ContextMenu`, `AnyTransition`, `PinnedScrollableViews`, `TextSelectability`, `AngularGradient`, `GridItem(.flexible/fixed, spacing:alignment:)`, `LazyVGrid(columns:alignment:spacing:)`, list-row modifiers, hover/text-selection/focus fallbacks, `offset(CGSize)`, `padding(EdgeInsets)`, `HStack`/`VStack` `Double` spacing, `Animation.snappy`, `repeatForever`, and `delay`.
- Moved the Linux `NSImage` compatibility type into QuillUI and made AppKit expose the same type, so `SwiftUI` no longer depends on the AppKit compatibility module while still supporting `Image(nsImage:)`.
- Fixed `FocusState` to provide SwiftUI-shaped default initializers for `Bool` and optional values, plus nonmutating writes, which also restored the prototype upstream slice build.
- Wired the generated chat-components check into `scripts/linux-gtk-check.sh` after the generated core check.
- Added Linux regression coverage for the Enchanted chat component modifier/layout/focus/transition surface.
- Updated the Quill Chat audit script and API coverage matrix to distinguish the generated real-source chat component harness from the older prototype slice.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux verification passed: `swift test --scratch-path .build-linux` with 93 tests in 12 suites.
- Linux GTK verification passed: unit tests, generated Enchanted core build, generated Enchanted chat-components build, both GTK products built, and both apps survived the 4-second Xvfb smoke run.
- Remaining honest gaps: this still uses generated-source lowering for SwiftData macros, previews, and SwiftOpenUI main-actor mismatches; it does not yet compile the full `UI/macOS/Chat` entry path or replace the prototype app with real Enchanted source plus a tiny Linux entry point.

## Checkpoint 32: Generated Enchanted macOS Chat Build

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added `scripts/generated-enchanted-macos-chat-check.sh`, a repeatable Linux-only harness that copies 45 real upstream Enchanted Swift files and compiles the actual `UI/macOS/Chat` path through QuillUI/QuillData.
- The new harness covers `ChatView_macOS`, `InputFields_macOS`, `ToolbarView_macOS`, `DragAndDrop`, `UnreachableAPIView`, recorder UI, `SpeechRecognizer`, shared chat messages, model picker, options menu, selected/removable images, stores, services, SwiftData models, Markdown, Splash, ActivityIndicatorView, AppKit, AVFoundation, Speech, Combine, and OllamaKit.
- Kept app-specific generated shims in the harness for hotkeys, a minimal `SidebarView`, a minimal `Settings` view, identity/hashability, and image rendering. Those are compile bridges, not edits to Enchanted or permanent QuillUI APIs.
- Expanded reusable QuillUI compatibility for the macOS chat path: Linux platform colors for `.pink`, `.black`, and `.white`; material aliases including `.ultraThinMaterial`; `Shape.strokeBorder(style:)`; `View.minimumScaleFactor(_:)`; and `Image(nsImage: PlatformImage)` through the Linux `SwiftUI` facade.
- Wired the generated macOS-chat check into `scripts/linux-gtk-check.sh` after the generated core and shared chat component checks.
- Added Linux regression coverage for the new material, stroke-border, minimum-scale-factor, and platform-color compatibility calls.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux coverage after this pass: QuillUI 1516/1713 lines (88.5%), functions 291/346 (84.1%), regions 420/520 (80.8%); QuillKit 142/175 lines (81.1%), functions 50/56 (89.3%), regions 53/62 (85.5%); QuillData 608/676 lines (89.9%), functions 96/117 (82.1%), regions 212/249 (85.1%).
- Linux GTK verification passed: unit tests, generated Enchanted core build, generated Enchanted chat-components build, generated Enchanted macOS-chat build, both GTK products built, and both apps survived the 4-second Xvfb smoke run.
- `bash -n scripts/*.sh`, `git diff --check`, `scripts/audit-quill-chat.sh`, and `scripts/audit-upstream-enchanted.sh` passed.
- Remaining honest gaps: this still uses generated source lowering for SwiftData macros, previews, actor/main-actor mismatches, and Enchanted-only hotkeys; it still uses a generated sidebar/settings bridge rather than the full real application entry/sidebar/settings source.

## Checkpoint 33: Generated Enchanted Full-Source Build

Status: passing on macOS, Linux, and Linux GTK smoke.

- Added `scripts/generated-enchanted-full-source-check.sh`, a Linux-only harness that copies all 87 upstream Enchanted Swift files, lowers SwiftData/Observation/previews/platform gates into generated source, and compiles the result through QuillUI, QuillData, QuillKit module shells, SwiftOpenUI, and OpenCombine.
- The harness now covers the full application/sidebar/settings/menu-bar/prompt-panel/completions/iOS/macOS/shared source set, not only the earlier core, shared chat components, or 45-file macOS chat slice.
- Moved reusable compatibility out of the generated harness and into QuillUI/AppKit/KeyboardShortcuts where it belongs: `State(initialValue:)`, default `WindowGroup`, `LabeledContent`, `Table`, `DragGesture`, scroll/focus/safe-area modifiers, `Array.move(fromOffsets:toOffset:)`, AppKit `NSImage`/`NSBitmapImageRep` image surface, and `KeyboardShortcuts.Name(default:)`.
- Kept only app-specific generated bridges in the full-source harness for Linux-only accessibility/hotkey/prompt-panel behavior, identity/hashability, and a generated entry point. Enchanted source itself remains untouched.
- Wired the full-source harness into `scripts/linux-gtk-check.sh`, after the generated core/chat/macOS-chat checks and before the GTK app smoke builds.
- Added Linux regression coverage for the new full-source compatibility surface and AppKit/KeyboardShortcuts adapters.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux verification passed: `swift test --scratch-path .build-linux` with 97 tests in 12 suites.
- Linux coverage after this pass: QuillUI 1816/2038 lines (89.1%), functions 345/405 (85.2%), regions 490/598 (81.9%); QuillKit 142/175 lines (81.1%), functions 50/56 (89.3%), regions 53/62 (85.5%).
- Generated full-source verification passed: 87 source Swift files copied, 89 generated Swift files compiled, and no generated-code warnings after lowering cleanup; remaining warnings are external SwiftPM/OpenCombine `-pthread` warnings.
- Linux GTK verification passed: unit tests, generated Enchanted core build, chat-components build, macOS-chat build, full-source build, both GTK products built, and both apps survived the 4-second Xvfb smoke run.
- Remaining honest gaps: this is 87/87 upstream Enchanted compile coverage, not yet the local 92-file Quill Chat rebrand as a production Linux app. The remaining work is turning the generated source pipeline into a maintained build plugin/tiny Linux entry point and replacing diagnostic service fallbacks with native Linux backends.

## Checkpoint 34: Local Quill Chat Full-Source Build

Status: passing on macOS, Linux, and Linux GTK smoke.

- Extended the full-source generated harness to handle the local Quill Chat rebrand without editing the app source: `ENCHANTED_SOURCE_DIR=/Users/jperla/claude/quill/clients/quill-chat/Enchanted QUILLUI_GENERATED_ENCHANTED_FULL_WORKDIR=/tmp/quill-chat-full-source-check scripts/generated-enchanted-full-source-check.sh`.
- Added a Linux `os` compatibility product with privacy-aware `Logger` interpolation, covering Quill Chat's USB launcher logging surface.
- Added the Quill Chat `OllamaKit(baseURL:bearerToken:session:)` initializer shape so the app's pinned Alamofire session call sites compile through the compatibility package.
- Added generated Linux bridges for Quill Chat's Sparkle updater menu item and macOS USB watcher/LaunchAgent services. These record or expose unavailable fallback behavior instead of running macOS launch services on Linux.
- Updated the audit script and API coverage matrix so the local 92-file Quill Chat full-source check is a first-class repeatable QA target, not a one-off manual command.
- Local Quill Chat generated full-source verification passed: 92 source Swift files copied and 94 generated Swift files compiled.
- macOS verification passed: `swift test --disable-automatic-resolution` with 58 tests in 9 suites.
- Linux GTK verification passed: 98 tests in 12 suites, generated Enchanted core build, chat-components build, macOS-chat build, upstream 87-file full-source build, both GTK products built, and both apps survived the 6-second Xvfb smoke run.
- `bash -n scripts/*.sh` and `git diff --check` passed.
- Remaining honest gaps: this is still generated-source compile coverage for the local Quill Chat app, not a packaged production Linux app. The next step is to turn the generated pipeline into a tiny maintained Linux target/build plugin and replace the updater/USB/platform-service fallbacks with native Linux backends where the app needs real behavior.

## Checkpoint 35: Quill Chat Generated App Build Tooling

Status: passing for generated check mode and generated app mode on Linux.

- Parameterized `scripts/generated-enchanted-full-source-check.sh` with `QUILLUI_GENERATED_ENCHANTED_MODE=check|app`, keeping the old compile-check product while adding app mode for a GTK-backed executable target.
- Added `scripts/build-quill-chat-linux.sh`, which points the generated-source pipeline at the local Quill Chat tree and emits `quill-chat-linux` without editing Quill Chat source.
- Wired optional local Quill Chat app generation into `scripts/linux-gtk-check.sh` when `../quill/clients/quill-chat/Enchanted` exists, with `QUILLUI_SKIP_QUILL_CHAT_BUILD=1` available for CI or machines without the local app checkout.
- Verified old check mode still builds the upstream 87-file generated product.
- Verified app mode builds the local 92-file Quill Chat tree into `/tmp/quill-chat-linux-build/.build-check/aarch64-unknown-linux-gnu/debug/quill-chat-linux`.
- Verified the generated `quill-chat-linux` executable survives a 6-second Xvfb smoke run; current warnings are GTK theme/accessibility noise and missing Material icon mappings, not startup failures.
- `bash -n scripts/*.sh` and `git diff --check` passed.
- Remaining honest gaps: this is shell build tooling, not yet a SwiftPM plugin; the generated app starts, but native Linux service behavior and screenshot-level visual parity still need the next passes.

## Checkpoint 36: SwiftOpenUI Checkout Patching for Quill Chat Icons

Status: passing for patch smoke, macOS tests, and generated Quill Chat Linux app smoke.

- Extended `scripts/patch-swiftopenui-gtk-css.sh` into the common pinned-SwiftOpenUI checkout patch step. It still removes unsupported GTK `object-fit` CSS and now adds the Quill Chat SF Symbol names missing from SwiftOpenUI's Material symbol map.
- Added mappings for Quill Chat symbols currently visible in the generated app path, including `textformat.abc`, `keyboard.fill`, `lightbulb.circle`, `waveform`, `sidebar.left`, `line.3.horizontal`, `paperplane.fill`, `photo.fill`, `speaker.wave.*`, `selection.pin.in.out`, and related stop/close/check variants.
- Wired `scripts/generated-enchanted-full-source-check.sh` to patch its generated package scratch checkout before building, so `scripts/build-quill-chat-linux.sh` gets the same renderer/icon patching as the root GTK smoke path.
- Expanded `QuillSystemSymbol.compatibleName(_:)` coverage for `keyboard.fill` and `x.circle.fill`, with regression expectations in `UpstreamCompatibilityTests`.
- Verified a fresh patch smoke inserts `textformat.abc`, `keyboard.fill`, and `sidebar.left` into SwiftOpenUI's map and removes `object-fit` from the GTK renderer.
- Verified `swift test --disable-automatic-resolution` passes on macOS with 58 tests in 9 suites.
- Verified generated local `quill-chat-linux` builds from the 92-file Quill Chat tree and survives a 6-second Xvfb smoke without missing Material-symbol or GTK `object-fit` warnings. Remaining smoke output is the Lima/Xvfb DRI3 acceleration warning.
- Remaining honest gaps: this is still a local checkout patch around a pinned dependency. The durable fix is to upstream the SF Symbol mappings to SwiftOpenUI or move QuillUI to a fork/revision containing them.

## Checkpoint 37: Generic SwiftUI Linux App Builder

Status: passing on macOS tests, direct generic Linux build, wrapper Linux build, and generated app smoke.

- Added `scripts/build-swiftui-linux-app.sh` as the generic build-tooling entry point for SwiftUI-shaped app trees. It accepts `--source-dir`, `--app-type`, `--product-name`, `--workdir`, `--run`, and `--profile`.
- Kept source lowering honest by making `enchanted-full-source` an explicit profile instead of presenting Enchanted/Quill Chat rewrites as universal Swift app lowering.
- Changed `scripts/build-quill-chat-linux.sh` into a thin wrapper over the generic builder with Quill Chat's source directory, `EnchantedApp`, `quill-chat-linux`, and the `enchanted-full-source` profile.
- Added generic environment aliases to `scripts/generated-enchanted-full-source-check.sh`: `QUILLUI_APP_SOURCE_DIR`, `QUILLUI_GENERATED_APP_WORKDIR`, `QUILLUI_GENERATED_APP_MODE`, `QUILLUI_GENERATED_APP_PRODUCT_NAME`, `QUILLUI_GENERATED_APP_PACKAGE_NAME`, `QUILLUI_GENERATED_APP_TARGET_NAME`, `QUILLUI_GENERATED_APP_ENTRY_TYPE`, and `QUILLUI_GENERATED_APP_MAIN_TYPE`.
- Added validation for generated Swift app entry/main type names before emitting `GeneratedMain.swift`.
- Added `docs/linux-build-tooling.md` to document the stable CLI contract and the current profile boundary.
- Verified `swift test --disable-automatic-resolution` passes on macOS with 58 tests in 9 suites.
- Verified the generic command builds the local 92-file Quill Chat tree and emits `quill-chat-linux` from `--source-dir`, `--app-type`, `--product-name`, and `--profile`.
- Verified the generated generic-builder `quill-chat-linux` executable survives a 6-second Xvfb smoke run.
- Verified `scripts/build-quill-chat-linux.sh` still builds as a wrapper over the generic command.
- `bash -n scripts/*.sh` and `git diff --check` passed.
- Remaining honest gap: the build CLI is generalized; the lowering backend is not yet universal. The next durable step is a profile/plugin system where IceCubes, NetNewsWire, CodeEdit, WireGuard, and other apps each add reusable compatibility/lowering rules instead of new bespoke app scripts.

## Checkpoint 38: Move Profile Fallbacks into Libraries

Status: passing on macOS tests, Linux GTK checks, generated full-source app build, and Xvfb smoke.

- Moved reusable Enchanted/Quill Chat Linux fallbacks for accessibility, hotkey combinations, floating panels, panel manager, updater, device watcher/launcher, `Window`, `NSWindow`, one-shot hotkey registration, image rendering placeholders, and platform-image base64/compression helpers into QuillKit, QuillUI, and AppKit.
- Replaced profile-embedded service heredocs with a small generated alias bridge, keeping app/source names while routing behavior through library APIs.
- Reduced `scripts/generated-enchanted-full-source-check.sh` from 730 lines to 554 lines; the removed code now lives in tested compatibility modules instead of the profile.
- Expanded QuillKit and Linux compatibility-module tests for the moved services, AppKit window/hotkey shape, image fallback diagnostics, AppStorage, file importer, symbol mapping, UTType inference, and NSItemProvider data/file flows.
- Verified `swift test --disable-automatic-resolution` on macOS: 59 tests in 9 suites passed.
- Verified Linux GTK QA: 107 tests in 12 suites passed, generated Enchanted core/chat/macOS/full-source checks passed, the generic local 92-file Quill Chat app built as `quill-chat-linux`, and GTK apps survived a 6-second Xvfb smoke run.
- Verified no missing Material-symbol or GTK `object-fit` warnings in the final Linux smoke log; remaining smoke output is the Lima/Xvfb DRI3 acceleration warning.
- Remaining honest gap: the profile still contains app-specific source-shape rewrites and generated compile-check construction. The next reduction should move the lowering rules into a real profile directory/build-plugin layer and keep only app-specific model conformances and names outside shared libraries.

## Checkpoint 39: Discoverable App Build Profiles

Status: passing for profile discovery, direct generated Quill Chat build, alias build, and generated app smoke.

- Added `scripts/profiles/` as the build-tooling profile directory so new app profiles can be added without editing the generic `scripts/build-swiftui-linux-app.sh` dispatcher.
- Moved the Enchanted/Quill Chat app-build dispatch into `scripts/profiles/enchanted-full-source.sh`, with `scripts/profiles/enchanted.sh` preserving the previous short profile alias.
- Added `--list-profiles` to the generic builder and documented the stable `QUILLUI_PROFILE_*` environment contract passed from the generic builder to profile scripts.
- Verified `scripts/build-swiftui-linux-app.sh --list-profiles` reports `enchanted-full-source` and `enchanted`.
- Verified the plugin-dispatched `enchanted-full-source` profile builds the local 92-file Quill Chat tree into `quill-chat-linux` and survives a 6-second Xvfb smoke run.
- Verified the compatibility alias `--profile enchanted` still builds the local 92-file Quill Chat generated app.
- `bash -n scripts/*.sh scripts/profiles/*.sh` and `git diff --check` passed.
- Remaining honest gap: profile discovery is now generic, but the Enchanted lowering implementation still lives in the legacy generated full-source script. The next pass should split lowering phases into profile-owned files so the generic generated-package writer can be reused by IceCubes, NetNewsWire, CodeEdit, and WireGuard.

## Checkpoint 40: Reusable Generated Package Builder

Status: passing for generated check mode, generic app mode, and Xvfb startup smoke after the refactor.

- Added `scripts/generate-swiftui-linux-package.sh` as the reusable generated-package assembly layer for SwiftUI-shaped app profiles.
- Moved generic source copying, SwiftPM package writing, broad QuillUI compatibility-product dependency wiring, optional GTK `@main` generation, SwiftOpenUI checkout patching, and final `swift build` out of the Enchanted full-source script.
- Reduced `scripts/generated-enchanted-full-source-check.sh` from 554 lines to 465 lines; its remaining content is now mostly Enchanted/Quill Chat source lowering and app-specific compile-check construction.
- Documented the stable `QUILLUI_GENERATED_*` package-helper contract in `docs/linux-build-tooling.md`.
- Expanded Linux-only compatibility tests for gradients, `PresentationMode`, compatibility error descriptions, `FocusState`, `Namespace`, sidebar actions, prompt identity, transitions, and diagnostic event equality.
- Verified the compatibility test expansion on Linux: 116 tests in 12 suites passed.
- Verified macOS tests after the compatibility expansion: 59 tests in 9 suites passed.
- Verified generated check mode through the new package helper against the local 92-file Quill Chat tree: 95 generated Swift files compiled.
- Verified generic app mode through `scripts/build-swiftui-linux-app.sh --profile enchanted-full-source`: `quill-chat-linux` built and survived a 6-second Xvfb startup smoke.
- `bash -n scripts/*.sh scripts/profiles/*.sh`, `scripts/build-swiftui-linux-app.sh --list-profiles`, and `git diff --check` passed.
- Remaining honest gap: Enchanted lowering is still a large shell profile. Next reductions should split source rewrites into named profile phases and move more source-shape compatibility into QuillUI/QuillKit APIs.

## Checkpoint 41: Cross-Platform Parity Tests

Status: passing on macOS and Linux test suites.

- Added `QuillParityTests`, a cross-platform test target that runs the same assertions on macOS and Linux for UTType identifiers/conformance, URL path behavior, UserDefaults semantics, JSON round-trips, Calendar date deltas, QuillData model-context persistence, and deterministic fuzz cases.
- Exposed QuillUI view-tree extraction helpers as `@_spi(QuillTesting)` so Linux compatibility tests can assert menu, command, label, and symbol extraction behavior directly without making those helpers public API.
- Added Linux compatibility coverage for `quillTextLabel`, `quillSystemImageName`, `quillMenuElements`, `quillCommandMenuItems`, and `quillPickerOptions`, including disabled-action behavior.
- Documented a real Foundation parity edge case: swift-corelibs `UserDefaults.integer(forKey:)` does not preserve every platform-sized extreme `Int`, so parity coverage now uses the portable integer range QuillUI/AppStorage depends on.
- Verified macOS: `swift test --disable-automatic-resolution` passed with 73 tests in 10 suites.
- Verified Linux: `swift test --scratch-path .build-linux` passed with 135 tests in 13 suites.
- Remaining honest gap: this is API/semantic parity coverage, not visual parity. Next useful parity tests should compare generated view trees and eventually screenshot-level output against real SwiftUI references.

## Checkpoint 42: Shared SwiftUI Source Lowering

Status: passing for generated check mode, generic app mode, and Xvfb startup smoke after extraction.

- Added `scripts/lower-swiftui-source-for-linux.sh` for app-agnostic cleanup of generated SwiftUI source before Linux builds.
- Moved generic `@main`, `@Observable`, preview, `@MainActor`, `os(macOS)`, and `View, Sendable` rewrites out of the Enchanted full-source script.
- Documented the generic SwiftData and SwiftUI source-lowering helpers in `docs/linux-build-tooling.md`.
- Verified generated check mode against the local 92-file Quill Chat tree through the shared SwiftUI lowering helper.
- Verified generic app mode through `scripts/build-swiftui-linux-app.sh --profile enchanted-full-source`: `quill-chat-linux` built and survived a 6-second Xvfb startup smoke.
- `bash -n scripts/*.sh scripts/profiles/*.sh` and `git diff --check` passed.
- Remaining honest gap: most of the Enchanted script is still app-specific actor/async/store/view patching. Future passes should convert those into named, testable profile phases and move more source-shape compatibility into library APIs.

## Checkpoint 43: Enchanted Profile Lowering Phase

Status: passing for shell checks, profile discovery, generated check mode, generic app mode, and Xvfb startup smoke after extraction.

- Added `scripts/profiles/enchanted-full-source/lower-profile-source.sh` as the Enchanted/Quill Chat-specific source-lowering phase.
- Moved the app-specific actor/async/store/view rewrites, replacement-file cleanup, generated profile aliases, and generated model hashability shims out of `scripts/generated-enchanted-full-source-check.sh`.
- Reduced the legacy generated full-source script from 457 lines to 220 lines; the `enchanted-full-source` profile wrapper remains 33 lines, and the profile-owned lowering phase is now isolated at 258 lines.
- Documented the convention that profile-specific lowering phases live under `scripts/profiles/<profile-name>/`.
- Verified `bash -n scripts/*.sh scripts/profiles/*.sh scripts/profiles/*/*.sh`, `scripts/build-swiftui-linux-app.sh --list-profiles`, and `git diff --check`.
- Verified generated check mode against the local 92-file Quill Chat tree: 95 generated Swift files compiled.
- Verified generic app mode through `scripts/build-swiftui-linux-app.sh --profile enchanted-full-source`: `quill-chat-linux` built and survived a 6-second Xvfb startup smoke.
- Remaining honest gap: the profile-specific phase is now isolated but still mostly regex source rewriting. The next reduction should turn repeated rewrite categories into tested reusable lowering helpers, then push more behavior into QuillUI/QuillKit APIs so app profiles shrink toward descriptor-sized files.

## Checkpoint 44: GdkPixbuf TIFF Transcoding for AppKit Images

Status: passing on Linux tests, macOS parity tests, generated Enchanted check mode, generic app mode, and Xvfb startup smoke.

- Added a Linux `CGdkPixbuf` system-library bridge and `quillTranscodeImageDataToTIFF(_:)` so QuillUI can decode image bytes through gdk-pixbuf and re-encode real TIFF data.
- Changed Linux `NSImage.tiffRepresentation` from returning mislabeled source bytes to deterministic TIFF behavior: existing TIFF data passes through unchanged, valid PNG/JPEG/GIF/BMP/WebP input transcodes to TIFF, and corrupt or unknown input returns `nil` with a warning.
- Added format-sniffing coverage for TIFF, PNG, JPEG, GIF, BMP, WebP, and unknown bytes; added Linux tests for valid PNG-to-TIFF transcoding, corrupt-input warnings, deterministic TIFF pass-through, and the direct gdk-pixbuf bridge.
- Added macOS parity tests proving real AppKit returns TIFF data for valid TIFF/PNG inputs and nil for garbage input.
- Updated the AppKit compatibility smoke and API coverage matrix so image behavior is now `partial-real` instead of pure fallback.
- Verified Linux: `swift test --scratch-path .build-linux` passed with 141 tests in 13 suites.
- Verified macOS: `swift test --disable-automatic-resolution` passed with 75 tests in 10 suites.
- Verified generated check mode against the local 92-file Quill Chat tree: 95 generated Swift files compiled.
- Verified generic app mode through `scripts/build-swiftui-linux-app.sh --profile enchanted-full-source`: `quill-chat-linux` built and survived a 6-second Xvfb startup smoke.
- Remaining honest gap: `ImageRenderer` and SwiftUI view rasterization are still nil-returning fallbacks. The native follow-up is an offscreen GTK snapshot/Cairo encode path for SwiftUI views, not another `NSImage` byte-transcode shim.

## Checkpoint 45: Generated Quill Chat Visual Smoke

Status: passing for generated app build and Xvfb screenshot smoke.

- Extended `scripts/linux-gtk-visual-check.sh` so it can screenshot the generated `quill-chat-linux` product, not only root SwiftPM products like `quill-enchanted`.
- For `quill-chat-linux`, the visual script now builds through `scripts/build-quill-chat-linux.sh`, resolves the generated package executable with SwiftPM's active bin path, launches it under Xvfb, and captures the screenshot.
- Tightened visual smoke validation from brightness-only to brightness plus pixel variation, so a blank white window no longer passes the check.
- Documented the generated app visual command in `docs/linux-build-tooling.md` and updated the API coverage matrix QA row.
- Verified in the Linux VM with `QUILLUI_SKIP_APT=1 scripts/linux-gtk-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux`: screenshot captured at 1180x760 with mean 62672.1 and standard deviation 4059.4.
- Remaining honest gap: this is still a nonblank/variation smoke, not a perceptual comparison against the macOS Quill Chat screenshot. The next visual QA step should compute layout landmarks such as sidebar width, toolbar height, composer position, prompt card bounds, and dominant colors from the screenshot.

## Checkpoint 46: Generated Quill Chat Layout Parity

Status: passing on macOS tests, Linux generated full-source build, and Linux GTK visual smoke.

- Added `QuillDesktopSplitLayout`, a reusable QuillUI desktop shell for apps whose SwiftUI `NavigationSplitView` source compiles but collapses visually under the current GTK backend.
- Extended `QuillChatEmptyState` with explicit card geometry so generated Linux apps can render the same four-card Quill prompt grid shape as the macOS reference instead of relying on `LazyVGrid` behavior.
- Updated the Enchanted full-source profile to rewrite only the generated Linux `ChatView_macOS.swift` and `EmptyConversaitonView.swift` copies, leaving upstream app sources untouched while avoiding the collapsed sidebar, vertical prompt-card layout, and narrow composer seen in the previous screenshot.
- Serialized the cross-platform parity suite because it exercises global `UserDefaults.standard` state; this removes a Linux-only parallel test race without changing the API under test.
- Added structural view-tree coverage for the desktop split shell and the fixed-geometry empty state.
- Verified macOS: `swift test --disable-automatic-resolution` passed with 75 tests in 10 suites.
- Verified Linux earlier in this checkpoint: `swift test --scratch-path .build-linux` passed with 141 tests in 13 suites.
- Verified generated check mode: `scripts/generated-enchanted-full-source-check.sh` compiled 90 generated Swift files from the 87-file reduced check slice.
- Verified generated app visual mode: `QUILLUI_SKIP_APT=1 scripts/linux-gtk-visual-check.sh .qa/quill-chat-linux-generated-gtk.png quill-chat-linux` captured a 1180x760 screenshot with mean 46702.9 and standard deviation 27302.8.
- Remaining honest gap: this is now much closer to the supplied macOS screenshot, but it is still layout-directed parity rather than a true screenshot comparator. The next pass should add landmark assertions for sidebar width, header height, prompt-card positions, and composer width.
