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
private let keychainSwiftInvalidEncodingStatus: Int32 = -67853

private struct KeychainSwiftStorageKey: Hashable {
    var accessGroup: String?
    var synchronizable: Bool
    var key: String
}

private struct KeychainSwiftStorageValue: Sendable {
    var data: Data
    var reference: Data
    var access: String?
}

/// Process-local KeychainSwift compatibility storage.
///
/// This module exists so upstream apps that import `KeychainSwift` can compile
/// and exercise non-sensitive flows under QuillUI. It intentionally does not
/// claim native secure persistence; `QuillKitCapabilities.secureStorage`
/// remains unavailable on Linux until a real Secret Service backend is wired.
open class KeychainSwift: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [KeychainSwiftStorageKey: KeychainSwiftStorageValue] = [:]

        func set(_ data: Data, access: String?, forKey key: KeychainSwiftStorageKey) {
            lock.lock()
            defer { lock.unlock() }
            values[key] = KeychainSwiftStorageValue(
                data: data,
                reference: referenceData(for: key),
                access: access
            )
        }

        func get(_ key: KeychainSwiftStorageKey) -> KeychainSwiftStorageValue? {
            lock.lock()
            defer { lock.unlock() }
            return values[key]
        }

        func delete(_ key: KeychainSwiftStorageKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return values.removeValue(forKey: key) != nil
        }

        func clearNamespace(accessGroup: String?, synchronizable: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let originalCount = values.count
            values = values.filter { storageKey, _ in
                storageKey.accessGroup != accessGroup
                    || storageKey.synchronizable != synchronizable
            }
            return values.count != originalCount
        }

        func allKeys(accessGroup: String?, synchronizable: Bool) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return values.keys
                .filter { $0.accessGroup == accessGroup && $0.synchronizable == synchronizable }
                .map(\.key)
                .sorted()
        }

        private func referenceData(for key: KeychainSwiftStorageKey) -> Data {
            let group = key.accessGroup ?? ""
            let sync = key.synchronizable ? "1" : "0"
            return Data("keychainswift-ref:\(group):\(sync):\(key.key)".utf8)
        }
    }

    private static let storage = Storage()

    var keyPrefix = ""
    open var accessGroup: String?
    open var synchronizable: Bool
    open var lastResultCode: Int32

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
    open func set(_ value: String, forKey key: String, withAccess: KeychainSwiftAccessOptions? = nil) -> Bool {
        guard let data = value.data(using: .utf8) else {
            lastResultCode = keychainSwiftParamStatus
            return false
        }
        return set(data, forKey: key, withAccess: withAccess)
    }

    @discardableResult
    open func set(_ value: Data, forKey key: String, withAccess: KeychainSwiftAccessOptions? = nil) -> Bool {
        Self.storage.set(value, access: accessValue(from: withAccess), forKey: storageKey(key))
        lastResultCode = keychainSwiftSuccessStatus
        return true
    }

    @discardableResult
    open func set(_ value: Bool, forKey key: String, withAccess: KeychainSwiftAccessOptions? = nil) -> Bool {
        set(Data([value ? 1 : 0]), forKey: key, withAccess: withAccess)
    }

    open func get(_ key: String) -> String? {
        guard let data = getData(key) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            lastResultCode = keychainSwiftInvalidEncodingStatus
            return nil
        }
        return value
    }

    open func getData(_ key: String, asReference: Bool = false) -> Data? {
        guard let value = Self.storage.get(storageKey(key)) else {
            lastResultCode = keychainSwiftItemNotFoundStatus
            return nil
        }
        lastResultCode = keychainSwiftSuccessStatus
        return asReference ? value.reference : value.data
    }

    open func getBool(_ key: String) -> Bool? {
        guard let data = getData(key), let first = data.first else {
            return nil
        }
        return first == 1
    }

    @discardableResult
    open func delete(_ key: String) -> Bool {
        let removed = Self.storage.delete(storageKey(key))
        lastResultCode = removed ? keychainSwiftSuccessStatus : keychainSwiftItemNotFoundStatus
        return removed
    }

    @discardableResult
    open func clear() -> Bool {
        let removed = Self.storage.clearNamespace(
            accessGroup: accessGroup,
            synchronizable: synchronizable
        )
        lastResultCode = removed ? keychainSwiftSuccessStatus : keychainSwiftItemNotFoundStatus
        return removed
    }

    public var allKeys: [String] {
        Self.storage.allKeys(accessGroup: accessGroup, synchronizable: synchronizable)
    }
}
