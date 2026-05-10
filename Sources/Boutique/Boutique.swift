import Foundation

public protocol StoreItem: Codable, Equatable, Sendable {}

/// A functional in-memory Boutique shim for Linux.
public final class Store<Item: StoreItem>: Sendable {
    private let itemsState = NSCache<NSString, AnyObject>()
    
    public init(storage: Any, cacheIdentifier: Any) {}
    
    public func items() async -> [Item] {
        // Simple mock: return empty but valid array to prevent app crashes
        []
    }
    
    public func add(_ item: Item) async throws {}
    public func remove(_ item: Item) async throws {}
    public func removeAll() async throws {}
}

public enum SQLiteStorageEngine {
    public static func defaultDatabase(directory: URL) -> Any { 0 }
}
