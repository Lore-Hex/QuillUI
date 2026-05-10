@_exported import QuillRS
import Foundation

// Tidemark is the upstream NetNewsWire/Ranchero Markdown-to-HTML
// helper used by RSParser. Our QuillRS-backed shim previously
// only re-exported its module surface; upstream usage now also
// calls `Tidemark.markdownToHTML(_:)`, so expose a minimal
// no-throws function with the same return shape.
//
// This is a conservative passthrough: bare Markdown gets wrapped
// in a single `<p>` block so downstream `contentHTML.isEmpty`
// checks behave correctly. Replace with a real CommonMark
// renderer once the QuillRS markdown lowering surfaces one.
public func markdownToHTML(_ markdown: String) -> String {
    let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    let escaped = trimmed
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    return "<p>\(escaped)</p>"
}
