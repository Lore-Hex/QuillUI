import Foundation

/// Paints a macOS-style radio button into a `PaintContext`.
///
/// A circular radio with filled-dot selected state. Following macOS 14 Sonoma,
/// the selected state uses the system accent color for the background fill
/// and a white dot in the center.
public struct MacRadioButtonPaint: PaintControl {
    public init() {}

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let diameter = MacMetrics.RadioButton.diameter
        // Center the radio button in the provided frame if it's larger
        let radioFrame = PaintRect(
            x: frame.minX + (frame.size.width - diameter) / 2,
            y: frame.minY + (frame.size.height - diameter) / 2,
            width: diameter,
            height: diameter
        )

        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.RadioButton.focusRingOutset
            let ringFrame = radioFrame.insetBy(dx: -outset, dy: -outset)
            let ringDiameter = diameter + (outset * 2)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: ringDiameter / 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // Chrome fill
        let fillColor = Self.chromeFillColor(for: state)
        context.fillRoundedRect(
            radioFrame,
            cornerRadius: diameter / 2,
            color: fillColor
        )

        // Chrome border (only for unselected state)
        if !state.isSelected {
            let borderColor = Self.borderColor(for: state)
            context.strokeRoundedRect(
                radioFrame,
                cornerRadius: diameter / 2,
                color: borderColor,
                lineWidth: MacMetrics.RadioButton.borderLineWidth
            )
        }

        // Selected state dot
        if state.isSelected {
            let dotDiameter = MacMetrics.RadioButton.dotDiameter
            let dotFrame = PaintRect(
                x: radioFrame.minX + (diameter - dotDiameter) / 2,
                y: radioFrame.minY + (diameter - dotDiameter) / 2,
                width: dotDiameter,
                height: dotDiameter
            )
            let dotColor = Self.dotColor(for: state)
            context.fillRoundedRect(
                dotFrame,
                cornerRadius: dotDiameter / 2,
                color: dotColor
            )
        }

        // Pressed-state darkening overlay
        if state.isPressed && !state.isDisabled {
            context.fillRoundedRect(
                radioFrame,
                cornerRadius: diameter / 2,
                color: MacColors.pressedOverlay
            )
        }
    }

    private static func chromeFillColor(for state: PaintControlState) -> PaintColor {
        if state.isSelected {
            if state.isDisabled {
                return PaintColor(
                    red: MacColors.accent.red,
                    green: MacColors.accent.green,
                    blue: MacColors.accent.blue,
                    alpha: 0.5
                )
            }
            return MacColors.accent
        }

        if state.isDisabled {
            return PaintColor(
                red: MacColors.controlBackground.red,
                green: MacColors.controlBackground.green,
                blue: MacColors.controlBackground.blue,
                alpha: 0.5
            )
        }
        return MacColors.controlBackground
    }

    private static func borderColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.separator.red,
                green: MacColors.separator.green,
                blue: MacColors.separator.blue,
                alpha: MacColors.separator.alpha * 0.5
            )
        }
        return MacColors.separator
    }

    private static func dotColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.defaultButtonText.red,
                green: MacColors.defaultButtonText.green,
                blue: MacColors.defaultButtonText.blue,
                alpha: 0.5
            )
        }
        return MacColors.defaultButtonText
    }
}
