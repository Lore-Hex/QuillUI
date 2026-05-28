import Foundation

/// Paints a macOS-style `NSProgressIndicator` (bar) into a `PaintContext`.
///
/// Draws in this z-order:
///   1. Progress bar track (background)
///   2. Progress fill (determinate)
///
public struct MacProgressBarPaint: PaintControl {
    /// The progress value, clamped to [0, 1].
    public var progress: Double

    public init(progress: Double = 0.0) {
        self.progress = progress
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let clampedProgress = max(0, min(1, progress))
        let cornerRadius = MacMetrics.ProgressBar.cornerRadius

        // 1. Track
        context.fillRoundedRect(
            frame,
            cornerRadius: cornerRadius,
            color: Self.trackColor(for: state)
        )

        // 2. Fill (only if progress > 0)
        if clampedProgress > 0 {
            let fillWidth = frame.size.width * clampedProgress
            let fillFrame = PaintRect(
                x: frame.minX,
                y: frame.minY,
                width: fillWidth,
                height: frame.size.height
            )

            context.fillRoundedRect(
                fillFrame,
                cornerRadius: cornerRadius,
                color: Self.fillColor(for: state)
            )
        }
    }

    private static func trackColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.progressBarTrack.withAlpha(MacColors.progressBarTrack.alpha * 0.5)
        }
        return MacColors.progressBarTrack
    }

    private static func fillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.progressBarFill.withAlpha(0.5)
        }
        return MacColors.progressBarFill
    }
}

private extension PaintColor {
    func withAlpha(_ alpha: Double) -> PaintColor {
        PaintColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }
}
