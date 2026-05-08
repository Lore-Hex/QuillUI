import Foundation
import QuillUI
import Testing

#if os(Linux)
private enum TestColorScheme: String {
    case system
    case dark
}

@Suite("QuillUI AppStorage compatibility", .serialized)
struct AppStorageCompatibilityTests {
    @Test("primitive values use defaults then persist updates")
    func primitiveValuesPersistAcrossWrappers() {
        let prefix = "quillui.tests.primitive.\(UUID().uuidString)"
        let stringKey = "\(prefix).string"
        let boolKey = "\(prefix).bool"
        let intKey = "\(prefix).int"
        let doubleKey = "\(prefix).double"
        defer {
            [stringKey, boolKey, intKey, doubleKey].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }

        let stringStorage = AppStorage(wrappedValue: "default", stringKey)
        let boolStorage = AppStorage(wrappedValue: true, boolKey)
        let intStorage = AppStorage(wrappedValue: 7, intKey)
        let doubleStorage = AppStorage(wrappedValue: 1.25, doubleKey)

        #expect(stringStorage.wrappedValue == "default")
        #expect(boolStorage.wrappedValue == true)
        #expect(intStorage.wrappedValue == 7)
        #expect(doubleStorage.wrappedValue == 1.25)

        stringStorage.wrappedValue = "stored"
        boolStorage.wrappedValue = false
        intStorage.wrappedValue = 42
        doubleStorage.wrappedValue = 9.5

        #expect(AppStorage(wrappedValue: "ignored", stringKey).wrappedValue == "stored")
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == false)
        #expect(AppStorage(wrappedValue: 0, intKey).wrappedValue == 42)
        #expect(AppStorage(wrappedValue: 0.0, doubleKey).wrappedValue == 9.5)
    }

    @Test("projected bindings write through to UserDefaults")
    func projectedBindingWritesThrough() {
        let key = "quillui.tests.binding.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let storage = AppStorage(wrappedValue: "before", key)
        storage.projectedValue.wrappedValue = "after"

        #expect(storage.wrappedValue == "after")
        #expect(UserDefaults.standard.string(forKey: key) == "after")
    }

    @Test("stores raw-representable enum values")
    func storesRawRepresentableEnums() {
        let key = "quillui.tests.colorScheme.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let storage = AppStorage(wrappedValue: TestColorScheme.system, key)
        #expect(storage.wrappedValue == .system)

        storage.wrappedValue = .dark

        let reloaded = AppStorage(wrappedValue: TestColorScheme.system, key)
        #expect(reloaded.wrappedValue == .dark)
    }

    @Test("invalid raw-representable stored values fall back to defaults")
    func invalidRawRepresentableValuesFallBackToDefaults() {
        let key = "quillui.tests.colorScheme.invalid.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        UserDefaults.standard.set("not-a-color-scheme", forKey: key)

        let storage = AppStorage(wrappedValue: TestColorScheme.system, key)
        #expect(storage.wrappedValue == .system)

        storage.wrappedValue = .dark
        #expect(UserDefaults.standard.string(forKey: key) == TestColorScheme.dark.rawValue)
    }
}
#endif
