import Foundation

/// Paints a macOS-style `.bordered` pop-up button into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the button
///   2. button chrome fill (`control` light grey)
///   3. button chrome border (subtle separator stroke)
///   4. (optional) pressed-state darkening overlay
///   5. centered/leading-aligned label
///   6. trailing double-arrow indicator
///
public struct MacPopUpButtonPaint: PaintControl {
    public var label: String?

    public init(label: String? = nil) {
        self.label = label
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.PopUpButton.focusRingOutset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.PopUpButton.cornerRadius + MacMetrics.PopUpButton.focusRingCornerRadiusAdjust,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.PopUpButton.focusRingLineWidth
            )
        }

        // Chrome fill
        let fillColor = Self.chromeFillColor(for: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.PopUpButton.cornerRadius,
            color: fillColor
        )

        // Chrome border
        context.strokeRoundedRect(
            frame,
            cornerRadius: MacMetrics.PopUpButton.cornerRadius,
            color: MacColors.separator,
            lineWidth: MacMetrics.PopUpButton.borderLineWidth
        )

        // Pressed-state darkening overlay
        if state.isPressed && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.PopUpButton.cornerRadius,
                color: MacColors.pressedOverlay
            )
        } else if state.isHovered && !state.isDisabled && !state.isPressed {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.PopUpButton.cornerRadius,
                color: MacColors.hoveredOverlay
            )
        }

        // Label
        if let label, !label.isEmpty {
            let font = MacFonts.controlLabel
            let size = PaintTextMetrics.measure(label, font: font)
            // Left-aligned with padding
            let point = PaintPoint(
                x: frame.minX + MacMetrics.PopUpButton.labelLeadingPadding,
                y: frame.midY - size.height / 2 + MacMetrics.PopUpButton.labelVerticalOpticalOffset
            )
            context.drawText(label, at: point, font: font, color: Self.labelColor(for: state))
        }

        // Trailing double-arrow indicator
        let indicatorColor = Self.labelColor(for: state)
        let centerX = frame.maxX - MacMetrics.PopUpButton.indicatorTrailingPadding
        let centerY = frame.midY
        
        let halfWidth = MacMetrics.PopUpButton.chevronWidth / 2
        let halfHeight = MacMetrics.PopUpButton.chevronHeight / 2
        let spacing = MacMetrics.PopUpButton.chevronSpacing / 2
        
        // Up arrow
        let upCenterY = centerY - spacing - halfHeight
        context.strokeLine(
            from: PaintPoint(x: centerX - halfWidth, y: upCenterY + halfHeight),
            to: PaintPoint(x: centerX, y: upCenterY - halfHeight),
            color: indicatorColor,
            lineWidth: MacMetrics.PopUpButton.chevronLineWidth
        )
        context.strokeLine(
            from: PaintPoint(x: centerX, y: upCenterY - halfHeight),
            to: PaintPoint(x: centerX + halfWidth, y: upCenterY + halfHeight),
            color: indicatorColor,
            lineWidth: MacMetrics.PopUpButton.chevronLineWidth
        )
        
        // Down arrow
        let downCenterY = centerY + spacing + halfHeight
        context.strokeLine(
            from: PaintPoint(x: centerX - halfWidth, y: downCenterY - halfHeight),
            to: PaintPoint(x: centerX, y: downCenterY + halfHeight),
            color: indicatorColor,
            lineWidth: MacMetrics.PopUpButton.chevronLineWidth
        )
        context.strokeLine(
            from: PaintPoint(x: centerX, y: downCenterY + halfHeight),
            to: PaintPoint(x: centerX + halfWidth, y: downCenterY - halfHeight),
            color: indicatorColor,
            lineWidth: MacMetrics.PopUpButton.chevronLineWidth
        )
    }

    static func chromeFillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.control.red,
                green: MacColors.control.green,
                blue: MacColors.control.blue,
                alpha: 0.5
            )
        }
        return MacColors.control
    }

    static func labelColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.disabledControlText
        }
        return MacColors.controlText
    }
}
