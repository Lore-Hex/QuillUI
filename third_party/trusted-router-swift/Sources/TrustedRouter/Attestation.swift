import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(Security)
import Security
#endif

public struct GatewayAttestation: Sendable {
    public var certSha256: String
    public var imageDigest: String
    public var imageReference: String
    public var nonce: String?
    public var expiresAt: Int?
    public var issuer: String?
    public var audience: String
    public var rawClaims: [String: SendableValue]
    
    public init(
        certSha256: String,
        imageDigest: String,
        imageReference: String,
        nonce: String?,
        expiresAt: Int?,
        issuer: String?,
        audience: String,
        rawClaims: [String: SendableValue]
    ) {
        self.certSha256 = certSha256
        self.imageDigest = imageDigest
        self.imageReference = imageReference
        self.nonce = nonce
        self.expiresAt = expiresAt
        self.issuer = issuer
        self.audience = audience
        self.rawClaims = rawClaims
    }
}

/// A simple recursive Sendable value type to store JSON-like claims without [String: Any].
public enum SendableValue: Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([SendableValue])
    case dictionary([String: SendableValue])
    case null
    
    static func from(any: Any?) -> SendableValue {
        guard let any = any else { return .null }
        if let s = any as? String { return .string(s) }
        if let n = any as? Double { return .number(n) }
        if let n = any as? Int { return .number(Double(n)) }
        if let b = any as? Bool { return .bool(b) }
        if let a = any as? [Any] { return .array(a.map { from(any: $0) }) }
        if let d = any as? [String: Any] { return .dictionary(d.mapValues { from(any: $0) }) }
        return .null
    }
}

public struct AttestationPolicy: Sendable {
    public var audience: String
    public var certSha256: String?
    public var imageDigest: String?
    public var imageReference: String?

    public init(
        audience: String = "quill-cloud",
        certSha256: String? = nil,
        imageDigest: String? = nil,
        imageReference: String? = nil
    ) {
        self.audience = audience
        self.certSha256 = certSha256
        self.imageDigest = imageDigest
        self.imageReference = imageReference
    }
}

public struct AttestationVerificationError: Error, LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { message }
}

public let GCPIssuer = "https://confidentialcomputing.googleapis.com"
public let GCPJwksURI = "https://www.googleapis.com/service_accounts/v1/metadata/jwk/signer@confidentialspace-sign.iam.gserviceaccount.com"

extension TrustedRouter {
    public func attestation() async throws -> Data {
        let urlString = self.baseUrl.replacingOccurrences(of: "/v1$", with: "", options: .regularExpression) + "/attestation"
        guard let url = URL(string: urlString) else {
            throw TrustedRouterError.internalError("Invalid attestation URL: \(urlString)")
        }
        var req = URLRequest(url: url)
        req.setValue("trusted-router-swift/\(TrustedRouterConstants.version)", forHTTPHeaderField: "user-agent")
        
        let (data, response) = try await urlSession.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TrustedRouterError.internalError("Non-HTTP response")
        }
        if httpResponse.statusCode >= 400 {
            throw TrustedRouterError.generic(statusCode: httpResponse.statusCode, message: "Attestation fetch failed", payload: nil)
        }
        return data
    }
    
    public func trustRelease(url: String = TrustedRouterConstants.defaultTrustReleaseURL) async throws -> [String: Any] {
        return try await fetchTrustRelease(trustUrl: url, urlSession: self.urlSession)
    }
}

public func fetchTrustRelease(trustUrl: String = TrustedRouterConstants.defaultTrustReleaseURL, urlSession: URLSession = .shared) async throws -> [String: Any] {
    guard let url = URL(string: trustUrl) else {
        throw TrustedRouterError.internalError("Invalid trust release URL")
    }
    var req = URLRequest(url: url)
    req.setValue("trusted-router-swift/\(TrustedRouterConstants.version)", forHTTPHeaderField: "user-agent")
    
    let (data, response) = try await urlSession.data(for: req)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw TrustedRouterError.internalError("Non-HTTP response")
    }
    if httpResponse.statusCode >= 400 {
        throw TrustedRouterError.generic(statusCode: httpResponse.statusCode, message: "Trust release fetch failed", payload: nil)
    }
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw TrustedRouterError.internalError("Invalid JSON in trust release")
    }
    return dict
}

public func policyFromTrustRelease(
    release: [String: Any]? = nil,
    audience: String = "quill-cloud",
    certSha256: String? = nil,
    trustReleaseUrl: String = TrustedRouterConstants.defaultTrustReleaseURL,
    urlSession: URLSession = .shared
) async throws -> AttestationPolicy {
    let rel: [String: Any]
    if let release = release {
        rel = release
    } else {
        rel = try await fetchTrustRelease(trustUrl: trustReleaseUrl, urlSession: urlSession)
    }
    return AttestationPolicy(
        audience: audience,
        certSha256: certSha256,
        imageDigest: rel["image_digest"] as? String,
        imageReference: rel["image_reference"] as? String
    )
}

func b64urlDecode(_ base64URLEncoded: String) -> Data? {
    var base64 = base64URLEncoded
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let paddingLength = (4 - base64.count % 4) % 4
    base64.append(String(repeating: "=", count: paddingLength))
    return Data(base64Encoded: base64)
}

public func verifyGatewayAttestation(
    document: Data,
    policy: AttestationPolicy,
    nonceHex: String? = nil,
    tlsCertDer: Data? = nil,
    jwks: [String: Any]? = nil,
    jwksUrl: String = GCPJwksURI,
    urlSession: URLSession = .shared
) async throws -> GatewayAttestation {
    
    guard let text = String(data: document, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw AttestationVerificationError("Invalid JWT data")
    }
    let parts = text.split(separator: ".")
    if parts.count != 3 {
        throw AttestationVerificationError("expected 3 JWT segments, got \(parts.count)")
    }
    
    let hB64 = String(parts[0])
    let pB64 = String(parts[1])
    let sB64 = String(parts[2])
    
    guard let headerData = b64urlDecode(hB64),
          let payloadData = b64urlDecode(pB64),
          let signatureData = b64urlDecode(sB64) else {
        throw AttestationVerificationError("invalid JWT encoding")
    }
    
    guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
          let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
        throw AttestationVerificationError("invalid JWT JSON payload")
    }
    
    let signingInput = "\(hB64).\(pB64)".data(using: .utf8)!
    
    let activeJwks: [String: Any]
    if let jwks = jwks {
        activeJwks = jwks
    } else {
        guard let url = URL(string: jwksUrl) else {
            throw AttestationVerificationError("Invalid JWKS URL")
        }
        let (data, response) = try await urlSession.data(from: url)
        if let resp = response as? HTTPURLResponse, resp.statusCode >= 400 {
            throw AttestationVerificationError("JWKS fetch returned HTTP \(resp.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AttestationVerificationError("JWKS response is not JSON")
        }
        activeJwks = json
    }
    
    guard let keys = activeJwks["keys"] as? [[String: Any]] else {
        throw AttestationVerificationError("JWKS response missing keys array")
    }
    
    guard let alg = header["alg"] as? String, alg == "RS256" else {
        throw AttestationVerificationError("unsupported JWT alg; expected RS256")
    }
    
    guard let kid = header["kid"] as? String else {
        throw AttestationVerificationError("missing kid in header")
    }
    
    guard let jwk = keys.first(where: { ($0["kid"] as? String) == kid }) else {
        throw AttestationVerificationError("no JWK with kid=\(kid) in JWKS")
    }
    
    guard let kty = jwk["kty"] as? String, kty == "RSA" else {
        throw AttestationVerificationError("expected RSA key in JWKS")
    }
    
    // Real RS256 signature verification via Security.framework.
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    guard let nB64 = jwk["n"] as? String, let eB64 = jwk["e"] as? String,
          let nData = b64urlDecode(nB64), let eData = b64urlDecode(eB64) else {
        throw AttestationVerificationError("invalid JWK RSA parameters")
    }
    let pkcs1 = DER.rsaPublicKeyPKCS1(n: nData, e: eData)
    let attr: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(pkcs1 as CFData, attr as CFDictionary, &error) else {
        throw AttestationVerificationError("failed to create public key: \(error?.takeRetainedValue().localizedDescription ?? "unknown")")
    }
    guard SecKeyVerifySignature(
        key,
        .rsaSignatureMessagePKCS1v15SHA256,
        signingInput as CFData,
        signatureData as CFData,
        &error
    ) else {
        throw AttestationVerificationError("JWT signature verification failed")
    }
    #endif
    
    // Check claims
    return try checkClaims(claims: payload, policy: policy, nonceHex: nonceHex, tlsCertDer: tlsCertDer)
}

private func checkClaims(claims: [String: Any], policy: AttestationPolicy, nonceHex: String?, tlsCertDer: Data?) throws -> GatewayAttestation {
    let now = Int(Date().timeIntervalSince1970)
    if let exp = claims["exp"] as? Int, exp <= now {
        throw AttestationVerificationError("JWT expired at \(exp) (now=\(now))")
    }
    if let iss = claims["iss"] as? String, iss != GCPIssuer {
        throw AttestationVerificationError("unexpected issuer \(iss); expected \(GCPIssuer)")
    }
    
    var audList: [String] = []
    if let audString = claims["aud"] as? String {
        audList.append(audString)
    } else if let audArr = claims["aud"] as? [String] {
        audList = audArr
    }
    if !audList.contains(policy.audience) {
        throw AttestationVerificationError("audience \(policy.audience) not in JWT aud \(audList)")
    }
    
    var imageDigest = ""
    var imageReference = ""
    if let submods = claims["submods"] as? [String: Any], let container = submods["container"] as? [String: Any] {
        imageDigest = container["image_digest"] as? String ?? ""
        imageReference = container["image_reference"] as? String ?? ""
    }
    
    if let pDigest = policy.imageDigest, imageDigest != pDigest {
        throw AttestationVerificationError("image_digest mismatch: workload=\(imageDigest), policy=\(pDigest)")
    }
    if let pRef = policy.imageReference, imageReference != pRef {
        throw AttestationVerificationError("image_reference mismatch: workload=\(imageReference), policy=\(pRef)")
    }
    
    var nonces: [String] = []
    if let nString = claims["eat_nonce"] as? String {
        nonces.append(nString)
    } else if let nArr = claims["eat_nonce"] as? [String] {
        nonces.append(contentsOf: nArr)
    } else if let nString = claims["nonces"] as? String {
        nonces.append(nString)
    } else if let nArr = claims["nonces"] as? [String] {
        nonces.append(contentsOf: nArr)
    }
    
    var nonceMatch: String? = nil
    if let nonceHex = nonceHex {
        if !nonces.contains(nonceHex) {
            throw AttestationVerificationError("nonce \(nonceHex) not present in JWT nonces \(nonces)")
        }
        nonceMatch = nonceHex
    }
    
    var certSha = claims["tls_cert_sha256"] as? String ?? claims["workload_tls_cert_sha256"] as? String
    
    #if canImport(CryptoKit)
    if certSha == nil, let tlsCertDer = tlsCertDer {
        let actual = SHA256.hash(data: tlsCertDer).compactMap { String(format: "%02x", $0) }.joined()
        for n in nonces {
            if n.lowercased() == actual {
                certSha = actual
                break
            }
        }
    }
    #endif
    
    guard let cSha = certSha, cSha.count == 64 else {
        throw AttestationVerificationError("JWT does not commit to a TLS cert SHA-256 — cannot bind connection")
    }
    let lowerCertSha = cSha.lowercased()
    
    #if canImport(CryptoKit)
    if let tlsCertDer = tlsCertDer {
        let actual = SHA256.hash(data: tlsCertDer).compactMap { String(format: "%02x", $0) }.joined()
        if actual != lowerCertSha {
            throw AttestationVerificationError("TLS cert mismatch: connection=\(actual), JWT=\(lowerCertSha)")
        }
    }
    #endif
    
    if let pCertSha = policy.certSha256?.lowercased(), lowerCertSha != pCertSha {
        throw AttestationVerificationError("JWT-committed cert SHA-256 doesn't match policy pin")
    }
    
    return GatewayAttestation(
        certSha256: lowerCertSha,
        imageDigest: imageDigest,
        imageReference: imageReference,
        nonce: nonceMatch,
        expiresAt: claims["exp"] as? Int,
        issuer: claims["iss"] as? String,
        audience: policy.audience,
        rawClaims: claims.mapValues { SendableValue.from(any: $0) }
    )
}
