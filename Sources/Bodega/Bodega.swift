import Foundation

public struct CacheKey: Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

public struct SQLiteStorageEngine: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func `default`(appendingPath path: String) -> SQLiteStorageEngine {
        SQLiteStorageEngine(directory: FileManager.Directory.defaultStorageDirectory(appendingPath: path).url)
    }

    public func allKeys() async -> [CacheKey] {
        []
    }

    public func readAllData() async -> [Data] {
        []
    }

    public func removeAllData() async throws {}

    public func write(_ values: [(CacheKey, Data)]) async throws {
        _ = values
    }
}

public extension FileManager {
    struct Directory: Sendable {
        public var url: URL

        public init(url: URL) {
            self.url = url
        }

        public static func defaultStorageDirectory(appendingPath path: String = "") -> Directory {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("QuillBodega", isDirectory: true)
            return Directory(url: path.isEmpty ? base : base.appendingPathComponent(path, isDirectory: true))
        }
    }
}

public final class Cache<T: Codable & Sendable>: Sendable {
    public init(storage: Any) {}
    public func insert(_ item: T, forKey key: String) async throws {}
    public func remove(forKey key: String) async throws {}
    public func allItems() async -> [T] { [] }
}

public final class DiskStorage {
    public init(directory: URL, cacheName: String) {}
}
