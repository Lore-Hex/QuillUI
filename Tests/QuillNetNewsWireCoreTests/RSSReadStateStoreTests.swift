import Foundation
import Testing
@testable import QuillNetNewsWireCore

@Suite("QuillNetNewsWire read-state persistence")
struct RSSReadStateStoreTests {
    private func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nnw-readstate-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("read-state.sqlite")
    }

    @Test("read/starred flags round-trip through a reopened store")
    func persistsAcrossReopen() throws {
        let url = tempStoreURL()
        do {
            let store = try RSSReadStateStore(url: url)
            try store.setState(articleID: "a", isRead: true, isStarred: false)
            try store.setState(articleID: "b", isRead: false, isStarred: true)
            try store.setState(articleID: "c", isRead: true, isStarred: true)
        }
        // A fresh store on the same file sees the persisted state.
        let reopened = try RSSReadStateStore(url: url)
        let (read, starred) = try reopened.load()
        #expect(read == ["a", "c"])
        #expect(starred == ["b", "c"])
    }

    @Test("setState upserts (overwrites) an article's flags by id")
    func setStateUpserts() throws {
        let store = try RSSReadStateStore(url: tempStoreURL())
        try store.setState(articleID: "x", isRead: true, isStarred: false)
        try store.setState(articleID: "x", isRead: false, isStarred: true)
        let (read, starred) = try store.load()
        #expect(read == [])
        #expect(starred == ["x"])
    }

    @Test("replaceAll overwrites the persisted state in one batch")
    func replaceAllOverwrites() throws {
        let store = try RSSReadStateStore(url: tempStoreURL())
        try store.setState(articleID: "old", isRead: true, isStarred: true)
        try store.replaceAll(read: ["x", "y"], starred: ["y"])
        let (read, starred) = try store.load()
        #expect(read == ["x", "y"])
        #expect(starred == ["y"])
    }
}
