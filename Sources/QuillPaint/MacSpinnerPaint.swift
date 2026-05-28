import Foundation

/// Paints a macOS-style indeterminate radial spinner (`NSProgressIndicator`).
///
/// Indeterminate radial spinner: 12 spokes at varying opacity.
public struct MacSpinnerPaint: PaintControl {
    public init() {}

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let center = PaintPoint(x: frame.midX, y: frame.midY)
        let spokeCount = MacMetrics.Spinner.spokeCount
        let innerRadius = MacMetrics.Spinner.innerRadius
        let outerRadius = innerRadius + MacMetrics.Spinner.spokeLength
        let lineWidth = MacMetrics.Spinner.spokeWidth
        
        let baseColor = MacColors.spinnerSpoke
        // macOS 14 Sonoma spinner opacities for the 12 spokes.
        // Spoke 0 is the "head" (brightest), and trailing spokes fade out.
        let opacities: [Double] = [
            1.00, 0.85, 0.70, 0.55, 0.40, 0.25,
            0.10, 0.10, 0.10, 0.10, 0.10, 0.10
        ]

        for i in 0..<spokeCount {
            // macOS spinner spokes start from the top (12 o'clock) and
            // the highlight moves clockwise.
            // Spoke 0 is at 12 o'clock, Spoke 1 is at 1 o'clock, etc.
            let angle = -Double.pi / 2 + (Double(i) * 2 * Double.pi / Double(spokeCount))
            
            let start = PaintPoint(
                x: center.x + cos(angle) * innerRadius,
                y: center.y + sin(angle) * innerRadius
            )
            let end = PaintPoint(
                x: center.x + cos(angle) * outerRadius,
                y: center.y + sin(angle) * outerRadius
            )
            
            var opacity = opacities[i]
            if state.isDisabled {
                opacity *= 0.5
            }
            
            context.strokeLine(
                from: start,
                to: end,
                color: baseColor.withAlpha(opacity),
                lineWidth: lineWidth,
                lineCap: .round
            )
        }
    }
}
