# QuillUI App Targets

QuillUI should prove itself against real open-source Swift apps that stress different parts of the Apple stack.

## 1. Enchanted

Status: active first port.

Why it matters:

- Chat app surface with sidebar, message list, composer, image attachments, model picker, and streaming network state.
- Good forcing function for SwiftUI compatibility, local persistence, Markdown rendering, async tasks, and Linux desktop polish.

Current approach:

- Build a reusable `QuillUI` facade and `QuillData` persistence layer while keeping app-specific changes small.
- Keep moving Enchanted-only stand-ins back into reusable QuillUI controls and shims.

## 2. IceCubes

Status: next app after Enchanted reaches a strong checkpoint.

Why it matters:

- Social client with timelines, account/session flows, media, notification surfaces, rich navigation, and large SwiftUI usage.
- Good forcing function for list performance, navigation compatibility, image loading, credential storage, and async feed updates.

Likely first milestone:

- Compile a Mastodon timeline shell using QuillUI controls, QuillData cache models, and a small adapter over IceCubes' data/client layer.

## 3. NetNewsWire

Status: third app target.

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

Status: opportunistic compatibility target.

Why it matters:

- It is a focused Apple app with settings, tunnel state, configuration import/export, key material handling, and privileged system integration.
- It should be a relatively contained way to test QuillUI forms, lists, disclosure sections, file import/export, QR/config flows, and service-status UI.
- The Linux app should not try to clone Apple's NetworkExtension stack. The likely Linux path is an adapter over installed WireGuard tooling or NetworkManager, with the Apple-specific tunnel implementation hidden behind a reusable service boundary.

Likely first milestone:

- Build a Linux configuration manager shell that can list, edit, import, and export tunnel configs while stubbing the privileged connect/disconnect path.
- Then wire connect/disconnect through a Linux-specific backend when running on a real desktop with the right permissions.

## 4. CodeEdit

Status: fourth main app target.

Why it matters:

- Large SwiftUI/macOS desktop app with dense professional UI: sidebar navigators, editor tabs, command surfaces, preferences, search, file trees, extension-like features, and project state.
- It forces QuillUI beyond consumer app layouts into IDE-grade split views, tables, toolbars, keyboard shortcuts, menus, focus handling, and text/editor integration.

Likely first milestone:

- Build a Linux project browser/editor shell: open a folder, show a file tree, open text files in tabs, edit/save plain text, and expose command/menu scaffolding.
- Reuse pure Swift model/project utilities where possible, but expect AppKit/editor surfaces to need QuillUI controls or a Linux text-editor backend.

## 5. Signal iOS

Status: fifth main app target.

Why it matters:

- Serious messaging app with large-scale state, account setup, secure local storage, media, notifications, database migrations, and high expectations for reliability.
- It stress-tests QuillData, encrypted persistence boundaries, chat timeline performance, attachment handling, and app lifecycle behavior.

Likely first milestone:

- Build a non-networked Linux conversation shell from local sample data, including chat list, message timeline, composer, media previews, settings, and database-shaped storage.
- Treat protocol/network/account work as out of scope until the UI/data architecture is stable.

## 6. Telegram Swift

Status: sixth main app target.

Why it matters:

- Massive real-world chat app with complex navigation, media, rich text, reactions, calls-adjacent surfaces, caching, localization, and performance pressure.
- It tests whether QuillUI can survive large app architecture rather than isolated SwiftUI examples.

Likely first milestone:

- Build a Telegram-shaped local shell around chats, folders, message timelines, composer, media thumbnails, and settings using a fixture data store.
- Reuse portable Swift pieces only after an audit; expect a lot of Apple UI and platform integration to sit behind adapters.

## 7. IINA

Status: seventh main app target; assuming "INNA" means IINA.

Why it matters:

- Media player UI stresses playback chrome, file/open panels, playlists, inspector panels, keyboard shortcuts, menus, preferences, and native media/backend integration.
- It is useful because Linux already has strong playback backends; QuillUI's job would be the Swift app shell and controls, not inventing a player core.

Likely first milestone:

- Build a Linux media-player shell that can open a local file, manage a playlist, and render playback controls around a Linux media backend.
- Keep exact mpv/player wiring behind an adapter so the UI target can compile before full playback parity.
