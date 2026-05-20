# QuillUI

QuillUI is an open-source Swift UI portability layer for bringing
SwiftUI-shaped app code to Linux desktops while keeping the same app scenes
usable on Apple platforms.

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

## Compatibility Progress

Status terms:

- `Apple-native`: QuillUI defers to the real Apple framework on Apple platforms.
- `Usable`: covered by source or smoke tests and exercised by at least one app target.
- `Partial`: enough API shape exists for current app ports, but framework behavior is incomplete.
- `Compile shim`: imports, types, and selected calls compile, with little or no runtime behavior.
- `Fallback`: the API intentionally degrades and usually records compatibility diagnostics.

### API-by-API SwiftUI Clone Progress

These rows track the SwiftUI-shaped API families QuillUI currently clones or
adapts. `Compatible today` means app source can compile and the preserved
metadata or runtime behavior is visible to the Linux backends and tests.

| API area | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `QuillUI` / `SwiftUI` module boundary | Apple-native on Apple, usable on Linux | Re-exports real SwiftUI on Apple platforms. Linux builds use SwiftOpenUI plus `QuillSwiftUICompatibility`, with `QuillUIGtk` and `QuillUIQt` sharing the same app scene contracts. | Not a complete SwiftUI replacement; compatibility is driven by the app matrix and source-contract tests. |
| App, scene, and backend launch | Usable | Canonical app products launch through `QUILLUI_BACKEND` at runtime and `QUILLUI_LINUX_BACKEND=gtk|qt` at build time. GTK and Qt products are tracked by `scripts/quillui-backend-products.sh app-matrix`. | Only the app/window patterns used by current ports are covered. Advanced SwiftUI scene types and multi-window behavior are still limited. |
| Core views, layout, controls, and modifiers | Partial | The current ports compile common `Text`, `Image`, `Button`, `Form`, picker, menu, list/sidebar, navigation, toolbar, and prompt-shaped code paths. Menu extraction, picker option extraction, confirmation dialogs, and text-label helpers are source-tested. | SwiftUI's full layout engine, animation model, gestures, accessibility tree, and many advanced modifiers are not visually identical yet. |
| State, environment, and storage | Partial | `@AppStorage` scalar and raw-enum persistence, bindings, `FocusState`, `Namespace`, `PresentationMode`, `OpenURLAction`, sidebar navigation actions, and prompt helpers have compatibility tests. | Full SwiftUI environment propagation, scene storage, focus routing, transaction semantics, and property-wrapper coverage remain incomplete. |
| Symbols, images, and rendering | Partial | SF-symbol style names map through `quillSystemImageName`, `Image(data:)` deduplicates payloads, PNG/TIFF/JPEG image round trips are tested through gdk-pixbuf, Linux `PlatformImage` can scale valid bitmap bytes by height and recompress them to JPEG, and `ImageRenderer` can render supported color payloads. | General SwiftUI view rendering to images, full symbol fidelity, animated images, metadata/color-profile preservation, and every platform image format are not complete. |
| File import, item providers, and type identifiers | Partial | `QuillFileImporter`, `NSItemProvider`, and `UniformTypeIdentifiers` cover the app-facing extension and conformance checks used by current ports. | Full file promises, drag/drop provider behavior, sandbox security-scoped resources, and system type database parity are not implemented. |
| Diagnostics and unsupported modifiers | Usable fallback | Unsupported fallbacks such as `symbolEffect`, `matchedGeometryEffect`, `Image.renderingMode`, and `Form.formStyle` record `QuillCompatibilityDiagnostics`; shape masks compile as a `clipShape` approximation, while generic view masks preserve content and mask metadata. `symbolRenderingMode`, keyboard/text-entry modifiers plus generic `View.imageScale`, `minimumScaleFactor`, `textSelection`, `listRowInsets`, `listRowSeparator`, `scrollIndicators`, `scrollContentBackground`, `contentShape`, `allowsHitTesting`, `gesture`, `onHover`, `focusEffectDisabled`, `edgesIgnoringSafeArea`, and `ignoresSafeArea` now preserve metadata for backend rendering/layout/input/focus work. | These APIs may compile without changing visuals or behavior until a backend implementation is added. |
| Third-party SwiftUI package shapes | Partial | Compatibility shims exist for `ActivityIndicatorView`, `MarkdownUI`, `Splash`, `WrappingHStack`, `Vortex`, and `KeyboardShortcuts`; the tests verify the app-facing contracts. | These are not full upstream package clones, and visual fidelity is limited to the features currently exercised by app targets. |
| GTK and Qt backends | Usable | `QuillUIGtk` and `QuillUIQt` keep separate dependency graphs. Qt builds require Qt6 Widgets and avoid loading the GTK graph. Shared smoke/profile tooling keeps visual and interaction rows aligned. | Pixel-perfect macOS parity and performance parity are still tracked incrementally per app and per backend. |

### API-by-API Kit Clone Progress

These rows cover the Apple framework and third-party package surfaces that have
been cloned far enough for current QuillUI app targets.

| Kit or package | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `AppKit` / `QuillAppKit` | Partial | Pasteboard items, images, workspace icons, menus, controls, popups, popovers, toolbars, windows, sheets, tabs, view hierarchy, frames, bounds, display/layout calls, hit testing, coordinate conversion, responders, event monitors, view controllers, split views, tracking areas, text views, table views, outline views, documents, and undo are source-tested. | This is not full AppKit. Auto Layout, CALayer, accessibility, drawing, menu validation, document lifecycle, and platform window-manager behavior need more work. |
| `QuillAppKitGTK` | Usable | Provides GTK-side AppKit bridge pieces and smoke targets used by backend parity checks. | GTK behavior is not a reference for Qt; both still need independent comparison against native macOS behavior. |
| `UIKit` / `QuillUIKit` | Compile shim to partial | Linux app ports can import UIKit-shaped types such as views, view controllers, colors, fonts, screens, table/collection/navigation/split containers, responders, constraints, and pasteboard support. | There is no full UIKit renderer or mobile event, layout, animation, accessibility, or lifecycle parity. |
| `SwiftData` / `QuillData` | Partial and usable | `@QuillModel`, model containers, model contexts, fetch descriptors, predicates, sort descriptors, SQLite/GRDB persistence, source lowering, predicate fuzzing, and Enchanted conversation storage are tested. | Apple SwiftData migrations, CloudKit integration, complete relationship semantics, observation behavior, and concurrency rules are not fully cloned. |
| `UniformTypeIdentifiers` | Partial | File-extension lookup, conformance checks, and app-facing item-provider flows are covered by compatibility tests. | It is not Apple's complete type database or LaunchServices-backed identifier system. |
| `QuillFoundation`, `QuillRS`, `CoreGraphics`, `Security` | Partial | Foundation-like selection helpers, image/color/font/screen aliases, localized string fallback, CoreGraphics image/render helpers, accessibility and security-shaped APIs compile and have focused tests. | Many APIs are placeholders or app-contract shims rather than complete framework implementations. |
| `QuillWebKit` / `WebKit` | Compile shim | `WKWebView`-shaped configuration, load, evaluate, and delegate APIs are available for source compatibility. | No full embedded web engine, JavaScript runtime, navigation stack, process model, or rendering parity exists yet. |
| `Network` and `NetworkExtension` | Compile shim | Imports and app-facing types compile for ports such as WireGuard. | Real VPN control, tunnel lifecycle, system extension behavior, and network monitoring are not implemented. |
| `AVFoundation`, `Speech`, `PhotosUI`, `MessageUI`, `SafariServices`, `MobileCoreServices` | Compile shim / fallback | Service-shaped modules compile and record diagnostic fallback behavior where applicable. | They do not provide real media capture/playback, speech recognition, photo picker, mail compose, browser, or mobile type services. |
| `Combine` | Partial | Publishers, subjects, merge, timers, notifications, cancellation, completion, and `AnyCancellable` contracts are tested. | The full Combine operator surface, scheduler semantics, and backpressure behavior are incomplete. |
| `os` | Partial | `Logger` and privacy diagnostic rendering are tested. | It is not Apple's unified logging system. |
| `AsyncAlgorithms`, `Carbon`, `IOKit`, `ApplicationServices`, `ServiceManagement` | Compile shim / partial | App-facing imports and the currently used prompt, USB, accessibility, and service-management calls compile. | These modules do not clone complete device, process, service, or legacy Carbon APIs. |
| `Alamofire`, `OllamaKit`, `KeychainSwift`, `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, and `Sparkle` | Partial to usable | Enchanted uses `OllamaKit` for model and streaming-chat contracts. `KeychainSwift` covers strings, data, bools, prefixes, and deletion. Markdown/code highlighting, keyboard shortcut, updater, hotkey, and UI-helper shims cover the current app surfaces. | These are scoped compatibility surfaces, not drop-in upstream replacements for all features. |

### App Target Progress

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
