import Foundation

/// Renderer-agnostic drawing surface.
///
/// The protocol intentionally only exposes the primitives the QuillPaint
/// control library needs to render macOS-style chrome — filled and stroked
/// rounded rectangles, line segments, and (in a future iteration) text
/// runs and image blits. The narrow surface keeps backend implementations
/// (Cairo on GTK, Skia or QPainter on Qt, CoreGraphics on Apple for
/// reference snapshots) small and trivially swappable.
///
/// All coordinates are in paint units; the backend is responsible for any
/// device-pixel translation (HiDPI scaling, retina, fractional scaling).
public protocol PaintContext: AnyObject {
    /// Fill a rounded rectangle. `cornerRadius` of 0 produces a sharp-cornered
    /// fill identical to `fillRect(rect:color:)`.
    func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor)

    /// Stroke the outline of a rounded rectangle.
    func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double)

    /// Stroke a single straight line segment.
    func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double)

    /// Draw a single line of text.
    func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor)

    /// Measure the size of a string when rendered with a specific font.
    func measureText(_ string: String, font: PaintFont) -> PaintSize
}

public extension PaintContext {
    /// Convenience: fill a rectangle with sharp corners.
    func fillRect(_ rect: PaintRect, color: PaintColor) {
        fillRoundedRect(rect, cornerRadius: 0, color: color)
    }
}

// MARK: - RecordingPaintContext

/// In-memory `PaintContext` that records draw calls in order. The primary
/// use is unit testing — assertions about control rendering can compare
/// against the recorded sequence without standing up a real Cairo/Skia
/// surface.
public final class RecordingPaintContext: PaintContext {
    public enum DrawCall: Equatable {
        case fillRoundedRect(rect: PaintRect, cornerRadius: Double, color: PaintColor)
        case strokeRoundedRect(rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double)
        case strokeLine(from: PaintPoint, to: PaintPoint, color: PaintColor, lineWidth: Double)
        case drawText(string: String, at: PaintPoint, font: PaintFont, color: PaintColor)
    }

    public private(set) var calls: [DrawCall] = []

    public init() {}

    public func reset() {
        calls.removeAll(keepingCapacity: true)
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        calls.append(.fillRoundedRect(rect: rect, cornerRadius: cornerRadius, color: color))
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        calls.append(.strokeRoundedRect(rect: rect, cornerRadius: cornerRadius, color: color, lineWidth: lineWidth))
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        calls.append(.strokeLine(from: start, to: end, color: color, lineWidth: lineWidth))
    }

    public func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {
        calls.append(.drawText(string: string, at: point, font: font, color: color))
    }

    public func measureText(_ string: String, font: PaintFont) -> PaintSize {
        // Return a deterministic heuristic size for testing purposes.
        PaintSize(width: Double(string.count) * 7.0, height: font.size)
    }
}
