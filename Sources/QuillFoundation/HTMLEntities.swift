import Foundation

/// Small shared HTML-entity decoder used by app cores that strip
/// HTML payloads from upstream feed / status content (IceCubes
/// Mastodon `HTMLString`, NetNewsWire RSS+Atom item descriptions,
/// …). Covers the entities that show up in real Mastodon / RSS
/// payloads.
///
/// Not a full HTML decoder — does not handle numeric entities
/// outside `&#39;` / `&#x27;`, named entities outside the listed
/// set, or nested decoding. Use `NSAttributedString(data:options:)`
/// on Apple platforms if you need a full pass.
public enum HTMLEntities {
    /// Ordered replacements applied in sequence. `&amp;` MUST be
    /// last so a payload like `&amp;lt;` decodes to `&lt;` (the
    /// literal) instead of `<` (the double-decoded character).
    private static let replacements: [(String, String)] = [
        ("&nbsp;", " "),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&#x27;", "'"),
        ("&amp;", "&"),
    ]

    /// Decode the listed HTML entities in the input. Tag-stripping
    /// stays at the caller — different callers want different
    /// shapes (Mastodon's HTMLString iterates characters,
    /// NetNewsWire uses a regex pass).
    public static func decode(_ source: String) -> String {
        var result = source
        for (entity, replacement) in replacements {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }
}
