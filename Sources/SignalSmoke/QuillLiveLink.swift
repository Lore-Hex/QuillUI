//
// QuillLiveLink.swift -- Track B FULL live secondary-device link flow (QuillOS).
//
// This wires the whole durable-login chain end to end, BUT it is strictly
// USER-GATED: it only runs when `QUILL_SIGNAL_LINK=1` is set in the environment
// (see main.swift). When it runs it:
//
//   (a) generates a one-time ephemeral provisioning (cipher) keypair,
//   (b) opens Signal's provisioning socket via libsignal's Rust transport and
//       HOLDS the connection + listener alive,
//   (c) prints the `sgnl://linkdevice` URL and WAITS for a human to scan it
//       with their phone's Signal app (Settings -> Linked Devices),
//   (d) on the encrypted provisioning envelope: decrypts it to a real
//       LinkingProvisioningMessage, builds the verify-secondary-device request
//       body from the REAL decrypted ACI/PNI identities + profile key +
//       provisioning code, with the device name encrypted to the ACI identity,
//   (e) PUTs it to https://chat.signal.org/v1/devices/link (HTTP Basic auth:
//       username=phoneNumber, password=fresh 16-byte server auth token),
//   (f) PERSISTS aci/pni/number/deviceId/registrationIds/identity ECKeyPairs/
//       serverAuthToken/profileKey to an on-disk DB (so login survives restart),
//   (g) connects an AUTHENTICATED chat to confirm the device is live.
//
// NOTHING below initiates a link by itself: steps (d)-(g) execute ONLY after a
// human voluntarily scans the printed QR with their own phone. With the flag
// unset, none of this runs (main.swift takes the durable-reconnect path
// instead, which is inert unless a prior scan already persisted credentials).
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Dispatch
import LibSignalClient
import SignalServiceKit

enum QuillLinkError: Error, CustomStringConvertible {
    case badResponse
    case httpStatus(Int, String)

    var description: String {
        switch self {
        case .badResponse: return "no/invalid HTTP response from chat.signal.org"
        case .httpStatus(let code, let body): return "HTTP \(code) from /v1/devices/link: \(body)"
        }
    }
}

/// On-disk path for the durable linked-account DB. Defaults into the `qs-work`
/// docker volume (mounted at /work) so a re-run after "restart" finds the same
/// file. Override with QUILL_SIGNAL_DB.
func quillSignalDBPath() -> String {
    if let p = ProcessInfo.processInfo.environment["QUILL_SIGNAL_DB"], !p.isEmpty { return p }
    if FileManager.default.fileExists(atPath: "/work") {
        return "/work/quill-signal-account.sqlite"
    }
    return FileManager.default.temporaryDirectory.appendingPathComponent("quill-signal-account.sqlite").path
}

/// The full live link flow. Only invoked when QUILL_SIGNAL_LINK=1.
func quillRunLiveLinkFlow() {
    print("signal-smoke LIVE LINK: starting secondary-device link flow (QUILL_SIGNAL_LINK=1)")
    let dbPath = quillSignalDBPath()

    // (a) one-time ephemeral provisioning (cipher) keypair. Its PUBLIC key goes
    // into the QR; its PRIVATE key decrypts the primary's ProvisionMessage.
    let ephemeral = IdentityKeyPair.generate()
    let pubB64 = ephemeral.publicKey.serialize().base64EncodedString()

    let net = Net(env: .production, userAgent: "quill-signal-link", buildVariant: .beta)
    let done = DispatchSemaphore(value: 0)

    // Hold conn + listener alive past the Task so the socket isn't torn down.
    var heldConn: ProvisioningConnection?
    var heldListener: QuillLiveLinkListener?

    Task {
        do {
            let conn = try await net.connectProvisioning()
            heldConn = conn
            let listener = QuillLiveLinkListener(
                pubKeyB64: pubB64,
                ourKeyPair: ephemeral,
                net: net,
                dbPath: dbPath,
                onFinished: { done.signal() }
            )
            heldListener = listener
            conn.start(listener: listener)
            print("signal-smoke LIVE LINK: provisioning socket connected; awaiting QR scan...")
        } catch {
            print("signal-smoke LIVE LINK: provisioning connect FAILED: \(error)")
            done.signal()
        }
    }
    // Wait (bounded) for the link to complete, or for the user to give up.
    _ = done.wait(timeout: .now() + 300)
    _ = heldConn
    _ = heldListener
}

/// Provisioning listener for the live flow: prints the QR URL, then on the
/// encrypted envelope runs the decrypt -> register -> persist -> authenticate
/// chain (once).
final class QuillLiveLinkListener: ProvisioningConnectionListener {
    private let pubKeyB64: String
    private let ourKeyPair: IdentityKeyPair
    private let net: Net
    private let dbPath: String
    private let onFinished: () -> Void
    private var handled = false

    init(pubKeyB64: String, ourKeyPair: IdentityKeyPair, net: Net, dbPath: String, onFinished: @escaping () -> Void) {
        self.pubKeyB64 = pubKeyB64
        self.ourKeyPair = ourKeyPair
        self.net = net
        self.dbPath = dbPath
        self.onFinished = onFinished
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveAddress address: String, sendAck: @escaping () throws -> Void) {
        // Build the URL string MANUALLY exactly like upstream DeviceProvisioningURL
        // .buildUrl(): URLComponents/URLQueryItem leave '+' and '/' RAW in the
        // base64 pub_key, which Android's primary does NOT tolerate (it would ECDH
        // to the wrong key, the envelope MAC-fails, and the single-use scan is
        // wasted). pub_key is percent-encoded with the real String.encodeURIComponent
        // (alphanumerics + "-_.!~*'()"); the address (ephemeralDeviceId) is raw; an
        // empty capabilities param is appended unconditionally, all per upstream.
        let encodedPub = pubKeyB64.encodeURIComponent ?? pubKeyB64
        let url = "sgnl://linkdevice?uuid=\(address)&pub_key=\(encodedPub)&capabilities="
        print("")
        print("============= SCAN THIS WITH YOUR PHONE =============")
        print(url)
        print("(Signal app -> Settings -> Linked Devices -> Link New Device)")
        print("====================================================")
        print("")
        try? sendAck()
    }

    func provisioningConnection(_ connection: ProvisioningConnection, didReceiveEnvelope envelope: Data, sendAck: @escaping () throws -> Void) {
        try? sendAck()
        if handled { return }
        handled = true
        print("signal-smoke LIVE LINK: received provisioning envelope (\(envelope.count) bytes) -- decrypting + linking")
        let ourKeyPair = self.ourKeyPair
        let net = self.net
        let dbPath = self.dbPath
        let finish = self.onFinished
        Task {
            do {
                let message = try quillDecryptProvisionEnvelope(envelope, ourKeyPair: ourKeyPair)
                try await quillCompleteLink(message: message, net: net, dbPath: dbPath)
            } catch {
                print("signal-smoke LIVE LINK: FAILED: \(error)")
            }
            finish()
        }
    }

    func connectionWasInterrupted(_ service: ProvisioningConnection, error: Error?) {
        if let error { print("signal-smoke LIVE LINK: connection interrupted: \(error)") }
    }
}

/// Steps (d)-(g): from a decrypted provisioning message, register the secondary
/// device on the server, persist the credentials durably, and confirm with an
/// authenticated chat connection.
func quillCompleteLink(message: LinkingProvisioningMessage, net: Net, dbPath: String) async throws {
    let aci = message.aci
    let pni = message.pni
    let phoneNumber = message.phoneNumber
    let provisioningCode = message.provisioningCode
    let aciIdentityKeyPair = message.aciIdentityKeyPair
    let pniIdentityKeyPair = message.pniIdentityKeyPair
    let profileKey = message.profileKey

    print("signal-smoke LIVE LINK: decrypted -- aci=\(aci.rawUUID.uuidString) number=\(phoneNumber)")

    // (d) device name encrypted to the ACI identity + 14-bit registration IDs.
    let encryptedDeviceName = try OWSDeviceNames.encryptDeviceName(
        plaintext: "QuillOS",
        identityKeyPair: aciIdentityKeyPair
    )
    // Signal registration IDs are 14-bit (1...0x3FFF), matching upstream
    // RegistrationIdGenerator.Constants.maximumRegistrationId.
    let aciRegistrationId = UInt32.random(in: 1...0x3FFF)
    let pniRegistrationId = UInt32.random(in: 1...0x3FFF)

    let inputs = QuillLinkInputs(
        verificationCode: provisioningCode,
        aciIdentityKeyPair: aciIdentityKeyPair,
        pniIdentityKeyPair: pniIdentityKeyPair,
        profileKey: profileKey,
        aciRegistrationId: aciRegistrationId,
        pniRegistrationId: pniRegistrationId,
        encryptedDeviceName: encryptedDeviceName
    )
    let body = try quillBuildVerifySecondaryDeviceBody(inputs)

    // (e) PUT v1/devices/link. password = fresh 16 random bytes, hex (mirrors
    // ProvisioningCoordinatorImpl.generateServerAuthToken: Randomness 16 -> hex).
    let serverAuthToken = Randomness.generateRandomBytes(16).map { String(format: "%02x", $0) }.joined()
    let (deviceId, responsePni) = try await quillPutDevicesLink(
        phoneNumber: phoneNumber, authPassword: serverAuthToken, body: body)
    print("signal-smoke LIVE LINK: server accepted link -> deviceId=\(deviceId) pni=\(responsePni)")

    // (f) persist everything needed to reconnect without re-scanning.
    let persistMsg = try quillPersistLinkedAccount(
        path: dbPath,
        aciServiceIdUppercase: aci.serviceIdUppercaseString,
        pniUuid: pni.rawUUID.uuidString,
        e164: phoneNumber,
        deviceId: deviceId,
        aciRegistrationId: aciRegistrationId,
        pniRegistrationId: pniRegistrationId,
        aciIdentityKeyPair: aciIdentityKeyPair,
        pniIdentityKeyPair: pniIdentityKeyPair,
        profileKey: profileKey.keyData,
        serverAuthToken: serverAuthToken
    )
    print("signal-smoke LIVE LINK: \(persistMsg)")

    // authed-chat / v2-keys username for a linked device =
    // "<aci.serviceIdString>.<deviceId>" (upstream TSAccountManagerImpl.serverUsername).
    let username = "\(aci.serviceIdString).\(deviceId)"

    // (f.2) ONE-TIME PREKEY UPLOAD -- "fully provisioned" step. Upstream, right
    // after the verify-secondary PUT, uploads EC + Kyber one-time prekeys to
    // /v2/keys (PreKeyManager.rotateOneTimePreKeysForRegistration) so other
    // clients can fetch a full prekey bundle and open brand-new inbound sessions
    // to this device. We generate + persist the private halves into the REAL
    // PreKey GRDB table (via the real upstream stores) BEFORE uploading, then PUT
    // both identities. This is NON-FATAL to the link: if it fails the device is
    // still linked + durably logged in, just not yet able to receive new sessions
    // until a later rotation succeeds.
    let prekeyMsg = await quillUploadOneTimePreKeys(
        dbPath: dbPath,
        aciIdentityKeyPair: aciIdentityKeyPair,
        pniIdentityKeyPair: pniIdentityKeyPair,
        username: username,
        password: serverAuthToken
    )
    print("signal-smoke LIVE LINK: \(prekeyMsg)")

    // (g) authenticated chat to confirm the device is live.
    let chat = try await net.connectAuthenticatedChat(
        username: username, password: serverAuthToken, receiveStories: false)
    print("signal-smoke LIVE LINK: authenticated chat connected as \(username) -- DEVICE IS LIVE")
    try? await chat.disconnect()
    print("signal-smoke LIVE LINK: complete. Credentials persisted to \(dbPath); re-run WITHOUT the flag to prove durable reconnect.")
}

/// PUT the verify-secondary-device body to chat.signal.org with HTTP Basic auth.
/// Uses the completion-handler URLSession API wrapped in a continuation (robust
/// on swift-corelibs FoundationNetworking, which is what runs on QuillOS/Linux).
func quillPutDevicesLink(phoneNumber: String, authPassword: String, body: Data) async throws -> (deviceId: UInt32, pni: String) {
    var req = URLRequest(url: URL(string: "https://chat.signal.org/v1/devices/link")!)
    req.httpMethod = "PUT"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Upstream's REST layer (OWSUrlSession.addDefaultHeaders) always injects a
    // Signal-iOS User-Agent + Accept-Language. On Linux FoundationNetworking we'd
    // otherwise ship a libcurl/Foundation default UA -- a clear non-Signal
    // fingerprint that an edge WAF/CDN could gate the link endpoint on. Present a
    // coherent Signal-iOS client identity. (X-Signal-Agent is intentionally NOT
    // set -- upstream omits it for this specific endpoint.)
    req.setValue("Signal-iOS/7.42.0 iOS/17.5", forHTTPHeaderField: "User-Agent")
    req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    let basic = Data("\(phoneNumber):\(authPassword)".utf8).base64EncodedString()
    req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
    req.httpBody = body

    let (data, http): (Data, HTTPURLResponse) = try await withCheckedThrowingContinuation { cont in
        let task = URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { cont.resume(throwing: error); return }
            guard let http = response as? HTTPURLResponse, let data else {
                cont.resume(throwing: QuillLinkError.badResponse); return
            }
            cont.resume(returning: (data, http))
        }
        task.resume()
    }

    // Upstream defines ONLY 200 as success (VerifySecondaryDeviceResponseCodes);
    // 409/411 are failures and there is no 201-299 success.
    guard http.statusCode == 200 else {
        throw QuillLinkError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    // Upstream VerifySecondaryDeviceResponse = {pni: <bare uuid string>, deviceId:
    // <bare int 1...127>}. Parse leniently: at this point the server has ALREADY
    // linked us, so a response-shape surprise must not throw away the (single-use)
    // scan -- extract the deviceId however it arrives. deviceId is validated to the
    // same 1...127 range upstream's DeviceId enforces (so a bad value never feeds
    // the authed-chat username).
    func validDeviceId(_ v: UInt32) -> Bool { (1...127).contains(v) }
    struct LinkResponse: Decodable { let pni: String; let deviceId: UInt32 }
    if let parsed = try? JSONDecoder().decode(LinkResponse.self, from: data), validDeviceId(parsed.deviceId) {
        return (parsed.deviceId, parsed.pni)
    }
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        let did: UInt32?
        if let n = obj["deviceId"] as? NSNumber { did = n.uint32Value }
        else if let i = obj["deviceId"] as? Int, i >= 0 { did = UInt32(i) }
        else { did = nil }
        if let did, validDeviceId(did) {
            return (did, (obj["pni"] as? String) ?? "")
        }
    }
    throw QuillLinkError.httpStatus(http.statusCode, "linked but could not parse a valid deviceId (1...127) from response: \(String(data: data, encoding: .utf8) ?? "")")
}

/// Durable-login proof: if a prior live link already persisted credentials,
/// load them and reconnect an authenticated chat WITHOUT re-scanning. Inert if
/// no linked account is stored (the STEP-9 / flag-off state). This is the
/// "survives restart" behaviour the user asked for.
func quillTryDurableReconnect() {
    let dbPath = quillSignalDBPath()
    guard FileManager.default.fileExists(atPath: dbPath) else {
        print("signal-smoke RECONNECT: no stored linked account at \(dbPath); skipping (link first with QUILL_SIGNAL_LINK=1)")
        return
    }
    do {
        guard let auth = try quillLoadStoredAuth(path: dbPath) else {
            print("signal-smoke RECONNECT: DB present but no linked-account credentials stored; skipping")
            return
        }
        let net = Net(env: .production, userAgent: "quill-signal-link", buildVariant: .beta)
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                let chat = try await net.connectAuthenticatedChat(
                    username: auth.username, password: auth.password, receiveStories: false)
                print("signal-smoke RECONNECT: durable login OK -- authenticated chat reconnected as \(auth.username) WITHOUT re-scan")
                try? await chat.disconnect()
            } catch {
                print("signal-smoke RECONNECT: authenticated reconnect FAILED: \(error)")
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 30)
    } catch {
        print("signal-smoke RECONNECT: error loading stored auth: \(error)")
    }
}
