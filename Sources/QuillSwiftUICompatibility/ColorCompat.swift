import SwiftOpenUI
import QuillFoundation

// SwiftUI `Color` conveniences used by vendored real source that SwiftOpenUI's
// `Color` doesn't yet provide: the semantic `.accentColor` and the grayscale
// `init(white:opacity:)`. Surfaced to real source through the SwiftUI shim,
// which re-exports QuillSwiftUICompatibility.
extension Color {
    public enum RGBColorSpace: Sendable {
        case sRGB
    }

    /// The app's accent color. Mirrors SwiftUI's default system accent (blue).
    public static var accentColor: Color { .blue }
    public static var tint: Color { accentColor }
    public static var foreground: Color { primary }
    // Disfavored: IceCubes' DesignSystem ships its own `Color.label`, and
    // StatusKit imports both it and this shadow (re-exported via SwiftUI),
    // which made `Color.label` ambiguous. Ports that don't pull DesignSystem
    // still get this one; DesignSystem's wins where both are visible.
    @_disfavoredOverload
    public static var label: Color { Color(RSColor.label) }
    public static var labelCustom: Color { Color("label") }
    public static var systemGray: Color { Color(RSColor.systemGray) }
    public static var systemGray2: Color { Color(RSColor.systemGray2) }
    public static var systemBlue: Color { Color(RSColor.systemBlue) }
    public static var systemRed: Color { Color(RSColor.systemRed) }
    public static var grayCustom: Color { Color("grayCustom") }
    public static var gray2Custom: Color { Color("gray2Custom") }
    public static var gray3Custom: Color { Color("gray3Custom") }
    public static var gray4Custom: Color { Color("gray4Custom") }
    public static var gray5Custom: Color { Color("gray5Custom") }
    public static var bgCustom: Color { Color("bgCustom") }

    /// Create a grayscale color. Mirrors SwiftUI's `Color(white:opacity:)`.
    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }

    /// Bridge UIKit/AppKit-style platform colors into the SwiftUI color value.
    public init(_ color: RSColor) {
        self.init(red: color._red, green: color._green, blue: color._blue, opacity: color._alpha)
    }

    public init(rgba: UInt32) {
        self.init(
            red: Double((rgba >> 24) & 0xff) / 255.0,
            green: Double((rgba >> 16) & 0xff) / 255.0,
            blue: Double((rgba >> 8) & 0xff) / 255.0,
            opacity: Double(rgba & 0xff) / 255.0
        )
    }

    public init(light: Color, dark: Color) {
        self = light
    }

    public init(_ assetName: String) {
        self = Self.assetColor(named: assetName)
    }

    /// SwiftUI's explicit RGB color-space initializer.
    public init(_ colorSpace: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        _ = colorSpace
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }

    private static func assetColor(named name: String) -> Color {
        switch name {
        case "label":
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        case "grayCustom":
            return Color(red: 0.56, green: 0.56, blue: 0.58)
        case "gray2Custom":
            return Color(red: 0.68, green: 0.68, blue: 0.70)
        case "gray3Custom":
            return Color(red: 0.78, green: 0.78, blue: 0.80)
        case "gray4Custom":
            return Color(red: 0.86, green: 0.86, blue: 0.88)
        case "gray5Custom":
            return Color(red: 0.91, green: 0.91, blue: 0.94)
        case "bgCustom":
            return Color(red: 0.96, green: 0.96, blue: 0.97)
        default:
            return .primary
        }
    }
}
