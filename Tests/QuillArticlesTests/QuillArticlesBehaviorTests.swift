import Foundation
import Testing
@testable import QuillArticles

/// Behavior coverage for the vendored upstream Articles module — the
/// `Set`/`Array` collection helpers and `ArticleStatus` mutation that the
/// article-cache wiring leans on. Complements `QuillArticlesSmokeTests`'
/// value-shape pins; upstream Articles ships no test target of its own, so
/// these are Quill-side guards against import-rewrite / shim regressions
/// (notably the Linux `OSAllocatedUnfairLock` path behind `read`/`starred`).
@Suite("QuillArticles — collection + status behavior")
struct QuillArticlesBehaviorTests {

    private func makeStatus(read: Bool = false, starred: Bool = false, id: String = "s") -> ArticleStatus {
        ArticleStatus(
            articleID: id, read: read, starred: starred,
            dateArrived: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeArticle(uniqueID: String, read: Bool = false, starred: Bool = false) -> Article {
        Article(
            accountID: "Local", articleID: nil,
            feedID: "https://example.test/feed", uniqueID: uniqueID,
            title: uniqueID, contentHTML: nil, contentText: nil, markdown: nil,
            url: nil, externalURL: nil, summary: nil, imageURL: nil,
            datePublished: nil, dateModified: nil, authors: nil,
            status: makeStatus(read: read, starred: starred, id: uniqueID)
        )
    }

    // MARK: - ArticleStatus

    @Test("boolStatus / setBoolStatus round-trip via Key, mutating in place")
    func statusBoolRoundTrip() {
        let s = makeStatus(read: false, starred: false)
        #expect(s.boolStatus(forKey: .read) == false)
        #expect(s.boolStatus(forKey: .starred) == false)
        s.setBoolStatus(true, forKey: .read)
        s.setBoolStatus(true, forKey: .starred)
        #expect(s.boolStatus(forKey: .read))
        #expect(s.boolStatus(forKey: .starred))
        // ArticleStatus is a reference type — the same instance is mutated.
        #expect(s.read)
        #expect(s.starred)
    }

    @Test("convenience init defaults starred to false")
    func statusConvenienceInit() {
        let s = ArticleStatus(
            articleID: "x", read: true,
            dateArrived: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(s.read)
        #expect(s.starred == false)
    }

    @Test("ArticleStatus.Key raw values are the stable wire strings")
    func statusKeyRawValues() {
        #expect(ArticleStatus.Key.read.rawValue == "read")
        #expect(ArticleStatus.Key.starred.rawValue == "starred")
    }

    // MARK: - Article identity + collections

    @Test("calculatedArticleID is a deterministic 32-char md5 of feedID + uniqueID")
    func calculatedArticleIDDeterminism() {
        let id1 = Article.calculatedArticleID(feedID: "F", uniqueID: "U")
        #expect(id1 == Article.calculatedArticleID(feedID: "F", uniqueID: "U"))
        #expect(id1.count == 32)
        #expect(id1 != Article.calculatedArticleID(feedID: "F", uniqueID: "V"))
    }

    @Test("Set<Article>.articleIDs collects the synthesized IDs")
    func setArticleIDs() {
        let a = makeArticle(uniqueID: "a")
        let b = makeArticle(uniqueID: "b")
        let ids = Set([a, b]).articleIDs()
        #expect(ids == Set([a.articleID, b.articleID]))
        #expect(ids.count == 2)
    }

    @Test("Set<Article>.unreadArticles filters on status.read")
    func setUnreadArticles() {
        let unread = makeArticle(uniqueID: "u", read: false)
        let read = makeArticle(uniqueID: "r", read: true)
        #expect(Set([unread, read]).unreadArticles() == Set([unread]))
    }

    @Test("Set<Article>.contains(accountID:articleID:) matches on both fields")
    func setContains() {
        let a = makeArticle(uniqueID: "a")
        let set = Set([a])
        #expect(set.contains(accountID: "Local", articleID: a.articleID))
        #expect(!set.contains(accountID: "Other", articleID: a.articleID))
        #expect(!set.contains(accountID: "Local", articleID: "nope"))
    }

    @Test("Array<Article>.articleIDs preserves order")
    func arrayArticleIDs() {
        let a = makeArticle(uniqueID: "a")
        let b = makeArticle(uniqueID: "b")
        #expect([a, b].articleIDs() == [a.articleID, b.articleID])
    }

    @Test("Set/Array<ArticleStatus>.articleIDs collect their IDs")
    func statusArticleIDs() {
        let s1 = makeStatus(id: "1")
        let s2 = makeStatus(id: "2")
        #expect(Set([s1, s2]).articleIDs() == Set(["1", "2"]))
        #expect([s1, s2].articleIDs() == ["1", "2"])
    }
}
