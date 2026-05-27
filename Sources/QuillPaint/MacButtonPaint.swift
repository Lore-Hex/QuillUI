import Foundation

/// Paints a macOS-style `.bordered` button into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the button
///   2. button chrome fill (default-blue accent if `state.isDefault`, else
///      `control` light grey)
///   3. button chrome border (subtle separator stroke)
///   4. (optional) pressed-state darkening overlay
///
/// Text and image content are NOT painted here — labels are layered on top
/// integration layer (a later iteration). That keeps
/// `MacButtonPaint` purely about chrome and lets it stay testable without
/// pulling in font rendering.
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

        // Label content
        if let label = label {
            let font = state.isDefault ? MacFonts.controlLabelEmphasized : MacFonts.controlLabel
            let color = state.isDisabled ? MacColors.disabledControlText : (state.isDefault ? MacColors.defaultButtonText : MacColors.controlText)

            let textSize = context.measureText(label, font: font)

            // Centered horizontally, vertically centered with a -1pt visual adjustment.
            // Core Text's CTLineDraw draws with the baseline at the point, so we
            // need to account for the typical ascent/descent of the font.
            // For 13pt SF Pro, midY + (textSize.height / 2) is a good heuristic
            // for the baseline that centers the glyph bounding box.
            let x = frame.midX - (textSize.width / 2)
            let y = frame.midY + (textSize.height / 2) - 1.0

            context.drawText(label, at: PaintPoint(x: x, y: y), font: font, color: color)
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
}
