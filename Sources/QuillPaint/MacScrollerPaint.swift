import Foundation

/// Paints a macOS-style overlay scroller into a `PaintContext`.
///
/// macOS overlay scrollers consist of a capsule-shaped "knob" that travels
/// along a mostly-transparent track. In modern macOS, these scrollers
/// auto-fade; this paint layer assumes the knob should always be drawn,
/// with the fade animation handled by the higher-level host layer.
///
/// State transitions:
/// - Normal: thin knob
/// - Hovered: knob thickens by ~2pt
/// - Pressed: knob stays thick and may darken slightly
/// - Disabled: knob is hidden
public struct MacScrollerPaint: PaintControl {
    public enum Orientation: Sendable {
        case horizontal
        case vertical
    }

    /// Whether this scroller is vertical or horizontal.
    public var orientation: Orientation

    /// The scroll position as a normalized value from 0.0 to 1.0.
    public var progress: Double

    /// The ratio of the viewport to the total content size (0.0 to 1.0).
    /// This determines the length of the knob.
    public var coverage: Double

    public init(
        orientation: Orientation = .vertical,
        progress: Double = 0,
        coverage: Double = 1
    ) {
        self.orientation = orientation
        self.progress = max(0, min(1, progress))
        self.coverage = max(0, min(1, coverage))
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        // Disabled hides the knob entirely.
        if state.isDisabled {
            return
        }

        // Draw the track (usually a very subtle background)
        context.fillRoundedRect(frame, cornerRadius: 0, color: MacColors.scrollerTrack)

        let isHoveredOrPressed = state.isHovered || state.isPressed
        let knobWidth = MacMetrics.Scroller.knobWidth + (isHoveredOrPressed ? 2.0 : 0.0)
        let knobCornerRadius = knobWidth / 2.0 // Capsule

        if orientation == .vertical {
            let trackHeight = frame.size.height
            let knobLength = max(MacMetrics.Scroller.minKnobLength, trackHeight * coverage)
            let maxTravel = max(0, trackHeight - knobLength)
            let knobY = frame.minY + maxTravel * progress

            // Position the knob according to trackInset from the right edge.
            // If the frame is narrow, it might overlap or center.
            let knobX = frame.maxX - MacMetrics.Scroller.trackInset - knobWidth
            let knobRect = PaintRect(x: knobX, y: knobY, width: knobWidth, height: knobLength)

            context.fillRoundedRect(knobRect, cornerRadius: knobCornerRadius, color: MacColors.scrollerKnob)

            // Darken slightly when pressed
            if state.isPressed {
                context.fillRoundedRect(knobRect, cornerRadius: knobCornerRadius, color: MacColors.pressedOverlay)
            }
        } else {
            let trackWidth = frame.size.width
            let knobLength = max(MacMetrics.Scroller.minKnobLength, trackWidth * coverage)
            let maxTravel = max(0, trackWidth - knobLength)
            let knobX = frame.minX + maxTravel * progress

            // Position the knob according to trackInset from the bottom edge.
            let knobY = frame.maxY - MacMetrics.Scroller.trackInset - knobWidth
            let knobRect = PaintRect(x: knobX, y: knobY, width: knobLength, height: knobWidth)

            context.fillRoundedRect(knobRect, cornerRadius: knobCornerRadius, color: MacColors.scrollerKnob)

            // Darken slightly when pressed
            if state.isPressed {
                context.fillRoundedRect(knobRect, cornerRadius: knobCornerRadius, color: MacColors.pressedOverlay)
            }
        }
    }
}
