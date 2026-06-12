//
// Headless secondary-device provisioning listener for the QuillOS Signal smoke
// (Track B). Turns the opaque provisioning address from Signal into the
// `sgnl://linkdevice?uuid=...&pub_key=...` URL that a user renders as a QR and
// scans in their phone's Signal app. When the primary sends back its encrypted
// ProvisionMessage, the envelope callback unwraps + ECDH-decrypts + parses it
// via `quillDecryptProvisionEnvelope` (QuillProvisioningDecrypt.swift). No
// account is touched -- we only produce the link URL and parse what we receive;
// nothing is registered or linked.
//
import Foundation
import LibSignalClient
import SignalServiceKit

final class QuillProvisioningListener: ProvisioningConnectionListener {
    private let pubKeyB64: String
    // OUR one-time ephemeral provisioning keypair: its public key is advertised
    // in the QR URL (`pubKeyB64`), and its private key decrypts the encrypted
    // ProvisionMessage the primary sends back through `didReceiveEnvelope`.
    private let ourKeyPair: IdentityKeyPair
    private let onURL: (String) -> Void

    init(pubKeyB64: String, ourKeyPair: IdentityKeyPair, onURL: @escaping (String) -> Void) {
        self.pubKeyB64 = pubKeyB64
        self.ourKeyPair = ourKeyPair
        self.onURL = onURL
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveAddress address: String, sendAck: @escaping () throws -> Void) {
        // Build the URL manually exactly like upstream DeviceProvisioningURL.buildUrl()
        // -- URLComponents/URLQueryItem leave '+' and '/' raw in the base64 pub_key,
        // which Android's primary mis-parses (wasting the single-use scan). pub_key
        // is percent-encoded via the real String.encodeURIComponent; address is raw;
        // an empty capabilities param is appended, per upstream.
        let encodedPub = pubKeyB64.encodeURIComponent ?? pubKeyB64
        let url = "sgnl://linkdevice?uuid=\(address)&pub_key=\(encodedPub)&capabilities="
        onURL(url)
        try? sendAck()
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveEnvelope envelope: Data, sendAck: @escaping () throws -> Void) {
        // `envelope` is a serialized ProvisioningProtoProvisionEnvelope (NOT an
        // already-unwrapped body), matching the upstream Signal app's
        // DecryptableProvisionEnvelope.decrypt(). Unwrap + ECDH-decrypt + parse.
        // NOTE: in the smoke we only RECEIVE and parse the primary's message; we
        // never act on it -- no account is registered or linked.
        print("signal-smoke PROVISION: received envelope \(envelope.count) bytes")
        do {
            let message = try quillDecryptProvisionEnvelope(envelope, ourKeyPair: ourKeyPair)
            print("signal-smoke PROVISION: decrypted ProvisionMessage -- aci=\(message.aci.rawUUID.uuidString) number=\(message.phoneNumber) provisioningCode set")
        } catch {
            print("signal-smoke PROVISION: envelope decrypt FAILED: \(error)")
        }
        try? sendAck()
    }

    func connectionWasInterrupted(_ service: ProvisioningConnection, error: Error?) {
        if let error { print("signal-smoke PROVISION: connection interrupted: \(error)") }
    }
}
