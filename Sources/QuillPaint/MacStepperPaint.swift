import Foundation

/// Paints a macOS-style `NSStepper` into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the capsule
///   2. stepper capsule fill (`control` light grey)
///   3. stepper capsule border and horizontal separator (subtle separator stroke)
///   4. (optional) pressed-state darkening overlay for top or bottom half
///   5. up and down chevrons
///
/// Metrics are sourced from macOS 14 Sonoma at 1x scale.
public struct MacStepperPaint: PaintControl {
    public init() {}

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let metrics = MacMetrics.Stepper.self
        
        // 1. Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.FocusRing.outset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: metrics.cornerRadius + 2, // approximation matching Button
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // 2. Capsule fill
        let fillColor = Self.chromeFillColor(for: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: metrics.cornerRadius,
            color: fillColor
        )

        // 3. Capsule border and separator
        context.strokeRoundedRect(
            frame,
            cornerRadius: metrics.cornerRadius,
            color: MacColors.separator,
            lineWidth: metrics.borderLineWidth
        )

        let separatorY = frame.minY + frame.size.height / 2
        context.strokeLine(
            from: PaintPoint(x: frame.minX, y: separatorY),
            to: PaintPoint(x: frame.maxX, y: separatorY),
            color: MacColors.separator,
            lineWidth: metrics.borderLineWidth
        )

        // 4. Pressed-state darkening overlay
        if !state.isDisabled {
            if state.isUpPressed {
                let topHalf = PaintRect(x: frame.minX, y: frame.minY, width: frame.size.width, height: frame.size.height / 2)
                context.fillRect(topHalf, color: MacColors.pressedOverlay)
            } else if state.isDownPressed {
                let bottomHalf = PaintRect(x: frame.minX, y: separatorY, width: frame.size.width, height: frame.size.height / 2)
                context.fillRect(bottomHalf, color: MacColors.pressedOverlay)
            }
        }

        // 5. Chevrons
        let chevronColor = state.isDisabled ? MacColors.disabledControlText : MacColors.controlText
        let midX = frame.midX
        let topHalfMidY = frame.minY + frame.size.height / 4
        let bottomHalfMidY = frame.minY + 3 * frame.size.height / 4
        
        let halfWidth = metrics.chevronWidth / 2
        let halfHeight = metrics.chevronHeight / 2

        // Up chevron (pointing up: ^)
        context.strokeLine(
            from: PaintPoint(x: midX - halfWidth, y: topHalfMidY + halfHeight),
            to: PaintPoint(x: midX, y: topHalfMidY - halfHeight),
            color: chevronColor,
            lineWidth: metrics.chevronLineWidth
        )
        context.strokeLine(
            from: PaintPoint(x: midX, y: topHalfMidY - halfHeight),
            to: PaintPoint(x: midX + halfWidth, y: topHalfMidY + halfHeight),
            color: chevronColor,
            lineWidth: metrics.chevronLineWidth
        )

        // Down chevron (pointing down: v)
        context.strokeLine(
            from: PaintPoint(x: midX - halfWidth, y: bottomHalfMidY - halfHeight),
            to: PaintPoint(x: midX, y: bottomHalfMidY + halfHeight),
            color: chevronColor,
            lineWidth: metrics.chevronLineWidth
        )
        context.strokeLine(
            from: PaintPoint(x: midX, y: bottomHalfMidY + halfHeight),
            to: PaintPoint(x: midX + halfWidth, y: bottomHalfMidY - halfHeight),
            color: chevronColor,
            lineWidth: metrics.chevronLineWidth
        )
    }

    /// Color used to fill the stepper chrome based on the current state.
    static func chromeFillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            // Disabled controls fade to a lighter shade of the control color.
            return PaintColor(
                red: MacColors.control.red,
                green: MacColors.control.green,
                blue: MacColors.control.blue,
                alpha: 0.5
            )
        }
        return MacColors.control
    }
}
