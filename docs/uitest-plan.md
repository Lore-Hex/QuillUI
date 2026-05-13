# QuillUI UITest Plan (2026-05-11)

User-raised bar across every app:

1. **Compile straight completely from source** — each app's upstream
   source tree compiles directly through the QuillUI compatibility
   layer.
2. **Real UITests on macOS** that drive real actions across many
   features + screenshot the result.
3. **Identical Linux parity** — the same flows run + screenshot
   identically through the GTK4 backend.

## Current state (CP106+)

| App         | Compile from source | macOS UITest | Linux GTK smoke |
|-------------|---------------------|--------------|-----------------|
| Enchanted   | ✅ (CP80)           | —            | ✅ generated + native matrix |
| IceCubes    | — (iOS-pinned)      | —            | ✅ baseline (CP104)        |
| NetNewsWire | — (Shared/Mac coupling) | —        | ✅ baseline (CP104)        |
| CodeEdit    | — (SwiftLintPlugin) | —            | ✅ baseline (CP104)        |
| Signal      | — (libsignal stack) | —            | ✅ baseline (CP104)        |
| Telegram    | — (MTProto stack)   | —            | ✅ baseline (CP104)        |
| IINA        | — (libmpv binding)  | —            | ✅ baseline (CP104)        |
| WireGuard   | side target         | —            | ✅ baseline matrix         |

The per-app backend smoke/profile roster now lives in
`scripts/quillui-backend-products.sh backend-apps`, so Linux visual and
profile coverage iterate the same user-facing app list:
`quill-enchanted`, `quill-enchanted-upstream-slice`,
`quill-icecubes`, `quill-netnewswire`, `quill-codeedit`,
`quill-signal`, `quill-telegram`, `quill-iina`, and
`quill-wireguard`. The older `scripts/linux-gtk-app-products.sh`
path delegates to the same helper for compatibility.

The six fixture app GTK smokes passed baseline (size + mean
brightness + stddev) on the first rollout (Linux CI run
25687405190); promoted off `continue-on-error: true` to hard-gated
in CP105 (e8acd09). CP106 widens the same hard gate to the native
Enchanted products and the WireGuard side target through the shared
matrix. Every Quill app product is now expected to paint something
non-blank on the GTK4 backend out of the box — not just
compile-green, but render-green.

Per-app fixture shells are compile-green hard-gated (CP82–CP89);
per-app-core test targets cover the pure-Foundation surface
(CP90–CP99); QuillUI itself has tests (CP103). What's missing is
**rendering-time** coverage that proves the SwiftUI views actually
paint correctly on both backends.

## Phase 1 — Linux GTK visual smoke for each fixture shell

For every Quill app, add a Linux CI step that:

- Builds and launches the Quill\*App executable under Xvfb
- Waits `${QUILLUI_SMOKE_SECONDS:-4}` seconds
- Screenshots the GTK window via `import` / `gnome-screenshot`
- Runs `scripts/verify-backend-screenshot.py` against the PNG

Reuse `scripts/linux-backend-visual-check.sh` (already proven for
Enchanted's `quill-chat-linux` target) — accepts the app product
name as `${2}`. Source the app list from
`scripts/quillui-backend-products.sh backend-apps` instead of
hard-coding products in CI. The verifier
`scripts/verify-backend-screenshot.py` needs
per-app landmark predicates; CP78 added Enchanted's generated-app
landmarks, while the root app shells still use the baseline
nonblank verifier until each gets its own small predicate block.
Backend launch fixtures use the same visual runner from
`scripts/quillui-backend-products.sh smoke-products`, which keeps the
GTK and Qt launch surfaces under the same screenshot contract while the
native Qt renderer is being brought up. Generated external app products use
`scripts/quillui-backend-products.sh generated-app-matrix`, so Quill Chat's
temporary SwiftPM package is also requested through both GTK and Qt. Visual and
interaction runners share `scripts/quillui-linux-backend-smoke-lib.sh`, so
package setup, executable resolution, and generated Quill Chat fixture state
stay identical between GTK and Qt smoke paths.

For interaction tests, reuse `scripts/linux-backend-interaction-check.sh`
(also proven for Enchanted) which drives the running app with
`xdotool`. Per-app interactions to start with:

- Signal: click second sidebar conversation, verify timeline changes
- Telegram: click "Work" folder pill, verify sidebar filters
- IINA: click second playlist row, verify canvas title changes
- CodeEdit: click `Package.swift` in the file tree, verify editor
  loads non-empty contents
- IceCubes: scroll the timeline once
- NetNewsWire: click the second article in the sidebar, verify the
  detail pane updates

## Phase 2 — macOS rendering snapshots

SwiftPM doesn't ship XCUITest. Two viable approaches:

**Option A: swift-snapshot-testing**
`pointfreeco/swift-snapshot-testing` is already a transitive dep
via `sqlite-data` → `swift-perception` → … (or close to it; needs
a Package.resolved scan). Pattern:

```swift
import SnapshotTesting
import SwiftUI

let view = QuillSignalContentView()
assertSnapshot(of: view, as: .image(layout: .fixed(width: 900, height: 700)))
```

Failures emit a diff PNG against the reference image stored under
`Tests/QuillSignalCoreTests/__Snapshots__/`. Pure-SwiftPM, runs in
`swift test`.

**Option B: ViewInspector**
View-tree assertions without rendering pixels. Good for behavioral
checks ("after `send()`, the timeline has one more bubble") but no
visual regression coverage.

**Recommended: Option A** — gives both image regression coverage
AND drives the same `swift test` pipeline that Linux CI already
uses, so the same .swift file can mount the snapshot on macOS and
delegate to the existing Linux GTK smoke on Linux via `#if`.

## Phase 3 — Compile from upstream source

App-by-app, sequenced by upstream-blocker tractability:

1. **CodeEdit** — Fix SwiftLintPlugin trip on SwiftPM 6 (drop the
   plugin from the vendored CodeEditSymbols; it's a prebuild-time
   lint, not a runtime requirement). Then enable the existing
   `CodeEditUpstream` target.
2. **NetNewsWire** — Detangle the `Shared/Mac` coupling: extract
   `Shared/` files that don't reach into `Mac/` into a Linux-safe
   target, leave the rest as macOS-only.
3. **IceCubes** — Fork `Models` + `NetworkClient` upstream to drop
   the iOS(.v18) + visionOS(.v1) platforms pin; vendor the fork
   under `.upstream/icecubesapp/`. Already proven: the local
   IceCubesAPI re-implementation tracks the upstream shape exactly.
4. **IINA** — Stub libmpv via a Linux-side adapter; the app shell
   compiles even when playback is unavailable.
5. **Signal-iOS** — Largest lift. Probably needs a multi-quarter
   push to detangle libsignal / RingRTC / GRDB.
6. **Telegram-Swift** — Similar scale; bespoke MTProto deps.

## Slice ordering rule

Each app's compile-from-source milestone is its own multi-slice
port. Don't pivot to the next app's compile-from-source work
until the prior app's compile + macOS-UITest + Linux-UITest trio
is green-gated.

## Acceptance criteria per app

App is "done" when ALL of:
- [ ] `swift build --target QuillFoo` compiles the upstream Foo
      source through QuillUI on both macOS and Linux as a hard
      gate
- [ ] At least one macOS image-snapshot test exists covering a
      meaningful flow and runs as a hard gate
- [ ] The same flow renders identically on Linux GTK via
      `scripts/linux-backend-visual-check.sh` and is hard-gated
- [ ] At least one interaction (click / text input) is exercised
      via `scripts/linux-backend-interaction-check.sh` and produces a
      second screenshot
