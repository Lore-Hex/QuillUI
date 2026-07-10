import XCTest

#if os(Linux)
import Foundation
import CoreFoundation
import Security

final class SecurityKeychainParityTests: XCTestCase {
    func testSecRandomCopyBytesMatchesAppleFillContract() {
        let sentinel = [UInt8](repeating: 0xA5, count: 32)
        var bytes = sentinel

        let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }

        XCTAssertEqual(status, errSecSuccess)
        XCTAssertNotEqual(bytes, sentinel)

        var zeroByteSentinel = UInt8(0xA5)
        XCTAssertEqual(SecRandomCopyBytes(kSecRandomDefault, 0, &zeroByteSentinel), errSecSuccess)
        XCTAssertEqual(zeroByteSentinel, 0xA5)
    }

    func testGenericPasswordAddCopyUpdateDelete() {
        let service = "signal-\(UUID().uuidString)"
        let account = "identity-key"
        let originalData = Data([0x01, 0x02, 0x03, 0x04])
        let updatedData = Data([0x05, 0x06, 0x07, 0x08])
        let baseQuery = cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ])
        defer { _ = SecItemDelete(baseQuery) }

        var addResult: CFTypeRef?
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: originalData,
            kSecReturnAttributes: true,
            kSecReturnData: true
        ]), &addResult), errSecSuccess)

        let addedAttributes = attributes(from: addResult)
        XCTAssertEqual(addedAttributes?[string(kSecClass)] as? String, string(kSecClassGenericPassword))
        XCTAssertEqual(addedAttributes?[string(kSecAttrService)] as? String, service)
        XCTAssertEqual(addedAttributes?[string(kSecAttrAccount)] as? String, account)
        XCTAssertEqual(data(from: addedAttributes?[string(kSecValueData)]), originalData)

        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: originalData
        ]), nil), errSecDuplicateItem)

        var copyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]), &copyResult), errSecSuccess)
        XCTAssertEqual(data(from: copyResult), originalData)

        XCTAssertEqual(SecItemUpdate(baseQuery, cfDictionary([
            kSecValueData: updatedData
        ])), errSecSuccess)

        var updatedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]), &updatedResult), errSecSuccess)
        XCTAssertEqual(data(from: updatedResult), updatedData)

        XCTAssertEqual(SecItemDelete(baseQuery), errSecSuccess)
        XCTAssertEqual(SecItemDelete(baseQuery), errSecItemNotFound)
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]), nil), errSecItemNotFound)
    }

    func testAccessControlAndUseOptionsAreAcceptedForSignalStyleQueries() {
        let service = "signal-access-control-\(UUID().uuidString)"
        let account = "aci-identity-key"
        let originalData = Data([0xAA, 0xBB])
        let updatedData = Data([0xCC, 0xDD])
        let baseQuery = cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
            kSecUseOperationPrompt: "Unlock Signal identity key"
        ])
        defer { _ = SecItemDelete(baseQuery) }

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.userPresence, .privateKeyUsage],
            nil
        ) else {
            XCTFail("SecAccessControlCreateWithFlags should create a shim object")
            return
        }

        XCTAssertEqual(accessControl.protection as? String, string(kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly))
        XCTAssertTrue(accessControl.flags.contains(.userPresence))
        XCTAssertTrue(accessControl.flags.contains(.privateKeyUsage))

        var addResult: CFTypeRef?
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccessControl: accessControl,
            kSecValueData: originalData,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip,
            kSecUseOperationPrompt: "Unlock Signal identity key"
        ]), &addResult), errSecSuccess)

        let addedAttributes = attributes(from: addResult)
        let storedAccessControl = addedAttributes?[string(kSecAttrAccessControl)] as? SecAccessControl
        XCTAssertTrue(storedAccessControl === accessControl)
        XCTAssertNil(addedAttributes?[string(kSecUseDataProtectionKeychain)])
        XCTAssertNil(addedAttributes?[string(kSecUseAuthenticationUI)])
        XCTAssertNil(addedAttributes?[string(kSecUseOperationPrompt)])
        XCTAssertEqual(data(from: addedAttributes?[string(kSecValueData)]), originalData)

        var copyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIAllow,
            kSecUseAuthenticationContext: "local-auth-context",
            kSecReturnData: true
        ]), &copyResult), errSecSuccess)
        XCTAssertEqual(data(from: copyResult), originalData)

        XCTAssertEqual(SecItemUpdate(baseQuery, cfDictionary([
            kSecValueData: updatedData,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ])), errSecSuccess)

        var updatedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]), &updatedResult), errSecSuccess)
        XCTAssertEqual(data(from: updatedResult), updatedData)
    }

    func testGenericPasswordMatchLimitAllReturnsAttributes() {
        let service = "signal-session-\(UUID().uuidString)"
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service
            ]))
        }

        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "session-key",
            kSecValueData: Data([0x10])
        ]), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "profile-key",
            kSecValueData: Data([0x20])
        ]), nil), errSecSuccess)

        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]), &result), errSecSuccess)

        let rows = (result as? NSArray)?.compactMap { $0 as? NSDictionary }
        let accounts = rows?
            .compactMap { $0[string(kSecAttrAccount)] as? String }
            .sorted()
        XCTAssertEqual(accounts, ["profile-key", "session-key"])
    }

    func testAccessGroupSeparatesGenericPasswordNamespaces() {
        let service = "signal-access-group-\(UUID().uuidString)"
        let account = "identity-key"
        let personalGroup = "org.signal.private"
        let sharedGroup = "group.org.signal.shared"
        let personalData = Data([0x41, 0x42])
        let sharedData = Data([0x51, 0x52])
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service
            ]))
        }

        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: personalGroup,
            kSecValueData: personalData
        ]), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: sharedGroup,
            kSecValueData: sharedData
        ]), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: personalGroup,
            kSecValueData: personalData
        ]), nil), errSecDuplicateItem)

        var personalResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: personalGroup,
            kSecReturnData: true
        ]), &personalResult), errSecSuccess)
        XCTAssertEqual(data(from: personalResult), personalData)

        var sharedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: sharedGroup,
            kSecReturnData: true
        ]), &sharedResult), errSecSuccess)
        XCTAssertEqual(data(from: sharedResult), sharedData)

        let updatedPersonalData = Data([0x61, 0x62])
        XCTAssertEqual(SecItemUpdate(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: personalGroup
        ]), cfDictionary([
            kSecValueData: updatedPersonalData
        ])), errSecSuccess)

        var updatedPersonalResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: personalGroup,
            kSecReturnData: true
        ]), &updatedPersonalResult), errSecSuccess)
        XCTAssertEqual(data(from: updatedPersonalResult), updatedPersonalData)

        var unchangedSharedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessGroup: sharedGroup,
            kSecReturnData: true
        ]), &unchangedSharedResult), errSecSuccess)
        XCTAssertEqual(data(from: unchangedSharedResult), sharedData)
    }

    func testSynchronizableAnyMatchesLocalAndSynchronizableRows() {
        let service = "signal-sync-\(UUID().uuidString)"
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service
            ]))
        }

        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "local-key",
            kSecValueData: Data([0x11])
        ]), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "sync-key",
            kSecAttrSynchronizable: true,
            kSecValueData: Data([0x22])
        ]), nil), errSecSuccess)

        var syncOnlyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: true,
            kSecReturnAttributes: true
        ]), &syncOnlyResult), errSecSuccess)
        let syncOnlyAttributes = attributes(from: syncOnlyResult)
        XCTAssertEqual(syncOnlyAttributes?[string(kSecAttrAccount)] as? String, "sync-key")
        XCTAssertEqual(bool(from: syncOnlyAttributes?[string(kSecAttrSynchronizable)]), true)

        var anyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]), &anyResult), errSecSuccess)

        let rows = (anyResult as? NSArray)?.compactMap { $0 as? NSDictionary }
        let accounts = rows?
            .compactMap { $0[string(kSecAttrAccount)] as? String }
            .sorted()
        XCTAssertEqual(accounts, ["local-key", "sync-key"])
    }

    func testGenericPasswordPersistentReferenceRoundTrip() {
        let service = "signal-persistent-\(UUID().uuidString)"
        let account = "identity-key"
        let secret = Data([0x31, 0x32, 0x33, 0x34])
        let baseQuery = cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ])
        defer { _ = SecItemDelete(baseQuery) }

        var addResult: CFTypeRef?
        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: secret,
            kSecReturnPersistentRef: true
        ]), &addResult), errSecSuccess)

        guard let persistentRef = data(from: addResult) else {
            XCTFail("SecItemAdd should return a persistent Data handle")
            return
        }
        XCTAssertFalse(persistentRef.isEmpty)

        var copyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecValuePersistentRef: persistentRef,
            kSecReturnData: true
        ]), &copyResult), errSecSuccess)
        XCTAssertEqual(data(from: copyResult), secret)

        var mixedValueResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecValuePersistentRef: persistentRef,
            kSecReturnData: true,
            kSecReturnPersistentRef: true
        ]), &mixedValueResult), errSecSuccess)
        let mixedValues = attributes(from: mixedValueResult)
        XCTAssertEqual(data(from: mixedValues?[string(kSecValueData)]), secret)
        XCTAssertEqual(data(from: mixedValues?[string(kSecValuePersistentRef)]), persistentRef)

        var attributeResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecValuePersistentRef: persistentRef,
            kSecReturnAttributes: true,
            kSecReturnPersistentRef: true
        ]), &attributeResult), errSecSuccess)
        let attributes = attributes(from: attributeResult)
        XCTAssertEqual(attributes?[string(kSecClass)] as? String, string(kSecClassGenericPassword))
        XCTAssertEqual(attributes?[string(kSecAttrService)] as? String, service)
        XCTAssertEqual(attributes?[string(kSecAttrAccount)] as? String, account)
        XCTAssertEqual(data(from: attributes?[string(kSecValuePersistentRef)]), persistentRef)

        XCTAssertEqual(SecItemDelete(cfDictionary([
            kSecValuePersistentRef: persistentRef
        ])), errSecSuccess)

        var deletedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecValuePersistentRef: persistentRef,
            kSecReturnData: true
        ]), &deletedResult), errSecItemNotFound)
        XCTAssertNil(deletedResult)
    }

    func testKeyClassItemsUseApplicationTagAndKeyClassIdentity() {
        let applicationTag = Data("org.signal.identity-key.\(UUID().uuidString)".utf8)
        let privateKeyData = Data([0xA1, 0xB2, 0xC3, 0xD4])
        let publicKeyData = Data([0x01, 0x23, 0x45, 0x67])
        let taggedKeyQuery = cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag
        ])
        defer { _ = SecItemDelete(taggedKeyQuery) }

        let privateKeyRow: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrApplicationLabel: Data([0x01, 0x02]),
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeyType: kSecAttrKeyTypeEC,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true,
            kSecAttrCanSign: true,
            kSecAttrCanVerify: false,
            kSecValueData: privateKeyData
        ]

        var addResult: CFTypeRef?
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(privateKeyRow, [
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecReturnPersistentRef: true
        ])), &addResult), errSecSuccess)

        let addedAttributes = attributes(from: addResult)
        XCTAssertEqual(addedAttributes?[string(kSecClass)] as? String, string(kSecClassKey))
        XCTAssertEqual(data(from: addedAttributes?[string(kSecAttrApplicationTag)]), applicationTag)
        XCTAssertEqual(data(from: addedAttributes?[string(kSecAttrApplicationLabel)]), Data([0x01, 0x02]))
        XCTAssertEqual(addedAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPrivate))
        XCTAssertEqual(addedAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeEC))
        XCTAssertEqual(String(describing: addedAttributes?[string(kSecAttrKeySizeInBits)] ?? ""), "256")
        XCTAssertEqual(bool(from: addedAttributes?[string(kSecAttrIsPermanent)]), true)
        XCTAssertEqual(bool(from: addedAttributes?[string(kSecAttrCanSign)]), true)
        XCTAssertEqual(bool(from: addedAttributes?[string(kSecAttrCanVerify)]), false)
        XCTAssertEqual(data(from: addedAttributes?[string(kSecValueData)]), privateKeyData)

        guard let persistentRef = data(from: addedAttributes?[string(kSecValuePersistentRef)]) else {
            XCTFail("SecItemAdd should return a persistent reference for key rows")
            return
        }
        XCTAssertFalse(persistentRef.isEmpty)

        XCTAssertEqual(SecItemAdd(cfDictionary(privateKeyRow), nil), errSecDuplicateItem)

        XCTAssertEqual(SecItemAdd(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrApplicationLabel: Data([0x03, 0x04]),
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeyType: kSecAttrKeyTypeEC,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true,
            kSecAttrCanVerify: true,
            kSecValueData: publicKeyData
        ]), nil), errSecSuccess)

        var privateCopyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnData: true
        ]), &privateCopyResult), errSecSuccess)
        XCTAssertEqual(data(from: privateCopyResult), privateKeyData)

        var allKeysResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]), &allKeysResult), errSecSuccess)

        let rows = (allKeysResult as? NSArray)?.compactMap { $0 as? NSDictionary }
        let keyClasses = rows?
            .compactMap { $0[string(kSecAttrKeyClass)] as? String }
            .sorted()
        XCTAssertEqual(keyClasses, [string(kSecAttrKeyClassPrivate), string(kSecAttrKeyClassPublic)])

        XCTAssertEqual(SecItemDelete(cfDictionary([
            kSecValuePersistentRef: persistentRef
        ])), errSecSuccess)
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnData: true
        ]), nil), errSecItemNotFound)

        var publicCopyResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecReturnData: true
        ]), &publicCopyResult), errSecSuccess)
        XCTAssertEqual(data(from: publicCopyResult), publicKeyData)
    }

    func testSecKeyCreateWithDataRoundTripsAttributesAndExternalRepresentation() {
        let keyData = Data([0x04, 0x01, 0x02, 0x03, 0x04])
        let tag = Data("org.signal.sec-key.\(UUID().uuidString)".utf8)
        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeEC,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 256,
            kSecAttrApplicationTag: tag,
            kSecAttrCanVerify: true
        ]

        guard let key = SecKeyCreateWithData(keyData, cfDictionary(keyAttributes), nil) else {
            XCTFail("SecKeyCreateWithData should import non-empty key bytes")
            return
        }

        guard let attributes = secKeyAttributes(key) else {
            XCTFail("SecKeyCopyAttributes should return imported key attributes")
            return
        }
        XCTAssertEqual(attributes[string(kSecClass)] as? String, string(kSecClassKey))
        XCTAssertEqual(attributes[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeEC))
        XCTAssertEqual(attributes[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPublic))
        XCTAssertEqual(String(describing: attributes[string(kSecAttrKeySizeInBits)] ?? ""), "256")
        XCTAssertEqual(data(from: attributes[string(kSecAttrApplicationTag)]), tag)
        XCTAssertEqual(bool(from: attributes[string(kSecAttrCanVerify)]), true)

        XCTAssertEqual(data(from: SecKeyCopyExternalRepresentation(key, nil)), keyData)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(key, .verify, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(key, .verify, kSecKeyAlgorithmECDSASignatureDigestX962SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(key, .sign, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(key, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard))
    }

    func testKeyClassReturnRefSynthesizesSecKeyForStoredKeyData() {
        let applicationTag = Data("org.signal.return-ref.\(UUID().uuidString)".utf8)
        let keyData = Data([0x04, 0xAA, 0xBB, 0xCC])
        let keyQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: applicationTag
            ]))
        }

        let keyRow = merged(keyQuery, [
            kSecAttrApplicationLabel: Data([0x09, 0x08]),
            kSecAttrKeyType: kSecAttrKeyTypeEC,
            kSecAttrKeySizeInBits: 256,
            kSecAttrCanVerify: true,
            kSecValueData: keyData
        ])

        var addResult: CFTypeRef?
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(keyRow, [kSecReturnRef: true])), &addResult), errSecSuccess)
        guard let addedKey = addResult as? SecKey else {
            XCTFail("SecItemAdd should return a SecKey reference for key data")
            return
        }
        XCTAssertEqual(data(from: SecKeyCopyExternalRepresentation(addedKey, nil)), keyData)
        let addedAttributes = secKeyAttributes(addedKey)
        XCTAssertEqual(data(from: addedAttributes?[string(kSecAttrApplicationTag)]), applicationTag)
        XCTAssertEqual(addedAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPublic))
        XCTAssertEqual(addedAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeEC))

        var copyRefResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(keyQuery, [kSecReturnRef: true])), &copyRefResult), errSecSuccess)
        guard let copiedKey = copyRefResult as? SecKey else {
            XCTFail("SecItemCopyMatching should synthesize a SecKey reference")
            return
        }
        XCTAssertEqual(data(from: SecKeyCopyExternalRepresentation(copiedKey, nil)), keyData)

        let updatedKeyData = Data([0x04, 0x11, 0x22, 0x33])
        XCTAssertEqual(SecItemUpdate(cfDictionary(keyQuery), cfDictionary([kSecValueData: updatedKeyData])), errSecSuccess)

        var updatedRefResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(keyQuery, [kSecReturnRef: true])), &updatedRefResult), errSecSuccess)
        guard let updatedKey = updatedRefResult as? SecKey else {
            XCTFail("SecItemUpdate should refresh synthesized SecKey references")
            return
        }
        XCTAssertEqual(data(from: SecKeyCopyExternalRepresentation(updatedKey, nil)), updatedKeyData)

        var attributeResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(keyQuery, [
            kSecReturnAttributes: true,
            kSecReturnRef: true
        ])), &attributeResult), errSecSuccess)
        let attributes = attributes(from: attributeResult)
        XCTAssertTrue(attributes?[string(kSecValueRef)] is SecKey)
    }

    func testSecKeyCreateRandomKeySynthesizesPrivateKeyMetadataAndPublicKey() {
        let applicationTag = Data("org.signal.generated-private.\(UUID().uuidString)".utf8)
        let parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrApplicationTag: applicationTag,
                kSecAttrIsPermanent: true,
                kSecAttrCanSign: true,
                kSecAttrCanDerive: true
            ] as NSDictionary
        ]
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: applicationTag
            ]))
        }

        guard let privateKey = SecKeyCreateRandomKey(cfDictionary(parameters), nil) else {
            XCTFail("SecKeyCreateRandomKey should synthesize a private key")
            return
        }

        let privateData = data(from: SecKeyCopyExternalRepresentation(privateKey, nil))
        XCTAssertEqual(privateData?.count, 32)
        XCTAssertEqual(SecKeyGetBlockSize(privateKey), 32)

        let privateAttributes = secKeyAttributes(privateKey)
        XCTAssertEqual(privateAttributes?[string(kSecClass)] as? String, string(kSecClassKey))
        XCTAssertEqual(privateAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPrivate))
        XCTAssertEqual(privateAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeECSECPrimeRandom))
        XCTAssertEqual(String(describing: privateAttributes?[string(kSecAttrKeySizeInBits)] ?? ""), "256")
        XCTAssertEqual(data(from: privateAttributes?[string(kSecAttrApplicationTag)]), applicationTag)
        XCTAssertEqual(bool(from: privateAttributes?[string(kSecAttrIsPermanent)]), true)
        XCTAssertEqual(bool(from: privateAttributes?[string(kSecAttrCanSign)]), true)
        XCTAssertEqual(bool(from: privateAttributes?[string(kSecAttrCanDerive)]), true)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .sign, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .sign, kSecKeyAlgorithmECDSASignatureDigestX962SHA256))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(privateKey, .verify, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(privateKey, .encrypt, kSecKeyAlgorithmRSAEncryptionPKCS1))

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            XCTFail("SecKeyCopyPublicKey should synthesize a public key")
            return
        }
        let publicData = data(from: SecKeyCopyExternalRepresentation(publicKey, nil))
        XCTAssertEqual(publicData?.count, 32)
        XCTAssertNotEqual(publicData, privateData)
        XCTAssertEqual(SecKeyGetBlockSize(publicKey), 32)

        let publicAttributes = secKeyAttributes(publicKey)
        XCTAssertEqual(publicAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPublic))
        XCTAssertEqual(publicAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeECSECPrimeRandom))
        XCTAssertEqual(bool(from: publicAttributes?[string(kSecAttrCanVerify)]), true)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(publicKey, .verify, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(publicKey, .verify, kSecKeyAlgorithmECDSASignatureDigestX962SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(publicKey, .sign, kSecKeyAlgorithmECDSASignatureMessageX962SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(publicKey, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard))

        let message = Data("signal identity message".utf8)
        guard let messageSignature = SecKeyCreateSignature(
            privateKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            message as NSData as CFData,
            nil
        ) else {
            XCTFail("SecKeyCreateSignature should sign with generated private EC key metadata")
            return
        }
        let messageSignatureData = messageSignature as NSData as Data
        XCTAssertEqual(messageSignatureData.count, 64)
        XCTAssertTrue(SecKeyVerifySignature(
            publicKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            message as NSData as CFData,
            messageSignature,
            nil
        ))

        let tamperedMessage = Data("tampered identity message".utf8)
        XCTAssertFalse(SecKeyVerifySignature(
            publicKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            tamperedMessage as NSData as CFData,
            messageSignature,
            nil
        ))

        var tamperedSignatureData = messageSignatureData
        tamperedSignatureData[tamperedSignatureData.startIndex] = tamperedSignatureData[tamperedSignatureData.startIndex] ^ 0xFF
        XCTAssertFalse(SecKeyVerifySignature(
            publicKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            message as NSData as CFData,
            tamperedSignatureData as NSData as CFData,
            nil
        ))

        XCTAssertNil(SecKeyCreateSignature(
            publicKey,
            kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            message as NSData as CFData,
            nil
        ))

        let digest = Data(repeating: 0x5A, count: 32)
        guard let digestSignature = SecKeyCreateSignature(
            privateKey,
            kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
            digest as NSData as CFData,
            nil
        ) else {
            XCTFail("SecKeyCreateSignature should sign digest payloads")
            return
        }
        XCTAssertTrue(SecKeyVerifySignature(
            publicKey,
            kSecKeyAlgorithmECDSASignatureDigestX962SHA256,
            digest as NSData as CFData,
            digestSignature,
            nil
        ))

        var storedResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: applicationTag,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnRef: true
        ]), &storedResult), errSecSuccess)
        XCTAssertTrue(storedResult is SecKey)
    }

    func testSecKeyCopyKeyExchangeResultSynthesizesSymmetricECDHMaterial() {
        let aliceTag = Data("org.signal.ecdh.alice.\(UUID().uuidString)".utf8)
        let bobTag = Data("org.signal.ecdh.bob.\(UUID().uuidString)".utf8)
        let baseParameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256
        ]
        defer {
            _ = SecItemDelete(cfDictionary([kSecClass: kSecClassKey, kSecAttrApplicationTag: aliceTag]))
            _ = SecItemDelete(cfDictionary([kSecClass: kSecClassKey, kSecAttrApplicationTag: bobTag]))
        }

        guard let alicePrivate = SecKeyCreateRandomKey(cfDictionary(merged(baseParameters, [
            kSecPrivateKeyAttrs: [
                kSecAttrApplicationTag: aliceTag,
                kSecAttrIsPermanent: true
            ] as NSDictionary
        ])), nil),
        let bobPrivate = SecKeyCreateRandomKey(cfDictionary(merged(baseParameters, [
            kSecPrivateKeyAttrs: [
                kSecAttrApplicationTag: bobTag,
                kSecAttrIsPermanent: true
            ] as NSDictionary
        ])), nil),
        let alicePublic = SecKeyCopyPublicKey(alicePrivate),
        let bobPublic = SecKeyCopyPublicKey(bobPrivate) else {
            XCTFail("Generated EC keys should support key exchange setup")
            return
        }

        XCTAssertEqual(bool(from: secKeyAttributes(alicePrivate)?[string(kSecAttrCanDerive)]), true)
        XCTAssertEqual(bool(from: secKeyAttributes(bobPrivate)?[string(kSecAttrCanDerive)]), true)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(alicePrivate, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(alicePublic, .keyExchange, kSecKeyAlgorithmECDHKeyExchangeStandard))

        let emptyParameters = cfDictionary([:])
        let aliceSecret = data(from: SecKeyCopyKeyExchangeResult(
            alicePrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandard,
            bobPublic,
            emptyParameters,
            nil
        ))
        let bobSecret = data(from: SecKeyCopyKeyExchangeResult(
            bobPrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandard,
            alicePublic,
            emptyParameters,
            nil
        ))
        XCTAssertEqual(aliceSecret?.count, 32)
        XCTAssertEqual(aliceSecret, bobSecret)

        let sizedParameters = cfDictionary([kSecKeyKeyExchangeParameterRequestedSize: 48])
        let aliceSizedSecret = data(from: SecKeyCopyKeyExchangeResult(
            alicePrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandard,
            bobPublic,
            sizedParameters,
            nil
        ))
        let bobSizedSecret = data(from: SecKeyCopyKeyExchangeResult(
            bobPrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandard,
            alicePublic,
            sizedParameters,
            nil
        ))
        XCTAssertEqual(aliceSizedSecret?.count, 48)
        XCTAssertEqual(aliceSizedSecret, bobSizedSecret)
        XCTAssertNotEqual(aliceSizedSecret.map { Data($0.prefix(32)) }, aliceSecret)

        let sharedInfoParameters = cfDictionary([
            kSecKeyKeyExchangeParameterSharedInfo: Data("signal-handshake".utf8) as NSData
        ])
        let aliceSharedInfoSecret = data(from: SecKeyCopyKeyExchangeResult(
            alicePrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256,
            bobPublic,
            sharedInfoParameters,
            nil
        ))
        let bobSharedInfoSecret = data(from: SecKeyCopyKeyExchangeResult(
            bobPrivate,
            kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256,
            alicePublic,
            sharedInfoParameters,
            nil
        ))
        XCTAssertEqual(aliceSharedInfoSecret?.count, 32)
        XCTAssertEqual(aliceSharedInfoSecret, bobSharedInfoSecret)
        XCTAssertNotEqual(aliceSharedInfoSecret, aliceSecret)

        XCTAssertNil(SecKeyCopyKeyExchangeResult(
            alicePublic,
            kSecKeyAlgorithmECDHKeyExchangeStandard,
            bobPublic,
            emptyParameters,
            nil
        ))
        XCTAssertNil(SecKeyCopyKeyExchangeResult(
            alicePrivate,
            kSecKeyAlgorithmRSAEncryptionPKCS1,
            bobPublic,
            emptyParameters,
            nil
        ))
    }

    func testSecKeyGeneratePairReturnsClassedKeysAndStoresPermanentRows() {
        let privateTag = Data("org.signal.generated-pair.private.\(UUID().uuidString)".utf8)
        let publicTag = Data("org.signal.generated-pair.public.\(UUID().uuidString)".utf8)
        let parameters: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 512,
            kSecPrivateKeyAttrs: [
                kSecAttrApplicationTag: privateTag,
                kSecAttrIsPermanent: true,
                kSecAttrCanSign: true,
                kSecAttrCanDecrypt: true
            ] as NSDictionary,
            kSecPublicKeyAttrs: [
                kSecAttrApplicationTag: publicTag,
                kSecAttrIsPermanent: true,
                kSecAttrCanVerify: true,
                kSecAttrCanEncrypt: true
            ] as NSDictionary
        ]
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: privateTag
            ]))
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassKey,
                kSecAttrApplicationTag: publicTag
            ]))
        }

        var publicKey: SecKey?
        var privateKey: SecKey?
        XCTAssertEqual(SecKeyGeneratePair(cfDictionary(parameters), &publicKey, &privateKey), errSecSuccess)
        guard let publicKey, let privateKey else {
            XCTFail("SecKeyGeneratePair should return both keys")
            return
        }

        XCTAssertEqual(SecKeyGetBlockSize(privateKey), 64)
        XCTAssertEqual(SecKeyGetBlockSize(publicKey), 64)

        let privateAttributes = secKeyAttributes(privateKey)
        XCTAssertEqual(privateAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPrivate))
        XCTAssertEqual(privateAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeRSA))
        XCTAssertEqual(String(describing: privateAttributes?[string(kSecAttrKeySizeInBits)] ?? ""), "512")
        XCTAssertEqual(data(from: privateAttributes?[string(kSecAttrApplicationTag)]), privateTag)
        XCTAssertEqual(bool(from: privateAttributes?[string(kSecAttrCanSign)]), true)
        XCTAssertEqual(bool(from: privateAttributes?[string(kSecAttrCanDecrypt)]), true)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .decrypt, kSecKeyAlgorithmRSAEncryptionPKCS1))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(privateKey, .encrypt, kSecKeyAlgorithmRSAEncryptionPKCS1))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(privateKey, .verify, kSecKeyAlgorithmRSAEncryptionPKCS1))

        let publicAttributes = secKeyAttributes(publicKey)
        XCTAssertEqual(publicAttributes?[string(kSecAttrKeyClass)] as? String, string(kSecAttrKeyClassPublic))
        XCTAssertEqual(publicAttributes?[string(kSecAttrKeyType)] as? String, string(kSecAttrKeyTypeRSA))
        XCTAssertEqual(String(describing: publicAttributes?[string(kSecAttrKeySizeInBits)] ?? ""), "512")
        XCTAssertEqual(data(from: publicAttributes?[string(kSecAttrApplicationTag)]), publicTag)
        XCTAssertEqual(bool(from: publicAttributes?[string(kSecAttrCanVerify)]), true)
        XCTAssertEqual(bool(from: publicAttributes?[string(kSecAttrCanEncrypt)]), true)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(publicKey, .encrypt, kSecKeyAlgorithmRSAEncryptionPKCS1))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(publicKey, .decrypt, kSecKeyAlgorithmRSAEncryptionPKCS1))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(publicKey, .sign, kSecKeyAlgorithmRSAEncryptionPKCS1))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(privateKey, .sign, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(privateKey, .verify, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        XCTAssertTrue(SecKeyIsAlgorithmSupported(publicKey, .verify, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(publicKey, .sign, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256))

        var privateDataResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: privateTag,
            kSecReturnData: true
        ]), &privateDataResult), errSecSuccess)
        XCTAssertEqual(data(from: privateDataResult)?.count, 64)

        var publicRefResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: publicTag,
            kSecReturnRef: true
        ]), &publicRefResult), errSecSuccess)
        XCTAssertTrue(publicRefResult is SecKey)
    }

    func testRSAImportedPublicKeyAcceptsUnmanagedCFErrorAndStaticSignatureAlgorithm() {
        let keyData = Data([0x30, 0x0A, 0x02, 0x01, 0x03, 0x02, 0x01, 0x05])
        let keyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?

        guard let key = SecKeyCreateWithData(keyData as NSData as CFData, cfDictionary(keyAttributes), &error) else {
            XCTFail("SecKeyCreateWithData should accept RSA public key bytes and Unmanaged<CFError>")
            return
        }

        XCTAssertNil(error)
        XCTAssertEqual(
            SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256,
            kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256
        )
        XCTAssertTrue(SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256))
        XCTAssertFalse(SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256))

        let payload = Data("payload".utf8)
        let signature = Data("signature".utf8)
        XCTAssertFalse(SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            payload as NSData as CFData,
            signature as NSData as CFData,
            &error
        ))
        XCTAssertNil(error)
    }

    func testInternetPasswordNamespacesByEndpointAttributes() {
        let server = "chat.signal.example"
        let account = "primary-\(UUID().uuidString)"
        let httpsMessages = Data([0x41, 0x42])
        let httpsAttachments = Data([0x51, 0x52])
        let httpMessages = Data([0x61, 0x62])

        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassInternetPassword,
                kSecAttrServer: server,
                kSecAttrAccount: account
            ]))
        }

        let messagesQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecAttrProtocol: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort: 443,
            kSecAttrPath: "/v1/messages"
        ]
        let attachmentsQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecAttrProtocol: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort: 443,
            kSecAttrPath: "/v1/attachments"
        ]
        let httpQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecAttrProtocol: kSecAttrProtocolHTTP,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort: 80,
            kSecAttrPath: "/v1/messages"
        ]

        XCTAssertEqual(SecItemAdd(cfDictionary(merged(messagesQuery, [
            kSecValueData: httpsMessages
        ])), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(messagesQuery, [
            kSecValueData: httpsMessages
        ])), nil), errSecDuplicateItem)
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(attachmentsQuery, [
            kSecValueData: httpsAttachments
        ])), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(httpQuery, [
            kSecValueData: httpMessages
        ])), nil), errSecSuccess)

        var messagesResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(messagesQuery, [
            kSecReturnData: true
        ])), &messagesResult), errSecSuccess)
        XCTAssertEqual(data(from: messagesResult), httpsMessages)

        var allResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary([
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecReturnAttributes: true,
            kSecMatchLimit: kSecMatchLimitAll
        ]), &allResult), errSecSuccess)

        let rows = (allResult as? NSArray)?.compactMap { $0 as? NSDictionary }
        let endpointKeys = rows?
            .map { row in
                let proto = row[string(kSecAttrProtocol)] as? String ?? ""
                let port = row[string(kSecAttrPort)] ?? ""
                let path = row[string(kSecAttrPath)] as? String ?? ""
                return "\(proto):\(port):\(path)"
            }
            .sorted()
        XCTAssertEqual(endpointKeys, [
            "htps:443:/v1/attachments",
            "htps:443:/v1/messages",
            "http:80:/v1/messages"
        ])

        XCTAssertEqual(SecItemDelete(cfDictionary(messagesQuery)), errSecSuccess)
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(messagesQuery, [
            kSecReturnData: true
        ])), nil), errSecItemNotFound)

        var attachmentResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(attachmentsQuery, [
            kSecReturnData: true
        ])), &attachmentResult), errSecSuccess)
        XCTAssertEqual(data(from: attachmentResult), httpsAttachments)
    }

    func testInternetPasswordUpdateRejectsDuplicateEndpointIdentity() {
        let server = "accounts.signal.example"
        let account = "device-\(UUID().uuidString)"
        defer {
            _ = SecItemDelete(cfDictionary([
                kSecClass: kSecClassInternetPassword,
                kSecAttrServer: server,
                kSecAttrAccount: account
            ]))
        }

        let messagesQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecAttrProtocol: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort: 443,
            kSecAttrPath: "/v1/messages"
        ]
        let attachmentsQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: server,
            kSecAttrAccount: account,
            kSecAttrProtocol: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType: kSecAttrAuthenticationTypeDefault,
            kSecAttrPort: 443,
            kSecAttrPath: "/v1/attachments"
        ]

        XCTAssertEqual(SecItemAdd(cfDictionary(merged(messagesQuery, [
            kSecValueData: Data([0x10])
        ])), nil), errSecSuccess)
        XCTAssertEqual(SecItemAdd(cfDictionary(merged(attachmentsQuery, [
            kSecValueData: Data([0x20])
        ])), nil), errSecSuccess)

        XCTAssertEqual(SecItemUpdate(cfDictionary(messagesQuery), cfDictionary([
            kSecAttrPath: "/v1/attachments"
        ])), errSecDuplicateItem)

        var messagesResult: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(cfDictionary(merged(messagesQuery, [
            kSecReturnData: true
        ])), &messagesResult), errSecSuccess)
        XCTAssertEqual(data(from: messagesResult), Data([0x10]))
    }
}

private func cfDictionary(_ dictionary: [CFString: Any]) -> CFDictionary {
    dictionary as CFDictionary
}

private func merged(_ dictionary: [CFString: Any], _ updates: [CFString: Any]) -> [CFString: Any] {
    dictionary.merging(updates) { _, new in new }
}

private func string(_ key: CFString) -> String {
    key as String
}

private func attributes(from result: CFTypeRef?) -> [String: Any]? {
    (result as? NSDictionary) as? [String: Any]
}

private func secKeyAttributes(_ key: SecKey) -> [String: Any]? {
    SecKeyCopyAttributes(key)
}

private func data(from value: Any?) -> Data? {
    if let value = value as? Data {
        return value
    }
    if let value = value as? NSData {
        return value as Data
    }
    return nil
}

private func bool(from value: Any?) -> Bool? {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? NSNumber {
        return value.boolValue
    }
    return nil
}
#endif
