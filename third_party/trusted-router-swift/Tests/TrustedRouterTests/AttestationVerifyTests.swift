import XCTest
@testable import TrustedRouter

#if canImport(Security)
import Security
#endif

/// Builds a real RSA keypair via Security framework, signs a JWT with it,
/// stitches together a JWKS pointing at the public half, and asserts
/// `verifyGatewayAttestation` accepts it (and rejects a tampered version).
/// This is the closest test to "the actual security guarantee."
final class AttestationVerifyTests: XCTestCase {

    func testValidJWTPassesVerification() async throws {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let kit = try Self.makeKeypairAndJWKS()
        let jwt = try kit.makeJWT()
        let result = try await verifyGatewayAttestation(
            document: Data(jwt.utf8),
            policy: AttestationPolicy(audience: "quill-cloud"),
            jwks: kit.jwks
        )
        XCTAssertEqual(result.audience, "quill-cloud")
        XCTAssertEqual(result.imageDigest, "sha256:abc")
        XCTAssertEqual(result.certSha256, kit.certSha)
        #else
        throw XCTSkip("Security framework not available")
        #endif
    }

    func testTamperedSignatureFailsVerification() async throws {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let kit = try Self.makeKeypairAndJWKS()
        let goodJWT = try kit.makeJWT()
        // Flip a single character in the signature segment.
        var parts = goodJWT.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return XCTFail("malformed JWT") }
        var sig = Array(parts[2])
        sig[0] = (sig[0] == "A") ? "B" : "A"
        parts[2] = String(sig)
        let tampered = parts.joined(separator: ".")

        do {
            _ = try await verifyGatewayAttestation(
                document: Data(tampered.utf8),
                policy: AttestationPolicy(audience: "quill-cloud"),
                jwks: kit.jwks
            )
            XCTFail("expected verification to fail on tampered signature")
        } catch let err as AttestationVerificationError {
            XCTAssertTrue(err.message.contains("signature"),
                          "expected a signature-specific error, got: \(err.message)")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        #else
        throw XCTSkip("Security framework not available")
        #endif
    }

    func testAudienceMismatchFails() async throws {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let kit = try Self.makeKeypairAndJWKS()
        let jwt = try kit.makeJWT()
        do {
            _ = try await verifyGatewayAttestation(
                document: Data(jwt.utf8),
                policy: AttestationPolicy(audience: "different-audience"),
                jwks: kit.jwks
            )
            XCTFail("expected audience-mismatch failure")
        } catch let err as AttestationVerificationError {
            XCTAssertTrue(err.message.contains("audience"))
        }
        #else
        throw XCTSkip("Security framework not available")
        #endif
    }

    #if canImport(Security)
    // MARK: - Test keypair / JWS helper

    private struct JWTKit {
        let privKey: SecKey
        let jwks: [String: Any]
        let certSha: String

        func makeJWT() throws -> String {
            let header: [String: Any] = ["alg": "RS256", "typ": "JWT", "kid": "test-kid"]
            // Exp 1 hour from now; iss matches GCPIssuer so checkClaims passes.
            let now = Int(Date().timeIntervalSince1970)
            let claims: [String: Any] = [
                "iss": GCPIssuer,
                "aud": "quill-cloud",
                "exp": now + 3600,
                "submods": [
                    "container": [
                        "image_digest": "sha256:abc",
                        "image_reference": "test/image:1",
                    ]
                ],
                "tls_cert_sha256": certSha,
            ]
            let hData = try JSONSerialization.data(withJSONObject: header)
            let pData = try JSONSerialization.data(withJSONObject: claims)
            let h64 = b64url(hData)
            let p64 = b64url(pData)
            let signingInput = "\(h64).\(p64)".data(using: .utf8)!
            var error: Unmanaged<CFError>?
            guard let sig = SecKeyCreateSignature(
                privKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                signingInput as CFData,
                &error
            ) as Data?
            else {
                throw NSError(domain: "JWTKit", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "signing failed"])
            }
            return "\(h64).\(p64).\(b64url(sig))"
        }

        private func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
    }

    private static func makeKeypairAndJWKS() throws -> JWTKit {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw NSError(domain: "JWTKit", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "keygen failed"])
        }
        guard let pub = SecKeyCopyPublicKey(priv),
              let raw = SecKeyCopyExternalRepresentation(pub, &error) as Data?
        else {
            throw NSError(domain: "JWTKit", code: 3)
        }
        // raw is PKCS#1 RSAPublicKey DER. Extract n and e for the JWK.
        let (n, e) = try Self.parsePKCS1RSAPublic(raw)
        let nB64 = base64url(n)
        let eB64 = base64url(e)
        let jwks: [String: Any] = [
            "keys": [
                ["kid": "test-kid", "kty": "RSA", "alg": "RS256", "n": nB64, "e": eB64]
            ]
        ]
        // Pick a deterministic cert SHA-256 — claim is required to bind the
        // attestation to a connection, but we have no real TLS cert in tests.
        let certSha = String(repeating: "a", count: 64)
        return JWTKit(privKey: priv, jwks: jwks, certSha: certSha)
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Minimal PKCS#1 RSAPublicKey decoder — enough to pull n/e out.
    private static func parsePKCS1RSAPublic(_ data: Data) throws -> (Data, Data) {
        var i = 0
        func readLength() throws -> Int {
            guard i < data.count else { throw NSError(domain: "DER", code: 10) }
            let first = data[i]; i += 1
            if first < 0x80 { return Int(first) }
            let n = Int(first & 0x7F)
            guard i + n <= data.count else { throw NSError(domain: "DER", code: 11) }
            var len = 0
            for _ in 0..<n { len = len << 8 | Int(data[i]); i += 1 }
            return len
        }
        func readInteger() throws -> Data {
            guard i < data.count, data[i] == 0x02 else { throw NSError(domain: "DER", code: 12) }
            i += 1
            let len = try readLength()
            let body = data.subdata(in: i..<i+len); i += len
            var unsigned = body
            if unsigned.first == 0 && unsigned.count > 1 { unsigned.removeFirst() }
            return unsigned
        }
        guard data[i] == 0x30 else { throw NSError(domain: "DER", code: 13) }
        i += 1
        _ = try readLength()
        let n = try readInteger()
        let e = try readInteger()
        return (n, e)
    }
    #endif
}
