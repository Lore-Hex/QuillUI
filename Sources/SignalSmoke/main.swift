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

// SignalServiceKit storage engine (GRDB) -- in-memory roundtrip.
do {
    print("signal-smoke DB: \(try quillSmokeGRDBRoundtrip())")
} catch {
    print("signal-smoke DB FAILED: \(error)")
}

// Networking: reach Signal's servers via libsignal's Rust transport.
//
// libsignal's entire chat/provisioning transport (TCP/TLS/WebSocket/DNS) lives
// in Rust inside libsignal_ffi.a (BoringSSL + rustls + tokio), which links and
// runs on QuillOS/Linux. The chat.signal.org root cert is pinned/compiled in,
// so this connects with no system cert store. UNAUTHENTICATED: no account, no
// credentials -- the same connectivity check Signal Desktop/iPad do before a
// user links a device. Proves the device can reach Signal, the prerequisite
// for secondary-device (QR) linking.
import Dispatch
let quillNet = Net(env: .production, userAgent: "quill-signal-smoke", buildVariant: .beta)
let quillNetSem = DispatchSemaphore(value: 0)
Task {
    do {
        let chat = try await quillNet.connectUnauthenticatedChat()
        print("signal-smoke NET: connected to Signal production (unauth chat websocket) via libsignal Rust transport")
        try? await chat.disconnect()
    } catch {
        print("signal-smoke NET FAILED: \(error)")
    }
    quillNetSem.signal()
}
quillNetSem.wait()
