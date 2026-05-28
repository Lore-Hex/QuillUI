import Foundation

/// Paints a modern macOS overlay `NSScroller` into a `PaintContext`.
///
/// Draws in this z-order:
///   1. thin translucent overlay track
///   2. capsule knob positioned by `progress`
///
/// Overlay fade timing belongs to the host layer. This paint control renders
/// the visible enabled scroller chrome for each frame; disabled scrollers are
/// hidden.
public struct MacScrollerPaint: PaintControl {
    public enum Orientation: Equatable, Hashable, Sendable {
        case vertical
        case horizontal
    }

    public var orientation: Orientation
    public var progress: Double
    public var coverage: Double

    public init(
        orientation: Orientation,
        progress: Double = 0,
        coverage: Double = 0.2
    ) {
        self.orientation = orientation
        self.progress = progress
        self.coverage = coverage
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        guard !state.isDisabled else { return }

        let track = frame.insetBy(
            dx: MacMetrics.Scroller.trackInset,
            dy: MacMetrics.Scroller.trackInset
        )
        guard track.size.width > 0, track.size.height > 0 else { return }

        context.fillRoundedRect(
            track,
            cornerRadius: Self.capsuleRadius(for: track),
            color: MacColors.scrollerTrack
        )

        let knob = Self.knobRect(
            orientation: orientation,
            track: track,
            progress: progress,
            coverage: coverage,
            state: state
        )
        guard knob.size.width > 0, knob.size.height > 0 else { return }

        context.fillRoundedRect(
            knob,
            cornerRadius: Self.capsuleRadius(for: knob),
            color: Self.knobColor(for: state)
        )
    }

    static func knobRect(
        orientation: Orientation,
        track: PaintRect,
        progress: Double,
        coverage: Double,
        state: PaintControlState
    ) -> PaintRect {
        let clampedProgress = progress.clamped(to: 0...1)
        let clampedCoverage = coverage.clamped(to: 0...1)
        let expands = state.isHovered || state.isPressed

        switch orientation {
        case .vertical:
            let width = min(
                track.size.width,
                MacMetrics.Scroller.verticalKnobWidth
                    + (expands ? MacMetrics.Scroller.hoveredKnobExpansion : 0)
            )
            let length = knobLength(trackLength: track.size.height, coverage: clampedCoverage)
            let x = track.midX - width / 2
            let y = track.minY + (track.size.height - length) * clampedProgress
            return PaintRect(x: x, y: y, width: width, height: length)

        case .horizontal:
            let height = min(
                track.size.height,
                MacMetrics.Scroller.horizontalKnobHeight
                    + (expands ? MacMetrics.Scroller.hoveredKnobExpansion : 0)
            )
            let length = knobLength(trackLength: track.size.width, coverage: clampedCoverage)
            let x = track.minX + (track.size.width - length) * clampedProgress
            let y = track.midY - height / 2
            return PaintRect(x: x, y: y, width: length, height: height)
        }
    }

    static func knobColor(for state: PaintControlState) -> PaintColor {
        if state.isPressed {
            return MacColors.scrollerKnob.withAlpha(MacColors.scrollerKnob.alpha + 0.18)
        }
        if state.isHovered {
            return MacColors.scrollerKnob.withAlpha(MacColors.scrollerKnob.alpha + 0.08)
        }
        return MacColors.scrollerKnob
    }

    private static func knobLength(trackLength: Double, coverage: Double) -> Double {
        min(trackLength, max(MacMetrics.Scroller.minimumKnobLength, trackLength * coverage))
    }

    private static func capsuleRadius(for rect: PaintRect) -> Double {
        min(MacMetrics.Scroller.knobCornerRadius, min(rect.size.width, rect.size.height) / 2)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension PaintColor {
    func withAlpha(_ alpha: Double) -> PaintColor {
        PaintColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }
}
