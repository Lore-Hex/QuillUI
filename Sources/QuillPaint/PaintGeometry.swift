import Foundation

/// 2D point in paint coordinates (origin top-left, Y grows downward — the
/// same convention as Cairo, Skia, and Quartz with the standard transform).
public struct PaintPoint: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = PaintPoint(x: 0, y: 0)
}

/// 2D size in paint coordinates.
public struct PaintSize: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = PaintSize(width: 0, height: 0)
}

/// Axis-aligned rectangle in paint coordinates.
public struct PaintRect: Equatable, Hashable, Sendable {
    public var origin: PaintPoint
    public var size: PaintSize

    public init(origin: PaintPoint, size: PaintSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: PaintPoint(x: x, y: y), size: PaintSize(width: width, height: height))
    }

    public var minX: Double { origin.x }
    public var minY: Double { origin.y }
    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
    public var midX: Double { origin.x + size.width / 2 }
    public var midY: Double { origin.y + size.height / 2 }

    /// Returns a rect inset by `dx` horizontally and `dy` vertically.
    public func insetBy(dx: Double, dy: Double) -> PaintRect {
        PaintRect(x: origin.x + dx, y: origin.y + dy,
                  width: max(0, size.width - 2 * dx),
                  height: max(0, size.height - 2 * dy))
    }

    public static let zero = PaintRect(origin: .zero, size: .zero)
}

/// RGBA color with components in `[0, 1]`. Cairo/Skia/Quartz all consume
/// this shape directly so no per-backend conversion is needed at draw time.
public struct PaintColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Construct from 0-255 byte components.
    public init(r: Int, g: Int, b: Int, a: Int = 255) {
        self.init(red: Double(r) / 255,
                  green: Double(g) / 255,
                  blue: Double(b) / 255,
                  alpha: Double(a) / 255)
    }

    public static let clear = PaintColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = PaintColor(red: 1, green: 1, blue: 1)
    public static let black = PaintColor(red: 0, green: 0, blue: 0)

    /// Returns a copy of this color with the provided alpha.
    public func withAlpha(_ alpha: Double) -> PaintColor {
        PaintColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }
}

/// Line cap styles for stroking operations.
public enum PaintLineCap: Equatable, Hashable, Sendable {
    /// Square end that stops exactly at the terminal point.
    case butt
    /// Semicircular end with a radius of half the line width.
    case round
    /// Square end that extends past the terminal point by half the line width.
    case square
}
