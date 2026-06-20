import Foundation

#if os(Linux)
// NSAttributedString document-conversion surface (HTML / RTF import).
// ====================================================================
// Apple's UIKit/AppKit layer adds the `init(data:options:documentAttributes:)`
// family plus the `DocumentType` / `DocumentReadingOptionKey` /
// `DocumentAttributeKey` nested key types to NSAttributedString. swift-corelibs
// Foundation on Linux ships none of them, so LinkPreview's HTMLMetadata (which
// imports HTML link-preview titles via `NSAttributedString(data:options:
// documentAttributes:)` with `.documentType: .html`) fails to compile.
//
// MODEL HONESTY: there is no rich HTML layout engine on Linux. The HTML import
// decodes the markup to its visible text (tags stripped, entities decoded via
// HTMLText) and returns it as a plain-attributes attributed string. That is
// exactly what HTMLMetadata needs (it reads `.string` for the title), without
// pretending to reconstruct fonts/colors from CSS.

public extension NSAttributedString {

    /// Mirrors Apple's `NSAttributedString.DocumentType` (the value passed as
    /// `options[.documentType]`). Raw values match Apple's documented strings.
    struct DocumentType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let plain = DocumentType(rawValue: "NSPlain")
        public static let rtf = DocumentType(rawValue: "NSRTF")
        public static let rtfd = DocumentType(rawValue: "NSRTFD")
        public static let html = DocumentType(rawValue: "NSHTML")
    }

    /// Mirrors Apple's `NSAttributedString.DocumentReadingOptionKey` (the keys
    /// of the `options:` dictionary). Raw values match Apple's.
    struct DocumentReadingOptionKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let documentType = DocumentReadingOptionKey(rawValue: "DocumentType")
        public static let characterEncoding = DocumentReadingOptionKey(rawValue: "CharacterEncoding")
        public static let defaultAttributes = DocumentReadingOptionKey(rawValue: "DefaultAttributes")
    }

    /// Mirrors Apple's `NSAttributedString.DocumentAttributeKey` (the keys of
    /// the `documentAttributes` output dictionary).
    struct DocumentAttributeKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let documentType = DocumentAttributeKey(rawValue: "DocumentType")
        public static let characterEncoding = DocumentAttributeKey(rawValue: "CharacterEncoding")
    }

    /// Apple's data-importing initializer. On Linux only the HTML (and plain)
    /// document types are interpreted, both reduced to visible text; the
    /// `documentAttributes` out-pointer is left untouched (no metadata is
    /// produced). Honors `.characterEncoding` when supplied (defaults to UTF-8).
    convenience init(
        data: Data,
        options: [DocumentReadingOptionKey: Any] = [:],
        // Apple types this `AutoreleasingUnsafeMutablePointer<NSDictionary?>?`, an
        // ObjC-interop pointer that doesn't exist on Linux. The out-attributes are
        // never produced here anyway, so a plain UnsafeMutablePointer matches the
        // call shape (callers pass `nil`) without the ObjC-only type.
        documentAttributes dict: UnsafeMutablePointer<NSDictionary?>? = nil
    ) throws {
        _ = dict
        let encoding: String.Encoding
        if let raw = options[.characterEncoding] as? UInt {
            encoding = String.Encoding(rawValue: raw)
        } else {
            encoding = .utf8
        }
        let source = String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""

        let documentType = options[.documentType] as? DocumentType ?? .plain
        let text: String
        switch documentType {
        case .html:
            text = HTMLText.plainText(fromHTML: source)
        default:
            text = source
        }
        self.init(string: text)
    }
}
#endif
