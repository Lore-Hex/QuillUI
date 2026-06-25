# Porting Upstream Apple Apps to QuillUI (Linux)

A field guide for **converting real Apple/iOS app source** (Enchanted, WireGuard,
NetNewsWire, Ice Cubes, …) to run on Linux through QuillUI — distilled from the
ports that have shipped. Read this before starting a new conversion; it will
save you days.

---

## 0. The core insight (read this twice)

> **An iOS/visionOS `platforms:` pin in an upstream `Package.swift` is a
> _manifest_ constraint, not a _source_ constraint.**

On Linux, SwiftPM **ignores `platforms:`** — that array only sets Apple
deployment targets. So portable upstream Swift + Foundation source **compiles on
Linux even when the manifest says iOS-only**. The pin stops you from depending on
the upstream package _as a path dependency_ (a macOS concern); it does **not**
stop you from vendoring the source and compiling it yourself.

**Corollary: don't reimplement what you can vendor.** A from-scratch reimpl is
fast and can look beautiful, but it is 0% real source and silently diverges from
upstream forever. Vendoring the real source gives genuine parity and free
upstream updates.

---

## 1. Strategy: reimpl vs vendor vs hybrid

| | Reimpl | Vendor (the win) |
|---|---|---|
| What | hand-write the API surface | compile the real upstream source via shims |
| Speed | fast | medium (shim discovery loop) |
| Fidelity | diverges; 0% real | real parity; free updates |
| Best for | throwaway shells, UI you can't compile | **data / network / parsing layers** |

The **UI is the genuinely hard part** — upstream views are SwiftUI/UIKit locked
to iOS and must be *mirrored* through QuillUI/SwiftOpenUI. The **non-UI layers
are usually portable** and should be *vendored*.

➡️ **The answer is the hybrid: vendor the portable non-UI layers, mirror the
UI.** Make the vendored real models *power the live app* behind a compile flag,
and retire the reimpl layer by layer.

---

## 2. Triage first (one grep saves a week)

Before writing anything, classify every upstream package by its imports:

```sh
for d in $(find Packages -type d -name Sources); do
  pkg=$(basename $(dirname "$d"))
  all=$(find "$d" -name '*.swift' | wc -l)
  ui=$(grep -rlE 'import (SwiftUI|UIKit|_?AppKit|SwiftData|Observation)' "$d" | wc -l)
  echo "$pkg: $all files, $ui UI/persistence-importing"
done
```

Foundation-only files port nearly free. Packages that are ~90% Foundation-only
are your **reusable core** (Models, Network, parsing); SwiftUI-heavy packages are
the **mirror marathon** (UI, design system).

> Ice Cubes example: `Models` 46/53 files clean, `NetworkClient` 28/29 clean,
> `StatusKit`/`Timeline`/`DesignSystem` almost entirely SwiftUI. So: vendor
> Models + Network (real source), mirror the UI.

---

## 3. The vendor recipe (the WireGuard pattern)

1. **Fetch into `.upstream/`** (gitignored), or pin small public app sources
   under `vendor/apps/<name>` when clone time dominates CI. Add a
   `fetch_repo <name> <url>` case to `scripts/fetch-upstream.sh` and include
   `<name>` in the default fetch set so **CI populates it**. The fetch helper
   prefers `vendor/apps/<name>` unless `QUILLUI_REFRESH_VENDORED_SOURCE=1`.
   Current vendored app sources include Enchanted and SolderScope.
2. **Present-gate** so a fresh clone still resolves without `.upstream/`:
   ```swift
   let xPresent = upstreamPresent(".upstream/<name>/.../Sources/<Module>")
   #if os(Linux)
   if xPresent { targets += [ /* vendored targets */ ] }
   #endif
   ```
3. **Name the target after the real module** (`Models`, not `MyAppModels`) so
   upstream's own `import Models` resolves to it.
4. **Lean on the existing Apple-framework shim modules.** The repo already
   exports `SwiftUI`, `UIKit`, `Combine`, `os`, `Observation`, `CoreGraphics`,
   etc. as compile-only shadow modules. Upstream `import SwiftUI` resolves to the
   shim — just add the shim target as a dependency.
5. **For the few Linux gaps, add a tiny auto-imported shim** so upstream source
   compiles **unmodified**:
   ```swift
   swiftSettings: [.unsafeFlags(["-Xfrontend","-import-module","-Xfrontend","MyShims"])]
   ```
   Wrap the shim contents in `#if os(Linux)` so they never shadow real frameworks
   on macOS.
6. **Exclude Apple-only subsystems** via `exclude: ["SwiftData"]` (etc.) — and
   verify nothing else references the excluded types.

---

## 4. The build-error → fix loop

Build the vendored target, then categorize each error:

| Error | Meaning | Fix |
|---|---|---|
| `no such module 'X'` | a framework with a repo shim | add the shim target as a dep |
| `cannot find type 'Y' in scope` | a Linux Foundation/SwiftUI gap | add `Y` to your auto-imported shim |
| `'Z' is unavailable: moved to the FoundationNetworking module` | the Linux networking split | see §5 |

Shim cookbook (the gaps that actually bite, all `#if os(Linux)`):

- **`LocalizedStringKey`** — `ExpressibleByStringLiteral` + `…Interpolation` struct.
- **`RelativeDateTimeFormatter`** — minimal class with `unitsStyle` +
  `localizedString(for:relativeTo:)` (Linux Foundation omits it entirely).
- **`AttributedString.init(markdown:options:)`** — Linux `AttributedString`
  exists but lacks the Markdown parser; provide a plain-text fallback init.
- **`Combine`** → depend on the repo's OpenCombine-backed `Combine` shim.
- **`os` / `OSLog`** → `os` shim defines `Logger`; add an `OSLog` target that is
  just `@_exported import os`.
- **`Observation`** → ships on Linux; no shim needed.

---

## 5. The Linux `FoundationNetworking` split

`URLRequest`, `URLResponse`, `HTTPURLResponse`, `URLSession` data tasks moved out
of `Foundation` into the `FoundationNetworking` module on Linux. Upstream files
that `import Foundation` and use them fail with *"moved to the FoundationNetworking
module."* Patch the affected files (in `fetch-upstream.sh`, like the wireguard
`sys/types.h` patch) to add:

```swift
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
```

Network-client files often *also* have non-portable async/Sendable surface —
budget real porting time for them, and vendor the pure data/endpoint files first.

---

## 6. ⚠️ The qt-native build trap (this one cost a CI cycle)

> **The qt-native product build evaluates the manifest with a TRIMMED dependency
> set.** A new external package dep (e.g. `SwiftSoup`) that resolves fine in the
> **gtk** build will fail the **qt** build with:
> `error: unknown package 'X' in dependencies of target 'Y'; valid packages are: …`
>
> **The gtk build can PASS while the qt build FAILS on the *same* `Package.swift`.**

Fixes:
- If the vendored target isn't needed by any qt app, gate it to gtk:
  `if xPresent && quillUILinuxBuildBackend == .gtk { targets += … }`.
- `QUILLUI_LINUX_BACKEND` **defaults to `.gtk`** when unset, so the default
  `swift build` / `swift test` paths still compile gtk-gated targets — you do get
  real CI compilation, not just resolution.
- CI is authoritative but ~50 min, and qt-manifest issues surface **only there**.
  Gate defensively and verify the gtk build locally first (warm Docker).

---

## 7. Wiring real types into the live app

The vendored target won't exist everywhere the app builds (it's gated to
gtk-Linux; macOS/qt don't have it). So:

- **Never** `import RealModule` unconditionally — it fails where the target
  isn't built.
- Pattern: the manifest **conditionally** adds the dep *and* a compile flag to
  the consuming target, and the source branches on it:
  ```swift
  // Package.swift (only where the vendored target is built)
  deps.append("Models"); settings.append(.define("USE_REAL_MODELS"))
  ```
  ```swift
  // Source
  #if USE_REAL_MODELS
  import Models
  // …map real types…
  #else
  // …reimpl fallback…
  #endif
  ```
- **Field-shape diffs:** your reimpl's conveniences (`contentText`,
  `displayNameText`) won't exist on the real types. Derive them in a mapping
  init from the real shape (`content.asRawText`, `account.acct`,
  `serverDate.asDate`).
- **Fixtures: decode, don't hand-build.** Real upstream models are `Codable` —
  decode a realistic API JSON payload. Gotchas: synthesized `Codable` needs
  *all* non-optional fields; custom decoders derive internal fields (e.g.
  `cachedDisplayName`); date wrapper types often fall back gracefully on an
  unparsed string; use **single-quoted HTML attributes** so embedded HTML stays
  valid JSON.
- **Make the real path distinguishable from the fallback** in your verification
  (e.g. a different row count), so a silent fallback can't masquerade as success.

---

## 8. Workflow & process

- Work in a **git worktree off latest `origin/main`**. Main moves fast (parallel
  efforts) → expect `BEHIND`; update via **`git merge origin/main`**
  (force-push is denied in this environment, so rebase-and-force is out).
- **Don't deep-stack PRs.** Squash-merge + no-force-push makes reconciliation
  painful, and **deleting a merged base branch CLOSES dependent PRs**. One small
  increment per branch off fresh main → merge → branch again.
- **Verify in the warm Docker** (`swift:6.2-noble`, gtk) before pushing. Build the
  one product, screenshot headless via `xvfb-run … import -window root`.
- **Persist the recipe + state in memory/docs.** Long ports span many sessions;
  capture the exact shim list, gates, and next steps so a fresh session resumes.

---

## 9. Reference ports

- **WireGuard** — real `wireguard-apple` via shims + a `sys/types.h` patch; the
  original vendor pattern. See [docs/wireguard-audit.md](wireguard-audit.md).
- **Ice Cubes** — reimpl made beautiful (HTML content, nav tabs) → proved the
  real `Models` compiles → vendored it → live app now renders on real
  `Models.Status`. The worked example for every section above.
- **NetNewsWire** — real `Account`/`RSCore` modules vendored. See
  [docs/netnewswire-audit.md](netnewswire-audit.md).
- **Enchanted** — full upstream source compiles through the compat surface. See
  [docs/upstream-enchanted-audit.md](upstream-enchanted-audit.md).
