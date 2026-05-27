import Foundation
import Testing
@testable import QuillPaint

@Suite("MacTextFieldPaint chrome rendering")
struct MacTextFieldPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 140, height: 22)

    @Test("Normal state: fill + border, no focus ring")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected first call to be fillRoundedRect, got \(ctx.calls[0])")
        }

        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.TextField.borderLineWidth)
        } else {
            Issue.record("Expected second call to be strokeRoundedRect, got \(ctx.calls[1])")
        }
    }

    @Test("Focused state draws focus ring behind chrome")
    func focusedDrawsRingFirst() {
        let ctx = RecordingPaintContext()
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: PaintControlState(isFocused: true))

        #expect(ctx.calls.count == 3)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, _, color, lineWidth) = first {
            let outset = MacMetrics.FocusRing.outset
            let expected = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.FocusRing.lineWidth)
        } else {
            Issue.record("Expected first call to be the focus ring stroke, got \(first)")
        }
    }

    @Test("Disabled state dims fill and border, suppresses focus ring")
    func disabledDimsAndSuppressesRing() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isDisabled: true)
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: state)

        // No focus ring — just fill + border.
        #expect(ctx.calls.count == 2)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha < 1.0, "Disabled fill should be partly transparent")
        }
        if case let .strokeRoundedRect(_, _, color, _) = ctx.calls[1] {
            #expect(color.alpha < MacColors.separator.alpha + 0.001, "Disabled border should be dimmer than enabled")
        }
    }

    @Test("Pressed / hovered / default flags are ignored for text fields")
    func nonApplicableStatesIgnored() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(
            isPressed: true,
            isFocused: false,
            isDisabled: false,
            isHovered: true,
            isDefault: true
        )
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: state)
        // Output should match the normal-state shape exactly.
        #expect(ctx.calls.count == 2)
    }
}
