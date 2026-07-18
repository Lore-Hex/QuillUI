import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

private struct KeychainSwiftStorageKey: Codable, Hashable {
    var accessGroup: String?
    var synchronizable: Bool
    var key: String
}

private struct KeychainSwiftStorageValue: Codable, Sendable {
    var data: Data
    var reference: Data
    var access: String?
}

private struct KeychainSwiftStorageRecord: Codable {
    var key: KeychainSwiftStorageKey
    var value: KeychainSwiftStorageValue
}

/// File-backed KeychainSwift compatibility storage.
///
/// This module exists so upstream apps that import `KeychainSwift` can compile
/// and exercise account flows under QuillUI. The Linux fallback persists across
/// launches, but it intentionally does not claim native secure storage;
/// `QuillKitCapabilities.secureStorage` remains unavailable until a real Secret
/// Service backend is wired.
open class KeychainSwift: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let defaultStoreURL: URL
        private var storeURL: URL
        private var values: [KeychainSwiftStorageKey: KeychainSwiftStorageValue] = [:]

        init() {
            let defaultStoreURL = Self.makeDefaultStoreURL()
            self.defaultStoreURL = defaultStoreURL
            storeURL = defaultStoreURL
            values = Self.loadValues(from: storeURL)
        }

        func set(_ data: Data, access: String?, forKey key: KeychainSwiftStorageKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
            values[key] = KeychainSwiftStorageValue(
                data: data,
                reference: referenceData(for: key),
                access: access
            )
            return saveLocked()
        }

        func get(_ key: KeychainSwiftStorageKey) -> KeychainSwiftStorageValue? {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
            return values[key]
        }

        func delete(_ key: KeychainSwiftStorageKey) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
            guard values.removeValue(forKey: key) != nil else {
                return false
            }
            return saveLocked()
        }

        func clearNamespace(accessGroup: String?, synchronizable: Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
            let originalCount = values.count
            values = values.filter { storageKey, _ in
                storageKey.accessGroup != accessGroup
                    || storageKey.synchronizable != synchronizable
            }
            guard values.count != originalCount else {
                return false
            }
            return saveLocked()
        }

        func allKeys(accessGroup: String?, synchronizable: Bool) -> [String] {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
            return values.keys
                .filter { $0.accessGroup == accessGroup && $0.synchronizable == synchronizable }
                .map(\.key)
                .sorted()
        }

        func useStoreForTesting(_ url: URL?) {
            lock.lock()
            defer { lock.unlock() }
            storeURL = url ?? defaultStoreURL
            values = Self.loadValues(from: storeURL)
        }

        func reloadForTesting() {
            lock.lock()
            defer { lock.unlock() }
            reloadLocked()
        }

        private func referenceData(for key: KeychainSwiftStorageKey) -> Data {
            let group = key.accessGroup ?? ""
            let sync = key.synchronizable ? "1" : "0"
            return Data("keychainswift-ref:\(group):\(sync):\(key.key)".utf8)
        }

        private func reloadLocked() {
            values = Self.loadValues(from: storeURL)
        }

        private func saveLocked() -> Bool {
            let records = values
                .map { KeychainSwiftStorageRecord(key: $0.key, value: $0.value) }
                .sorted { lhs, rhs in
                    let l = lhs.key
                    let r = rhs.key
                    return [
                        l.accessGroup ?? "",
                        l.synchronizable ? "1" : "0",
                        l.key
                    ].lexicographicallyPrecedes([
                        r.accessGroup ?? "",
                        r.synchronizable ? "1" : "0",
                        r.key
                    ])
                }

            do {
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(records)
                try data.write(to: storeURL, options: [.atomic])
                return true
            } catch {
                return false
            }
        }

        private static func loadValues(from url: URL) -> [KeychainSwiftStorageKey: KeychainSwiftStorageValue] {
            guard let data = try? Data(contentsOf: url),
                  let records = try? JSONDecoder().decode([KeychainSwiftStorageRecord].self, from: data) else {
                return [:]
            }
            var loaded: [KeychainSwiftStorageKey: KeychainSwiftStorageValue] = [:]
            for record in records {
                loaded[record.key] = record.value
            }
            return loaded
        }

        private static func environmentValue(for key: String) -> String? {
            #if canImport(Darwin) || canImport(Glibc)
            return key.withCString { keyPointer in
                guard let valuePointer = getenv(keyPointer) else { return nil }
                return String(validatingCString: valuePointer)
            }
            #else
            return ProcessInfo.processInfo.environment[key]
            #endif
        }

        private static func makeDefaultStoreURL() -> URL {
            if let override = environmentValue(for: "QUILLUI_KEYCHAINSWIFT_STORE_PATH"),
               !override.isEmpty {
                return URL(fileURLWithPath: override)
            }

            #if os(Linux)
            if let dataHome = environmentValue(for: "XDG_DATA_HOME"),
               !dataHome.isEmpty {
                return URL(fileURLWithPath: dataHome)
                    .appendingPathComponent("QuillUI", isDirectory: true)
                    .appendingPathComponent("KeychainSwiftStore.json")
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share/QuillUI", isDirectory: true)
                .appendingPathComponent("KeychainSwiftStore.json")
            #else
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            return base
                .appendingPathComponent("QuillUI", isDirectory: true)
                .appendingPathComponent("KeychainSwiftStore.json")
            #endif
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

    static func quillUsePersistentStoreForTesting(_ url: URL?) {
        storage.useStoreForTesting(url)
    }

    static func quillReloadPersistentStoreForTesting() {
        storage.reloadForTesting()
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
    open func set(_ value: String, forKey key: String, withAccess: Any? = nil) -> Bool {
        guard let data = value.data(using: .utf8) else {
            lastResultCode = keychainSwiftParamStatus
            return false
        }
        return set(data, forKey: key, withAccess: withAccess)
    }

    @discardableResult
    open func set(_ value: String, forKey key: String, withAccess: KeychainSwiftAccessOptions) -> Bool {
        set(value, forKey: key, withAccess: withAccess as Any)
    }

    @discardableResult
    open func set(_ value: Data, forKey key: String, withAccess: Any? = nil) -> Bool {
        let stored = Self.storage.set(value, access: accessValue(from: withAccess), forKey: storageKey(key))
        lastResultCode = stored ? keychainSwiftSuccessStatus : keychainSwiftParamStatus
        return stored
    }

    @discardableResult
    open func set(_ value: Data, forKey key: String, withAccess: KeychainSwiftAccessOptions) -> Bool {
        set(value, forKey: key, withAccess: withAccess as Any)
    }

    @discardableResult
    open func set(_ value: Bool, forKey key: String, withAccess: Any? = nil) -> Bool {
        set(Data([value ? 1 : 0]), forKey: key, withAccess: withAccess)
    }

    @discardableResult
    open func set(_ value: Bool, forKey key: String, withAccess: KeychainSwiftAccessOptions) -> Bool {
        set(value, forKey: key, withAccess: withAccess as Any)
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
