import Foundation

/// Paints a macOS-style disclosure triangle (`NSButton` disclosure indicator)
/// into a `PaintContext`.
///
/// The collapsed state draws a right-pointing chevron. The expanded state
/// rotates the same measured glyph into a down-pointing chevron.
public struct MacDisclosureTrianglePaint: PaintControl {
    public var isExpanded: Bool

    public init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let color = Self.glyphColor(for: state)
        let lineWidth = MacMetrics.DisclosureTriangle.lineWidth

        if isExpanded {
            let glyphFrame = Self.expandedGlyphFrame(in: frame)
            let left = PaintPoint(x: glyphFrame.minX, y: glyphFrame.minY)
            let mid = PaintPoint(x: glyphFrame.midX, y: glyphFrame.maxY)
            let right = PaintPoint(x: glyphFrame.maxX, y: glyphFrame.minY)

            context.strokeLine(from: left, to: mid, color: color, lineWidth: lineWidth)
            context.strokeLine(from: mid, to: right, color: color, lineWidth: lineWidth)
        } else {
            let glyphFrame = Self.collapsedGlyphFrame(in: frame)
            let top = PaintPoint(x: glyphFrame.minX, y: glyphFrame.minY)
            let mid = PaintPoint(x: glyphFrame.maxX, y: glyphFrame.midY)
            let bottom = PaintPoint(x: glyphFrame.minX, y: glyphFrame.maxY)

            context.strokeLine(from: top, to: mid, color: color, lineWidth: lineWidth)
            context.strokeLine(from: mid, to: bottom, color: color, lineWidth: lineWidth)
        }
    }

    static func collapsedGlyphFrame(in frame: PaintRect) -> PaintRect {
        let width = MacMetrics.DisclosureTriangle.collapsedGlyphWidth
        let height = MacMetrics.DisclosureTriangle.collapsedGlyphHeight
        return PaintRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func expandedGlyphFrame(in frame: PaintRect) -> PaintRect {
        let width = MacMetrics.DisclosureTriangle.collapsedGlyphHeight
        let height = MacMetrics.DisclosureTriangle.collapsedGlyphWidth
        return PaintRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func glyphColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.disabledDisclosureTriangle
        }
        return MacColors.disclosureTriangle
    }
}
