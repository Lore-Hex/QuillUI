// UIFont extras
// =============
// The Apple Dynamic Type / font-descriptor surface that Signal-iOS's SignalUI
// compiles against (UIFont+OWS.swift, UIFont+TextStyle.swift, UIKit+Image.swift):
// UIFont.TextStyle + preferredFont, UIFontMetrics scaling, UIFontDescriptor
// attribute/trait keys, and the UILabel.font accessor layered over QuillUIKit's
// storage slot. Extensions only — the UIFont/UIFontDescriptor/UIFontMetrics
// class declarations stay in UIKit.swift.
//
// MODEL HONESTY: there is no font engine on Linux. Text styles map to UIKit's
// default (.large category) point sizes, UIFontMetrics scaling is identity
// (clamping at maximumPointSize still applies), and descriptor attributes
// round-trip the font name while traits stay inert.

import Foundation
import QuillFoundation
import QuillUIKit

#if !os(iOS)

#if canImport(AppKit) && !os(Linux)
import AppKit
// macOS: UIFont is a typealias for NSFont, which already carries the real
// preferredFont/descriptor/metrics surface — adding it here would collide
// with AppKit. Only the UILabel.font accessor below applies.
#else

// MARK: - UIFont.TextStyle + Dynamic Type entry points (Linux)

extension UIFont {
    /// Mirror of UIKit's UIFont.TextStyle. Raw values match the platform
    /// constants so persisted/compared values stay stable. Hashable: SignalUI
    /// keys its max-point-size clamp table by text style.
    public struct TextStyle: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let largeTitle = TextStyle(rawValue: "UICTFontTextStyleTitle0")
        public static let title1 = TextStyle(rawValue: "UICTFontTextStyleTitle1")
        public static let title2 = TextStyle(rawValue: "UICTFontTextStyleTitle2")
        public static let title3 = TextStyle(rawValue: "UICTFontTextStyleTitle3")
        public static let headline = TextStyle(rawValue: "UICTFontTextStyleHeadline")
        public static let subheadline = TextStyle(rawValue: "UICTFontTextStyleSubhead")
        public static let body = TextStyle(rawValue: "UICTFontTextStyleBody")
        public static let callout = TextStyle(rawValue: "UICTFontTextStyleCallout")
        public static let footnote = TextStyle(rawValue: "UICTFontTextStyleFootnote")
        public static let caption1 = TextStyle(rawValue: "UICTFontTextStyleCaption1")
        public static let caption2 = TextStyle(rawValue: "UICTFontTextStyleCaption2")
    }

    /// The system font for a text style at UIKit's default (.large) content
    /// size category — there is no Dynamic Type setting to scale by on Linux.
    public static func preferredFont(forTextStyle style: TextStyle) -> UIFont {
        switch style {
        case .largeTitle: return .systemFont(ofSize: 34)
        case .title1: return .systemFont(ofSize: 28)
        case .title2: return .systemFont(ofSize: 22)
        case .title3: return .systemFont(ofSize: 20)
        case .headline: return .systemFont(ofSize: 17, weight: .semibold)
        case .callout: return .systemFont(ofSize: 16)
        case .subheadline: return .systemFont(ofSize: 15)
        case .footnote: return .systemFont(ofSize: 13)
        case .caption1: return .systemFont(ofSize: 12)
        case .caption2: return .systemFont(ofSize: 11)
        default: return .systemFont(ofSize: 17) // .body and unknown styles
        }
    }

    /// Trait-compatible variant. The trait collection's content size category
    /// is ignored — every category yields the default sizes above.
    public static func preferredFont(forTextStyle style: TextStyle, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        _ = traitCollection
        return preferredFont(forTextStyle: style)
    }

    /// Monospaced-digit system font. Inert digit-spacing on Linux: same shim
    /// font as systemFont (no glyph substitution to make).
    public static func monospacedDigitSystemFont(ofSize fontSize: CGFloat, weight: Weight) -> UIFont {
        systemFont(ofSize: fontSize, weight: weight)
    }

    // Approximate vertical metrics (no glyph tables on Linux). System-font
    // ratios chosen so ascender - descender == lineHeight (1.2 × pointSize,
    // see UIFont.lineHeight in UIKit.swift) and matching RSFont's values.
    public var ascender: CGFloat { pointSize * 0.95 }
    public var descender: CGFloat { -pointSize * 0.25 }
}

// MARK: - UIFontDescriptor attribute/trait keys (Linux)

extension UIFontDescriptor {
    /// Mirror of UIKit's UIFontDescriptor.AttributeName (raw values match the
    /// platform constants). Only `.name` is consumed on Linux; the rest are
    /// accepted and dropped (no font substitution to drive).
    public struct AttributeName: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let name = AttributeName(rawValue: "NSFontNameAttribute")
        public static let family = AttributeName(rawValue: "NSFontFamilyAttribute")
        public static let face = AttributeName(rawValue: "NSFontFaceAttribute")
        public static let size = AttributeName(rawValue: "NSFontSizeAttribute")
        public static let traits = AttributeName(rawValue: "NSCTFontTraitsAttribute")
        public static let cascadeList = AttributeName(rawValue: "NSCTFontCascadeListAttribute")
        public static let textStyle = AttributeName(rawValue: "NSCTFontUIUsageAttribute")
    }

    /// Mirror of UIKit's UIFontDescriptor.TraitKey — keys inside the `.traits`
    /// attribute dictionary (SignalUI's medium()/semibold()/bold() helpers).
    public struct TraitKey: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }

        public static let symbolic = TraitKey(rawValue: "NSCTFontSymbolicTrait")
        public static let weight = TraitKey(rawValue: "NSCTFontWeightTrait")
        public static let width = TraitKey(rawValue: "NSCTFontProportionTrait")
        public static let slant = TraitKey(rawValue: "NSCTFontSlantTrait")
    }

    /// UIFontDescriptor(fontAttributes:) — honors `.name`; other attributes
    /// (cascade lists, trait dictionaries) are inert on Linux.
    public convenience init(fontAttributes: [AttributeName: Any] = [:]) {
        self.init(name: fontAttributes[.name] as? String ?? ".AppleSystemUIFont")
    }

    /// Returns a descriptor with `attributes` layered on. `.name` replaces the
    /// font name; symbolic traits already on this descriptor are preserved.
    public func addingAttributes(_ attributes: [AttributeName: Any] = [:]) -> UIFontDescriptor {
        UIFontDescriptor(
            name: attributes[.name] as? String ?? name,
            symbolicTraits: symbolicTraits
        )
    }

    /// The descriptor behind UIFont.preferredFont(forTextStyle:) — the system
    /// font descriptor; the style's point size is applied when a UIFont is made.
    public static func preferredFontDescriptor(withTextStyle style: UIFont.TextStyle) -> UIFontDescriptor {
        let font = UIFont.preferredFont(forTextStyle: style)
        let descriptor = UIFontDescriptor()
        descriptor.pointSize = font.pointSize
        return descriptor
    }
}

extension UIFontDescriptor.SymbolicTraits {
    /// Stylistic-class trait (bits 28–31 hold the class; 3 = modern serifs),
    /// matching the platform constant. SignalUI's story-text serif cascade
    /// requests it; inert here like the other traits.
    public static let classModernSerifs = UIFontDescriptor.SymbolicTraits(rawValue: 3 << 28)
}

// MARK: - UIFontMetrics scaling (Linux)

extension UIFontMetrics {
    /// Style-specific metrics. The style is irrelevant on Linux — all metrics
    /// are identity — so this delegates to the default instance's behavior.
    public convenience init(forTextStyle textStyle: UIFont.TextStyle) {
        _ = textStyle
        self.init()
    }

    /// Identity: no Dynamic Type setting exists to scale toward.
    public func scaledFont(for font: UIFont) -> UIFont { font }

    public func scaledFont(for font: UIFont, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        _ = traitCollection
        return font
    }

    /// Identity scaling, but the cap still applies — SignalUI's "clamped"
    /// dynamic-type fonts rely on maximumPointSize being honored.
    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat) -> UIFont {
        font.pointSize > maximumPointSize ? font.withSize(maximumPointSize) : font
    }

    public func scaledFont(for font: UIFont, maximumPointSize: CGFloat, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        _ = traitCollection
        return scaledFont(for: font, maximumPointSize: maximumPointSize)
    }
}

#endif // Linux UIFont surface

// MARK: - UILabel.font (all non-iOS platforms)

extension UILabel {
    /// UILabel.font, layered over QuillUIKit's `quillFontStorage` slot — the
    /// UIFont type is declared in this module (or is NSFont on macOS), which
    /// depends on QuillUIKit, so the class body can't hold the typed property.
    /// Implicitly unwrapped like UIKit's; reads never return nil (a nil store
    /// falls back to UIKit's default label font, the 17pt system font).
    public var font: UIFont! {
        get { (quillFontStorage as? UIFont) ?? UIFont.systemFont(ofSize: 17) }
        set {
            quillFontStorage = newValue
            quillFontPointSize = newValue?.pointSize ?? 17
            invalidateIntrinsicContentSize()
            quillNotifyTextMutation(true)
        }
    }
}

#endif // !os(iOS)
