# Porting macOS apps & libraries to Linux — lessons learned

Hard-won, transferable lessons for bringing real Apple/upstream code to Linux in
this repo. If you are an agent or contributor picking up a port (a flagship app,
a vendored framework, an Apple-framework clone), **read this first** — it will
save you the cycles we already spent.

## 0. The whole point: clone the missing macOS API into the *lib*, not the app

When verbatim Apple/upstream source hits an API that exists on macOS but not on
Linux (swift-corelibs-foundation, the SwiftUI/AppKit clones, …), the fix is to
**add that API to the clone**, so the source compiles unchanged — **not** to
work around it in the app or edit the vendored source.

- Right: `NSString.localizedStringWithFormat` is macOS-only → add it to the
  Foundation clone (`QuillFoundation`, `#if os(Linux)`). `AccountError` stays
  verbatim and *every* app that needs it is now covered.
- Wrong: rewrite the app's call to `String(format:)`. That hides the gap, leaves
  the source non-verbatim, and the next app hits the same wall.

Each gap you hit is a unit of work for the macOS-lib clone. Filling it is the
deliverable, not a detour.

## 1. "Full port" = faithful reimpl UI + verbatim-vendored frameworks

You cannot compile a real app (Enchanted, IceCubes, NetNewsWire) *verbatim* —
they pin recent iOS/macOS SDKs and lean on AppKit/UIKit surfaces. The model is:

- **Faithful reimplementation of the app UI** against SwiftOpenUI / QuillUI /
  the AppKit reimpl (the upstream-slice/adaptation pattern), **plus**
- **Real, verbatim-vendored frameworks** (`QuillRSParser`, `QuillArticles`,
  `QuillAccount`, …) with their original copyright headers.

Where you *can* compile verbatim framework source, do — and grow the clone for
each gap it surfaces.

## 2. Vendoring pattern

- Vendor real upstream source **verbatim**; keep the copyright headers.
- **Name the target to match the real import** so `import X` resolves to it
  (GNUstep-style source-recompile): a target named `RSWeb` for `import RSWeb`, a
  target named `AppKit` for `import AppKit`.
- **Forward dependencies** (a type the file references that isn't vendored yet)
  → trim them with a clear `// Quill bring-up:` note and restore verbatim once
  they land. Keep the *body* verbatim.
- To see clone gap-fills, a vendored file may need an extra `import QuillFoundation`
  (the Foundation gap-fills live there). That one-line link is acceptable; the
  body stays verbatim.

## 3. Where clone gap-fills live

- **Foundation:** `QuillFoundation` does `@_exported import Foundation` and adds
  missing Apple APIs under `#if os(Linux)` (see `Sources/QuillFoundation/FoundationLinuxClone.swift`).
  A consuming target depends on `QuillFoundation` and the file `import`s it.
- **AppKit:** the reimpl is the target named `AppKit` (`Sources/QuillAppKit`),
  declared **`#if os(Linux)` only** — on macOS it would clash with Apple's real
  AppKit, so it does not exist there.
- **Frameworks:** shims like `RSWeb` (`Sources/QuillRSWebShim`), RSCore
  (`QuillRSCoreShim`), etc., start minimal (just the referenced surface) and grow.

## 4. Verify on macOS where you can; on Linux CI where you can't

- **Foundation-only modules** (`QuillFoundation`, `QuillAccount`, `QuillArticles`,
  `QuillRSParser`) build *and* test on macOS — fast local loop. Verify here first.
- **The reimpl `AppKit`** is `#if os(Linux)` and **cannot build on macOS** (Apple's
  real AppKit wins / name-clashes). It is validated only by the **Swift Linux
  Backends** CI job (or a heavy `swift:6.2-noble` Docker run). Write assertions
  carefully by **reading the actual implementations** before asserting — blind
  tests written this way have passed Linux CI on the first try.

## 5. macOS-vs-Linux gaps that *only* Linux CI catches (running catalog)

| Symptom on Linux | Cause | Fix |
|---|---|---|
| `NSString has no member 'localizedStringWithFormat'` | macOS-only Foundation API | Clone it into `QuillFoundation` (`#if os(Linux)`) |
| `DateComponents has no member 'hour'` / `cannot convert SwiftOpenUI.DateComponents` | `DateComponents`/`Calendar` **shadowed** by SwiftOpenUI (QuillUI `@_exported import SwiftOpenUI`) | Qualify `Foundation.DateComponents` / `Foundation.Calendar` in any module importing QuillUI |
| `type 'Text' has no member 'Run'` / `Text(styledRuns:)` (on **macOS**) | `Text.Run`/`Text(styledRuns:)` exist only in the SwiftOpenUI fork, not real SwiftUI | Mirror the API in QuillUI's real-SwiftUI layer (`#if os(macOS)||os(iOS)||os(visionOS)`) so app code needs no `#if` |
| `%@` + Swift `String` in `String(format:)` | uncertain on Linux historically | Works on current swift-corelibs-foundation (validated); still confirm via CI |

Add a row whenever you find a new one.

## 6. CI topology — verify the *full* rollup

- **"Build all 4 apps + test"** runs on a **macOS** runner.
- **"Swift Linux Backends"** runs on **Linux** (~45–50 min under swarm
  contention). Only the **Qt-backend** Linux mode runs the AppKit tests.
- A macOS-only break **is** caught (by the macOS job) — so **check both jobs**
  before merging, not just one. (We once `--admin`-merged past a red macOS job by
  watching only the Linux check; main went red repo-wide until fixed.)

## 7. The local test harness (`swift test` quirks)

- `swift test` builds the **whole** graph, including `.upstream/wireguard-apple`,
  which doesn't compile on macOS. Hide it for local runs: `mv` it aside, purge
  `.build/**/WireGuardKit*`, **content-edit** `Package.swift` to bust the manifest
  cache, run, and restore via an `EXIT` trap.
- SwiftPM caches the manifest by **content hash** — an mtime `touch` won't bust
  it; a real content edit will.
- **Package.swift changes vs the harness:** the harness does `git checkout -- Package.swift`,
  which reverts *uncommitted* manifest edits. So when a slice adds a target/dep,
  **commit first, then validate** (amend if the test then fails).
- `Package.resolved` churns on local builds — `git checkout -- Package.resolved`
  before committing.
- **Local Linux verification** is possible via Docker `swift:6.2-noble` (matches
  CI) / `scripts/linux-swift-test.sh`, but it's heavy (full GTK/Qt stack), so CI
  is often the faster validator for Linux-only targets.

## 8. Process discipline

- **Branch first**, right after syncing `main`, *before* any edits. (Committing
  to local `main` by forgetting `checkout -b` is easy; recover by moving the
  commit to a branch and `git reset --hard origin/main`.)
- **One small PR per increment**, merged one commit at a time. Don't accumulate
  commits or open big PRs. Work in **rungs**: each PR is one slice (a vendored
  type, a test file, one clone gap-fill).
- `--admin` merge only for an **isolated, fully-green-but-behind** PR (main moves
  faster than the ~50-min Linux CI). Verify the **full** macOS+Linux rollup first.

## 9. State of the AppKit clone (so you don't re-discover it)

`NSTableView` / `NSOutlineView` already have substantial **model** logic:
data-source-driven `reloadData`, tree flattening (`rebuildVisibleItems`),
expand/collapse with state preservation, selection, and view-based cell caching.
The remaining gaps are **Qt rendering** and **tests**. Add model tests
(Linux-CI-validated) as you bring up more — they're the cheapest reliable
progress until rendering lands.
