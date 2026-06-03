# QuillSignal — real Signal on QuillOS

## ⮕ PIVOT (2026-06-03): Rust core, not the iOS app

**Decision (user):** stop compiling `signalapp/Signal-iOS` on Linux; **pivot to
the Rust core** — the real `presage`/`libsignal` Signal protocol engine behind a
**native QuillUI UI**.

**Why:** Signal-iOS is a deeply Objective-C-coupled iOS app. Compiling its Swift
on Linux needs porting ~35 ObjC base classes *and* a mechanical pass to
strip/conditionalize `@objc`/`#selector`/NSCoding across **~200 of Signal's own
Swift files** (Linux Swift has **no ObjC interop** — 124k "ObjC interop disabled"
errors). 823/1119 SSK Swift files are clean, but they all depend on the
ObjC-coupled 26%. Multi-week source transform → not worth it vs. the Rust core,
which already builds + runs on aarch64 and reached a real device-linking
handshake (emitted `sgnl://linkdevice`).

**New deliverable:** a QuillUI app (native GTK UI) whose backend is the real
`presage`/`libsignal` Rust engine, via a unix-socket bridge daemon.

**Assets (validated, ready to integrate):**
- `quill-signal-bridge` (Rust, presage workspace member) — unix-socket daemon;
  ping/status/link-begin; emitted a real device-link URL. [parked: `/Users/jperla/claude/QuillSignal`, built in `qs-work` volume]
- `BridgeClient.swift` — Swift unix-socket client (decodes `BridgeMessage`). [parked repo]
- QuillUI `QuillSignal` fixture app (`Sources/QuillSignalCore`, `Sources/QuillSignal`) — the UI shell to rewire from fixtures to the real bridge.

**KEPT from the iOS attempt (reusable QuillUI hardening, independent of Signal):**
the Apple-framework shims — `CoreGraphics` CGFloat, `CryptoKit`→swift-crypto,
`CommonCrypto`→OpenSSL, `COSUnfairLock` os_unfair_lock, `Contacts`, +others.
The `SignalServiceKit` target is gated on `signalUpstreamPresent` and stays inert
when `.upstream/signal-ios` isn't fetched.

**Pivot plan:** (1) bring `BridgeClient.swift` into QuillUI as a `QuillSignalKit`
module. (2) rewire `QuillSignalContentView` from `QuillSignalFixtures` to the
bridge (status → link flow → conversations/messages). (3) build on Linux GTK.
(4) run daemon + app; verify the app connects and can request a link URL
(reaches Signal's servers — **no account needed** for the provisioning URL).
(5) real account link/send/receive = **PAUSE & coordinate** (needs the user's
phone). Engine build/run uses the `qs-work` cargo cache; bridge builds as the
4th member of the presage workspace.

**Engine re-verified (pivot step 2, 2026-06-03):** ran the prebuilt bridge daemon
from `qs-work` on aarch64 and round-tripped all three commands — `ping`→pong,
`status`→`{registered:false}` (presage sqlite store opens), and **`link-begin`
emitted a fresh real `sgnl://linkdevice?uuid=…&pub_key=…` URL** from Signal's
production servers. The Rust core (presage/libsignal) + bridge are alive on
QuillOS arch and reach Signal — the pivot foundation is solid. Step 1
(`QuillSignalKit` in QuillUI) also builds.

**App builds + links (pivot step 3, 2026-06-03):** `QuillSignalContentView`
rewired to the bridge (`QuillSignalModel` ObservableObject — status query + a
device-link panel driving `link-begin`). Caught the branch up to `main`
(vendored `third_party/SwiftOpenUI`) and used the **canonical Linux-GTK recipe**:
`scripts/prepare-linux-build-backend.sh --scratch-path .build-linux` (runs the
SwiftOpenUI mega-patcher `patch-swiftopenui-gtk-css.sh`, which adds
`ButtonStyleType.quillPaint*` + `gtk_swift_accessible_*` + dozens of Linux fixes)
then `swift build --scratch-path .build-linux --product quill-signal`. Build
image needs `python3`/`perl` for the patcher. Result: **`quill-signal` links into
a 13 MB aarch64 Linux ELF** at `.build-linux/aarch64-unknown-linux-gnu/debug/
quill-signal` — a native QuillUI/GTK Signal app with the real bridge client, on
QuillOS arch. **Next: run it (app + daemon) end-to-end; then extend the bridge
with conversation commands.** (`swift build --target` only emits the module;
the **`--product`** build links the executable.)

---

## Historical: the abandoned Signal-iOS compile

Compile the **real `signalapp/Signal-iOS` app** on Linux/QuillOS as
**QuillUI targets**, linked against QuillUI's real Apple-framework shim
products (`UIKit`/`SwiftUI`/`AVFoundation`/`Network`/`os`/`CoreGraphics`/
`Security`/`Combine`/…), **real GRDB**, **real SwiftProtobuf**, and **real
libsignal**. (Superseded by the pivot above — kept as the record of why, and of
the reusable framework-shim work.)

Branch `signal/real-backend` (off `main`). Upstream source lives under
`.upstream/` (per-worktree, gitignored — fetch, don't commit).

## Verified facts (2026-06-03)

- **Signal-iOS is NOT a SwiftPM package** — it's CocoaPods + Xcode
  (`Podfile`, `Pods/`, `Signal.xcodeproj`). So we author the SPM targets
  ourselves, pointing at its source dirs (the WireGuard upstream-slice
  pattern, but inverted to `#if os(Linux)` because Signal builds *on* Linux).
- **`SignalServiceKit` = 1412 Swift + 32 `.m` + 38 `.h` (18M).** ~95% Swift;
  the ObjC layer (the `<Foundation/Foundation.h>` blocker) is small + excludable.
- **Import frequency across SignalServiceKit** (drives shim needs):
  `Foundation` 925 · `LibSignalClient` 469 · `GRDB` 230 · `XCTest` 187 ·
  `UIKit` 56 · `Testing` 49 · `CryptoKit` 26 · `SwiftProtobuf` 23 ·
  `SignalRingRTC` 20 · `Contacts` 15 · `AVFoundation` 7 · `SDWebImage` 6 ·
  `Intents`/`CommonCrypto`/`CocoaLumberjack` 5 · `Network`/`LocalAuthentication`/
  `PassKit`/`UniformTypeIdentifiers`/`ObjectiveC` 4 · `os`/`Security`/`zlib`/
  `QuartzCore`/`ImageIO`/`libPhoneNumber_iOS` 2.
- **`LibSignalClient` (469) gates everything** → wire libsignal first.

## Pod → SPM dependency map

| Pod | Plan |
|-----|------|
| `LibSignalClient` v0.94.1 | **real** — `.upstream/libsignal` (cloned), build `libsignal_ffi.a`, wire `SignalFfi` + `LibSignalClient` targets |
| `SwiftProtobuf` 1.36.1 | real SPM pkg — **added** to `quillDataPackageDependencies` |
| `GRDB.swift/SQLCipher` | QuillUI already deps `GRDB.swift` 7.0.0 (plain SQLite first; SQLCipher later) |
| `SignalRingRTC` v2.69.1 | **defer** — exclude `Calls/` for first compile (WebRTC+Rust) |
| `MobileCoin` / `LibMobileCoin` | **defer** — exclude `Payments/` (optional) |
| `libPhoneNumber-iOS` | **defer / shim** — 2 imports |
| `SDWebImage*` / `libwebp` | **defer** — UI image loading |
| `BonMot`/`PureLayout`/`lottie-ios` | app-target UI; later |
| `CocoaLumberjack` | logging shim later |

## libsignal wiring recipe (verified from libsignal v0.94.1 swift/Package.swift)

- `SignalFfi` = `.systemLibrary` at `.upstream/libsignal/swift/Sources/SignalFfi`;
  its `module.modulemap` declares `header "signal_ffi.h"` + `link "signal_ffi"`.
- `LibSignalClient` = `.target` deps `["SignalFfi"]`, Linux links `stdc++`,
  `-L<dir with libsignal_ffi.a>`.
- Build the static lib: `cargo build -p libsignal-ffi --release` (crate at
  `rust/bridge/ffi`) → `.upstream/libsignal/target/release/libsignal_ffi.a`.
  Reuse the `qs-work` Docker cargo cache. Build v0.94.1 fresh (FFI symbol
  version must match the Swift wrapper — do **not** reuse presage's older FFI).
- The Swift wrapper compiles independently of the `.a`; the `.a` is only
  needed when a downstream executable/test links.

## Exclude strategy for SignalServiceKit (first compile)

- All tests: `XCTest` (187) + `Testing` (49) files, `Mocks/`.
- ObjC: 32 `.m` + 38 `.h` (`SignalServiceKit.h`, `*-Prefix.pch`).
- `Calls/` (RingRTC), `Payments/` (MobileCoin).
- Non-source resources SPM would reject: `.proto` (13), `.crt`/`.cer`/`.encrypted`
  certs, `.png`/`.webp`, `.py`, `.md`, `Protos/Makefile` → exclude or `.copy`.

## Milestone ladder

1. ✅ Clone real libsignal v0.94.1 → `.upstream/libsignal`.
2. ✅ Scaffold `SignalFfi` + `LibSignalClient` targets + `SwiftProtobuf` dep +
   `signalUpstreamPresent`/`libsignalUpstreamPresent` gates; manifest parses
   (`swift package dump-package` exit 0, 186 targets).
3. ✅ Build `libsignal_ffi.a` (aarch64, **194MB**, exit 0, rustc 1.96.0-nightly
   pin) + compile real `LibSignalClient` Swift wrapper on Linux: `Build of
   target: 'LibSignalClient' complete!` exit 0, **132 files, zero source edits**
   (`swiftLanguageMode(.v5)`). Real libsignal Rust FFI + Swift API both build on
   aarch64/Linux against QuillUI.
4. 🔄 `SignalServiceKit` target **wired** (1412 Swift, ObjC + tests/Calls/Payments
   + resources excluded — 94 exclude entries) vs QuillUI shims (UIKit/AVFoundation/
   Network/os/Security/CoreGraphics) + LibSignalClient + GRDB + SwiftProtobuf.
   NOTE: generated `.pb.swift` ARE checked in (kept). First baseline = 677 errors
   but **all of it was a build-env artifact**: GRDB's `GRDBSQLite` C module needs
   `sqlite3.h` → fixed by apt `libsqlite3-dev`; 230 GRDB-importing files cascaded.
   **True baseline (sqlite fixed) = 47 errors**, and the build doesn't even reach
   SSK yet — 46 are one root in GRDB: `Core/Support/CoreGraphics/CGFloat.swift`
   `cannot find type 'CGFloat'`. QuillUI's `CoreGraphics` shim makes
   `canImport(CoreGraphics)` true so GRDB compiles its CG support, but the shim
   never re-exported `CGFloat`. **Fix (QuillUI shim):** `@_exported import struct
   Foundation.CGFloat` in `Sources/CoreGraphics/CoreGraphics.swift` (verifying).

## Build environment (Docker, swift:6.2-noble, arm64)

Use the prebuilt **`quillui-signal-build`** image (`docker/quillui-signal-build.Dockerfile`
= swift:6.2-noble + libgtk-4-dev/libgdk-pixbuf-2.0-dev/libcairo2-dev/libsqlite3-dev/
libssl-dev/pkg-config/clang/protobuf-compiler/cmake/git) rather than per-run `apt`
— apt intermittently dropped libsqlite3-dev/libssl-dev, breaking GRDBSQLite /
CommonCrypto. Env: `QUILLUI_LINUX_BACKEND=gtk`.
Build with **`swift build --disable-index-store`** — swift-crypto's BoringSSL C++
(and the apt clang) reject SwiftPM's Apple-only `-index-store-path` flag.
Mounts: worktree → `/qui`, `qui-build` volume → `/qui/.build`. libsignal `.a`
build reuses `qs-work` cargo cache with `CARGO_HOME=/work/cargo`.
5. ⬜ Grind errors (cascade-cause playbook); extend QuillUI shims where Signal
   needs APIs they lack — commit each shim addition + each error-count drop.

## ⚠ Central challenge — Signal's ObjC core-model layer

~35 `.m/.h` files implement Signal's base model + util layer in **Objective-C**:
`TSInteraction`/`TSMessage`/`TSIncomingMessage`/`TSOutgoingMessage`/`TSErrorMessage`/
`TSInfoMessage`/`TSGroupModel`/`TSQuotedMessage`, the storage base
(`BaseModel`/`TSYapDatabaseObject`), and macros (`OWSAsserts`/`OWSLogs`/
`DebuggerUtils`). They `#import <Foundation/Foundation.h>` (the ObjC Foundation
umbrella), which **does not exist on swift-corelibs-foundation** — and Linux
Swift can't mix GNUstep ObjC-Foundation with the Swift Foundation the rest of the
code uses. **Hundreds of Swift files subclass/use these types.**

→ The real milestone-4/5 work is **porting this ObjC layer to Swift** (faithful
reimplementations on Linux), not just filling shim gaps. This is the crux of
"Signal on QuillOS" and the bulk of the remaining effort. The baseline build
(ObjC excluded) quantifies how much Swift depends on them.
6. ⬜ `SignalUI`, then the `Signal` app target.

## Grind log (SignalServiceKit, vs QuillUI shims)

Each fix unblocks a deeper layer, so the count rises when a dependency clears and
the build reaches further. "Top blocker" = dominant error after that fix.

| # | Fix | Top blocker after |
|---|-----|-------------------|
| 0 | sqlite3.h env (apt `libsqlite3-dev`) | 47: GRDB `CGFloat` |
| 1 | CoreGraphics re-export `Foundation.CGFloat` (6fdd83a) | 2263: reached SSK, `no such module CryptoKit` |
| 2 | `CryptoKit` shim → swift-crypto `Crypto` + `--disable-index-store` | 2263: `no such module CommonCrypto` |
| 3 | `CommonCrypto` shim → OpenSSL EVP (AES) | 2263: `no such module SignalRingRTC` |
| 4 | `SignalRingRTC` faithful type-shim (calling deferred) | 2263: `no such module os.lock` |
| 5 | `os_unfair_lock` C spinlock (COSUnfairLock) + 1-line TSMutex import patch | 1: CommonCrypto `openssl/evp.h` (flaky libssl-dev) |
| 6 | prebuilt `quillui-signal-build` image (deps baked, no flaky apt) | 2263: `no such module Contacts` |
| 7 | `Contacts` shim (value types real, store access deferred) | 2263: `no such module libPhoneNumber_iOS` |
| 8 | `libPhoneNumber_iOS` shim (best-effort E164) | 2263: `no such module ContactsUI` |
| 9 | batch 27 placeholder Apple-framework shims (ContactsUI/Intents/PassKit/…) | 2263: `no such module UniformTypeIdentifiers` (QuillUI has it — missing SSK dep edge) |
| 10 | add UniformTypeIdentifiers to SSK deps … | _(in progress)_ |

## Status

Real libsignal (Rust FFI + Swift) builds on aarch64/Linux; SignalServiceKit
target compiles its dependency graph (LibSignalClient/GRDB/SwiftProtobuf/
swift-crypto) and is now grinding through its own 1412 Swift files — adding one
QuillUI shim per missing Apple module, heading toward the ObjC-core-layer port.
The fixtures `QuillSignalCore`/`QuillSignal` app and the parked presage bridge
are placeholders the real compiled Signal-iOS supersedes. Real account link/send
needs the user's phone — far off; first it has to compile.
