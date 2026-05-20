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
#endif
