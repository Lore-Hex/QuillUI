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
    ///
    /// Coverage: the seven baseline (lt/gt/amp/quot/apos/nbsp +
    /// numeric apos variants) plus the typographical entities
    /// real-world RSS feeds publish in abundance — em / en
    /// dashes, smart quotes, ellipses, copyright family.
    /// Without these, the timeline preview shows literal
    /// "&hellip;" instead of "…".
    private static let replacements: [(String, String)] = [
        ("&nbsp;", " "),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&apos;", "'"),
        ("&#39;", "'"),
        ("&#x27;", "'"),
        // Typography — most common in real feeds.
        ("&hellip;", "\u{2026}"),
        ("&mdash;", "\u{2014}"),
        ("&ndash;", "\u{2013}"),
        ("&ldquo;", "\u{201C}"),
        ("&rdquo;", "\u{201D}"),
        ("&lsquo;", "\u{2018}"),
        ("&rsquo;", "\u{2019}"),
        ("&laquo;", "\u{00AB}"),
        ("&raquo;", "\u{00BB}"),
        // Symbols.
        ("&copy;", "\u{00A9}"),
        ("&reg;", "\u{00AE}"),
        ("&trade;", "\u{2122}"),
        ("&deg;", "\u{00B0}"),
        ("&middot;", "\u{00B7}"),
        ("&bull;", "\u{2022}"),
        // amp last — double-decode guard (see header comment).
        ("&amp;", "&"),
    ]

    /// Decode the listed HTML entities in the input. Tag-stripping
    /// stays at the caller — different callers want different
    /// shapes (Mastodon's HTMLString iterates characters,
    /// NetNewsWire uses a regex pass).
    ///
    /// Two-pass:
    ///   1. Named entities (table-driven, fast).
    ///   2. Numeric entities `&#NNNN;` (decimal) and `&#xHHHH;`
    ///      (hex) via a single regex sweep. Real RSS feeds
    ///      publish typography this way too (e.g. `&#8217;` for
    ///      a right single quote when the publisher's CMS
    ///      doesn't emit `&rsquo;`).
    public static func decode(_ source: String) -> String {
        var result = source
        for (entity, replacement) in replacements {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return decodeNumericEntities(result)
    }

    /// Replace `&#NNNN;` / `&#xHHHH;` numeric entities with the
    /// corresponding Unicode scalar. Invalid sequences (overflow,
    /// surrogate halves, bad parse) are left as-is.
    private static func decodeNumericEntities(_ source: String) -> String {
        let pattern = #"&#(x[0-9A-Fa-f]+|[0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        let nsself = source as NSString
        let matches = regex.matches(
            in: source, range: NSRange(location: 0, length: nsself.length)
        )
        guard !matches.isEmpty else { return source }
        // Walk matches in reverse so earlier offsets stay valid.
        var result = source
        for m in matches.reversed() {
            let numericRange = m.range(at: 1)
            guard numericRange.location != NSNotFound else { continue }
            let numericString = nsself.substring(with: numericRange)
            let scalarValue: UInt32?
            if numericString.first == "x" || numericString.first == "X" {
                scalarValue = UInt32(numericString.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(numericString, radix: 10)
            }
            guard let value = scalarValue,
                  let scalar = Unicode.Scalar(value) else { continue }
            let replacement = String(scalar)
            let fullRange = m.range(at: 0)
            let swiftRange = Range(fullRange, in: result)!
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }
}
