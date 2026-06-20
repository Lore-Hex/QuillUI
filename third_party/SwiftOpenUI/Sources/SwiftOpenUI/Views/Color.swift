import Foundation

/// A color value for use with `.foregroundColor()`, `.background()`, `.border()`.
///
/// Supports hex strings, RGB/RGBA components, fractional components,
/// and an `.opacity()` modifier.
public struct Color: Equatable, Sendable {
    public typealias Body = Never

    /// Red component (0.0–1.0).
    public let red: Double
    /// Green component (0.0–1.0).
    public let green: Double
    /// Blue component (0.0–1.0).
    public let blue: Double
    /// Alpha component (0.0–1.0).
    public let alpha: Double

    public var body: Never { fatalError("Color is a primitive view") }

    /// Create a color from fractional RGBA components (0.0–1.0).
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        self.red = Self.clamp01(red)
        self.green = Self.clamp01(green)
        self.blue = Self.clamp01(blue)
        self.alpha = Self.clamp01(opacity)
    }

    /// Create a color from integer RGB components (0–255).
    ///
    /// SwiftUI's `Color(red:green:blue:)` is fractional. Keeping 8-bit
    /// components on distinct labels avoids hijacking real SwiftUI source
    /// such as `Color(red: 187 / 255, green: 59 / 255, blue: 226 / 255)`.
    public init(red8: Int, green8: Int, blue8: Int, alpha8: Int = 255) {
        self.red = Double(Self.clamp255(red8)) / 255.0
        self.green = Double(Self.clamp255(green8)) / 255.0
        self.blue = Double(Self.clamp255(blue8)) / 255.0
        self.alpha = Double(Self.clamp255(alpha8)) / 255.0
    }

    /// Create a color from a hex string (e.g., "#FF0000" or "#FF000080").
    public init(hex: String) {
        let hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(hex, radix: 16) ?? 0

        if hex.count == 8 {
            self.red = Double((value >> 24) & 0xFF) / 255.0
            self.green = Double((value >> 16) & 0xFF) / 255.0
            self.blue = Double((value >> 8) & 0xFF) / 255.0
            self.alpha = Double(value & 0xFF) / 255.0
        } else {
            self.red = Double((value >> 16) & 0xFF) / 255.0
            self.green = Double((value >> 8) & 0xFF) / 255.0
            self.blue = Double(value & 0xFF) / 255.0
            self.alpha = 1.0
        }
    }

    /// Create a color from HSB (hue 0–360, saturation 0.0–1.0, brightness 0.0–1.0).
    public init(hue: Double, saturation: Double, brightness: Double, opacity: Double = 1.0) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        let s = Self.clamp01(saturation)
        let b = Self.clamp01(brightness)

        let c = b * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c

        let r1, g1, b1: Double
        switch h {
        case 0..<60:    (r1, g1, b1) = (c, x, 0)
        case 60..<120:  (r1, g1, b1) = (x, c, 0)
        case 120..<180: (r1, g1, b1) = (0, c, x)
        case 180..<240: (r1, g1, b1) = (0, x, c)
        case 240..<300: (r1, g1, b1) = (x, 0, c)
        default:        (r1, g1, b1) = (c, 0, x)
        }

        self.red = Self.clamp01(r1 + m)
        self.green = Self.clamp01(g1 + m)
        self.blue = Self.clamp01(b1 + m)
        self.alpha = Self.clamp01(opacity)
    }

    /// Return a new color with the given opacity (0.0–1.0).
    public func opacity(_ value: Double) -> Color {
        Color(red: red, green: green, blue: blue, opacity: value)
    }

    // MARK: - Named colors

    public static let red = Color(red: 1.0, green: 0.0, blue: 0.0)
    public static let green = Color(red: 0.0, green: 0.667, blue: 0.0)
    public static let blue = Color(red: 0.0, green: 0.0, blue: 1.0)
    public static let orange = Color(red: 1.0, green: 0.533, blue: 0.0)
    public static let purple = Color(red: 0.533, green: 0.0, blue: 0.533)
    public static let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    public static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)
    public static let gray = Color(red: 0.533, green: 0.533, blue: 0.533)
    public static let white = Color(red: 1.0, green: 1.0, blue: 1.0)
    public static let black = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let clear = Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.0)
    public static let pink = Color(red: 1.0, green: 0.176, blue: 0.333)
    public static let brown = Color(red: 0.635, green: 0.518, blue: 0.369)
    public static let mint = Color(red: 0.0, green: 0.780, blue: 0.745)
    public static let teal = Color(red: 0.188, green: 0.690, blue: 0.780)
    public static let indigo = Color(red: 0.345, green: 0.337, blue: 0.839)

    /// Process-wide scheme for semantic colors. QuillOS sets
    /// QUILLUI_COLOR_SCHEME=dark for apps whose macOS appearance is dark
    /// (video/imaging tools like SolderScope); defaults to light, matching
    /// the historical hardcoded values.
    public static let quillPrefersDarkScheme: Bool =
        ProcessInfo.processInfo.environment["QUILLUI_COLOR_SCHEME"]?.lowercased() == "dark"

    public static var primary: Color {
        quillPrefersDarkScheme ? Color(red: 1.0, green: 1.0, blue: 1.0) : .black
    }
    public static var secondary: Color {
        quillPrefersDarkScheme ? Color(red: 0.682, green: 0.682, blue: 0.698) : .gray
    }

    // MARK: - Helpers

    /// Hex string representation (e.g., "#FF0000").
    public var hex: String {
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        if alpha < 1.0 {
            let a = Int(alpha * 255)
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func clamp255(_ v: Int) -> Int { min(max(v, 0), 255) }
}

// View conformance lives in an extension (Apple declares it the same
// way for primitive value views): protocol-isolation inference applies
// only to conformances declared on the type itself, so statics like
// Color.accentColor stay nonisolated and remain usable as default
// argument values in nonisolated app code (IceCubes ToastCenter).
extension Color: View, PrimitiveView {}
