import Foundation

/// Backend-agnostic helpers for serializing `PaintColor` into the textual
/// formats native widget toolkits consume for styling (CSS for GTK, style
/// sheets for Qt). The painted-control foundation draws control *chrome*
/// through `PaintContext`, but the transparent native widget that sits on
/// top (the real `GtkEntry`, `QLineEdit`, label text, …) is still styled by
/// the toolkit, and those style strings need the same colors QuillPaint uses.
///
/// Centralizing the formatting here keeps the GTK and (future) Qt hosts from
/// each re-deriving the 0–255 rounding rule, which previously drifted between
/// `quillCSSRGBA`, `quillTextFieldCSSRGBA`, and `quillToggleCSSRGBA`.
public enum PaintCSSColor {
    /// Format a `PaintColor` as a CSS `rgba(r, g, b, a)` string with integer
    /// 0–255 color channels and a `[0, 1]` alpha. Channels are clamped to
    /// their valid range before rounding so out-of-gamut colors never emit
    /// malformed CSS.
    public static func rgba(_ color: PaintColor) -> String {
        let red = channelByte(color.red)
        let green = channelByte(color.green)
        let blue = channelByte(color.blue)
        let alpha = clamp01(color.alpha)
        return "rgba(\(red), \(green), \(blue), \(alpha))"
    }

    /// Convert a `[0, 1]` channel to a clamped 0–255 integer byte using
    /// round-half-away-from-zero, matching the previous per-host formatters.
    private static func channelByte(_ value: Double) -> Int {
        Int((clamp01(value) * 255).rounded())
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
