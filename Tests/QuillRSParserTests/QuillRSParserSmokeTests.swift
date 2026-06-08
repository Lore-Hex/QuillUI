import Foundation
import Testing
@testable import QuillRSParser

/// Smoke tests for the vendored upstream RSParser. These pin
/// the FeedParser entry point against the parsers we'll be
/// hooking into QuillNetNewsWireCore — RSS 2.0, Atom — so a
/// regression in the import-rewrite (RSCore → QuillRSCoreShim)
/// or in the cross-platform compile lands loudly.
///
/// Not exhaustive — upstream RSParser has its own test suite at
/// .upstream/netnewswire/Modules/RSParser/Tests/. These cover
/// only the surface QuillNetNewsWireCore actually needs.
@Suite("QuillRSParser — vendored upstream smoke tests")
struct QuillRSParserSmokeTests {

    @Test("Parse RSS 2.0 feed: title + items + unique IDs via md5 shim")
    func parseRSS2() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Example Feed</title>
            <link>https://example.test/</link>
            <description>Site description</description>
            <item>
              <title>First Article</title>
              <link>https://example.test/1</link>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <description>Hello.</description>
            </item>
            <item>
              <title>Second Article</title>
              <link>https://example.test/2</link>
              <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
              <description>Another post.</description>
            </item>
          </channel>
        </rss>
        """

        let data = ParserData(url: "https://example.test/feed.xml", data: Data(xml.utf8))
        let parsedFeed = try FeedParser.parse(data)
        #expect(parsedFeed?.title == "Example Feed")
        #expect(parsedFeed?.items.count == 2)

        // IDs computed via String.md5String (the upstream-faithful
        // path) so a shim drift here also fails this test.
        let ids = parsedFeed?.items.map(\.uniqueID)
        #expect(ids?.count == 2)
        #expect(ids?[0].count == 32 || ids?[0] == "https://example.test/1")
    }

    @Test("Parse Atom feed: title + entries")
    func parseAtom() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Sample Atom</title>
          <link href="https://example.test/" />
          <updated>2024-03-01T12:00:00Z</updated>
          <id>tag:example.test,2024:/feed</id>
          <entry>
            <title>Hello Atom</title>
            <link href="https://example.test/atom/1" />
            <id>tag:example.test,2024:/atom/1</id>
            <updated>2024-03-01T12:00:00Z</updated>
            <summary>Hi.</summary>
          </entry>
        </feed>
        """

        let data = ParserData(url: "https://example.test/atom.xml", data: Data(xml.utf8))
        let parsedFeed = try FeedParser.parse(data)
        #expect(parsedFeed?.title == "Sample Atom")
        #expect(parsedFeed?.items.count == 1)
        #expect(parsedFeed?.items.first?.title == "Hello Atom")
    }

    @Test("FeedType detection routes RSS / Atom correctly")
    func feedTypeDetection() {
        // Longer fixtures preserve the normal real-feed path.
        let filler = "Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod"
        let rss = "<?xml version=\"1.0\"?><rss><channel><title>X</title><description>\(filler)</description></channel></rss>"
        let atom = "<?xml version=\"1.0\"?><feed xmlns=\"http://www.w3.org/2005/Atom\"><title>X</title><subtitle>\(filler)</subtitle></feed>"

        let rssData = ParserData(url: "https://example.test/rss", data: Data(rss.utf8))
        let atomData = ParserData(url: "https://example.test/atom", data: Data(atom.utf8))

        // Top-level free function in upstream RSParser, not a FeedType init.
        #expect(feedType(rssData) == .rss)
        #expect(feedType(atomData) == .atom)
    }

    @Test("FeedType detection recognizes explicit feed markers below the inconclusive-data threshold")
    func shortFeedTypeDetection() {
        let rss = "<?xml version=\"1.0\"?><rss><channel><title>X</title></channel></rss>"
        let atom = "<?xml version=\"1.0\"?><feed><title>X</title></feed>"
        let jsonFeed = "{\"version\":\"https://jsonfeed.org/version/1\",\"items\":[]}"

        #expect(Data(rss.utf8).count < 128)
        #expect(Data(atom.utf8).count < 128)
        #expect(Data(jsonFeed.utf8).count < 128)

        #expect(feedType(ParserData(url: "https://example.test/rss", data: Data(rss.utf8))) == .rss)
        #expect(feedType(ParserData(url: "https://example.test/atom", data: Data(atom.utf8))) == .atom)
        #expect(feedType(ParserData(url: "https://example.test/feed.json", data: Data(jsonFeed.utf8))) == .jsonFeed)
    }

    @Test("FeedType keeps short inconclusive payloads unknown")
    func shortInconclusivePayloadsRemainUnknown() {
        let text = Data("not enough bytes and no feed markers".utf8)

        #expect(text.count < 128)
        #expect(feedType(ParserData(url: "https://example.test/short", data: text)) == .unknown)
    }
}
