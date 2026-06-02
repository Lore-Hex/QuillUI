import Foundation
import Testing
@testable import QuillArticles

/// Smoke tests for the vendored upstream Articles module. Pins
/// the Article / Author / ArticleStatus value-shape pieces that
/// the next iteration (article-cache wiring through
/// QuillNetNewsWireCore) will lean on. Upstream Articles has no
/// test target of its own; these are Quill-side guards against
/// import-rewrite regressions.
@Suite("QuillArticles — vendored upstream smoke tests")
struct QuillArticlesSmokeTests {

    @Test("Article identity uses accountID + uniqueID + feedID for articleID synthesis")
    func articleArticleIDFromTriple() {
        // When articleID is nil, upstream synthesizes one from
        // accountID + feedID + uniqueID — routed through the
        // QuillRSCoreShim md5String extension (already pinned by
        // QuillRSCoreShimTests against RFC 1321 vectors).
        let status = ArticleStatus(
            articleID: "_unused_",
            read: false,
            starred: false,
            dateArrived: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let article = Article(
            accountID: "Local",
            articleID: nil,
            feedID: "https://example.test/feed",
            uniqueID: "post-42",
            title: "Hello",
            contentHTML: "<p>Hi</p>",
            contentText: nil,
            markdown: nil,
            url: "https://example.test/post-42",
            externalURL: nil,
            summary: nil,
            imageURL: nil,
            datePublished: nil,
            dateModified: nil,
            authors: nil,
            status: status
        )
        // articleID is synthesized — should be 32-char md5 hex.
        #expect(article.articleID.count == 32)
        #expect(article.articleID.allSatisfy { $0.isHexDigit })
        // Same triple should yield the same articleID (determinism).
        let again = Article(
            accountID: "Local",
            articleID: nil,
            feedID: "https://example.test/feed",
            uniqueID: "post-42",
            title: "Different title shouldn't matter",
            contentHTML: nil, contentText: nil, markdown: nil,
            url: nil, externalURL: nil, summary: nil, imageURL: nil,
            datePublished: nil, dateModified: nil, authors: nil, status: status
        )
        #expect(article.articleID == again.articleID)
    }

    @Test("ArticleStatus is value-equatable on read + starred + arrival")
    func articleStatusEquality() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = ArticleStatus(articleID: "x", read: false, starred: false, dateArrived: now)
        let b = ArticleStatus(articleID: "x", read: false, starred: false, dateArrived: now)
        let differentRead = ArticleStatus(articleID: "x", read: true, starred: false, dateArrived: now)
        #expect(a == b)
        #expect(a != differentRead)
    }

    @Test("Author identity is content-addressed via md5 over name + url + email + avatar")
    func authorIdentityIsContentAddressed() {
        // authorID: nil triggers upstream's synthesis path —
        // md5 hash over name/url/email/avatar via the shim.
        let one = Author(authorID: nil, name: "Brent", url: "https://example.test/brent", avatarURL: nil, emailAddress: nil)
        let two = Author(authorID: nil, name: "Brent", url: "https://example.test/brent", avatarURL: nil, emailAddress: nil)
        let diff = Author(authorID: nil, name: "Other", url: "https://example.test/brent", avatarURL: nil, emailAddress: nil)
        #expect(one?.authorID == two?.authorID)
        #expect(one?.authorID != diff?.authorID)
    }
}

private extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
