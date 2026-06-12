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

    /// Create a grayscale color. Mirrors SwiftUI's `Color(white:opacity:)`.
    public init(white: Double, opacity: Double = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }

    /// Bridge UIKit/AppKit-style platform colors into the SwiftUI color value.
    ///
    /// `@_disfavoredOverload`: generated SwiftUI apps see this module (via the
    /// SwiftUI shim) AND QuillUI, so implicit-member calls like `Color(.label)`
    /// or `Color(.systemBlue)` have two viable routes — this RSColor bridge
    /// (UIColor/NSColor statics re-exported through QuillShims) and QuillUI's
    /// `Color.init(_: QuillPlatformColor)` — and fail as ambiguous. The
    /// QuillPlatformColor route is the established surface for generated code,
    /// so this bridge yields. Explicit RSColor arguments (telegram-mac graph)
    /// and RSColor-only members (e.g. `Color(.secondaryLabel)`) still resolve
    /// here: a disfavored overload is used whenever it is the only viable one.
    @_disfavoredOverload
    public init(_ color: RSColor) {
        self.init(red: color._red, green: color._green, blue: color._blue, opacity: color._alpha)
    }

    /// SwiftUI's explicit RGB color-space initializer.
    public init(_ colorSpace: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1.0) {
        _ = colorSpace
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}
