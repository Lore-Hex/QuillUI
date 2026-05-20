import Foundation
import KeychainSwift
import Testing

private let keychainSuccessStatus: Int32 = 0
private let keychainItemNotFoundStatus: Int32 = -25300
private let keychainInvalidEncodingStatus: Int32 = -67853

@Suite("KeychainSwift compatibility store", .serialized)
struct KeychainSwiftTests {
    @Test("stores strings, data, and bools by key")
    func storesSupportedValueTypes() {
        let keychain = KeychainSwift(keyPrefix: "types-\(UUID().uuidString)-")
        defer { keychain.clear() }

        #expect(keychain.set("token", forKey: "string"))
        #expect(keychain.set(Data([0, 1, 2, 3]), forKey: "data"))
        #expect(keychain.set(true, forKey: "bool"))

        #expect(keychain.get("string") == "token")
        #expect(keychain.getData("string") == Data("token".utf8))
        #expect(keychain.getData("data") == Data([0, 1, 2, 3]))
        #expect(keychain.getData("bool") == Data([1]))
        #expect(keychain.getBool("bool") == true)
    }

    @Test("key prefixes isolate reads while clear matches the upstream namespace behavior")
    func keyPrefixesIsolateReadsAndClearNamespace() {
        let suffix = UUID().uuidString
        let first = KeychainSwift(keyPrefix: "first-\(suffix)-")
        let second = KeychainSwift(keyPrefix: "second-\(suffix)-")
        defer {
            first.clear()
            second.clear()
        }

        #expect(first.set("one", forKey: "token"))
        #expect(second.set("two", forKey: "token"))

        #expect(first.get("token") == "one")
        #expect(second.get("token") == "two")
        #expect(first.allKeys.filter { $0.hasSuffix("-\(suffix)-token") } == [
            "first-\(suffix)-token",
            "second-\(suffix)-token"
        ])

        #expect(first.delete("token"))
        #expect(first.get("token") == nil)
        #expect(second.get("token") == "two")

        #expect(first.set("one", forKey: "token"))
        #expect(first.clear())
        #expect(first.get("token") == nil)
        #expect(second.get("token") == nil)
    }

    @Test("delete removes one key without disturbing siblings")
    func deleteRemovesOneKey() {
        let keychain = KeychainSwift(keyPrefix: "delete-\(UUID().uuidString)-")
        defer { keychain.clear() }

        #expect(keychain.set("one", forKey: "first"))
        #expect(keychain.set("two", forKey: "second"))
        #expect(keychain.delete("first"))

        #expect(keychain.get("first") == nil)
        #expect(keychain.get("second") == "two")
    }

    @Test("bool reads follow upstream first-byte behavior")
    func boolReadsFollowFirstByteBehavior() {
        let keychain = KeychainSwift(keyPrefix: "bool-\(UUID().uuidString)-")
        defer { keychain.clear() }

        #expect(keychain.set("not-bool", forKey: "string"))
        #expect(keychain.set(Data(), forKey: "empty"))

        #expect(keychain.getBool("string") == false)
        #expect(keychain.getBool("empty") == nil)
    }

    @Test("data references return a stable handle instead of value bytes")
    func dataReferencesReturnStableHandles() {
        let keychain = KeychainSwift(keyPrefix: "reference-\(UUID().uuidString)-")
        defer { keychain.clear() }

        let payload = Data("payload".utf8)
        #expect(keychain.set(payload, forKey: "data"))

        let firstReference = keychain.getData("data", asReference: true)
        let secondReference = keychain.getData("data", asReference: true)
        #expect(keychain.getData("data") == payload)
        #expect(firstReference != nil)
        #expect(firstReference == secondReference)
        #expect(firstReference != payload)
    }

    @Test("access groups and synchronizable mode isolate namespaces")
    func accessGroupsAndSynchronizableModeIsolateNamespaces() {
        let prefix = "namespaces-\(UUID().uuidString)-"
        let local = KeychainSwift(keyPrefix: prefix)
        let grouped = KeychainSwift(keyPrefix: prefix, accessGroup: "group.org.signal")
        let synchronized = KeychainSwift(keyPrefix: prefix, synchronizable: true)
        defer {
            local.clear()
            grouped.clear()
            synchronized.clear()
        }

        #expect(local.set("local", forKey: "token"))
        #expect(grouped.set("group", forKey: "token"))
        #expect(synchronized.set("sync", forKey: "token"))

        #expect(local.get("token") == "local")
        #expect(grouped.get("token") == "group")
        #expect(synchronized.get("token") == "sync")

        #expect(grouped.clear())
        #expect(grouped.get("token") == nil)
        #expect(local.get("token") == "local")
        #expect(synchronized.get("token") == "sync")
    }

    @Test("tracks result codes and accepts accessibility options")
    func tracksResultCodesAndAcceptsAccessOptions() {
        let keychain = KeychainSwift(keyPrefix: "result-\(UUID().uuidString)-")
        defer { keychain.clear() }

        #expect(keychain.set(
            "token",
            forKey: "token",
            withAccess: KeychainSwiftAccessOptions.accessibleAfterFirstUnlockThisDeviceOnly
        ))
        #expect(keychain.lastResultCode == keychainSuccessStatus)
        #expect(keychain.get("token") == "token")
        #expect(keychain.lastResultCode == keychainSuccessStatus)

        #expect(keychain.get("missing") == nil)
        #expect(keychain.lastResultCode == keychainItemNotFoundStatus)

        #expect(!keychain.delete("missing"))
        #expect(keychain.lastResultCode == keychainItemNotFoundStatus)

        #expect(keychain.set(Data([0xff]), forKey: "invalid-string"))
        #expect(keychain.get("invalid-string") == nil)
        #expect(keychain.lastResultCode == keychainInvalidEncodingStatus)
    }
}
