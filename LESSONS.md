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
   1 (DB-write/receipt/notification side effects deferred).

   **✅ MESSAGE-SUBCLASS SPINE COMPLETE.** `TSInfoMessage` (+`InfoMessageUserInfoKey`
   NS_STRING_ENUM, `5075929`, →168204), `TSOutgoingMessage` (pass 1, `b333766`,
   →**139678, −28526** the biggest subclass: 13 columns, the 40-param SDS init,
   real NSSecureCoding encode/initWithCoder + both builder inits, recipient-state
   computation deferred). Notes: a subclass that re-declares an already-inherited
   protocol (TSOutgoingMessage `<NSSecureCoding>`, inherited from TSMessage) is a
   **redundant-conformance error → drop it**; the "1 extension-override" for
   TSOutgoingMessage/TSGroupModel turned out to be **test-only** (not in the
   `--target SignalServiceKit` build) so no relocate was needed. **From the 377k
   peak: −237,805 (~63%)** across 15 zero-error commits.

   **✅ POST-SPINE RESIDUAL CLEARED (377k peak → 93,695, ~75%).** After the spine,
   the long tail fell to import-injection + same-module shims + a test-strip:
   - **`import FoundationNetworking`** (`8e52980`, −19,219): on Linux `URLRequest`/
     `URLSession`/`URLSessionWebSocketTask`/… live in the separate
     FoundationNetworking module. Added a `canImport`-gated pass to the inject
     script (harmless on Apple).
   - **Selector shims** (`968972b`, −15,128): the `Selector` band was NOT unlowered
     `#selector` (zero remain) — it was the missing `Selector` *type* (ObjC overlay,
     absent on Linux) + the missing `NotificationCenter.addObserver(_:selector:…)`
     overload. Define `Selector` + a no-op `addObserver` SAME-MODULE.
   - **UIColor / LocalizationNotNeeded / autoreleasepool shims** (`b23295c`,
     `47cea89`, `298711c`): `LocalizationNotNeeded` (an excluded ObjC inline), the
     `UIColor` `init(red:…)`/`init(white:…)`/`getRed` that the RSColor shim lacks
     (delegate to the base init — cross-module reachability gotcha: only SOME color
     inits are visible from SSK), and a no-op `autoreleasepool(invoking:)`.
   - **TEST-STRIP** (`fed062b`, `d889ade`, −7k): Signal **co-locates** XCTest *and*
     swift-testing test files (and `TESTABLE_BUILD`-only helpers like `InMemoryDB`)
     INSIDE the SignalServiceKit dir; SwiftPM compiles everything under the target
     path into the LIBRARY. `scripts/quill-signal-strip-tests.sh` removes any file
     under a `tests/` dir, named `*Test(s).swift`, or importing `XCTest`/`Testing`.
   Remaining (~94k): leaf ObjC classes to port (`OWSOutgoingArchivedPaymentMessage`),
   cascade-broken Swift files to root-fix (`CallRecord`/`GroupCallManager`), and two
   shim gaps (`UIApplication.State` needs the nested enum in QuillUIKit; the
   `contentHint` override-in-extension needs the durable lowerer-relocate).

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

### Track B framework-shim gaps + module identity (2026-06)

- **The `UIKit` module is `Sources/UIKitShim/`, NOT `Sources/QuillUIKit/`.**
  SSK `import UIKit` resolves `UIKitShim` (Package.swift target `UIKit`, path
  `Sources/UIKitShim`); `QuillUIKit` is a separate module. When an error says
  `'X' is not a member type of class 'UIKit.Foo'`, edit `UIKitShim/UIKit.swift`.
  Editing QuillUIKit changed nothing (byte-identical error count) -- always
  confirm which target owns a shadow type before editing it.
- **Framework-shim-gap pattern (clean, high-yield).** Many bands are one missing
  member on an existing Apple-framework shadow type; add it to the owning shim
  module and the whole band clears:
  - `UIApplication.State` -> `typealias State = UIApplicationState` (enum already
    existed) + lifecycle `Notification.Name` statics. (-1,004)
  - `LAError`/`LAContext`/`LAPolicy` -> `AppleFrameworkShims/LocalAuthentication/`.
    `LAError.Code`: iOS aliases touchID*/biometry* to the same raw, but a Swift
    enum cannot dup raws -> give each a distinct dummy raw (never constructed on
    Linux). SSK's own `LAError.*Localized` statics resolve once `LAError` exists.
  - `CNLabeledValue.localizedString(forLabel:)` -> static on the generic in
    `ContactsShim`; return the label (no Contacts localization on Linux).
  Shared QuillUI infra -- real commits on the branch, additive only, keep main
  green, swarm-sync to QuillUI main.
- **`Calls/` is excluded for mixed-language, not absence.** `CallRecord`/
  `CallRecordStore`/`GroupCallManager` are Swift but live under the excluded
  `Calls/` dir (`signalServiceKitExcludes`), so `Backups/` consumers get
  `cannot find type CallRecord`. Un-excluding the whole dir FAILS: `target ...
  contains mixed language source files; feature not supported` (Calls/ has
  `.m`/`.h`). To include the Calls *Swift*: exclude only the per-file ObjC
  sources + port the ObjC types they need (OWSGroupCallMessage etc.). Big lever
  (~1,100 errors) but multi-step.
- **Cascade vs excluded:** a `.swift` type with no own errors that consumers
  still `cannot find` may be EXCLUDED, not cascade-broken. Check
  `signalServiceKitExcludes` before hunting a root error.

### Track B framework-shim mechanics (2026-06, cont.)

- **Shim targets depend on QuillFoundation.** The Package.swift generator (~L1457)
  gives every `Sources/AppleFrameworkShims/<Fw>` target a `QuillFoundation` dep so
  a shim can return QuillFoundation's CoreGraphics shadow types (e.g. ImageIO's
  CGImageSource returns `CGImage`). No cycle: QuillFoundation -> QuillKit only.
  But NOT every CG type exists there yet -- `CGImage` does, `CGContext` does NOT
  (AvatarBuilder's `context.cgContext` is still a gap; QuartzCore's `render(in:)`
  takes `Any` to avoid referencing the missing type).
- **Linux CF gotchas.** A shim using `CFString`/`CFData`/`CFDictionary`/`CFURL`/
  `CFTimeInterval` must `import CoreFoundation` (swift-corelibs-foundation does
  NOT re-export them via `import Foundation` the way Apple does). A String literal
  is NOT convertible to `CFString` and a `CFString` GLOBAL is not Sendable, so
  declare `kC*` string keys as plain `String` (SSK uses them via `as String` /
  dict keys). `CACurrentMediaTime()` -> implement faithfully as
  `ProcessInfo.processInfo.systemUptime` (a real monotonic clock on Linux), not a
  stub -- timing stays accurate.
- **Extend `inject-foundation.sh` per transitively-imported framework.** When SSK
  files use an Apple-framework type WITHOUT importing it (transitive via the ObjC
  umbrella / UIKit on Apple), add a rule: define `<FW>_TYPES` regex +
  `inject_if_needed "$f" "<FW>" "$<FW>_TYPES"` in the loop, then re-run. Rules so
  far: Foundation, UIKit, ImageIO, CoreFoundation, QuartzCore (+ gated
  FoundationNetworking). `.upstream` is disposable -> the committed SCRIPT is the
  durable artifact (never commit `.upstream`).
- **Cross-module type-dodge.** When a shim init/method takes a type defined in a
  DIFFERENT module not reachable from the shim (SSK's same-module `Selector`, the
  missing `CGContext`), type the inert parameter `Any` -- the call site still
  passes its real value and the shim never inspects it. Used for
  `CADisplayLink(target:selector: Any)` and `CALayer.render(in: Any)`.
- **Yields this sweep:** Intents -5,572, ImageIO -970, QuartzCore -1,152,
  CoreFoundation-inject -858, UIApplication.State -1,004, LAError/Contacts -2,319.
  The framework-shim-gap pattern is the highest-yield clean lever; SSK 377k peak
  -> ~80k (~79% cleared). Remaining big bands are the EXCLUDED Calls (~7k occ) and
  Payments (~3k occ) mixed-language dirs + unported TS*/OWS* interaction
  subclasses (OWSRecoverableDecryptionPlaceholder, TSCall, ...).

### Track B subclass-port mechanics (2026-06, cont.)

- **Port symlinks MUST be relative.** A port lives in
  `Sources/SignalServiceKitObjCPort/Quill<Name>.swift` and is symlinked into
  `<SSK>/QuillPort/`. The link target MUST be relative
  (`../../../../Sources/SignalServiceKitObjCPort/<base>`): an ABSOLUTE symlink
  compiles standalone but SSK still reports `cannot find type` because the build
  container mounts the repo at a different path. `scripts/quill-signal-link-ports.sh`
  (re)creates all links correctly -- run it after adding a port, and on fetch.
- **Subclass-port override rules** (learned porting the TS*/OWS* interaction
  subclasses): (a) if the subclass's SDS `init(grdbId:...)` has the SAME
  signature as its base's -> it OVERRIDES, needs `public override init`; if it
  adds columns (different signature) -> NO override. (b) `init?(coder:)` is
  `@available(*, unavailable)` (fatalError) for any TSMessage/TSInfoMessage/
  TSErrorMessage subclass -- "not NSCoder-archived"; `init()` likewise. (c) a new
  readonly property is NOT an override unless the base actually declares it --
  the FRESH-build error is authoritative ("does not override" -> drop `override`;
  "requires an override keyword" -> add it). (d) port BOTH the SDS designated
  init (interaction deserializers, e.g. TSInteraction+SDS.swift) AND any thread/
  builder init that has Swift call sites; check call sites with
  `grep -A1 'ClassName($'` (constructions are newline-formatted). Omit builder
  inits with zero Swift callers.
- **Build staleness after editing a symlinked port:** swift incremental can
  serve a STALE compile -- the giveaway is an error citing a line number that no
  longer matches the file. Bust it: `touch` the Sources file AND rm+ln-recreate
  the symlink (link-ports.sh does the latter), then rebuild. Trust only a build
  whose error lines match the current file.
- **Ports landed:** OWSOutgoingArchivedPaymentMessage, OWSRecoverableDecryption
  Placeholder (-1,242), OWSDisappearingConfigurationUpdateInfoMessage (-706),
  OWSVerificationStateChangeMessage (-1,759). One TSInfoMessage/TSErrorMessage
  subclass port = ~700-1,800 errors cleared. TSCall is in the EXCLUDED Calls/
  dir -> not a simple port (part of the mixed-language band).

### Track B framework-shim + libc/header gaps (2026-06, ~81% cleared)

- **CocoaLumberjack shim** (-2,530): SSK's Debugging layer logs through it. Filled
  the shim with DDLogFlag/DDLogLevel (OptionSet), DDLogMessage (timestamp is a
  non-optional `Date` -- consumed by `DateFormatter.string(from:)` -- but the init
  takes `Date?` and defaults to `Date()`), the DDLogFormatter protocol, a no-op
  DDLog, DDTTYLogger/DDFileLogger/DDLogFileManagerDefault (open + a
  didArchiveLogFile override hook). A `static let sharedInstance` of a non-Sendable
  class type needs `nonisolated(unsafe)`. The OWSLogs.h inline helpers
  (ddLogLevel/ShouldLogFlag/ShouldLog{Error,Warning,Info,Debug,Verbose}) live in
  an excluded header -> defined in the same shim (the Debugging files already
  `import CocoaLumberjack`).
- **Excluded-header NON-class symbols** go where they're reachable: an NS_ENUM ->
  TSModelEnums.swift; OWSLogs.h log helpers -> the CocoaLumberjack shim;
  DebuggerUtils.h `IsDebuggerAttached()`/`TrapDebugger()` -> a same-module
  `QuillDebuggerUtils.swift` (mirror the non-DEBUG inline: false / no-op).
- **`Darwin.x` used UNGUARDED on Linux:** OWSMath/ConnectionLock call
  `Darwin.ceil/floor/round/close/fcntl` outside any `#if canImport(Darwin)`, so on
  Linux (no Darwin module) they fail. Fix = a same-module caseless `enum Darwin`
  forwarding to the stdlib (`x.rounded(.up)` etc.) and Glibc (close/fcntl). `flock`
  the struct is referenceable for the fcntl pointer param.
- **CGSize/CGRect/CGPoint -- DEFERRED, still open:** the QuillUI `CoreGraphics`
  module (Sources/CoreGraphics) re-exports only CGFloat; QuillFoundation does
  `@_exported import CoreGraphics`. Some SSK files `import Foundation` only and
  still `cannot find CGSize` (~302). Resolve next: find which module actually
  defines the geometry structs on this toolchain and inject that import (or add
  them to Sources/CoreGraphics). CGContext is genuinely absent (only CGImage
  exists in QuillFoundation) -> needs a class + CGColor/CGPath/CGGradient deps.
- **A correct fix can tick the count UP:** porting DebuggerUtils unblocked
  OWSSwiftUtils and exposed +31 real errors that were masked. Pair such a fix with
  a net-negative one in the same commit, or just accept it -- the newly-visible
  errors are real work, not a regression.

### Track B mixed-language-dir INCLUSION (2026-06, ~86% cleared, the big levers)

- **The technique (Calls -10.6k, Payments -3.4k):** an EXCLUDED mixed-language
  dir (`Calls/`, `Payments/` in `signalServiceKitExcludes`) blocks ALL its Swift,
  which causes huge `cannot find type` bands in the rest of SSK (CallRecord*,
  PaymentsHelperSwift, ...). To include the Swift: (1) PORT the dir's few ObjC
  classes as `Sources/SignalServiceKitObjCPort/Quill*.swift` -- Calls had only
  TSCall + OWSGroupCallMessage (TSInteraction subclasses); Payments had only
  TSPaymentModels (TSPaymentAmount/Address/Notification value types). Include the
  SDS init AND any BUILDER inits the (now-compiling) Backups archivers call --
  grep `<Class>($` in Backups for the arg labels. (2) In Package.swift REPLACE the
  bare dir-string with per-file excludes of ONLY its `.m`/`.h`. (3) rebuild +
  MEASURE; revert Package.swift if net-regression. SignalRingRTC IS a Linux shim
  module, so the Calls Swift's RingRTC imports resolve.
- **Do the ports FIRST, the Package.swift include SECOND:** the ObjC-class ports
  clear their `cannot find` bands independent of the dir inclusion (and are the
  inclusion's prerequisite). Each is its own committable milestone; the
  Package.swift one-liner is the next.
- **Inclusion exposes the dir's own residual Swift gaps** (e.g. SignalRingRTC HTTP
  types for CallHTTPClient; the OWSPaymentMessage ObjC chain in Messages/Payments/
  which is a SEPARATE dir from Payments/). These are follow-ups; the net is still
  hugely negative.
- **CGSize/CGRect/CGPoint resolved:** swift-corelibs Foundation provides the CG
  geometry value types -- the failing files just lacked `import Foundation` (they
  matched no other Foundation type). Fixed by adding the CG geometry types to
  inject-foundation.sh's FOUNDATION_TYPES.

### Track B override-band + UIKit-text tail (2026-06, ~88% cleared, 45.7k)

- **THE override-band distinction (clears thousands):** a subclass override error
  is one of two kinds. (1) `method does not override any method from its
  superclass` = the base member is genuinely MISSING -> ADD it `open` to the base
  port's CLASS BODY. Adding contentBuilder/dataMessageBuilder/buildPlaintextData/
  shouldSyncTranscript/buildSyncTranscriptMessage to QuillTSOutgoingMessage cleared
  -2,522. The SendableMessage protocol's `extension TSOutgoingMessage:
  SendableMessage` only implements threadUniqueId, so the rest were missing, not
  walled. (2) `property/method X is declared in extension of TSOutgoingMessage and
  cannot be overridden` (contentHint/shouldRecordSendLog/anyUpdateOutgoingMessage)
  = the genuine override-in-extension WALL -> DEFER to a durable lowerer pass that
  relocates the extension-declared members into the class body. This is the
  largest remaining deferred band (~600).
- **A whole missing superclass:** EditableMessageBodyTextStorage's overrides all
  failed because its base NSTextStorage was absent ("super has no superclass").
  Added `open class NSTextStorage: NSMutableAttributedString` to UIKitShim (the
  UIKit module). swift-corelibs NSMutableAttributedString already has
  beginEditing/endEditing (inherit, don't redeclare) but not fixAttributes; add
  the nested `NSTextStorage.EditActions` alias for callers.
- **UIKit text attributes are not in swift-corelibs Foundation** (-1,600): the
  standard NSAttributedString.Key statics (.font/.foregroundColor/.background
  Color/.paragraphStyle/.underline*/.strikethrough*/.link/.attachment) and
  NSParagraphStyle/NSMutableParagraphStyle (+ NSLineBreakMode/NSWritingDirection)
  are UIKit/AppKit additions -> add them to UIKitShim (raw values match Apple's;
  QuillAppKit has the canonical copy to model).
- **swift-corelibs-unavailable type -> shadow it:** DateComponentsFormatter is
  declared `@available(*, unavailable)` in swift-corelibs Foundation; a same-module
  class named `DateComponentsFormatter` shadows it (local declaration wins over
  the imported, unavailable one). UTType lives in the `UniformTypeIdentifiers`
  shim module; NSAdaptiveImageGlyph (iOS-18) needed even in dead `#available`
  branches because Swift type-checks them.
- **Shim files (Sources/UIKitShim, Sources/<Fw>) are direct-edit -- NOT symlinked.**
  Only Sources/SignalServiceKitObjCPort/*.swift are symlinked into QuillPort (and
  need touch+link-ports.sh after edits). Editing a shim is a plain Edit + rebuild.
- **Filling a placeholder framework shim (high-yield, low-risk):** an empty
  Sources/AppleFrameworkShims/<Fw> stub leaves every type cannot-find. READ the
  (often single) consumer first, then fill the shim with inert value-holders
  mirroring its exact usage: init param order = call-site order; methods return
  []/nil/false. UserNotifications (-1.7k) from the lone UserNotificationsPresenter
  -- center drops requests, delivered/pending lists empty, requestAuthorization
  reports NOT granted (honest: nothing is presented on Linux). NSDataDetector
  (same module via a QuillPort file, matches()->[]) and UIEdgeInsets (-0.4k)
  follow the same shape. Mark model classes `@unchecked Sendable`; a static-let
  of a non-Sendable class needs `nonisolated(unsafe)`.
- **Duplicate-type ambiguity across two shims -> consolidate + re-export:** a type
  declared in BOTH a core module (QuillUIKit) AND a dedicated framework shim makes
  any file importing both fail with `X is ambiguous for type lookup`, and that
  cascades (downstream contextual-type + keypath-inference failures that look
  unrelated). Fix: keep ONE authoritative declaration (the dedicated shim), DELETE
  the duplicate, and have the umbrella module re-export the shim
  (`@_exported import <Fw>` in UIKitShim + add the dep in Package.swift) so
  import-umbrella-only callers still resolve it. One correct consolidation clears
  the whole cascade, not just the ambiguous line (UN dedup: 41,371 -> 41,079 even
  though only ~6 lines named the type). Touches shared infra -> swarm-sync to main.
- **A shim whose OWN compile fails makes ALL its types "cannot find" in every
  consumer.** If a large existing shim shows a huge cannot-find for a type it
  clearly declares (e.g. AVAsset = 616 cannot-find from a 200-line AVFoundation
  shim), suspect the shim MODULE failed to build: one bad line emits no symbols,
  so every `import <Fw>` consumer can't find anything. ALWAYS grep the shim's OWN
  errors FIRST (`grep "<Fw>/<Fw>.swift.*error:"`). Root cause here: AVFoundation.
  swift referenced CGImage (a QuillFoundation type) without `import QuillFoundation`
  -> module failed -> AVAsset cannot-find module-wide. The AppleFrameworkShims
  targets already depend on QuillFoundation; just add the import. errors:5 (not a
  drop to 5 -- a dependency module failing to build aborts the whole SSK compile,
  so the log holds only the shim's own handful of errors; that signature = "fix
  the shim's own errors, rebuild").
- **AVFoundation media was the single biggest fill (-3,812).** AVAsset/AVURLAsset/
  AVAssetTrack/AVAssetImageGenerator/AVAssetReader(+TrackOutput)/AVAssetExportSession
  + the resource-loader API + AVAudioPlayer + the CoreMedia spine (CMTime,
  CMSampleBuffer/CMBlockBuffer, CM* getter funcs, AudioStreamBasicDescription) +
  audio-settings String keys. SSK uses the OLDER SYNC AVFoundation API (tracks(
  withMediaType:), asset.duration:CMTime, CMTimeMake) not the iOS-16 async `load`.
  All inert: assets not-readable, reader yields no samples, generator/export throw.
  CGAffineTransform is absent from swift-corelibs -> AVAssetTrack.preferredTransform
  typed Any. A correct big fill EXPOSES coherent residuals in the same consumers
  (audio keys, resourceLoader, AVAudioPlayer) -- pair them in a follow-on commit.
- **Framework-shim tail cleared (~91% of peak):** Network (NWConnection+NWListener
  added to the 1445-line shim -> SignalProxy), SDWebImage (SDAnimatedImage), DeviceCheck
  (DCError/DCAppAttestService App-Attest), AudioToolbox (SystemSoundID/AudioServices),
  SignalRingRTC (the big one, -1,436: SFUClient peek + PeekInfo/PeekRequest/PeekResponse/
  GroupMemberInfo + CallId + callIdFromEra/RingId + RingUpdate + the RingRTC HTTP bridge
  HTTPClient/HTTPDelegate/HTTPRequest/HTTPResponse/HTTPMethod). Each = read the consumer,
  fill inert, build, confirm shim own-errors empty, commit.
- **Cross-module UIImage subclass needs RSImage `open`** (was `public`). SDWebImage's
  `SDAnimatedImage: UIImage` couldn't subclass it from another module until RSImage
  became `open` (matches Apple, where UIImage/NSImage are open). A subclass adding NO
  stored properties INHERITS all of RSImage's inits (so `SDAnimatedImage(data:)` just works).
- **Exhaustive-switch enums: match the consumer's case set EXACTLY.** A consumer
  `switch x { ... }` with NO `default`/`@unknown default` (RingRTC enums are non-resilient
  Swift enums, treated as exhaustive) means the shim enum must declare PRECISELY the cases
  used -- extra cases break exhaustiveness, missing cases break the `.case` references.
  RingUpdate = the 7 cases the ring handler switches; HTTPMethod = exactly get/post/put/delete.
- **A member the consumer adds in its OWN extension must NOT be a stored member of the
  shim type.** SSK declares `var callId` in a `private extension PeekInfo`, so the PeekInfo
  shim must omit `callId` or it collides ("invalid redeclaration"/ambiguity).
- **swift-corelibs has no URL<->CFURL toll-free bridging** (`url as CFURL` fails on Linux).
  Defer as a CFURL-bridging residual (a pipeline-level `as CFURL`-strip or a real bridge),
  not a per-shim fix -- typing the shim param `CFURL` vs `URL` doesn't help; the cast itself
  is what fails.
- **Pure-math types can be FAITHFUL, not inert.** CGAffineTransform is absent from
  swift-corelibs but is just 2-D matrix math (no platform backend), so it's implemented
  for real in QuillFoundation (concatenating/inverted/rotated actually compute). Same
  could apply to any value type whose semantics are pure computation.
- **@convention(c) callback typealias can't take Swift class/struct params.** A SystemConfiguration
  `SCNetworkReachabilityCallBack` whose params are the (Swift class) reachability handle +
  (struct) flags is "not representable in Objective-C". Since the callback is inert (never
  fires) and the consumer passes a non-capturing closure literal, drop `@convention(c)` and
  use a plain Swift closure type -- the literal still converts. (The Context's pointer-only
  retain/release closures keep `@convention(c)` fine.)
- **A cross-shim residual is OK to DEFER rather than force a Package edit.** PassKit's
  `PKContact.phoneNumber`/`.postalAddress` are `CNPhoneNumber`/`CNPostalAddress` (Contacts),
  so PKContact needs a PassKit->Contacts package dep. Land the PassKit bulk, note the
  coupled residual, do it as a focused follow-on -- don't bloat one milestone with a
  cross-shim dependency mid-fill.
- **Real system C libs: prefer a `.systemLibrary` over an inert Swift shim.** `zlib` was an
  inert Swift framework-shim, but libz is present on Linux (zlib1g-dev) + macOS, so it became
  a real `.systemLibrary` (Sources/zlib: module.modulemap `link "z"` + shim.h `#include <zlib.h>`,
  pkgConfig "zlib") -- gzip/crc32 ACTUALLY work, and the upstream `import zlib` resolves
  unmodified. -1,979 (the whole z_stream/deflate/inflate/crc32/Z_* surface). To convert: remove
  it from the shim-name list, add the systemLibrary target + an explicit SSK dep, delete the
  Swift stub. **CRITICAL GOTCHA:** SwiftPM REUSES the stale `<name>.swiftmodule` from the cached
  `.build-linux` after a Swift-shim->systemLibrary switch, so `import zlib` resolves but exposes
  ZERO symbols. Delete the stale artifacts (`.build-linux/**/Modules/zlib.swiftmodule` +
  `**/zlib.build`) and rebuild -- then the systemLibrary takes and the symbols appear.

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
