import Foundation

/// Source-compatible accessibility options used by `KeychainSwift` callers.
public enum KeychainSwiftAccessOptions: String, Sendable {
    case accessibleWhenUnlocked = "ak"
    case accessibleAfterFirstUnlock = "ck"
    case accessibleAlways = "dk"
    case accessibleWhenPasscodeSetThisDeviceOnly = "akpu"
    case accessibleWhenUnlockedThisDeviceOnly = "aku"
    case accessibleAfterFirstUnlockThisDeviceOnly = "cku"
    case accessibleAlwaysThisDeviceOnly = "dku"
}

private let keychainSwiftSuccessStatus: Int32 = 0
private let keychainSwiftParamStatus: Int32 = -50
private let keychainSwiftItemNotFoundStatus: Int32 = -25300

private struct KeychainSwiftStorageKey: Hashable {
    var accessGroup: String?
    var synchronizable: Bool
    var key: String
}

private struct KeychainSwiftStorageValue: Sendable {
    var value: String
    var access: String?
}

/// Process-local KeychainSwift compatibility storage.
///
/// This module exists so upstream apps that import `KeychainSwift` can compile
/// and exercise non-sensitive flows under QuillUI. It intentionally does not
/// claim native secure persistence; `QuillKitCapabilities.secureStorage`
/// remains unavailable on Linux until a real Secret Service backend is wired.
public final class KeychainSwift: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [KeychainSwiftStorageKey: KeychainSwiftStorageValue] = [:]

        func set(_ value: String, access: String?, forKey key: KeychainSwiftStorageKey) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = KeychainSwiftStorageValue(value: value, access: access)
        }

        func get(_ key: KeychainSwiftStorageKey) -> String? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]?.value
        }

        func delete(_ key: KeychainSwiftStorageKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return values.removeValue(forKey: key) != nil
        }

        func clearNamespace(accessGroup: String?, synchronizable: Bool, prefix: String) {
            lock.lock()
            defer { lock.unlock() }
            if prefix.isEmpty {
                values = values.filter { storageKey, _ in
                    storageKey.accessGroup != accessGroup
                        || storageKey.synchronizable != synchronizable
                }
            } else {
                values = values.filter { storageKey, _ in
                    storageKey.accessGroup != accessGroup
                        || storageKey.synchronizable != synchronizable
                        || !storageKey.key.hasPrefix(prefix)
                }
            }
        }
    }

    private static let storage = Storage()

    private let keyPrefix: String
    public var accessGroup: String?
    public var synchronizable: Bool
    public private(set) var lastResultCode: Int32

    public init(keyPrefix: String = "", accessGroup: String? = nil, synchronizable: Bool = false) {
        self.keyPrefix = keyPrefix
        self.accessGroup = accessGroup
        self.synchronizable = synchronizable
        lastResultCode = keychainSwiftSuccessStatus
    }

    private func storageKey(_ key: String) -> KeychainSwiftStorageKey {
        KeychainSwiftStorageKey(
            accessGroup: accessGroup,
            synchronizable: synchronizable,
            key: keyPrefix + key
        )
    }

    private func accessValue(from access: Any?) -> String? {
        guard let access else {
            return nil
        }

        switch access {
        case let option as KeychainSwiftAccessOptions:
            return option.rawValue
        case let value as String:
            return value
        case let value as NSString:
            return value as String
        case let value as CustomStringConvertible:
            return value.description
        default:
            return nil
        }
    }

    @discardableResult
    public func set(_ value: String, forKey key: String, withAccess: Any? = nil) -> Bool {
        Self.storage.set(value, access: accessValue(from: withAccess), forKey: storageKey(key))
        lastResultCode = keychainSwiftSuccessStatus
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
        guard let value = Self.storage.get(storageKey(key)) else {
            lastResultCode = keychainSwiftItemNotFoundStatus
            return nil
        }
        lastResultCode = keychainSwiftSuccessStatus
        return value
    }

    public func getData(_ key: String) -> Data? {
        guard let s = get(key) else { return nil }
        guard let data = Data(base64Encoded: s) else {
            lastResultCode = keychainSwiftParamStatus
            return nil
        }
        return data
    }

    public func getBool(_ key: String) -> Bool? {
        guard let s = get(key) else { return nil }
        switch s {
        case "true":
            return true
        case "false":
            return false
        default:
            lastResultCode = keychainSwiftParamStatus
            return nil
        }
    }

    @discardableResult
    public func delete(_ key: String) -> Bool {
        let removed = Self.storage.delete(storageKey(key))
        lastResultCode = removed ? keychainSwiftSuccessStatus : keychainSwiftItemNotFoundStatus
        return true
    }

    @discardableResult
    public func clear() -> Bool {
        Self.storage.clearNamespace(
            accessGroup: accessGroup,
            synchronizable: synchronizable,
            prefix: keyPrefix
        )
        lastResultCode = keychainSwiftSuccessStatus
        return true
    }
}
