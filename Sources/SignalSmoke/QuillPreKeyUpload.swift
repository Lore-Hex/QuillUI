//
// QuillPreKeyUpload.swift -- Track B: upload one-time prekeys to v2/keys after
// linking, completing "fully provisioned" status for the QuillOS linked device.
//
// Upstream flow this mirrors (ProvisioningCoordinatorImpl after the
// verify-secondary-device PUT succeeds):
//   PreKeyManager.rotateOneTimePreKeysForRegistration ->
//     createOneTimePreKeys(.aci) + createOneTimePreKeys(.pni) ->
//   OWSRequestFactory.registerPrekeysRequest ->
//     PUT v2/keys            (ACI)   body {preKeys, pqPreKeys}
//     PUT v2/keys?identity=pni (PNI) body {preKeys, pqPreKeys}
//   auth = .identified -> HTTP Basic, username "<aci.serviceIdString>.<deviceId>",
//   password = serverAuthToken; timeoutInterval 45 (all per upstream).
//
// Generation + persistence happen INSIDE SignalServiceKit via the real upstream
// stores (QuillPreKeyPersist.swift): the private halves land in the real
// `PreKey` GRDB table BEFORE the upload (mirroring persistKeysPriorToUpload),
// so a crash between persist and upload never strands server-advertised keys
// we can't decrypt with.
//
// USER-GATED like everything else in the live flow: only invoked from
// quillCompleteLink, which itself only runs after a human voluntarily scans
// the QR. The self-test below touches NO network and NO account.
//
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LibSignalClient
import SignalServiceKit

/// PUT a one-time prekey upload body to v2/keys for one identity.
/// `identityQueryParam` is nil for ACI, "identity=pni" for PNI (upstream
/// OWSRequestFactory.queryParam(for:)). 2xx = success (default REST success
/// range; this endpoint has no special-cased codes upstream).
func quillPutV2Keys(
    identityQueryParam: String?,
    username: String,
    password: String,
    body: Data
) async throws {
    var path = "https://chat.signal.org/v2/keys"
    if let identityQueryParam { path += "?\(identityQueryParam)" }
    var req = URLRequest(url: URL(string: path)!)
    req.httpMethod = "PUT"
    req.timeoutInterval = 45  // upstream registerPrekeysRequest sets 45s
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Same coherent Signal-iOS client identity as the v1/devices/link PUT.
    req.setValue(quillSignalUserAgent, forHTTPHeaderField: "User-Agent")
    req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    let basic = Data("\(username):\(password)".utf8).base64EncodedString()
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
    guard (200...299).contains(http.statusCode) else {
        throw QuillLinkError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Post-link step: generate + persist one-time prekeys for BOTH identities via
/// the real SSK stores, then upload them to v2/keys (ACI first, then PNI,
/// matching upstream's per-identity tasks). Failure is reported but NON-FATAL
/// to the link: the device already linked + persisted durable credentials; it
/// is just not yet able to receive brand-new inbound sessions until a later
/// rotation succeeds.
func quillUploadOneTimePreKeys(
    dbPath: String,
    aciIdentityKeyPair: IdentityKeyPair,
    pniIdentityKeyPair: IdentityKeyPair,
    username: String,
    password: String
) async -> String {
    do {
        let (aciBody, pniBody, summary) = try quillGenerateAndPersistOneTimePreKeys(
            path: dbPath,
            aciIdentityKeyPair: aciIdentityKeyPair,
            pniIdentityKeyPair: pniIdentityKeyPair
        )
        try await quillPutV2Keys(identityQueryParam: nil, username: username, password: password, body: aciBody)
        try await quillPutV2Keys(identityQueryParam: "identity=pni", username: username, password: password, body: pniBody)
        return "ONE-TIME PREKEYS uploaded to v2/keys (aci + pni) -- device fully provisioned; \(summary)"
    } catch {
        return "ONE-TIME PREKEYS upload FAILED (link still durable; receive of brand-new sessions deferred to a later rotation): \(error)"
    }
}

/// Runtime self-test (NO network, NO account): generate + persist via the real
/// SSK stores into a temp DB, verify both upload bodies carry exactly 100 EC +
/// 100 Kyber entries with in-range 24-bit keyIds and the exact upstream JSON
/// field shape (EC = {keyId, publicKey} with NO signature; PQ = {keyId,
/// publicKey, signature}), and verify 200+200 rows landed in the real `PreKey`
/// table and reopen from disk.
func quillOneTimePreKeysSelfTest() -> String {
    do {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-prekeys-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        let (aciBody, pniBody, _) = try quillGenerateAndPersistOneTimePreKeys(
            path: path,
            aciIdentityKeyPair: IdentityKeyPair.generate(),
            pniIdentityKeyPair: IdentityKeyPair.generate()
        )

        struct ECEntry: Decodable { let keyId: UInt32; let publicKey: String; let signature: String? }
        struct PQEntry: Decodable { let keyId: UInt32; let publicKey: String; let signature: String }
        struct Body: Decodable { let preKeys: [ECEntry]; let pqPreKeys: [PQEntry] }

        for (name, data) in [("aci", aciBody), ("pni", pniBody)] {
            let parsed = try JSONDecoder().decode(Body.self, from: data)
            guard parsed.preKeys.count == 100, parsed.pqPreKeys.count == 100 else {
                return "ONE-TIME PREKEYS self-test FAILED: \(name) counts \(parsed.preKeys.count)/\(parsed.pqPreKeys.count) != 100/100"
            }
            guard parsed.preKeys.allSatisfy({ (1..<0x100_0000).contains($0.keyId) && $0.signature == nil }),
                  parsed.pqPreKeys.allSatisfy({ (1..<0x100_0000).contains($0.keyId) && !$0.signature.isEmpty }) else {
                return "ONE-TIME PREKEYS self-test FAILED: \(name) keyId out of 24-bit range or wrong signature shape"
            }
        }

        let counts = try quillCountOneTimePreKeys(path: path)
        guard counts.ec == 200, counts.pq == 200 else {
            return "ONE-TIME PREKEYS self-test FAILED: PreKey table has \(counts.ec) EC / \(counts.pq) PQ one-time rows (want 200/200)"
        }
        return "ONE-TIME PREKEYS: built v2/keys bodies (100 EC + 100 Kyber per identity, 24-bit ids, upstream shape) + 400 private halves persisted in real PreKey table"
    } catch {
        return "ONE-TIME PREKEYS self-test FAILED: \(error)"
    }
}
