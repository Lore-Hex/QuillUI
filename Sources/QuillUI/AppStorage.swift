import Foundation
#if os(Linux)
import SwiftOpenUI
#endif

#if os(Linux)
public protocol QuillAppStorageValue {
    static func readAppStorageValue(forKey key: String) -> Self?
    static func writeAppStorageValue(_ value: Self, forKey key: String)
}

extension String: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    public static func writeAppStorageValue(_ value: String, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Bool: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Bool? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    public static func writeAppStorageValue(_ value: Bool, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Int: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Int? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    public static func writeAppStorageValue(_ value: Int, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Double: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Double? {
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.double(forKey: key)
    }

    public static func writeAppStorageValue(_ value: Double, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

@propertyWrapper
public struct AppStorage<Value>: AnyStateStorageProvider {
    private let key: String
    private let writeValue: (Value) -> Void
    public let storage: StateStorage<Value>

    public init(wrappedValue defaultValue: Value, _ key: String) where Value: QuillAppStorageValue {
        self.key = key
        writeValue = { Value.writeAppStorageValue($0, forKey: key) }
        storage = StateStorage(Value.readAppStorageValue(forKey: key) ?? defaultValue)
    }

    public init(wrappedValue defaultValue: Value, _ key: String)
    where Value: RawRepresentable, Value.RawValue: QuillAppStorageValue {
        self.key = key
        writeValue = { Value.RawValue.writeAppStorageValue($0.rawValue, forKey: key) }
        if let rawValue = Value.RawValue.readAppStorageValue(forKey: key),
           let value = Value(rawValue: rawValue) {
            storage = StateStorage(value)
        } else {
            storage = StateStorage(defaultValue)
        }
    }

    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set {
            writeValue(newValue)
            storage.setValue(newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { storage.value },
            set: { newValue in
                writeValue(newValue)
                storage.setValue(newValue)
            }
        )
    }

    public var anyStorage: AnyStateStorage { storage }
}
#endif
