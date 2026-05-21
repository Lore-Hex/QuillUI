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
        ## Plan
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

    @Test("renders markdown links as readable plain text")
    func cleansLinks() {
        #expect(MarkdownParser.cleanInline("[QuillUI](https://example.com) works") == "QuillUI (https://example.com) works")
        #expect(MarkdownParser.cleanInline("![Preview](file:///tmp/preview.png)") == "Preview (file:///tmp/preview.png)")
    }
}
