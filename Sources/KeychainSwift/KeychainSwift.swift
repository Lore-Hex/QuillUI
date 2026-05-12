import Foundation

/// Process-local KeychainSwift compatibility storage.
///
/// This module exists so upstream apps that import `KeychainSwift` can compile
/// and exercise non-sensitive flows under QuillUI. It intentionally does not
/// claim native secure persistence; `QuillKitCapabilities.secureStorage`
/// remains unavailable on Linux until a real Secret Service backend is wired.
public final class KeychainSwift: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: String] = [:]

        func set(_ value: String, forKey key: String) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = value
        }

        func get(_ key: String) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func delete(_ key: String) {
            lock.lock()
            defer { lock.unlock() }
            values.removeValue(forKey: key)
        }

        func clear(prefix: String) {
            lock.lock()
            defer { lock.unlock() }
            if prefix.isEmpty {
                values.removeAll()
            } else {
                values = values.filter { !$0.key.hasPrefix(prefix) }
            }
        }
    }

    private static let storage = Storage()

    private let keyPrefix: String

    public init() {
        self.keyPrefix = ""
    }

    public init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
    }

    private func fullKey(_ key: String) -> String {
        keyPrefix + key
    }

    @discardableResult
    public func set(_ value: String, forKey key: String, withAccess: Any? = nil) -> Bool {
        Self.storage.set(value, forKey: fullKey(key))
        return true
    }

    @discardableResult
    public func set(_ value: Data, forKey key: String, withAccess: Any? = nil) -> Bool {
        set(value.base64EncodedString(), forKey: key, withAccess: withAccess)
    }

    @discardableResult
    public func set(_ value: Bool, forKey key: String, withAccess: Any? = nil) -> Bool {
        set(value ? "true" : "false", forKey: key, withAccess: withAccess)
    }

    public func get(_ key: String) -> String? {
        Self.storage.get(fullKey(key))
    }

    public func getData(_ key: String) -> Data? {
        guard let s = get(key) else { return nil }
        return Data(base64Encoded: s)
    }

    public func getBool(_ key: String) -> Bool? {
        guard let s = get(key) else { return nil }
        switch s {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    @discardableResult
    public func delete(_ key: String) -> Bool {
        Self.storage.delete(fullKey(key))
        return true
    }

    @discardableResult
    public func clear() -> Bool {
        Self.storage.clear(prefix: keyPrefix)
        return true
    }
}
