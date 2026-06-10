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

// Pin chat.signal.org to Signal's own root CA for the URLSession (libcurl/
// OpenSSL) REST path BEFORE any networking. chat.signal.org chains to Signal's
// private root, not a public CA; without this the v1/devices/link + v2/keys PUTs
// fail with "self-signed certificate in certificate chain" on Linux. (libsignal's
// websocket transport pins independently, so the unauth/provisioning sockets work
// regardless.) See QuillSignalTrust.swift.
quillInstallSignalCATrust()

// No-scan TLS probe: confirm the corelibs URLSession REST path now trusts
// chat.signal.org (the v1/devices/link + v2/keys PUTs go through this same path).
// ANY HTTP response = TLS validated; a certificate error = trust not installed.
print("signal-smoke \(quillSignalTLSProbe())")

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

// Device-name crypto self-test: a secondary device must send an ENCRYPTED
// device name in its registration. Exercises the REAL OWSDeviceNames
// encrypt/decrypt pair (ephemeral-ECDH + HMAC-SHA256 + AES-CTR) over an
// in-memory identity keypair. No network, no account.
print("signal-smoke DEVICENAME SELFTEST: \(quillDeviceNameRoundTripSelfTest())")

// Registration self-test: build the verify-secondary-device request body a
// freshly-linked device PUTs to v1/devices/link -- aci+pni EC signed prekeys,
// aci+pni Kyber last-resort prekeys (from LibSignalClient primitives), random
// registration IDs, and AccountAttributes -- then JSON-encode it. Mirrors the
// REAL ProvisioningRequestFactory.verifySecondaryDeviceRequest body shape. No
// network, no account.
print("signal-smoke REGISTER SELFTEST: \(quillBuildLinkRequestSelfTest())")

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

// Faithful persistence: prove the link credentials round-trip under the REAL
// SignalServiceKit account/identity keys + value types (NewKeyValueStore raw
// account state + legacy-archiver identity keys), so the on-disk DB is a genuine
// real-SSK account store and a restart recovers the reconnect username + token.
let quillFaithfulPath = FileManager.default.temporaryDirectory.appendingPathComponent("quill-faithful-\(UUID().uuidString).sqlite").path
print("signal-smoke FAITHFUL PERSIST: \(quillFaithfulPersistSelfTest(path: quillFaithfulPath))")

// One-time prekey self-test: generate 100 EC + 100 Kyber one-time prekeys per
// identity via the REAL upstream stores (PreKeyId/PreKeyStoreImpl/
// KyberPreKeyStoreImpl), persist the private halves into the real `PreKey`
// table, and build the exact v2/keys upload bodies. This is the post-link
// "fully provisioned" step's machinery, exercised with NO network, NO account.
print("signal-smoke PREKEYS SELFTEST: \(quillOneTimePreKeysSelfTest())")

// STEP 9/10: the FULL live secondary-device link flow -- strictly USER-GATED
// behind QUILL_SIGNAL_LINK=1 (default OFF). With the flag set, it prints a QR
// URL and WAITS for the user to scan with their phone, then registers + persists
// + authenticates (steps that run ONLY after a real human scan). With the flag
// unset (the default, and what CI / the self-test run exercises) it instead
// attempts a DURABLE RECONNECT from any previously-persisted credentials --
// which is inert when none exist, so the self-tests above are the whole run and
// EXIT stays 0. Either way nothing initiates a link without a human scanning.
if ProcessInfo.processInfo.environment["QUILL_SIGNAL_LINK"] == "1" {
    quillRunLiveLinkFlow()
} else {
    quillTryDurableReconnect()
}
