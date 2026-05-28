import Foundation

/// Paints a macOS-style toggle switch (`NSSwitch`) into a `PaintContext`.
///
/// Follows macOS 14 Sonoma 1x measurements: 38x21 pill with a 19x19 knob.
/// The knob slides from left (OFF) to right (ON).
public struct MacSwitchPaint: PaintControl {
    /// Whether the switch is currently toggled to the "ON" state.
    public var isOn: Bool

    public init(isOn: Bool = false) {
        self.isOn = isOn
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let metrics = MacMetrics.Switch.self
        
        // Focus ring (behind, when focused and not disabled)
        if state.isFocused && !state.isDisabled {
            let outset = MacMetrics.FocusRing.outset
            let ringFrame = frame.insetBy(dx: -outset, dy: -outset)
            context.strokeRoundedRect(
                ringFrame,
                cornerRadius: metrics.cornerRadius + 2, // Approximate focus ring corner radius adjust
                color: MacColors.focusRing,
                lineWidth: MacMetrics.FocusRing.lineWidth
            )
        }

        // Pill (background)
        let pillColor = Self.pillColor(isOn: isOn, state: state)
        context.fillRoundedRect(
            frame,
            cornerRadius: metrics.cornerRadius,
            color: pillColor
        )

        // Pill border (only when OFF, to define the shape against white backgrounds)
        if !isOn && !state.isDisabled {
            context.strokeRoundedRect(
                frame,
                cornerRadius: metrics.cornerRadius,
                color: MacColors.separator,
                lineWidth: metrics.borderLineWidth
            )
        }

        // Knob
        let knobX: Double
        if isOn {
            knobX = frame.maxX - metrics.knobInset - metrics.knobDiameter
        } else {
            knobX = frame.minX + metrics.knobInset
        }
        
        let knobFrame = PaintRect(
            x: knobX,
            y: frame.minY + metrics.knobInset,
            width: metrics.knobDiameter,
            height: metrics.knobDiameter
        )
        
        // Knob fill
        context.fillRoundedRect(
            knobFrame,
            cornerRadius: metrics.knobDiameter / 2,
            color: Self.knobFillColor(state: state)
        )
        
        // Knob subtle border/shadow approximation
        context.strokeRoundedRect(
            knobFrame,
            cornerRadius: metrics.knobDiameter / 2,
            color: PaintColor(r: 0, g: 0, b: 0, a: 38), // Slightly stronger than separator for knob definition
            lineWidth: 0.5
        )
    }

    private static func pillColor(isOn: Bool, state: PaintControlState) -> PaintColor {
        if isOn {
            if state.isDisabled {
                return MacColors.accent.withAlpha(0.5)
            }
            return MacColors.accent
        } else {
            if state.isDisabled {
                return MacColors.control.withAlpha(0.5)
            }
            return MacColors.controlBackground
        }
    }

    private static func knobFillColor(state: PaintControlState) -> PaintColor {
        // Switch knobs remain white but might dim slightly when disabled.
        let color = PaintColor(r: 255, g: 255, b: 255)
        if state.isDisabled {
            return color.withAlpha(0.8)
        }
        return color
    }
}

private extension PaintColor {
    func withAlpha(_ alpha: Double) -> PaintColor {
        return PaintColor(red: self.red, green: self.green, blue: self.blue, alpha: alpha)
    }
}
