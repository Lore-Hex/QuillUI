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
- **THE OVERRIDE-IN-EXTENSION WALL (-2,686, the single biggest lever): relocate
  extension members into the port class body.** Upstream declares overridable
  members (contentHint, shouldRecordSendLog, relatedUniqueIds, anyUpdateOutgoingMessage,
  updateWithSendSuccess, updateWithAllSendingRecipientsMarkedAsFailed, isStorySend,
  envelopeGroupIdWithTransaction, encryptionStyle) in `extension TSOutgoingMessage`,
  and subclasses do `override var contentHint { ... }`. On Apple this works because
  TSOutgoingMessage is @objc (dynamic dispatch allows overriding extension members);
  on Linux (no @objc) it's "X is declared in extension of 'TSOutgoingMessage' and
  cannot be overridden" -- 2,532 errors from 9 members x many subclasses. FIX:
  (1) re-declare the members in the PORT class body (QuillTSOutgoingMessage.swift);
  (2) an idempotent prepare-pipeline script (quill-signal-relocate-extension-members.sh,
  python regex, non-greedy to the first 4-space `^    }`) STRIPS the now-duplicate
  base decls from the upstream extensions. ACCESS LEVEL: declare them `internal`
  (no modifier), NOT `public`/`open` -- the upstream overrides are a MIX of internal
  and public, an override must be >= the base, internal is the minimum so internal
  overrides match and public overrides legally widen (a public base rejects the
  internal overrides: "override must be as accessible as the declaration it
  overrides"; an open base adds "as accessible as its enclosing type"). The port +
  subclasses are the same SSK module so no `open` is needed. Relocated-member BODIES
  call other extension methods (anyUpdate is itself a TSInteraction-extension method)
  -- fine, the class body can CALL extension methods, it just can't be overridden as
  one. Validate on a small batch first (the 7 one-liners before the 2 long ones).
- **GRDB `enum Columns must be declared public` (~208, next):** the generated
  *+SDS.swift `enum Columns: String, CodingKey, ColumnExpression` matches a public
  `TableRecord` requirement -> needs `public`. Same flavor of fix (a prepare-pass
  `public`-prefix, or relocate) -- separate sub-pass.

### Track B small-bounded tail (2026-06, ~95% cleared, 17.8k and dropping)

The override-in-extension wall (the 2.5k single lever) + GRDB-Columns + the
framework-shim tail are DONE. What's left is small bounded categories (<=~150
each) and small cannot-find clusters. New patterns from this stretch:

- **A get-set property SATISFIES a `{ get }`-only protocol requirement.** When a
  protocol declares `var x: T { get }` and the conformer needs `x` writable,
  just make the concrete one `{ get set }` (or a stored var, or get-set
  computed) -- NO protocol edit needed. (Used for `wasRead` across the
  TS*/OWS* read-tracking ports: `var wasRead: Bool { get { read } set { read = newValue } }`.)
- **cannot-override-mutable-with-readonly -> get-only computed over a private
  backing var.** A subclass that must `override` a property with a derived
  read-only value can't override a mutable stored prop ("cannot override mutable
  property with read-only property"). Fix: base declares `private var _x` +
  `open var x: T { _x }` (get-only computed); move the base's own sets to `_x`.
  Now the subclass legally `override var x: T { ...derived... }`. (TSGroupModel
  `groupMembers` so TSGroupModelV2 can derive it from membership.)
- **`@inlinable` can only reference public / usableFromInline.** An `@inlinable`
  function that calls into a C-shim module needs `public import <CShim>` -- a
  plain `internal import` hides the C symbols from the inlinable body
  ("X is internal and cannot be referenced from an @inlinable function").
  (COSUnfairLock's `os_unfair_lock_lock` in the inlinable lock wrapper.)
- **Darwin numeric constants (NSEC_PER_SEC/NSEC_PER_MSEC/MSEC_PER_SEC) are not
  in swift-corelibs.** Darwin vends them via `<mach/clock_types.h>` as UInt64;
  Linux Foundation does not. Fix: add them as **Linux-gated** `public let`
  globals in QuillFoundation (Darwin already defines them, so an ungated global
  collides on macOS), then `inject-foundation.sh` an `import QuillFoundation`
  into the consumers -- they `import Foundation` only (not UIKit, which already
  re-exports QuillFoundation), so they cannot see it otherwise. Also add
  QuillFoundation as a **direct SSK-target dep** (it was only transitive via
  UIKit) so the injected import resolves. -1392 (the constants were also
  blocking type inference across all 17 consuming files).
- **Methods declared in an EXCLUDED ObjC `.m` are simply MISSING from the port
  (distinct from override-in-extension).** TSMessage.m's
  `update(with: OWSLinkPreview/TSQuotedMessage/MessageSticker)` +
  `update(withContactShare:)` + `update(withIsPoll:)` aren't overrides of an
  extension member -- they don't exist in the compiled set at all (their .m is
  excluded). Fix: add them as `open func` to the port class body, each setting
  the matching stored prop directly (these run at message-PREP time, pre-insert,
  so a direct set is faithful enough; the upstream anyUpdate-wrap is a
  persistence concern). The three `update(with:)` overloads resolve by arg type.
  -650 (also unblocked type inference in the two call-site files).

- **PIPELINE MECHANICS GOTCHA (cost me a confused rebuild):**
  `prepare-linux-build-backend.sh` only does the **GTK/backend** prep -- it does
  NOT run the signal-upstream prepare scripts (inject-foundation / strip-tests /
  relocate-extension-members / publicize-sds-columns). Those are SEPARATE manual
  steps that mutate the **persistent** `.upstream` tree IN PLACE. So after you
  edit `inject-foundation.sh` (e.g. add a new inject rule), the build alone will
  NOT re-apply it -- you must re-run the script (inside docker: it uses GNU-grep
  `\b`) against `.upstream` first. `.upstream` persists across turns, so prior
  injections survive; re-running is idempotent, so just re-run the one you
  changed. Symptom of forgetting: your new rule's symbol stays "cannot find in
  scope" and the target file's `head` shows no injected import.

### Track B per-file-cap targeting + shim/type fixes (2026-06, ~95.6%, 16.2k)

- **TOPFILES is the lever now.** The Swift per-file diagnostic cap (~50/kind)
  means each "50"-count category is really ONE-FEW broken files. Add a TOPFILES
  line to the build (`grep -oE "(\.upstream|Sources)/[^:]+\.swift:[0-9]+:[0-9]+:
  error:" | sed 's/:line:col://' | sort | uniq -c | sort -rn`) and root-cause the
  FILE, not the diagnostic. To see one file's WHAT: `grep "FILE.swift:.*error:" |
  sed 's/^.*error: //' | sort | uniq -c | sort -rn`.
- **swift-corelibs HAS more than you think — verify before shimming.** A 1-file
  `swiftc` compile test proved Foundation 6.2 vends `NSAttributedString` +
  `.Key`; the only fix was adding it to inject-foundation's FOUNDATION_TYPES so
  the one Foundation-less consumer got `import Foundation` (−100). Test, don't
  assume absence.
- **vDSP / Accelerate is PURE-MATH -> faithful, not inert.** AudioWaveformSampler
  needed vDSP_Length/Stride + vflt16/vabs/vdbcon/vclip/meanv; wrote numerically
  faithful loops (honor stride). −650 (vDSP_Length was used beyond that file).
- **QuillKit CF* typealiases vs swift-corelibs CoreFoundation = ambiguity.**
  QuillKit defines `CFDictionary=[String:Any]`, `CFArray=[Any]`,
  `CFTypeRef=AnyObject`, `CFString=String`, `CFData=Data` and is `@_exported` by
  Security/UIKit/etc. A file importing BOTH a re-exporter AND swift-corelibs
  `CoreFoundation` sees two `CFDictionary` -> "CFDictionary is ambiguous for type
  lookup". Fix: inject-foundation now STRIPS (and skips) the CoreFoundation
  injection for files that use Security, **iff they reference only CF *types* and
  no real CF *functions*** (CFArrayCreate etc) — verified by grep before
  stripping. −425 (SSKKeychainStorage 144->0, Certificates->0). Generalizes to
  any QuillKit-re-exporter; widen the guard only after the no-CF-function check.
- **Extending an existing compatibility shim: grep what it ALREADY has.** The
  Security shim was huge but missing `errSecInteractionNotAllowed`, `SecPolicy`/
  `SecPolicyCreateSSL`, `SecTrustResultType`, `SecTrustGetTrustResult`,
  `SecTrustSetPolicies`. Read the consumer's exact call to get the signature, add
  only the gaps. TLS trust shims should accept (.unspecified / true) + carry a
  "needs native backend before production" note (these are not real TLS).
- **[Key: Any] vs [Key: AnyObject] is a real wall on Linux** (no NSDictionary
  bridge; Dictionary is invariant in Value). `AnyObject->Any` upcasts implicitly
  (so [K:AnyObject] args satisfy a [K:Any] param) but NOT the reverse. When a
  stored prop is [K:Any] and the SDS passes the prop value into subclass inits,
  make EVERY init in the class hierarchy take [K:Any] (the deserialize-side
  [K:AnyObject] locals still pass via upcast). Unify the whole hierarchy, not one
  class. (infoMessageUserInfo across TSInfoMessage + 3 subclass ports, −361.)
- **OPEN (still): GRDB `row[N].flatMap { Enum(rawValue: $0) }` infers
  `any DatabaseValueConvertible`** not the enum's RawValue on Linux Swift 6.2
  (works on Apple) -> "cannot convert any DatabaseValueConvertible to Int/UInt/..."
  (225 in TSInteraction+SDS). Likely a GRDB index-subscript overload-resolution /
  version-skew issue; needs a prepare-pass type annotation or a GRDB-pin probe.

### Track B GRDB/sqlite + drawing-shim pass (2026-06, ~96.2%, 14.2k)

- **GRDB 7.10 Row index subscript has NO generic-optional overload.** It vends
  `subscript(_:Int) -> (any DatabaseValueConvertible)?` (non-generic) and
  `subscript<Value>(_:Int) -> Value` (non-optional generic). So
  `row[N].flatMap { Enum(rawValue: $0) }` (needs an Optional to flatMap, and the
  closure to pick the element type) falls to the existential overload ->
  "cannot convert any DatabaseValueConvertible to Int/UInt/...". Signal builds
  against a GRDB fork that has the optional generic subscript. RESOLVED by a
  prepare-pass (quill-signal-fix-sds-rowsubscript.sh) rewriting to the idiomatic
  typed cast `(row[N] as Enum.RawValue?).flatMap { ... }` -- the `.RawValue`
  avoids needing each enum's concrete underlying type, and `as T?` selects the
  generic subscript with Value=Optional<...> (Optional conforms to
  DatabaseValueConvertible when Wrapped does). Adding an extension subscript
  instead would make `row[N] as T?` ambiguous, so prefer the prepare-pass. -389.
- **Raw sqlite3 C API -> GRDB's GRDBSQLite product.** ~12 SSK files use SQLITE_OK
  / sqlite3_errmsg / sqlite3_step etc. On Apple these come via the bridging
  header; GRDB already ships `GRDBSQLite` as a `.library` product whose module
  map is `link "sqlite3"` (real libsqlite3, faithful). Add it to the SSK target
  deps + an inject-foundation rule (SQLITE_TYPES -> import GRDBSQLite). -606. Lesson:
  before shimming a C API, check whether a dep already vends it as a product.
- **swift-corelibs renamed APIs are hard errors.** decodeTopLevelObject(of:forKey:)
  -> decodeObject(of:forKey:) (same signature). Fix via a fetch-upstream
  patch_signal_ios python replace (the `try` on the now-non-throwing call is a
  harmless warning). Place such patches BEFORE blocks that have early-returns.
- **@objc optional protocol after the @objc-strip.** The lowering pass turns
  `@objc protocol` into plain `public protocol`, leaving `optional func` invalid.
  Model optionality the Swift-native way: drop `optional`, add a default no-op
  extension, and drop the `?` optional-chaining at call sites. Verify which
  members conformers actually skip (those defaults are load-bearing).
- **Font/text shims: UIKit, not Foundation; Linux-gate to avoid AppKit clash.**
  RSFont needed withSize / init?(name:size:) (failable, named font absent) /
  lineHeight / capHeight (approx ~1.2x / 0.7x point size). String drawing
  (NSStringDrawingOptions, NSStringDrawingContext, String.boundingRect/draw) is a
  UIKit extension, absent from swift-corelibs -- added to the UIKit shim under
  `#if os(Linux)` so AppKit's own String.boundingRect doesn't collide on macOS.
  boundingRect returns a rough estimate from the `.font` attribute; draw is inert.
  UIFont -296, NSString-drawing -425 (the String ext cascades widely; expect a
  few files to tick UP as masked downstream errors surface -- net strongly down).

### Track B Mach/ImageIO/sqlite + shim-isolation pass (2026-06, ~96.8%, 12.1k)

- **Find the SHARED shim that serves many call sites.** The cheapest fixes this
  stretch each cleared multiple files at once: GRDBSQLite (12 raw-sqlite3 files,
  -606), the Mach task_info+malloc-zone shim (Bench 267 + LocalDevice 240 -> 0,
  -805 -- both did process-memory introspection via the same absent Mach APIs),
  the GRDB Row-subscript prepare-pass (-389). When a recurring category spans
  several TOPFILES, one shim usually covers them.
- **Mach / Darwin-C symbols are used UNQUALIFIED** (Darwin makes them implicit on
  Apple) -> put them as TOP-LEVEL decls in the QuillDarwin.swift port (it is in
  the SSK module, so unqualified refs resolve). Inert task_info returns
  KERN_SUCCESS with the info struct left zeroed (footprint 0); sysctlbyname sets
  out-length 0 + returns -1 so `guard size > 0` cleanly bails.
- **Inert @MainActor shim used from nonisolated SSK -> just drop @MainActor.**
  The haptic generators were @MainActor (matching UIKit) but SSK constructs them
  off-main. They are no-op shims, so relaxing isolation is correct and never
  breaks a main-actor caller (-397, every caller's main-actor-init error).
- **GRDB ships the C SQLite as a PRODUCT (GRDBSQLite, link sqlite3).** Before
  shimming a C API, check whether a dependency already vends it -- add the
  product to deps + inject the import.
- **swift-corelibs renamed/removed APIs are HARD errors.** decodeTopLevelObject
  -> decodeObject (fetch-upstream patch). And some bridges are simply absent:
  URL->CFURL, [String:CFBoolean?]->CFDictionary (kCFBoolean* is real corelibs
  CoreFoundation, optional) -- these need a real workaround, not a type shim.
- **CGImage/UIFont/NSString-drawing are UIKit/CoreGraphics, not Foundation.**
  Verified-absent (1-file swiftc) then added Linux-gated: CGImage decode inits +
  CGColorRenderingIntent + width/height/cropping (inert, 0-dim); UIFont
  withSize/init?(name:size:)/lineHeight/capHeight (approx metrics); the NSString
  drawing surface. Cross-module type-dodge: param typed `Any` when the real type
  (CGDataProvider) lives in a module that depends on you.
- **NLLanguageRecognizer + NSHashTable**: two more verified-absent types; the
  recognizer is inert (no on-device language model on Linux), NSHashTable is an
  unconstrained-generic strong-ref stand-in (weak semantics deferred).
- **COMMIT GOTCHA:** no backticks in `git commit -m` -- they trigger shell
  command-substitution and silently eat text (parens in double quotes are fine).

### Track B Contacts/QoS/notify + witness pass (2026-06, ~97.3%, 10.8k)

- **A shim FIELD's TYPE matters, not just its existence.** The recurring
  "type Int has no member userDefault" (50, across files) was
  CNContactFetchRequest.sortOrder typed `Int` in the shim instead of the
  CNContactSortOrder enum (which has `.userDefault`). One-line type change
  cleared the whole category. When a category is "type X has no member Y",
  suspect a shim property declared with too-loose a type.
- **A shim TYPE is only as good as the import PATH to its consumer.** NSHashTable
  was added to QuillFoundation but never resolved in MessagePipelineSupervisor,
  which imports ONLY Foundation (no UIKit/QuillFoundation). Fix: add such
  QuillFoundation-only symbols (NSHashTable, NSEC_*) to the inject-foundation
  QuillFoundation rule so consumers get `import QuillFoundation`. Don't assume a
  re-exporter (UIKit) covers a file -- check its actual imports.
- **CNError-style bridged-error pattern.** `catch CNError.communicationError` /
  `case CNError.communicationError` need a static value + an expression-pattern
  `static func ~= (pattern:error:)` (and the code Equatable) so both type-check
  (the inert store never throws it -- compile-only).
- **Darwin C subsystems = top-level QuillDarwin port decls (unqualified) OR a
  named module shim (qualified import).** Mach (task_info), sysctlbyname, Dispatch
  QoS (qos_class_t + QOS_CLASS_* at real values so rawValue ranges hold) are used
  unqualified -> top-level in QuillDarwin. notify(3) is `import notify` -> fill
  the `notify` shim MODULE. All inert (no real bus/telemetry on Linux).
- **A SendableMessage-style protocol requirement whose witness lives in an
  excluded .m** shows up as Swift's "different argument labels ... required by
  protocol" near-miss diagnostic. The conformer is just MISSING the method -- add
  it to the port class body (update(withHasSyncedTranscript:) on TSOutgoingMessage).
- **Pattern recap (shim members):** CGImage decode-inits/width/height/cropping,
  UIFont metrics, RSScreen.nativeBounds (= bounds*scale) -- all UIKit/CG, not
  Foundation; Linux-gate, approximate/inert. Still-OPEN hard nut: the genuine
  swift-corelibs CF-bridging gaps (URL->CFURL, [String:CFBoolean?]->CFDictionary
  where kCFBoolean* is real-corelibs optional) in BadgeAssets -- need a real
  workaround (a helper that builds the CFDictionary/CFURL), not a type shim.

### Track B tail to <10k (2026-06, ~97.5%, 9.6k)

The remaining ~10k were concentrated, harder clusters than the mid-game bands.
Patterns that closed them:

- **Darwin C subsystems used UNQUALIFIED -> top-level QuillDarwin port decls.**
  Mach task_info/task_vm_info + malloc-zone (Bench+LocalDevice, -805),
  sysctlbyname (String+SSK device model), Dispatch QoS (qos_class_t +
  QOS_CLASS_* at real values for the rawValue-range switches). All inert.
- **Named-module C subsystems -> fill that module's shim.** notify(3)
  (DarwinNotificationCenter, inert), System/swift-system (FileDescriptor made
  FAITHFUL over POSIX open/lseek/read/close -- real file I/O for attachment
  crypto), CFHost (CFNetwork shim, real-CoreFoundation context: Unmanaged +
  return Unmanaged<NSArray>? so the `.takeUnretainedValue() as NSArray?` cast
  works without the absent CFArray<->NSArray bridge).
- **Shim type exists but the consumer can't see it.** Verify with a 1-file
  swiftc test FIRST -- often swift-corelibs/an existing shim already HAS the type
  (NSAttributedString, AVSpeechUtterance, NSHashTable) and the only gap is the
  import PATH -> add an inject-foundation rule, don't write new shim code.
- **SHIM-OWN-COMPILE-FAILURE.** A consumer "has no member X" can mean the
  extension FILE that defines X failed to compile (CGDataProvider+SSK couldn't
  find CGDataProvider -> needs import ImageIO). Grep the defining file's OWN
  errors first.
- **inout vs pointer param.** A shim method taking `error: inout NSError?`
  rejects a literal `nil` caller; use NSErrorPointer-shaped
  `UnsafeMutablePointer<NSError?>?` (LAContext.canEvaluatePolicy).
- **Excluded-.m members keep surfacing** as overrides (relocate to port class +
  extend the strip script -- TSInteraction.anyDidInsert/anyDidUpdate),
  protocol witnesses (SendableMessage.update(withHasSyncedTranscript:)),
  override-bases (TSOutgoingMessage.buildDataMessage), bridged-error patterns
  (CNError.communicationError -> static value + `~=`), and free enums
  (OutgoingGroupProtoResult -> match the caller's switch cases exactly).
- **Still-OPEN hard nuts:** the genuine swift-corelibs CF-bridging gaps
  (URL->CFURL, [String:CFBoolean?]->CFDictionary where kCFBoolean* is real
  corelibs-optional) in BadgeAssets need a real helper, not a type shim;
  PKContact (PassKit needs a Contacts dep); selector-based Timer / NSObject
  .perform (NSTimer+OWS) absent on swift-corelibs.

---

### Track B sub-9.3k: import-path-via-existing-import + SHIM-OWN close (2026-06, ~97.6%, 9.27k)

- **The import PATH can be the consumer's OTHER existing import.** When a
  consumer needs a Foundation-extension shim but does NOT import QuillFoundation,
  you don't always need a new inject-foundation rule -- put the inert extension
  in a shim module the consumer ALREADY imports. LogFormatter imports
  `CocoaLumberjack` (not QuillFoundation) and sets
  `formatter.formatterBehavior = .behavior10_4` (swift-corelibs DateFormatter has
  neither the property nor a Behavior enum) -> shim `extension DateFormatter {
  enum Behavior; var formatterBehavior (no-op get/set) }` INSIDE the
  CocoaLumberjack shim. Cheapest path = whatever import is already on the file.
  (`formatterBehavior` is also a contextual member, awkward to regex for an
  inject rule -- another reason to host it where it's already visible.)
- **SHIM-OWN-COMPILE-FAILURE, closed (the @convention(c) callback-struct case).**
  `CGDataProvider` was an empty `class CGDataProvider {}` stub; CGDataProvider+SSK
  needs `CGDataProviderDirectCallbacks` (a struct of `@convention(c)` fn-pointer
  fields) + `CGDataProvider(directInfo:size:callbacks:)`. Missing -> the
  extension file failed to compile -> 48 call sites saw "has no member 'from'".
  Fix = fill the stub's missing surface in the ImageIO shim + add CGDataProvider
  to the ImageIO inject regex. Two sub-lessons: (1) when YOU own a Linux callback
  struct, type its params to the CONSUMER's usage, not Apple's -- the position
  param is `UInt64` (not Apple's `off_t`/Int64) because the upstream closure
  compares it to `FileHandle.offset()` (UInt64) directly; (2) an inert init can
  still need to DO something -- here it invokes `releaseInfo(info)` to balance
  the caller's `passRetained`, else the FileHandle wrapper leaks.

---

### Track B sub-8.8k: raw-pointer overloads + import-path statics (2026-06, ~97.8%, 8.76k)

- **Raw->typed pointer mismatches at Foundation method calls -> a raw-pointer
  overload in a same-module port.** swift-corelibs imports several Foundation
  methods with typed `UnsafePointer<UInt8>` params where SSK passes a
  `withUnsafeBytes`/`withUnsafeMutableBytes` `baseAddress` (an
  `UnsafeRawPointer`). Two instances closed the same way: `NSCoder.encodeBytes`
  (ECKeyPair) and `OutputStream.write`/`InputStream.read` (OWSMultipart,
  InputStream+SSK, OutputStreamable). Fix = add an overload taking the raw
  pointer and forward via `assumingMemoryBound(to: UInt8.self)`. Three notes:
  (1) one raw overload ALSO catches an `UnsafePointer<Int8>` call site, since
  `UnsafePointer<Int8>` converts to `UnsafeRawPointer`; (2) no recursion -- the
  forwarded `UnsafePointer<UInt8>` exact-matches the base method, not the
  overload; (3) host it in a same-module PORT file (QuillStream/QuillNSCoder),
  visible to every SSK file with no import. A NEW port file is auto-picked-up
  (link-ports globs `*.swift`); touch the linked copy before building.
- **Absent Notification.Name/static -> host it where the consumer already
  imports, and mind actor isolation.** DeviceBatteryLevelManager aliases
  `UIDevice.batteryLevelDidChangeNotification` + `.NSProcessInfoPowerStateDidChange`
  (both absent). It does `public import UIKit`, so both inert names went into the
  UIKit shim (import-path-via-existing-import again -- even though the
  ProcessInfo one is conceptually Foundation; its sole consumer imports UIKit).
  WRINKLE: a `static let` on a `@MainActor` class (UIDevice) is MainActor-
  isolated, so a file-scope `extension Notification.Name` aliasing it fails
  ("main actor-isolated ... from a non-isolated context") -- mark the static
  `nonisolated` (Notification.Name is Sendable). Linux-gate names macOS
  Foundation already defines (NSProcessInfoPowerStateDidChange); the UIKitShim
  compiles on macOS too.

---

### Track B sub-8.3k: module-qualified shims, unavailable-API patches, partial-corelibs converters (2026-06, ~97.9%, 8.25k)

- **Shim a module-QUALIFIED type by adding it to that module's shim.** SSK wraps
  `SignalRingRTC.CallLinkState` (reads name/restrictions/revoked/expiration/rootKey)
  and maps its `.Restrictions` to an Int enum; the RingRTC shim only had
  CallLinkRootKey, so every reference was "no type named 'CallLinkState' in module
  'SignalRingRTC'" (~100+). Add the struct + nested enum to SignalRingRTCShim with
  EXACTLY the enum cases SSK's mapping switches over (none/adminApproval/unknown --
  exhaustive, no default). The real value is FFI-produced on the deferred calling
  paths; the non-calling paths only read fields, so a faithful shape suffices.
- **Unavailable swift-corelibs API -> fetch-upstream patch (+ apply once to
  .upstream).** `URLSessionConfiguration.background(withIdentifier:)` is
  `@available(unavailable)` on non-Darwin. One call site (ReachabilityManager) ->
  rewrite to `.default` in a patch_signal_ios() block. fetch-upstream patches run
  at FETCH only, so ALSO apply the same replacement to the live .upstream once
  (python3 inline before the build) -- else the persistent tree stays unpatched.
  Cleared the category even though the file kept SEPARATE errors (SCNetworkReachability)
  -- judge by category, not whole-file.
- **swift-corelibs has SOME of a convenience family but not all -- verify each.**
  NSKeyedUnarchiver HAS `unarchivedObject(ofClass:/ofClasses:from:)` and
  NSKeyedArchiver HAS `archivedData(...requiringSecureCoding:)`, but it LACKS the
  typed-collection converters `unarchivedArrayOfObjects(ofClass:from:)` /
  `unarchivedDictionary(ofKeyClass:objectClass:from:)` (1-file swiftc confirmed
  exactly which). Implement the missing two over the multi-class
  `unarchivedObject(ofClasses:from:)` that DOES exist, then bridge-cast to the
  typed Swift collection -- in a same-module port (QuillNSCoder), no import
  needed. Cleared SDSDeserialization entirely and KeyValueStore 75->25. Don't
  assume a whole API family is present or absent; probe member by member.

---

### Track B sub-7.9k: cross-module visibility, C-struct & init shims, inert raster (2026-06, ~98.2%, 7.87k)

- **CROSS-MODULE shim/extension members MUST be public.** A shim in a *separate*
  module (QuillFoundation, UIKitShim, the AppleFrameworkShims) is only visible to
  SSK consumers if its members are `public`. An inert `extension sockaddr_in {
  var sin_len }` added as `internal` left ReachabilityManager still red and the
  count unchanged -- the rebuild that added `public` fixed it. (SAME-module PORT
  files -- QuillNSCoder/QuillStream/QuillIndexPath, linked into SSK -- can stay
  internal.) Note: `grep -c SYMBOL` counts swiftc's context lines too (~6-24x per
  distinct error), so a fix can look like it INCREASED a symbol's mentions; count
  distinct with `grep -E "FILE.swift:[0-9]+:[0-9]+: error:" | wc -l`.
- **You can extend a C struct with an inert computed property.** `sockaddr_in`
  (Glibc) lacks Apple's BSD `sin_len` length byte. `extension sockaddr_in { public
  var sin_len: UInt8 { get {0} set {} } }` (canImport(Glibc)-gated, in the
  SystemConfiguration shim the consumer imports) lets the assignment compile;
  Linux derives socket length from the address family so the value is ignored.
- **A convenience init delegating to the designated init adds an arg-variant
  without losing init().** AVAsset only had `init()`; `convenience init(url:) {
  self.init() }` added the URL form AttachmentContentValidatorImpl calls, while
  keeping the `init()` that the AVURLAsset subclass's `super.init()` relies on.
- **A UIKit-ism the consumer needs but can't import -> same-module port.**
  `IndexPath(row:section:)` is a UIKit add (corelibs IndexPath has only
  init(indexes:)); CollectionDifference+SSK imports only Foundation, so the
  convenience went in a new same-module port (QuillIndexPath) delegating to
  init(indexes: [section, row]).
- **Inert raster: fill the CGContext bitmap surface, return nil.** BlurHash builds
  a CGContext bitmap context (CGBitmapInfo | CGImageAlphaInfo -> UInt32 bitmapInfo,
  then CGContext(data:...) + makeImage()). Added CGBitmapInfo (OptionSet) +
  CGImageAlphaInfo (enum) with Apple's raw values, an inert bitmap init, and
  makeImage()->nil to QuillFoundation's CG shim. The existing setFillColor/fill/
  draw no-ops mean the whole path compiles and yields nil (placeholder rendering
  deferred). BlurHash 150->50. Diagnostic-only "extra argument"/"takes no
  arguments" usually means a shim type/init is MISSING an arg-variant, not that
  the caller is wrong.

---

### Track B sub-7.6k: empty-module shims + the OMITTED-builder-init pattern (2026-06, ~98.5%, 7.57k)

- **An empty placeholder shim module just needs its consumed surface filled.**
  `import blurhash` resolved to an empty stub, so `image.blurHash(numberOfComponents:)`
  + `UIImage(blurHash:size:)` were "no member"/"extra argument 'size'". Filled the
  blurhash shim with a `public` UIImage extension: encoder -> nil, failable
  `init?(blurHash:size:punch:)` -> nil (both inert; callers treat nil as
  "couldn't compute"). `public` (cross-module); UIImage/CGSize via the shim's
  QuillFoundation dep. A failable convenience init may `return nil` immediately
  without calling self.init().
- **"argument passed to call that takes no arguments" at a port-class call site =
  the port OMITTED a builder init.** Several ports kept only the SDS (grdbId)
  init; their `.m` builder inits were dropped as "no callers" -- but callers DID
  surface (OWSRecoverableDecryptionPlaceholder, OWSIncoming/OutgoingPaymentMessage,
  OWSIncomingArchivedPaymentMessage). The call then binds to the unavailable
  `init()` -> "takes no arguments". Fix per class: port the `.m` builder init as a
  **designated** `init` (NOT convenience -- the subclass already declares its own
  designated init, so it does NOT inherit the superclass inits, and `self.init`
  can't reach them) that (1) sets the subclass's stored props, (2) calls
  `super.init(<base builder init>)` -- TSErrorMessage(errorMessageWithBuilder:),
  TSIncomingMessage(incomingMessageWithBuilder:), TSOutgoingMessage(outgoingMessageWith:
  additionalRecipients:explicitRecipients:skippedRecipients:transaction:). A
  failable one (placeholder) may `return nil` before super.init since the subclass
  has no stored props to leave uninitialized. Read the `.m` for the exact super
  call + simplify deferred branches (placeholder: contact-thread only, no
  TSGroupThread.fetchWithGroupId). Cleared 4 files + the whole category.

---

### Track B sub-7.0k: fetch-patch renames, @_disfavoredOverload, and the OWN-grep blindspot (2026-06, ~98.7%, 7.02k)

- **swift-corelibs / GRDB API renames & removals -> fetch-upstream patch** (one
  line often clears a whole file). ProxiedContentDownloader: `NSURL.fileURL(withPath:)`
  (corelibs only has withPathComponents:[String], returns URL?) + `.atomicWrite`
  (now `.atomic`) -> rewrite to `URL(fileURLWithPath:)` + `.atomic` (100->0).
  GRDBDatabaseStorageAdapter: drop `Configuration.defaultTransactionKind` ("now
  automatically managed") + `.automaticMemoryManagement` (removed). Always ALSO
  apply the replacement to the live .upstream once (fetch-patches run at fetch).
- **NSFileCoordinator absent -> inert same-module port** (init(filePresenter:) +
  coordinate(writing/readingItemAt:options:error:byAccessor:) that just runs the
  accessor with the same URL; single-process DB on Linux). Its WritingOptions
  OptionSet needs `.forMerging`. swift-corelibs has NO `NSErrorPointer` typealias
  -> type the error param `UnsafeMutablePointer<NSError?>?` directly.
- **THE BLINDSPOT: the OWN-errors grep was checking the wrong path.** Port files
  live at `Sources/SignalServiceKitObjCPort/` but link-ports compiles them at
  `.upstream/.../SignalServiceKit/QuillPort/`, so an OWN grep keyed on
  `SignalServiceKitObjCPort/` NEVER matched port-body errors. QuillNSCoder.encodeBytes
  + QuillStream.write/read had `ambiguous use of ...` errors in their bodies the
  whole time (~50, counted but invisible to OWN). External callers (raw pointers)
  resolved to these overloads fine, masking the broken bodies. FIX the grep to
  include `QuillPort/.*error:`.
- **@_disfavoredOverload resolves raw/typed-pointer overload ambiguity.** A raw
  overload `f(UnsafeRawPointer)` next to the corelibs base `f(UnsafePointer<UInt8>)`
  makes the internal forward (a typed pointer, which converts to raw) ambiguous.
  Mark the raw overload `@_disfavoredOverload`: the typed internal forward picks
  the base, external raw-pointer calls still pick the overload.

---

### Track B sub-5.6k: generic decode converters, @_exported import path, init-override trap, nonisolated instance vars (2026-06, ~99%, 5.62k)

- **One missing NSCoder convenience can gate many files.** `decodeArrayOfObjects(
  ofClass:forKey:)` (absent on corelibs) is used by ~9 NSSecureCoding decoders;
  adding it (generic `-> [DecodedObjectType]?` over `decodeObject(forKey:) as?`,
  in the QuillNSCoder port) cleared all 9 + cascades (-820 in one build). Apple's
  is generic so `ofClass: NSData.self` yields `[NSData]?` and callers bridge
  `as [Data]?`. Same shape as the NSKeyedUnarchiver converters.
- **UIKit shim re-exports QuillFoundation** (`@_exported import QuillFoundation`
  in UIKitShim), so ANY symbol added to QuillFoundation OR UIKitShim is visible to
  every SSK file that does `import UIKit`. That's the import path for the UIKit-
  text cluster (String+SSK): NSTextAttachment, UIImage.withRenderingMode +
  RenderingMode, NSParagraphStyle.defaultWritingDirection, NSAttributedString(
  attachment:) -- all inert, in UIKitShim.
- **You CANNOT add a no-arg `init()` to an NSObject subclass via extension** --
  "initializer 'init()' declared in 'NSObject' cannot be overridden from
  extension". `NSAttributedString()`/`NSMutableAttributedString()` (corelibs lacks
  a usable parameterless init) must instead be a fetch-upstream patch rewriting
  the call sites to `(string: "")`. Tell: the broken extension still DECLARES the
  init (so consumers compile) while its body errors -- check OWN (incl QuillPort/).
- **`nonisolated` is needed for INSTANCE computed vars too, not just statics**, on
  a `@MainActor` class accessed from a nonisolated consumer. UIDevice is
  @MainActor; ProximityMonitoringManager reads `UIDevice.current.proximityState`
  off the main actor -> mark the inert `proximityState`/`isProximityMonitoringEnabled`
  vars `nonisolated` (Bool is Sendable), same as the battery/proximity static
  notification names.

---

### Track B sub-5.1k: the medium-file long tail -- UIColor/UIDevice/Intents/Locale (2026-06, ~99.2%, 5.09k)

Below ~6k the top files are a steady 72-150-error tail; each is usually 2-3
concentrated causes. Pattern: build, grep the file's distinct WHAT, fix the
cleanest, repeat. Recent clears:

- **UIColor math accessors.** RSColor (= UIColor) needed getRed(_:green:blue:alpha:)
  (write stored RGBA into out-pointers, return true), getHue(...) (real RGB->HSB),
  and init(hue:saturation:brightness:alpha:) (HSB->RGB convenience init delegating
  to the RGBA designated init). Cleared UIColor+OWS + UIColor+SSK (UIColor.components()
  builds on getRed). All in QuillFoundation (visible via UIKit's @_exported).
- **More UIDevice inert members** (same shim, same nonisolated rule as battery/
  proximity): systemVersion/model (AppVersion), proximityState/isProximityMonitoringEnabled
  + the two *DidChangeNotification names.
- **Intents donation metadata.** INInteraction needed groupIdentifier + direction
  vars (the enum already had .outgoing) -- inert; the interaction is never
  registered on Linux. (ThreadUtil.donateSendMessageIntent.)
- **swift-corelibs makes some Apple-public members `internal`.** (locale as
  NSLocale).countryCode -> "inaccessible due to internal protection level". Use the
  public Swift API instead (Locale.regionCode) via a fetch-patch -- don't try to
  widen corelibs' access.

---

### Landing Track B infra on main: the #424 -> #428 split + CI gauntlet (2026-06-07)

The Track B SSK shim/port/script infrastructure was landed on `main` (gated, so it
does NOT affect main's build/CI) via PR #428 (merge bb2fd654). The road there taught
several CI/packaging lessons worth keeping:

- **Split Track B from Track A before merging.** The long-lived `signal/real-backend`
  branch (254 commits) tangled the SSK infra (the goal) with half-baked Track A
  QuillSignal chat-UI experiments (QuillSignalKit, QuillChatKit chat features) that
  violated main's source-hygiene/manifest tests. PR #424 (whole branch) was abandoned;
  PR #428 brought ONLY the gated infra onto a fresh branch off main. Mechanism: branch
  off main, `git checkout <oldbranch> -- <track-B paths>` for the additive shim/port/
  script dirs + the infra modifications to shared files, hand-reconstruct Package.swift
  (drop the Track-A target/product/dep hunks), DON'T bring the Track-A files.
- **Gate criteria for a NEW Signal target/package-dep behind `signalUpstreamPresent`:**
  (a) it has external system deps CI lacks (CommonCrypto -> libssl/openssl), (b) it's a
  *package dependency* only Signal uses (swift-crypto, swift-protobuf -- an unused
  package dep makes the warning-clean Qt-product gate FAIL with "dependency X is not
  used by any target"), or (c) it's signal-only AND not depended-on by an always-built
  target. Gate its sole consumer too (CryptoKit -> swift-crypto). Do NOT gate the inert
  AppleFrameworkShims (`#if os(Linux)` only) -- the always-built UIKit shim depends on
  some (UIKit `@_exported import UserNotifications`); gating them dangles that dep and
  invalidates the whole manifest (every job fails fast at resolution).
- **Hygiene tests read Package.swift as TEXT and pin exact substrings.** A deliberate
  manifest change needs the matching pin updated: UIKit's deps list (+UserNotifications)
  -> QuillDataSourceLoweringTests; `let`->`var quillDataPackageDependencies` ->
  SourceHygieneTests + QuillQtBackendManifestTests. `signalUpstreamPresent` is
  irrelevant to these (they read the file), so verify with grep, no build.
- **Package.resolved must match main's signal-absent resolution.** Commit main's exact
  lockfile; signal-present local builds re-add swift-crypto/swift-protobuf pins on the
  fly -- never commit that churn (treat like the build-generated SwiftOpenUI worktree dirt).
- **Whole-package `swift build` over-builds Apple-only targets CI skips** (e.g.
  QuillPaintCoreGraphics needs real CoreGraphics CGContext). To validate signal-absent,
  reproduce the EXACT CI command (linux-swift-test.sh / `swift build --target QuillUIGtk`),
  not a bare whole-package build.
- **OllamaKitTests "chat publisher..." is a known main flake** (a 2s wall-clock poll
  racing async Combine completion under CI load -- the await-not-poll class). It fails
  main too; cleared by `gh run rerun <id> --failed`. Don't mistake it for a real failure.
- **The full "Swift Linux Backends" job is ~45-50min** (swift test + targeted builds +
  smoke/profile matrices). Early 6-10min results are FAILURES, not fast passes.
- **Fast-moving-main treadmill:** main advanced mid-PR repeatedly (QuillChatKit's iOS
  AppKit-guard fix landed after the commit I merged). Re-merge current main, or land a
  fully-green-but-BEHIND PR with `gh pr merge --admin` (per-case authorized) to break it.
- **Go-forward:** `signal/real-backend` is OBSOLETE (its infra is on main; its Track-A
  cruft dropped). Do future SSK error-clearing on FRESH branches off origin/main (with
  `.upstream` present locally) -> PR/merge promptly, one increment per branch.

---

### Track B post-infra: CI OOM flake fix + the UIKit font-shim cluster (2026-06-07)

- **CI "Corrupted JSON" flake = OOM, fixed by a global swift `--jobs` cap (#440).**
  The main-wide Linux CI failure `Internal Error: dataCorrupted(... "Corrupted JSON"
  ... unexpected end of file)` is NOT a transient compiler hiccup -- it is an OOM. On
  the 16 GiB `ubuntu-24.04` runner `swift build/test` default to `-j$(nproc)`; the huge
  generated SwiftUI app and the full package+test build spike past memory, the OOM
  killer truncates a compiler frontend mid-write, and SwiftPM aborts reading the
  truncated JSON. It hit the `Swift tests` step (a per-step retry was insufficient).
  Fix: inject a cap at the shared `scripts/swiftpm-preserve-package-resolved.sh`
  chokepoint every GTK/Qt `swift build/test` routes through -- auto = ~6 GiB/frontend
  capped to `nproc` (-> 2 on the 16 GiB runner), Linux-only (via `/proc/meminfo`, so
  macOS is untouched), `QUILLUI_SWIFT_JOBS` overrides (0/off disables), explicit
  `--jobs` wins. Cost ~0 wall-time (50m21s vs ~50m baseline -- memory, not CPU, was the
  bottleneck). Residual: a few bare `swift build` else-branches (GTK fast-paths) do not
  route through the wrapper; cap them if they ever flake.
- **UIKit font-shim cluster: StyleAttribute + MentionAttribute (202+26 -> 0, SSK
  4818 -> 4402).** Two distinct `UIFontDescriptor` types exist -- UIKitShim's (what SSK
  `import UIKit` resolves to) and QuillFoundation's (for RSFont). The error
  `'SymbolicTraits' is not a member type of class 'UIKit.UIFontDescriptor'` means the
  *UIKitShim* one lacked it. Added to UIKitShim's `UIFontDescriptor`: a nested
  `SymbolicTraits` OptionSet (traitBold/Italic/MonoSpace/...), a `symbolicTraits` prop,
  and `withSymbolicTraits(_:)`. Made `UIFont: Equatable` -- it was the ONLY
  non-Equatable stored member of `StyleDisplayConfiguration`/`MentionDisplayConfiguration`
  (`ThemedColor` already conforms), so their synthesized `Equatable` then succeeds. Added
  `NSUnderlineStyle` (OptionSet: `.single` etc.). Lesson: "type X not a member type of
  class UIKit.Y" or "value type does not conform to Equatable" on an SSK struct usually =
  a missing nested type or a single non-Equatable stored-property shim type -- find the
  ONE offending member rather than touching the upstream struct.
- **AvatarBuilder.swift (175 -> 0, SSK 4402 -> 4066).** Spanned BOTH shim families:
  on Linux `UIFont` resolves to UIKitShim's own `class UIFont` (it shadows the
  `@_exported`-re-exported `QuillFoundation.UIFont = RSFont`), but `UIImage`/`UIColor`
  resolve to QuillFoundation's `RSImage`/`RSColor` (UIKitShim has no own class for
  those). So `UIFont.withSize`/`init?(name:size:)` went in UIKitShim, while
  `RSImage.withTintColor`/`CGContext.clip(to:mask:)` went in QuillFoundation. Tricks:
  (a) `type 'Any' has no member 'white'` on `.withTintColor(.white)` = the shim method
  takes `Any` so a leading-dot literal can't resolve -> add a typed overload
  `withTintColor(_ color: RSColor)` (additive, non-breaking; Swift prefers it over the
  `Any` one for color args, falls back to `Any` otherwise). (b) `[Any?]` -> `CFArray`
  coercion: swift-corelibs has no bridge; since `CGGradient.init` already takes
  `colors: Any?`, fetch-patch-drop the explicit `] as CFArray` cast (unique occurrence).
  (c) `extra argument 'mask'` = add the `clip(to:mask:)` overload (inert).
- **50-error tail, fetch-patch-only wins (no shim):** QuotedReplyManager (50->0, #445):
  `CGImageSourceCreateWithData` shim changed to take `Data` (like CreateWithURL took URL)
  + drop `as CFData`/`as CFDictionary` at its 2 call sites. DebugLogger (50->0): pure
  fetch-patch -- `kCFURLContentModificationDateKey as URLResourceKey` ->
  `URLResourceKey.contentModificationDateKey` (CF URL key constants absent on corelibs;
  use the native URLResourceKey case), and `ProcessInfo()` -> `ProcessInfo.processInfo`
  (corelibs ProcessInfo has no PUBLIC init -- use the shared singleton).
- **C/ObjC helper from an excluded `.m` -> a Swift PORT free function.**
  DispatchQueue+Promise (50->0, +cascades -> SSK 3830->3682): `DispatchQueueIsCurrentQueue`
  / `_CurrentStackUsage` are declared in `Concurrency/Threading.{h,m}` (the `.m` is not
  compiled on Linux + no bridging header). Add them as free functions in a new
  `Sources/SignalServiceKitObjCPort/Quill*.swift` PORT file (auto-globbed into the target;
  linked into `<SSK>/QuillPort/` by quill-signal-link-ports.sh -> compiled as part of SSK,
  so same-module visibility). Inert: `DispatchQueueIsCurrentQueue` returns false so the
  `asyncIfNecessary` fast path always dispatches async (contract-safe). Clearing a
  heavily-depended-on file (Promise/DispatchQueue) cascade-clears dependents.
- **More excluded-`.m` method PORTs (same pattern, `QuillTSMessageObjCMethods.swift`).**
  Missing TSMessage/TSInfoMessage/TSIncomingMessage methods declared in a `.h` +
  implemented in an excluded `.m` -> add inert (or faithful-forward) Swift extension
  methods in the SSK-globbed PORT file: `infoMessagePreviewText` (faithful forward to
  the Swift `_infoMessagePreviewText`), `updateWithRemotelyDeleted…`,
  `updateWithViewOnceCompleteAndRemoveRenderableContent` (#458, ViewOnceMessages 48->0),
  `markAsViewed(atTimestamp:thread:circumstance:transaction:)` (#458; the ObjC
  `markAsViewedAtTimestamp:…` selector). Inert where the body needs the unported
  SDS-mutation/receipt path (those run only with a real linked account = paused).
- **`objc_sync_enter`/`objc_sync_exit` are absent on swift-corelibs (no ObjC runtime).**
  They're what `@synchronized(obj)` lowers to. Port them (`QuillObjCSync.swift`, #456,
  ModelReadCache 50->0) as a process-global **`NSRecursiveLock` table keyed by object
  identity** — must be RE-ENTRANT (ModelReadCache.performSync documents it). Return
  `OBJC_SYNC_SUCCESS` (0). Table is unevicted like the real runtime's; SSK only
  synchronizes long-lived singletons.
- **NSObject KVC (`setValue(_:forKey:)`) is absent on corelibs NSObject but PRESENT
  (`@objc`) on macOS.** UIDevice+FeatureSupport's `ows_setOrientation` rotation hack
  needs it. Add the inert shim method **`#if os(Linux)` ONLY** (#457) — an
  unconditional method on an always-built shim would conflict with the macOS
  superclass `@objc` selector. (Companion: `UINavigationController.attemptRotationToDeviceOrientation()`
  is a harmless static add on the shim's own class, no guard needed.)
- **The TOPFILES per-file error COUNT is cascade-inflated — judge by UNIQUE.** A file
  reporting "48-50 errors" usually has only ~2 distinct root-cause `line:col` sites
  (each re-emitted across batch/incremental jobs + per dependent). Dump the real work
  with `grep -E 'FILE\.swift:[0-9]+:[0-9]+: error:' /tmp/ssk.log | sort -u` before
  estimating effort — many "big" tail files are 1-2 fixes (ModelReadCache, UIDevice,
  ViewOnceMessages were each ~2 unique).

---

## Parallel fan-out method (the SSK tail, 40 unique root causes)

The whole remaining ~1952-error tail was just **~40 unique error MESSAGES**
(`grep -E ': error:' /tmp/ssk.log | sed 's#/qui/##' | sort -u`). Workflow:
dump all unique messages -> group into independent clusters -> design patches
in a **Workflow** (one agent per cluster; embed the error + ±7-line source +
the relevant existing shim surface IN THE PROMPT, since workflow subagents
CANNOT read this repo; return schema-structured edits) -> apply ALL via one
python applier with `assert count==N` per edit -> ONE batched build to verify
OWN-empty + each target->0 -> triage regressions. One batch cleared 25 of 40.

## Linux-corelibs gotchas (this batch)

- **URLRequest / URLSession / URLResponse live in `FoundationNetworking` on
  Linux**, not Foundation. A port/shim file using them needs
  `#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif`
  (else "cannot find type 'URLRequest'").
- `nonisolated static let X = T()` on a `@MainActor` class needs a
  `nonisolated init` too, or the default value can't be evaluated off-main
  ("main actor-isolated default value in a nonisolated context").
- `NSTextCheckingResult` has NO data-detector accessors on corelibs — add inert
  `.url/.date/.components` (always nil; data detection is absent). But the
  transit `NSTextCheckingKey.airline/.flight` keys are **internal** in corelibs
  -> can't reference them -> gate that block `#if !os(Linux)` (dead on Linux).
- **Timer is block-only on corelibs**: no `Timer(timeInterval:target:selector:
  userInfo:repeats:)` / `scheduledTimer(...)` target-selector overloads and no
  `perform`/Selector dispatch. Fix internal proxies (WeakTimer,
  StorageServiceManager) by gating to the block-based timer
  (`Timer.scheduledTimer(withTimeInterval:repeats:){ ... }`, strong-capture the
  proxy/self to match the original retain). `NSTimer+OWS`'s public
  `weakScheduledTimer`/`weakTimer` are `@available(swift, obsoleted: 1)` =
  ObjC-only -> dead on Linux (ObjC excluded) -> make `TimerProxy.timerFired`
  inert under `#if os(Linux)`.
- `Data.WritingOptions.atomicWrite` -> alias `.atomic`. `UserDefaults.setValue`
  (KVC) -> forward to `set(_:forKey:)`. `NSCoder.encodeCInt` -> `encode(Int32)`.
  `NSURLSessionDownloadTaskResumeData` global const absent -> define it.
  `NotificationCenter.notifications(named:)` async seq absent -> AsyncStream
  over `addObserver`. `LAContext.evaluatePolicy` async overload -> bridge the
  callback via `withCheckedThrowingContinuation`. `vDSP_desamp` -> faithful
  FIR-decimation Swift port (vDSP_Stride/vDSP_Length already in Accelerate.swift).
  `SecTrustSetPolicies(_, CFTypeRef)` -> widen param to `Any` (corelibs
  `CFArray == Array<Any>`, not class-constrained).
- **DEFERRED**: GRDB `Filter.operator` typed `(any SQLSpecificExpressible,
  SQLExpressible?) -> SQLExpression` — passing `==` (or `{ $0 == $1 }`) fails
  "`any SQLSpecificExpressible` cannot conform to itself"; needs `Filter` made
  generic. PassKit `PKContact` is cross-module (its `phoneNumber`/`postalAddress`
  are Contacts `CNPhoneNumber`/`CNPostalAddress`) -> define `PKContact` in the
  SSK module (`SignalServiceKitObjCPort`, importing Contacts+PassKit), de-finalize
  `PKPaymentSummaryItem` so `PKRecurringPaymentSummaryItem` can subclass it, and
  `PKPayment.billingContact` as a computed `{ nil }` extension (inert).

---

## MILESTONES: SSK compiles to 0, and the toolchain RUNS

### STEP C: GRDB storage engine runs at runtime
A bare in-memory GRDB roundtrip (open `DatabaseQueue`, CREATE/INSERT/SELECT) runs on
QuillOS Linux from the signal-smoke exe -- SSK's SQLite persistence engine executes,
not just crypto. The full Signal schema migration is the next frontier (its entry
points -- migrateDatabase(databaseStorage:)/runIncrementalMigrations(databaseWriter:)/
registerSchemaMigrations -- are internal/private/`#if TESTABLE_BUILD`).

The real signalapp/Signal-iOS **SignalServiceKit compiles to 0 errors** on QuillOS
(aarch64 Linux, swift-corelibs-foundation) against QuillUI's Apple-framework shims +
real libsignal (~4880 -> 0 over this effort). And a **`signal-smoke` executable runs**:
it links SignalServiceKit + the 194MB `libsignal_ffi.a` Rust core and executes a pure
libsignal primitive (`IdentityKeyPair.generate()` -> 69-byte keypair, exit 0). HONEST:
in-memory crypto only -- no DB, no network, no account.

### STEP D-I: the full secondary-device LINK chain runs on QuillOS
Every piece a phone-scanned QR linking needs is verified RUNNING on Linux from the
signal-smoke exe (each a merged PR; all crypto/parse/persist paths are real, exercised):
- **NET** -- `Net(env:.production, userAgent:..., buildVariant:.beta)` +
  `connectUnauthenticatedChat()` / `connectProvisioning()`. The ENTIRE TCP/TLS/WS/DNS
  stack is Rust inside `libsignal_ffi.a` (BoringSSL+rustls+tokio); chat.signal.org's root
  cert is pinned/compiled in, so it connects with NO system cert store and NO corelibs
  URLSession. Hold the conn + listener alive past the spawning `Task` or the socket is
  torn down when the local var deallocates.
- **SCHEMA** -- `GRDBSchemaMigrator.quillRunSchemaMigrations(on:)` migrates **85 tables**
  on a plain `DatabaseQueue` with NO DI bootstrap. Prereqs (each found by running + reading
  the crash): `SetCurrentAppContext(QuillSmokeAppContext(), isRunningTests:false)`; a REAL
  `clock_gettime_nsec_np` (MonotonicDate calls it on every DB tx and owsFails on 0); the
  `OWSBundleIDPrefix` Info.plist owsFailDebug gated `#if !os(Linux)`. `runDataMigrations:false`
  avoids DependenciesBridge/SSKEnvironment (only data migrations need them).
- **QR / DECRYPT** -- the `sgnl://linkdevice?uuid=<addr>&pub_key=<b64(ephemeral.pub)>` URL
  is built headless via URLComponents (DeviceProvisioningURL is app-layer). The envelope
  delivered by `didReceiveEnvelope` is a *serialized ProvisionEnvelope proto* (not an
  unwrapped body): `ProvisioningProtoProvisionEnvelope(serializedData:)` ->
  `ProvisioningCipher(ourKeyPair:).decrypt(data: env.body, theirPublicKey: PublicKey(env.publicKey))`
  -> `LinkingProvisioningMessage(plaintext:)`. Round-trip self-test (encrypt->wrap->decrypt)
  passes.
- **PERSIST** -- account state = rows in the `keyvalue(collection,key,value)` table created
  by createInitialSchema, written via `KeyValueStore(collection:)` + a `q.write { db in let
  tx = DBWriteTransaction(database: db); defer { tx.finalizeTransaction() }; ... }`. Identity
  keys via `setObject`/`getObject(ofClass: ECKeyPair.self)`. Reopening the on-disk file
  reloads everything incl. the archived ECKeyPair -> **login survives restart**. NSCoder fix
  (below) was required for the ECKeyPair round-trip. Plain SQLite silently ignores Signal's
  `PRAGMA key`, so the store works unencrypted with zero patching (encryption is a separate
  decision; SQLCipher isn't in the build image). Account collection
  `TSStorageUserAccountCollection`; ACI identity `TSStorageManagerIdentityKeyStoreCollection`,
  PNI identity `TSStorageManagerPNIIdentityKeyStoreCollection`, both under key
  `TSStorageManagerIdentityKeyStoreIdentityKey`.
- **REGISTER** -- the verify-secondary body is byte-shape-identical to upstream
  `ProvisioningRequestFactory.verifySecondaryDeviceRequest`: `{verificationCode,
  accountAttributes(as dict), aciSignedPreKey, pniSignedPreKey, aciPqLastResortPreKey,
  pniPqLastResortPreKey}`, PUT to `v1/devices/link`, auth = HTTP Basic (username=phoneNumber,
  password=fresh 16-byte server auth token hex). Prekeys built from LibSignalClient PRIMITIVES
  (must qualify `LibSignalClient.SignedPreKeyRecord`/`.KyberPreKeyRecord` -- ambiguous with
  SSK's own); base64 via `base64EncodedStringWithoutPadding()` (NOT url-safe). Account
  attributes reuse the real `AccountAttributes` Codable. Device name = base64 of
  `OWSDeviceNames.encryptDeviceName(plaintext:identityKeyPair:)` encrypted to the **ACI**
  identity. Self-test JSON-encodes a ~5.3KB body.
- **LIVE FLOW (STEP 9, USER-GATED)** -- `quillRunLiveLinkFlow()` chains it all behind
  `QUILL_SIGNAL_LINK=1` (default OFF): connectProvisioning -> print QR + "SCAN THIS WITH
  YOUR PHONE" -> on envelope: decrypt -> build verify body from the REAL decrypted
  aci/pni/identityKeyPairs/profileKey/provisioningCode -> PUT /v1/devices/link (URLSession
  via FoundationNetworking; completion-handler API wrapped in withCheckedThrowingContinuation
  -- robust on corelibs) -> persist creds to `/work/quill-signal-account.sqlite` (qs-work
  volume, survives the container) -> `connectAuthenticatedChat(username:"<aci.serviceIdString>.<deviceId>",
  password:serverAuthToken,...)`. Steps PUT/persist/authenticate run ONLY after a human
  scans; with the flag off the exe instead runs `quillTryDurableReconnect()` (loads stored
  creds + reconnects authenticated chat WITHOUT re-scan -- the "survives restart" proof),
  inert when none exist. Verified build + run with flag OFF: all self-tests pass, live flow
  compiled-dormant, reconnect inert, EXIT=0.

**Persistence FIDELITY (matching the real account store, not just self-consistent).** A
self-consistent roundtrip (write key X, read key X) proves *my* reconnect survives restart,
but for the DB to be a genuine real-SSK account store -- so a real SignalServiceKit boot
loads the linked account -- the keys, value TYPES, and STORE must match upstream exactly:
- **Two different stores back the `keyvalue` table.** Account state uses `NewKeyValueStore`
  (raw column values via a `KeyValueStoreValue` protocol -- String/Int64/Bool/Data stored
  natively, NOT archived). Identity keys use the legacy `KeyValueStore` (NSKeyedArchiver
  blobs). Writing an account scalar with legacy `KeyValueStore.setString` is INVISIBLE to a
  real read via `NewKeyValueStore.fetchValue(String.self)` even with the same key+table --
  the byte format differs. Write each field with the SAME store the real reader uses.
- **Exact account keys/types (TSAccountManagerImpl.Keys, collection
  "TSStorageUserAccountCollection"):** `TSStorageRegisteredNumberKey`(e164 String),
  `TSStorageRegisteredUUIDKey`(ACI as `aci.serviceIdUppercaseString` -- uppercase UUID, no
  prefix), `TSAccountManager_RegisteredPNIKey`(pni `rawUUID.uuidString`),
  `TSAccountManager_DeviceId`(**Int64**), `TSStorageLocalRegistrationId`(**Int64**),
  `TSStorageLocalPniRegistrationId`(**Int64** -- note the `Local`),
  `TSStorageServerAuthToken`(String), `TSAccountManager_ManualMessageFetchKey`(Bool true).
- **Identity keys (OWSIdentityManagerImpl, ONE collection
  "TSStorageManagerIdentityKeyStoreCollection", TWO keys):** ACI under
  `TSStorageManagerIdentityKeyStoreIdentityKey`, PNI under
  `TSStorageManagerIdentityKeyStorePNIIdentityKey` (NOT two separate collections). Stored as
  `ECKeyPair` via the legacy archiver (the NSCoder NSData fix below makes this round-trip).
- **Reconnect username** = `"<aci.serviceIdString>.<deviceId>"`. Stored ACI is the *uppercase*
  UUID; reconstruct via `Aci.parseFrom(aciString:)?.serviceIdString` (lowercase) for the
  websocket username. Runtime-verified: write via `quillPersistLinkedAccount` -> reopen ->
  `quillLoadStoredAuth` recovers `"<lowercase-uuid>.<deviceId>"` + token (EXIT=0).
- Caught by reading the actual upstream constants -- my first guess used invented keys
  (`localAciUuid`, `localE164`, `TSStoragePniRegistrationId`) + UInt32 + two identity
  collections, all wrong. ALWAYS ground persistence keys/types/store in the real source.

**Adversarial parallel audit caught TWO scan-wasting bugs the single perspective missed.**
After STEP 9 built green, an 8-dimension Workflow (one skeptical reviewer per wire dimension,
each given the upstream ground truth + my code embedded -- robust whether or not subagents can
read the repo) found two defects that would each have wasted the user's SINGLE-USE QR scan,
both confirmed against the real source before fixing:
- **Prekey keyId range** -- I used `UInt32.random(in: 1...0x7FFFFFFF)` (31-bit); upstream
  `PreKeyId.random()` is `UInt32.random(in: 1..<0x1000000)` (24-bit) and the server REJECTS
  IDs >= 0x1000000. ~99% of my IDs were out of range -> the PUT /v1/devices/link 4xxes on
  almost every attempt. Fix: `1..<0x100_0000` in both prekey generators.
- **QR pub_key not percent-encoded** -- I built the `sgnl://linkdevice` URL with
  `URLComponents`/`URLQueryItem`, which leaves base64 `+` and `/` RAW. Upstream
  `DeviceProvisioningURL.buildUrl()` explicitly AVOIDS URLComponents ("encodes '+' and '/' in
  the base64 pub_key in a way Android doesn't tolerate") and builds the string by hand,
  percent-encoding pub_key via `String.encodeURIComponent` (alphanumerics + `-_.!~*'()`),
  address raw, `&capabilities=` appended. An Android primary mis-parses raw `+`/`/` -> ECDHs
  to the wrong key -> the envelope MAC-fails -> no ProvisionMessage -> scan wasted. iOS-only
  testing hides this. Fix: build the string manually and call the real `pubB64.encodeURIComponent`.
Plus medium/low: added the Signal-iOS `User-Agent` + `Accept-Language` headers the real REST
layer injects (WAF/fingerprint risk on the link PUT); tightened the success guard to `==200`
and validated `deviceId` to 1...127 (upstream `DeviceId`); added `registrationDate` for
fidelity. DEFERRED (honest, non-blocking for durable login): the post-link one-time prekey
upload to `/v2/keys` -- the authed-chat reconnect works without it, so the device links +
reconnects but isn't yet fully provisioned to receive brand-new inbound sessions.
LESSON: a green build + self-consistent self-tests do NOT prove wire-correctness against a
single-use action; fan out an adversarial panel over the real protocol source FIRST.

**NSCoder NSData fix (the persistence-blocker):** swift-corelibs NSCoder's
`encodeBytes(UInt8?,length:,forKey:)` uses an internal keyed-archive byte format that has
NO `decodeBytes` reader; ECKeyPair's NSSecureCoding round-trip failed "Class ECKeyPair
failed to decode". Fix: the `@_disfavoredOverload encodeBytes(UnsafeRawPointer?,...)` shim
stores an **NSData** under the key (`encode(NSData(...), forKey:)`), and `decodeBytes` reads
it back via `decodeObject(of: NSData.self, forKey:)`. NSData round-trips faithfully; this
unblocked all ECKeyPair on-disk persistence.

**Cross-check the wire body BEFORE the single-use scan.** A wrong verify-secondary body
wastes the QR (single-use). Read upstream `ProvisioningRequestFactory` +
`ProvisioningCoordinatorImpl` directly in the MAIN agent (repo-read in sandboxed subagents
is unreliable -- the documented "don't waste a Workflow on repo-read" lesson) to confirm:
exact body keys, PUT/Basic-auth, serverAuthToken = `Randomness.generateRandomBytes(16).hexadecimalString`,
device name encrypted to the ACI identity, response `{pni, deviceId}`, authed-chat username
`"<aci.serviceIdString>.<deviceId>"`.

**Don't merge Track B onto another team's red main.** keep-main-green outranks
landing-promptly: when main's latest completed CI run is failure for an UNRELATED reason
(e.g. the swarm/loom GTK interaction-smoke or a QuillData regression -- signal PRs are
signal-gated and NOT built in CI, so they're inert and can't have caused it), HOLD the
admin-merge and keep building locally. Re-check main health each wake; merge only when its
own run is green.

### Smallest-milestone exe recipe (3 essential parts)
1. **libsignal testing-gate** -- LibSignalClient's "testing endpoints" (FakeChat / OTP /
   comparable-backup helpers) are gated `#if !os(iOS) || targetEnvironment(simulator)`
   ("not generated in device builds, to save code size"). On Linux `!os(iOS)` is true so
   they compile and reference `signal_testing_*` FFI symbols ABSENT from the **release**
   `libsignal_ffi.a` -> undefined-symbol at link. Narrow the gate to
   `#if (!os(iOS) || targetEnvironment(simulator)) && !os(Linux)` in
   ChatServiceTypes.swift / ComparableBackup.swift / Net.swift / ChatConnection+Fake.swift
   (durable: `patch_libsignal()` in scripts/fetch-upstream.sh, mirroring patch_signal_ios
   -- signal/libsignal are dev-only, manually provisioned, not CI-fetched).
2. **lld linker** -- the default bfd linker OOMs ("clang: error: unable to execute
   command: Killed") linking the 194MB `libsignal_ffi.a`; `ld.lld` links it in ~44s. Bake
   `linkerSettings: [.unsafeFlags(["-use-ld=lld"])]` into the exe target so a plain
   `swift build` works (no -Xswiftc needed).
3. **exe target** -- `.executableTarget(name: "signal-smoke", dependencies:
   ["SignalServiceKit", "LibSignalClient"], ...)` inside the
   `if signalUpstreamPresent && libsignalUpstreamPresent` block (Linux+upstream gated, so
   absent from CI / fresh checkouts -- CI doesn't build SSK or the exe).

An exe depending on SignalServiceKit transitively links LibSignalClient -> SignalFfi, whose
module.modulemap does `link "signal_ffi"`; the `-L.upstream/libsignal/target/release` flag
on LibSignalClient supplies the .a path. The .a is only needed when a downstream exe/test
links (the SSK *target* alone compiles without resolving it).

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
