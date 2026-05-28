import Foundation

/// Renderer-agnostic drawing surface.
///
/// The protocol intentionally only exposes the primitives the QuillPaint
/// control library needs to render macOS-style chrome and labels — filled and
/// stroked rounded rectangles, line segments, and text runs. The narrow
/// surface keeps backend implementations
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

    /// Draw a single text run with `point` as the top-left typographic bounds
    /// origin in paint coordinates.
    func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor)
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
        case drawText(string: String, point: PaintPoint, font: PaintFont, color: PaintColor)
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
        calls.append(.drawText(string: string, point: point, font: font, color: color))
    }
}
