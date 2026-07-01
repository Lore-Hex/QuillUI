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

extension Font {
    /// Nominal point size for each preset text style; matches the sizes the
    /// backends render (see the GTK CSS table for FontModifiedView).
    var presetPointSize: Double {
        switch self {
        case .largeTitle: return 28
        case .title: return 24
        case .title2: return 20
        case .title3: return 18
        case .headline: return 14
        case .subheadline: return 12
        case .body: return 14
        case .callout: return 12
        case .footnote: return 10
        case .caption: return 12
        case .caption2: return 10
        case .custom(let size, _, _): return size
        }
    }

    private func withDesign(_ design: FontDesign) -> Font {
        switch self {
        case .custom(let size, let weight, _):
            return .custom(size: size, weight: weight, design: design)
        default:
            return .custom(size: presetPointSize, weight: .regular, design: design)
        }
    }

    /// Returns this font with the monospaced design (SwiftUI parity:
    /// `Font.body.monospaced()`).
    public func monospaced() -> Font {
        withDesign(.monospaced)
    }
}
