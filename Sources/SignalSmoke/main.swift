//
// signal-smoke -- smallest-milestone executable for Track B (QuillOS).
//
// Proves the real signalapp/Signal-iOS toolchain on QuillOS (aarch64 Linux,
// swift-corelibs-foundation) LINKS and RUNS:
//   * SignalServiceKit (the real ~1400-file SSK) links into an executable.
//   * libsignal_ffi.a (the Rust crypto core) links and executes via a pure
//     libsignal primitive -- IdentityKeyPair.generate() -- needing NO database,
//     NO network, and NO Signal account.
//
// HONEST STATUS: this exercises only an in-memory crypto primitive plus a pure
// SignalServiceKit helper. It does NOT register, link a device, or touch any
// real Signal account. Account actions remain strictly user-gated.
//
import SignalServiceKit
import LibSignalClient

// libsignal FFI: generate a Curve25519 identity keypair (pure, in-memory).
let keyPair = IdentityKeyPair.generate()
let serialized = keyPair.serialize()

// SignalServiceKit: call a pure SSK-module helper to force SSK linkage.
let ssk = LocalizationNotNeeded("signal-smoke")

print("signal-smoke OK: \(ssk); libsignal IdentityKeyPair.generate() -> \(serialized.count) bytes serialized")
