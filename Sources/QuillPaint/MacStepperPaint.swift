import Foundation

/// Paints a regular macOS `NSStepper` into a `PaintContext`.
///
/// Draws in this z-order:
///   1. capsule chrome fill
///   2. (optional) pressed overlay for the active up/down half
///   3. capsule border
///   4. horizontal divider between the two halves
///   5. up/down chevron glyphs
///
/// The stepper's pressed half is modeled as value configuration because
/// `PaintControlState` only carries a generic `isPressed` flag.
public struct MacStepperPaint: PaintControl {
    public enum Segment: Equatable, Hashable, Sendable {
        case up
        case down
    }

    public var pressedSegment: Segment?

    public init(pressedSegment: Segment? = nil) {
        self.pressedSegment = pressedSegment
    }

    public func paint(into context: PaintContext, frame: PaintRect, state: PaintControlState) {
        let chrome = Self.chromeRect(in: frame)
        guard chrome.size.width > 0, chrome.size.height > 0 else { return }

        context.fillRoundedRect(
            chrome,
            cornerRadius: MacMetrics.Stepper.cornerRadius,
            color: Self.fillColor(for: state)
        )

        if state.isPressed, !state.isDisabled, let pressedSegment {
            context.fillRoundedRect(
                Self.segmentRect(pressedSegment, in: chrome),
                cornerRadius: MacMetrics.Stepper.segmentCornerRadius,
                color: MacColors.stepperPressedOverlay
            )
        }

        context.strokeRoundedRect(
            chrome,
            cornerRadius: MacMetrics.Stepper.cornerRadius,
            color: Self.borderColor(for: state),
            lineWidth: MacMetrics.Stepper.borderLineWidth
        )

        let dividerY = chrome.midY
        context.strokeLine(
            from: PaintPoint(x: chrome.minX + 1, y: dividerY),
            to: PaintPoint(x: chrome.maxX - 1, y: dividerY),
            color: Self.dividerColor(for: state),
            lineWidth: MacMetrics.Stepper.dividerLineWidth
        )

        let glyphColor = Self.glyphColor(for: state)
        for segment in [Segment.up, .down] {
            let chevron = Self.chevronPoints(for: segment, in: chrome)
            context.strokeLine(
                from: chevron.left,
                to: chevron.apex,
                color: glyphColor,
                lineWidth: MacMetrics.Stepper.chevronLineWidth
            )
            context.strokeLine(
                from: chevron.apex,
                to: chevron.right,
                color: glyphColor,
                lineWidth: MacMetrics.Stepper.chevronLineWidth
            )
        }
    }

    static func chromeRect(in frame: PaintRect) -> PaintRect {
        frame.insetBy(
            dx: MacMetrics.Stepper.chromeHorizontalInset,
            dy: MacMetrics.Stepper.chromeVerticalInset
        )
    }

    static func segmentRect(_ segment: Segment, in chrome: PaintRect) -> PaintRect {
        let segmentHeight = chrome.size.height / 2
        switch segment {
        case .up:
            return PaintRect(
                x: chrome.minX,
                y: chrome.minY,
                width: chrome.size.width,
                height: segmentHeight
            )
        case .down:
            return PaintRect(
                x: chrome.minX,
                y: chrome.midY,
                width: chrome.size.width,
                height: segmentHeight
            )
        }
    }

    static func chevronPoints(
        for segment: Segment,
        in chrome: PaintRect
    ) -> (left: PaintPoint, apex: PaintPoint, right: PaintPoint) {
        let segmentRect = Self.segmentRect(segment, in: chrome)
        let centerX = segmentRect.midX
        let centerY = segmentRect.midY
        let halfWidth = MacMetrics.Stepper.chevronWidth / 2
        let halfHeight = MacMetrics.Stepper.chevronHeight / 2

        switch segment {
        case .up:
            return (
                left: PaintPoint(x: centerX - halfWidth, y: centerY + halfHeight),
                apex: PaintPoint(x: centerX, y: centerY - halfHeight),
                right: PaintPoint(x: centerX + halfWidth, y: centerY + halfHeight)
            )
        case .down:
            return (
                left: PaintPoint(x: centerX - halfWidth, y: centerY - halfHeight),
                apex: PaintPoint(x: centerX, y: centerY + halfHeight),
                right: PaintPoint(x: centerX + halfWidth, y: centerY - halfHeight)
            )
        }
    }

    static func fillColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.stepperFill.red,
                green: MacColors.stepperFill.green,
                blue: MacColors.stepperFill.blue,
                alpha: 0.5
            )
        }
        return MacColors.stepperFill
    }

    static func borderColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.stepperBorder.red,
                green: MacColors.stepperBorder.green,
                blue: MacColors.stepperBorder.blue,
                alpha: MacColors.stepperBorder.alpha * 0.5
            )
        }
        return MacColors.stepperBorder
    }

    static func dividerColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return PaintColor(
                red: MacColors.stepperDivider.red,
                green: MacColors.stepperDivider.green,
                blue: MacColors.stepperDivider.blue,
                alpha: MacColors.stepperDivider.alpha * 0.5
            )
        }
        return MacColors.stepperDivider
    }

    static func glyphColor(for state: PaintControlState) -> PaintColor {
        if state.isDisabled {
            return MacColors.disabledControlText
        }
        return MacColors.stepperGlyph
    }
}
