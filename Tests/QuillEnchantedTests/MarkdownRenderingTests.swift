import Testing
@testable import QuillEnchantedCore

@Suite("Markdown rendering fallback")
struct MarkdownRenderingTests {
    @Test("combines paragraph lines and removes lightweight inline markers")
    func parsesParagraphs() {
        let blocks = MarkdownParser.parse("This is **bold** text\nwith `inline` code.")

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "This is bold text with inline code.")
        ])
    }

    @Test("keeps blank parser output empty")
    func keepsBlankParserOutputEmpty() {
        #expect(MarkdownParser.parse("").isEmpty)
        #expect(MarkdownParser.parse(" \n\t ").isEmpty)
    }

    @Test("parses headings and list items")
    func parsesStructuralBlocks() {
        let blocks = MarkdownParser.parse("""
        ## Plan ##
        - Build the shim
        2. Verify Linux
        3) Match macOS
        > Keep it native
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .heading(level: 2), text: "Plan"),
            MarkdownBlock(id: 1, kind: .unorderedListItem, text: "Build the shim"),
            MarkdownBlock(id: 2, kind: .orderedListItem(number: 2), text: "Verify Linux"),
            MarkdownBlock(id: 3, kind: .orderedListItem(number: 3), text: "Match macOS"),
            MarkdownBlock(id: 4, kind: .quote, text: "Keep it native")
        ])
    }

    @Test("trims valid closing ATX heading markers")
    func trimsClosingATXHeadingMarkers() {
        let blocks = MarkdownParser.parse("""
        # Heading #
        ### C# guide ###
        ## Heading##
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .heading(level: 1), text: "Heading"),
            MarkdownBlock(id: 1, kind: .heading(level: 3), text: "C# guide"),
            MarkdownBlock(id: 2, kind: .heading(level: 2), text: "Heading##")
        ])
    }

    @Test("parses setext headings")
    func parsesSetextHeadings() {
        let blocks = MarkdownParser.parse("""
        Overview
        ========

        A **bold**
        heading
        ---
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .heading(level: 1), text: "Overview"),
            MarkdownBlock(id: 1, kind: .heading(level: 2), text: "A bold heading")
        ])
    }

    @Test("parses thematic breaks")
    func parsesThematicBreaks() {
        let blocks = MarkdownParser.parse("""
        Before

        ---

        * * *

        _ _ _

        After
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "Before"),
            MarkdownBlock(id: 1, kind: .divider, text: ""),
            MarkdownBlock(id: 2, kind: .divider, text: ""),
            MarkdownBlock(id: 3, kind: .divider, text: ""),
            MarkdownBlock(id: 4, kind: .paragraph, text: "After")
        ])
    }

    @Test("keeps malformed markers as paragraph text")
    func keepsMalformedMarkersAsParagraphText() {
        let blocks = MarkdownParser.parse("""
        #Heading
        -Item
        1.Item
        2)Item
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "#Heading -Item 1.Item 2)Item")
        ])
    }

    @Test("keeps empty unordered list markers as paragraph text")
    func keepsEmptyUnorderedListMarkersAsParagraphText() {
        let markdown = """
        -
        Follow-up

        *
        Follow-up

        +
        Follow-up
        """ + "\n\n-   \nFollow-up"

        let blocks = MarkdownParser.parse(markdown)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "- Follow-up"),
            MarkdownBlock(id: 1, kind: .paragraph, text: "* Follow-up"),
            MarkdownBlock(id: 2, kind: .paragraph, text: "+ Follow-up"),
            MarkdownBlock(id: 3, kind: .paragraph, text: "- Follow-up")
        ])
    }

    @Test("keeps empty quote markers as paragraph text")
    func keepsEmptyQuoteMarkersAsParagraphText() {
        let blocks = MarkdownParser.parse("""
        >
        Follow-up
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "> Follow-up")
        ])
    }

    @Test("normalizes block quote marker spacing")
    func normalizesBlockQuoteMarkerSpacing() {
        let blocks = MarkdownParser.parse("""
        >Quoted
        >   Spaced quote
        > **Bold**
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .quote, text: "Quoted"),
            MarkdownBlock(id: 1, kind: .quote, text: "Spaced quote"),
            MarkdownBlock(id: 2, kind: .quote, text: "Bold")
        ])
    }

    @Test("preserves fenced code with language labels")
    func parsesCodeFences() {
        let blocks = MarkdownParser.parse("""
        ```swift
        let app = EnchantedApp()

        app.run()
        ```
        """)

        #expect(blocks == [
            MarkdownBlock(
                id: 0,
                kind: .codeBlock(language: "swift"),
                text: "let app = EnchantedApp()\n\napp.run()"
            )
        ])
    }

    @Test("matches code fences by marker length")
    func matchesCodeFencesByMarkerLength() {
        let blocks = MarkdownParser.parse("""
        ````swift
        ```swift
        let value = 1
        ```
        ````
        """)

        #expect(blocks == [
            MarkdownBlock(
                id: 0,
                kind: .codeBlock(language: "swift"),
                text: "```swift\nlet value = 1\n```"
            )
        ])
    }

    @Test("keeps tilde and backtick fences independent")
    func keepsTildeAndBacktickFencesIndependent() {
        let blocks = MarkdownParser.parse("""
        ~~~~text
        ```
        body
        ```
        ~~~~
        """)

        #expect(blocks == [
            MarkdownBlock(
                id: 0,
                kind: .codeBlock(language: "text"),
                text: "```\nbody\n```"
            )
        ])
    }

    @Test("drops block HTML comments outside code fences")
    func dropsBlockHTMLComments() {
        let blocks = MarkdownParser.parse("""
        Visible
        <!--
        hidden **markdown**
        -->
        Still visible

        <!-- inline comment block -->
        After
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "Visible"),
            MarkdownBlock(id: 1, kind: .paragraph, text: "Still visible"),
            MarkdownBlock(id: 2, kind: .paragraph, text: "After")
        ])
    }

    @Test("preserves HTML comments inside fenced code")
    func preservesHTMLCommentsInsideFencedCode() {
        let blocks = MarkdownParser.parse("""
        ```html
        <!-- visible in code -->
        <p>Visible</p>
        ```
        """)

        #expect(blocks == [
            MarkdownBlock(
                id: 0,
                kind: .codeBlock(language: "html"),
                text: "<!-- visible in code -->\n<p>Visible</p>"
            )
        ])
    }

    @Test("drops link reference definitions outside code fences")
    func dropsLinkReferenceDefinitions() {
        let blocks = MarkdownParser.parse("""
        Intro
        [docs]: https://example.com "Docs"
        [image]: <file:///tmp/image.png>
        Still visible
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "Intro"),
            MarkdownBlock(id: 1, kind: .paragraph, text: "Still visible")
        ])
    }

    @Test("preserves link reference definitions inside fenced code")
    func preservesLinkReferenceDefinitionsInsideFencedCode() {
        let blocks = MarkdownParser.parse("""
        ```markdown
        [docs]: https://example.com
        ```
        """)

        #expect(blocks == [
            MarkdownBlock(
                id: 0,
                kind: .codeBlock(language: "markdown"),
                text: "[docs]: https://example.com"
            )
        ])
    }

    @Test("keeps escaped link reference definitions visible")
    func keepsEscapedLinkReferenceDefinitionsVisible() {
        let blocks = MarkdownParser.parse("\\[docs]: https://example.com")

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .paragraph, text: "[docs]: https://example.com")
        ])
    }

    @Test("renders markdown links as readable plain text")
    func cleansLinks() {
        #expect(MarkdownParser.cleanInline("[QuillUI](https://example.com) works") == "QuillUI (https://example.com) works")
        #expect(MarkdownParser.cleanInline("![Preview](file:///tmp/preview.png)") == "Preview")
        #expect(MarkdownParser.cleanInline("Status [](/health)") == "Status (/health)")
        #expect(MarkdownParser.cleanInline("Drop ![](file:///tmp/chart.png)") == "Drop")
        #expect(MarkdownParser.cleanInline("[Swift Array](https://developer.apple.com/documentation/swift/Array(_:))") == "Swift Array (https://developer.apple.com/documentation/swift/Array(_:))")
        #expect(MarkdownParser.cleanInline("![Chart](assets/chart(size).png)") == "Chart")
        #expect(MarkdownParser.cleanInline("Preview ![Architecture Diagram](assets/architecture.png) done") == "Preview Architecture Diagram done")
        #expect(MarkdownParser.cleanInline("\\![Preview](file:///tmp/preview.png)") == "![Preview](file:///tmp/preview.png)")
        #expect(MarkdownParser.cleanInline("Open <https://example.com/docs?q=1>") == "Open https://example.com/docs?q=1")
        #expect(MarkdownParser.cleanInline("Email <support@example.com>") == "Email support@example.com")
        #expect(MarkdownParser.cleanInline("Keep 2 < 3 > 1") == "Keep 2 < 3 > 1")
        #expect(MarkdownParser.cleanInline("Visible <!-- hidden --> text") == "Visible  text")
        #expect(MarkdownParser.cleanInline("Press <kbd>Esc</kbd> now") == "Press Esc now")
        #expect(MarkdownParser.cleanInline("Line<br>break") == "Line break")
        #expect(MarkdownParser.cleanInline("Open <https://example.com> and <kbd>Esc</kbd>") == "Open https://example.com and Esc")
        #expect(MarkdownParser.cleanInline("Keep <model> literal") == "Keep <model> literal")
        #expect(MarkdownParser.cleanInline("Show \\<kbd\\>Esc\\</kbd\\>") == "Show <kbd>Esc</kbd>")
        #expect(MarkdownParser.cleanInline("Use &lt;model&gt; &amp; tools") == "Use <model> & tools")
        #expect(MarkdownParser.cleanInline("It&rsquo;s ready &mdash; ship it &#x2713;") == "It\u{2019}s ready \u{2014} ship it \u{2713}")
        #expect(MarkdownParser.cleanInline("Keep &unknown; literal") == "Keep &unknown; literal")
        #expect(MarkdownParser.cleanInline("Use *local* and _remote_ models") == "Use local and remote models")
        #expect(MarkdownParser.cleanInline("Use **local** and __remote__ models") == "Use local and remote models")
        #expect(MarkdownParser.cleanInline("Try `swift` code and ~~old~~ text") == "Try swift code and old text")
        #expect(MarkdownParser.cleanInline("Keep a literal * marker") == "Keep a literal * marker")
        #expect(MarkdownParser.cleanInline("Keep a literal ** marker") == "Keep a literal ** marker")
        #expect(MarkdownParser.cleanInline("Keep a literal ` marker") == "Keep a literal ` marker")
        #expect(MarkdownParser.cleanInline("Keep a literal ~~ marker") == "Keep a literal ~~ marker")
        #expect(MarkdownParser.cleanInline("Show \\*literal\\* and \\[label\\]") == "Show *literal* and [label]")
        #expect(MarkdownParser.cleanInline("\\# Not a heading") == "# Not a heading")
        #expect(MarkdownParser.cleanInline("\\[Not a link](https://example.com)") == "[Not a link](https://example.com)")
        #expect(MarkdownParser.cleanInline("Keep \\path and value\\9") == "Keep \\path and value\\9")
    }
}
