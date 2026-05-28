import Foundation

/// Paints a macOS-style checkbox (`NSButton` with `.switch` type) into a `PaintContext`.
///
/// Draws in this z-order:
///   1. (optional) focus ring outset, behind the box
///   2. checkbox box fill (white if `off`, accent blue if `on` or `mixed`)
///   3. checkbox box border (subtle separator stroke, only when `off`)
///   4. (optional) checkmark or mixed-state dash glyph
///   5. (optional) pressed-state or hovered-state darkening overlay
///
public struct MacCheckboxPaint: PaintControl {
    public enum Value: Equatable, Hashable, Sendable {
        case off
        case on
        case mixed
    }

    public var value: Value

    public init(value: Value = .off) {
        self.value = value
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.Checkbox.focusRingOutset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: MacMetrics.Checkbox.cornerRadius + 2,
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // Box fill
        let fillColor = Self.fillColor(for: value, state: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: MacMetrics.Checkbox.cornerRadius,
            color: fillColor
        )

        // Box border (only for 'off' state on macOS)
        if value == .off {
            let borderColor = Self.borderColor(for: state)
            context.strokeRoundedRect(
                frame,
                cornerRadius: MacMetrics.Checkbox.cornerRadius,
                color: borderColor,
                lineWidth: 1.0
            )
        }

        // Glyph (checkmark or dash)
        if value != .off {
            let glyphColor = Self.glyphColor(for: state)
            let lineWidth = MacMetrics.Checkbox.checkmarkLineWidth

            if value == .on {
                // Draw checkmark
                // Coordinates relative to frame, approximating macOS Sonoma 1x appearance.
                let start = PaintPoint(x: frame.minX + frame.size.width * 0.25, y: frame.minY + frame.size.height * 0.5)
                let mid = PaintPoint(x: frame.minX + frame.size.width * 0.45, y: frame.minY + frame.size.height * 0.72)
                let end = PaintPoint(x: frame.minX + frame.size.width * 0.78, y: frame.minY + frame.size.height * 0.3)

                context.strokeLine(from: start, to: mid, color: glyphColor, lineWidth: lineWidth)
                context.strokeLine(from: mid, to: end, color: glyphColor, lineWidth: lineWidth)
            } else if value == .mixed {
                // Draw dash
                let start = PaintPoint(x: frame.minX + frame.size.width * 0.22, y: frame.midY)
                let end = PaintPoint(x: frame.maxX - frame.size.width * 0.22, y: frame.midY)
                context.strokeLine(from: start, to: end, color: glyphColor, lineWidth: lineWidth)
            }
        }

        // Pressed-state darkening overlay
        if state.isPressed && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.Checkbox.cornerRadius,
                color: MacColors.pressedOverlay
            )
        } else if state.isHovered && !state.isDisabled {
            context.fillRoundedRect(
                frame,
                cornerRadius: MacMetrics.Checkbox.cornerRadius,
                color: MacColors.hoveredOverlay
            )
        }
    }

    static func fillColor(for value: Value, state: PaintControlState) -> PaintColor {
        if value == .off {
            if state.isDisabled {
                return PaintColor(
                    red: MacColors.controlBackground.red,
                    green: MacColors.controlBackground.green,
                    blue: MacColors.controlBackground.blue,
                    alpha: 0.5
                )
            }
            return MacColors.controlBackground
        } else {
            // on or mixed
            if state.isDisabled {
                // Disabled checked/mixed boxes use a greyed out accent or standard control color.
                // Modern macOS uses a lighter accent-ish grey.
                return PaintColor(
                    red: MacColors.accent.red,
                    green: MacColors.accent.green,
                    blue: MacColors.accent.blue,
                    alpha: 0.5
                )
            }
            return MacColors.accent
        }
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

    static func glyphColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.defaultButtonText.red,
                green: MacColors.defaultButtonText.green,
                blue: MacColors.defaultButtonText.blue,
                alpha: 0.7
            )
        }
        return MacColors.defaultButtonText
    }
}
