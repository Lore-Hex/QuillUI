/// Font weight for custom fonts.
public enum FontWeight: Equatable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black
}

/// Font design (typeface family).
public enum FontDesign: Equatable {
    case `default`
    case monospaced
    case rounded
    case serif
}

/// Font presets matching SwiftUI's font system.
public enum Font: Equatable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case footnote
    case caption
    case caption2
    /// Custom font with explicit size in points, optional weight and design.
    case custom(size: Double, weight: FontWeight, design: FontDesign)

    /// Create a system font with explicit size, weight, and design.
    public static func system(
        size: Double,
        weight: FontWeight = .regular,
        design: FontDesign = .default
    ) -> Font {
        .custom(size: size, weight: weight, design: design)
    }
}

// SwiftUI nests these on `Font` (`Font.Weight` / `Font.Design` / `Font.TextStyle`);
// upstream source references them that way. Map to the top-level enums.
extension Font {
    public typealias Weight = FontWeight
    public typealias Design = FontDesign
    public typealias TextStyle = Font
}

// SwiftUI `Font.custom(_:size:relativeTo:)` / `Font.custom(_:size:)` (DesignSystem
// chosen-font). SwiftOpenUI has no custom-font-name plumbing yet; approximate with
// the system font at that size (name/relativeTo accepted for source compatibility).
extension Font {
    public static func custom(_ name: String, size: Double, relativeTo textStyle: Font.TextStyle) -> Font {
        .custom(size: size, weight: .regular, design: .default)
    }
    public static func custom(_ name: String, size: Double) -> Font {
        .custom(size: size, weight: .regular, design: .default)
    }
}
