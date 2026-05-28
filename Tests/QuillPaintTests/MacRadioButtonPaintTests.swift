import Foundation
import Testing
@testable import QuillPaint

@Suite("MacRadioButtonPaint rendering")
struct MacRadioButtonPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 16, height: 16)
    private let diameter = MacMetrics.RadioButton.diameter // 14
    private let radioFrame = PaintRect(x: 1, y: 1, width: 14, height: 14)

    @Test("Off-normal state: fill + border, no dot, no focus ring")
    func offNormalState() {
        let ctx = RecordingPaintContext()
        MacRadioButtonPaint().paint(into: ctx, frame: frame, state: .normal)

        // Expected calls: 1. fill outer circle, 2. stroke outer circle border
        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == radioFrame)
            #expect(radius == diameter / 2)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected first call to be fillRoundedRect, got \(ctx.calls[0])")
        }

        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == radioFrame)
            #expect(radius == diameter / 2)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.RadioButton.borderLineWidth)
        } else {
            Issue.record("Expected second call to be strokeRoundedRect, got \(ctx.calls[1])")
        }
    }

    @Test("On-normal state: accent fill, no border, white dot")
    func onNormalState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isSelected: true)
        MacRadioButtonPaint().paint(into: ctx, frame: frame, state: state)

        // Expected calls: 1. fill outer circle (accent), 2. fill dot (white)
        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        if case let .fillRoundedRect(rect, _, color) = ctx.calls[0] {
            #expect(rect == radioFrame)
            #expect(color == MacColors.accent)
        }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            let dotDiameter = MacMetrics.RadioButton.dotDiameter // 6
            let expectedDotFrame = PaintRect(x: 5, y: 5, width: 6, height: 6)
            #expect(rect == expectedDotFrame)
            #expect(radius == dotDiameter / 2)
            #expect(color == MacColors.defaultButtonText)
        } else {
            Issue.record("Expected second call to be fillRoundedRect for dot, got \(ctx.calls[1])")
        }
    }

    @Test("Focused state draws focus ring behind")
    func focusedDrawsRingFirst() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacRadioButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = first {
            let outset = MacMetrics.RadioButton.focusRingOutset // 2.5
            let expected = radioFrame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(radius == (diameter + outset * 2) / 2)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.FocusRing.lineWidth)
        } else {
            Issue.record("Expected first call to be the focus ring stroke, got \(first)")
        }
    }

    @Test("Disabled state uses dimmed colors")
    func disabledStateColors() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDisabled: true, isSelected: true)
        MacRadioButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 2)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
            #expect(color.red == MacColors.accent.red)
        }
        if case let .fillRoundedRect(_, _, color) = ctx.calls[1] {
            #expect(color.alpha == 0.5)
            #expect(color.red == MacColors.defaultButtonText.red)
        }
    }

    @Test("Pressed state adds darkening overlay")
    func pressedStateOverlay() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true)
        MacRadioButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3)
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls.last {
            #expect(rect == radioFrame)
            #expect(radius == diameter / 2)
            #expect(color == MacColors.pressedOverlay)
        } else {
            Issue.record("Expected pressed overlay as the final call")
        }
    }
}
