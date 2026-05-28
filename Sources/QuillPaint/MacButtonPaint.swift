import Foundation

/// Paints a macOS-style `.bordered` button into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the button
///   2. button chrome fill (default-blue accent if `state.isDefault`, else
///      `control` light grey)
///   3. button chrome border (subtle separator stroke)
///   4. (optional) pressed-state darkening overlay
///   5. (optional) centered label
///
public struct MacButtonPaint: PaintControl {
    public var label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.Button.focusRingOutset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.Button.cornerRadius + MacMetrics.Button.focusRingCornerRadiusAdjust,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.Button.focusRingLineWidth
            )
        }

        // Chrome fill
        let fillColor = Self.chromeFillColor(for: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.Button.cornerRadius,
            color: fillColor
        )

        // Chrome border (skipped for default buttons — the accent fill is its own affordance)
        if !state.isDefault {
            context.strokeRoundedRect(
                frame,
                cornerRadius: MacMetrics.Button.cornerRadius,
                color: MacColors.separator,
                lineWidth: MacMetrics.Button.borderLineWidth
            )
        }

        // Pressed-state darkening overlay
        if state.isPressed && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.Button.cornerRadius,
                color: MacColors.pressedOverlay
            )
        } else if state.isHovered && !state.isDisabled && !state.isPressed {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.Button.cornerRadius,
                color: MacColors.hoveredOverlay
            )
        }

        if let label, !label.isEmpty {
            let font = MacFonts.controlLabel
            let size = PaintTextMetrics.measure(label, font: font)
            let point = PaintPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2 + MacMetrics.Button.labelVerticalOpticalOffset
            )
            context.drawText(label, at: point, font: font, color: Self.labelColor(for: state))
        }
    }

    /// Color used to fill the button chrome based on the current state.
    /// Exposed `internal` so tests can assert against it without
    /// reproducing the lookup.
    static func chromeFillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            // Disabled buttons fade to a lighter shade of the control color.
            return PaintColor(
                red: MacColors.control.red,
                green: MacColors.control.green,
                blue: MacColors.control.blue,
                alpha: 0.5
            )
        }
        if state.isDefault {
            return MacColors.defaultButtonFill
        }
        return MacColors.control
    }

    static func labelColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.disabledControlText
        }
        if state.isDefault {
            return MacColors.defaultButtonText
        }
        return MacColors.controlText
    }
}
