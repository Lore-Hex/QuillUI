import Foundation
import Testing
@testable import QuillPaint

@Suite("MacCheckboxPaint rendering")
struct MacCheckboxPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 14, height: 14)

    @Test("Unchecked normal: fill + border")
    func uncheckedNormal() {
        let ctx = RecordingPaintContext()
        MacCheckboxPaint(value: .off).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        #expect(ctx.calls[0] == .fillRoundedRect(rect: frame, cornerRadius: MacMetrics.Checkbox.cornerRadius, color: MacColors.controlBackground))
        #expect(ctx.calls[1] == .strokeRoundedRect(rect: frame, cornerRadius: MacMetrics.Checkbox.cornerRadius, color: MacColors.separator, lineWidth: 1.0))
    }

    @Test("Checked normal: fill + checkmark (2 lines)")
    func checkedNormal() {
        let ctx = RecordingPaintContext()
        MacCheckboxPaint(value: .on).paint(into: ctx, frame: frame, state: .normal)

        // Fill + 2 strokeLine calls for checkmark
        #expect(ctx.calls.count == 3)
        #expect(ctx.calls[0] == .fillRoundedRect(rect: frame, cornerRadius: MacMetrics.Checkbox.cornerRadius, color: MacColors.accent))

        // Verify checkmark strokes
        if case let .strokeLine(start, mid, color, lineWidth) = ctx.calls[1] {
            #expect(color == MacColors.defaultButtonText)
            #expect(lineWidth == MacMetrics.Checkbox.checkmarkLineWidth)
            #expect(start.x == frame.minX + frame.size.width * 0.25)
            #expect(mid.y == frame.minY + frame.size.height * 0.72)
        } else {
            Issue.record("Expected strokeLine for checkmark part 1, got \(ctx.calls[1])")
        }

        if case .strokeLine = ctx.calls[2] {
            // OK
        } else {
            Issue.record("Expected strokeLine for checkmark part 2, got \(ctx.calls[2])")
        }
    }

    @Test("Mixed normal: fill + dash (1 line)")
    func mixedNormal() {
        let ctx = RecordingPaintContext()
        MacCheckboxPaint(value: .mixed).paint(into: ctx, frame: frame, state: .normal)

        // Fill + 1 strokeLine call for dash
        #expect(ctx.calls.count == 2)
        #expect(ctx.calls[0] == .fillRoundedRect(rect: frame, cornerRadius: MacMetrics.Checkbox.cornerRadius, color: MacColors.accent))

        if case let .strokeLine(start, end, color, lineWidth) = ctx.calls[1] {
            #expect(color == MacColors.defaultButtonText)
            #expect(lineWidth == MacMetrics.Checkbox.checkmarkLineWidth)
            #expect(start.y == frame.midY)
            #expect(end.y == frame.midY)
        } else {
            Issue.record("Expected strokeLine for dash, got \(ctx.calls[1])")
        }
    }

    @Test("Focused state draws focus ring behind")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacCheckboxPaint(value: .off).paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3)
        if case let .strokeRoundedRect(rect, _, color, _) = ctx.calls[0] {
            #expect(color == MacColors.focusRing)
            let outset = MacMetrics.Checkbox.focusRingOutset
            #expect(rect == frame.insetBy(dx: -outset, dy: -outset))
        } else {
            Issue.record("Expected focus ring first, got \(ctx.calls[0])")
        }
    }

    @Test("Pressed state adds overlay")
    func pressedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true)
        MacCheckboxPaint(value: .off).paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3) // Fill + Border + Pressed Overlay
        #expect(ctx.calls.last == .fillRoundedRect(rect: frame, cornerRadius: MacMetrics.Checkbox.cornerRadius, color: MacColors.pressedOverlay))
    }

    @Test("Disabled state dims colors and suppresses focus ring")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isDisabled: true)
        MacCheckboxPaint(value: .on).paint(into: ctx, frame: frame, state: state)

        // No focus ring when disabled.
        // Should have: Fill + Checkmark (2 lines)
        #expect(ctx.calls.count == 3)

        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
            #expect(color.red == MacColors.accent.red)
        } else {
            Issue.record("Expected fillRoundedRect, got \(ctx.calls[0])")
        }

        if case let .strokeLine(_, _, color, _) = ctx.calls[1] {
            #expect(color.alpha == 0.7)
        } else {
            Issue.record("Expected strokeLine, got \(ctx.calls[1])")
        }
    }
}
