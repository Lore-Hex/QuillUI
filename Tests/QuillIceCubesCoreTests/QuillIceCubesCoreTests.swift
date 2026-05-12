import Foundation
import Testing
@testable import QuillIceCubesCore

@Suite("IceCubes Mastodon API surface")
struct QuillIceCubesCoreTests {

    // MARK: - HTMLString

    @Test("HTMLString.asRawText strips simple paragraph tags")
    func htmlStringStripsTags() {
        let html = HTMLString(stringLiteral: "<p>Hello <b>world</b></p>")
        #expect(html.asRawText == "Hello world")
    }

    @Test("HTMLString.asRawText decodes the entity set Mastodon ships")
    func htmlStringDecodesEntities() {
        #expect(HTMLString(stringLiteral: "AT&amp;T").asRawText == "AT&T")
        #expect(HTMLString(stringLiteral: "a &lt; b").asRawText == "a < b")
        #expect(HTMLString(stringLiteral: "a &gt; b").asRawText == "a > b")
        #expect(HTMLString(stringLiteral: "say &quot;hi&quot;").asRawText == "say \"hi\"")
        #expect(HTMLString(stringLiteral: "don&#39;t").asRawText == "don't")
        #expect(HTMLString(stringLiteral: "a&nbsp;b").asRawText == "a b")
    }

    @Test("HTMLString.asRawText handles nested + adjacent tags")
    func htmlStringNestedTags() {
        let html = HTMLString(stringLiteral: "<p>line one</p><p><span class=\"h\">line two</span></p>")
        #expect(html.asRawText == "line oneline two")
    }

    @Test("HTMLString round-trips through a single-value codable container")
    func htmlStringCodable() throws {
        let payload = #"["<p>hi</p>"]"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([HTMLString].self, from: payload)
        #expect(decoded.count == 1)
        #expect(decoded[0].htmlValue == "<p>hi</p>")
        #expect(decoded[0].asRawText == "hi")
    }

    // MARK: - Account / Status decoding

    @Test("Account decodes Mastodon's snake_case display_name + avatar URL")
    func accountDecodesSnakeCase() throws {
        let json = """
        {
          "id": "1",
          "acct": "alex",
          "username": "alex",
          "display_name": "Alex Doe",
          "avatar": "https://example.test/avatar.png"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let account = try decoder.decode(Account.self, from: json)

        #expect(account.id == "1")
        #expect(account.acct == "alex")
        #expect(account.username == "alex")
        #expect(account.displayName == "Alex Doe")
        #expect(account.avatar?.absoluteString == "https://example.test/avatar.png")
    }

    @Test("Account.cachedDisplayName falls back to username when display_name is nil")
    func accountCachedDisplayNameFallback() {
        let withName = Account(id: "1", acct: "a", username: "alex", displayName: "Alex")
        let withoutName = Account(id: "2", acct: "b", username: "bobby")
        #expect(withName.cachedDisplayName.htmlValue == "Alex")
        #expect(withName.displayNameText == "Alex")
        #expect(withName.handleText == "@a")
        #expect(withoutName.cachedDisplayName.htmlValue == "bobby")
        #expect(withoutName.displayNameText == "bobby")
        #expect(withoutName.handleText == "@b")
    }

    @Test("Status decodes nested account + HTMLString content + created_at")
    func statusDecodesNestedAccount() throws {
        let json = """
        {
          "id": "42",
          "content": "<p>hello</p>",
          "created_at": "2024-01-15T12:00:00Z",
          "account": {
            "id": "1",
            "acct": "alex",
            "username": "alex",
            "display_name": "Alex",
            "avatar": null
          }
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(Status.self, from: json)

        #expect(status.id == "42")
        #expect(status.content.htmlValue == "<p>hello</p>")
        #expect(status.content.asRawText == "hello")
        #expect(status.contentText == "hello")
        #expect(status.createdAt == "2024-01-15T12:00:00Z")
        #expect(status.account.id == "1")
        #expect(status.account.displayName == "Alex")
        #expect(status.account.displayNameText == "Alex")
        #expect(status.account.handleText == "@alex")
        #expect(status.account.avatar == nil)
    }

    // MARK: - Timelines endpoint

    @Test("Timelines.pub path is the Mastodon public timeline endpoint")
    func timelinesPubPath() {
        let endpoint: Timelines = .pub(sinceId: nil, maxId: nil, minId: nil, local: false, limit: 40)
        #expect(endpoint.path == "/api/v1/timelines/public")
    }

    @Test("Timelines.pub query always carries local + limit")
    func timelinesPubAlwaysHasLocalAndLimit() {
        let endpoint: Timelines = .pub(sinceId: nil, maxId: nil, minId: nil, local: true, limit: 20)
        let items = endpoint.query
        let pairs = items.map { ($0.name, $0.value) }
        #expect(pairs.contains(where: { $0.0 == "local" && $0.1 == "true" }))
        #expect(pairs.contains(where: { $0.0 == "limit" && $0.1 == "20" }))
        #expect(items.count == 2) // no since/max/min when nil
    }

    @Test("Timelines.pub query appends since/max/min ids only when non-nil")
    func timelinesPubAppendsOptionalIds() {
        let endpoint: Timelines = .pub(
            sinceId: "100",
            maxId: "200",
            minId: "150",
            local: false,
            limit: 40
        )
        let pairs = endpoint.query.map { ($0.name, $0.value) }

        #expect(pairs.contains(where: { $0.0 == "since_id" && $0.1 == "100" }))
        #expect(pairs.contains(where: { $0.0 == "max_id" && $0.1 == "200" }))
        #expect(pairs.contains(where: { $0.0 == "min_id" && $0.1 == "150" }))
        #expect(pairs.contains(where: { $0.0 == "local" && $0.1 == "false" }))
        #expect(pairs.contains(where: { $0.0 == "limit" && $0.1 == "40" }))
    }

    @Test("Timelines.pub local=true encodes the string \"true\" (not 1)")
    func timelinesPubLocalEncoding() {
        let local: Timelines = .pub(sinceId: nil, maxId: nil, minId: nil, local: true, limit: 5)
        let remote: Timelines = .pub(sinceId: nil, maxId: nil, minId: nil, local: false, limit: 5)
        #expect(local.query.first(where: { $0.name == "local" })?.value == "true")
        #expect(remote.query.first(where: { $0.name == "local" })?.value == "false")
    }

    // MARK: - MastodonClient construction

    @Test("MastodonClient defaults to v1 + no oauth token")
    func mastodonClientDefaults() {
        let client = MastodonClient(server: "mastodon.social")
        #expect(client.server == "mastodon.social")
        #expect(client.oauthToken == nil)
        if case .v1 = client.version { } else { Issue.record("expected .v1") }
    }

    // MARK: - Profile fixtures

    @Test("Profile fixtures are non-empty with unique ids")
    func profileFixturesShape() {
        let statuses = QuillIceCubesProfileFixtures.statuses
        #expect(!statuses.isEmpty)
        let ids = Set(statuses.map(\.id))
        #expect(ids.count == statuses.count)
        #expect(QuillIceCubesProfileFixtures.rows.count == statuses.count)
    }

    @Test("Profile fixtures carry an account display name + non-empty content")
    func profileFixturesContent() {
        for status in QuillIceCubesProfileFixtures.statuses {
            #expect(status.account.displayName?.isEmpty == false)
            #expect(!status.content.asRawText.isEmpty)
            #expect(status.account.displayNameText == status.account.cachedDisplayName.asRawText)
            #expect(status.account.handleText == "@\(status.account.acct)")
            #expect(status.contentText == status.content.asRawText)
        }
    }

    @Test("Timeline rows project render-facing status fields once")
    func timelineRowsProjectStoredStatusFields() {
        for (status, row) in zip(QuillIceCubesProfileFixtures.statuses, QuillIceCubesProfileFixtures.rows) {
            #expect(row.id == status.id)
            #expect(row.displayNameText == status.account.displayNameText)
            #expect(row.handleText == status.account.handleText)
            #expect(row.contentText == status.contentText)
            #expect(row.avatar == status.account.avatar)
        }
    }
}
