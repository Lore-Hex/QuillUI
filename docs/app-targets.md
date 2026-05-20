# QuillUI App Targets

QuillUI should prove itself against real open-source Swift apps that stress different parts of the Apple stack.

## 1. Enchanted

Status: active first port. Compile-green hard-gated on macOS CI; full upstream gluonfield/enchanted source tree compiles + links + backend-renders end-to-end on Linux via the QuillUI / SwiftOpenUI / QuillFoundation / QuillAppKit / QuillDataMacros + 22-shim compatibility layer (CP80). Enchanted's canonical Qt row now compiles through the explicit Qt manifest graph and dedicated Enchanted Qt native host while the full SwiftUI tree remains on the GTK path.

Why it matters:

- Chat app surface with sidebar, message list, composer, image attachments, model picker, and streaming network state.
- Good forcing function for SwiftUI compatibility, local persistence, Markdown rendering, async tasks, and Linux desktop polish.

Current approach:

- Build a reusable `QuillUI` facade and `QuillData` persistence layer while keeping app-specific changes small.
- Keep moving Enchanted-only stand-ins back into reusable QuillUI controls and shims.

## 2. IceCubes

Status: compile-green hard-gated. First-milestone Mastodon timeline shell shipped (CP82 + CP93) — `IceCubesAPI.swift` re-implements the Mastodon API surface (`Account`, `Status`, `HTMLString`, `Timelines.pub`, `MastodonClient`) locally since the upstream Models / NetworkClient packages pin iOS-18-only. Live public-timeline shell fetches via URLSession with snake_case JSON decoding. `QuillIceCubesCoreTests` (22 tests, hard-gated) pin the entire pure-data surface.

Why it matters:

- Social client with timelines, account/session flows, media, notification surfaces, rich navigation, and large SwiftUI usage.
- Good forcing function for list performance, navigation compatibility, image loading, credential storage, and async feed updates.

Likely first milestone:

- Compile a Mastodon timeline shell using QuillUI controls, QuillData cache models, and a small adapter over IceCubes' data/client layer.

## 3. NetNewsWire

Status: compile-green hard-gated. Self-contained two-pane RSS reader (sidebar + detail) shipped (CP84 + CP94) — `QuillNetNewsWireCore` ships a Foundation `XMLParser`-backed RSS 2.0 + Atom 1.0 parser + `URLSession` fetcher; defaults to fetching daringfireball.net on first launch. The upstream `NetNewsWireLogic` target's Shared/Mac tree (~1655 unresolved symbols on either platform) stays opt-in and unbuilt. `QuillNetNewsWireCoreTests` (12 tests) pin the parser via fixture XML strings. OPML import/export and three-pane layout are follow-ups.

Why it matters:

- Mature RSS reader with a large real-world Swift codebase, modular feed parsing/downloading packages, SQLite-backed article/account state, AppKit table/outline/web views, OPML import/export, smart feeds, search, and sync services.
- It tests whether QuillUI can support productivity-app density rather than only chat/social layouts.

Likely first milestone:

- Build a Linux reader shell with a three-pane layout: feed/sidebar tree, article timeline, and article reader.
- Reuse NetNewsWire's parser and model packages where they compile cleanly on Linux.
- Avoid full sync-service parity at first; start with local/direct RSS and OPML import.

Audit doc:

- `docs/netnewswire-audit.md`

## Side Target: WireGuard Apple

Linux window sizing note: WireGuard's shared default window width now matches the Linux minimum width, so GTK and Qt start from the same unclamped dimensions before either host applies backend-specific window constraints. The same style snapshot now owns tunnel row metrics, detail key width, monospaced text sizing, and import editor height, removing duplicated GTK/Qt literals from the inner app chrome.

Status: compile-green hard-gated on macOS CI (CP87). `scripts/fetch-upstream.sh wireguard` patches `WireGuardKitC.h` to explicitly `#include <sys/types.h>` so the macOS 15+ modular-header check on `u_int32_t` / `u_char` / `u_int16_t` resolves through the right Darwin module. A Linux configuration-manager shell renders deterministic tunnel fixtures with interface details, peer details, editable tunnel names, `wg-quick` export text, and shared `.conf` parsing through the `QuillWireGuardCore` + `QuillWireGuardUI` targets. The GTK shell can import pasted or selected `.conf` text through the shared Swift parser and now exposes the same selected-row background and import-error text tokens that the native Qt host uses. The native Qt experiment now keeps the canonical `quill-wireguard` product name behind the explicit SwiftPM build selector `QUILLUI_LINUX_BACKEND=qt`; that graph uses a Qt6 Widgets host fed by the same `QuillWireGuardCore` presentation snapshot instead of linking the GTK path, and its import dialog can paste or choose a `.conf` file before calling back into Swift for the shared parser rather than duplicating WireGuard parsing in C++. The shared `interaction-extra-mode-matrix` now seeds `Tests/Fixtures/WireGuard/imported-edge.conf` for GTK paste import, GTK file import, Qt paste import, and Qt file import, plus `import-invalid-paste` and `import-invalid-file` on both backends for malformed shared-parser error states. GTK file import uses the cross-platform `QuillFileImporter` selection hook, while Qt file import uses its native file-read startup hook; invalid Qt file import can seed and submit the native dialog on startup so screenshots capture the same visible error state as invalid paste. Valid GTK and Qt import screenshots assert that the imported tunnel row becomes selected; invalid import screenshots assert that the shared error color appears in the GTK panel and native Qt dialog. The default app interaction matrix now drives the same editable tunnel-name smoke on both GTK and native Qt, so rename regressions fail before backend-specific import checks run. The GTK fallback view now resolves its shell dimensions, sidebar/detail spacing, section padding, and neutral colors from the same shared style and metadata tokens consumed by the Qt host. Privileged connect/disconnect remains behind a future backend adapter.

Why it matters:

- It is a focused Apple app with settings, tunnel state, configuration import/export, key material handling, and privileged system integration.
- It should be a relatively contained way to test QuillUI forms, lists, disclosure sections, file import/export, QR/config flows, and service-status UI.
- The Linux app should not try to clone Apple's NetworkExtension stack. The likely Linux path is an adapter over installed WireGuard tooling or NetworkManager, with the Apple-specific tunnel implementation hidden behind a reusable service boundary.

Next milestone:

- Persist edited/imported tunnel fixtures through QuillData.
- Extend the same malformed import coverage to the next native app target once it exposes a semantic error-state interaction.
- Promote the WireGuard Qt host pattern into a reusable QuillUI backend adapter once the broader Qt renderer shape is stable.
- Wire connect/disconnect through a Linux-specific backend when running on a real desktop with the right permissions.

## 4. CodeEdit

Status: compile-green hard-gated. Fixtures-only IDE shell shipped (CP86 + CP89) — file-tree sidebar with emoji icons keyed off `ProjectFile.extension`, tab bar with close `×` per tab + active highlight, monospaced editor pane. Editor is now editable (CP100): `TextEditor` bound to `project.files[idx].contents` via a two-way Binding so edits flow back to the project model. `QuillCodeEditCoreTests` (10 tests) pin ProjectFile.extension parsing + fixture invariants. The vendored CodeEditUpstream target stays opt-in (its `CodeEditSymbols` SwiftLintPlugin prebuild command trips SwiftPM 6). Folder-open + save-to-disk are follow-ups.

Why it matters:

- Large SwiftUI/macOS desktop app with dense professional UI: sidebar navigators, editor tabs, command surfaces, preferences, search, file trees, extension-like features, and project state.
- It forces QuillUI beyond consumer app layouts into IDE-grade split views, tables, toolbars, keyboard shortcuts, menus, focus handling, and text/editor integration.

Likely first milestone:

- Build a Linux project browser/editor shell: open a folder, show a file tree, open text files in tabs, edit/save plain text, and expose command/menu scaffolding.
- Reuse pure Swift model/project utilities where possible, but expect AppKit/editor surfaces to need QuillUI controls or a Linux text-editor backend.

## 5. Signal iOS

Status: compile-green hard-gated. Fixtures-only conversation shell shipped (CP85 + CP89 + CP92) — NavigationSplitView with sidebar list of seeded `Conversation`s, scrollable message timeline with rounded bubbles, and a functional `ChatComposer` (TextField + Send) that appends new self-messages to the active conversation. Bubble / sidebar-row / sidebar-list / timeline / composer chrome shared with Telegram via `QuillChatKit` (CP90 + CP96 + CP128). `QuillSignalCoreTests` (10 tests) pin fixture invariants, ChatMessage routing, and ChatListItem sidebar routing. The full libsignal / RingRTC / GRDB stack stays a follow-up.

A process-local `Security` surface now covers `SecRandomCopyBytes` for Signal-style key-material generation plus `SecItem` generic-password and internet-password add/copy/update/delete, duplicate detection, returned attributes/data, persistent-reference handles, access-group namespace filters, synchronizable filters, `kSecAttrSynchronizableAny` matching, server/protocol/authentication/port/path endpoint separation, and match-all queries. The `KeychainSwift` clone also exposes upstream-shaped UTF-8 string bytes, raw data bytes, single-byte bool storage, `getData(_:asReference:)`, `allKeys`, prefix/access-group/synchronizable namespaces, accessibility options, namespace clear behavior, and `lastResultCode` tracking so future libsignal/account storage code has a Linux source target. Native secure persistence, OS-enforced access control, real keychain sharing, real synchronization, and cross-process keychain behavior remain blockers.

Why it matters:

- Serious messaging app with large-scale state, account setup, secure local storage, media, notifications, database migrations, and high expectations for reliability.
- It stress-tests QuillData, encrypted persistence boundaries, chat timeline performance, attachment handling, and app lifecycle behavior.

Likely first milestone:

- Build a non-networked Linux conversation shell from local sample data, including chat list, message timeline, composer, media previews, settings, and database-shaped storage.
- Treat protocol/network/account work as out of scope until the UI/data architecture is stable.

## 6. Telegram Swift

Status: compile-green hard-gated. Fixtures-only folder-grouped chat shell shipped (CP85 + CP89 + CP92 + CP97) — pill row of All/Personal/Work folders above a shared `ChatSidebarList` with unread badges, scrollable timeline, and `ChatComposer` wired to `send()` that appends new self-messages. Folder filter logic extracted as `TelegramFolderFilter` for unit-testability. `QuillTelegramCoreTests` (11 tests) cover the filter, fixture invariants, and ChatListItem sidebar routing. The full MTProto / TDLib / SwiftSignalKit stack stays a follow-up.

Why it matters:

- Massive real-world chat app with complex navigation, media, rich text, reactions, calls-adjacent surfaces, caching, localization, and performance pressure.
- It tests whether QuillUI can survive large app architecture rather than isolated SwiftUI examples.

Likely first milestone:

- Build a Telegram-shaped local shell around chats, folders, message timelines, composer, media thumbnails, and settings using a fixture data store.
- Reuse portable Swift pieces only after an audit; expect a lot of Apple UI and platform integration to sit behind adapters.

## 7. IINA

Status: compile-green hard-gated. Fixtures-only desktop-player shell shipped (CP85 + CP89) — top row: now-playing title + Play/Pause/Stop transport controls + duration; left sidebar: playlist with `+ Add file` button + four seeded Blender Foundation shorts (Big Buck Bunny / Sintel / Tears of Steel / Charge); right canvas: large ▶/⏸ indicator backed by `isPlaying`. `QuillIINACoreTests` (7 tests) pin PlaylistItem identity + fixture invariants (mm:ss duration format, named shorts present). Real mpv playback backend stays a follow-up.

Why it matters:

- Media player UI stresses playback chrome, file/open panels, playlists, inspector panels, keyboard shortcuts, menus, preferences, and native media/backend integration.
- It is useful because Linux already has strong playback backends; QuillUI's job would be the Swift app shell and controls, not inventing a player core.

Likely first milestone:

- Build a Linux media-player shell that can open a local file, manage a playlist, and render playback controls around a Linux media backend.
- Keep exact mpv/player wiring behind an adapter so the UI target can compile before full playback parity.
