import Foundation

public final class Cache<T: Codable & Sendable>: Sendable {
    public init(storage: Any) {}
    public func insert(_ item: T, forKey key: String) async throws {}
    public func remove(forKey key: String) async throws {}
    public func allItems() async -> [T] { [] }
}

public final class DiskStorage {
    public init(directory: URL, cacheName: String) {}
}
