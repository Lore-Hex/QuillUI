import Foundation
import Testing
@testable import QuillRSParser

/// Format + rich-field coverage for the vendored upstream RSParser — the
/// reusable feed parser every RSS-app port links. The existing smoke tests
/// pin basic RSS 2.0 / Atom title+items; these add the paths real feeds
/// exercise and that downstream code (QuillArticles, readers) depends on:
/// JSON Feed, `guid`/`dc:creator`/`content:encoded`/`enclosure`, CDATA +
/// XML-entity decoding, and Atom author/content/dates. Pure-data; no I/O.
@Suite("QuillRSParser — formats + rich fields")
struct QuillRSParserFormatTests {

    @Test("Parse JSON Feed: type, feed metadata, item content + date + author")
    func parseJSONFeed() throws {
        let json = """
        {
          "version": "https://jsonfeed.org/version/1",
          "title": "JSON Feed Sample",
          "home_page_url": "https://example.test/",
          "feed_url": "https://example.test/feed.json",
          "items": [
            {
              "id": "json-1",
              "url": "https://example.test/1",
              "title": "First JSON item",
              "content_html": "<p>Hello JSON.</p>",
              "date_published": "2024-01-01T12:00:00Z",
              "author": { "name": "Jane" }
            }
          ]
        }
        """
        let data = ParserData(url: "https://example.test/feed.json", data: Data(json.utf8))
        let feed = try FeedParser.parse(data)
        #expect(feed?.type == .jsonFeed)
        #expect(feed?.title == "JSON Feed Sample")
        #expect(feed?.homePageURL == "https://example.test/")
        let item = try #require(feed?.items.first)
        #expect(item.uniqueID == "json-1")
        #expect(item.url == "https://example.test/1")
        #expect(item.contentHTML == "<p>Hello JSON.</p>")
        #expect(item.datePublished != nil)
        #expect(item.authors?.first?.name == "Jane")
    }

    @Test("Parse RSS 2.0 rich fields: guid, dc:creator, content:encoded, enclosure, pubDate")
    func parseRSS2RichFields() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">
          <channel>
            <title>Rich RSS</title>
            <link>https://example.test/</link>
            <item>
              <title>Rich Item</title>
              <link>https://example.test/rich</link>
              <guid>urn:uuid:1234</guid>
              <dc:creator>Jane Doe</dc:creator>
              <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
              <content:encoded><![CDATA[<p>Full <b>content</b> here.</p>]]></content:encoded>
              <enclosure url="https://example.test/a.mp3" length="12345" type="audio/mpeg"/>
            </item>
          </channel>
        </rss>
        """
        let data = ParserData(url: "https://example.test/feed.xml", data: Data(xml.utf8))
        let feed = try FeedParser.parse(data)
        #expect(feed?.type == .rss)
        let item = try #require(feed?.items.first)
        #expect(item.uniqueID == "urn:uuid:1234")
        #expect(item.authors?.first?.name == "Jane Doe")
        #expect(item.contentHTML?.contains("Full") == true)
        #expect(item.datePublished != nil)
        let attachment = item.attachments?.first
        #expect(attachment?.url == "https://example.test/a.mp3")
        #expect(attachment?.mimeType == "audio/mpeg")
        #expect(attachment?.sizeInBytes == 12345)
    }

    @Test("RSS 2.0 decodes XML entities and preserves CDATA literally in titles")
    func parseRSS2CDATAAndEntities() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Entities</title>
            <link>https://example.test/</link>
            <item>
              <title>Tom &amp; Jerry &lt;3</title>
              <link>https://example.test/e1</link>
              <guid>e1</guid>
            </item>
            <item>
              <title><![CDATA[Raw & <markup> kept]]></title>
              <link>https://example.test/e2</link>
              <guid>e2</guid>
            </item>
          </channel>
        </rss>
        """
        let data = ParserData(url: "https://example.test/feed.xml", data: Data(xml.utf8))
        let feed = try FeedParser.parse(data)
        let byID = Dictionary(uniqueKeysWithValues: (feed?.items ?? []).map { ($0.uniqueID, $0) })
        #expect(byID["e1"]?.title == "Tom & Jerry <3")
        #expect(byID["e2"]?.title == "Raw & <markup> kept")
    }

    @Test("Parse Atom: author name + html content + published date")
    func parseAtomRichFields() throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Rich</title>
          <link href="https://example.test/" rel="alternate"/>
          <id>tag:example.test,2024:/feed</id>
          <updated>2024-03-01T12:00:00Z</updated>
          <entry>
            <title>Atom Entry</title>
            <link href="https://example.test/atom/1" rel="alternate"/>
            <id>atom-1</id>
            <published>2024-03-01T08:00:00Z</published>
            <updated>2024-03-02T09:00:00Z</updated>
            <author><name>Atom Author</name></author>
            <content type="html">&lt;p&gt;Atom body.&lt;/p&gt;</content>
          </entry>
        </feed>
        """
        let data = ParserData(url: "https://example.test/atom.xml", data: Data(xml.utf8))
        let feed = try FeedParser.parse(data)
        #expect(feed?.type == .atom)
        let item = try #require(feed?.items.first)
        #expect(item.uniqueID == "atom-1")
        #expect(item.authors?.first?.name == "Atom Author")
        #expect(item.contentHTML?.contains("Atom body") == true)
        #expect(item.datePublished != nil)
    }
}
