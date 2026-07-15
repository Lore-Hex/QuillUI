# IceCubes Behavior Parity Log

This tracks the gap between "IceCubes compiles on Linux" and "IceCubes behaves
like the macOS/iOS SwiftUI app through QuillUI." Percentages are rough working
estimates, not release claims.

## Current Baseline

- Compile coverage: 100% for `IceCubesLinuxApp`.
- Runnable app graph source coverage: about 97%.
- Useful runtime behavior estimate: 78-82%.
- Exact macOS-quality visual/interaction parity estimate: 25-30%.

## P0 Runtime Blockers

- [x] Upstream `@main App` lifecycle must run a GTK event loop instead of only
      constructing `body`.
- [x] Launch smoke must prove `IceCubesLinuxApp` stays alive under Xvfb.
- [x] Launch smoke must map a visibly populated first window. Current capture
      shows the unauthenticated timeline shell and Add Account sheet.
- [x] First-run environment must not crash on missing account/session defaults
      during the initial 8-second launch smoke.
- [x] Value-based `WindowGroup(for:)` scenes must defer at startup and open
      observable GTK windows from `openWindow(value:)` with the bound value.
- [ ] Scene phase, full commands, command keyboard routing, and value-window
      restoration/refocus must have observable GTK behavior.

## P1 Core App Behavior

- [ ] Login/auth flow: browser authentication, callback URL handling, account
      persistence, token storage, account switching.
- [ ] Timeline flow: load public/home timelines, render rows, scroll, first
      home pagination, Home refresh, Notifications refresh, Status detail
      refresh, and detail navigation are covered; broader refresh/pagination
      surfaces and deeper row interactions remain open.
- [ ] Composer flow: text entry and fixture-backed submit are covered; mentions/tags
      autocomplete, media attachment, drafts, and post-result routing remain open.
- [ ] Settings flow: root Settings tab and Display Settings child navigation
      render under the authenticated upstream app, including the Display preview
      and upper/lower form controls; Display font-size slider mutation is
      covered. Tab/sidebar settings, content settings, API settings, remote
      timelines, tag groups, icon/support panes, and broader setting mutations
      remain open.
- [ ] Media flow: images/video attachments, quick look/media viewer, and
      thumbnails are partly covered; video attachments and share sheet metadata
      remain open.
- [ ] Notifications/conversations/lists/explore/profile tabs: notifications,
      conversations, profile, Explore, and Lists render/navigate are covered;
      Notifications/Messages/List refresh, List pagination, and Messages detail
      navigation are covered; list mutation state, refresh on the remaining tabs,
      and deeper row interactions remain open.

## P1 QuillUI/SwiftUI Surface Gaps

- [ ] Exact app lifecycle for canonical `import SwiftUI` apps.
- [x] Initial content paint for upstream `TabView`/sidebar app shells. IceCubes
      now paints the logged-out timeline/add-account path instead of a blank
      first window.
- [ ] Allocation-aware SwiftUI layout parity for split views, lists, grids,
      forms, sheets, popovers, and toolbars.
- [ ] Real menu and command behavior: disabled state, keyboard shortcuts,
      click-outside dismissal, native menu placement.
- [x] `ToolbarTitleMenu` renders as compact toolbar menu chrome for IceCubes'
      authenticated timeline shell instead of dumping menu contents into the
      main content area.
- [ ] Focus, text input hints, selection, keyboard navigation, accessibility,
      and scroll-to behavior across rebuilt GTK widgets.
- [x] GTK `List` direct row lifecycle: row-contained `.task` / `onAppear`
      payloads are excluded from the parent host's eager lifecycle pass and
      started by viewport-visible row tracking. Follow-up remains for nested
      hosted row subtrees, non-`List` lazy stacks, and real row virtualization.
- [x] SwiftUI `.refreshable`: GTK keeps the async refresh action instead of
      dropping it, wires `Command/Ctrl-R` through the existing window shortcut
      registry, and attaches top-edge overscroll handlers to nested
      `GtkScrolledWindow` widgets.
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
- [x] `AuthenticationServices`: active sessions can monitor a callback URL
      bridge file, so desktop URL-scheme helper processes can hand OAuth
      callbacks to the running app without app-source changes.
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
- [x] `UserNotifications`: non-repeating time-interval local notification
      requests move from pending to delivered and route through the same desktop
      presentation backend when their timer fires.
- [ ] `UserNotifications`: durable OS-level scheduling and APNs-equivalent
      remote push behavior.
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
- [x] Add CI launch smoke and screenshot artifacts for `IceCubesLinuxApp`.
- [x] Add CI smokes for upstream Add Account interaction, OAuth browser-boundary
      launch, seeded authenticated shell chrome, seeded authenticated Trending
      sidebar navigation, seeded authenticated Local timeline navigation, seeded
      authenticated Federated timeline navigation, seeded authenticated
      Explore navigation, seeded authenticated Notifications navigation, seeded
      authenticated Profile/Messages/List navigation, seeded authenticated
      Explore Links/Tags/Suggested Users/Search routes, Composer window
      open/text entry/submit, and seeded authenticated Status detail
      navigation/action mutation, seeded authenticated media viewer, seeded
      authenticated Home pagination/refresh, seeded authenticated Notifications
      refresh, seeded authenticated Messages refresh, plus seeded authenticated
      Settings root and Display Settings child navigation.
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
- 2026-06-17: Added typed value-window registration to SwiftOpenUI and the GTK
  backend. `OpenWindowAction` now supports `openWindow(value:)` and
  `openWindow(id:value:)`, `WindowGroup(for:)` preserves its
  `Binding<Value?>` content factory through window modifiers, and GTK opens a
  deferred top-level window with the requested value bound into content. This
  covers IceCubes' composer and media-viewer destination pattern generically;
  scene phase, command parity, value-window restoration/refocus, and exact
  window chrome remain incomplete. Verification: Docker/GTK
  `SwiftUIValueWindowCompatibilityTests` passed.
- 2026-06-19: Added `seeded-authenticated-home-pagination` coverage. The
  upstream IceCubes GTK visual harness now scrolls the real Home timeline,
  waits for the app's
  `GET /api/v1/timelines/home?max_id=1001&limit=40` request, serves a visible
  next-page fixture, scrolls again after the response, and verifies lower
  appended row pixels instead of accepting the unchanged top media row. Docker
  visual verification now passes for this route. This pins GTK scroll-wheel
  propagation, IceCubes' unmodified timeline pagination task, direct fixture
  matching, and list repaint after append.
- 2026-06-19: Added generic GTK `List` row lifecycle gating. `List` now
  describes direct rows inside a `listRowLifecycleScope`, suppresses those row
  `.task` / `onAppear` payloads from the parent `GTKViewHost`, attaches a row
  lifecycle box during row rendering, and starts/cancels row tasks as the row
  enters/leaves the scrolled viewport. This removes the worst eager pagination
  behavior for direct row tasks while keeping IceCubes source unchanged.
  Remaining gaps: nested row subhosts can still own their own eager lifecycle,
  rows are still materially rendered rather than virtualized, and non-Home
  refresh plus broader pagination routes remain open.
- 2026-06-19: Added reusable SwiftUI `.refreshable` behavior for GTK and
  pinned it with `seeded-authenticated-home-refresh`. The old compatibility
  fallback discarded the async action; `RefreshableView` now preserves it,
  the GTK renderer registers `Command/Ctrl-R` against the active window and
  installs top-edge overscroll handlers on nested scrolled windows, and the
  IceCubes smoke proves the unmodified Home timeline runs
  `TimelineViewModel.pullToRefresh()` by observing an additional
  `/api/v1/timelines/home?limit=50` fixture request plus refreshed Home pixels.
  Remaining gaps at that point: native pull indicator/progress chrome,
  touch-drag threshold parity, and refresh coverage for
  Notifications/Conversations/Status detail.
- 2026-06-20: Extended the same reusable GTK `.refreshable` path to
  `seeded-authenticated-notifications-refresh`. The visual harness now has a
  route-agnostic refresh shortcut driver that focuses the window, sends
  `Command/Ctrl-R`, waits for a fresh refresh debug trigger, and verifies the
  upstream Notifications list performs another v2 grouped-notifications request
  using `since_id=1002` without changing IceCubes source. The seeded Mastodon
  fixture now covers both the legacy v1 Notifications response and the current
  `/api/v2/notifications?...grouped_types...` response shape, so the smoke stays
  network-independent as upstream IceCubes prefers grouped notifications.
  Remaining gaps: native pull indicator/progress chrome, touch-drag threshold
  parity, and refresh coverage for Status detail and non-list lazy surfaces.
- 2026-06-20: Extended the route-agnostic refresh smoke to
  `seeded-authenticated-messages-refresh`. The harness now opens the real
  upstream Messages/Conversations tab through a shared route opener, waits for
  the fixture-backed `/api/v1/conversations` navigation fetch, sends
  `Command/Ctrl-R`, verifies another conversations fetch through the reusable
  GTK `.refreshable` action, and captures populated Messages pixels. This moves
  refresh coverage beyond timeline-style lists without changing IceCubes source.
  Remaining gaps: native pull indicator/progress chrome, touch-drag threshold
  parity, Status detail refresh, and non-list lazy surfaces.
- 2026-06-20: Extended the same reusable refresh coverage to
  `seeded-authenticated-status-detail-refresh`. The harness opens the real
  `StatusDetailView`, sends `Command/Ctrl-R`, exact-matches fresh fixture log
  lines for both `/api/v1/statuses/1003` and
  `/api/v1/statuses/1003/context`, and reuses the populated Status detail visual
  validator. This proves the upstream `StatusDetailViewModel.fetch()` refresh
  path runs under GTK without app-source changes. Remaining gaps: native pull
  indicator/progress chrome, touch-drag threshold parity, and non-list lazy
  surfaces.
- 2026-06-20: Tightened the status-detail opener so it no longer depends on
  verbose GTK action debug logs. The click retry loop now waits for exact
  fixture activity on the real status and context detail endpoints, then runs
  the populated visual validator. This keeps Status detail/navigation/refresh
  smokes behavior-based while avoiding large CI app logs.
- 2026-06-17: Added reusable Linux `Combine` scheduler overloads for the Apple
  spellings IceCubes uses (`DispatchQueue.main` with `debounce`, plus
  `RunLoop`/`OperationQueue` coverage for adjacent operators). The gated
  Docker/GTK `icecubes-linux-app` product build now completes after clearing
  the previous `DispatchQueue` scheduler failure; this is compile parity, not
  a claim of complete interactive or visual parity.
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
- 2026-06-17: Extended SwiftOpenUI `.xcstrings` loading to handle top-level
  plural variations, which IceCubes uses for status-detail summary rows such as
  `status.summary.n-favorites %lld` and `status.summary.n-boosts %lld`.
  Verification: `LocalizationTests/testTopLevelPluralVariationCatalogEntryFormatsFlattenedInterpolation`
  passed, and the authenticated status-detail smoke captured
  `.qa/icecubes-auth-status-detail-localization-v1.png` with visible
  `42 favorites` / `8 boosts` instead of raw localization keys.
- 2026-06-19: Extended SwiftOpenUI `.xcstrings` plural substitutions to honor
  catalog `argNum` metadata and `%arg` replacement tokens. This fixes IceCubes'
  Explore Tags rows, where `TagRowView` renders
  `design.tag.n-posts-from-n-participants \(uses) \(accounts)`. Verification:
  `LocalizationTests/testPluralCatalogSubstitutionUsesArgNumAndArgToken`
  passed, source-hygiene pins cover the vendored patch script, and the
  authenticated Explore Tags smoke captured
  `.qa/icecubes-auth-explore-tags-argnum-fixed.png` with `146 posts from 45
  participants` / `217 posts from 75 participants` instead of `%arg`.
- 2026-06-19: Fixed authenticated Settings -> Display child navigation as a
  reusable SwiftOpenUI GTK navigation behavior. `NavigationLink` rows inside
  `Form` now install a primary-action fallback, destination routes persist
  through root rebuilds even when the stack also has a bound router path, and
  the GTK menu-bar patcher no longer rewraps its own guarded setup block on
  repeated clean setup runs. The Settings Display verifier now rejects the
  transitional root Settings frame with the visible Log Out row, so the smoke
  waits for real child content. Verification: Docker `icecubes-linux-app`
  build passed, the authenticated Settings Display visual smoke passed at
  `.qa/icecubes-auth-settings-display-v16.png`, and focused source-hygiene
  tests passed.
- 2026-06-19: Fixed GTK `ZStack`/overlay vertical expansion so IceCubes'
  `DisplaySettingsView` preview post no longer fills the pushed Settings
  screen and hides the real controls. SwiftOpenUI now tracks explicit vertical
  fill intent separately from incidental GTK `vexpand`, the patcher preserves
  that contract, and the Settings Display verifier requires both upper controls
  and lower font-scaling controls to catch this regression. Verification:
  source-hygiene contract test passed, Docker/GTK
  `GTK4RenderTests.testZStackTopOverlay*` passed under Xvfb, Docker
  `icecubes-linux-app` build passed, and the authenticated Settings Display
  smoke passed at `.qa/icecubes-auth-settings-display-v18.png`.
- 2026-06-19: Added authenticated Settings Display font-size slider interaction
  coverage. The visual harness now opens the real upstream Display Settings
  route, drags the first font scaling `Slider`, and verifies the post-mutation
  blue track extends beyond the old midpoint while the Display form remains
  routed and visible. This covers one real setting mutation through GTK
  `Slider` events and SwiftUI binding rebuilds. Verification: source-hygiene
  visual-smoke pins passed, and Docker
  `seeded-authenticated-settings-display-font-scale` passed at
  `.qa/icecubes-auth-settings-display-font-scale-v1.png` with
  `Font Scaling: 1.2`.
- 2026-06-19: Added authenticated Settings Display system-color toggle
  mutation coverage. The first run exposed a shared `@Bindable` parity gap:
  IceCubes' upstream `Theme.followSystemColorScheme` uses `didSet` storage
  rather than `@Published`, so toggling the real SwiftUI row updated the GTK
  checkbox but did not rebuild the dependent color-picker rows. SwiftOpenUI now
  lets `@Bindable` key-path writes notify the environment observable-object
  dependency registry after mutation, while suppressing duplicate scheduling
  when normal `objectWillChange` already fired. The visual harness now covers
  `seeded-authenticated-settings-display-system-color` and verifies that the
  real Display form remains routed after the toggle and the color rows become
  enabled. Verification: Docker Linux
  `SwiftOpenUIStateCompatibilityTests/bindableEnvironmentObjectWritesInvalidateDidSetOnlyObservableProperties`
  passed, and Docker `seeded-authenticated-settings-display-system-color`
  passed at `.qa/icecubes-auth-settings-display-system-color-v2.png` with
  `system_color_toggle_accent_pixels=0` and
  `enabled_color_row_text_pixels=1100`.
- 2026-06-19: Promoted authenticated Settings Display font-picker coverage from
  row mutation to real route presentation plus select/dismiss behavior. GTK
  `Picker` now participates in descriptor-based navigation checks and binds
  dropdown/segmented callbacks to the render-time environment; boolean
  `navigationDestination(isPresented:)` routes now install a destination-local
  `dismiss` action, so IceCubes' UIKit font picker coordinator can pop the
  route after selection. The seed account reset also clears persisted display
  font defaults so the route is deterministic. Visual smokes now cover both
  `seeded-authenticated-settings-display-font-picker` for the pushed
  `Choose Font` route and
  `seeded-authenticated-settings-display-font-picker-select` for selecting
  `Inter`, dismissing, and returning to Display Settings with a non-default
  font label. Verification: Docker/GTK navigation tests for
  `testNavigationDestinationIsPresented*` passed, UIKit controller
  representable coordinator tests passed, the route smoke passed at
  `.qa/icecubes-auth-settings-display-font-picker-route-v4.png`, and the
  select/dismiss smoke passed at
  `.qa/icecubes-auth-settings-display-font-picker-select-v2.png`.
- 2026-06-17: Tightened authenticated status-detail chrome: SwiftUI
  `Text(date, style: .time)` now formats as a time instead of duplicating the
  date, GTK `NavigationStack` preserves empty destination titles instead of
  falling back to route type strings, and the shared SF Symbols map/codepoint
  table now covers the IceCubes status-detail action/sidebar glyphs observed
  in CI. Verification: focused `QuillUITests` date-style and source-hygiene
  tests passed, and the authenticated status-detail smoke captured
  `.qa/icecubes-auth-status-detail-icons-nav-v1.png` with no raw route title
  and no missing-symbol debug lines.
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
  `UNUserNotificationCenter.add` deliveries. Verification: targeted
  QuillKit/UserNotifications tests were added; Linux-only compatibility coverage
  runs in the PR Linux graph.
- 2026-06-17: Added `seeded-authenticated-trending` to the IceCubes GTK visual
  harness. It reuses the persisted test account, waits for the home timeline,
  clicks the real Trending sidebar row, and requires a fresh
  `/api/v1/trends/statuses` fixture request before screenshot verification.
  This turns authenticated sidebar navigation into a repeatable parity gate;
  detail navigation, compose windows, toolbar-menu click behavior, and richer
  timeline interactions remain follow-ups.
- 2026-06-17: Added `seeded-authenticated-local` to the same upstream visual
  harness. It clicks the real Local sidebar row, waits for
  `/api/v1/timelines/public?local=true&limit=50`, and verifies the selected
  sidebar state plus fixture-backed timeline rows. This expands authenticated
  timeline coverage beyond Home/Trending without modifying upstream IceCubes
  source; federated timeline, row detail navigation, pagination, refresh, and
  compose remain follow-ups.
- 2026-06-17: Added `seeded-authenticated-federated` and split the Mastodon
  public timeline fixtures by exact query. Local now serves
  `local=true&limit=50` rows, Federated serves `local=false&limit=50` rows, and
  the visual harness requires the corresponding IceCubes API request before
  screenshot verification. Authenticated Home, Trending, Local, and Federated
  route changes are now deterministic CI gates; row detail navigation,
  pagination, refresh, compose, settings, media, notifications, and visual
  polish remain open.
- 2026-06-17: Tightened the seeded authenticated visual harness so sidebar
  navigation smokes use a short initial settle, zero post-navigation settle,
  and explicit URLSession fixture activity waits. This avoids a Linux
  FoundationNetworking URLProtocol cancel-after-completion assertion in the
  test harness while still requiring the real IceCubes API request before
  capture. Screenshot capture now times out and prints the app log if the
  window dies before verification.
- 2026-06-17: Moved `QuillURLSessionFixtures` response delivery off the
  synchronous `URLProtocol.startLoading()` stack and made pending fixture
  delivery cancellation-aware. This stabilizes IceCubes' route-change fetch
  churn on Linux without changing upstream IceCubes source; the fixture delay
  remains opt-in through `QUILLUI_URLSESSION_FIXTURE_RESPONSE_DELAY_MS`.
- 2026-06-17: Added a direct async `QuillURLSessionFixtures.data(...)` transport
  and lowered IceCubes' generated `NetworkClient` calls through it. Matched
  Mastodon fixture requests now bypass swift-corelibs `URLProtocol` entirely and
  only fall back to real `URLSession` for unmatched requests, preserving upstream
  app logic while avoiding the Linux task-registry continuation trap in route
  smokes.
- 2026-06-17: Added `seeded-authenticated-notifications` to the IceCubes GTK
  visual harness. It clicks the real Notifications sidebar row, waits for the
  fixture-backed v2 grouped Notifications request and follow-up `since_id=1002`
  display refresh, serves the matching marker POST, and verifies populated
  notification rows rather than only sidebar selection. This also exercises
  SwiftUI `Tab(value:)` selection write-back through the GTK sidebar.
  Notification filtering,
  notification settings, push delivery, row detail navigation, and unread-count
  mutation remain follow-ups.
- 2026-06-19: Added `seeded-authenticated-profile` to the same upstream visual
  harness. It clicks the real Profile sidebar row and verifies the selected
  Profile sidebar row plus populated current-account detail header/stat surface.
  This extends authenticated tab coverage beyond timelines and notifications
  without changing upstream IceCubes source; full account refetch, profile tab
  switching, follow/edit mutations, conversations, lists, explore, and exact
  account-detail visual parity remain open.
- 2026-06-19: Added `seeded-authenticated-messages` to the upstream visual
  harness. It clicks the real Messages sidebar row, waits for the
  fixture-backed `/api/v1/conversations` request, and verifies a selected
  Messages row plus populated `ConversationsListView` content from a
  deterministic unread direct-message fixture. Mark-read/delete/favorite/bookmark
  mutations, stream updates, lists, explore, and exact conversation row visual
  parity remain open.
- 2026-06-20: Added `seeded-authenticated-messages-detail` coverage. It opens
  the real upstream Messages tab, clicks the deterministic conversation row,
  verifies the fixture-backed `POST /api/v1/conversations/conversation-1001/read`
  and `GET /api/v1/statuses/conversation-status-1001/context` calls, then gates
  the navigated `ConversationDetailView` against the Back button, selected
  Messages sidebar row, detail header/date area, reply composer, and content
  surface. Remaining conversation gaps are richer threaded fixture content,
  delete/favorite/bookmark/context menu mutations, stream updates, and exact
  visual parity of the conversation row/detail typography.
- 2026-06-19: Added `seeded-authenticated-list` to the upstream visual harness.
  It waits for IceCubes' app-dependency bootstrap to fetch `/api/v1/lists`,
  clicks the real `Quill Core` sidebar row, waits for
  `/api/v1/timelines/list/list-quill-core`, and verifies the selected row plus
  populated list timeline content. The reusable fixes behind this were in
  SwiftOpenUI rather than IceCubes source: GTK standalone lifecycle now runs
  stacked `.task` modifiers attached to the same root widget, and
  environment-injected observable object reads are wired so global/shared
  observable mutations can repaint sidebar content. List edit/create/delete
  flows and exact list-row visual parity remain open.
- 2026-06-20: Added `seeded-authenticated-list-refresh` to the same harness.
  It opens the real `Quill Core` list route through the shared sidebar helper,
  sends the same Ctrl-R refresh shortcut used by Home/Notifications/Messages,
  waits for another `/api/v1/timelines/list/list-quill-core` request, and
  reuses the authenticated List visual validator so list refresh remains a
  first-class Linux CI route.
- 2026-06-20: Added `seeded-authenticated-list-pagination` coverage. It opens
  the real list route, waits for the fixture-backed automatic
  `/api/v1/timelines/list/list-quill-core?max_id=list-9002` pagination request,
  and revalidates the populated List surface afterward.
- 2026-06-19: Added `seeded-authenticated-explore` to the upstream visual
  harness. It clicks the real Explore sidebar row, waits for fixture-backed
  `/api/v1/suggestions`, `/api/v1/trends/tags`,
  `/api/v1/trends/statuses`, and `/api/v1/trends/links` requests, and verifies
  the selected Explore row plus populated quick-access, trending hashtag, and
  suggested/account content regions. Search entry/results, quick-access
  destination clicks, pagination, lists, and exact Explore visual parity remain
  open.
- 2026-06-19: Added `seeded-authenticated-explore-links` to cover the first
  Explore quick-access destination. The smoke opens the real Explore tab,
  clicks the real News/Trending Links quick-access button, and verifies that
  `RouterPath` pushes into a populated `TrendingLinksListView` while keeping
  the Explore sidebar row selected. Link pagination, tap-through to link
  timelines/browser handling, and exact card visual parity
  remain open.
- 2026-06-19: Added `seeded-authenticated-explore-posts` to cover the Trending
  Posts quick-access destination. The smoke opens the real Explore tab, clicks
  the real Trending Posts button, and verifies that `RouterPath` pushes into a
  populated `TimelineView(.trending)` while keeping the Explore sidebar row
  selected. The root Explore screen already fetches `/api/v1/trends/statuses`,
  so the route smoke asserts the post-click pixels instead of requiring an
  extra fetch. Status detail from the pushed timeline, pagination, refresh, and
  exact row visual parity remain open.
- 2026-06-19: Added `seeded-authenticated-explore-tags` to cover another
  Explore quick-access destination. The smoke opens the real Explore tab,
  verifies its fixture-backed data load, clicks the real Trending Tags
  quick-access button, and verifies that `RouterPath`/`NavigationStack(path:)`
  push into a populated `TagsListView` while keeping the Explore sidebar row
  selected. Search entry/results, the other quick-access destinations,
  pagination, lists, and exact Explore visual parity remain open.
- 2026-06-19: Added `seeded-authenticated-explore-suggested-users` to cover the
  next Explore quick-access destination. The smoke opens the real Explore tab,
  clicks the real Suggested Users quick-access button, waits for the
  fixture-backed suggested-account relationship lookup, and verifies that
  `RouterPath` pushes into a populated `AccountsListView` while keeping the
  Explore sidebar row selected. Search entry/results, News/links, Trending
  Posts, pagination, account-row mutations, and exact Explore visual parity
  remain open.
- 2026-06-19: Added `seeded-authenticated-explore-search` and fixed GTK
  `.searchable(..., placement: .navigationBarDrawer(displayMode: .always))`
  so the search entry and scopes stay visible when IceCubes is not actively
  presenting search. The smoke opens the real Explore tab, types `quill` into
  the SwiftUI search field, waits for fixture-backed `/api/v2/search` plus
  account relationship requests, and verifies populated account/tag/status
  search results. News/links, Trending Posts, pagination, search scope
  switching, account-row mutations, and exact Explore visual parity remain
  open.
- 2026-06-17: Fixed GTK `ForEach` row state identity for flattened keyed rows
  and added generic `TabView` sidebar selected styling. The authenticated Local
  route now replaces placeholder `StatusRowView` state with the fixture-backed
  Local timeline rows, and the selected sidebar row is visibly highlighted by
  the renderer rather than by an app-specific workaround. The IceCubes visual
  harness was recalibrated to the current sidebar geometry and the verifier now
  detects the blue selected-row fill. Verification: focused source hygiene,
  seeded authenticated Local, Trending, Federated, and Notifications Docker/GTK
  visual smokes passed.
- 2026-06-17: Added `seeded-authenticated-status-detail` to the upstream
  IceCubes GTK visual harness and Linux CI row. The smoke clicks a real
  fixture-backed home timeline status, waits for the app's
  `/api/v1/statuses/1003` and `/api/v1/statuses/1003/context` detail fetches,
  and verifies a populated status-detail surface instead of treating timeline
  load as sufficient. This covers first-level row navigation through IceCubes'
  real `StatusRowViewModel.navigateToDetail()` path; deeper context threads,
  row mutations, refresh, pagination, and exact macOS visual parity remain open.
- 2026-06-17: Extended authenticated status-detail coverage to real action
  mutations. `seeded-authenticated-status-detail-favorite` clicks IceCubes'
  real favorite button, waits for `POST /api/v1/statuses/1003/favourite`, and
  verifies the favorited star/summary repaint. `seeded-authenticated-status-detail-boost`
  adds the matching `POST /api/v1/statuses/1003/reblog` fixture path and pins
  the boosted tint plus boosts summary row. `seeded-authenticated-status-detail-bookmark`
  now clicks the secondary bookmark action, waits for a fixture-backed bookmark
  mutation on the visible detail status/action row, and verifies the bookmarked
  accent repaint. These smokes cover `StatusDataController.toggleFavorite`,
  `toggleReblog`, and `toggleBookmark` through the upstream
  `StatusRowActionsView`; menu visual chrome, pagination, and exact macOS
  visual parity remain open.
- 2026-06-19: Stabilized authenticated route repaint by giving stateless GTK
  composite bodies a deterministic state namespace, then added authenticated
  composer-open, composer-text-entry, and composer-submit smokes. `seeded-authenticated-composer`
  now clicks the real IceCubes compose toolbar button, waits for the
  value-window sheet, focuses the editor surface without crashing on
  `GtkTextView`, and verifies the sheet pixels instead of accepting a stale main
  timeline capture. `seeded-authenticated-composer-type` types into the real
  editor and verifies visible body text, settled send-button toolbar chrome, and
  the updated character counter. The same pass moved GTK `TextEditor` binding
  writes onto the debounced text-update path already used by `TextField`, fixing
  fast-typing character loss during rebuild/focus restoration. It also added
  Mastodon notification policy/custom-emoji fixtures and SF Symbol mappings for
  the composer toolbar glyphs. Verification: Docker/GTK authenticated shell,
  Trending, Local, Federated, Notifications, Composer, and typed Composer visual
  smokes passed locally with no URL fixture misses or missing-symbol debug
  lines. `seeded-authenticated-composer-submit` now clicks the real send button,
  waits for `POST /api/v1/statuses`, verifies the composer window dismisses back
  to the authenticated shell, and uses a normal Mastodon status fixture response
  for the posting service. `seeded-authenticated-status-detail-reply` clicks the
  real reply action on a status detail and verifies that the upstream composer
  opens with reply context under GTK. `seeded-authenticated-status-detail-quote`
  opens IceCubes' real boost/quote menu, clicks the Quote row, and verifies that
  the upstream quote composer opens through the same status-detail action path.
  Autocomplete, attachment import, drafts, post-result toast/detail routing,
  menu pixel parity, and exact compose visual parity remain open.
- 2026-06-19: Added `seeded-authenticated-settings` to the upstream IceCubes GTK
  visual harness and Linux CI row. The smoke clicks the real Settings sidebar
  row from a seeded authenticated session and verifies the selected row, title
  chrome, populated Settings `Form`, and absence of stale timeline avatar rows.
  The same pass added a fixture-backed `/api/v2/instance` response so Settings
  exercises IceCubes' real `CurrentInstance.fetchCurrentInstance()` path, and
  mapped SF Symbol `server.rack` to the bundled Material `dns` glyph so the
  Instance row does not fall back to the missing-icon placeholder. Deeper
  Settings destinations and setting mutations remain open.
- 2026-06-19: Added `seeded-authenticated-settings-display`, extending the
  Settings smoke from root navigation into the real Display Settings
  `NavigationLink`. The flow scrolls the upstream Settings form to the General
  section, clicks Display Settings, and verifies the pushed Display form
  renders a stacked control surface instead of the stale root account/log-out
  rows. This starts child Settings coverage; picker/toggle mutation persistence
  and the remaining Settings destinations are still open.
- 2026-06-16: Added Linux non-repeating `UNTimeIntervalNotificationTrigger`
  delivery. Scheduled local notification requests now start as pending, move to
  delivered when the timer fires, and present through the QuillKit desktop
  backend. Durable OS scheduling and remote push remain incomplete.
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
- 2026-06-16: Added a Linux `ASWebAuthenticationSession` callback-file bridge
  for desktop URL-scheme helper processes. The running app can monitor a
  configured file and consume the newest callback URL line while ignoring stale
  contents present before the session starts. Verification: Docker/GTK
  `webAuthenticationSessionConsumesCallbackFileUpdates` passed.
- 2026-06-16: Promoted SwiftUI `listRowInsets` and `listRowSeparator` from
  inert compatibility no-ops into reusable SwiftOpenUI row metadata and taught
  the GTK `List`/`Form`/`Section` renderers to consume it. Live IceCubes
  Add Account captures now keep suggestion rows inset and separated instead of
  painting form content flush to the left edge. Remaining visible gaps on this
  screen include font fallback boxes for broader scripts and titlebar/control
  chrome. Verification: `SourceHygieneTests` passed locally and the Docker/GTK
  `icecubes-linux-app` product rebuilt successfully before the screenshot
  capture script hit a missing `file` utility in the container.
- 2026-06-16: Added a real upstream `icecubes-linux-app` GTK visual smoke path
  (`scripts/icecubes-linux-visual-check.sh`) and Linux CI artifact row. The
  smoke builds the upstream product with `QUILLUI_ICECUBES=1`, launches it
  under Xvfb, captures the Add Account window, and validates that the title,
  cancel action, populated suggestion text, stats, and media/placeholder rows
  render. This gives IceCubes parity work a real-app screenshot artifact
  instead of relying only on the smaller `quill-icecubes` fixture app.
- 2026-06-16: Extended the IceCubes GTK visual smoke with
  `QUILLUI_ICECUBES_VISUAL_SCROLL_CLICKS` so the Add Account sheet can be
  captured after real scroll-wheel interaction. A non-skip Docker run installed
  `fonts-noto-cjk`, scrolled the upstream suggestions list, and captured
  rendered Japanese copy for `mstdn.jp` with no top-left sheet artifact.
- 2026-06-16: Added an opt-in upstream Add Account interaction capture:
  `QUILLUI_ICECUBES_VISUAL_INTERACTION=type-instance` clicks the focused
  instance field, sends xdotool key events for `mastodon.social`, waits for the
  real IceCubes async detail fetch, and verifies the transitioned state with the
  `icecubes-linux-add-account-instance` screenshot product. The selected-state
  verifier requires typed text, the Sign in row, the populated Instance info
  table, and rejects stale suggestion media. This pins TextField binding,
  onChange, async state refresh, conditional layout, and sheet repaint behavior
  as first-class Linux parity coverage.
- 2026-06-16: Added a file-backed QuillWorkspace URL-open bridge and an
  upstream `sign-in-open` IceCubes smoke. The app now reaches the real
  Mastodon OAuth browser boundary from the Add Account sheet in Linux CI:
  the smoke types `mastodon.social`, clicks Sign in, lets
  `MastodonClient.oauthURL()` register an OAuth app, and verifies the emitted
  `/oauth/authorize` URL has `response_type=code`, the `icecubesapp://`
  redirect URI, a client id, and the `read write follow push` scopes. This does
  not complete login; token exchange/credential verification still require a
  valid user callback code or a testable Mastodon auth backend.
- 2026-06-16: Added `icecubes-seed-account`, a Linux-only harness executable
  that uses IceCubes' real `AppAccount`/`OauthToken` persistence path to seed a
  deterministic account into the JSON-backed KeychainSwift store. The visual
  script now has `QUILLUI_ICECUBES_VISUAL_INTERACTION=seeded-authenticated-shell`
  to launch the upstream app past the Add Account sheet and verify authenticated
  shell chrome under CI. The verifier pins the compact `ToolbarTitleMenu`
  rendering so menu contents cannot leak into the timeline body again. This is
  still fake-token shell coverage; valid-token callback exchange, credential
  verification, home timeline rows, and row interactions remain open.
