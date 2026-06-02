import Foundation
import Testing
@testable import QuillNewsBlur

/// Smoke tests for the vendored upstream NewsBlur module.
/// Pins the public types so a future re-vendor doesn't
/// silently change the API surface this Quill build depends
/// on. Upstream NewsBlur has no test target of its own — these
/// are Quill-side guards against drift.
@Suite("QuillNewsBlur — vendored upstream smoke tests")
struct QuillNewsBlurSmokeTests {

    @Test("NewsBlurFeed exposes upstream's id/title/url fields")
    func newsBlurFeedFields() {
        let feed = NewsBlurFeed(
            name: "Hacker News",
            feedID: 12345,
            feedURL: "https://hnrss.org/frontpage",
            homePageURL: "https://news.ycombinator.com",
            faviconURL: nil
        )
        #expect(feed.feedID == 12345)
        #expect(feed.name == "Hacker News")
        #expect(feed.feedURL == "https://hnrss.org/frontpage")
    }

    @Test("NewsBlurFolder typealiases NewsBlurFeedsResponse.Folder")
    func newsBlurFolderTypealias() {
        let folder = NewsBlurFolder(name: "Dev", feedIDs: [1, 2, 3])
        #expect(folder.name == "Dev")
        #expect(folder.feedIDs == [1, 2, 3])
    }

    @Test("NewsBlur namespace + public API surface is reachable")
    func newsBlurNamespaceReachable() {
        // Compiles == reachable. The actual API surface
        // (NewsBlurAPICaller / NewsBlurFeed / NewsBlurStory /
        // NewsBlurFolder / NewsBlurFolderRelationship) is what
        // the future Account-integration iteration will hook
        // into. This test just pins that the namespace types
        // compile + are visible from outside the module.
        _ = NewsBlur.self
        _ = NewsBlurFolderRelationship.self
    }
}
