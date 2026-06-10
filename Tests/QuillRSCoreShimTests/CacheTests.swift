import Foundation
import Testing
@testable import QuillRSCoreShim

/// Pins the vendored RSCore generic TTL `Cache` that real NetNewsWire RSWeb's
/// DownloadCache sits on. Expiry is driven entirely by the record's
/// `dateCreated` (a `CacheRecord` protocol requirement), so the tests inject
/// backdated records instead of sleeping — no wall-clock races.
@Suite("QuillRSCoreShim — Cache (vendored RSCore TTL cache)")
struct CacheTests {

    private struct StubRecord: CacheRecord {
        let dateCreated: Date
        let value: String
    }

    private func fresh(_ value: String) -> StubRecord {
        StubRecord(dateCreated: Date(), value: value)
    }

    private func expired(_ value: String, ttl: TimeInterval) -> StubRecord {
        StubRecord(dateCreated: Date(timeIntervalSinceNow: -(ttl + 60)), value: value)
    }

    @Test("set/get round-trips a fresh record")
    func roundTrip() {
        let cache = Cache<StubRecord>(timeToLive: 60, timeBetweenCleanups: 3600)
        cache["a"] = fresh("hello")
        #expect(cache["a"]?.value == "hello")
        #expect(cache["missing"] == nil)
    }

    @Test("a newer record overwrites, and nil removes")
    func overwriteAndRemove() {
        let cache = Cache<StubRecord>(timeToLive: 60, timeBetweenCleanups: 3600)
        cache["a"] = fresh("one")
        cache["a"] = fresh("two")
        #expect(cache["a"]?.value == "two")
        cache["a"] = nil
        #expect(cache["a"] == nil)
    }

    @Test("an expired record reads as nil and is evicted")
    func expiry() {
        let cache = Cache<StubRecord>(timeToLive: 60, timeBetweenCleanups: 3600)
        cache["stale"] = expired("old", ttl: 60)
        #expect(cache["stale"] == nil)
        // Second read stays nil (the lazy-expiry path removed the entry).
        #expect(cache["stale"] == nil)
        // A fresh record under the same key works again.
        cache["stale"] = fresh("new")
        #expect(cache["stale"]?.value == "new")
    }

    @Test("removeAll empties the cache")
    func removeAll() {
        let cache = Cache<StubRecord>(timeToLive: 60, timeBetweenCleanups: 3600)
        cache["a"] = fresh("a")
        cache["b"] = fresh("b")
        cache.removeAll()
        #expect(cache["a"] == nil)
        #expect(cache["b"] == nil)
    }

    @Test("cleanup() sweeps expired records while keeping fresh ones")
    func cleanupSweeps() {
        // timeBetweenCleanups 0 → every cleanupIfNeeded pass actually sweeps.
        let cache = Cache<StubRecord>(timeToLive: 60, timeBetweenCleanups: 0)
        cache["stale"] = expired("old", ttl: 60)
        cache["live"] = fresh("keep")
        cache.cleanup()
        #expect(cache["stale"] == nil)
        #expect(cache["live"]?.value == "keep")
    }
}
