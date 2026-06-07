import Foundation
@_exported import QuillKit

public final class SecCertificate: @unchecked Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

public final class SecTrust: @unchecked Sendable {
    public init() {}
}

public final class SecPolicy: @unchecked Sendable {
    public let isServer: Bool
    public let hostname: String?
    public init(isServer: Bool = true, hostname: String? = nil) {
        self.isServer = isServer
        self.hostname = hostname
    }
}

// SecTrust.h's SecTrustResultType (UInt32-backed; cases match the kSecTrustResult* values).
public enum SecTrustResultType: UInt32, Sendable {
    case invalid = 0
    case proceed = 1
    case confirm = 2  // deprecated by Apple
    case deny = 3
    case unspecified = 4
    case recoverableTrustFailure = 5
    case fatalTrustFailure = 6
    case otherError = 7
}

public final class SecRandom: @unchecked Sendable {
    public init() {}
}

public final class SecKey: @unchecked Sendable {
    private let data: Data
    private let keyAttributes: [String: Any]

    public init(data: Data, attributes: [String: Any] = [:]) {
        self.data = data
        self.keyAttributes = attributes
    }

    public func copyExternalRepresentation() -> Data {
        data
    }

    public func copyAttributes() -> [String: Any] {
        var attributes = keyAttributes
        attributes[secKey(kSecClass)] = attributes[secKey(kSecClass)] ?? secString(kSecClassKey)
        return attributes
    }

    func copyReplacingAttributes(_ updates: [String: Any]) -> SecKey {
        var attributes = copyAttributes()
        for (key, value) in updates {
            attributes[key] = value
        }
        return SecKey(data: data, attributes: attributes)
    }
}

public typealias SecKeyRef = SecKey
public typealias SecKeyAlgorithm = CFString
public typealias SecKeyKeyExchangeParameter = CFString

public enum SecKeyOperationType: Int, Sendable {
    case sign
    case verify
    case encrypt
    case decrypt
    case keyExchange
}

public final class SecAccessControl: @unchecked Sendable {
    public let protection: Any
    public let flags: SecAccessControlCreateFlags

    public init(protection: Any, flags: SecAccessControlCreateFlags) {
        self.protection = protection
        self.flags = flags
    }
}

public struct SecAccessControlCreateFlags: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let userPresence = Self(rawValue: 1 << 0)
    public static let biometryAny = Self(rawValue: 1 << 1)
    public static let touchIDAny = biometryAny
    public static let biometryCurrentSet = Self(rawValue: 1 << 3)
    public static let touchIDCurrentSet = biometryCurrentSet
    public static let devicePasscode = Self(rawValue: 1 << 4)
    public static let `or` = Self(rawValue: 1 << 14)
    public static let `and` = Self(rawValue: 1 << 15)
    public static let privateKeyUsage = Self(rawValue: 1 << 30)
    public static let applicationPassword = Self(rawValue: 1 << 31)
}

public typealias OSStatus = Int32
public typealias SecRandomRef = SecRandom
public let errSecSuccess: OSStatus = 0
public let errSecUnimplemented: OSStatus = -4
public let errSecParam: OSStatus = -50
public let errSecAllocate: OSStatus = -108
public let errSecNotAvailable: OSStatus = -25291
public let errSecDuplicateItem: OSStatus = -25299
public let errSecItemNotFound: OSStatus = -25300
public let errSecInteractionNotAllowed: OSStatus = -25308

public let kSecClass: CFString = "class" as CFString
public let kSecClassGenericPassword: CFString = "genp" as CFString
public let kSecClassInternetPassword: CFString = "inet" as CFString
public let kSecClassKey: CFString = "keys" as CFString
public let kSecClassCertificate: CFString = "cert" as CFString
public let kSecClassIdentity: CFString = "idnt" as CFString

public let kSecAttrService: CFString = "svce" as CFString
public let kSecAttrAccount: CFString = "acct" as CFString
public let kSecAttrServer: CFString = "srvr" as CFString
public let kSecAttrSecurityDomain: CFString = "sdmn" as CFString
public let kSecAttrProtocol: CFString = "ptcl" as CFString
public let kSecAttrAuthenticationType: CFString = "atyp" as CFString
public let kSecAttrPort: CFString = "port" as CFString
public let kSecAttrPath: CFString = "path" as CFString
public let kSecAttrAccessGroup: CFString = "agrp" as CFString
public let kSecAttrSynchronizable: CFString = "sync" as CFString
public let kSecAttrSynchronizableAny: CFString = "syna" as CFString
public let kSecAttrLabel: CFString = "labl" as CFString
public let kSecAttrGeneric: CFString = "gena" as CFString
public let kSecAttrAccessible: CFString = "pdmn" as CFString
public let kSecAttrAccessControl: CFString = "accc" as CFString
public let kSecAttrAccessibleWhenUnlocked: CFString = "ak" as CFString
public let kSecAttrAccessibleAfterFirstUnlock: CFString = "ck" as CFString
public let kSecAttrAccessibleAlways: CFString = "dk" as CFString
public let kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly: CFString = "akpu" as CFString
public let kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFString = "aku" as CFString
public let kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: CFString = "cku" as CFString
public let kSecAttrAccessibleAlwaysThisDeviceOnly: CFString = "dku" as CFString
public let kSecAttrApplicationTag: CFString = "atag" as CFString
public let kSecAttrApplicationLabel: CFString = "alis" as CFString
public let kSecAttrKeyClass: CFString = "kcls" as CFString
public let kSecAttrKeyClassPublic: CFString = "publ" as CFString
public let kSecAttrKeyClassPrivate: CFString = "priv" as CFString
public let kSecAttrKeyClassSymmetric: CFString = "symm" as CFString
public let kSecAttrKeyType: CFString = "type" as CFString
public let kSecAttrKeyTypeRSA: CFString = "42" as CFString
public let kSecAttrKeyTypeEC: CFString = "73" as CFString
public let kSecAttrKeyTypeECSECPrimeRandom: CFString = "73" as CFString
public let kSecAttrKeySizeInBits: CFString = "bsiz" as CFString
public let kSecAttrEffectiveKeySize: CFString = "esiz" as CFString
public let kSecAttrIsPermanent: CFString = "perm" as CFString
public let kSecAttrCanEncrypt: CFString = "encr" as CFString
public let kSecAttrCanDecrypt: CFString = "decr" as CFString
public let kSecAttrCanDerive: CFString = "drve" as CFString
public let kSecAttrCanSign: CFString = "sign" as CFString
public let kSecAttrCanVerify: CFString = "vrfy" as CFString
public let kSecAttrCanWrap: CFString = "wrap" as CFString
public let kSecAttrCanUnwrap: CFString = "unwp" as CFString
public let kSecAttrTokenID: CFString = "tkid" as CFString
public let kSecAttrTokenIDSecureEnclave: CFString = "SecureEnclave" as CFString
public let kSecPrivateKeyAttrs: CFString = "private" as CFString
public let kSecPublicKeyAttrs: CFString = "public" as CFString

public let kSecKeyAlgorithmECDSASignatureMessageX962SHA256: CFString = "algid:sign:ECDSA:message-X962:SHA256" as CFString
public let kSecKeyAlgorithmECDSASignatureDigestX962SHA256: CFString = "algid:sign:ECDSA:digest-X962:SHA256" as CFString
public let kSecKeyAlgorithmECDHKeyExchangeStandard: CFString = "algid:keyexchange:ECDH:standard" as CFString
public let kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256: CFString = "algid:keyexchange:ECDH:standard-X963:SHA256" as CFString
public let kSecKeyAlgorithmRSAEncryptionPKCS1: CFString = "algid:encrypt:RSA:PKCS1" as CFString
public let kSecKeyKeyExchangeParameterRequestedSize: CFString = "requestedSize" as CFString
public let kSecKeyKeyExchangeParameterSharedInfo: CFString = "sharedInfo" as CFString

public let kSecAttrProtocolFTP: CFString = "ftp " as CFString
public let kSecAttrProtocolFTPAccount: CFString = "ftpa" as CFString
public let kSecAttrProtocolHTTP: CFString = "http" as CFString
public let kSecAttrProtocolIRC: CFString = "irc " as CFString
public let kSecAttrProtocolNNTP: CFString = "nntp" as CFString
public let kSecAttrProtocolPOP3: CFString = "pop3" as CFString
public let kSecAttrProtocolSMTP: CFString = "smtp" as CFString
public let kSecAttrProtocolSOCKS: CFString = "sox " as CFString
public let kSecAttrProtocolIMAP: CFString = "imap" as CFString
public let kSecAttrProtocolLDAP: CFString = "ldap" as CFString
public let kSecAttrProtocolAppleTalk: CFString = "atlk" as CFString
public let kSecAttrProtocolAFP: CFString = "afp " as CFString
public let kSecAttrProtocolTelnet: CFString = "teln" as CFString
public let kSecAttrProtocolSSH: CFString = "ssh " as CFString
public let kSecAttrProtocolFTPS: CFString = "ftps" as CFString
public let kSecAttrProtocolHTTPS: CFString = "htps" as CFString
public let kSecAttrProtocolHTTPProxy: CFString = "htpx" as CFString
public let kSecAttrProtocolHTTPSProxy: CFString = "htsx" as CFString
public let kSecAttrProtocolFTPProxy: CFString = "ftpx" as CFString
public let kSecAttrProtocolSMB: CFString = "smb " as CFString
public let kSecAttrProtocolRTSP: CFString = "rtsp" as CFString
public let kSecAttrProtocolRTSPProxy: CFString = "rtsx" as CFString
public let kSecAttrProtocolDAAP: CFString = "daap" as CFString
public let kSecAttrProtocolEPPC: CFString = "eppc" as CFString
public let kSecAttrProtocolIPP: CFString = "ipp " as CFString
public let kSecAttrProtocolNNTPS: CFString = "ntps" as CFString
public let kSecAttrProtocolLDAPS: CFString = "ldps" as CFString
public let kSecAttrProtocolTelnetS: CFString = "tels" as CFString
public let kSecAttrProtocolIMAPS: CFString = "imps" as CFString
public let kSecAttrProtocolIRCS: CFString = "ircs" as CFString
public let kSecAttrProtocolPOP3S: CFString = "pops" as CFString

public let kSecAttrAuthenticationTypeNTLM: CFString = "ntlm" as CFString
public let kSecAttrAuthenticationTypeMSN: CFString = "msna" as CFString
public let kSecAttrAuthenticationTypeDPA: CFString = "dpaa" as CFString
public let kSecAttrAuthenticationTypeRPA: CFString = "rpaa" as CFString
public let kSecAttrAuthenticationTypeHTTPBasic: CFString = "http" as CFString
public let kSecAttrAuthenticationTypeHTTPDigest: CFString = "httd" as CFString
public let kSecAttrAuthenticationTypeHTMLForm: CFString = "form" as CFString
public let kSecAttrAuthenticationTypeDefault: CFString = "dflt" as CFString

public let kSecValueData: CFString = "v_Data" as CFString
public let kSecValueRef: CFString = "v_Ref" as CFString
public let kSecValuePersistentRef: CFString = "v_PersistentRef" as CFString
public let kSecReturnData: CFString = "r_Data" as CFString
public let kSecReturnAttributes: CFString = "r_Attributes" as CFString
public let kSecReturnRef: CFString = "r_Ref" as CFString
public let kSecReturnPersistentRef: CFString = "r_PersistentRef" as CFString
public let kSecMatchLimit: CFString = "m_Limit" as CFString
public let kSecMatchLimitOne: CFString = "m_LimitOne" as CFString
public let kSecMatchLimitAll: CFString = "m_LimitAll" as CFString
public let kSecUseDataProtectionKeychain: CFString = "u_DPK" as CFString
public let kSecUseAuthenticationUI: CFString = "u_AuthUI" as CFString
public let kSecUseAuthenticationUIAllow: CFString = "u_AuthUIAllow" as CFString
public let kSecUseAuthenticationUIFail: CFString = "u_AuthUIFail" as CFString
public let kSecUseAuthenticationUISkip: CFString = "u_AuthUISkip" as CFString
public let kSecUseAuthenticationContext: CFString = "u_AuthCtx" as CFString
public let kSecUseOperationPrompt: CFString = "u_OpPrompt" as CFString
public let kSecUseItemList: CFString = "u_ItemList" as CFString
public let kSecUseKeychain: CFString = "u_Keychain" as CFString

public let kSecRandomDefault: SecRandomRef? = nil

public func SecCertificateCreateWithData(_ allocator: CFAllocator?, _ data: CFData) -> SecCertificate? {
    SecCertificate(data: data)
}

public func SecAccessControlCreateWithFlags(
    _ allocator: CFAllocator?,
    _ protection: Any,
    _ flags: SecAccessControlCreateFlags,
    _ error: UnsafeMutablePointer<CFError?>?
) -> SecAccessControl? {
    SecAccessControl(protection: protection, flags: flags)
}

@discardableResult
public func SecRandomCopyBytes(_ _: SecRandomRef?, _ count: Int, _ bytes: UnsafeMutableRawPointer) -> OSStatus {
    guard count >= 0 else {
        return errSecParam
    }
    guard count > 0 else {
        return errSecSuccess
    }

    var generator = SystemRandomNumberGenerator()
    let buffer = bytes.bindMemory(to: UInt8.self, capacity: count)
    for index in 0..<count {
        buffer[index] = UInt8.random(in: UInt8.min ... UInt8.max, using: &generator)
    }
    return errSecSuccess
}

public func SecKeyCreateWithData(_ keyData: CFData, _ attributes: CFDictionary, _ error: UnsafeMutablePointer<CFError?>?) -> SecKey? {
    let data = keyData as NSData as Data
    guard !data.isEmpty else {
        error?.pointee = nil
        return nil
    }
    error?.pointee = nil
    return SecKey(data: data, attributes: secDictionary(attributes))
}

public func SecKeyCopyAttributes(_ key: SecKey) -> CFDictionary? {
    key.copyAttributes()
}

public func SecKeyCopyExternalRepresentation(_ key: SecKey, _ error: UnsafeMutablePointer<CFError?>?) -> CFData? {
    error?.pointee = nil
    return key.copyExternalRepresentation() as NSData as CFData
}

public func SecKeyCreateRandomKey(_ parameters: CFDictionary, _ error: UnsafeMutablePointer<CFError?>?) -> SecKey? {
    let parameterValues = secDictionary(parameters)
    guard let key = makeGeneratedSecKey(from: parameterValues, keyClass: kSecAttrKeyClassPrivate) else {
        error?.pointee = nil
        return nil
    }

    if boolValue(key.copyAttributes()[secKey(kSecAttrIsPermanent)]) {
        guard storeGeneratedSecKey(key) == errSecSuccess else {
            error?.pointee = nil
            return nil
        }
    }

    error?.pointee = nil
    return key
}

public func SecKeyGeneratePair(
    _ parameters: CFDictionary,
    _ publicKey: UnsafeMutablePointer<SecKey?>?,
    _ privateKey: UnsafeMutablePointer<SecKey?>?
) -> OSStatus {
    let parameterValues = secDictionary(parameters)
    guard let privateGeneratedKey = makeGeneratedSecKey(from: parameterValues, keyClass: kSecAttrKeyClassPrivate) else {
        publicKey?.pointee = nil
        privateKey?.pointee = nil
        return errSecParam
    }

    let publicData = synthesizedPublicKeyData(from: privateGeneratedKey.copyExternalRepresentation())
    guard let publicGeneratedKey = makeGeneratedSecKey(from: parameterValues, keyClass: kSecAttrKeyClassPublic, data: publicData) else {
        publicKey?.pointee = nil
        privateKey?.pointee = nil
        return errSecParam
    }

    if boolValue(privateGeneratedKey.copyAttributes()[secKey(kSecAttrIsPermanent)]) {
        let status = storeGeneratedSecKey(privateGeneratedKey)
        guard status == errSecSuccess else {
            publicKey?.pointee = nil
            privateKey?.pointee = nil
            return status
        }
    }
    if boolValue(publicGeneratedKey.copyAttributes()[secKey(kSecAttrIsPermanent)]) {
        let status = storeGeneratedSecKey(publicGeneratedKey)
        guard status == errSecSuccess else {
            publicKey?.pointee = nil
            privateKey?.pointee = nil
            return status
        }
    }

    publicKey?.pointee = publicGeneratedKey
    privateKey?.pointee = privateGeneratedKey
    return errSecSuccess
}

public func SecKeyCopyPublicKey(_ key: SecKey) -> SecKey? {
    let attributes = key.copyAttributes()
    if stringValue(attributes[secKey(kSecAttrKeyClass)]) == secString(kSecAttrKeyClassSymmetric) {
        return nil
    }
    if stringValue(attributes[secKey(kSecAttrKeyClass)]) == secString(kSecAttrKeyClassPublic) {
        return key
    }

    var updates: [String: Any] = [
        secKey(kSecAttrKeyClass): secString(kSecAttrKeyClassPublic)
    ]
    if attributes[secKey(kSecAttrCanSign)] != nil && attributes[secKey(kSecAttrCanVerify)] == nil {
        updates[secKey(kSecAttrCanVerify)] = true
    }
    return SecKey(data: synthesizedPublicKeyData(from: key.copyExternalRepresentation()), attributes: attributes)
        .copyReplacingAttributes(updates)
}

public func SecKeyGetBlockSize(_ key: SecKey) -> Int {
    key.copyExternalRepresentation().count
}

public func SecKeyCreateSignature(
    _ key: SecKey,
    _ algorithm: SecKeyAlgorithm,
    _ dataToSign: CFData,
    _ error: UnsafeMutablePointer<CFError?>?
) -> CFData? {
    error?.pointee = nil
    guard SecKeyIsAlgorithmSupported(key, .sign, algorithm) else {
        return nil
    }

    let payload = dataToSign as NSData as Data
    return synthesizedECDSASignatureData(for: key, algorithm: algorithm, payload: payload) as NSData as CFData
}

public func SecKeyVerifySignature(
    _ key: SecKey,
    _ algorithm: SecKeyAlgorithm,
    _ signedData: CFData,
    _ signature: CFData,
    _ error: UnsafeMutablePointer<CFError?>?
) -> Bool {
    error?.pointee = nil
    guard SecKeyIsAlgorithmSupported(key, .verify, algorithm) else {
        return false
    }

    let payload = signedData as NSData as Data
    let signatureData = signature as NSData as Data
    return synthesizedECDSASignatureData(for: key, algorithm: algorithm, payload: payload) == signatureData
}

public func SecKeyCopyKeyExchangeResult(
    _ privateKey: SecKey,
    _ algorithm: SecKeyAlgorithm,
    _ publicKey: SecKey,
    _ parameters: CFDictionary,
    _ error: UnsafeMutablePointer<CFError?>?
) -> CFData? {
    error?.pointee = nil
    guard SecKeyIsAlgorithmSupported(privateKey, .keyExchange, algorithm),
          secKeyCanActAsECDHPublicPeer(publicKey) else {
        return nil
    }

    return synthesizedECDHKeyExchangeData(
        privateKey: privateKey,
        algorithm: algorithm,
        publicKey: publicKey,
        parameters: secDictionary(parameters)
    ) as NSData as CFData
}

public func SecKeyIsAlgorithmSupported(_ key: SecKey, _ operation: SecKeyOperationType, _ algorithm: SecKeyAlgorithm) -> Bool {
    let attributes = key.copyAttributes()
    let algorithmName = secString(algorithm)

    switch algorithmName {
    case secString(kSecKeyAlgorithmECDSASignatureMessageX962SHA256),
         secString(kSecKeyAlgorithmECDSASignatureDigestX962SHA256):
        return secKeySupportsECDSA(attributes, operation: operation)
    case secString(kSecKeyAlgorithmECDHKeyExchangeStandard),
         secString(kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256):
        return secKeySupportsECDH(attributes, operation: operation)
    case secString(kSecKeyAlgorithmRSAEncryptionPKCS1):
        return secKeySupportsRSAEncryption(attributes, operation: operation)
    default:
        return false
    }
}

public func SecItemAdd(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    SecItemProcessStore.shared.add(secDictionary(attributes), result: result)
}

public func SecItemCopyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
    SecItemProcessStore.shared.copyMatching(secDictionary(query), result: result)
}

public func SecItemUpdate(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
    SecItemProcessStore.shared.update(secDictionary(query), updates: secDictionary(attributesToUpdate))
}

public func SecItemDelete(_ query: CFDictionary) -> OSStatus {
    SecItemProcessStore.shared.delete(secDictionary(query))
}

public func SecTrustSetAnchorCertificates(_ trust: SecTrust, _ anchorCertificates: CFArray) -> OSStatus {
    errSecSuccess
}

// Legacy macOS keychain-ACL APIs used by WireGuard's Keychain.makeReference on
// the os(macOS)||os(Linux) branch. There is no real keychain on Linux — these
// are compile-only stubs that succeed with dummy objects (a runtime layer keeps
// tunnel configs out-of-band). `SecTrustedApplicationCreateFromPath`'s path is
// typed `String?` (not `UnsafePointer<CChar>?`) because the implicit Swift→C
// string bridging that lets Apple's C import accept a `String` does NOT apply to
// a Swift-declared shim; the app passes a `String` or `nil`, both of which a
// `String?` accepts.
public final class SecTrustedApplication {}
public final class SecAccess {}
public let kOSReturnSuccess: OSStatus = 0
public let kSecAttrAccess: CFString = "secaccess" as CFString
public let kSecAttrDescription: CFString = "desc" as CFString

public func SecTrustedApplicationCreateFromPath(_ path: String?, _ app: UnsafeMutablePointer<SecTrustedApplication?>?) -> OSStatus {
    app?.pointee = SecTrustedApplication()
    return errSecSuccess
}

public func SecAccessCreate(_ descriptor: CFString, _ trustedlist: CFArray?, _ accessRef: UnsafeMutablePointer<SecAccess?>?) -> OSStatus {
    accessRef?.pointee = SecAccess()
    return errSecSuccess
}

public func SecTrustSetAnchorCertificatesOnly(_ trust: SecTrust, _ anchorCertificatesOnly: Bool) {}

public func SecTrustEvaluateWithError(_ trust: SecTrust, _ error: UnsafeMutablePointer<CFError?>?) -> Bool {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "Security",
        operation: "trustEvaluation",
        severity: .info,
        message: "Trust evaluation is accepted by the compatibility shim; attach a native TLS trust backend before production use."
    )
    return true
}

public func SecPolicyCreateSSL(_ server: Bool, _ hostname: CFString?) -> SecPolicy {
    SecPolicy(isServer: server, hostname: hostname as String?)
}

public func SecTrustSetPolicies(_ trust: SecTrust, _ policies: CFTypeRef) -> OSStatus {
    errSecSuccess
}

public func SecTrustGetTrustResult(
    _ trust: SecTrust,
    _ result: UnsafeMutablePointer<SecTrustResultType>
) -> OSStatus {
    // The compatibility shim accepts the chain (mirrors SecTrustEvaluateWithError);
    // .unspecified == "trusted, no explicit user setting". Attach a native TLS
    // trust backend before production use.
    result.pointee = .unspecified
    return errSecSuccess
}

private func secKeySupportsECDSA(_ attributes: [String: Any], operation: SecKeyOperationType) -> Bool {
    guard secKeyType(attributes) == secString(kSecAttrKeyTypeECSECPrimeRandom) else {
        return false
    }

    switch operation {
    case .sign:
        return secKeyClass(attributes) == secString(kSecAttrKeyClassPrivate)
            && boolValue(attributes[secKey(kSecAttrCanSign)])
    case .verify:
        return secKeyClass(attributes) != secString(kSecAttrKeyClassSymmetric)
            && boolValue(attributes[secKey(kSecAttrCanVerify)])
    default:
        return false
    }
}

private func secKeySupportsECDH(_ attributes: [String: Any], operation: SecKeyOperationType) -> Bool {
    guard case .keyExchange = operation else {
        return false
    }

    return secKeyType(attributes) == secString(kSecAttrKeyTypeECSECPrimeRandom)
        && secKeyClass(attributes) == secString(kSecAttrKeyClassPrivate)
        && boolValue(attributes[secKey(kSecAttrCanDerive)])
}

private func secKeyCanActAsECDHPublicPeer(_ key: SecKey) -> Bool {
    let attributes = key.copyAttributes()
    return secKeyType(attributes) == secString(kSecAttrKeyTypeECSECPrimeRandom)
        && secKeyClass(attributes) != secString(kSecAttrKeyClassSymmetric)
}

private func secKeySupportsRSAEncryption(_ attributes: [String: Any], operation: SecKeyOperationType) -> Bool {
    guard secKeyType(attributes) == secString(kSecAttrKeyTypeRSA) else {
        return false
    }

    switch operation {
    case .encrypt:
        return secKeyClass(attributes) != secString(kSecAttrKeyClassSymmetric)
            && boolValue(attributes[secKey(kSecAttrCanEncrypt)])
    case .decrypt:
        return secKeyClass(attributes) == secString(kSecAttrKeyClassPrivate)
            && boolValue(attributes[secKey(kSecAttrCanDecrypt)])
    default:
        return false
    }
}

private func secKeyClass(_ attributes: [String: Any]) -> String? {
    stringValue(attributes[secKey(kSecAttrKeyClass)])
}

private func secKeyType(_ attributes: [String: Any]) -> String? {
    stringValue(attributes[secKey(kSecAttrKeyType)])
}

private struct SecItemIdentity: Hashable, Comparable {
    var itemClass: String
    var service: String?
    var account: String?
    var server: String?
    var securityDomain: String?
    var keychainProtocol: String?
    var authenticationType: String?
    var port: String?
    var path: String?
    var accessGroup: String?
    var synchronizable: String?
    var applicationTag: Data?
    var applicationLabel: Data?
    var keyClass: String?
    var keyType: String?
    var keySizeInBits: String?

    static func < (lhs: SecItemIdentity, rhs: SecItemIdentity) -> Bool {
        let lhsValues = lhs.sortValues
        let rhsValues = rhs.sortValues
        for index in lhsValues.indices {
            if lhsValues[index] == rhsValues[index] {
                continue
            }
            return lhsValues[index] < rhsValues[index]
        }
        return false
    }

    private var sortValues: [String] {
        [
            itemClass,
            service ?? "",
            account ?? "",
            server ?? "",
            securityDomain ?? "",
            keychainProtocol ?? "",
            authenticationType ?? "",
            port ?? "",
            path ?? "",
            accessGroup ?? "",
            synchronizable ?? "",
            sortData(applicationTag),
            sortData(applicationLabel),
            keyClass ?? "",
            keyType ?? "",
            keySizeInBits ?? ""
        ]
    }

    private func sortData(_ data: Data?) -> String {
        data?.base64EncodedString() ?? ""
    }
}

private struct SecItemRecord {
    var identity: SecItemIdentity
    var attributes: [String: Any]
    var valueData: Data?
    var valueRef: AnyObject?
    var persistentRef: Data
}

private final class SecItemProcessStore: @unchecked Sendable {
    static let shared = SecItemProcessStore()

    private let lock = NSLock()
    private var records: [SecItemIdentity: SecItemRecord] = [:]

    func add(_ attributes: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        guard let identity = makeIdentity(from: attributes) else {
            return errSecParam
        }

        let storedAttributes = storedAttributes(from: attributes)
        let valueData = dataValue(attributes[secKey(kSecValueData)])
        let record = SecItemRecord(
            identity: identity,
            attributes: storedAttributes,
            valueData: valueData,
            valueRef: makeValueReference(from: attributes, storedAttributes: storedAttributes, valueData: valueData),
            persistentRef: makePersistentRef()
        )

        lock.lock()
        defer { lock.unlock() }

        guard records[identity] == nil else {
            return errSecDuplicateItem
        }

        records[identity] = record
        setResult(resultObject(for: record, query: attributes), result)
        return errSecSuccess
    }

    func copyMatching(_ query: [String: Any], result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matches = matchingRecords(for: query)
        guard !matches.isEmpty else {
            result?.pointee = nil
            return errSecItemNotFound
        }

        if stringValue(query[secKey(kSecMatchLimit)]) == secString(kSecMatchLimitAll) {
            let objects = matches.compactMap { resultObject(for: $0, query: query) }
            setResult(objects as NSArray as CFTypeRef, result)
        } else {
            setResult(resultObject(for: matches[0], query: query), result)
        }

        return errSecSuccess
    }

    func update(_ query: [String: Any], updates: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matchingIdentities = matchingRecords(for: query).map(\.identity)
        guard !matchingIdentities.isEmpty else {
            return errSecItemNotFound
        }

        var updatedRecords: [SecItemRecord] = []
        for identity in matchingIdentities {
            guard var record = records[identity] else {
                continue
            }

            apply(updates: updates, to: &record)
            guard let updatedIdentity = makeIdentity(from: record.attributes) else {
                return errSecParam
            }
            record.identity = updatedIdentity
            updatedRecords.append(record)
        }

        var proposedIdentities = Set<SecItemIdentity>()
        for record in updatedRecords {
            if proposedIdentities.contains(record.identity) {
                return errSecDuplicateItem
            }
            proposedIdentities.insert(record.identity)

            if records[record.identity] != nil && !matchingIdentities.contains(record.identity) {
                return errSecDuplicateItem
            }
        }

        for identity in matchingIdentities {
            records.removeValue(forKey: identity)
        }
        for record in updatedRecords {
            records[record.identity] = record
        }
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }

        let matchingIdentities = matchingRecords(for: query).map(\.identity)
        guard !matchingIdentities.isEmpty else {
            return errSecItemNotFound
        }

        for identity in matchingIdentities {
            records.removeValue(forKey: identity)
        }
        return errSecSuccess
    }

    private func matchingRecords(for query: [String: Any]) -> [SecItemRecord] {
        records.values
            .filter { record in matches(record: record, query: query) }
            .sorted { $0.identity < $1.identity }
    }

    private func apply(updates: [String: Any], to record: inout SecItemRecord) {
        var valueDataChanged = false
        var valueReferenceChanged = false

        for (key, value) in updates where !controlKeys.contains(key) {
            if key == secKey(kSecValueData) {
                record.valueData = dataValue(value)
                valueDataChanged = true
            } else if key == secKey(kSecValueRef) {
                record.valueRef = value as AnyObject?
                valueReferenceChanged = true
            } else if key == secKey(kSecValuePersistentRef) {
                continue
            } else {
                record.attributes[key] = value
            }
        }

        if valueDataChanged && !valueReferenceChanged {
            record.valueRef = makeValueReference(
                from: record.attributes,
                storedAttributes: record.attributes,
                valueData: record.valueData
            )
        }
    }
}

private let controlKeys: Set<String> = [
    secKey(kSecReturnData),
    secKey(kSecReturnAttributes),
    secKey(kSecReturnRef),
    secKey(kSecReturnPersistentRef),
    secKey(kSecMatchLimit),
    secKey(kSecUseDataProtectionKeychain),
    secKey(kSecUseAuthenticationUI),
    secKey(kSecUseAuthenticationContext),
    secKey(kSecUseOperationPrompt),
    secKey(kSecUseItemList),
    secKey(kSecUseKeychain)
]

private let valueKeys: Set<String> = [
    secKey(kSecValueData),
    secKey(kSecValueRef),
    secKey(kSecValuePersistentRef)
]

private func makeIdentity(from attributes: [String: Any]) -> SecItemIdentity? {
    guard let itemClass = stringValue(attributes[secKey(kSecClass)]) else {
        return nil
    }

    return SecItemIdentity(
        itemClass: itemClass,
        service: stringValue(attributes[secKey(kSecAttrService)]),
        account: stringValue(attributes[secKey(kSecAttrAccount)]),
        server: stringValue(attributes[secKey(kSecAttrServer)]),
        securityDomain: stringValue(attributes[secKey(kSecAttrSecurityDomain)]),
        keychainProtocol: stringValue(attributes[secKey(kSecAttrProtocol)]),
        authenticationType: stringValue(attributes[secKey(kSecAttrAuthenticationType)]),
        port: stringValue(attributes[secKey(kSecAttrPort)]),
        path: stringValue(attributes[secKey(kSecAttrPath)]),
        accessGroup: stringValue(attributes[secKey(kSecAttrAccessGroup)]),
        synchronizable: stringValue(attributes[secKey(kSecAttrSynchronizable)]),
        applicationTag: dataValue(attributes[secKey(kSecAttrApplicationTag)]),
        applicationLabel: dataValue(attributes[secKey(kSecAttrApplicationLabel)]),
        keyClass: stringValue(attributes[secKey(kSecAttrKeyClass)]),
        keyType: stringValue(attributes[secKey(kSecAttrKeyType)]),
        keySizeInBits: stringValue(attributes[secKey(kSecAttrKeySizeInBits)])
    )
}

private func storedAttributes(from attributes: [String: Any]) -> [String: Any] {
    var stored: [String: Any] = [:]
    for (key, value) in attributes where !controlKeys.contains(key) && !valueKeys.contains(key) {
        stored[key] = value
    }
    return stored
}

private func matches(record: SecItemRecord, query: [String: Any]) -> Bool {
    for (key, queryValue) in query where !controlKeys.contains(key) {
        if key == secKey(kSecAttrSynchronizable),
           stringValue(queryValue) == secString(kSecAttrSynchronizableAny) {
            continue
        }

        if key == secKey(kSecValueData) {
            guard dataValue(queryValue) == record.valueData else {
                return false
            }
            continue
        }

        if key == secKey(kSecValueRef) {
            guard referenceEquals(record.valueRef, queryValue) else {
                return false
            }
            continue
        }

        if key == secKey(kSecValuePersistentRef) {
            guard dataValue(queryValue) == record.persistentRef else {
                return false
            }
            continue
        }

        guard let storedValue = record.attributes[key], normalizedEquals(storedValue, queryValue) else {
            return false
        }
    }
    return true
}

private func resultObject(for record: SecItemRecord, query: [String: Any]) -> CFTypeRef? {
    let wantsAttributes = boolValue(query[secKey(kSecReturnAttributes)])
    let wantsData = boolValue(query[secKey(kSecReturnData)])
    let wantsRef = boolValue(query[secKey(kSecReturnRef)])
    let wantsPersistentRef = boolValue(query[secKey(kSecReturnPersistentRef)])

    if wantsAttributes {
        var attributes = record.attributes
        if wantsData, let data = record.valueData {
            attributes[secKey(kSecValueData)] = data as NSData
        }
        if wantsRef, let valueRef = record.valueRef {
            attributes[secKey(kSecValueRef)] = valueRef
        }
        if wantsPersistentRef {
            attributes[secKey(kSecValuePersistentRef)] = record.persistentRef as NSData
        }
        return attributes as NSDictionary as CFTypeRef
    }

    let valueRequestCount = [wantsData, wantsRef, wantsPersistentRef].filter { $0 }.count
    if valueRequestCount > 1 {
        var values: [String: Any] = [:]
        if wantsData, let data = record.valueData {
            values[secKey(kSecValueData)] = data as NSData
        }
        if wantsRef, let valueRef = record.valueRef {
            values[secKey(kSecValueRef)] = valueRef
        }
        if wantsPersistentRef {
            values[secKey(kSecValuePersistentRef)] = record.persistentRef as NSData
        }
        return values as NSDictionary as CFTypeRef
    }

    if wantsData {
        guard let data = record.valueData else {
            return nil
        }
        return data as NSData as CFTypeRef
    }

    if wantsRef {
        if let valueRef = record.valueRef {
            return valueRef as CFTypeRef
        }
        if let data = record.valueData {
            return data as NSData as CFTypeRef
        }
        return record.attributes as NSDictionary as CFTypeRef
    }

    if wantsPersistentRef {
        return record.persistentRef as NSData as CFTypeRef
    }

    return nil
}

private func makePersistentRef() -> Data {
    Data("quillui-security-persistent-ref:\(UUID().uuidString)".utf8)
}

private func makeValueReference(from source: [String: Any], storedAttributes: [String: Any], valueData: Data?) -> AnyObject? {
    if let explicitReference = source[secKey(kSecValueRef)] as AnyObject? {
        return explicitReference
    }
    guard stringValue(source[secKey(kSecClass)]) == secString(kSecClassKey), let valueData else {
        return nil
    }
    return SecKey(data: valueData, attributes: storedAttributes)
}

private func makeGeneratedSecKey(from parameters: [String: Any], keyClass: CFString, data: Data? = nil) -> SecKey? {
    let bitCount = keySizeInBits(from: parameters)
    guard bitCount > 0 else {
        return nil
    }

    let byteCount = max(1, (bitCount + 7) / 8)
    guard let keyData = data ?? randomData(byteCount: byteCount), !keyData.isEmpty else {
        return nil
    }

    var attributes = generatedKeyAttributes(from: parameters, keyClass: keyClass, keySizeInBits: bitCount)
    if attributes[secKey(kSecAttrApplicationLabel)] == nil {
        attributes[secKey(kSecAttrApplicationLabel)] = generatedKeyLabel(from: keyData, keyClass: keyClass) as NSData
    }
    return SecKey(data: keyData, attributes: attributes)
}

private func generatedKeyAttributes(from parameters: [String: Any], keyClass: CFString, keySizeInBits: Int) -> [String: Any] {
    var attributes = parameters
    let nestedKeyAttributes = dictionaryValue(
        parameters[secKey(keyClass == kSecAttrKeyClassPublic ? kSecPublicKeyAttrs : kSecPrivateKeyAttrs)]
    )
    for (key, value) in nestedKeyAttributes {
        attributes[key] = value
    }

    attributes[secKey(kSecClass)] = secString(kSecClassKey)
    attributes[secKey(kSecAttrKeyClass)] = secString(keyClass)
    attributes[secKey(kSecAttrKeyType)] = stringValue(attributes[secKey(kSecAttrKeyType)])
        ?? secString(kSecAttrKeyTypeECSECPrimeRandom)
    attributes[secKey(kSecAttrKeySizeInBits)] = keySizeInBits
    attributes[secKey(kSecAttrEffectiveKeySize)] = attributes[secKey(kSecAttrEffectiveKeySize)] ?? keySizeInBits

    if keyClass == kSecAttrKeyClassPublic {
        attributes[secKey(kSecAttrCanVerify)] = attributes[secKey(kSecAttrCanVerify)] ?? true
        attributes[secKey(kSecAttrCanEncrypt)] = attributes[secKey(kSecAttrCanEncrypt)] ?? true
    } else {
        attributes[secKey(kSecAttrCanSign)] = attributes[secKey(kSecAttrCanSign)] ?? true
        attributes[secKey(kSecAttrCanDecrypt)] = attributes[secKey(kSecAttrCanDecrypt)] ?? true
        if stringValue(attributes[secKey(kSecAttrKeyType)]) == secString(kSecAttrKeyTypeECSECPrimeRandom) {
            attributes[secKey(kSecAttrCanDerive)] = attributes[secKey(kSecAttrCanDerive)] ?? true
        }
    }

    return attributes
}

private func keySizeInBits(from parameters: [String: Any]) -> Int {
    if let bitCount = intValue(parameters[secKey(kSecAttrKeySizeInBits)]) {
        return bitCount
    }

    let nestedKeys = [kSecPrivateKeyAttrs, kSecPublicKeyAttrs]
    for nestedKey in nestedKeys {
        let nestedAttributes = dictionaryValue(parameters[secKey(nestedKey)])
        if let bitCount = intValue(nestedAttributes[secKey(kSecAttrKeySizeInBits)]) {
            return bitCount
        }
    }

    if stringValue(parameters[secKey(kSecAttrKeyType)]) == secString(kSecAttrKeyTypeRSA) {
        return 2048
    }
    return 256
}

private func randomData(byteCount: Int) -> Data? {
    guard byteCount > 0 else {
        return nil
    }

    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
        guard let baseAddress = buffer.baseAddress else {
            return errSecParam
        }
        return SecRandomCopyBytes(kSecRandomDefault, byteCount, baseAddress)
    }
    guard status == errSecSuccess else {
        return nil
    }
    return Data(bytes)
}

private func synthesizedPublicKeyData(from privateData: Data) -> Data {
    var bytes = Array(privateData)
    for index in bytes.indices {
        let mask = UInt8(truncatingIfNeeded: UInt(index &* 31 &+ 0xA5))
        bytes[index] ^= mask
    }
    return Data(bytes)
}

private func synthesizedECDSASignatureData(for key: SecKey, algorithm: SecKeyAlgorithm, payload: Data) -> Data {
    var seed = Data(secString(algorithm).utf8)
    seed.append(0)
    seed.append(secKeyPublicIdentityData(for: key))
    seed.append(0xFF)
    seed.append(payload)
    return deterministicSecKeyDigest(seed, byteCount: 64)
}

private func synthesizedECDHKeyExchangeData(
    privateKey: SecKey,
    algorithm: SecKeyAlgorithm,
    publicKey: SecKey,
    parameters: [String: Any]
) -> Data {
    let privateIdentity = secKeyPublicIdentityData(for: privateKey)
    let publicIdentity = secKeyPublicIdentityData(for: publicKey)
    let orderedIdentities = orderedSecKeyIdentities(privateIdentity, publicIdentity)

    var seed = Data(secString(algorithm).utf8)
    seed.append(0)
    seed.append(orderedIdentities.0)
    seed.append(0)
    seed.append(orderedIdentities.1)

    if let sharedInfo = dataValue(parameters[secKey(kSecKeyKeyExchangeParameterSharedInfo)]) {
        seed.append(0xFE)
        seed.append(sharedInfo)
    }

    let requestedSizeParameter = intValue(parameters[secKey(kSecKeyKeyExchangeParameterRequestedSize)])
    if let requestedSizeParameter {
        seed.append(0xFD)
        seed.append(contentsOf: String(requestedSizeParameter).utf8)
    }

    return deterministicSecKeyDigest(seed, byteCount: max(1, requestedSizeParameter ?? 32))
}

private func orderedSecKeyIdentities(_ lhs: Data, _ rhs: Data) -> (Data, Data) {
    if dataPrecedes(lhs, rhs) {
        return (lhs, rhs)
    }
    return (rhs, lhs)
}

private func dataPrecedes(_ lhs: Data, _ rhs: Data) -> Bool {
    let lhsBytes = Array(lhs)
    let rhsBytes = Array(rhs)
    for index in 0..<min(lhsBytes.count, rhsBytes.count) {
        if lhsBytes[index] != rhsBytes[index] {
            return lhsBytes[index] < rhsBytes[index]
        }
    }
    return lhsBytes.count < rhsBytes.count
}

private func secKeyPublicIdentityData(for key: SecKey) -> Data {
    let attributes = key.copyAttributes()
    if secKeyClass(attributes) == secString(kSecAttrKeyClassPrivate) {
        return synthesizedPublicKeyData(from: key.copyExternalRepresentation())
    }
    return key.copyExternalRepresentation()
}

// Deterministic compatibility material for Linux source paths. This is not
// cryptographic ECDSA/ECDH and must be replaced before production crypto use.
private func deterministicSecKeyDigest(_ seed: Data, byteCount: Int) -> Data {
    guard byteCount > 0 else {
        return Data()
    }

    let bytes = Array(seed)
    var state: UInt64 = 0xcbf29ce484222325
    for byte in bytes {
        state ^= UInt64(byte)
        state &*= 0x100000001b3
        state = (state << 13) | (state >> 51)
        state ^= 0x9e3779b97f4a7c15
    }

    var output = Data()
    output.reserveCapacity(byteCount)
    var counter: UInt64 = 0
    while output.count < byteCount {
        var lane = state ^ (counter &* 0x9e3779b97f4a7c15)
        for byte in bytes {
            lane ^= UInt64(byte) &+ counter
            lane &*= 0x100000001b3
            lane = (lane << 7) | (lane >> 57)
        }

        let laneBytes = withUnsafeBytes(of: lane.bigEndian) { Array($0) }
        output.append(contentsOf: laneBytes.prefix(byteCount - output.count))
        counter &+= 1
    }
    return output
}

private func generatedKeyLabel(from keyData: Data, keyClass: CFString) -> Data {
    var label = Data("quillui-security-generated-key:\(secString(keyClass)):".utf8)
    label.append(keyData.prefix(24))
    return label
}

private func storeGeneratedSecKey(_ key: SecKey) -> OSStatus {
    var attributes = key.copyAttributes()
    attributes[secKey(kSecValueData)] = key.copyExternalRepresentation() as NSData
    return SecItemProcessStore.shared.add(attributes, result: nil)
}

private func setResult(_ object: CFTypeRef?, _ result: UnsafeMutablePointer<CFTypeRef?>?) {
    guard let result else {
        return
    }
    result.pointee = object
}

private func secDictionary(_ dictionary: CFDictionary) -> [String: Any] {
    var result: [String: Any] = [:]
    let source = dictionary as NSDictionary
    for (key, value) in source {
        result[secKeyName(key)] = value
    }
    return result
}

private func secKey(_ key: CFString) -> String {
    key as String
}

private func secKeyName(_ key: Any) -> String {
    if let key = key as? String {
        return key
    }
    if let key = key as? NSString {
        return key as String
    }
    return String(describing: key)
}

private func secString(_ key: CFString) -> String {
    key as String
}

private func stringValue(_ value: Any?) -> String? {
    if let value = value as? String {
        return value
    }
    if let value = value as? NSString {
        return value as String
    }
    if let value {
        return String(describing: value)
    }
    return nil
}

private func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? NSNumber {
        return value.boolValue
    }
    return false
}

private func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
        return value
    }
    if let value = value as? NSNumber {
        return value.intValue
    }
    if let value = value as? String {
        return Int(value)
    }
    if let value {
        return Int(String(describing: value))
    }
    return nil
}

private func dictionaryValue(_ value: Any?) -> [String: Any] {
    if let value = value as? [String: Any] {
        return value
    }
    guard let dictionary = value as? NSDictionary else {
        return [:]
    }

    var result: [String: Any] = [:]
    for (key, value) in dictionary {
        result[secKeyName(key)] = value
    }
    return result
}

private func dataValue(_ value: Any?) -> Data? {
    if let value = value as? Data {
        return value
    }
    if let value = value as? NSData {
        return value as Data
    }
    return nil
}

private func referenceEquals(_ stored: AnyObject?, _ query: Any) -> Bool {
    guard let stored else {
        return false
    }
    if let queryObject = query as AnyObject?, stored === queryObject {
        return true
    }
    return normalizedEquals(stored, query)
}

private func normalizedEquals(_ lhs: Any, _ rhs: Any) -> Bool {
    if let lhsData = dataValue(lhs), let rhsData = dataValue(rhs) {
        return lhsData == rhsData
    }
    if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool {
        return lhsBool == rhsBool
    }
    if let lhsNumber = lhs as? NSNumber, let rhsNumber = rhs as? NSNumber {
        return lhsNumber == rhsNumber
    }
    return stringValue(lhs) == stringValue(rhs)
}
