import Foundation

#if canImport(CoreText)
import CoreText
#endif

/// Renderer-agnostic font token used by `PaintContext.drawText`.
///
/// `family` names the preferred family. `size` is in paint units / points,
/// and `weight` follows the CSS/OpenType numeric scale from 100 through 900.
public struct PaintFont: Equatable, Hashable, Sendable {
    public var family: String
    public var size: Double
    public var weight: Int

    public init(family: String, size: Double, weight: Int) {
        self.family = family
        self.size = size
        self.weight = weight
    }
}

/// macOS font tokens used by QuillPaint controls.
public enum MacFonts {
    public static let controlLabel = PaintFont(
        family: MacFontResolution.preferredMacTextFamily,
        size: 13,
        weight: 400
    )

    public static let controlLabelEmphasized = PaintFont(
        family: MacFontResolution.preferredMacTextFamily,
        size: 13,
        weight: 600
    )

    public static let titlebarTitle = PaintFont(
        family: MacFontResolution.preferredMacTextFamily,
        size: 13,
        weight: 400
    )
}

/// Resolves macOS typography tokens to a locally available family.
public enum MacFontResolution {
    public static let preferredMacTextFamily = "SF Pro Text"
    public static let interFallbackFamily = "Inter"
    public static let helveticaFallbackFamily = "Helvetica Neue"
    public static let systemDefaultFamily = ".system"

    public static let preferredFamilies = [
        preferredMacTextFamily,
        interFallbackFamily,
        helveticaFallbackFamily
    ]

    /// Resolve a Mac font token to the best available local family.
    public static func resolve(_ font: PaintFont) -> PaintFont {
        resolve(font, availableFamilies: installedFontFamilies())
    }

    /// Resolve a Mac font token against an explicit family set. This overload
    /// keeps fallback behavior deterministic in tests.
    public static func resolve(_ font: PaintFont, availableFamilies: Set<String>) -> PaintFont {
        guard shouldResolve(family: font.family) else {
            return font
        }

        var resolved = font
        resolved.family = resolvedFamily(availableFamilies: availableFamilies)
        return resolved
    }

    public static func resolvedFamily() -> String {
        resolvedFamily(availableFamilies: installedFontFamilies())
    }

    public static func resolvedFamily(availableFamilies: Set<String>) -> String {
        for family in preferredFamilies {
            if containsFamily(family, in: availableFamilies) {
                return family
            }
        }
        return systemDefaultFamily
    }

    public static func installedFontFamilies() -> Set<String> {
        #if canImport(CoreText)
        let names = CTFontManagerCopyAvailableFontFamilyNames() as NSArray
        return Set(names.compactMap { $0 as? String })
        #elseif os(Linux)
        // Inter is QuillPaint's expected SF Pro substitute on Linux. Without
        // a platform font enumerator in this target, emit the preferred Linux
        // family and let the backend's text stack fall through if unavailable.
        return [interFallbackFamily]
        #else
        return []
        #endif
    }

    private static func shouldResolve(family: String) -> Bool {
        family.isEmpty
            || family == systemDefaultFamily
            || preferredMacTextFamily.caseInsensitiveCompare(family) == .orderedSame
    }

    private static func containsFamily(_ family: String, in availableFamilies: Set<String>) -> Bool {
        availableFamilies.contains { $0.caseInsensitiveCompare(family) == .orderedSame }
    }
}

/// Minimal text measurement helper for controls that need alignment before
/// dispatching a draw call to the active backend.
public enum PaintTextMetrics {
    public static func measure(_ string: String, font: PaintFont) -> PaintSize {
        guard !string.isEmpty else {
            return PaintSize(width: 0, height: lineHeight(for: font))
        }

        #if canImport(CoreText)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: coreTextFont(from: font)]
            )
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return PaintSize(
            width: ceil(width),
            height: ceil(Double(ascent + descent + leading))
        )
        #else
        return PaintSize(
            width: ceil(Double(string.count) * font.size * 0.52),
            height: lineHeight(for: font)
        )
        #endif
    }

    public static func lineHeight(for font: PaintFont) -> Double {
        #if canImport(CoreText)
        let ctFont = coreTextFont(from: font)
        return ceil(Double(CTFontGetAscent(ctFont) + CTFontGetDescent(ctFont) + CTFontGetLeading(ctFont)))
        #else
        return ceil(font.size * 1.2)
        #endif
    }
}

#if canImport(CoreText)
private func coreTextFont(from font: PaintFont) -> CTFont {
    let resolved = MacFontResolution.resolve(font)
    let traits: [String: Any] = [
        kCTFontWeightTrait as String: coreTextWeight(from: resolved.weight)
    ]
    var attributes: [String: Any] = [
        kCTFontTraitsAttribute as String: traits
    ]
    if resolved.family != MacFontResolution.systemDefaultFamily {
        attributes[kCTFontFamilyNameAttribute as String] = resolved.family
    }

    let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, CGFloat(resolved.size), nil)
}

private func coreTextWeight(from weight: Int) -> CGFloat {
    switch max(100, min(900, weight)) {
    case 100: return -0.80
    case 200: return -0.60
    case 300: return -0.40
    case 400: return 0.00
    case 500: return 0.23
    case 600: return 0.30
    case 700: return 0.40
    case 800: return 0.56
    default: return 0.62
    }
}
#endif
