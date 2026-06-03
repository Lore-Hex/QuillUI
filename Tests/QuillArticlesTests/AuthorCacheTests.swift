import Foundation
import Testing
@testable import QuillArticles

/// Coverage for the vendored upstream `Author` value type and its
/// `AuthorCache` dedup, completing the QuillArticles real-source pins.
/// `AuthorCache` carries a real-source Linux adaptation (a block-based
/// `.lowMemory` observer in place of upstream's `#selector`, which can't
/// compile without an Obj-C runtime); these tests guard its `add`/`clear`
/// semantics. Uses fresh `AuthorCache()` instances, not `.shared`, to stay
/// isolated under parallel test runs.
@Suite("QuillArticles — Author + AuthorCache")
struct AuthorCacheTests {

    private func author(id: String, name: String) -> Author {
        Author(authorID: id, name: name, url: nil, avatarURL: nil, emailAddress: nil)!
    }

    // MARK: - Author value semantics

    @Test("Author init returns nil only when name, url, and email are all nil")
    func authorInitFailability() {
        // avatarURL alone is not enough to make an author.
        #expect(Author(authorID: nil, name: nil, url: nil, avatarURL: "https://a.test/x.png", emailAddress: nil) == nil)
        #expect(Author(authorID: nil, name: "X", url: nil, avatarURL: nil, emailAddress: nil) != nil)
        #expect(Author(authorID: nil, name: nil, url: "https://a.test", avatarURL: nil, emailAddress: nil) != nil)
    }

    @Test("Author equality and hashing are authorID-only")
    func authorEqualityByID() {
        let a = author(id: "ID", name: "Alpha")
        let b = author(id: "ID", name: "Beta")
        #expect(a == b)                 // same explicit authorID, different names → equal
        #expect(Set([a, b]).count == 1) // hash is authorID-only too
    }

    @Test("Set<Author> json() round-trips through authorsWithJSON")
    func authorJSONRoundTrip() {
        let authors: Set<Author> = [
            Author(authorID: "A", name: "Alpha", url: "https://a.test", avatarURL: nil, emailAddress: nil)!
        ]
        let json = authors.json()
        #expect(json != nil)
        let decoded = Author.authorsWithJSON(Data(json!.utf8))
        #expect(decoded?.first?.authorID == "A")
    }

    // MARK: - AuthorCache

    @Test("add dedups by authorID, returning the first-cached instance")
    func cacheDedups() {
        let cache = AuthorCache()
        let first = cache.add([author(id: "FIXED", name: "Alpha")])
        #expect(first.count == 1)
        #expect(cache.count() == 1)

        // A second author with the same authorID but a different name: the
        // cache already has "FIXED", so it returns the first-cached value.
        let second = cache.add([author(id: "FIXED", name: "Beta")])
        #expect(second.first?.name == "Alpha")
        #expect(cache.count() == 1)
    }

    @Test("add caches distinct authorIDs separately")
    func cacheDistinct() {
        let cache = AuthorCache()
        _ = cache.add([author(id: "A", name: "A"), author(id: "B", name: "B")])
        #expect(cache.count() == 2)
    }

    @Test("clear empties the cache")
    func cacheClear() {
        let cache = AuthorCache()
        _ = cache.add([author(id: "A", name: "A")])
        #expect(cache.count() == 1)
        cache.clear()
        #expect(cache.count() == 0)
    }
}
