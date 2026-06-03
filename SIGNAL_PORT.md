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
3. ⬜ Build `libsignal_ffi.a` (aarch64) + compile `LibSignalClient` on Linux GTK.
4. ⬜ Add `SignalServiceKit` target (path + excludes above) vs QuillUI shims;
   first build → baseline error count.
5. ⬜ Grind errors (cascade-cause playbook); extend QuillUI shims where Signal
   needs APIs they lack — commit each shim addition + each error-count drop.
6. ⬜ `SignalUI`, then the `Signal` app target.

## Status

Milestones 1–2 done. The fixtures `QuillSignalCore`/`QuillSignal` app and the
parked `QuillSignal` presage bridge are placeholders the real compiled
Signal-iOS supersedes. Real account link/send needs the user's phone — far off;
first it has to compile.
