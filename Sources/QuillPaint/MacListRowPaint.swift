import Foundation

/// Paints macOS-style sidebar/list row chrome.
///
/// Text and row content are layered by the UI backend. This control owns only
/// the rounded fill states needed by Enchanted's conversation history rows.
public struct MacListRowPaint: PaintControl {
    public init() {}

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.ListRow.cornerRadius,
            color: Self.fillColor(for: state)
        )

        if state.isHovered && !state.isSelected && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.ListRow.cornerRadius,
                color: MacColors.hoveredOverlay
            )
        }
    }

    public static func fillColor(for state: PaintControlState) -> PaintColor {
        if state.isSelected {
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

    public static func primaryTextColor(for state: PaintControlState) -> PaintColor {
        state.isSelected ? MacColors.defaultButtonText : MacColors.controlText
    }

    public static func secondaryTextColor(for state: PaintControlState) -> PaintColor {
        state.isSelected ? MacColors.defaultButtonText : MacColors.secondaryLabel
    }

    public static func effectiveFillColor(for state: PaintControlState) -> PaintColor {
        let fill = fillColor(for: state)
        guard state.isHovered && !state.isSelected && !state.isDisabled else {
            return fill
        }
        return composite(MacColors.hoveredOverlay, over: fill)
    }

    private static func composite(_ overlay: PaintColor, over base: PaintColor) -> PaintColor {
        let alpha = overlay.alpha + base.alpha * (1 - overlay.alpha)
        guard alpha > 0 else { return .clear }

        return PaintColor(
            red: (overlay.red * overlay.alpha + base.red * base.alpha * (1 - overlay.alpha)) / alpha,
            green: (overlay.green * overlay.alpha + base.green * base.alpha * (1 - overlay.alpha)) / alpha,
            blue: (overlay.blue * overlay.alpha + base.blue * base.alpha * (1 - overlay.alpha)) / alpha,
            alpha: alpha
        )
    }
}
