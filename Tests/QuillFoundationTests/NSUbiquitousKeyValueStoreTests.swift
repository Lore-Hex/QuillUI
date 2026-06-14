#if os(Linux)
import Foundation
import QuillFoundation
import Testing

@Suite("NSUbiquitousKeyValueStore Linux clone")
struct NSUbiquitousKeyValueStoreTests {
    @Test func storesTypedValuesAndPublishesNotificationName() {
        let store = NSUbiquitousKeyValueStore()

        store.set(true, forKey: "enabled")
        store.set(4.5, forKey: "ratio")
        store.set(Int64(42), forKey: "count")
        store.set("value", forKey: "name")
        store.set(Data([1, 2, 3]), forKey: "payload")
        store.set(["a", "b"], forKey: "items")
        store.set(["key": "value"], forKey: "dictionary")

        #expect(store.bool(forKey: "enabled"))
        #expect(store.double(forKey: "ratio") == 4.5)
        #expect(store.longLong(forKey: "count") == 42)
        #expect(store.string(forKey: "name") == "value")
        #expect(store.data(forKey: "payload") == Data([1, 2, 3]))
        #expect(store.array(forKey: "items") as? [String] == ["a", "b"])
        #expect(store.dictionary(forKey: "dictionary")?["key"] as? String == "value")
        #expect(NSUbiquitousKeyValueStore.didChangeExternallyNotification.rawValue == "NSUbiquitousKeyValueStoreDidChangeExternallyNotification")

        store.removeObject(forKey: "name")
        #expect(store.object(forKey: "name") == nil)
        #expect(store.synchronize())
    }
}
#endif
