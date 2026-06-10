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

    /// Convert already-sanitized inline Markdown into the visible text Apple
    /// `AttributedString(markdown:)` exposes through its character view.
    ///
    /// This is intentionally a display-text pass, not a CommonMark renderer:
    /// links keep their visible label, formatting markers disappear, autolinks
    /// keep their address, entities decode, and escaped punctuation is restored.
    public static func plainText(fromMarkdown markdown: String) -> String {
        var result = ""
        var index = markdown.startIndex

        while index < markdown.endIndex {
            if let replacement = markdownLinkReplacement(in: markdown, at: index) {
                result += plainText(fromMarkdown: replacement.label)
                index = replacement.endIndex
                continue
            }

            if markdown[index] == "<",
               let closing = markdown[markdown.index(after: index)...].firstIndex(of: ">") {
                let content = String(markdown[markdown.index(after: index)..<closing])
                if isAutolinkContent(content) {
                    result += content
                    index = markdown.index(after: closing)
                    continue
                }
            }

            if markdown[index] == "\\" {
                let next = markdown.index(after: index)
                if next < markdown.endIndex, isEscapableMarkdownPunctuation(markdown[next]) {
                    result.append(markdown[next])
                    index = markdown.index(after: next)
                    continue
                }
            }

            if hasPrefix("**", in: markdown, at: index)
                || hasPrefix("__", in: markdown, at: index)
                || hasPrefix("~~", in: markdown, at: index) {
                index = markdown.index(index, offsetBy: 2)
                continue
            }

            if markdown[index] == "*" || markdown[index] == "_" || markdown[index] == "`" {
                index = markdown.index(after: index)
                continue
            }

            result.append(markdown[index])
            index = markdown.index(after: index)
        }

        return HTMLEntities.decode(result)
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

    private static func markdownLinkReplacement(
        in text: String,
        at index: String.Index
    ) -> (label: String, endIndex: String.Index)? {
        var labelStart = index
        if text[labelStart] == "!" {
            labelStart = text.index(after: labelStart)
            guard labelStart < text.endIndex else { return nil }
        }

        guard text[labelStart] == "[" else { return nil }
        let labelContentStart = text.index(after: labelStart)
        guard let labelEnd = closingBracket(in: text, from: labelContentStart) else { return nil }

        let destinationStartMarker = text.index(after: labelEnd)
        guard destinationStartMarker < text.endIndex,
              text[destinationStartMarker] == "(" else {
            return nil
        }

        let destinationStart = text.index(after: destinationStartMarker)
        guard let destinationEnd = closingParenthesis(in: text, from: destinationStart) else {
            return nil
        }

        return (
            String(text[labelContentStart..<labelEnd]),
            text.index(after: destinationEnd)
        )
    }

    private static func closingBracket(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "]" {
                return index
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func closingParenthesis(in text: String, from start: String.Index) -> String.Index? {
        var index = start
        var depth = 0
        var escaped = false

        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 {
                    return index
                }
                depth -= 1
            }
            index = text.index(after: index)
        }

        return nil
    }

    private static func isAutolinkContent(_ text: String) -> Bool {
        guard !text.isEmpty,
              !text.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else {
            return false
        }

        if let colon = text.firstIndex(of: ":") {
            let scheme = text[..<colon]
            return (2...32).contains(scheme.count)
                && scheme.first?.isLetter == true
                && scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }
                && text.index(after: colon) < text.endIndex
        }

        if let at = text.firstIndex(of: "@") {
            let local = text[..<at]
            let domain = text[text.index(after: at)...]
            return !local.isEmpty && domain.contains(".") && !domain.isEmpty
        }

        return false
    }

    private static func hasPrefix(_ prefix: String, in text: String, at index: String.Index) -> Bool {
        guard let end = text.index(index, offsetBy: prefix.count, limitedBy: text.endIndex) else {
            return false
        }
        return text[index..<end] == prefix[...]
    }

    private static func isEscapableMarkdownPunctuation(_ character: Character) -> Bool {
        switch character {
        case "!", "#", "(", ")", "*", "+", "-", ".", "<", ">", "[", "\\", "]", "_", "`", "{", "|", "}", "~":
            return true
        default:
            return false
        }
    }
}
