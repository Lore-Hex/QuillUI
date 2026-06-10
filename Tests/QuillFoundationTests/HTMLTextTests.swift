import Testing
@testable import QuillFoundation

@Suite("QuillFoundation HTMLText")
struct HTMLTextTests {
    // MARK: - plainText

    @Test("plainText strips tags, decodes entities, and trims")
    func plainTextStripsAndDecodes() {
        #expect(HTMLText.plainText(fromHTML: "<p>Hello <b>world</b></p>") == "Hello world")
        #expect(HTMLText.plainText(fromHTML: "Tom &amp; Jerry") == "Tom & Jerry")
        #expect(HTMLText.plainText(fromHTML: "  <div>trimmed</div>  ") == "trimmed")
        #expect(HTMLText.plainText(fromHTML: "") == "")
    }

    // MARK: - Markdown display text

    @Test("plainText(fromMarkdown:) renders inline links as visible labels")
    func markdownPlainTextRendersLinksAsLabels() {
        #expect(
            HTMLText.plainText(
                fromMarkdown: "follow [@MastodonEngineering](https://mastodon.social/@MastodonEngineering)"
            ) == "follow @MastodonEngineering"
        )
        #expect(HTMLText.plainText(fromMarkdown: "[#swift](https://mastodon.social/tags/swift)") == "#swift")
    }

    @Test("plainText(fromMarkdown:) strips inline styling and restores escaped punctuation")
    func markdownPlainTextStripsStyling() {
        #expect(HTMLText.plainText(fromMarkdown: #"This \[\*is\*] \`a\` \*\*test\*\*"#) == "This [*is*] `a` **test**")
        #expect(HTMLText.plainText(fromMarkdown: "This is **bold**, _em_, `code`, and ~~gone~~") == "This is bold, em, code, and gone")
    }

    @Test("plainText(fromMarkdown:) preserves autolinks and decodes entities")
    func markdownPlainTextAutolinksAndEntities() {
        #expect(HTMLText.plainText(fromMarkdown: "Read <https://swift.org> &amp; share") == "Read https://swift.org & share")
        #expect(HTMLText.plainText(fromMarkdown: "mail <hello@example.com>") == "mail hello@example.com")
    }

    // MARK: - paragraphs

    @Test("paragraphs splits on block boundaries and drops empties")
    func paragraphsSplitsBlocks() {
        #expect(HTMLText.paragraphs(fromHTML: "<p>One.</p><p>Two.</p>") == ["One.", "Two."])
    }

    @Test("paragraphs collapses tag-free text to a single paragraph")
    func paragraphsSingle() {
        #expect(HTMLText.paragraphs(fromHTML: "Just text") == ["Just text"])
    }

    @Test("paragraphs returns empty for empty input")
    func paragraphsEmpty() {
        #expect(HTMLText.paragraphs(fromHTML: "").isEmpty)
    }

    @Test("paragraphs breaks on <br> and decodes entities per block")
    func paragraphsBreaksAndDecodes() {
        #expect(HTMLText.paragraphs(fromHTML: "Line A<br>Tom &amp; Jerry") == ["Line A", "Tom & Jerry"])
    }

    // MARK: - snippet

    @Test("snippet collapses whitespace runs to single spaces")
    func snippetCollapses() {
        #expect(HTMLText.snippet(fromPlainText: "Hello   world\n\nthere") == "Hello world there")
    }

    @Test("snippet under the limit is returned unchanged")
    func snippetUnderLimit() {
        #expect(HTMLText.snippet(fromPlainText: "short body", limit: 160) == "short body")
    }

    @Test("snippet over the limit is truncated with a bounded ellipsis")
    func snippetTruncates() {
        let long = HTMLText.snippet(fromPlainText: String(repeating: "a ", count: 200), limit: 10)
        #expect(long.hasSuffix("…"))
        #expect(long.count <= 12)
    }
}
