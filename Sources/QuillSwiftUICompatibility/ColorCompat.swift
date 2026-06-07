import SwiftOpenUI

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
