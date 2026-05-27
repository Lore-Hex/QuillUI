import Foundation

/// Paints a macOS-style `.bezelStyle = .roundedBezel` text field chrome
/// into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the field
///   2. field fill (white normally, slightly dimmed when disabled)
///   3. field border (subtle separator stroke)
///
/// Text field content is still composited by the host; this paint primitive
/// owns only the field chrome until selection, caret, and editable text
/// layout land together.
///
/// Text fields ignore `isPressed`, `isHovered`, and `isDefault` — those
/// affordances don't apply to text input on macOS.
public struct MacTextFieldPaint: PaintControl {
    public init() {}

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.FocusRing.outset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.TextField.cornerRadius + 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // Fill
        let fillColor = Self.fillColor(for: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.TextField.cornerRadius,
            color: fillColor
        )

        // Border
        let borderColor = Self.borderColor(for: state)
        context.strokeRoundedRect(
            frame,
            cornerRadius: MacMetrics.TextField.cornerRadius,
            color: borderColor,
            lineWidth: MacMetrics.TextField.borderLineWidth
        )
    }

    static func fillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            // Disabled text fields fade to a slightly off-white.
            return PaintColor(
                red: MacColors.controlBackground.red,
                green: MacColors.controlBackground.green,
                blue: MacColors.controlBackground.blue,
                alpha: 0.6
            )
        }
        return MacColors.controlBackground
    }

    static func borderColor(for state: PaintControlState) -> PaintColor {
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
}
