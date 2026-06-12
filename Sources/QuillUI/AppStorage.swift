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

extension Data: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    public static func writeAppStorageValue(_ value: Data, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

extension Optional: QuillAppStorageValue where Wrapped: QuillAppStorageValue {
    public static func readAppStorageValue(forKey key: String) -> Optional<Wrapped>? {
        Wrapped.readAppStorageValue(forKey: key)
    }

    public static func writeAppStorageValue(_ value: Optional<Wrapped>, forKey key: String) {
        guard let wrapped = value else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        Wrapped.writeAppStorageValue(wrapped, forKey: key)
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

    public init(wrappedValue defaultValue: Value, _ key: String, store: UserDefaults?) where Value: QuillAppStorageValue {
        self.init(wrappedValue: defaultValue, key, store: store ?? .standard)
    }

    public init(wrappedValue defaultValue: Value, _ key: String, store: UserDefaults) where Value: QuillAppStorageValue {
        self.key = key
        writeValue = { value in store.setAppStorageValue(value, forKey: key) }
        storage = StateStorage(store.appStorageValue(forKey: key, as: Value.self) ?? defaultValue)
    }

    public init(_ key: String) where Value: ExpressibleByNilLiteral, Value: QuillAppStorageValue {
        self.key = key
        let defaultValue: Value = nil
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

private extension UserDefaults {
    func appStorageValue<Value: QuillAppStorageValue>(forKey key: String, as type: Value.Type) -> Value? {
        switch Value.self {
        case is String.Type:
            return string(forKey: key) as? Value
        case is Bool.Type:
            guard object(forKey: key) != nil else { return nil }
            return bool(forKey: key) as? Value
        case is Int.Type:
            guard object(forKey: key) != nil else { return nil }
            return integer(forKey: key) as? Value
        case is Double.Type:
            guard object(forKey: key) != nil else { return nil }
            return double(forKey: key) as? Value
        case is Data.Type:
            return data(forKey: key) as? Value
        default:
            return Value.readAppStorageValue(forKey: key)
        }
    }

    func setAppStorageValue<Value: QuillAppStorageValue>(_ value: Value, forKey key: String) {
        switch value {
        case let value as String:
            set(value, forKey: key)
        case let value as Bool:
            set(value, forKey: key)
        case let value as Int:
            set(value, forKey: key)
        case let value as Double:
            set(value, forKey: key)
        case let value as Data:
            set(value, forKey: key)
        default:
            Value.writeAppStorageValue(value, forKey: key)
        }
    }
}
#endif
