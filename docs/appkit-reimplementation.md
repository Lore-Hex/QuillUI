# Reimplementing AppKit on Qt — architecture & hard-won lessons

> **Audience:** anyone (human or agent) working on running real macOS/AppKit
> apps on Linux through QuillUI. This is the transferable knowledge — the
> strategy, the traps we already hit, and the recipes that work — so you don't
> relearn them the hard way. Tracking issue: **#231**. Conformance app #1:
> WireGuard (`.upstream/wireguard-apple`).

---

## 1. The goal (read this first — it's easy to under-scope)

**The product is the framework, not any one app.** We are reimplementing
**AppKit itself** (and the macOS framework stack around it) so that *unmodified
AppKit apps recompile and run* on Linux/QuillOS, rendered via **Qt**. It is
**general and app-agnostic**.

- **WireGuard is conformance test #1, not the goal.** Same for Enchanted,
  NetNewsWire, etc. Apps are the test suite that proves the framework works.
- **Any per-app shortcut is the wrong instinct.** If a fix only helps one app,
  it belongs in that app's slice, not in the shared `QuillAppKit`/`Cocoa`
  libraries. The shared libs must be useful to the *next* app too.
- This effort was under-scoped as "port WireGuard" **three times** before the
  framing landed as "reimplement AppKit, apps are conformance tests." If you
  find yourself special-casing an app inside a shared library, stop.

**Compat model = source-recompile (GNUstep-style), NOT a binary/.app loader.**
Apps are recompiled from source against the shadow libraries. There is **no**
Mach-O/dyld/ObjC-runtime/ABI fidelity requirement. The simplifying consequence:
**loose API-compat is enough** — you do not need Apple's exact class layout,
selector mangling, or ivar offsets, only correct behavior at the Swift/ObjC
*source API* contract.

---

## 2. Architecture: map AppKit onto Qt, don't rebuild it from scratch

Reimplementing AppKit from zero is a GNUstep-scale, decades-long project. We
avoid that by **mapping AppKit concepts onto Qt6 Widgets**, which already supply
the heavy subsystems.

### Shadow-module pattern

On Linux, the app's own `import` lines resolve to our shadows; on macOS they
resolve to the real frameworks. No app source changes:

| App writes        | Linux resolves to                  | Backed by              |
|-------------------|------------------------------------|------------------------|
| `import AppKit`   | `QuillAppKit`                      | Qt6 via C-ABI bridges  |
| `import Cocoa`    | `CocoaShim` (re-exports AppKit+Foundation) | —              |
| `import Foundation` | real swift-corelibs Foundation + `QuillFoundation` supplements | — |

`QuillAppKit` does `@_exported import QuillFoundation`, and `Cocoa` re-exports
`AppKit` — so types we add to `QuillFoundation` (e.g. `Selector`, `CGFloat`,
`CGRect`) are transparently visible to app source that only wrote `import Cocoa`.

### The Qt mapping (NS\* → Qt)

`NSView`→`QWidget`, `NSWindow`→top-level `QWidget`, `NSButton`→`QPushButton`,
`NSTextField`→`QLabel`/`QLineEdit`, `NSTableView`/`NSOutlineView`→
`QTableView`/`QTreeView` (+`QAbstractItemModel`), `NSScrollView`→`QScrollArea`,
`NSStackView`→`QBoxLayout`, `NSTextView`→`QPlainTextEdit` (+`QSyntaxHighlighter`),
`NSMenu`→`QMenu`, `NSStatusItem`→`QSystemTrayIcon`, `NSAlert`→`QMessageBox`,
panels→`QFileDialog`, `NSColor`/`NSImage`/`NSFont`→`QColor`/`QImage`/`QFont`.

The bridge is **imperative/retained-mode** (create/mutate/addSubview/connect by
opaque handle), not the JSON-renderer used elsewhere. Each primitive is ~5–10
lines of Qt behind an `extern "C"` ABI (`CQuillAppKitQt`), with Swift extensions
(`QuillAppKitQt`) driving it.

> **Handle lifetime lesson:** store the native handle *on the object*
> (`NSResponder.quillBackendHandle: UnsafeMutableRawPointer?`), tied to its
> lifetime. We started with `ObjectIdentifier` side-tables and they leaked.

### The one thing Qt does NOT have: Auto Layout

Qt has no constraint solver. We vendored **nucleic/kiwi** (Cassowary, BSD,
header-only C++) behind a pure-C ABI (`CKiwi` + `QuillAutoLayout`).
`NSLayoutConstraint`/anchors build a constraint model; a solve pass
(`NSView.layoutQtSubtree`) feeds the active constraints to kiwi and writes the
resulting frames onto the `QWidget`s. This was the make-or-break subsystem; it
works (priorities included).

---

## 3. The biggest wall: there is no Objective-C runtime on Linux

This is the lesson that costs the most time if you don't know it up front.

**Linux Swift ships no `ObjectiveC` overlay module.** `#selector` and `@objc`
are compiler features bound to that module — they **cannot compile** on Linux.
This is not something you can `apt install` around.

What does **not** work (we tried all of these):

- **`-enable-objc-interop`** — the flag exists but the runtime/overlay doesn't;
  you get a different wall, not a solution.
- **`libobjc.so.4` / GNUstep libobjc2** — that's the *C* runtime. Swift's
  `#selector`/`@objc` need the *Swift `ObjectiveC` overlay module*, which is an
  Apple-SDK component, not the C library. Installing the C runtime changes
  nothing for Swift source.
- **A fake same-named `ObjectiveC` module** — it flips `canImport(ObjectiveC)`
  true package-wide, which breaks Foundation's own `Selector` plumbing and
  cascades. Don't.

**What works: automatic, generalizable source-lowering.** See §4. The key
realization that unlocks it: in a source-recompile world with no real ObjC
runtime, a `Selector` is just an **opaque token**. It does not need to match
Apple's selector mangling — it only has to be *self-consistent* between the
value and our dispatch. That frees us to lower `#selector`/`@objc` into plain
Swift.

---

## 4. Source-lowering: lower the ~2% glue, keep ~98% of the app unchanged

`QuillSourceLowering` is a **host-side SwiftSyntax** toolkit (builds/tests on
macOS *and* Linux, no Docker, no Qt). It already had passes for SwiftUI
(`@main`/`@MainActor`/`@Observable`/`#Preview`…) and SwiftData. We added
**`AppKitLowering`** for the ObjC glue. Same shape every time: a
`SyntaxRewriter` subclass + a `lower(_:)`/`lowerInPlace(sourceDir:)` API,
mirrored by an in-place CLI (`Sources/quill-lower-*/main.swift`).

**Principle:** the ObjC surface in a real AppKit app is small and stereotyped
(WireGuard's macOS UI: 55 `#selector` + 32 `@objc` ≈ **2.3%** of lines; zero
hard dynamic ObjC — no `perform`, KVO, `NSInvocation`, `objc_*`). Lower exactly
that glue automatically; leave everything else byte-for-byte.

`AppKitLowering` does two things, app-agnostically:

1. **Strip ObjC-exposure attributes** (`@objc`, `@objcMembers`, `@IB*`,
   `@NSManaged`, `@GKInspectable`, `@NSApplicationMain`) from
   func/var/init/subscript/class/**protocol**/**enum**/extension.
2. **`#selector(x)` → `Selector("x")`**, keyed off the reference's **source
   text** (legal because the token is opaque, per §3). The leading **type
   qualifier is normalized away** — `#selector(Type.foo)` and `#selector(foo)`
   both → `Selector("foo")` — because AppKit menu validation compares
   `menuItem.action == #selector(Type.foo)` and the *setter* usually used the
   unqualified form; if the keys didn't match, validation would silently break.

The runtime token is **`QuillFoundation.Selector` = `struct { let name: String }`**
(defined `#if !canImport(ObjectiveC)`). It constructs, supports `==`, and exposes
`.name` for the runtime dispatch layer.

**Closing the loop — generate dispatch + a runtime to invoke it.** Lowering
`#selector` to an opaque token only compiles; to *run*, the same pass also
**generates the dispatch conformance**: for each type with `@objc` actions it
appends `extension Type: QuillActionDispatching { func quillPerform(_ selector:
Selector, with sender: Any?) { switch selector.name { case "save": save(); case
"foo(sender:)": foo(sender: sender as! AnyObject); … } } }` (collected from the
`@objc` methods *before* the strip; 0- or 1-(sender)-arg, cast by declared type).
The runtime side is a tiny protocol (`QuillActionDispatching`) plus
`NSControl.sendAction` calling `(target as? QuillActionDispatching)?.quillPerform(
sel, with: self)` and `NSButton.performClick` firing it. Net: `#selector`/`@objc`
→ plain Swift that both compiles *and* dispatches, generated automatically from
the app's own code. Protocol-based (not an `NSObject` method) so it works for any
target — `NSResponder`, `NSViewController`, `AppDelegate` — with no `override` and
no edits to Foundation's `NSObject`.

### Lessons from building lowering passes

- **`#selector(...)` parses as `MacroExpansionExprSyntax`** with
  `macroName == "selector"`. Handle it there; guard the name so you don't catch
  `#keyPath` etc.
- **Preserve leading trivia when deleting a line-leading attribute.** If you
  just drop `@objc`, the newline+indent that was attached to the `@` token is
  lost and the decl merges onto the previous line — a *"consecutive statements"*
  compile error when that line isn't brace-terminated. Fix: do the strip at the
  **decl level** and re-anchor `node.leadingTrivia` onto the surviving first
  token. (Doing it only in `visit(AttributeListSyntax)` can't reach the sibling
  token to fix it.)
- **`SyntaxCollection.filter` already returns the collection type** — don't
  re-wrap (`AttributeListSyntax(kept)` warns as deprecated; assign `kept`).
- **swift-testing `Comment` string interpolation** has an overload-inference
  snag with bare `#expect(cond, "\(x) ...")`. Build the `String` first and pass
  `Comment(rawValue: msg)`, or use a plain literal.

### Real-source smoke tests earn their keep

Unit tests on hand-written snippets are not enough. Add a smoke test that runs
the pass over the **entire vendored upstream tree** and asserts the invariants
(here: every `#selector`/`@objc` cleared, and the pass is **idempotent**).
Make it **skip gracefully when `.upstream` is absent** (the host CI job doesn't
fetch it; it's only present for the Docker conformance build). Our first run of
this smoke immediately caught `@objc protocol` — a decl kind the unit cases had
missed. The whole-corpus check finds the long tail the examples don't.

---

## 5. Conformance: the build *is* the test

We prove the libraries work by **compiling real, unmodified upstream files**
against them. There is no separate assertion — *if it compiles, it conforms*.

- Add a **path-based target** that points at the real upstream file(s) (e.g.
  `Sources/.../macOS/View/KeyValueRow.swift`) and depends on `Cocoa`.
- **Gate every conformance target `#if os(Linux)`.** The shadows are Linux-only;
  on macOS the app uses the real frameworks, so an ungated conformance target
  fails the macOS build with *"product 'Cocoa' not found."* Pattern: append it
  inside `if wireguardUpstreamPresent { ... #if os(Linux) targets.append(...) #endif }`.
- Fill AppKit gaps in the shared libs **as each compile surfaces them** — never
  edit the upstream source. The compiler errors *are* your TODO list.
- Match real AppKit's initializer model so subclasses compile cleanly: NSView's
  designated init is `init(frame:)`/`init?(coder:)` and NSViewController's is
  `init(nibName:bundle:)`. Making the shadow's `init()` a `convenience` lets a
  subclass's `init()` compile without `override`.
- **Build the conformance target with the DEFAULT graph, not `QUILLUI_LINUX_BACKEND=qt`.**
  The qt selector swaps `targets` for a stripped minimal list, which *drops* the
  conformance target — you'll get *"no target named …"*. The shadow needs neither
  GTK nor Qt (the Qt backing is a separate module), so a plain
  `swift build --target <Conformance>` (default/gtk graph) compiles it.

**Proven (first real ViewController):** WireGuard's unmodified
`ButtonedDetailViewController` — a full `NSViewController` (NSButton, `#selector`
target-action, Auto Layout, `init(nibName:)`/`init?(coder:)`, `loadView`) —
compiles against the shadow after lowering, with **zero new shadow APIs needed**.
The core thesis works on real ViewControllers, not just layout views.

**Triaging "what's missing" — two categories.** When a real VC won't compile, the
errors split into: **(A) app-level deps** — the app's *own* types the conformance
target doesn't include (`tr` the i18n helper, model/view-model layer, sibling
views). Fix by including those files in the target, or pick a VC that has none
(ButtonedDetail). **(B) real AppKit-surface gaps** — `NSTableView.dequeueReusableCell`,
`NSStackView.addView`, `NSView.left/rightAnchor`, `NSBox`, etc. Fix by growing the
shadow. Don't conflate them: (A) is "include more app source," (B) is "build more
framework." A single `tr` inclusion can clear a hundred (A) errors at once.

---

## 6. CI & build-graph gotchas (these have bitten us)

- **Watch ALL required checks, not just Linux.** There are three: *Swift Linux
  Backends* (~50 min), *Build all 4 apps + test* (macOS), and *Strict
  Mac-reference verifier*. A Linux-only watcher once reported a PR "green" while
  the macOS job was red. Roll up every check.
- **Transient `apt` failures** (ports.ubuntu.com timeouts) are common in the
  Linux job — just re-run; they're not your bug.
- **`SourceHygieneTests` pins manifest details.** Some target dependency lists
  and qt module names are asserted to occur **exactly once**. Do **not** hack a
  shared target's deps to gain CI coverage — that breaks the hygiene test.
  Duplicating a target into another graph is fine *unless* it has a `== 1`
  assertion.
- **The qt build graph is a separate, minimal target list** in `Package.swift`
  (`if quillUILinuxBuildBackend == .qt { targets = [...] }`). New AppKit-Qt
  targets must be added **there too**, not only to the default array.
- **CI runs no qt unit tests** (it only does per-product backend builds). Qt
  slices must be validated in Docker (see §7). Real qt CI coverage arrives only
  when an app *product* consumes the target.
- **Host-side lowering tests DO run in normal CI** (the "Swift tests" step), so
  put as much validation there as possible — it's the fast lane.

---

## 7. Docker validation recipe (for Linux-only / Qt slices)

The shadows are Linux-gated, so validate them in a native-arm64 container:

```bash
# image: swift:6.2-noble (Ubuntu 24.04, GTK 4.8+ floor, Qt6)
apt-get install -y pkg-config qt6-base-dev libsqlite3-dev git ca-certificates
#   ^ retry in a loop; DON'T add libgl1-mesa-dev (it caused apt timeouts and
#     conformance/--target builds need no GL).
git clone /work /src && cd /src
git clone --depth 1 https://github.com/WireGuard/wireguard-apple.git \
    .upstream/wireguard-apple
swift build --target <ConformanceTarget>     # the build IS the test
QT_QPA_PLATFORM=offscreen QUILLUI_LINUX_BACKEND=qt \
    swift test --filter QuillAppKitQtTests    # headless widget round-trips
```

Notes: `import error:` in a smoke log means **success** (the module loaded), not
failure. GTK `Ctrl+Return` submit is dead under headless Xvfb (the button
works) — don't chase it.

**Make it fast: bake a warm image + cache the build dir.** A cold qt-graph build
is ~15–20 min; warm it's seconds. Build `FROM swift:6.2-noble` (or any Swift base)
+ `apt install qt6-base-dev libsqlite3-dev pkg-config` once, then mount the repo
and a *named volume* at the scratch path so SwiftPM caches across runs:

```bash
docker run --rm -v "$PWD":/work -w /work -v quillui-build:/work/.build-linux \
  -e QUILLUI_LINUX_BACKEND=qt -e QT_QPA_PLATFORM=offscreen <warm-image> \
  bash -lc 'git config --global --add safe.directory /work; \
            swift test --scratch-path .build-linux --filter <Test>'
```

**Manifest gotcha:** `Package.swift` hard-`fatalError`s if `QUILLUI_LINUX_BACKEND=qt`
and the `Qt6Widgets` pkg-config package is absent — so **Qt6 must be installed even
to *evaluate* the manifest** under the qt selector, not just to compile qt targets.
(Conformance builds dodge this by using the default graph — see §5.)

---

## 8. Git / PR workflow lessons

- **Branch hygiene:** unique branch slug per cycle; **verify `HEAD == origin/main`
  before editing** (`git fetch && git checkout -B <slug> origin/main`). We
  committed to the wrong base twice by skipping this.
- **Always be merging.** Land each small green increment on main *promptly* —
  one increment per branch → merge → branch fresh off main. Holding PRs open
  across many ~50-min CI cycles causes the "behind-main treadmill."
- **`--admin` merge** is appropriate for fully-green-but-behind PRs (it bypasses
  *only* the up-to-date requirement; all status checks must still pass) when
  main moves faster than CI. Scope it to the authorized effort.
- **Force-push is denied** in this environment. To update a PR after a local
  amend, use `git reset --soft` + a follow-up commit instead.
- **Keep increments tight.** A pure library/tests change (like a lowering pass)
  ships separately from CLI wiring, which ships separately from manifest/Docker
  conformance. Smaller PRs = faster green = less treadmill.
- **Beware shared test files as conflict hotspots.** A single test file that many
  PRs append `@Test`s to (e.g. `QuillAppKitQtTests.swift`) conflicts every time a
  sibling PR lands first (both insert before the final `}`). Either give a new
  slice its *own* test file, or sequence test-touching PRs to land one at a time.
- **`reset --soft origin/main` only works to "rebase" a held branch if that branch
  shares main's current base.** If main advanced (e.g. the swarm merged things)
  after your branch's base, reset-soft stages a *revert* of all that intervening
  work. Instead, branch fresh off `origin/main` and `git checkout <held-sha> --
  <only-your-files>` to replay just your diff cleanly.

---

## 9. Component ladder (where we are, where it's going)

Issue **#231** has the live status. The general shape:

- **M0 ✅** Auto Layout (`CKiwi`/`QuillAutoLayout`, Cassowary).
- **M1 ✅** Core hierarchy + imperative bridge (NSResponder/NSView/NSWindow/
  NSViewController/NSApplication + run loop).
- **M2 ✅** Functional `NSLayoutConstraint`/anchors + the solve pass.
- **M3 ✅** NSControl family (NSButton/NSTextField…), priorities, content
  resistance, `Cocoa` shadow. **First conformance achieved:** WireGuard's
  unmodified `KeyValueRow.swift` compiles against the libs.
- **M4 (in progress)** ObjC target-action lowering (`AppKitLowering`) →
  compiles the real ViewControllers. Then the big subsystems: **NSTableView**
  (tunnel list/detail), **NSTextView + highlighter** (config editor),
  **NSMenu/NSStatusItem** (menu-bar app).
- **M5/M6** menus/chrome, then drawing + pixel-equivalence, then **launch the
  actual window** (render + interactive, not just compile).

---

## 10. The meta-lessons (the ones that generalize beyond AppKit)

1. **Name the real goal and resist re-scoping it down.** "Make the framework,
   apps are tests" beats "port this app" — the latter quietly produces per-app
   hacks that don't compound.
2. **Map onto an existing toolkit; only build what's genuinely missing.** Qt
   gave us everything except a constraint solver. We built only that.
3. **In a source-recompile world, exotic runtime features become text
   problems.** No ObjC runtime? Lower the ~2% of ObjC glue with a syntax pass;
   keep 98% of the app verbatim. Automatic + generalizable, never hand-edits.
4. **The compiler error list is the spec.** Compile real upstream source; fix
   what it complains about; repeat. The build is the test.
5. **Validate against the whole real corpus, not just examples.** Whole-tree
   smoke tests find the decl kind / edge case your snippets forgot.
6. **Measure honestly before committing to an approach.** "Will lowering really
   keep ~98% unchanged?" — we counted (55 `#selector` + 32 `@objc`, no hard
   dynamic ObjC) before betting on it.

---

*Related: [docs/apple-package-function-coverage.md](apple-package-function-coverage.md)
(AppKit API ledger), [docs/linux-build-tooling.md](linux-build-tooling.md),
[docs/wireguard-audit.md](wireguard-audit.md). Source of record for status:
GitHub issue #231.*
