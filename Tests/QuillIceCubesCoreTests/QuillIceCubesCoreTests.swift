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
        #expect(statuses.count >= 4)
        let ids = Set(statuses.map(\.id))
        #expect(ids.count == statuses.count)
        #expect(QuillIceCubesProfileFixtures.rows.count == statuses.count)
    }

    @Test("Profile bare mode title is user-facing app content")
    func profileBareModeTitleIsUserFacingAppContent() {
        #expect(QuillIceCubesProfileLabels.bareTimelineTitle == "IceCubes Public Timeline")
        #expect(!QuillIceCubesProfileLabels.bareTimelineTitle.localizedCaseInsensitiveContains("placeholder"))
        #expect(!QuillIceCubesProfileLabels.bareTimelineTitle.localizedCaseInsensitiveContains("stub"))
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

    @Test("Initial timeline selection reads the shared backend env key")
    func initialTimelineSelectionReadsEnvironment() {
        let rows = QuillIceCubesProfileFixtures.rows

        #expect(QuillIceCubesInitialSelection.selectedTimelineIndexEnvironmentKey == "QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START")
        #expect(
            QuillIceCubesInitialSelection.selectedTimelineID(
                in: rows,
                environment: ["QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START": "1"]
            ) == rows[1].id
        )
        #expect(
            QuillIceCubesInitialSelection.selectedTimelineID(
                in: rows,
                environment: ["QUILLUI_ICECUBES_SELECTED_TIMELINE_INDEX_ON_START": "99"]
            ) == rows.last?.id
        )
    }

    // MARK: - Engagement counts

    @Test("Status decodes Mastodon snake_case engagement counts")
    func statusDecodesEngagementCounts() throws {
        let json = """
        {
          "id": "7",
          "content": "<p>hi</p>",
          "created_at": "2024-01-15T12:00:00Z",
          "replies_count": 4,
          "reblogs_count": 12,
          "favourites_count": 99,
          "account": { "id": "1", "acct": "a", "username": "a" }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(Status.self, from: json)
        #expect(status.repliesCount == 4)
        #expect(status.reblogsCount == 12)
        #expect(status.favouritesCount == 99)
    }

    @Test("Status defaults engagement counts to zero when absent")
    func statusDefaultsCountsToZero() throws {
        let json = """
        {
          "id": "8",
          "content": "<p>hi</p>",
          "account": { "id": "1", "acct": "a", "username": "a" }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(Status.self, from: json)
        #expect(status.repliesCount == 0)
        #expect(status.reblogsCount == 0)
        #expect(status.favouritesCount == 0)
    }

    // MARK: - Relative time

    @Test("IceCubesRelativeTime buckets seconds into now/m/h/d")
    func relativeTimeBuckets() {
        let createdAt = "2024-01-15T12:00:00Z"
        let base = IceCubesRelativeTime.parse(createdAt)!
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(30)) == "now")
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(300)) == "5m")
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(7_200)) == "2h")
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(259_200)) == "3d")
    }

    @Test("IceCubesRelativeTime falls back to an absolute date past a week")
    func relativeTimeAbsoluteDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let createdAt = "2024-01-15T12:00:00Z"
        let base = IceCubesRelativeTime.parse(createdAt)!
        // 30 days later, same calendar year → "Jan 15"
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(2_592_000), calendar: utc) == "Jan 15")
        // ~500 days later, across the year boundary → "Jan 15, 2024"
        #expect(IceCubesRelativeTime.string(fromISO8601: createdAt, now: base.addingTimeInterval(43_200_000), calendar: utc) == "Jan 15, 2024")
    }

    @Test("IceCubesRelativeTime returns empty for an unparseable timestamp")
    func relativeTimeUnparseable() {
        #expect(IceCubesRelativeTime.string(fromISO8601: "", now: Date()) == "")
        #expect(IceCubesRelativeTime.string(fromISO8601: "not-a-date", now: Date()) == "")
    }

    @Test("Timeline row precomputes timeText, subtitle, and counts")
    func timelineRowProjectsTimeAndCounts() {
        let status = Status(
            id: "9",
            account: Account(id: "9", acct: "alex", username: "alex", displayName: "Alex"),
            content: HTMLString(stringLiteral: "<p>hi</p>"),
            createdAt: "2024-01-15T12:00:00Z",
            repliesCount: 2,
            reblogsCount: 5,
            favouritesCount: 1280
        )
        // +2h is timezone-independent, so the projection is deterministic.
        let now = IceCubesRelativeTime.parse("2024-01-15T14:00:00Z")!
        let row = IceCubesTimelineRow(status: status, now: now)
        #expect(row.timeText == "2h")
        #expect(row.subtitleText == "@alex · 2h")
        #expect(row.repliesCount == 2)
        #expect(row.reblogsCount == 5)
        #expect(row.favouritesCount == 1280)
    }

    @Test("QuillIceCubesStats.summary pluralizes + omits zero metrics")
    func statsSummary() {
        #expect(QuillIceCubesStats.summary(reblogs: 12, favourites: 28) == "12 Boosts · 28 Favorites")
        #expect(QuillIceCubesStats.summary(reblogs: 1, favourites: 1) == "1 Boost · 1 Favorite")
        #expect(QuillIceCubesStats.summary(reblogs: 0, favourites: 5) == "5 Favorites")
        #expect(QuillIceCubesStats.summary(reblogs: 3, favourites: 0) == "3 Boosts")
        #expect(QuillIceCubesStats.summary(reblogs: 0, favourites: 0) == "")
        // Large-count compaction ("1.3K") is Apple's IntegerFormatStyle and
        // locale-dependent, so it isn't asserted here — only this type's own
        // pluralization + zero-omission logic is.
    }
}
