import Foundation

/// Paints a macOS-style `NSSearchField` chrome into a `PaintContext`.
///
/// Follows the same z-order and state logic as `MacTextFieldPaint`, but with
/// capsule-shaped corners and a leading magnifier glyph.
///
/// Search fields on macOS Sonoma (1x):
/// - Height: 22px
/// - Corner radius: 11px
/// - Magnifier glyph: leading-aligned, approx 13x13px
/// - Placeholder: centered vertically, following the magnifier
public struct MacSearchFieldPaint: PaintControl {
    public var placeholder: String?

    public init(placeholder: String? = "Search") {
        self.placeholder = placeholder
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.FocusRing.outset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.SearchField.cornerRadius + 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // Fill
        let fillColor = MacTextFieldPaint.fillColor(for: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.SearchField.cornerRadius,
            color: fillColor
        )

        // Border
        let borderColor = MacTextFieldPaint.borderColor(for: state)
        context.strokeRoundedRect(
            frame,
            cornerRadius: MacMetrics.SearchField.cornerRadius,
            color: borderColor,
            lineWidth: MacMetrics.SearchField.borderLineWidth
        )

        // Magnifier Icon
        let magnifierSize = MacMetrics.SearchField.magnifierSize
        let magnifierRect = PaintRect(
            x: frame.minX + MacMetrics.SearchField.magnifierLeadingPadding,
            y: frame.midY - magnifierSize / 2,
            width: magnifierSize,
            height: magnifierSize
        )
        drawMagnifier(into: context, rect: magnifierRect, color: MacColors.controlText)

        // Placeholder Text
        if let placeholder, !placeholder.isEmpty {
            let font = MacFonts.controlLabel
            let textX = magnifierRect.maxX + MacMetrics.SearchField.magnifierTrailingPadding
            let textSize = PaintTextMetrics.measure(placeholder, font: font)
            let textPoint = PaintPoint(
                x: textX,
                y: frame.midY - textSize.height / 2
            )

            let textColor = state.isDisabled ? MacColors.disabledControlText : MacColors.secondaryLabel
            context.drawText(placeholder, at: textPoint, font: font, color: textColor)
        }
    }

    private func drawMagnifier(into context: PaintContext, rect: PaintRect, color: PaintColor) {
        let iconColor = PaintColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha * MacMetrics.SearchField.magnifierOpacity
        )

        // Circle: approx 8.5x8.5
        let circleSize: Double = 8.5
        let circleRect = PaintRect(
            x: rect.minX + 0.5,
            y: rect.minY + 0.5,
            width: circleSize,
            height: circleSize
        )
        context.strokeRoundedRect(
            circleRect,
            cornerRadius: circleSize / 2,
            color: iconColor,
            lineWidth: 1.2
        )

        // Handle: from circle bottom-right towards rect bottom-right
        // macOS magnifier handle is typically at 45 degrees
        let handleStart = PaintPoint(x: circleRect.minX + 6.5, y: circleRect.minY + 6.5)
        let handleEnd = PaintPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)
        context.strokeLine(from: handleStart, to: handleEnd, color: iconColor, lineWidth: 1.5)
    }
}
