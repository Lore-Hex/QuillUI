# IceCubes-on-Linux — session handoff (2026-06-10)

## UPDATE (later 2026-06-10 session)

- **GTK Cancel-dismiss bug: FIXED + verified.** Root cause: this branch's
  vendored renderer predated main's 8 swarm sheet commits ("Let GTK root sheet
  dismiss via binding", "Defer GTK sheet dismissal teardown", …) — the sheet
  behavior layers in via `scripts/patch-swiftopenui-gtk-css.sh`. Merged
  origin/main (commit 39ca4c8a; 8 conflicts — UIKitShim keeps the
  extension-over-QuillUIKit structure, AVFoundation/State/button-action paths
  take main's), re-applied the patch script (it ABORTS on unrecognized shapes;
  had to delete this branch's dead `gtkResolveOrQueueScrollTo` first), deduped
  both-sides-committed decls (scroll system / gtkScheduleOnAppear / gtkDebugLog,
  commit 172345b1). Smoke-verified: xdotool click at (80,344) now dismisses the
  Add Account sheet (`.tmp-ice-c1-before.png` → `.tmp-ice-c2-after-cancel.png`).
  Repro loop: `bash /work/.tmp-ice-cancel-smoke.sh` in quillui-signal-build.
- **Qt wiring LANDED (commit f4bf37fb):** `iceCubesLinuxGraphEnabled =
  gtk || (qt && QUILLUI_QT_GENERIC)` widens the 3 gates; under qt-generic the
  qt branch APPENDS its graph to the common shim graph (name-filtered) instead
  of resetting; SwiftUI shim backend dep is conditional (BackendQt vs
  BackendGTK4). dump-package passes in qui-appkit-qt for plain-qt AND
  qt-generic; flag-off qt reset is byte-identical. First qt build reached
  706/1118 jobs. ⚠️ GRDB `canImport(Combine)` race: GRDB sees the Combine shim
  .swiftmodule mid-build but not OpenCombine's COpenCombineHelpers module map →
  "missing required module". Deterministic workaround in flight: fresh scratch,
  `swift build --target GRDB` FIRST (before the Combine shim exists), then the
  product. If that holds, bake it into the qt build loop.
- Next: qt build verdict → launch smoke (QT_QPA_PLATFORM=xcb); then parity P1
  (toolbar stacked-pickers artifact at top of window — visible in both smokes).


Mission (from Joseph): get the REAL upstream IceCubesApp **fully running** on
Linux, **on BOTH backends — GTK (SwiftOpenUI/GTK4) and Qt (generic BackendQt)**.
Work in THIS worktree: `/Users/jperla/claude/QuillUI-icecubes-build`,
branch `icecubes/linux-app` (pushed; 4 commits hold the previously-uncommitted
431-file WIP).

## State: what is PROVEN working (verified this session)

- The real upstream app **builds, links, launches** on aarch64 Linux (GTK):
  binary `.build-icecubes-app/aarch64-unknown-linux-gnu/debug/icecubes-linux-app`.
- BUILD LOOP (verified green, ~5s incremental):
  `docker run --rm -v /Users/jperla/claude/QuillUI-icecubes-build:/work quillui-signal-build bash -c 'cd /work && QUILLUI_LINUX_BACKEND=gtk ./scripts/swiftpm-preserve-package-resolved.sh swift build --disable-index-store --scratch-path .build-icecubes-app --product icecubes-linux-app'`
  (`--disable-index-store` is REQUIRED — apt clang rejects `-index-store-path`.)
- RUN LOOP (verified): same image + `apt-get install -y xdotool openbox`, then
  Xvfb :98 1280x900, openbox, run binary, `import -window root shot.png`.
  Live captures: `.tmp-ice-1-launch.png`, `.tmp-ice-2-after-cancel.png`.
- What renders: logged-out timeline shell + **Add Account sheet with LIVE
  instances.social data** (real mastodon.social banner images, "3.3M users ·
  177M posts", localized strings, Instance URL field). Real async images WORK.
- Status doc with P0/P1/P2 ladder: `docs/icecubes-behavior-parity.md`
  (prior session's estimates: compile 100%, runnable-graph ~97%, behavior
  50-60%, visual parity 20-30%).

## Top GTK behavior blocker (reproduced this session)

**Add Account sheet Cancel does NOT dismiss** (clicked via xdotool at real
coords (80,344) on 1280x900, with openbox running — sheet stays). Matches the
parity doc's known gap "modal dimming and hit-testing". Suggestion ROWS were
documented clickable, so clicks reach sheet content — suspicion: the sheet
header Cancel button action or `@Environment(\.dismiss)` inside root-overlay
sheets isn't wired to remove the overlay. Code: root-overlay sheet path in
`third_party/SwiftOpenUI/Sources/Backend/GTK4/Rendering/GTKRenderer.swift`
(gtkCreateSheetOverlay / gtkShouldRenderSheetInRootOverlay / SheetModifierView).
NEXT: verify with a suggestion-row click (real coords ~(400,560)), then trace
Cancel's action → dismiss env → overlay removal.

## Dual-backend wiring (user requirement) — IN FLIGHT

DONE (uncommitted → committed in this save): `Sources/SwiftUIShim/AppRuntime.swift`
is now backend-agnostic: `#if canImport(BackendQt) QtBackend().run(Self.self)
#elseif canImport(BackendGTK4) GTK4Backend().run(Self.self)`. Qt entry pattern
mirrors `Sources/QuillQtGenericSmoke/main.swift` (`QtBackend().run(App.self)`,
gated `canImport(BackendQt)`).

Manifest structure (mapped this session; Package.swift is 3,173 lines):
- `var products` L230, `var targets` L657 — the BIG shim region (L657–2160,
  incl. SwiftUI shim L1931, UIKit L2047, Nuke/NukeUI L2083-4, the
  `signalAppleFrameworkShims` loop L1719-1746) is **common Linux graph, NOT
  backend-gated** (the gtk-only block at L313 is tiny, 313–315).
- Qt graph block: L2203–2432; the **generic SwiftOpenUI→Qt backend** sub-block
  (`quillUIQtGenericEnabled`, env `QUILLUI_QT_GENERIC=1`) at L2334–2400 adds
  SwiftOpenUI package dep + CQtBridge + BackendQt + quill-qt-generic-smoke.
- IceCubes gates to widen: L416 (`QuillIceCubesCore` real-Models),
  L2163 (SwiftSoup package dep), **L2726–3163 (the whole upstream graph +
  `icecubes-linux-app` product — currently `&& quillUILinuxBuildBackend == .gtk`)**.
- `SwiftUI` shim target (L1931) hard-depends on
  `.product(name: "BackendGTK4", package: "SwiftOpenUI")` + uses
  `quillUIGTKSwiftImporterSettings` (already `[]` under qt). PLAN: make the
  backend dep conditional:
  `let swiftUIShimBackendDependency: Target.Dependency = (quillUILinuxBuildBackend == .qt && quillUIQtGenericEnabled) ? "BackendQt" : .product(name: "BackendGTK4", package: "SwiftOpenUI")`
  — note BackendQt is a TARGET in this package (string dep), BackendGTK4 is a
  PRODUCT of third_party/SwiftOpenUI.
- OPEN QUESTION (was mid-investigation): how the plain-qt manifest currently
  tolerates SwiftUI→BackendGTK4 when SwiftOpenUI isn't in qt's package deps —
  check whether plain `QUILLUI_LINUX_BACKEND=qt swift build` even evaluates with
  the common region present, or whether allPackageDependencies trimming makes it
  error only on USE. Empirically qt CI is green today, so evaluation passes;
  just ensure the conditional dep doesn't regress plain qt.
- Dependency closure of IceCubesLinuxApp: 82 targets (analysis script output in
  this doc's sibling `icecubes-qt-shim-defs-extracted.txt` — 34 verbatim shim
  target definitions extracted for reference; 6 more (AuthenticationServices,
  CoreImage, ImageIO, NaturalLanguage, StoreKit, UserNotifications) come from
  the `signalAppleFrameworkShims` loop L1719). Since the shim region is COMMON,
  most targets already exist under qt — the qt wiring may need only:
  (1) widen the three gates to `gtk || (qt && quillUIQtGenericEnabled)`,
  (2) the conditional SwiftUI backend dep,
  (3) `targets += ...filter { !existingNames.contains($0.name) }` guard if any
  collision with qt-graph targets (KeychainSwift etc. — check; KeychainSwiftTests
  exists in qt graph),
  (4) SwiftSoup gate widen (L2163).
- Qt build env: image `qui-appkit-qt:latest` (running container `qui-wg-qt`
  proves it) has swift+qt6. Build:
  `QUILLUI_LINUX_BACKEND=qt QUILLUI_QT_GENERIC=1 swift build --disable-index-store --scratch-path .build-icecubes-app-qt --product icecubes-linux-app`
  (separate scratch path to avoid cross-backend cache poisoning — see stale-
  module cascade lesson in quillui-signal LESSONS.md STEP K).
- EXPECT: BackendQt renderer is younger than GTK4 backend (it was the
  "generic spike" + Enchanted parity work) — after compile, a long behavior
  tail on Qt is likely. GTK stays lead; Qt must build + launch-smoke first.

## Priority order on resume

1. Finish Qt wiring (above) → `icecubes-linux-app` builds under qt-generic →
   launch smoke under Xvfb (QT_QPA_PLATFORM=xcb) + screenshot.
2. GTK sheet hit-test/dismiss bug (Cancel) — unblocks ALL interaction flows.
3. Then parity-doc P1 ladder: timeline rendering behind the sheet, toolbar
   stacked-pickers artifact (top of window), auth/browser sign-in flow
   (`AuthenticationServices` web-auth shim → xdg-open + callback), media flows.
4. Keep committing in slices on `icecubes/linux-app`; never leave >a-day WIP
   uncommitted (431-file lesson).

## Quick context pointers

- Strategy + per-app honest %: this session's analysis lives in the QuillSignal
  conversation; IceCubes UI-experience parity ≈ 3% before this push, target =
  "fully running, both backends, 100% original code".
- Signal Track B (separate agent) + Enchanted (separate effort) — don't touch.
- The repo-wide porting playbook: docs/porting-upstream-apps.md.
- Build images: quillui-signal-build (gtk, has all deps), qui-appkit-qt (qt6).


---

## Session addendum (2026-06-10, later session)

**Both resume priorities LANDED:**

1. **Qt wiring DONE** (commit f4bf37fb): `iceCubesLinuxGraphEnabled = gtk ||
   (qt && QUILLUI_QT_GENERIC)` widens the three gates; under qt-generic the qt
   branch APPENDS its native graph to the common shim graph (name-filtered)
   instead of resetting products/deps/targets; the SwiftUI shim's backend dep
   is conditional (`BackendQt` target vs `BackendGTK4` product). Plain-qt reset
   byte-identical. **`icecubes-linux-app` BUILDS + LINKS under Qt** (92.8MB).
   Build gotcha: GRDB's `canImport(Combine)` races our Combine shim → fresh
   scratch must `swift build --target GRDB` FIRST, then the product
   (deterministic; "missing required module 'COpenCombineHelpers'" otherwise).
   Qt launch reaches window + root-content build; first crash was
   OnChangeTwoArgView's fatalError → fixed by (a) OnChange{,TwoArg}View
   QtRenderable extensions, (b) qtRenderView now degrades UNHANDLED PrimitiveViews
   to an empty placeholder + `[backendqt] unhandled primitive …` trace, so one
   launch enumerates every missing Qt renderable (no more crash-per-primitive).

2. **GTK sheet Cancel dismiss FIXED** — root cause was a STALE gtk-css patch
   application: this branch's renderer predated main's 8 swarm sheet commits
   (`Let GTK root sheet dismiss via binding`, `Defer GTK sheet dismissal
   teardown`, …). Merged origin/main (commit 39ca4c8a; kept this branch's
   UIKitShim extension-over-QuillUIKit structure, took main's service-backed
   AVAudioSession / State wiring refactor / button-action scheduling),
   re-applied `scripts/patch-swiftopenui-gtk-css.sh`, deduped both-sides-kept
   decls (commit 172345b1: scroll system, gtkScheduleOnAppear, gtkDebugLog).
   PROOF: `.tmp-ice-c1-before.png` (sheet open) → `.tmp-ice-c2-after-cancel.png`
   (sheet dismissed; logged-out timeline shell + first status-row fragments).
   ⚠️ patch-script lesson: it ABORTS on unrecognized shapes — delete this
   branch's dead/stale copies first (it expected exact stale text for
   gtkResolveOrQueueScrollTo and bailed mid-run, leaving later steps unapplied).

**Next:** (1) qt smoke gap list → implement the high-traffic missing Qt
renderables; (2) GTK timeline row rendering behind the dismissed sheet (two
floating row fragments visible — layout rung); (3) parity-doc P1 ladder.
