# IceCubes Behavior Parity Log

This tracks the gap between "IceCubes compiles on Linux" and "IceCubes behaves
like the macOS/iOS SwiftUI app through QuillUI." Percentages are rough working
estimates, not release claims.

## Current Baseline

- Compile coverage: 100% for `IceCubesLinuxApp`.
- Runnable app graph source coverage: about 97%.
- Useful runtime behavior estimate: 50-60%.
- Exact macOS-quality visual/interaction parity estimate: 20-30%.

## P0 Runtime Blockers

- [x] Upstream `@main App` lifecycle must run a GTK event loop instead of only
      constructing `body`.
- [x] Launch smoke must prove `IceCubesLinuxApp` stays alive under Xvfb.
- [x] Launch smoke must map a visibly populated first window. Current capture
      shows the unauthenticated timeline shell and Add Account sheet.
- [x] First-run environment must not crash on missing account/session defaults
      during the initial 8-second launch smoke.
- [ ] App-level `WindowGroup`, extra windows, `openWindow`, scene phase, and
      commands must have observable GTK behavior.

## P1 Core App Behavior

- [ ] Login/auth flow: browser authentication, callback URL handling, account
      persistence, token storage, account switching.
- [ ] Timeline flow: load public/home timelines, render rows, scroll, refresh,
      pagination, detail navigation.
- [ ] Composer flow: text entry, mentions/tags autocomplete, media attachment,
      post submission, drafts.
- [ ] Settings flow: display settings, tab/sidebar settings, content settings,
      API settings, remote timelines, tag groups, icon/support panes.
- [ ] Media flow: images/video attachments, quick look/media viewer, thumbnails,
      share sheet metadata.
- [ ] Notifications/conversations/lists/explore/profile tabs: render, navigate,
      refresh, and mutate state.

## P1 QuillUI/SwiftUI Surface Gaps

- [ ] Exact app lifecycle for canonical `import SwiftUI` apps.
- [x] Initial content paint for upstream `TabView`/sidebar app shells. IceCubes
      now paints the logged-out timeline/add-account path instead of a blank
      first window.
- [ ] Allocation-aware SwiftUI layout parity for split views, lists, grids,
      forms, sheets, popovers, and toolbars.
- [ ] Real menu and command behavior: disabled state, keyboard shortcuts,
      click-outside dismissal, native menu placement.
- [ ] Focus, text input hints, selection, keyboard navigation, accessibility,
      and scroll-to behavior across rebuilt GTK widgets.
- [x] First Add Account sheet interaction path: suggestions load, suggestion
      rows are clickable, text-field state survives sheet rebuilds, and the
      instance detail/sign-in flow can render after the instance lookup settles.
- [ ] Animation parity: transition playback, matched geometry, symbol effects,
      implicit animation timing.
- [ ] Visual parity: fonts, spacing, colors, symbol rendering, materials,
      masks, gradients, row chrome, toolbar chrome.

## P1 Apple Service Shims

- [x] `AuthenticationServices` / web auth session: open browser through the
      shared Linux URL opener, receive a delivered callback URL, and return it
      through SwiftUI's async `webAuthenticationSession` action.
- [x] SwiftUI `openURL` default handling uses the same shared Linux URL opener,
      so regular IceCubes links and OAuth browser launches share diagnostics,
      headless rejection, and injectable desktop/test backends.
- [x] OAuth/account storage survives app restarts through the `KeychainSwift`
      compatibility store. This is persistent Linux behavior for IceCubes'
      `AppAccount.save()` / `retrieveAll()` flow, not native secure storage.
- [ ] Desktop URL-scheme registration and native Secret Service-backed OAuth
      token security.
- [x] `UserNotifications`: immediate local notification delivery routes through
      an injectable Linux desktop presentation backend, with a `notify-send`
      default when a desktop session is available.
- [ ] `UserNotifications`: scheduled timer delivery and APNs-equivalent remote
      push behavior.
- [x] `ImageIO`: local file/data decode, dimensions metadata, thumbnail
      downsample, crop-preserving `CGImage` pixels, and JPEG/PNG/TIFF output
      through gdk-pixbuf.
- [x] `UIImage` / `UIGraphicsImageRenderer`: PNG/JPEG decode into `UIImage`,
      `UIImage(cgImage:)`, `jpegData`, `pngData`, bitmap renderer output,
      image draw/resize, `UIColor.setFill`, and `UIRectFill` produce real
      pixels for IceCubes' upload/downsample/fill paths.
- [ ] `UIImage` / `UIGraphicsImageRenderer`: text drawing, gradients, masks,
      complex paths/transforms/blend modes, orientation/EXIF metadata,
      animated images, HEIC/video thumbnails, and full compositing parity.
- [x] `Photos`: local Linux photo-library fallback saves `UIImage` assets,
      fetches `PHAsset` rows, and loads image data/resized thumbnails back
      through `PHImageManager`.
- [x] SwiftUI `.fileImporter`: shared Linux URL selection supports test,
      environment, and desktop command backends with content-type validation
      and single/multiple-selection behavior.
- [x] `PhotosUI` / `CoreTransferable`: file-backed
      `PhotosPickerItem.loadTransferable` and `NSItemProvider.loadTransferable`
      import IceCubes image/GIF/movie `FileRepresentation` values from local
      URLs or compatible data blobs; `.photosPicker` modifiers consume the
      same shared Linux file selections and write file-backed picker items.
- [ ] `PhotosUI`: native photo-library picker UI, native GTK/Qt dialog
      integration beyond command-dialog fallback, native picker item providers,
      video previews, and real system photo-library integration.
- [x] SwiftUI `.quickLookPreview(_:)` opens local preview URLs through a shared
      QuillKit QuickLook backend instead of dropping the binding.
- [ ] `QuickLook`: full IceCubes media viewer/window behavior for
      `Env.QuickLook.selectedMediaAttachment`, not just selected item storage.
- [ ] `AppIntents`: runtime values and shortcuts, not just compile surface.
- [ ] `RevenueCat`, `StoreKit`, `WishKit`: graceful real Linux behavior or
      explicit unsupported UI states.
- [ ] Haptics/sounds: desktop substitutes or explicit no-hardware behavior.

## P2 Build/Profile Gaps

- [ ] Replace ad hoc app-target wiring with reusable profile/build-plugin
      descriptors.
- [ ] Fix the incremental GTK importer leak where targets such as
      `IceCubesShims` can require a clean scratch rebuild after backend module
      changes.
- [ ] Keep IceCubes-specific shims isolated; move reusable behavior into
      QuillUI, QuillKit, QuillData, or Apple framework shim targets.
- [ ] Add CI launch smoke and screenshot artifacts for `IceCubesLinuxApp`.
- [ ] Add side-by-side macOS/Linux interaction test plan for the top workflows.

## Checkpoints

- 2026-06-09: Compile-clean GTK Linux target exists. Behavior pass starts with
  canonical SwiftUI app lifecycle and launch smoke.
- 2026-06-09: Added real `icecubes-linux-app` executable product and verified
  it links. Fixed canonical `App.main` GTK dispatch for `import SwiftUI` apps.
- 2026-06-09: Removed launch traps for nested SwiftUI `Tab` values, eager
  boolean sheet content, UIKit representable placeholders, and async
  `@Environment(SomeClass.self)` reads. The real upstream app now stays alive
  under Xvfb for 8 seconds (`timeout` exit 124).
- 2026-06-09: Captured `.tmp-icecubes-screenshot.png`; it maps a GTK surface
  with menu chrome but still lacks visible IceCubes content. Next blocker is
  initial content paint/layout, not process launch.
- 2026-06-09: Deferred value-based `WindowGroup(for:)` scenes at startup so
  editor/media value windows no longer cover the main app with a blank window.
- 2026-06-09: Added form/section fill behavior, responsive sheet sizing, root
  sheet overlay navigation context, `.xcstrings` localization, and additional
  SF Symbol mappings. Fresh captures show the real Add Account sheet with
  localized title, Cancel action, `Instance URL` placeholder, Suggestions
  header, and populated unauthenticated timeline chrome.
- 2026-06-09: Remaining visible gaps include GTK-native toolbar styling,
  duplicate/over-eager toolbar menu presentation, async image timing, modal
  dimming and hit-testing, picker/menu interaction parity, and authenticated
  Mastodon sign-in/browser callback behavior.
- 2026-06-09: Fixed sheet-local `@State` identity for item sheets so
  Add Account's suggestion-row state writes update the visible `TextField`
  after sheet rebuilds. Custom-label GTK buttons now recursively defer pointer
  targeting to the button and expand GTK-box row labels so the clickable area
  better matches the painted suggestion card.
- 2026-06-09: Added horizontal `LabeledContent` compatibility rows, mapped
  `checkmark.seal`, added `Text(AttributedString)`, removed an unsafe recursive
  sheet-dismissal reflection walk that could segfault on IceCubes' large view
  graph, and made text-bearing leading `VStack`s use flexible GTK box layout.
  Current instance-info captures show usable content and non-collapsed account
  rows, but still have rough Form styling, imperfect rich text/link styling, and
  unauthenticated browser sign-in still incomplete.
- 2026-06-09: Fixed `.xcstrings` plural/positional substitutions, stopped
  arbitrary locale fallback when the preferred/source language is missing, and
  resolved flattened SwiftUI interpolation keys such as
  `account.label.followers 872850 872.8K`. The Add Account instance-info capture
  now shows English `API Versions` / `Monthly Active Users` and
  `872.8K followers`.
- 2026-06-09: Added shared `QuillFoundation.HTMLText.plainText(fromMarkdown:)`
  and routed Linux `AttributedString(markdown:)` plus `EmojiText(markdown:)`
  through it. This removes literal markdown source from visible account-note
  text, e.g. `follow [@MastodonEngineering](...)` renders as
  `follow @MastodonEngineering`. Verification: `QuillFoundationTests` target
  compile passed, a one-off Swift runtime assertion check passed, and
  `icecubes-linux-app` rebuilt successfully. Current Xvfb interaction could not
  re-enter instance info because the live `instances.social` suggestions API
  returned empty/loading in-app and headless keyboard input did not focus the GTK
  text field; this remains an automation/app-flow gap, not a compile failure.
- 2026-06-16: Replaced the process-local `KeychainSwift` compatibility store
  with a JSON-backed persistent store so IceCubes account JSON and OAuth tokens
  can be retrieved across Linux app restarts. This keeps the security capability
  honest: persistence works now, native Secret Service encryption remains a
  follow-up. Verification: `KeychainSwiftTests` (8 tests) and
  `QuillIceCubesCoreTests` (34 tests) passed locally.
- 2026-06-16: Routed SwiftUI `OpenURLAction`'s default handler through
  `QuillWorkspace.open` instead of spawning `xdg-open` directly. This makes
  regular IceCubes links testable and keeps URL behavior aligned with
  `ASWebAuthenticationSession`, `UIApplication.open`, and `NSWorkspace.open`.
  Verification: `SourceHygieneTests` (52 tests) passed locally; the new
  Linux-only compatibility test runs in the PR Linux graph.
- 2026-06-16: Added an injectable QuillKit desktop notification presentation
  backend and Linux `notify-send` fallback for immediate
  `UNUserNotificationCenter.add` deliveries. Scheduled notifications remain
  queued-only. Verification: targeted QuillKit/UserNotifications tests were
  added; Linux-only compatibility coverage runs in the PR Linux graph.
- 2026-06-16: Added `QuillQuickLookService` and routed SwiftUI
  `.quickLookPreview($url)` through it, clearing the binding after an attempt to
  avoid repeated preview launches during GTK/Qt rebuilds. This covers IceCubes'
  media toolbar quick-look button; the larger selected-attachment media viewer
  still needs native window/sheet parity. Verification: targeted QuillKit and
  Linux-only compatibility tests were added.
- 2026-06-16: Replaced the inert Linux `ImageIO` shim with a gdk-pixbuf-backed
  `CGImageSource`/`CGImageDestination` subset: data/provider/URL decode,
  image type, dimensions metadata, full image pixels, thumbnails, crop
  preservation, and JPEG/PNG/TIFF output now work. This unblocks IceCubes'
  media upload/downsample path and the `InlinePostImageIntent` image pipeline
  shape. Verification: `quill-imageio-smoke` passed in Docker/GTK; the
  Linux-only compatibility test covers the same contract in the broader suite.
- 2026-06-16: Added a QuillFoundation bitmap image codec and a real
  `UIImage`/`UIGraphicsImageRenderer` pixel path for Linux. `UIImage(data:)`,
  `UIImage(cgImage:)`, `jpegData`, `pngData`, renderer output, image
  draw/resize, `UIColor.setFill`, and `UIRectFill` now exercise real bitmap
  pixels instead of inert placeholders. Verification: `QuillFoundationTests`,
  `SourceHygieneTests`, Docker/GTK `quill-imageio-smoke`, Docker/GTK
  `IceCubesLinuxApp`, and Docker/Qt `ImageIO` builds passed locally.
- 2026-06-16: Replaced the empty Linux `Photos` behavior with a local
  Quill photo-library fallback. `UIImageWriteToSavedPhotosAlbum`,
  `PHAssetCreationRequest`, `PHAsset.fetchAssets`, and `PHImageManager`
  data/image requests now persist and reload real image bytes for IceCubes'
  media viewer save button and recent-photos strip. Verification: Docker/GTK
  `quill-photos-smoke`, Docker/GTK `IceCubesLinuxApp`, and
  `SourceHygieneTests` passed locally.
- 2026-06-16: Moved Linux file selection into the canonical
  `QuillSwiftUICompatibility` SwiftUI surface, added multi-selection support,
  and wired SwiftUI `.fileImporter` plus PhotosUI `.photosPicker` modifiers to
  the same test/environment/desktop-command URL picker. Verification:
  Docker/GTK `fileImporterAndPhotosPickerUseSharedFileSelection` passed, and
  the same source compiles on macOS.
