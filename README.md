# QuillUI

QuillUI is an open-source Swift UI portability layer for bringing
SwiftUI-shaped app code to Linux desktops while keeping the same app scenes
usable on Apple platforms.

## Start Here

- **Function-by-function Apple package coverage:** [docs/apple-package-function-coverage.md](docs/apple-package-function-coverage.md) is the linked source of truth for complete vs incomplete APIs in each cloned Apple package and each app target. Start there for SwiftUI, SwiftData, AppKit/UIKit, Network, media/service kits, system kits, third-party package clones, and app progress.
- **Network parity pocket:** [Network function rows](docs/apple-package-function-coverage.md#network) list the narrow API rows currently at `Parity`; path monitor initial state, pre-start cancellation, path support/interface helper queries, scoped service endpoint descriptions, associated interface values, `NWError.posix`/`.dns`/`.tls` value text, `NWProtocolTCP.Options`/`NWProtocolUDP.Options` default and setter behavior, `NWProtocolOptions`, `NWParameters.defaultProtocolStack`, `NWParameters.ProtocolStack`, `NWProtocolIP.Options`, IP option enum value surfaces, and `NWParameters` policy enum/default/setter/debug text are now pinned there, while broader transport, DNS, TLS, connection, listener, VPN, live monitoring, and IP packet/socket effects are still incomplete.
- **Security and Signal key-material coverage:** [Security rows](docs/apple-package-function-coverage.md#security), [KeychainSwift rows](docs/apple-package-function-coverage.md#keychainswift), and [Signal app progress](docs/apple-package-function-coverage.md#app-progress-summary) track `SecKey`, `SecItem`, `KeychainSwift`, and Signal/libsignal-facing compatibility, including which rows are deterministic source-compatibility shims versus production-grade crypto.
- **App progress:** [App progress summary](docs/apple-package-function-coverage.md#app-progress-summary) and [docs/app-targets.md](docs/app-targets.md) track target-by-target status.

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

Function coverage index:

- [Network](docs/apple-package-function-coverage.md#network): the current first
  parity pocket, including path monitor initial/pre-start-cancel state,
  path/interface value semantics, endpoint/host/address/port value behavior,
  `NWError` constructor/equality/debug/localized text behavior,
  `NWProtocolOptions`, `NWParameters.defaultProtocolStack`,
  `NWParameters.ProtocolStack`, `NWProtocolIP.Options`, IP option enum value
  surfaces, `NWParameters` factory/initializer text plus
  policy enum/default/setter/debug behavior, and Apple-checked
  protocol-surface conformance rows.
- [SwiftUI](docs/apple-package-function-coverage.md#swiftui),
  [SwiftData](docs/apple-package-function-coverage.md#swiftdata),
  [AppKit](docs/apple-package-function-coverage.md#appkit), and
  [UIKit](docs/apple-package-function-coverage.md#uikit): primary Apple UI and
  model package clone ledgers.
- [WebKit](docs/apple-package-function-coverage.md#webkit),
  [AuthenticationServices](docs/apple-package-function-coverage.md#authenticationservices),
  [UniformTypeIdentifiers](docs/apple-package-function-coverage.md#uniformtypeidentifiers),
  [NetworkExtension](docs/apple-package-function-coverage.md#networkextension),
  [AVFoundation](docs/apple-package-function-coverage.md#avfoundation),
  [AVKit](docs/apple-package-function-coverage.md#avkit),
  [Speech](docs/apple-package-function-coverage.md#speech),
  [PhotosUI and Photos](docs/apple-package-function-coverage.md#photosui-and-photos),
  [Charts](docs/apple-package-function-coverage.md#charts),
  [StoreKit](docs/apple-package-function-coverage.md#storekit), and
  [TipKit](docs/apple-package-function-coverage.md#tipkit): web, network
  extension, media, and service kit ledgers.
- [CoreGraphics](docs/apple-package-function-coverage.md#coregraphics),
  [Security](docs/apple-package-function-coverage.md#security),
  [Observation](docs/apple-package-function-coverage.md#observation),
  [ApplicationServices](docs/apple-package-function-coverage.md#applicationservices),
  [ServiceManagement](docs/apple-package-function-coverage.md#servicemanagement),
  [AsyncAlgorithms](docs/apple-package-function-coverage.md#asyncalgorithms),
  [Carbon](docs/apple-package-function-coverage.md#carbon),
  [Combine](docs/apple-package-function-coverage.md#combine),
  [os](docs/apple-package-function-coverage.md#os), and
  [IOKit](docs/apple-package-function-coverage.md#iokit): system and support
  package clone ledgers.
- [Re-export-only Apple shims](docs/apple-package-function-coverage.md#re-export-only-apple-shims),
  [third-party and app-support package clones](docs/apple-package-function-coverage.md#third-party-and-app-support-package-clones),
  and [app progress](docs/apple-package-function-coverage.md#app-progress-summary):
  compatibility-only shims, package clone progress, and app target status.

- [Network function coverage](docs/apple-package-function-coverage.md#network): current
  Network rows that have reached Apple/Linux parity. The path monitor initial
  state and pre-start cancellation rows, path/interface enum rows, and scoped-interface value rows are pinned by
  `NetworkPathInterfaceParityTests` for string, name/type, equality, and hash
  semantics; the address rows are backed by Apple-observed
  IPv4/IPv6 parser, data initializer, classifier-boundary, multicast-scope,
  IPv4 mapping, string, debug-output, equality, and hash tests, including
  `IPv4Address.init?(String)` legacy single-value wrapping and dotted-field
  octal/hex edge cases; the endpoint rows cover scoped and unscoped host parsing,
  direct-value equality/hash coherence, port
  parser/constant/equality/hash semantics, host-port/service/Unix endpoint
  value behavior including scoped service interface suffixes, and
  `NWError.posix`, `.dns`, and `.tls` equality, Sendable, debug text, Apple
  localized error formatting, and common Darwin POSIX network failure payloads;
  TCP/UDP protocol option defaults and setters; and
  `NWParameters` policy enums, defaults, setter normalization, local endpoint
  debug formatting, and traffic, multipath, proxy, and DNSSEC debug segments are
  pinned by shared Apple/Linux tests.
- [API coverage matrix](docs/api-coverage-matrix.md): backend and app-facing API evidence.
- [App targets](docs/app-targets.md): target-by-target app progress.

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
That ledger is the source of truth for per-function `Parity`, `Usable`, and
incomplete rows across Apple package clones such as `Network` and `Security`.
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
| Web, network, media, and service Apple kits | Selected compile or fallback shapes for `WebKit`, `AuthenticationServices`, `Network`, `NetworkExtension`, `AVFoundation`, `Speech`, `PhotosUI`, `Charts`, `StoreKit`, and `TipKit`; `Network` address parsing, address constants, address classifier properties, scoped IPv4/IPv6/name host interface literals, port parsing with seeded fuzz coverage, port equality/hash semantics, well-known port constants, path monitor initial and pre-start cancel state, path status/reason/type string/equality/hash semantics, endpoint-host classification/equality/hash including scoped parsed-to-direct values, `NWEndpoint` host-port/service/Unix path description/debug/equality/hash value APIs, `NWError.posix`/`.dns`/`.tls` constructor/equality/debug/localized text, and `NWParameters` plus TCP/UDP/TLS option constructor, protocol-stack/IP option value surfaces, policy enum/default/setter, and debug text now have Apple-checked parity rows. | Real web rendering, authentication sessions, DNS/TLS/TCP/UDP behavior, IP packet/socket option effects, VPN tunnels, media I/O, speech, photo library, chart rendering, purchases, and tip persistence. |
| System and support kits | Focused usable rows for `ServiceManagement`, `Security` `SecRandomCopyBytes`, process-local `Security` `SecItem` generic-password, internet-password, and key-class add/copy/update/delete storage with persistent-reference handles, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny` matching, access-control metadata, authentication/use query controls, internet endpoint identity fields, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, process-local `SecKeyCreateWithData`, `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, `SecKeyGetBlockSize`, `SecKeyCopyAttributes`, `SecKeyCopyExternalRepresentation`, metadata-gated `SecKeyIsAlgorithmSupported` checks, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, and synthesized `SecKey` references for key-class `kSecReturnRef` rows, `AsyncAlgorithms`, `AnyPublisher`, and `Logger` initialization. | Full `CoreGraphics`, native secure `Security` keychain persistence/access-control enforcement, OS-enforced keychain sharing, real keychain synchronization, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, Secure Enclave behavior, `Observation`, `ApplicationServices`, `Carbon`, `IOKit`, `os`, and Combine edge-case parity. |
| Re-export-only Apple shims | Imports compile for current app source. | Standalone framework behavior for `MessageUI`, `SafariServices`, `MobileCoreServices`, `LocalAuthentication`, and `CoreSpotlight`. |

### Current Progress Snapshot

| Track | Done now | Still open |
| --- | --- | --- |
| SwiftUI clone | App/scene launch, common view declarations, state wrappers, file-import helpers, menu/picker/list extraction, image helpers, compatibility diagnostics, and many modifier metadata paths compile and are tested against current app sources. | Full SwiftUI layout, accessibility, animation, transitions, gesture semantics, focus routing, multi-window scenes, and pixel-perfect backend rendering are incomplete. |
| Apple kit clones | AppKit, UIKit, SwiftData, Foundation/CoreGraphics/Security, WebKit, Network, media/service frameworks, Combine, `os`, and legacy platform kits expose enough surface for the app targets to compile. Network protocol-stack/IP option value surfaces are now in the Apple-checked Network parity pocket, and `Security` has parity for the valid-count `SecRandomCopyBytes` contract plus a usable process-local `SecItem` generic-password, internet-password, and key-class contract for add/copy/update/delete, persistent-reference handles, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny` matching, access-control metadata, authentication/use query controls, server/protocol/authentication/port/path endpoint identity, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, imported/generated `SecKey` byte/attribute/block-size round-trips, metadata-gated common ECDSA/ECDH/RSA algorithm-support queries, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, process-local `SecKeyCreateRandomKey`/`SecKeyGeneratePair`/`SecKeyCopyPublicKey`, and synthesized key references. | Most kits are scoped app-contract clones, not full framework replacements; real platform services such as native secure keychain persistence/access-control enforcement, OS-enforced keychain sharing, real keychain synchronization, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, Secure Enclave behavior, VPN tunnels, web rendering, media playback/capture, speech, IP packet/socket option effects, and service management remain limited or fallback-only. |
| Third-party package clones | Enchanted and chat/editor/feed shells can compile with scoped clones of packages such as `OllamaKit`, `KeychainSwift`, `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, `Sparkle`, and `Alamofire`. Signal-style key-material work now has lower-level `Security` random-byte generation, process-local imported/generated `SecKey` byte/attribute/block-size round-trips, metadata-gated common ECDSA/ECDH/RSA algorithm-support queries, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, generated private/public key references via `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, and `SecKeyCopyPublicKey`, synthesized key references, and process-local `SecItem` generic-password, internet-password, and key-class storage surfaces, including access-group/synchronizable namespace filters, `kSecAttrSynchronizableAny` matching, access-control metadata, authentication/use query controls, server/protocol/authentication/port/path endpoint separation, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, and persistent keychain handle lookup/delete. `KeychainSwift` now follows upstream-shaped UTF-8 `String`, raw `Data`, single-byte `Bool`, `getData(_:asReference:)`, `allKeys`, prefix/access-group/synchronizable, result-code, and namespace `clear()` semantics for current Signal-style account/key storage code. | Package coverage follows the app ports. APIs not exercised by current targets may be missing or fallback-only, and keychain rows/generated keys/signatures/key-exchange data are not secure OS keychain or native crypto replacements yet. |
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
| `QuillFoundation`, `QuillRS`, `CoreGraphics`, `Security` | Partial | Foundation-like selection helpers, image/color/font/screen aliases, localized string fallback, CoreGraphics image/render helpers, accessibility and security-shaped APIs compile and have focused tests. `Security` now covers Apple-observed valid-count `SecRandomCopyBytes` behavior plus process-local `SecKeyCreateWithData`, `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, `SecKeyGetBlockSize`, `SecKeyCopyAttributes`, `SecKeyCopyExternalRepresentation`, `SecKeyIsAlgorithmSupported`, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, and `SecItemDelete` generic-password, internet-password, and key-class flows, including synthesized `SecKey` references, generated private/public key metadata, metadata-gated common ECDSA/ECDH/RSA algorithm-support checks, persistent-reference returns, lookup, mixed value returns, delete-by-reference, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny` matching, `SecAccessControlCreateWithFlags`, `kSecAttrAccessControl` metadata, `kSecUse*` authentication/use query controls, server/security-domain/protocol/authentication/port/path endpoint identity, and key-item application-tag/application-label/key-class/key-type/key-size/capability metadata. | Many APIs are placeholders or app-contract shims rather than complete framework implementations. `Security` still lacks native secure keychain persistence, access-control enforcement, OS-enforced keychain sharing, real synchronization, cross-process lookup, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, Secure Enclave behavior, and production trust evaluation. |
| `QuillWebKit` / `WebKit` | Compile shim | `WKWebView`-shaped configuration, load, evaluate, and delegate APIs are available for source compatibility. | No full embedded web engine, JavaScript runtime, navigation stack, process model, or rendering parity exists yet. |
| `Network` and `NetworkExtension` | Partial overall; selected `Network` functions at Parity | Imports and app-facing types compile for ports such as WireGuard. `IPv4Address` and `IPv6Address` parsing, constants, data initializer lengths, classifier boundary behavior, multicast scope, IPv4 mapping, scoped interface literals, string/debug text, address equality/hash behavior, and absence of Linux-only public address classifiers are now covered by Apple-observed parity tests. `NWPathMonitor` initial `currentPath` and pre-start `cancel()` state, `NWPath` support/interface helper queries, `NWPath.Status`, `NWPath.UnsatisfiedReason`, `NWInterface.InterfaceType`, `NWInterface` values returned by scoped address/host parsing, `NWEndpoint.Port` parsing/known constants/debug text/equality/hash behavior with seeded fuzz coverage, and the `NWEndpoint.Host.init(_:)` classification/description/equality/hash contract for current scoped and unscoped edge cases now match Apple-observed behavior, including scoped parsed-to-direct equality and scoped-vs-unscoped inequality. `NWPathMonitor.start(queue:)` now provides a usable Linux one-shot snapshot of currently-up IPv4/IPv6 interfaces and required interface filters. `NWEndpoint.hostPort`, `.service`, and `.unix` description/debug/equality/hash behavior now covers Apple-observed DNS-SD service-name escaping, `_tcp`/`_udp` type formatting, empty-name/domain cases, invalid-type concatenation, leading/internal domain dot behavior, exact endpoint equality, scoped host-port equality, and hash coherence. `NWError.posix`, `.dns`, `.tls`, equality, debug/describing/reflecting text, and localized error formatting now have Apple-checked value-surface parity. `NWProtocolTCP.Options`, including its Apple-observed Bool and Int option defaults/setters, `NWProtocolUDP.Options.preferNoChecksum`, `NWProtocolTLS.Options`, `NWParameters.tcp`, `.udp`, `.tls`, `.dtls`, `init(tls:tcp:)`, `init(dtls:udp:)`, and `NWParameters` debug/string text now have Apple-checked constructor/value-surface parity. `NWParameters.Attribution`, `ExpiredDNSBehavior`, `MultipathServiceType`, `ServiceClass`, required/prohibited interface policies, required local endpoint, local endpoint reuse, peer-to-peer, service class, multipath, expired DNS, fast open, expensive/constrained path, DNSSEC, proxy preference, attribution setters, and the resulting debug text now have Apple-checked policy-surface parity. | Real VPN control, tunnel lifecycle, system extension behavior, DNS/TLS/TCP/UDP behavior, connections, listeners, continuous live path monitoring, exact Apple path/DNS policy flags, and synthetic constructed interfaces are not implemented. |
| `AVFoundation`, `Speech`, `PhotosUI`, `MessageUI`, `SafariServices`, `MobileCoreServices` | Compile shim / fallback | Service-shaped modules compile and record diagnostic fallback behavior where applicable. | They do not provide real media capture/playback, speech recognition, photo picker, mail compose, browser, or mobile type services. |
| `Combine` | Partial | Publishers, subjects, merge, timers, notifications, cancellation, completion, and `AnyCancellable` contracts are tested. | The full Combine operator surface, scheduler semantics, and backpressure behavior are incomplete. |
| `os` | Partial | `Logger` and privacy diagnostic rendering are tested. | It is not Apple's unified logging system. |
| `AsyncAlgorithms`, `Carbon`, `IOKit`, `ApplicationServices`, `ServiceManagement` | Compile shim / partial | App-facing imports and the currently used prompt, USB, accessibility, and service-management calls compile. | These modules do not clone complete device, process, service, or legacy Carbon APIs. |
| `Alamofire`, `OllamaKit`, `KeychainSwift`, `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, and `Sparkle` | Partial to usable | `Alamofire` now covers scoped GET/POST request creation, URLSession transport, status validation, and JSON decoding. Enchanted uses `OllamaKit` for model and streaming-chat contracts. `KeychainSwift` covers upstream-shaped UTF-8 string bytes, raw data bytes, single-byte bools, `getData(_:asReference:)`, `allKeys`, prefix isolation, namespace clear behavior, deletion, and result-code tracking, and the lower-level `Security` shim covers `SecRandomCopyBytes` for Signal-shaped key generation, imported and generated `SecKey` byte/attribute/block-size round-trips, metadata-gated common ECDSA/ECDH/RSA algorithm-support checks, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, process-local `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, synthesized key references, and process-local `SecItem` generic-password, internet-password, and key-class add/copy/update/delete rows, access-group/synchronizable namespace filters, `kSecAttrSynchronizableAny` matching, access-control metadata, authentication/use query controls, server/protocol/authentication/port/path endpoint separation, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, and persistent-reference handles for storage. Markdown/code highlighting, keyboard shortcut, updater, hotkey, and UI-helper shims cover the current app surfaces. | These are scoped compatibility surfaces, not drop-in upstream replacements for all features. Keychain-compatible rows are process-local and do not provide secure OS persistence, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, or Secure Enclave behavior yet. |

### Cloned Module Coverage Checklist

This table maps the cloned or shimmed products in `Package.swift` to the
current compatibility level. It is intentionally grouped by API family so gaps
are easier to scan than the raw product list.

| Module group | Products covered | Compatibility checkpoint |
| --- | --- | --- |
| SwiftUI portability core | `SwiftUI`, `QuillUI`, `QuillUIGtk`, `QuillUIQt`, `QuillShims` | Apple-native on Apple; Linux app source compiles through SwiftOpenUI compatibility plus GTK/Qt backend products. Backend rendering remains incremental and app-matrix driven. |
| Data and persistence | `SwiftData`, `QuillData` | Usable for Enchanted conversation storage and source-lowered model tests; not a complete Apple SwiftData clone. |
| Desktop and mobile UI kits | `AppKit`, `QuillAppKitGTK`, `UIKit` | AppKit-shaped desktop APIs are partial and source-tested. UIKit is primarily an import/type compatibility layer for current ports. |
| Foundation, drawing, identity, and security | `QuillFoundation`, `QuillRS`, `CoreGraphics`, `Security`, `UniformTypeIdentifiers` | Common app-facing helpers, image/type/security aliases, and source contracts compile; many APIs are focused shims. `Security` includes `SecRandomCopyBytes` parity for valid-count random fills, process-local `SecKeyCreateWithData`, `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, `SecKeyGetBlockSize`, `SecKeyCopyAttributes`, `SecKeyCopyExternalRepresentation`, `SecKeyIsAlgorithmSupported`, `SecKeyCreateSignature`, `SecKeyVerifySignature`, `SecKeyCopyKeyExchangeResult`, key-exchange parameter constants, imported/generated `SecKey` byte/attribute/block-size round-trips, metadata-gated common ECDSA/ECDH/RSA algorithm-support checks, deterministic ECDSA message/digest signing/verification, deterministic symmetric ECDH key-exchange material, synthesized `SecKey` references, and a process-local `SecItem` generic-password, internet-password, and key-class contract for add, copy, update, delete, duplicate, not-found, attributes, data, persistent-reference, access-group filters, synchronizable filters, `kSecAttrSynchronizableAny`, access-control metadata, authentication/use query controls, server/protocol/authentication/port/path endpoint identity, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, and match-all rows; native secure persistence/access-control enforcement/OS-enforced sharing/real synchronization/cross-process keychain behavior, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, and Secure Enclave behavior are not cloned. |
| Web, network, and extensions | `QuillWebKit`, `Network`, `NetworkExtension` | Web/network imports and selected types compile. Network address parsing, address constants/properties, address equality/hash behavior, scoped and unscoped endpoint host address/name parsing/debug/equality/hash behavior, port construction with seeded fuzz coverage plus equality/hash semantics, well-known port constants, path monitor initial and pre-start cancel state, path support/interface helper queries, path status/reason/type string/equality/hash semantics, `NWEndpoint` host-port/service/Unix path descriptions/debug/equality/hash behavior, `NWError.posix`/`.dns`/`.tls` constructor/equality/debug/localized text behavior, `NWProtocolOptions`, `NWParameters.defaultProtocolStack`, `NWParameters.ProtocolStack`, `NWProtocolIP.Options`, IP option enum value behavior, and `NWParameters` plus TCP/UDP/TLS option constructor/value/policy text are parity-tested for current Apple-observed value behavior. `NWPathMonitor.start(queue:)` is usable for a Linux one-shot current-interface snapshot; real web rendering, VPN tunnels, system extensions, DNS/TLS/TCP/UDP behavior, IP packet/socket option effects, connections, listeners, and continuous network monitoring are not implemented. |
| Media, sharing, browser, and mobile services | `AVFoundation`, `Speech`, `PhotosUI`, `MessageUI`, `SafariServices`, `MobileCoreServices` | Service-shaped APIs compile or fallback for app source compatibility. Real device/media/service behavior is mostly absent. |
| Reactive, logging, async, and system kits | `Combine`, `os`, `AsyncAlgorithms`, `Carbon`, `IOKit`, `ApplicationServices`, `ServiceManagement` | Combine and logging have focused tests; the rest are partial or compile shims for app-facing calls. |
| Network/client third-party packages | `Alamofire`, `OllamaKit` | `OllamaKit` covers Enchanted model listing and streaming-chat contracts. `Alamofire` covers current GET/POST, status-validation, and decodable-response needs, but not the full upstream client surface. |
| UI third-party packages | `MarkdownUI`, `Splash`, `ActivityIndicatorView`, `WrappingHStack`, `Vortex`, `KeyboardShortcuts`, `Magnet`, `Sparkle` | Enough API shape exists for markdown/code, loading, wrapping layout, effects, shortcuts, hotkeys, and updater surfaces used by the app shells. |
| Storage and keychain packages | `Security`, `KeychainSwift` | `Security` `SecRandomCopyBytes` covers Apple-observed valid-count random fills for Signal-style key generation, while `SecKeyCreateWithData`, `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, `SecKeyGetBlockSize`, `SecKeyCopyAttributes`, `SecKeyCopyExternalRepresentation`, `SecKeyIsAlgorithmSupported`, `SecKeyCreateSignature`, `SecKeyVerifySignature`, `SecKeyCopyKeyExchangeResult`, key-exchange parameter constants, generated private/public metadata, metadata-gated common ECDSA/ECDH/RSA algorithm-support checks, deterministic ECDSA message/digest sign/verify, deterministic symmetric ECDH key-exchange material, and synthesized `SecKey` references cover process-local imported/generated key round-trips. `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, and `SecItemDelete` cover process-local generic-password, internet-password, and key-class storage with duplicate/not-found status, returned attributes/data, object references, persistent-reference returns, lookup, mixed value returns, delete-by-reference, access-control metadata, authentication/use query controls, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny`, server/protocol/authentication/port/path endpoint filters, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, and match-all queries. `KeychainSwift` covers upstream-shaped UTF-8 string, raw data, single-byte bool, `getData(_:asReference:)`, deterministic reference handle, `allKeys`, prefix/access-group/synchronizable namespace, delete, clear, and result-code behavior for current app expectations. |

### App Target Progress

App progress is tracked per target and per backend. Enchanted remains the
highest-priority parity target; GTK and Qt are each compared against the native
macOS app rather than against each other.

| App target | Status | Compatible today | Not compatible yet |
| --- | --- | --- | --- |
| `quill-enchanted` | Highest-priority usable target | GTK and Qt launch paths share the macOS-shaped app scene. Tests cover Ollama model discovery, streaming chat chunks, local QuillData and legacy SQLite conversation history, markdown fallback rendering, image attachments, AppStorage, prompt catalog behavior, selection/list interaction, shell copy, icon contracts, and Qt graph isolation from GTK. | Full pixel and performance parity with the native macOS app is still in progress. Unsupported SwiftUI modifiers may still degrade through diagnostics. |
| `quill-enchanted-upstream-slice` | Partial | Carries a focused upstream-source slice through the backend product matrix for regression coverage. | It is not the complete upstream Enchanted app. |
| `quill-wireguard` | Usable presentation/import target | GTK/default and native Qt launch targets share `QuillWireGuardCore` presentation snapshots. Tests cover wg-quick import/export, parse errors, import-paste/import-file/invalid import modes, backend availability, native Qt style keys, and manifest graph selection. | Real tunnel activation, NetworkExtension lifecycle, system VPN permissions, and live platform service integration are not cloned. |
| `quill-signal` | Partial chat shell | Uses `QuillChatKit` for sidebar/message presentation, fixture data, and GTK/Qt list-selection smoke rows. The lower-level `Security` shim now has Apple-observed `SecRandomCopyBytes` valid-count behavior, process-local `SecKeyCreateWithData`, `SecKeyCreateRandomKey`, `SecKeyGeneratePair`, `SecKeyCopyPublicKey`, `SecKeyGetBlockSize`, attribute/external-representation round-trips, metadata-gated common ECDSA/ECDH/RSA algorithm-support queries, deterministic ECDSA message/digest `SecKeyCreateSignature` and `SecKeyVerifySignature` compatibility, deterministic symmetric ECDH `SecKeyCopyKeyExchangeResult` compatibility with requested-size/shared-info parameters, synthesized `SecKey` references for stored and generated key rows, and a process-local `SecItem` generic-password, internet-password, and key-class contract with access-control metadata, authentication/use query controls, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny`, server/protocol/authentication/port/path endpoint filters, key-item application-tag/application-label/key-class/key-type/key-size/capability metadata, and persistent-reference handles suitable for source-targeting future key-material and account-storage flows on Linux. `KeychainSwift` now also has upstream-shaped byte storage, reference reads, `allKeys`, and prefix/access-group/synchronizable semantics for Signal-style account/key storage code. | Signal protocol, account setup, encryption, native secure keychain persistence/access-control enforcement, OS-enforced keychain sharing, real synchronization, native key validation/handles, native cryptographic key generation, cryptographically valid sign/verify, native/cryptographically valid key agreement, Secure Enclave behavior, network sync, calls, media, and notification parity are out of scope so far. |
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
