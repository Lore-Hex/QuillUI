import Foundation
import KeychainSwift
import Testing

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
        #expect(keychain.getData("data") == Data([0, 1, 2, 3]))
        #expect(keychain.getBool("bool") == true)
    }

    @Test("key prefixes isolate keys and clear only their namespace")
    func keyPrefixesIsolateAndClear() {
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

        #expect(first.clear())
        #expect(first.get("token") == nil)
        #expect(second.get("token") == "two")
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

    @Test("bool reads reject non-bool strings")
    func boolReadsRejectNonBoolStrings() {
        let keychain = KeychainSwift(keyPrefix: "bool-\(UUID().uuidString)-")
        defer { keychain.clear() }

        #expect(keychain.set("not-bool", forKey: "value"))
        #expect(keychain.getBool("value") == nil)
    }
}
