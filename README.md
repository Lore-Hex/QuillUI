# QuillUI

QuillUI is an open-source Swift UI portability layer for bringing
SwiftUI-shaped app code to Linux desktops while keeping the same app scenes
usable on Apple platforms.

**Function-by-function Apple package coverage:** start with the [Apple package function coverage ledger](docs/apple-package-function-coverage.md)
for the per-function complete/incomplete status of each cloned Apple package
and app-facing package clone. Network has the first concentrated parity pocket:
the [Network function rows](docs/apple-package-function-coverage.md#network)
separate path/interface enum value APIs plus address/endpoint value APIs that
are parity-tested from the still incomplete transport, DNS, TLS, connection,
listener, VPN, and monitoring work.

The Linux runtime and build graph are selected separately. `QUILLUI_BACKEND`
requests `gtk` or `qt` at launch for backend smoke/profile parity. App products
use canonical executable names on Linux; the SwiftPM manifest-time selector
`QUILLUI_LINUX_BACKEND=gtk|qt` chooses whether those products compile against
GTK or Qt dependencies. Qt builds require Qt6 Widgets and never load the GTK
graph.

`QuillChatKit` is a reusable SwiftUI chat chrome library product for Signal,
Telegram, and native SwiftUI clients on macOS/iOS. Its native SwiftUI boundary
is checked with `scripts/check-quillchatkit-ios.sh`, which builds the library
against the iOS simulator SDK at the package's iOS 14 floor. The default
`ChatAppearance.standard` tokens preserve the desktop app chrome, while
`ChatAppearance.touch` and `ChatAppearance.platformDefault` provide touch-first
density profiles for iOS clients without a UIKit or QuillUI dependency.
`ChatSplitShell` is available on iOS 16+ / macOS 13+ for apps that want the
same split-view chat routing used by the Linux Signal and Telegram targets.

Current backend parity app targets:

1. `quill-enchanted`
2. `quill-enchanted-upstream-slice`
3. `quill-icecubes`
4. `quill-netnewswire`
5. `quill-codeedit`
6. `quill-signal`
7. `quill-telegram`
8. `quill-iina`
9. `quill-wireguard`

Generated external app coverage also includes `quill-chat-linux` when the
local Quill Chat checkout is available.

## Apple Package Function Coverage

The [Apple package function coverage ledger](docs/apple-package-function-coverage.md)
is the source of truth for function-by-function complete/incomplete status
across SwiftUI, SwiftData, AppKit/UIKit, Network, media/service kits, system
kits, third-party package clones, and app progress. Rows marked `Parity` are
the only rows treated as full Apple/Linux contract matches.

- [Network function coverage](docs/apple-package-function-coverage.md#network): current
  Network rows that have reached Apple/Linux parity. The path/interface enum
  rows are pinned by `NetworkPathInterfaceParityTests` for string,
  equality, and hash semantics; the address rows are backed by Apple-observed
  IPv4/IPv6 parser, data initializer, classifier-boundary, multicast-scope,
  IPv4 mapping, string, and debug-output tests; the endpoint rows cover scoped
  and unscoped host parsing, direct-value equality/hash coherence, port
  parser/constant/equality/hash semantics, and host-port/service/Unix endpoint
  value behavior.
- [API coverage matrix](docs/api-coverage-matrix.md): backend and app-facing API evidence.
- [App targets](docs/app-targets.md): target-by-target app progress.

Direct package anchors in the function coverage ledger: [SwiftUI](docs/apple-package-function-coverage.md#swiftui), [SwiftData](docs/apple-package-function-coverage.md#swiftdata), [AppKit](docs/apple-package-function-coverage.md#appkit), [UIKit](docs/apple-package-function-coverage.md#uikit), [WebKit](docs/apple-package-function-coverage.md#webkit), [AuthenticationServices](docs/apple-package-function-coverage.md#authenticationservices), [UniformTypeIdentifiers](docs/apple-package-function-coverage.md#uniformtypeidentifiers), [Network](docs/apple-package-function-coverage.md#network), [NetworkExtension](docs/apple-package-function-coverage.md#networkextension), [CoreGraphics](docs/apple-package-function-coverage.md#coregraphics), [Security](docs/apple-package-function-coverage.md#security), [AVFoundation](docs/apple-package-function-coverage.md#avfoundation), [AVKit](docs/apple-package-function-coverage.md#avkit), [Speech](docs/apple-package-function-coverage.md#speech), [PhotosUI and Photos](docs/apple-package-function-coverage.md#photosui-and-photos), [Charts](docs/apple-package-function-coverage.md#charts), [StoreKit](docs/apple-package-function-coverage.md#storekit), [TipKit](docs/apple-package-function-coverage.md#tipkit), [Observation](docs/apple-package-function-coverage.md#observation), [ApplicationServices](docs/apple-package-function-coverage.md#applicationservices), [ServiceManagement](docs/apple-package-function-coverage.md#servicemanagement), [AsyncAlgorithms](docs/apple-package-function-coverage.md#asyncalgorithms), [Carbon](docs/apple-package-function-coverage.md#carbon), [Combine](docs/apple-package-function-coverage.md#combine), [os](docs/apple-package-function-coverage.md#os), [IOKit](docs/apple-package-function-coverage.md#iokit), [re-export-only Apple shims](docs/apple-package-function-coverage.md#re-export-only-apple-shims), [third-party and app-support package clones](docs/apple-package-function-coverage.md#third-party-and-app-support-package-clones), and [app progress](docs/apple-package-function-coverage.md#app-progress-summary).

## Coverage Ledgers

- [Apple package function coverage](docs/apple-package-function-coverage.md): direct function-by-function coverage ledger.
- [API coverage matrix](docs/api-coverage-matrix.md): backend and app-facing API evidence.
- [App targets](docs/app-targets.md): target-by-target app progress.

## Compatibility Progress

Status terms:

- `Apple-native`: QuillUI defers to the real Apple framework on Apple platforms.
- `Parity`: the same app/API source compiles and runs on Apple and Linux, with shared contract, golden, and seeded fuzz tests proving equivalent user-facing outputs except for explicitly documented platform differences.
- `Usable`: covered by source or smoke tests and exercised by at least one app target.
- `Partial`: enough API shape exists for current app ports, but framework behavior is incomplete.
- `Compile shim`: imports, types, and selected calls compile, with little or no runtime behavior.
- `Fallback`: the API intentionally degrades and usually records compatibility diagnostics.

Progress is intentionally conservative. `Compatible today` means either real
Linux runtime behavior exists or enough metadata is preserved for the GTK/Qt
backends and source-contract tests to prove the app-facing API shape. The
detailed evidence lives in [docs/api-coverage-matrix.md](docs/api-coverage-matrix.md),
[docs/apple-package-function-coverage.md](docs/apple-package-function-coverage.md),
and [docs/app-targets.md](docs/app-targets.md); this README is the high-level
checklist.

### Function-Level Compatibility Ledger

The function-by-function Apple package and app-facing package clone status lives
in [docs/apple-package-function-coverage.md](docs/apple-package-function-coverage.md).
In that ledger, `Usable` and `Parity` rows are complete for today's tested
Linux contract. `Partial`, `Fallback`, `Compile-only`, and `Incomplete` rows
are intentionally listed as incomplete until the missing Apple or upstream
package behavior is implemented and covered by source-contract, golden, or
seeded fuzz tests.

| Apple package area | Complete today | Incomplete today |
| --- | --- | --- |
| `SwiftUI` clone layer | Focused rows such as `Font.Weight`. | Most app-facing view and modifier metadata is still partial; full layout, diffing, animation, transition, gesture, accessibility, focus, scene, and rendering parity remains open. |
| `SwiftData` / `QuillData` | Table mapping, inserts, deletes, saves, deterministic error text, and current Enchanted persistence flows. | Full Apple SwiftData schema, relationship, predicate, migration, CloudKit, undo, observation, and concurrency semantics. |
| `AppKit` / `QuillAppKit` | In-memory undo, view hierarchy, window geometry, pasteboard, menu, pop-up, stack, progress, child-controller, and selected workspace/document flows. | Native event loop, Auto Layout, CALayer/drawing, accessibility, file dialogs, cursor/event taps, XPC, sharing, audio, host font metrics, and full window-manager behavior. |
| `UIKit` / `QuillUIKit` | `UIApplication.shared` and selected source-compatible aliases and in-memory bridges. | Mobile renderer, lifecycle, layout engine, navigation, presentation, text input, events, accessibility, haptics, notifications, and collection/table parity. |
| Web, network, media, and service Apple kits | Selected compile or fallback shapes for `WebKit`, `AuthenticationServices`, `Network`, `NetworkExtension`, `AVFoundation`, `Speech`, `PhotosUI`, `Charts`, `StoreKit`, and `TipKit`; `Network` address parsing, address constants, address classifier properties, scoped IPv4/IPv6/name host interface literals, port parsing with seeded fuzz coverage, port equality/hash semantics, well-known port constants, path status/reason/type string/equality/hash semantics, endpoint-host classification/equality/hash including scoped parsed-to-direct values, and `NWEndpoint` host-port/service/Unix path description/debug/equality/hash value APIs now have Apple-checked parity rows. | Real web rendering, authentication sessions, DNS/TLS/TCP/UDP behavior, VPN tunnels, media I/O, speech, photo library, chart rendering, purchases, and tip persistence. |
| System and support kits | Focused usable rows for `ServiceManagement`, `AsyncAlgorithms`, `AnyPublisher`, and `Logger` initialization. | Full `CoreGraphics`, `Security`, `Observation`, `ApplicationServices`, `Carbon`, `IOKit`, `os`, and Combine edge-case parity. |
| Re-export-only Apple shims | Imports compile for current app source. | Standalone framework behavior for `MessageUI`, `SafariServices`, `MobileCoreServices`, `LocalAuthentication`, and `CoreSpotlight`. |

### Current Progress Snapshot

| Track | Done now | Still open |
| --- | --- | --- |
| SwiftUI clone | App/scene launch, common view declarations, state wrappers, file-import helpers, menu/picker/list extraction, image helpers, compatibility diagnostics, and many modifier metadata paths compile and are tested against current app sources. | Full SwiftUI layout, accessibility, animation, transitions, gesture semantics, focus routing, multi-window scenes, and pixel-perfect backend rendering are incomplete. |
| Apple kit clones | AppKit, UIKit, SwiftData, Foundation/CoreGraphics/Security, WebKit, Network, media/service frameworks, Combine, `os`, and legacy platform kits expose enough surface for the app targets to compile. | Most kits are scoped app-contract clones, not full framework replacements; real platform services such as VPN tunnels, web rendering, media playback/capture, speech, and service management remain limited or fallback-only. |
| Third-party package clones | Enchanted and chat/editor/feed shells can compile with scoped clones of packages such as `OllamaKit`, `KeychainSwift`, `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, `Sparkle`, and `Alamofire`. | Package coverage follows the app ports. APIs not exercised by current targets may be missing or fallback-only. |
| App targets | Enchanted, WireGuard, Signal, Telegram, IceCubes, NetNewsWire, CodeEdit, IINA, and optional generated Quill Chat coverage are represented in the backend matrix. | Enchanted is the parity priority. The other ports are mostly shell/core-logic targets until their upstream app behaviors are brought across. |
| Backend parity | GTK and Qt build graphs are isolated and checked independently through shared matrix scripts. | GTK and Qt are both compared against native macOS behavior; neither Linux backend is treated as the reference for the other. |

### API-by-API SwiftUI Clone Progress

These rows track the SwiftUI-shaped API families QuillUI currently clones or
adapts. `Compatible today` means app source can compile and the preserved
metadata or runtime behavior is visible to the Linux backends and tests.

| API area | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `QuillUI` / `SwiftUI` module boundary | Apple-native on Apple, usable on Linux | Re-exports real SwiftUI on Apple platforms. Linux builds use SwiftOpenUI plus `QuillSwiftUICompatibility`, with `QuillUIGtk` and `QuillUIQt` sharing the same app scene contracts. | Not a complete SwiftUI replacement; compatibility is driven by the app matrix and source-contract tests. |
| App, scene, and backend launch | Usable | Canonical app products launch through `QUILLUI_BACKEND` at runtime and `QUILLUI_LINUX_BACKEND=gtk|qt` at build time. GTK and Qt products are tracked by `scripts/quillui-backend-products.sh app-matrix`. | Only the app/window patterns used by current ports are covered. Advanced SwiftUI scene types and multi-window behavior are still limited. |
| Text, labels, and markdown-shaped content | Partial | Current ports compile common `Text`, `Label`, text-label helpers, MarkdownUI/Splash-shaped code paths, prompt text, selection text, and shell copy affordances. | Rich text editing, full `AttributedString` rendering, bidirectional text, text selection parity, accessibility text metadata, and every Markdown/code-highlighting feature are incomplete. |
| Images, symbols, and rendering | Partial | `Image`, SF-symbol-style names, `Image(data:)`, `PlatformImage`, gdk-pixbuf round trips, `ImageRenderer` color payloads, and system icon contracts are tested. | General view-to-image rendering, full symbol fidelity, animated images, metadata/color-profile preservation, and every bitmap/vector format are incomplete. |
| Layout containers and navigation | Partial | Stacks, lists/sidebars, split-view-shaped shells, navigation routing, toolbar declarations, prompts, and initial selection flows compile for the current apps. | SwiftUI's full layout solver, layout priority, geometry preferences, scroll behavior, navigation stacks/split state restoration, and macOS-exact sidebar metrics need more backend work. |
| Controls, forms, menus, pickers, and dialogs | Partial | `Button`, `Form`, picker option extraction, menu extraction, confirmation dialogs, toolbar items, popovers/sheets via AppKit bridges, and app prompt controls are source-tested. | Control styling, keyboard navigation, validation, menu command routing, modal lifecycle, accessibility, and platform-native visual fidelity are incomplete. |
| State, environment, and storage | Partial | `@AppStorage` scalar and raw-enum persistence, bindings, `FocusState`, `Namespace`, `PresentationMode`, `OpenURLAction`, sidebar navigation actions, and prompt helpers have compatibility tests. | Full SwiftUI environment propagation, scene storage, focus routing, transaction semantics, and property-wrapper coverage remain incomplete. |
| Input, focus, hover, gestures, and keyboard hints | Partial | `FocusState`, generic focus binding wrappers, keyboard/text-entry modifiers, `contentShape`, `allowsHitTesting`, `gesture`, `onHover`, and `focusEffectDisabled` preserve metadata for backend rendering/layout/input/focus work. | Full event routing, gesture recognition, hover/focus visuals, accessibility focus, keyboard shortcut propagation, and responder-chain parity are incomplete. |
| Visual effects, masks, safe areas, transitions, and animation | Fallback to partial | Shape masks compile as `clipShape` approximations, generic view masks preserve content and mask metadata, safe-area modifiers preserve metadata, transition descriptors preserve metadata, and unsupported visual modifiers record diagnostics. | Exact transition playback, animation timing, matched geometry, symbol effects, complex masks, blend/compositing behavior, and visual-effect fidelity do not yet match macOS. |
| File import, item providers, and type identifiers | Partial | `QuillFileImporter`, `NSItemProvider`, and `UniformTypeIdentifiers` cover the app-facing extension, conforming extension, preferred metadata, and conformance checks used by current ports. | Full file promises, drag/drop provider behavior, sandbox security-scoped resources, and system type database parity are not implemented. |
| Diagnostics and unsupported modifiers | Usable fallback | Unsupported fallbacks such as `symbolEffect`, `matchedGeometryEffect`, `Image.renderingMode`, and `Form.formStyle` record `QuillCompatibilityDiagnostics`; shape masks compile as a `clipShape` approximation, while generic view masks preserve content and mask metadata. `symbolRenderingMode`, keyboard/text-entry modifiers plus generic `View.imageScale`, `minimumScaleFactor`, `textSelection`, `listRowInsets`, `listRowSeparator`, `scrollIndicators`, `scrollContentBackground`, `contentShape`, `allowsHitTesting`, `gesture`, `transition`, `onHover`, `focused`, `focusEffectDisabled`, `edgesIgnoringSafeArea`, and `ignoresSafeArea` now preserve metadata for backend rendering/layout/input/focus work. | These APIs may compile without changing visuals or behavior until a backend implementation is added. |
| Third-party SwiftUI package shapes | Partial | Compatibility shims exist for `ActivityIndicatorView`, `MarkdownUI`, `Splash`, `WrappingHStack`, `Vortex`, and `KeyboardShortcuts`; the tests verify the app-facing contracts. | These are not full upstream package clones, and visual fidelity is limited to the features currently exercised by app targets. |
| GTK and Qt backends | Usable | `QuillUIGtk` and `QuillUIQt` keep separate dependency graphs. Qt builds require Qt6 Widgets and avoid loading the GTK graph. Shared smoke/profile tooling keeps visual and interaction rows aligned. | Pixel-perfect macOS parity and performance parity are still tracked incrementally per app and per backend. |

### API-by-API Kit Clone Progress

These rows cover the Apple framework and third-party package surfaces that have
been cloned far enough for current QuillUI app targets.

| Kit or package | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `AppKit` / `QuillAppKit` | Partial | Pasteboard items, images, workspace icons, appearance names and common appearance matching, deterministic font-manager fallback lists, open-panel configuration and headless cancellation, menus, controls, popups, popovers, toolbars, windows, sheets, tabs, view hierarchy, frames, bounds, display/layout calls, hit testing, coordinate conversion, responders, event monitors, view controllers, split views, tracking areas, text views, table views, outline views, documents, and undo are source-tested. | This is not full AppKit. Host font discovery, native file dialogs, Auto Layout, CALayer, accessibility, drawing, full system appearance resolution, menu validation, document lifecycle, and platform window-manager behavior need more work. |
| `QuillAppKitGTK` | Usable | Provides GTK-side AppKit bridge pieces and smoke targets used by backend parity checks. | GTK behavior is not a reference for Qt; both still need independent comparison against native macOS behavior. |
| `UIKit` / `QuillUIKit` | Compile shim to partial | Linux app ports can import UIKit-shaped types such as views, view controllers, colors, fonts, screens, table/collection/navigation/split containers, responders, constraints, and pasteboard support. | There is no full UIKit renderer or mobile event, layout, animation, accessibility, or lifecycle parity. |
| `SwiftData` / `QuillData` | Partial and usable | `@QuillModel`, model containers, model contexts, fetch descriptors, predicates, sort descriptors, SQLite/GRDB persistence, source lowering, predicate fuzzing, and Enchanted conversation storage are tested. | Apple SwiftData migrations, CloudKit integration, complete relationship semantics, observation behavior, and concurrency rules are not fully cloned. |
| `UniformTypeIdentifiers` | Partial with usable app rows | File-extension lookup, conforming extension filters, common image aliases, preferred extension/MIME metadata, conformance checks, and app-facing item-provider flows are covered by compatibility tests. | It is not Apple's complete type database or LaunchServices-backed identifier system. |
| `QuillFoundation`, `QuillRS`, `CoreGraphics`, `Security` | Partial | Foundation-like selection helpers, image/color/font/screen aliases, localized string fallback, CoreGraphics image/render helpers, accessibility and security-shaped APIs compile and have focused tests. | Many APIs are placeholders or app-contract shims rather than complete framework implementations. |
| `QuillWebKit` / `WebKit` | Compile shim | `WKWebView`-shaped configuration, load, evaluate, and delegate APIs are available for source compatibility. | No full embedded web engine, JavaScript runtime, navigation stack, process model, or rendering parity exists yet. |
| `Network` and `NetworkExtension` | Partial overall; selected `Network` functions at Parity | Imports and app-facing types compile for ports such as WireGuard. `IPv4Address` and `IPv6Address` parsing, constants, data initializer lengths, classifier boundary behavior, multicast scope, IPv4 mapping, scoped interface literals, string/debug text, and absence of Linux-only public address classifiers are now covered by Apple-observed parity tests. `NWPath.Status`, `NWPath.UnsatisfiedReason`, `NWInterface.InterfaceType`, `NWEndpoint.Port` parsing/known constants/debug text/equality/hash behavior with seeded fuzz coverage, and the `NWEndpoint.Host.init(_:)` classification/description/equality/hash contract for current scoped and unscoped edge cases now match Apple-observed behavior, including scoped parsed-to-direct equality and scoped-vs-unscoped inequality. `NWEndpoint.hostPort`, `.service`, and `.unix` description/debug/equality/hash behavior now covers Apple-observed DNS-SD service-name escaping, `_tcp`/`_udp` type formatting, empty-name/domain cases, invalid-type concatenation, leading/internal domain dot behavior, exact endpoint equality, scoped host-port equality, and hash coherence. | Real VPN control, tunnel lifecycle, system extension behavior, DNS/TLS/TCP/UDP behavior, connections, listeners, path monitoring, and live interface/path probing are not implemented. |
| `AVFoundation`, `Speech`, `PhotosUI`, `MessageUI`, `SafariServices`, `MobileCoreServices` | Compile shim / fallback | Service-shaped modules compile and record diagnostic fallback behavior where applicable. | They do not provide real media capture/playback, speech recognition, photo picker, mail compose, browser, or mobile type services. |
| `Combine` | Partial | Publishers, subjects, merge, timers, notifications, cancellation, completion, and `AnyCancellable` contracts are tested. | The full Combine operator surface, scheduler semantics, and backpressure behavior are incomplete. |
| `os` | Partial | `Logger` and privacy diagnostic rendering are tested. | It is not Apple's unified logging system. |
| `AsyncAlgorithms`, `Carbon`, `IOKit`, `ApplicationServices`, `ServiceManagement` | Compile shim / partial | App-facing imports and the currently used prompt, USB, accessibility, and service-management calls compile. | These modules do not clone complete device, process, service, or legacy Carbon APIs. |
| `Alamofire`, `OllamaKit`, `KeychainSwift`, `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, and `Sparkle` | Partial to usable | `Alamofire` now covers scoped GET/POST request creation, URLSession transport, status validation, and JSON decoding. Enchanted uses `OllamaKit` for model and streaming-chat contracts. `KeychainSwift` covers strings, data, bools, prefixes, and deletion. Markdown/code highlighting, keyboard shortcut, updater, hotkey, and UI-helper shims cover the current app surfaces. | These are scoped compatibility surfaces, not drop-in upstream replacements for all features. |

### Cloned Module Coverage Checklist

This table maps the cloned or shimmed products in `Package.swift` to the
current compatibility level. It is intentionally grouped by API family so gaps
are easier to scan than the raw product list.

| Module group | Products covered | Compatibility checkpoint |
| --- | --- | --- |
| SwiftUI portability core | `SwiftUI`, `QuillUI`, `QuillUIGtk`, `QuillUIQt`, `QuillShims` | Apple-native on Apple; Linux app source compiles through SwiftOpenUI compatibility plus GTK/Qt backend products. Backend rendering remains incremental and app-matrix driven. |
| Data and persistence | `SwiftData`, `QuillData` | Usable for Enchanted conversation storage and source-lowered model tests; not a complete Apple SwiftData clone. |
| Desktop and mobile UI kits | `AppKit`, `QuillAppKitGTK`, `UIKit` | AppKit-shaped desktop APIs are partial and source-tested. UIKit is primarily an import/type compatibility layer for current ports. |
| Foundation, drawing, identity, and security | `QuillFoundation`, `QuillRS`, `CoreGraphics`, `Security`, `UniformTypeIdentifiers` | Common app-facing helpers, image/type/security aliases, and source contracts compile; many APIs are focused shims. |
| Web, network, and extensions | `QuillWebKit`, `Network`, `NetworkExtension` | Web/network imports and selected types compile. Network address parsing, address constants/properties, scoped and unscoped endpoint host address/name parsing/debug/equality/hash behavior, port construction with seeded fuzz coverage plus equality/hash semantics, well-known port constants, path status/reason/type string/equality/hash semantics, and `NWEndpoint` host-port/service/Unix path descriptions/debug/equality/hash behavior are parity-tested for current Apple-observed value behavior; real web rendering, VPN tunnels, system extensions, DNS/TLS/TCP/UDP behavior, connections, listeners, and network monitoring are not implemented. |
| Media, sharing, browser, and mobile services | `AVFoundation`, `Speech`, `PhotosUI`, `MessageUI`, `SafariServices`, `MobileCoreServices` | Service-shaped APIs compile or fallback for app source compatibility. Real device/media/service behavior is mostly absent. |
| Reactive, logging, async, and system kits | `Combine`, `os`, `AsyncAlgorithms`, `Carbon`, `IOKit`, `ApplicationServices`, `ServiceManagement` | Combine and logging have focused tests; the rest are partial or compile shims for app-facing calls. |
| Network/client third-party packages | `Alamofire`, `OllamaKit` | `OllamaKit` covers Enchanted model listing and streaming-chat contracts. `Alamofire` covers current GET/POST, status-validation, and decodable-response needs, but not the full upstream client surface. |
| UI third-party packages | `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, `Sparkle` | Enough API shape exists for markdown/code, loading, wrapping layout, effects, shortcuts, hotkeys, and updater surfaces used by the app shells. |
| Storage and keychain third-party packages | `KeychainSwift` | String/data/bool storage, prefixes, reads, writes, and deletion are tested for current app expectations. |

### App Target Progress

App progress is tracked per target and per backend. Enchanted remains the
highest-priority parity target; GTK and Qt are each compared against the native
macOS app rather than against each other.

| App target | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `quill-enchanted` | Highest-priority usable target | GTK and Qt launch paths share the macOS-shaped app scene. Tests cover Ollama model discovery, streaming chat chunks, local QuillData and legacy SQLite conversation history, markdown fallback rendering, image attachments, AppStorage, prompt catalog behavior, selection/list interaction, shell copy, icon contracts, and Qt graph isolation from GTK. | Full pixel and performance parity with the native macOS app is still in progress. Unsupported SwiftUI modifiers may still degrade through diagnostics. |
| `quill-enchanted-upstream-slice` | Partial | Carries a focused upstream-source slice through the backend product matrix for regression coverage. | It is not the complete upstream Enchanted app. |
| `quill-wireguard` | Usable presentation/import target | GTK/default and native Qt launch targets share `QuillWireGuardCore` presentation snapshots. Tests cover wg-quick import/export, parse errors, import-paste/import-file/invalid import modes, backend availability, native Qt style keys, and manifest graph selection. | Real tunnel activation, NetworkExtension lifecycle, system VPN permissions, and live platform service integration are not cloned. |
| `quill-signal` | Partial chat shell | Uses `QuillChatKit` for sidebar/message presentation, fixture data, and GTK/Qt list-selection smoke rows. | Signal protocol, account setup, encryption, network sync, calls, media, and notification parity are out of scope so far. |
| `quill-telegram` | Partial chat shell | Folder filters, fixture chats/messages, `QuillChatKit` summaries, routing, initial selection, and backend matrix coverage are tested. | Telegram protocol, account auth, network sync, media, calls, and full upstream UI parity are not implemented. |
| `quill-icecubes` | Partial Mastodon reader shell | Covers Mastodon HTML decoding, account/status fixtures, timeline endpoint/query construction, profile projection, timeline rows, and backend launch matrix coverage. | Full Ice Cubes auth, live timeline sync, posting, media, notifications, and all upstream screens are incomplete. |
| `quill-netnewswire` | Partial reader shell | Core/feed logic and Linux backend product coverage exist for the current shell. | Full NetNewsWire feed database behavior, syncing, article rendering, account providers, and upstream UI parity are incomplete. |
| `quill-codeedit` | Partial editor shell | Fixture projects, file extension icons, stable file IDs, non-empty sample contents, initial selection, and backend product coverage are tested. | Full editor behavior, LSP, search, Git integration, project indexing, tabs, and CodeEdit UI parity are incomplete. |
| `quill-iina` | Partial media-player shell | Core test coverage and backend product matrix coverage keep the target compiling and launching through the same parity tooling. | Real mpv/AV playback, timeline controls, subtitle/audio handling, media library behavior, and full IINA UI parity are not implemented. |
| `quill-chat-linux` | Optional generated external app | Generated external app coverage is included when the local Quill Chat checkout is available. | It is not a required package target and depends on the external checkout being present. |

Current tooling checkpoint:

- `scripts/quillui-backend-products.sh`: canonical app, generated-app, smoke, and profile rosters for GTK/Qt parity loops.
- `scripts/run-linux-backend-smoke-matrix.sh`: shared visual/interaction matrix runner so local and CI GTK/Qt smoke rows stay identical.
- `scripts/linux-backend-check.sh`: guarded aggregate check for the current Linux backend matrix.

## Run

On macOS:

```sh
swift run quill-enchanted
```

On Linux with backend smoke dependencies installed:

```sh
curl -O "https://download.swift.org/swiftly/linux/swiftly-1.1.1-$(uname -m).tar.gz"
tar -zxf "swiftly-1.1.1-$(uname -m).tar.gz"
./swiftly init
sudo apt-get update
sudo apt-get install -y git imagemagick libgdk-pixbuf-2.0-dev libgtk-4-dev libsqlite3-dev pkg-config x11-apps xdotool xvfb
swift run quill-enchanted
QUILLUI_LINUX_BACKEND=gtk swift run quill-signal
sudo apt-get install -y qt6-base-dev
QUILLUI_LINUX_BACKEND=qt swift run quill-signal
QUILLUI_LINUX_BACKEND=qt swift run quill-wireguard
```

You also need an Ollama server reachable at `http://localhost:11434` or the endpoint configured in the app.

Backend parity checks:

```sh
scripts/quillui-backend-products.sh app-matrix
scripts/run-linux-backend-smoke-matrix.sh --dry-run visual app-matrix '.qa/{product}-{backend}.png'
scripts/run-linux-backend-smoke-matrix.sh --dry-run interaction interaction-matrix '.qa/{product}-interaction-{backend}.png'
scripts/run-linux-backend-smoke-matrix.sh --dry-run interaction interaction-extra-mode-matrix '.qa/{product}-{mode}-{backend}.png'
scripts/linux-backend-check.sh
```
