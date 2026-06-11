# SolderScope conformance campaign — notes

Goal: **[rjwalters/SolderScope](https://github.com/rjwalters/SolderScope) at 100% on GTK** —
the real macOS SwiftUI USB-microscope viewer, source UNMODIFIED, fully working on
QuillOS Linux. First community-requested app. Owner: main-loop agent; surfaces
parallelized to the swarm via the issues below.

## Status ladder

| Rung | State | Work |
|---|---|---|
| 1. Compiles unmodified | ~80% (152 → ~124 unique errors) | #506 AVFoundation surface, #507 AppKit members, #508 SwiftUI chrome, #512 @MainActor AppKit tree, #513 @MainActor View.body |
| 2. Launches + renders | in progress (main agent) | NSViewRepresentable GTK mount: GtkDrawingArea-backed custom-draw NSView + Cairo-backed CGContext; #510 CALayer painting |
| 3. Live camera | spec'd | #515 V4L2 AVCaptureSession backend |
| 4. Recording/snapshots | queued | AVAssetWriter→encoder; NSBitmapImageRep→PNG (part of #507 acceptance) |
| 5. Pixel-parity vs macOS | later | QuillPaint mac-reference pipeline once 2–4 are real |

Wire it: `scripts/fetch-upstream.sh solderscope` → gated target `QuillSolderScope`
(inert in CI). Measure: `swift build --scratch-path .build-linux --disable-index-store
--target QuillSolderScope`.

## Decisions log

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

## Verification recipes

- Compile measure: see above; unique-error count =
  `grep -E "^/qui/.upstream.*error:" log | sed -E 's/:[0-9]+:[0-9]+.*//' | sort -u | wc -l`
- Tests in container: `CC=/usr/bin/clang-17 swift test --scratch-path .build-linux`
  (NO --disable-index-store — Linux test discovery needs the store; clang-17 is the
  Swift-fork clang, apt's clang-18 lacks -index-store-path). Park `.upstream/<app>`
  dirs first — `swift test` builds gated app targets too.
- GTK screenshot smokes: existing headless-Xvfb harness (see GTK smoke targets).
