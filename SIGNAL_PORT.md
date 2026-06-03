# Signal-iOS → QuillUI/QuillOS port

Compile the **real `signalapp/Signal-iOS` app** on Linux/QuillOS as
**QuillUI targets**, linked against QuillUI's real Apple-framework shim
products (`UIKit`/`SwiftUI`/`AVFoundation`/`Network`/`os`/`CoreGraphics`/
`Security`/`Combine`/…), **real GRDB**, **real SwiftProtobuf**, and **real
libsignal**. Where QuillUI's shims fall short of Signal's usage, **extend
the shims in QuillUI** — Signal is the flagship that hardens the framework
layer. No hand-written stubs; no separate fixture app.

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

apt deps: `libgtk-4-dev libgdk-pixbuf-2.0-dev libcairo2-dev libsqlite3-dev
pkg-config clang protobuf-compiler cmake git`. Env: `QUILLUI_LINUX_BACKEND=gtk`.
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
| 6 | ensure libssl-dev present each build … | _(in progress — then SSK Swift finally compiles)_ |

## Status

Real libsignal (Rust FFI + Swift) builds on aarch64/Linux; SignalServiceKit
target compiles its dependency graph (LibSignalClient/GRDB/SwiftProtobuf/
swift-crypto) and is now grinding through its own 1412 Swift files — adding one
QuillUI shim per missing Apple module, heading toward the ObjC-core-layer port.
The fixtures `QuillSignalCore`/`QuillSignal` app and the parked presage bridge
are placeholders the real compiled Signal-iOS supersedes. Real account link/send
needs the user's phone — far off; first it has to compile.
