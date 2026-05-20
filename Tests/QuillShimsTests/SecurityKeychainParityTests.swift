import XCTest

#if os(Linux)
import Foundation
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
}

private func cfDictionary(_ dictionary: [CFString: Any]) -> CFDictionary {
    dictionary as CFDictionary
}

private func string(_ key: CFString) -> String {
    key as String
}

private func attributes(from result: CFTypeRef?) -> [String: Any]? {
    (result as? NSDictionary) as? [String: Any]
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
