import Foundation

/// Reusable HTML → display-text helpers for reader and social-timeline apps.
///
/// Content from feeds and social timelines (RSS `description` /
/// `content:encoded`, Mastodon status HTML, …) arrives as HTML fragments
/// that the UI needs as plain text or display paragraphs. A NetNewsWire-style
/// reader and a Mastodon client independently reinvented tag-stripping (see
/// the note in ``HTMLEntities/decode(_:)`` — "Mastodon's HTMLString iterates
/// characters, NetNewsWire uses a regex pass"). `HTMLText` is the shared,
/// tested implementation any such app can link instead of carrying its own.
///
/// Tag handling is intentionally lightweight — a regex pass over a small
/// block-boundary set, not a full HTML parser. It targets the well-formed
/// fragment HTML that feeds and timelines emit, and decodes entities via
/// ``HTMLEntities``. Callers that need real DOM fidelity should use a parser.
public enum HTMLText {
    /// Strip every tag and decode entities, returning a single trimmed
    /// string. Inline structure (paragraph breaks, lists) is flattened —
    /// use ``paragraphs(fromHTML:)`` when block structure should survive.
    public static func plainText(fromHTML html: String) -> String {
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return HTMLEntities.decode(withoutTags)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split an HTML body into display paragraphs. Block-level boundaries
    /// (`</p>`, `<br>`, `<div>`, `<h1>`–`<h6>`, `<li>`, `<blockquote>`, …)
    /// become paragraph breaks; remaining inline tags are stripped and
    /// entities decoded. A body with no block tags collapses to a single
    /// paragraph; empty paragraphs are dropped. This lets multi-paragraph
    /// articles render as discrete blocks instead of one run-on blob.
    public static func paragraphs(fromHTML html: String) -> [String] {
        guard !html.isEmpty else { return [] }
        // U+2029 PARAGRAPH SEPARATOR — a marker that can't collide with
        // feed prose, inserted at every block boundary.
        let marker = "\u{2029}"
        let blockBoundary =
            "</?(?:p|div|br|h[1-6]|li|ul|ol|blockquote|section|article|header|footer|figure|figcaption)(?:\\s[^>]*)?/?>"
        let withBreaks = html.replacingOccurrences(
            of: blockBoundary, with: marker,
            options: [.regularExpression, .caseInsensitive]
        )
        let stripped = withBreaks.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return stripped
            .components(separatedBy: marker)
            .map { HTMLEntities.decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Collapse whitespace runs and truncate already-plain text to a short
    /// single-line preview (e.g. a timeline snippet, ~two rendered lines).
    /// Appends an ellipsis when truncated. Pass text that has already been
    /// run through ``plainText(fromHTML:)``; tags are not stripped here.
    public static func snippet(fromPlainText body: String, limit: Int = 160) -> String {
        let collapsed = body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<end]).trimmingCharacters(in: .whitespaces) + "…"
    }
}
