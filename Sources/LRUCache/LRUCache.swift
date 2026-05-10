import Foundation

public final class LRUCache<Key: Hashable, Value>: Sendable where Key: Sendable, Value: Sendable {
    public init(countLimit: Int = 0) {}
    public subscript(key: Key) -> Value? {
        get { nil }
        set {}
    }
    public func removeAll() {}
}
