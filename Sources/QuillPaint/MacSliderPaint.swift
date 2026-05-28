import Foundation

/// Paints a macOS-style `NSSlider` into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring around the knob
///   2. slider track fill
///   3. circular knob fill
///   4. circular knob border
///
public struct MacSliderPaint: PaintControl {
    public enum Orientation: Equatable, Hashable, Sendable {
        case vertical
        case horizontal
    }

    public var orientation: Orientation
    public var progress: Double

    public init(orientation: Orientation = .horizontal, progress: Double = 0.5) {
        self.orientation = orientation
        self.progress = progress
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let knobDiameter = MacMetrics.Slider.knobDiameter
        let knobRadius = knobDiameter / 2
        let trackThickness = MacMetrics.Slider.trackThickness
        let clampedProgress = progress.clamped(to: 0...1)

        let trackRect: PaintRect
        let knobCenter: PaintPoint

        switch orientation {
        case .horizontal:
            let availableWidth = frame.size.width - knobDiameter
            let x = frame.minX + knobRadius + availableWidth * clampedProgress
            let y = frame.midY
            knobCenter = PaintPoint(x: x, y: y)

            trackRect = PaintRect(
                x: frame.minX + knobRadius,
                y: frame.midY - trackThickness / 2,
                width: max(0, frame.size.width - knobDiameter),
                height: trackThickness
            )

        case .vertical:
            let availableHeight = frame.size.height - knobDiameter
            let x = frame.midX
            // In vertical sliders, 0 is bottom, 1 is top?
            // Usually in GUI, Y grows down. So 1 (top) is minY + knobRadius.
            let y = frame.maxY - knobRadius - availableHeight * clampedProgress
            knobCenter = PaintPoint(x: x, y: y)

            trackRect = PaintRect(
                x: frame.midX - trackThickness / 2,
                y: frame.minY + knobRadius,
                width: trackThickness,
                height: max(0, frame.size.height - knobDiameter)
            )
        }

        // 1. Track
        context.fillRoundedRect(
            trackRect,
            cornerRadius: MacMetrics.Slider.trackCornerRadius,
            color: Self.trackColor(for: state)
        )

        // 2. Focus Ring (around knob)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.Slider.focusRingOutset
            let ringFrame = PaintRect(
                x: knobCenter.x - knobRadius - outset,
                y: knobCenter.y - knobRadius - outset,
                width: knobDiameter + 2 * outset,
                height: knobDiameter + 2 * outset
            )
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: (knobDiameter + 2 * outset) / 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // 3. Knob
        let knobRect = PaintRect(
            x: knobCenter.x - knobRadius,
            y: knobCenter.y - knobRadius,
            width: knobDiameter,
            height: knobDiameter
        )

        context.fillRoundedRect(
            knobRect,
            cornerRadius: knobRadius,
            color: Self.knobFillColor(for: state)
        )

        context.strokeRoundedRect(
            knobRect,
            cornerRadius: knobRadius,
            color: Self.knobBorderColor(for: state),
            lineWidth: MacMetrics.Slider.knobBorderLineWidth
        )
    }

    private static func trackColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.sliderTrack.withAlpha(MacColors.sliderTrack.alpha * 0.5)
        }
        return MacColors.sliderTrack
    }

    private static func knobFillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            // macOS disabled knobs are slightly translucent white
            return MacColors.sliderKnobFill.withAlpha(0.8)
        }
        return MacColors.sliderKnobFill
    }

    private static func knobBorderColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.sliderKnobBorder.withAlpha(MacColors.sliderKnobBorder.alpha * 0.5)
        }
        return MacColors.sliderKnobBorder
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension PaintColor {
    func withAlpha(_ alpha: Double) -> PaintColor {
        PaintColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }
}
