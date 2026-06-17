# SolderScope conformance campaign — notes

Goal: **[rjwalters/SolderScope](https://github.com/rjwalters/SolderScope) at 100% on GTK** —
the real macOS SwiftUI USB-microscope viewer, source UNMODIFIED, fully working on
QuillOS Linux. First community-requested app. Owner: main-loop agent; surfaces
parallelized to the swarm via the issues below.

## Status ladder

| Rung | State | Work |
|---|---|---|
| 1. Compiles unmodified | **Build green when fetched** | Gated `QuillSolderScope` product builds from the upstream source after the generic fetch/patch step; the remaining work is fidelity, not the old compile-error burn-down. |
| 2. Launches + renders + input | **GTK launch/input proven** (Xvfb launch/interaction smoke, custom NSView draw host, cursor rects, primary click/drag, scroll-wheel delivery, deterministic synthetic camera frame smoke, real SolderScope command-menu extraction, and Tests/QuillUITests/SolderScopeChromeConformanceTests.swift) | remaining: mac-reference visual delta closure, broader real-device gesture coverage, and toolbar/menu behavior beyond the currently smoke-driven shortcuts |
| 3. Live camera | partial | #515 V4L2 AVCaptureSession backend plus opt-in `QUILL_AVFOUNDATION_SYNTHETIC_CAMERA=1` fixture camera for deterministic CI/runtime smoke; remaining: real USB microscope/device matrix coverage |
| 4. Recording/snapshots | partial-real | `NSBitmapImageRep` writes real PNG/JPEG/TIFF data and `AVAssetWriter` can produce real `.mov` files through ffmpeg when present. CI now splits capture into a snapshot smoke and a recording-only smoke; the recording pass uses shortcut start/stop with bounded retries, waits for SolderScope's app-level `Recording started`/`Recording saved` logs, and rejects a lingering `REC` badge. Freeze and toolbar recording drivers remain opt-in diagnostics because freeze currently blacks the hosted camera view and rebuilt toolbar buttons can still miss synthetic pointer activation. Remaining: output-directory controls, freeze rendering, and full snapshot/record toolbar parity. |
| 5. Pixel-parity vs macOS | later | QuillPaint mac-reference pipeline once 2–4 are real |

Wire it: `scripts/fetch-upstream.sh solderscope` → gated target `QuillSolderScope`
(inert in CI). Measure: `swift build --scratch-path .build-linux --disable-index-store
--target QuillSolderScope`.

## Decisions log

- **2026-06-17 — Capture smoke must reject half-stopped recordings**:
  CI now runs snapshot and recording as separate interaction passes. The
  recording pass uses shortcut start/stop with bounded retries, waits for
  app-level `Recording started` and `Recording saved` logs before accepting the
  `.mov`, and rejects a lingering lower-left `REC` badge so an early `.mov`
  header can no longer masquerade as a completed stop/finalize path. Toolbar
  recording drivers remain opt-in diagnostics until rebuilt toolbar hit-testing
  is fixed in SwiftOpenUI GTK; freeze is also opt-in until its frozen hosted
  camera view keeps the current frame instead of rendering black.

- **2026-06-16 — Runtime smoke needs frames, not just a surviving no-camera UI**:
  SolderScope ignores zoom/pan until its hosted microscope view has an image
  size, so a no-camera interaction smoke only proved event delivery and app
  survival. AVFoundation now has an opt-in synthetic capture device
  (`QUILL_AVFOUNDATION_SYNTHETIC_CAMERA=1`) that appears through normal
  `AVCaptureDevice.DiscoverySession`, feeds BGRA `CMSampleBuffer`s through
  `AVCaptureVideoDataOutput`, and lets the interaction smoke verify visible
  microscope frame pixels after scroll/drag/double-click gestures. This is a
  deterministic runtime-fidelity fixture, not a substitute for the real USB
  camera matrix.

- **2026-06-16 — Snapshot smoke must not write to a developer Desktop**:
  Upstream SolderScope resolves snapshot output through
  `FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)`.
  On Linux corelibs this follows the passwd home, not `HOME`, so the smoke now
  auto-drives the `s` shortcut only when that Desktop is disposable (`/root`,
  `/tmp`, or the checkout). In that case it creates the directory, records the
  pre-run file count, presses `s`, and fails unless a new `SolderScope_*.png`
  appears.

- **2026-06-16 — Recording smoke must prove the real app shortcut**:
  The interaction smoke now applies the same disposable-Desktop policy to the
  `r` shortcut. In auto mode it requires ffmpeg, starts recording through
  SolderScope's command-menu shortcut, waits for synthetic capture frames,
  stops recording through the same shortcut, and fails unless a new finalized
  `SolderScope_*.mov` appears with a plausible QuickTime/MP4 `ftyp` box.
  AVFoundation also has a narrow real-time writer fallback: active video
  writers with `expectsMediaDataInRealTime` receive synthetic/V4L2 capture
  frames until the app manually appends frames, which lets the unmodified
  SolderScope checkout exercise its recording UI even though its
  `CaptureManager` does not call `RecordingManager.writeFrame`.

- **2026-06-16 — Hosted AppKit NSView input is backend-local, not app-local**:
  QuillAppKitGTK's custom `NSView` drawing host now installs GTK motion,
  primary-click, and scroll controllers. Those synthesize AppKit mouse,
  drag, scroll, and cursor-rect behavior for hosted views, which covers
  SolderScope's microscope zoom/pan/double-click-reset path without changing
  SolderScope source. Focused conformance: 25/25 SolderScope chrome tests.

- **2026-06-11 — Apple-faithful re-export topology** (PR #511): SwiftUI⊃AppKit
  (macOS SwiftUI does), UIKit⊃QuartzCore (iOS UIKit does), CoreGraphics⊃QuillFoundation
  CG types, SwiftUI⊃Combine. Unmodified app source can never compile without the
  SDK's import graph.
- **2026-06-11 — ObservableObject/Published are Combine's** (PR #511): SwiftOpenUI
  typealiases the canonical pair (real Combine on Apple / OpenCombine on Linux);
  re-render wiring via `objectWillChange`; storages stay GenerationTracked for
  Phase 6/7 gating; ObservedObject/StateObject/EnvironmentObject gained Apple's
  `projectedValue` wrappers. Killed the entire ambiguity/`$`-projection error class.
- **2026-06-11 — One canonical declaration per Apple name** (PR #511): twins are
  ambiguity bombs once both UI worlds are visible. UIApplication/UIScene →
  QuillUIKit only; flavor-free text-layout family → QuillFoundation
  (`NSTextLayoutShared.swift`); NSTextAttachment/NSTextStorage stay per-flavor
  (UIImage- vs NSImage-typed members) until the image types converge.
- **2026-06-11 — NSViewRepresentable owned by SwiftUI module** (PR #511), Apple
  shape: @MainActor, struct conformers, Coordinator plumbing. Rendering via a
  default `body` returning a GTK host view (NOT Body == Never — SwiftOpenUI's
  renderer walks body until it hits a `GTKRenderable`).
- **os link dep**: `canImport(os)` in swift-syntax binds to the os SHADOW module
  build-order-dependently; `swiftSyntaxOSLinkDependencies` (same hunk as PR #514)
  makes the link explicit. byName platform *conditions* do NOT work for this —
  SwiftPM validates target existence regardless of condition.

## Coordination

- PR #514 (functional QuartzCore: real CALayer model, UIView.layer, UIKit re-export)
  overlaps PR #511 on UIKitShim/Package.swift/QuillUIKit — whichever lands second
  rebases; the UIKit⊃QuartzCore + os-dep hunks are intentionally identical.
- Swarm: #506–#510, #512, #513, #515 all `loom:issue`d with acceptance criteria;
  workers claim via `codex:claimed`.

## Review-fleet round 2 outcomes (2026-06-11)

9 adversarially-sustained findings; must-fix bucket landed on the branch:
representable lifecycle (mount registry + updateNSView reuse + dismantle —
remount-per-render would have been ~30/s under a live camera), CG image-draw
orientation/alpha, canImport pins in the fork state core, StateObject lazy-
wiring guard, gtk/qt graph separation (QUILLUI_SWIFTUI_GTK_MOUNT). Deferred
with owners: NSTextAttachment/NSTextStorage flavor-neutral core (needed before
the next Signal rebase), vendoring the OpenCombineDispatch Scheduler guard
(prep rm-hack stands until then). Verified-safe: ViewHost.scheduleRebuild is
idle-coalesced, so willSet-time objectWillChange is sound.

## Ultracode workbench pattern

Workflow subagents cannot read the repo (sandbox) but CAN read `~/.claude` —
stage artifacts (diffs, error lists, app source, shim snapshots) into
`~/.claude/tmp/ss-workbench/` and fan agents out over those. Used for the
PR #511 adversarial review panel + SolderScope API-coverage audit.

## Verification recipes

- Compile measure: see above; unique-error count =
  `grep -E "^/qui/.upstream.*error:" log | sed -E 's/:[0-9]+:[0-9]+.*//' | sort -u | wc -l`
- Tests in container: `CC=/usr/bin/clang-17 swift test --scratch-path .build-linux`
  (NO --disable-index-store — Linux test discovery needs the store; clang-17 is the
  Swift-fork clang, apt's clang-18 lacks -index-store-path). Park `.upstream/<app>`
  dirs first — `swift test` builds gated app targets too.
- GTK screenshot smokes: existing headless-Xvfb harness (see GTK smoke targets).

## Backend abstraction audit (2026-06-12)

The Qt path is the discipline check: everything SolderScope added to shared
surfaces must stay toolkit-agnostic. Audit result:

- **Clean (zero GTK references)**: the SwiftUI chrome (SolderScopeChrome),
  `App.main()` (dispatches through QuillApp's backend registry), the V4L2
  capture stack, both rung-4 encoders (gdk-pixbuf is a standalone library,
  not GTK; ffmpeg is a process boundary), `Color`'s scheme spine, and
  `WindowGroup.quillHidesTitleBar` (a plain stored flag — each backend
  decides how to honor it; GTK maps it to an undecorated window).
- **Backend-local by design**: GTK_THEME selection lives in GTK4Backend;
  the representable mount is `QUILLUI_SWIFTUI_GTK_MOUNT`-gated; a Qt mount
  is the symmetric follow-up (NSViewRepresentable's non-GTK body traps with
  a clear message until it exists).
- **Known asymmetry, deliberate**: the `@MainActor` renderable-protocol
  shape (GTKRenderable/GTKMultiChildRenderable/GTKDescribable) was applied
  to the GTK backend only. SwiftOpenUI's Win32Renderable/WebRenderable need
  the same treatment when whole-protocol View isolation reaches their
  platforms — flagged here rather than edited blind (no Windows/Wasm
  compile available in this environment). The `MainActor.assumeIsolated`
  boundary pattern transfers as-is (Qt's and Win32's UI loops are also the
  main thread).
- **Qt parity surface**: `quill-solderscope` joins the qt graph via the
  generic native runtime catalog (snapshot facade, same as the other
  canonical apps). The REAL abstraction probe — compiling the unmodified
  app against the generic SwiftUI->Qt backend (`QUILLUI_QT_GENERIC=1`) —
  shares the GTK lane's zero-error surface by construction (all app-facing
  API lives in toolkit-neutral modules); its remaining gap is the Qt
  representable mount + BackendQt renderer coverage.
