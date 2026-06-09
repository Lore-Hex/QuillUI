//
// Headless secondary-device provisioning listener for the QuillOS Signal smoke
// (Track B). Turns the opaque provisioning address from Signal into the
// `sgnl://linkdevice?uuid=...&pub_key=...` URL that a user renders as a QR and
// scans in their phone's Signal app. The envelope callback receives the primary
// device's encrypted ProvisionMessage (decryption with ProvisioningCipher is a
// later step). No account is touched here -- this only produces the link URL.
//
import Foundation
import LibSignalClient

final class QuillProvisioningListener: ProvisioningConnectionListener {
    private let pubKeyB64: String
    private let onURL: (String) -> Void
    private let onEnvelope: (Data) -> Void

    init(pubKeyB64: String, onURL: @escaping (String) -> Void, onEnvelope: @escaping (Data) -> Void) {
        self.pubKeyB64 = pubKeyB64
        self.onURL = onURL
        self.onEnvelope = onEnvelope
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveAddress address: String, sendAck: @escaping () throws -> Void) {
        var comps = URLComponents()
        comps.scheme = "sgnl"
        comps.host = "linkdevice"
        comps.queryItems = [
            URLQueryItem(name: "uuid", value: address),
            URLQueryItem(name: "pub_key", value: pubKeyB64),
        ]
        if let url = comps.url?.absoluteString { onURL(url) }
        try? sendAck()
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveEnvelope envelope: Data, sendAck: @escaping () throws -> Void) {
        onEnvelope(envelope)
        try? sendAck()
    }

    func connectionWasInterrupted(_ service: ProvisioningConnection, error: Error?) {
        if let error { print("signal-smoke PROVISION: connection interrupted: \(error)") }
    }
}
