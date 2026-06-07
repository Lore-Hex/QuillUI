import SwiftOpenUI
#if os(Linux)
import QuillFoundation
#endif

// SwiftUI `Color` conveniences used by vendored real source that SwiftOpenUI's
// `Color` doesn't yet provide: the semantic `.accentColor` and the grayscale
// `init(white:opacity:)`. Surfaced to real source through the SwiftUI shim,
// which re-exports QuillSwiftUICompatibility.
extension Color {
    /// The app's accent color. Mirrors SwiftUI's default system accent (blue).
    public static var accentColor: Color { .blue }

    /// Create a grayscale color. Mirrors SwiftUI's `Color(white:opacity:)`.
    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }
}

#if os(Linux)
// Core Image `CIColor` + `UIColor(_:Color)` + `Color(_:UIColor)` used by vendored
// DesignSystem (Resources/Colors.swift extracts RGB via CIColor(color: UIColor(color));
// Color(.label)). Linux has no Core Image / AppKit UIColor(Color); provide the
// component-reading shape. Linux-only: macOS supplies the real types.
public struct CIColor {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat
    public init?(color: UIColor) {
        guard let components = color.components, components.count >= 3 else { return nil }
        self.red = components[0]; self.green = components[1]; self.blue = components[2]
        self.alpha = components.count > 3 ? components[3] : 1
    }
}

extension Color {
    /// Build a SwiftUI `Color` from a UIColor (RSColor on Linux). DS `Color(.label)`.
    public init(_ uiColor: UIColor) {
        let c = uiColor.components ?? [0, 0, 0, 1]
        self.init(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]),
                  opacity: Double(c.count > 3 ? c[3] : 1))
    }
}

extension UIColor {
    /// Build a UIColor (RSColor on Linux) from a SwiftUI `Color`'s components.
    public convenience init(_ color: Color) {
        self.init(red: CGFloat(color.red), green: CGFloat(color.green),
                  blue: CGFloat(color.blue), alpha: CGFloat(color.alpha))
    }
}
#endif
