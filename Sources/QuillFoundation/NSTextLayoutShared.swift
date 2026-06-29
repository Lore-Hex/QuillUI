import Foundation

// Shared text-layout value types + attributed-string keys. On Apple platforms
// these names exist in BOTH UIKit (iOS) and AppKit (macOS) — and on Catalyst
// they converge to single declarations. QuillOS offers UIKit and AppKit
// side-by-side on Linux, so the single canonical declarations live HERE in
// QuillFoundation, which both the UIKit shim and QuillAppKit (module AppKit)
// `@_exported import`. Files importing UIKit, AppKit, SwiftUI (which
// re-exports AppKit), or any combination resolve ONE declaration — declaring
// these in both UI modules made every use ambiguous the moment a file could
// see both worlds (e.g. SwiftUI + UIKit imports in Signal-iOS sources).
//
// NSTextAttachment also lives in QuillFoundation now that the Linux image
// aliases converge on RSImage. NSTextStorage intentionally stays per-flavor in
// the UI modules because editing/storage APIs still diverge.

public enum NSTextAlignment: Int, Sendable {
    case left, right, center, justified, natural
}

public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

public enum NSWritingDirection: Int, Sendable {
    case natural = -1, leftToRight = 0, rightToLeft = 1
}

open class NSParagraphStyle: NSObject, @unchecked Sendable {
    public static let `default` = NSParagraphStyle()

    public override init() {}
    public var alignment: NSTextAlignment = .natural
    public var lineHeightMultiple: CGFloat = 0
    public var lineSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var paragraphSpacingBefore: CGFloat = 0
    public var firstLineHeadIndent: CGFloat = 0
    public var headIndent: CGFloat = 0
    public var tailIndent: CGFloat = 0
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var minimumLineHeight: CGFloat = 0
    public var maximumLineHeight: CGFloat = 0
    public var baseWritingDirection: NSWritingDirection = .natural
    public var defaultTabInterval: CGFloat = 0
    public var tabStops: [Any] = []

    /// Inert on Linux: returns .natural (no per-language BiDi resolution yet).
    /// SSK's String.naturalTextAlignment switches over the result.
    public class func defaultWritingDirection(forLanguage language: String?) -> NSWritingDirection {
        return .natural
    }
}

open class NSMutableParagraphStyle: NSParagraphStyle, @unchecked Sendable {}

/// Mirror of UIKit/AppKit's NSUnderlineStyle. Modeled as an OptionSet
/// (matching the platform, where line styles and patterns combine) with the
/// standard raw values; SSK uses `.single.rawValue` for strikethrough and
/// underline attributes.
public struct NSUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 0x01)
    public static let thick = NSUnderlineStyle(rawValue: 0x02)
    public static let double = NSUnderlineStyle(rawValue: 0x09)
    public static let patternSolid: NSUnderlineStyle = []
    public static let patternDot = NSUnderlineStyle(rawValue: 0x0100)
    public static let patternDash = NSUnderlineStyle(rawValue: 0x0200)
    public static let patternDashDot = NSUnderlineStyle(rawValue: 0x0300)
    public static let patternDashDotDot = NSUnderlineStyle(rawValue: 0x0400)
    public static let byWord = NSUnderlineStyle(rawValue: 0x8000)
}

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1 << 0)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 1 << 1)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 1 << 3)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 1 << 5)
}

public final class NSStringDrawingContext {
    public init() {}
    public var minimumScaleFactor: CGFloat = 0
    public var actualScaleFactor: CGFloat = 1
    public var totalBounds: CGRect = .zero
}

// Standard attributed-string attribute keys (UIKit/AppKit additions; not in
// swift-corelibs Foundation). Raw values match Apple's. Union of the two
// previously-duplicated copies.
public extension NSAttributedString.Key {
    static let font = NSAttributedString.Key(rawValue: "NSFont")
    static let foregroundColor = NSAttributedString.Key(rawValue: "NSColor")
    static let backgroundColor = NSAttributedString.Key(rawValue: "NSBackgroundColor")
    static let paragraphStyle = NSAttributedString.Key(rawValue: "NSParagraphStyle")
    static let underlineStyle = NSAttributedString.Key(rawValue: "NSUnderline")
    static let underlineColor = NSAttributedString.Key(rawValue: "NSUnderlineColor")
    static let strikethroughStyle = NSAttributedString.Key(rawValue: "NSStrikethrough")
    static let strikethroughColor = NSAttributedString.Key(rawValue: "NSStrikethroughColor")
    static let strokeColor = NSAttributedString.Key(rawValue: "NSStrokeColor")
    static let strokeWidth = NSAttributedString.Key(rawValue: "NSStrokeWidth")
    static let link = NSAttributedString.Key(rawValue: "NSLink")
    static let attachment = NSAttributedString.Key(rawValue: "NSAttachment")
    static let kern = NSAttributedString.Key(rawValue: "NSKern")
    static let baselineOffset = NSAttributedString.Key(rawValue: "NSBaselineOffset")
    static let writingDirection = NSAttributedString.Key(rawValue: "NSWritingDirection")
    static let selectionBackgroundColor = NSAttributedString.Key(rawValue: "NSSelectionBackgroundColor")
}
