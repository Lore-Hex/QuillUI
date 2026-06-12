// BonMot -- Linux shim for compiling Signal-iOS SignalUI against QuillUI (QuillOS).
// Symbols are added on demand as the SignalUI compile reports missing API.
// API shapes mirror upstream BonMot (Rightpoint/BonMot): StringStyle + Part,
// Composable (String/NSAttributedString), styled(with:), composed(of:),
// XMLStyleRule. Only the surface SignalUI exercises is declared:
//   StringStyle([.font(...), .color(...)])        OWSTableViewController2
//   "...".styled(with: .color(...)/.font(...))    ProfileDetailLabel
//   .styled(with: .font, .color, .alignment)      FingerprintViewController
//   .styled(with: .link(URL))                     FingerprintViewController & co.
//   .styled(with: .font, .xmlRules([.style(...)]))ConnectionsEducationSheet
//   StringStyle(.xmlRules([.style(tag, StringStyle(.extraAttributes(...)))]))
//   snippet.styled(with: matchStyle)              FullTextSearcher
//   NSAttributedString.composed(of: [...])        ProfileDetailLabel & co.
import Foundation
import UIKit

// MARK: - StringStyle

/// BonMot's attribute-dictionary alias (upstream: `[NSAttributedString.Key: Any]`).
public typealias StyleAttributes = [NSAttributedString.Key: Any]

/// Subset of upstream BonMot's `StringStyle`: a declarative bag of text
/// attributes. Only the properties SignalUI's parts demand are stored;
/// further upstream slots (tracking, adaptive styles, ...) are added when
/// the compile demands them.
public struct StringStyle {
    public var extraAttributes: StyleAttributes = [:]
    public var font: UIFont?
    public var link: URL?
    public var color: UIColor?
    public var alignment: NSTextAlignment?
    /// XML rules captured from `.xmlRules`. Upstream stores an `XMLStyler`
    /// protocol value; the shim keeps the rule array directly — only the
    /// rule-array shape is demanded so far.
    var xmlRules: [XMLStyleRule] = []

    public init() {}

    /// The attribute dictionary this style resolves to (upstream `attributes`,
    /// minus the adaptive/embedded-transform machinery, which has no Dynamic
    /// Type engine to talk to on Linux).
    public var attributes: StyleAttributes {
        var theAttributes = extraAttributes
        if let font { theAttributes[.font] = font }
        if let link { theAttributes[.link] = link }
        if let color { theAttributes[.foregroundColor] = color }
        if let alignment {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = alignment
            theAttributes[.paragraphStyle] = paragraphStyle
        }
        return theAttributes
    }
}

extension StringStyle {

    /// Upstream BonMot's `StringStyle.Part` — one declarative styling command.
    /// Cases are added as SignalUI demands them.
    public enum Part {
        case extraAttributes(StyleAttributes)
        case font(UIFont)
        case link(URL)
        case color(UIColor)
        case alignment(NSTextAlignment)
        case xmlRules([XMLStyleRule])
    }

    public init(_ parts: Part...) {
        self.init(parts)
    }

    public init(_ parts: [Part]) {
        self.init()
        for part in parts {
            update(part: part)
        }
    }

    /// Mutate the style with one part (upstream shape).
    public mutating func update(part: Part) {
        switch part {
        case let .extraAttributes(attributes):
            extraAttributes.merge(attributes) { _, new in new }
        case let .font(font):
            self.font = font
        case let .link(link):
            self.link = link
        case let .color(color):
            self.color = color
        case let .alignment(alignment):
            self.alignment = alignment
        case let .xmlRules(rules):
            xmlRules.append(contentsOf: rules)
        }
    }

    /// A copy of this style updated with `parts` (upstream shape).
    public func byAdding(_ parts: Part...) -> StringStyle {
        byAdding(stringStyle: StringStyle(parts))
    }

    /// A copy of this style overridden by every non-nil slot of `style`
    /// (upstream merge semantics: the added style wins).
    public func byAdding(stringStyle style: StringStyle) -> StringStyle {
        var result = self
        result.extraAttributes.merge(style.extraAttributes) { _, new in new }
        if let font = style.font { result.font = font }
        if let link = style.link { result.link = link }
        if let color = style.color { result.color = color }
        if let alignment = style.alignment { result.alignment = alignment }
        result.xmlRules.append(contentsOf: style.xmlRules)
        return result
    }

    /// Style a plain string, applying XML rules when present (upstream
    /// `attributedString(from:)`, kept internal until the compile demands it).
    func attributedString(from theString: String) -> NSAttributedString {
        if xmlRules.isEmpty {
            return NSAttributedString(string: theString, attributes: attributes)
        }
        return applyingFlatXMLRules(to: theString)
    }

    /// MODEL HONESTY: upstream BonMot feeds the string through a real
    /// XMLParser (nesting, attributes, enter/exit rules, full entity
    /// handling). This shim is a flat scanner: it styles non-nested
    /// `<tag>...</tag>` spans whose tag has a `.style` rule, strips other
    /// tag markers, and decodes only the five predefined XML entities.
    /// That covers SignalUI's uses (FTS `<match>` snippets, `<bold>` spans
    /// in explainer copy); nested or attributed markup would style wrong.
    private func applyingFlatXMLRules(to string: String) -> NSAttributedString {
        let baseAttributes = attributes
        var styleForTag: [String: StyleAttributes] = [:]
        for case let .style(tag, style) in xmlRules {
            styleForTag[tag] = byAdding(stringStyle: style).attributes
        }

        let result = NSMutableAttributedString()
        var rest = string[...]
        func appendText<S: StringProtocol>(_ text: S, _ attributes: StyleAttributes) {
            guard !text.isEmpty else { return }
            result.append(NSAttributedString(string: decodingXMLEntities(text), attributes: attributes))
        }
        while let lt = rest.firstIndex(of: "<") {
            appendText(rest[..<lt], baseAttributes)
            guard let gt = rest[lt...].firstIndex(of: ">") else {
                // Dangling "<": keep it literally, like text.
                appendText(rest[lt...], baseAttributes)
                rest = rest[rest.endIndex...]
                break
            }
            let tag = String(rest[rest.index(after: lt)..<gt])
            let afterOpen = rest.index(after: gt)
            if let tagAttributes = styleForTag[tag],
               let close = rest.range(of: "</\(tag)>", range: afterOpen..<rest.endIndex) {
                appendText(rest[afterOpen..<close.lowerBound], tagAttributes)
                rest = rest[close.upperBound...]
            } else {
                // Unknown tag (or unmatched open): strip the marker, keep
                // scanning — mirrors the XML parse, which drops markup.
                rest = rest[afterOpen...]
            }
        }
        appendText(rest, baseAttributes)
        return result
    }

    private func decodingXMLEntities<S: StringProtocol>(_ text: S) -> String {
        var out = String(text)
        guard out.contains("&") else { return out }
        // "&amp;" last, so "&amp;lt;" decodes to the literal "&lt;".
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        return out
    }
}

// MARK: - XMLStyleRule

/// Upstream BonMot's XML styling rule. Only `.style` is demanded; `.enter` /
/// `.exit` are added when the compile asks for them.
public enum XMLStyleRule {
    case style(String, StringStyle)
}

// MARK: - Composable

/// Upstream BonMot's composition protocol. `composed(of:)` takes a
/// heterogeneous `[Composable]` (SignalUI mixes Strings and
/// NSAttributedStrings), so this is a real protocol, not ad-hoc extensions.
public protocol Composable {
    func append(to attributedString: NSMutableAttributedString, baseStyle: StringStyle, isLastElement: Bool)
}

public extension Composable {

    func append(to attributedString: NSMutableAttributedString, baseStyle: StringStyle) {
        append(to: attributedString, baseStyle: baseStyle, isLastElement: false)
    }

    /// Style the receiver with `style`, updated with any `overrideParts`.
    func styled(with style: StringStyle, _ overrideParts: StringStyle.Part...) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        let newStyle = style.byAdding(stringStyle: StringStyle(overrideParts))
        append(to: attributedString, baseStyle: newStyle)
        return attributedString
    }

    /// Style the receiver with the passed-in parts.
    func styled(with parts: StringStyle.Part...) -> NSAttributedString {
        styled(with: StringStyle(parts))
    }
}

extension String: Composable {
    public func append(to attributedString: NSMutableAttributedString, baseStyle: StringStyle, isLastElement: Bool) {
        attributedString.append(baseStyle.attributedString(from: self))
    }
}

extension NSAttributedString: Composable {
    /// Upstream semantics: the appended string keeps its own run attributes;
    /// `baseStyle` only supplies defaults underneath them. (This is what lets
    /// SignalUI compose a gray "(secondaryName)" span and then apply a font
    /// to the whole string without losing the gray.)
    public func append(to attributedString: NSMutableAttributedString, baseStyle: StringStyle, isLastElement: Bool) {
        attributedString.quillBonMotExtend(with: self, baseStyle: baseStyle)
    }
}

public extension NSAttributedString {
    /// Upstream BonMot's `composed(of:baseStyle:separator:)`.
    static func composed(of composables: [Composable], baseStyle: StringStyle = StringStyle(), separator: Composable? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, composable) in composables.enumerated() {
            composable.append(to: result, baseStyle: baseStyle, isLastElement: index == composables.count - 1)
            if let separator, index != composables.count - 1 {
                separator.append(to: result, baseStyle: baseStyle)
            }
        }
        return result
    }
}

private extension NSMutableAttributedString {
    /// Append `attributedString`, then lay `baseStyle`'s attributes UNDER the
    /// appended runs (existing run attributes win — upstream BonMot's merge).
    func quillBonMotExtend(with attributedString: NSAttributedString, baseStyle: StringStyle) {
        let location = length
        append(attributedString)
        let appendedRange = NSRange(location: location, length: attributedString.length)
        let baseAttributes = baseStyle.attributes
        guard appendedRange.length > 0, !baseAttributes.isEmpty else { return }
        // Snapshot runs first; setAttributes inside enumerateAttributes would
        // mutate under the enumeration.
        var runs: [(NSRange, StyleAttributes)] = []
        enumerateAttributes(in: appendedRange, options: []) { existing, range, _ in
            runs.append((range, existing))
        }
        for (range, existing) in runs {
            var merged = baseAttributes
            merged.merge(existing) { _, run in run }
            setAttributes(merged, range: range)
        }
    }
}

// MARK: - Composable conveniences

// BonMot's Composable surface: upstream provides `attributedString()` via the
// Composable extension. Signal-iOS calls it on NSTextStorage
// (ImageEditorCanvasView, BodyRangesTextView) in files that do NOT import
// BonMot — that resolves upstream (and here) via Swift's
// pre-MemberImportVisibility member lookup, which sees extension members from
// any module loaded by the target (other SignalUI files import BonMot).
// Declared concretely (not on Composable) so that lookup stays robust.
public extension NSAttributedString {
    /// Returns a styled copy. Copying preserves BonMot's snapshot semantics,
    /// which matter when the receiver is a mutable NSTextStorage.
    func attributedString() -> NSAttributedString {
        NSAttributedString(attributedString: self)
    }
}

public extension String {
    /// BonMot Composable: a String composes to an unstyled attributed string.
    func attributedString() -> NSAttributedString {
        NSAttributedString(string: self)
    }
}
