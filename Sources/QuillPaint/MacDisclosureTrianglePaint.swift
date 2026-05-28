import Foundation

/// Paints a macOS-style disclosure triangle (NSButton bezel style .disclosure).
///
/// A small filled triangle that points right when collapsed and down when
/// expanded. Rotates 90 degrees on toggle.
public struct MacDisclosureTrianglePaint: PaintControl {
    public var isExpanded: Bool

    public init(isExpanded: Bool = false) {
        self.isExpanded = isExpanded
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let size = MacMetrics.DisclosureTriangle.size
        
        // Center the triangle in the provided frame.
        let triangleFrame = PaintRect(
            x: frame.midX - size / 2,
            y: frame.midY - size / 2,
            width: size,
            height: size
        )

        let points: [PaintPoint]
        if isExpanded {
            // Points down: horizontal top edge, vertex at bottom center.
            // Metrics match macOS 14 Sonoma at 1x.
            points = [
                PaintPoint(x: triangleFrame.minX + 0.5, y: triangleFrame.minY + 2),
                PaintPoint(x: triangleFrame.maxX - 0.5, y: triangleFrame.minY + 2),
                PaintPoint(x: triangleFrame.midX, y: triangleFrame.maxY - 2)
            ]
        } else {
            // Points right: vertical left edge, vertex at right center.
            // Metrics match macOS 14 Sonoma at 1x.
            points = [
                PaintPoint(x: triangleFrame.minX + 2, y: triangleFrame.minY + 0.5),
                PaintPoint(x: triangleFrame.minX + 2, y: triangleFrame.maxY - 0.5),
                PaintPoint(x: triangleFrame.maxX - 2, y: triangleFrame.midY)
            ]
        }

        let color = state.isDisabled ? MacColors.disabledControlText : MacColors.secondaryLabel
        context.fillPolygon(points, color: color)
    }
}
