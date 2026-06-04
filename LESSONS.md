# QuillSignal / Real-Apple-Apps-on-QuillOS — Lessons Learned

Cross-cutting, high-level lessons + **cross-effort coordination** for compiling
real Apple apps on QuillOS. Written so any future conversation skips the dead
ends. Detail: `SIGNAL_PORT.md` (full chronology), `/Users/jperla/claude/QuillSignal/FINDINGS.md`
(presage de-risk). Real upstream source lives under `.upstream/` (gitignored).

> **READ FIRST if you are about to fight Objective-C on Linux:**
> `/Users/jperla/claude/QuillUI-wg/docs/appkit-reimplementation.md` §3–4 and
> `/Users/jperla/claude/QuillUI/docs/porting-lessons.md`. That frontier is
> already mapped and **owned by QuillUI/QuillAppKit.** Coordinate, don't redo it.

---

## TL;DR — the two things to know

1. **Two different products wear the name "Signal on QuillOS." Don't conflate
   them.** Track A = a *reimplementation* (presage Rust core + hand-written
   QuillUI/GTK UI) — works, but is not Signal's source. Track B = *compile the
   real `signalapp/Signal-iOS` source* against QuillUI/QuillAppKit shims — the
   real goal, gated behind the ObjC frontier below.
2. **The ObjC wall on Linux is NOT solved by `libobjc2`/a custom toolchain.**
   That was the tempting wrong answer (I chased it; so did others before me).
   The decided answer is **automatic source-lowering** (`QuillSourceLowering` /
   `AppKitLowering`), which already exists in QuillUI. See "THE WALL."

---

## The two tracks (decide which you're on before writing code)

- **Track A — reimplementation (works today).** Real Signal *protocol* + real
  *libsignal* crypto via `presage` (Rust) behind a unix-socket bridge, driven by
  a hand-written QuillUI (SwiftOpenUI/GTK) front-end. Sidesteps ObjC entirely.
  A *different app that speaks Signal* — not Signal's code. Most QuillSignal
  commits build this.
- **Track B — compile original `signalapp/Signal-iOS`.** The QuillAppKit
  "recompile real Apple apps" thesis. Got far (real `libsignal_ffi.a` built;
  `LibSignalClient` compiles **zero source edits**; `SignalServiceKit` wired,
  ObjC/tests/Calls/Payments excluded) then parked at the ObjC wall.

Track A, however polished, never becomes Track B. Choose deliberately.

---

## THE WALL: `@objc` on Linux — what does NOT work, and what does

Real `SignalServiceKit` is pervasively `@objc` (its model layer: `TSMessage`,
`TSGroupModel`, the `TS*Type` enums…). On Linux that is the dominant blocker.

**Linux Swift ships no `ObjectiveC` overlay module.** `@objc`/`#selector` are
compiler features bound to that Apple-SDK overlay; they **cannot compile** on
Linux. Things that look like fixes but are NOT (QuillUI tried them; I re-tried
some and confirmed):

- **`-enable-objc-interop`** — unknown/ineffective; the overlay still isn't
  there. A different wall, not a solution.
- **`libobjc.so.4` / GNUstep `libobjc2`** — that's the *C* runtime. Swift's
  `@objc`/`#selector` need the *Swift `ObjectiveC` overlay*, an Apple-SDK
  component — **not** the C library. Installing it changes nothing for Swift.
- **A fake same-named `ObjectiveC` shim module** — flips `canImport(ObjectiveC)`
  true package-wide, **breaks Foundation's own `Selector` plumbing, and cascades.
  Don't.** (This is precisely what produced a **~492k-error cascade** when I
  tried it on `SignalServiceKit`. Documented anti-pattern in
  `appkit-reimplementation.md` §3 — I hadn't read it first. Lesson: read it
  first.)

**What works — automatic source-lowering (`QuillSourceLowering` /
`AppKitLowering`).** Host-side SwiftSyntax toolkit (builds macOS + Linux, no
Docker/Qt). Key realization: in a source-recompile world with no ObjC runtime, a
`Selector` is just an **opaque token** — it only has to be self-consistent, not
match Apple's mangling. So:

1. **Strip ObjC-exposure attributes** (`@objc`, `@objcMembers`, `@IB*`,
   `@NSManaged`, `@NSApplicationMain`, …).
2. **`#selector(x)` → `Selector("x")`** (normalize the type qualifier away).

The ObjC surface of a real AppKit app is small + stereotyped (WireGuard's macOS
UI: 55 `#selector` + 32 `@objc` ≈ **2.3%** of lines, **zero** hard-dynamic ObjC).
Lower that ~2% glue automatically; keep ~98% byte-for-byte.

**MEASURED — Track B is more viable than the 492k cascade implied**
(`SignalServiceKit`, 1392 Swift files / 388k LOC, excl tests/mocks):

- **Lowerable glue** (`AppKitLowering` handles): **2836 `@objc` + 88 `#selector`**
  ≈ 0.75% of LOC — *less* dense than WireGuard's 2.3%; mechanical, just volume.
- **Hard-dynamic ObjC is small + bounded:** `@NSManaged` **0**, `NSInvocation`
  **0**, `perform` **3**, `objc_*` **8**, KVC `forKey` **7**, swizzle/runtime-string
  **1**, YapDatabase **4** (migrated to GRDB). KVO shows ~97 but that's an **upper
  bound** — `NotificationCenter.addObserver` is folded in and is NOT hard-dynamic.
  **No pervasive dynamic-ObjC blocker** — a few dozen handleable sites.
- **The real bounded wall:** **32 `.m` + 38 `.h` ObjC base-model files**
  (`TSMessage`/`TSInteraction`/`TSGroupModel`…). Not Swift, so source-lowering
  doesn't touch them; they must be **ported to Swift.** Hundreds of Swift files
  subclass them — *that* is what the 492k cascade was.

**Verdict:** Swift side lowers cleanly (`AppKitLowering`); the gating task is a
**finite port of the central ObjC base-model spine to Swift**, not an open-ended
toolchain project.

### Codex-reviewed Track-B sequence (2026-06-04)

A second-opinion review (codex, read-only) sharpened the plan — adopt this order:

0. ✅ **DONE — lowerer landed + proven on Signal at scale.** `AppKitLowering` is
   already on QuillUI `main` (PR **#286** — the swarm landed it; note
   `quillui-signal` is the *same repo* `Lore-Hex/QuillUI` on branch
   `signal/real-backend`, just **behind main**, which is why its
   `QuillSourceLowering` only had SwiftUI/SwiftData). The missing
   `quill-lower-appkit` CLI was added on `main` in PR **#302**. **Proven on real
   Signal:** running the CLI over all of `SignalServiceKit` (1412 Swift files,
   ~88s, no crash) collapsed **`@objc` 2843 → 1** and **`#selector` 88 → 0** —
   i.e. it mechanically removes essentially the entire ~61k "ObjC interop disabled"
   wall. **To consume it in the Signal build:** sync `signal/real-backend` with
   `main` (merge/rebase to pull #286 + #302), then wire the CLI into the build —
   lower a *generated copy* of `.upstream/signal-ios` before compiling (mirroring
   the SwiftUI lowering pipeline; never lower the upstream tree in place).

   **✅ RE-MEASURED (2026-06-04) — the wall fell.** Synced `main` into
   `signal/real-backend` (merge `338775a`, manifest parses, 0 behind). Lowered the
   SSK source and rebuilt `SignalServiceKit`: **492,965 errors → 17**, and
   **"Objective-C interoperability is disabled" 61k → 0.** The build now sails
   through SwiftProtobuf/deps. The **17 residual errors aren't in Signal source** —
   they're `cannot find type 'Selector'` in the **`QuillUIKit`** shim, caused by the
   still-present **`ObjectiveC` shim anti-pattern** (it flips `canImport(ObjectiveC)`
   true and breaks Foundation's `Selector` plumbing, exactly as warned).

   **✅ DONE — `ObjectiveC` shim retired (commit `60a6a11`).** Removed it from
   `signalAppleFrameworkShims`, stripped the vestigial `import ObjectiveC` from
   `Error+ErrorLocalizedDescription`/`Error+IsRetryable`, and added a tiny
   `ObjCAssoc` target (locked `[ObjectIdentifier:[UInt:Any]]` map) for
   `ObjectRetainer`/`ProxiedContentDownloader`. **Gotcha:** `canImport` changes are
   invisible to SwiftPM incremental builds — force-clean the stale `ObjectiveC`/
   `QuillFoundation`/`QuillUIKit` scratch modules or the flip won't take. The 17
   cleared; infra is fully green (objc-interop 0, Selector 0, missing-ObjectiveC 0)
   and the build reached the `TS*` cascade: **377,483 errors.**

   **✅ DONE — TS* model enums ported (commit `5a26b06`): 377k → 342,605.** First
   spine sub-step. Ported the 11 ObjC `NS_ENUM` model enums the Swift layer needs
   but that live in excluded `.h` (`TSOutgoingMessageState`, `OWSVerificationState`,
   `TSEditState`, `TSInfoMessageType`, `TSErrorMessageType`, `RPRecentCallType`,
   `TSRecentCallOfferType`, four `TSPayment*`) as faithful Swift enums. **Three
   contract traps, all verified against call sites:** (a) match the exact ObjC raw
   *type* — `int32_t`→`Int32`, `uint64_t`→`UInt64`, etc. — because `+SDS.swift` does
   `Enum(rawValue: <column>)` and GRDB decodes the column to `RawValue`; (b) use the
   Swift-*imported* (prefix-stripped, lower-camel) case names, and mixed-prefix
   enums strip less (`TSInfoMessageType` keeps a leading `type` on its `...Type...`
   cases, while `TSEditState_None`→`.none`); (c) Codable is already supplied by
   `SDS+Enums.swift`'s empty extensions — **don't** redeclare it (redundant-
   conformance error). Overlay pattern: committed source of truth at
   `Sources/SignalServiceKitObjCPort/`, symlinked same-module into the SSK tree
   under `QuillPort/` (no Package change; the durable pipeline overlay-copies).

   **Spine-step finding:** remaining top errors are the base classes
   (`TSMessage`/`TSInteraction`/`TSGroupModel`/`TSQuotedMessage`) plus a large
   co-located cascade of *spurious* `cannot find type 'Date'/'Data'/'DispatchQueue'`
   + `does not override … superclass` — a missing superclass degrades the whole
   file's type resolution, so porting the base classes should clear far more than
   face value. **But some are real:** a few files (e.g. `Storage/.../V2/DB.swift`)
   use `public import GRDB` with **no `import Foundation`** yet reference
   `DispatchQueue` — Apple supplied it implicitly; Linux needs an explicit-import
   injection step in the durable pipeline.

   **✅ Spine progress (signal/real-backend) — ENUMS 377k→343k, then bases
   343k→314k (−63k from the 377k peak):** root trio `SDSRecordDelegate` +
   `TSYapDatabaseObject` + `BaseModel` (`2a68575`, 342605→340389), keystone
   `TSInteraction` (`b8d9d8f`, →338575), `TSQuotedMessage` (`8bacecd`, →332529,
   standalone NSObject archived into the message blob), and the abstract base
   `TSMessage` (`f4ffa05`, →**314063, −18466 the biggest single drop** — 83 files
   descend from it; its 29-param generated SDS init is what subclass `+SDS`
   deserializers call via `super`). Each port compiles with zero errors. Pattern
   confirmed at scale: port the abstract base's FULL stored-prop surface + the SDS
   init exactly (subclasses call it via super) but you may DEFER behavior with no
   compile cost (write-hook overrides, 0-caller `updateWith…` mutators, derived
   accessors that need an unported helper). Remaining top type-errors:
   `TSGroupModel` (1160) + the message subclasses + a large `Date`/`Data`/
   `DispatchQueue`/`TimeInterval` band that is **barely moving as bases land →
   likely real missing `import Foundation` (DB.swift-style), not cascade**; the
   import-injection pipeline step is becoming the next high-leverage lever.
   **🏆 BIGGEST WIN — `import Foundation` injection (`84975ae`): 314063 → 207849,
   −106,214 in ONE step** (confirming the hypothesis above). On Apple the
   SignalServiceKit ObjC umbrella makes Foundation implicit for **every** Swift
   file in the module; on Linux + SwiftPM there is no umbrella, so each file must
   `import Foundation` itself. **290** SSK files used Foundation types while
   importing only `GRDB`/`LibSignalClient`/`CryptoKit` — none of which re-export
   Foundation on Linux — turning every such use into a `cannot find type` error
   (plus cascade). Fix: `scripts/quill-signal-inject-foundation.sh`, an idempotent
   prepare step that prepends `import Foundation` to any module file using a
   Foundation type without importing it. **THE lesson for recompiling any
   ObjC-umbrella framework on Linux: inject the implicit Foundation (and UIKit)
   import per-file.** Run after fetch+lower; the committed SCRIPT is the durable
   artifact (`.upstream` edits are disposable). (UIKit has the same gap — the
   script also injects `import UIKit` (the QuillUIKit shim) into the 17 files that
   need it: `32230d4`, → 205975.)

   **✅ TS* message subclasses (`open class X: TSMessage`):** `TSGroupModel` base
   (`5fee818`, → **195599, under 200k**), `OWSReadTracking` protocol +
   `OWSReceiptCircumstance` + `TSErrorMessage` (`3d7e1f8`, → 192366),
   `TSIncomingMessage` (`e6965e8`, → 185944). **Subclass recipe:** the generated
   SDS designated init = `TSMessage`'s 29 params **+** the subclass's own columns,
   in the exact order of the `<Name>+SDS` `case .<recordType>` deserializer call,
   and it calls `super.init(grdbId:…all 29…)`; the builder init
   `init(<x>MessageWithBuilder:)` calls `super.init(messageWithBuilder:)`;
   `override var interactionType`; conform `OWSReadTracking` via `var wasRead {
   read }`; **SDS-tabled subclasses are NOT blob-archived** → mark `init()` AND
   `init?(coder:)` `@available(*, unavailable)` (no `encode`/`initWithCoder`
   needed); read-tracking `markAsRead`/`markAsViewed` set the flag directly in pass
   1 (DB-write/receipt/notification side effects deferred). From the 377k peak this
   is **−191,539 (~51%)** across 13 zero-error commits; remaining are
   `TSInfoMessage`/`TSOutgoingMessage`, the 2 override-relocate sites, and a small
   residual shim band (`URLRequest`/`URLSessionWebSocketTask`, `Selector`,
   `UIColor.rgbHex`).

   The validated NSObject port pattern: designated
   inits set all stored props **before** `super.init()`; `required override
   init()` + `required init?(coder:)` for NSSecureCoding subclasses & dynamic init;
   `override var hash`/`func isEqual(_:)`; NSCoding via `decodeObject(of:forKey:)`/
   `encode(_:forKey:)`; relax setters to `public internal(set)`; **no `@objc`**.
   Overlay: committed at `Sources/SignalServiceKitObjCPort/`, symlinked into
   `QuillPort/`; **Quill-prefix the basename when it collides with an existing
   tree `.swift`** (there is already a `TSInteraction.swift` extension file → SwiftPM
   "multiple producers" object-file collision).

   **✅ RESOLVED — override-in-extension (experiment, 2026-06-04).** Signal
   organizes subclass overrides of base methods in **`extension` blocks** (e.g.
   `extension TSInteraction { override func anyDidInsert(with:) { super… } }`).
   Exact error: `instance method 'anyDidInsert(with:)' declared in
   'TSYapDatabaseObject' cannot be overridden from extension`. Tested both fixes on
   the Linux SSK build:
   - **`@objc` is DEAD on this build:** annotating the base hooks `@objc` yields
     `error: Objective-C interoperability is disabled` (this is exactly why lowering
     strips `@objc`; it applies to our ported NSObject bases too — even though the
     param `DBWriteTransaction` *is* ObjC-representable as an NSObject subclass).
   - **`dynamic` alone does NOT help** (it enables dynamic *replacement*, not
     vtable override-from-extension) — error count unchanged.
   - **Therefore the only fix is to RELOCATE the override into the class body** — a
     `quill-lower-appkit` pass that hoists `extension Sub { override … }` members
     into the ported class (durable). **Do not annotate.**
   - **Blast radius is tiny and the spine is NOT gated:** only **5 files** use
     `extension TS* { override }` — `TSInteraction`×3, `TSOutgoingMessage`×1,
     `TSGroupModel`×1. **`TSMessage`/`TSIncomingMessage`/`TSInfoMessage`/
     `TSErrorMessage`/`TSCall` have ZERO** → port them now; handle the 5 relocate
     sites as a separate small lowerer step. (The 2 live `TSInteraction` sites cost
     ~2 errors + a little cascade until then.)
1. **Port the central SPINE, NOT leaf-first.** The cascade is dominated by
   high-fan-out types: `TSYapDatabaseObject`, `BaseModel`, `TSInteraction`,
   `TSMessage`, `TSIncomingMessage`, `TSOutgoingMessage`, `TSInfoMessage`,
   `TSErrorMessage`, `TSQuotedMessage`, `TSGroupModel` (+ `OWSAsserts`/`OWSLogs`).
   Leaf-first is low-leverage and won't collapse the cannot-find-type cascade.
2. **Shim, don't rewrite.** SDS is already mostly Swift/GRDB. Write
   **interface-accurate Swift base classes** that preserve the source contract
   (stored props, initializers — incl. the generated `+SDS.swift` `init(grdbId:…)`
   signatures — `asRecord()`/`SDSRecordDelegate`, `copy`/`hash`/equality,
   `NSCoding`/`NSSecureCoding`); **stub** deep send/delete/network side effects
   until the smoke target links + runs. Port KVC as direct `NSNumber` boxing — do
   not emulate dynamic KVC.
3. **Smallest milestone (target this, not all of SSK):** one executable that
   links `libsignal_ffi.a` (touch one `LibSignalClient` symbol), constructs a
   `TSMessage` subclass + `TSGroupModelV2` via the generated SDS initializer,
   calls `asRecord()`, archives/unarchives one legacy blob (`TSQuotedMessage` /
   `TSGroupModel`), exits 0. Excludes SignalUI / linking / receive-send / Calls /
   Payments / migrations.

**Underestimated risks (codex):** stripping `@objc(ClassName)` can break
**`NSKeyedArchiver` class-name compatibility** — a *runtime* wall, not just
compile — so map class names deliberately. `NSKeyedArchiver` fidelity on Linux
generally may bite at runtime. `NotificationCenter` selector observers compile
after lowering but may need closure/runtime rewrites. `objc_sync_enter/exit`, KVO
leftovers, atomic props, swizzling are few but semantically sharp. SQLCipher /
keychain / file-protection / APNs are deferred, not gone. Hand ports will drift
from the generated SDS contract unless the constructor/property surface is
generated or test-pinned.

---

## COORDINATION — this is a shared frontier; converge, don't duplicate

The "real `@objc` Apple code on Linux" problem is **owned by QuillUI/QuillAppKit**
and shared across efforts. Do the lowering ONCE, centrally; each app *consumes*
it.

- **Owner / canonical docs:** `/Users/jperla/claude/QuillUI` —
  `docs/appkit-reimplementation.md` (the ObjC strategy, §3–4) and
  `docs/porting-lessons.md`. Tooling: `QuillSourceLowering` + `AppKitLowering`
  (+ `quill-lower-*` CLIs). Orchestrated via **Loom** (labeled GitHub issues,
  `.swarm/worktrees/codex-issue-*` — multiple agents already in this area).
- **Shared consumers of the lowering pass:**
  - **WireGuard** — AppKit conformance app #1 (clean ~2.3% glue; the proving
    ground for `AppKitLowering`).
  - **NetNewsWire** — same root blocker (`RSCoreObjC`/`RSDatabaseObjC` `#import
    <Foundation/Foundation.h>`). In *this* repo its real-source graph is gated
    **off** (`nnwUpstreamPresent = false`); the live port is in QuillUI. If an
    NNW agent is extending lowering to ObjC `.m`/`.h` files (a harder case than
    Swift `@objc`), **that work and Signal's overlap — coordinate there.**
  - **Signal (Track B)** — needs the *same* `AppKitLowering` pass over
    `.upstream/signal-ios` before `SignalServiceKit` can compile. Do **not**
    rebuild a toolchain or add an `ObjectiveC` shim here; run the QuillUI pass.
- **Coordination channel:** QuillUI's Loom issues + the two docs above. Before
  starting ObjC-lowering work for Signal, check QuillUI open issues/worktrees so
  Signal becomes another consumer of `AppKitLowering`, not a fork of it. Feed
  Signal-specific findings (hard-dynamic ObjC, YapDatabase) **back** into the
  QuillUI docs.

---

## The `canImport` shim leak (subtle, bites both ways)

Adding "Apple-framework shim" modules (`Sources/AppleFrameworkShims/<Name>`) so
`import UIKit` resolves has a catch: a shim named after a real framework flips
`canImport(<Name>)` **true for EVERY target**, including unrelated checkout deps
(GRDB), via SwiftPM's shared module dir.

- **Helped — CoreGraphics.** GRDB does `#if canImport(CoreGraphics) import
  CoreGraphics` then uses `CGFloat`; fix = shim re-exports the real symbol:
  `@_exported import struct Foundation.CGFloat`.
- **Hurt — ObjectiveC.** GRDB's own no-op `autoreleasepool` exists only
  `#if !canImport(ObjectiveC)`; the shim deletes it, and GRDB never imports the
  shim so a re-export can't reach it. (And per "THE WALL," an `ObjectiveC` shim
  is an anti-pattern anyway — once source-lowering removes Signal's `import
  ObjectiveC`, the shim should not exist at all and GRDB self-heals.)

**Rule:** re-exporting from a shim only helps deps that actually `import` it.
Deps that key off `canImport(X)` without importing X must be fixed at the dep —
or, better, remove the need for module `X`.

---

## Other concrete lessons

- **`swift-corelibs-foundation` gaps on Linux:** no `autoreleasepool`
  (even `import Foundation` fails); `CGFloat` needs explicit re-export. Expect a
  long tail once interop is handled.
- **"It compiles" is per-target.** `Image(filePath:)` is **SwiftOpenUI-only** —
  real SwiftUI (macOS) lacks it, so GTK-green code can fail on macOS. Gate it:
  `#if os(Linux)` → `Image(filePath:)` else `NSImage(contentsOfFile:)`. **Build
  the native-macOS product as a second, stricter gate.** (The macOS resolve
  drops the Linux-only `opencombine` pin from `Package.resolved` — do not commit
  that; restore it.)
- **macOS is the pixel-perfect reference; capture by window ID.** Build native +
  `QUILLUI_SIGNAL_FAKELINKED=1`, then `screencapture -l<CGWindowID>` (region
  capture grabs whatever is visually at those coords — wrong app if occluded).
  Get the ID via a `CGWindowListCopyWindowInfo` helper filtered by PID.
- **Headless GTK render caveats:** no emoji font (📄 → tofu → use ASCII tags like
  `FILE`), DejaVu not SF, no native chrome. The GTK render is a faithful *layout*
  reproduction, **not** a pixel clone — "pixel-perfect on Linux" is font/env
  dependent.
- **SwiftOpenUI ViewBuilder:** `if`/`if case` only — **no `switch`, no standalone
  `let`** inside a builder (fine in plain funcs). `@MainActor` calls are OK inside
  `assumeIsolated`.
- **Verification honesty:** "works" was Linux-GTK-only until the macOS build was
  tried; and **no real Signal account was ever linked** (link/send/receive/
  download are user-gated). Compile + unit + decode-contract + UI-fixture
  verified ≠ functionally proven end-to-end. Say which.
- **Why presage (Track A):** `signal-cli` is blocked on ARM (bundled
  libsignal-client jar ships no linux-aarch64 `.so`); `presage` builds libsignal
  from source for the target arch. Build the bridge as a **4th member of the
  presage cargo workspace** (standalone git-dep = ~220 transitive-skew errors).

---

## Pointers

- `SIGNAL_PORT.md` — chronology + "Historical: abandoned Signal-iOS compile"
  (milestone ladder, pod→SPM map, exclude strategy).
- `/Users/jperla/claude/QuillUI/docs/appkit-reimplementation.md`,
  `/Users/jperla/claude/QuillUI/docs/porting-lessons.md` — the ObjC frontier +
  `QuillSourceLowering`/`AppKitLowering` (the real fix). **Coordinate here.**
- `/Users/jperla/claude/QuillSignal/FINDINGS.md` — presage de-risk phases.
- `.upstream/signal-ios` (~2554 Swift + 33 `.m`), `.upstream/libsignal`
  (`libsignal_ffi.a` built), `.upstream/wireguard-apple`.
- Package.swift gates: `signalUpstreamPresent`, `libsignalUpstreamPresent`,
  `nnwUpstreamPresent`; `signalAppleFrameworkShims`; `SignalServiceKit` ~L1489.
