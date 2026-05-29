import Foundation
import Testing
@testable import QuillPaint

@Suite("MacStepperPaint rendering")
struct MacStepperPaintTests {
    private let frame = PaintRect(
        x: 0,
        y: 0,
        width: MacMetrics.Stepper.regularWidth,
        height: MacMetrics.Stepper.regularHeight
    )

    @Test("Geometry matches regular NSStepper bounds")
    func geometry() {
        let chrome = MacStepperPaint.chromeRect(in: frame)
        #expect(chrome == PaintRect(x: 1, y: 2, width: 17, height: 24))

        #expect(MacStepperPaint.segmentRect(.up, in: chrome) == PaintRect(x: 1, y: 2, width: 17, height: 12))
        #expect(MacStepperPaint.segmentRect(.down, in: chrome) == PaintRect(x: 1, y: 14, width: 17, height: 12))

        let upChevron = MacStepperPaint.chevronPoints(for: .up, in: chrome)
        #expect(upChevron.left == PaintPoint(x: 7, y: 9.5))
        #expect(upChevron.apex == PaintPoint(x: 9.5, y: 6.5))
        #expect(upChevron.right == PaintPoint(x: 12, y: 9.5))

        let downChevron = MacStepperPaint.chevronPoints(for: .down, in: chrome)
        #expect(downChevron.left == PaintPoint(x: 7, y: 18.5))
        #expect(downChevron.apex == PaintPoint(x: 9.5, y: 21.5))
        #expect(downChevron.right == PaintPoint(x: 12, y: 18.5))
    }

    @Test("Normal state draws fill, border, divider, and both chevrons")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacStepperPaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 7)
        guard ctx.calls.count == 7 else { return }

        let chrome = MacStepperPaint.chromeRect(in: frame)
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == chrome)
            #expect(radius == MacMetrics.Stepper.cornerRadius)
            #expect(color == MacColors.stepperFill)
        } else {
            Issue.record("Expected first call to be stepper fill")
        }

        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == chrome)
            #expect(radius == MacMetrics.Stepper.cornerRadius)
            #expect(color == MacColors.stepperBorder)
            #expect(lineWidth == MacMetrics.Stepper.borderLineWidth)
        } else {
            Issue.record("Expected second call to be stepper border")
        }

        if case let .strokeLine(from, to, color, lineWidth) = ctx.calls[2] {
            #expect(from == PaintPoint(x: chrome.minX + 1, y: chrome.midY))
            #expect(to == PaintPoint(x: chrome.maxX - 1, y: chrome.midY))
            #expect(color == MacColors.stepperDivider)
            #expect(lineWidth == MacMetrics.Stepper.dividerLineWidth)
        } else {
            Issue.record("Expected third call to be stepper divider")
        }
    }

    @Test("Up pressed state shades the upper segment")
    func upPressedState() {
        let ctx = RecordingPaintContext()
        let paint = MacStepperPaint(pressedSegment: .up)
        paint.paint(into: ctx, frame: frame, state: PaintControlState(isPressed: true))

        #expect(ctx.calls.count == 8)
        guard ctx.calls.count == 8 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            let chrome = MacStepperPaint.chromeRect(in: frame)
            #expect(rect == MacStepperPaint.segmentRect(.up, in: chrome))
            #expect(radius == MacMetrics.Stepper.segmentCornerRadius)
            #expect(color == MacColors.stepperPressedOverlay)
        } else {
            Issue.record("Expected second call to be upper pressed overlay")
        }
    }

    @Test("Down pressed state shades the lower segment")
    func downPressedState() {
        let ctx = RecordingPaintContext()
        let paint = MacStepperPaint(pressedSegment: .down)
        paint.paint(into: ctx, frame: frame, state: PaintControlState(isPressed: true))

        #expect(ctx.calls.count == 8)
        guard ctx.calls.count == 8 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            let chrome = MacStepperPaint.chromeRect(in: frame)
            #expect(rect == MacStepperPaint.segmentRect(.down, in: chrome))
            #expect(radius == MacMetrics.Stepper.segmentCornerRadius)
            #expect(color == MacColors.stepperPressedOverlay)
        } else {
            Issue.record("Expected second call to be lower pressed overlay")
        }
    }

    @Test("Disabled state dims chrome and suppresses pressed overlay")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let paint = MacStepperPaint(pressedSegment: .up)
        paint.paint(
            into: ctx,
            frame: frame,
            state: PaintControlState(isPressed: true, isDisabled: true)
        )

        #expect(ctx.calls.count == 7)
        guard ctx.calls.count == 7 else { return }

        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
        } else {
            Issue.record("Expected disabled fill")
        }

        if case let .strokeRoundedRect(_, _, color, _) = ctx.calls[1] {
            #expect(color.alpha == MacColors.stepperBorder.alpha * 0.5)
        } else {
            Issue.record("Expected disabled border")
        }

        if case let .strokeLine(_, _, color, _) = ctx.calls[3] {
            #expect(color == MacColors.disabledControlText)
        } else {
            Issue.record("Expected disabled chevron stroke")
        }
    }
}
