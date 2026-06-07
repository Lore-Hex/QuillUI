//
// NSUbiquitousKeyValueStore — Linux shadow for SignalServiceKit (Track B).
//
// Foundation's iCloud key-value store is unavailable in swift-corelibs. SSK's
// Secure Value Recovery credential backup uses `NSUbiquitousKeyValueStore.default`
// (.set / .data(forKey:)). Declared in the SignalServiceKit module so the local
// type wins over the unavailable Foundation import (same shadow pattern as
// DateComponentsFormatter).
//
// INERT: an in-memory store that round-trips within a single process but does NOT
// sync to iCloud (there is no iCloud on Linux). SVR *iCloud* credential
// backup/restore is therefore effectively unavailable — local-keychain SVR paths
// are unaffected. HONEST STATUS: no cross-device iCloud key-value sync.
//
import Foundation

public class NSUbiquitousKeyValueStore {
    nonisolated(unsafe) public static let `default` = NSUbiquitousKeyValueStore()

    private var storage: [String: Any] = [:]

    public init() {}

    public func set(_ value: Any?, forKey key: String) { storage[key] = value }
    public func set(_ value: Bool, forKey key: String) { storage[key] = value }
    public func set(_ value: Double, forKey key: String) { storage[key] = value }
    public func set(_ value: Int64, forKey key: String) { storage[key] = value }

    public func object(forKey key: String) -> Any? { storage[key] }
    public func data(forKey key: String) -> Data? { storage[key] as? Data }
    public func string(forKey key: String) -> String? { storage[key] as? String }
    public func array(forKey key: String) -> [Any]? { storage[key] as? [Any] }
    public func dictionary(forKey key: String) -> [String: Any]? { storage[key] as? [String: Any] }
    public func bool(forKey key: String) -> Bool { (storage[key] as? Bool) ?? false }
    public func double(forKey key: String) -> Double { (storage[key] as? Double) ?? 0 }
    public func longLong(forKey key: String) -> Int64 { (storage[key] as? Int64) ?? 0 }

    public func removeObject(forKey key: String) { storage[key] = nil }

    public var dictionaryRepresentation: [String: Any] { storage }

    /// No iCloud to sync with on Linux; reports success.
    @discardableResult public func synchronize() -> Bool { true }
}
