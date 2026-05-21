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

    @Test("parses headings and list items")
    func parsesStructuralBlocks() {
        let blocks = MarkdownParser.parse("""
        ## Plan
        - Build the shim
        2. Verify Linux
        > Keep it native
        """)

        #expect(blocks == [
            MarkdownBlock(id: 0, kind: .heading(level: 2), text: "Plan"),
            MarkdownBlock(id: 1, kind: .unorderedListItem, text: "Build the shim"),
            MarkdownBlock(id: 2, kind: .orderedListItem(number: 2), text: "Verify Linux"),
            MarkdownBlock(id: 3, kind: .quote, text: "Keep it native")
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
    }
}
