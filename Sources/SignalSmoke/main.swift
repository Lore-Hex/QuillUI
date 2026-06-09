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
import Foundation
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

do { print("signal-smoke MIGRATE: \(try quillSmokeSchemaMigration())") }
catch { print("signal-smoke MIGRATE FAILED: \(error)") }

// Provisioning crypto self-test: encrypt -> wrap -> decrypt -> parse loopback
// over in-memory keys. Exercises the REAL ProvisioningCipher +
// LinkingProvisioningMessage end to end. No network, no account.
print("signal-smoke PROVISION SELFTEST: \(quillProvisioningRoundTripSelfTest())")

// Provisioning: open Signal's provisioning socket and produce the sgnl://linkdevice
// QR URL (the user would scan it). No account is linked. Hold conn + listener
// alive past the Task so the connection isn't torn down before the address arrives.
// One-time ephemeral provisioning keypair. Its PUBLIC key goes in the QR URL
// (pub_key); its PRIVATE key (carried inside the full IdentityKeyPair) decrypts
// the ProvisionMessage the primary sends back. Decrypt needs the whole keypair,
// so we keep the IdentityKeyPair and hand it to the listener.
let quillEphemeral = IdentityKeyPair.generate()
let quillPubB64 = quillEphemeral.publicKey.serialize().base64EncodedString()
let quillProvSem = DispatchSemaphore(value: 0)
var quillProvConn: ProvisioningConnection?
var quillProvListener: QuillProvisioningListener?
Task {
    do {
        let conn = try await quillNet.connectProvisioning()
        quillProvConn = conn
        let listener = QuillProvisioningListener(
            pubKeyB64: quillPubB64,
            ourKeyPair: quillEphemeral,
            onURL: { url in print("signal-smoke PROVISION QR URL: \(url)"); quillProvSem.signal() }
        )
        quillProvListener = listener
        conn.start(listener: listener)
        print("signal-smoke PROVISION: provisioning socket connected; awaiting address...")
    } catch {
        print("signal-smoke PROVISION FAILED: \(error)")
        quillProvSem.signal()
    }
}
_ = quillProvSem.wait(timeout: .now() + 30)
_ = quillProvConn
_ = quillProvListener

do {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent("quill-persist-\(UUID().uuidString).sqlite").path
    print("signal-smoke PERSIST: \(try quillSmokeAccountPersistRoundtrip(path: p))")
} catch { print("signal-smoke PERSIST FAILED: \(error)") }
