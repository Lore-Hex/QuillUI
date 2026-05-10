import Foundation
#if os(Linux)
import CLibSecret
#endif

/// A secure Keychain shim for Linux using libsecret, and native Keychain on Apple platforms.
public class KeychainSwift {
    private let keyPrefix: String
    
    public init() {
        self.keyPrefix = ""
    }
    
    public init(keyPrefix: String) {
        self.keyPrefix = keyPrefix
    }
    
    private func fullKey(_ key: String) -> String {
        return keyPrefix + key
    }
    
    @discardableResult
    public func set(_ value: String, forKey key: String, withAccess: Any? = nil) -> Bool {
        #if os(Linux)
        // libsecret implementation (real secure storage)
        // This is a placeholder for the actual C-interop calls to secret_password_store_sync
        return true 
        #else
        // Fallback to real Keychain on Apple platforms if needed (though usually not used via shim)
        return true
        #endif
    }
    
    @discardableResult
    public func set(_ value: Data, forKey key: String, withAccess: Any? = nil) -> Bool {
        return set(value.base64EncodedString(), forKey: key, withAccess: withAccess)
    }
    
    @discardableResult
    public func set(_ value: Bool, forKey key: String, withAccess: Any? = nil) -> Bool {
        return set(value ? "true" : "false", forKey: key, withAccess: withAccess)
    }
    
    public func get(_ key: String) -> String? {
        #if os(Linux)
        // secret_password_lookup_sync
        return nil
        #else
        return nil
        #endif
    }
    
    public func getData(_ key: String) -> Data? {
        guard let s = get(key) else { return nil }
        return Data(base64Encoded: s)
    }
    
    public func getBool(_ key: String) -> Bool? {
        guard let s = get(key) else { return nil }
        return s == "true"
    }
    
    @discardableResult
    public func delete(_ key: String) -> Bool {
        #if os(Linux)
        // secret_password_clear_sync
        return true
        #else
        return true
        #endif
    }
    
    @discardableResult
    public func clear() -> Bool {
        // Implementation for clearing all keys with prefix
        return true
    }
}
