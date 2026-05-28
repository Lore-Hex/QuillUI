import Foundation
import Testing
@testable import QuillPaint

@Suite("MacTextFieldPaint chrome rendering")
struct MacTextFieldPaintTests {
    private let frame = PaintRect(x: 10, y: 10, width: 140, height: 22)

    @Test("Normal state: fill + border, no focus ring")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: .normal)

        // Normal state should have 2 calls: 1. Fill, 2. Border
        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        // 1. Fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected first call to be fillRoundedRect, got \(ctx.calls[0])")
        }

        // 2. Border
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.TextField.borderLineWidth)
        } else {
            Issue.record("Expected second call to be strokeRoundedRect, got \(ctx.calls[1])")
        }
    }

    @Test("Focused state: focus ring + fill + border")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: state)

        // Focused state should have 3 calls: 1. Focus Ring, 2. Fill, 3. Border
        #expect(ctx.calls.count == 3)
        guard ctx.calls.count == 3 else { return }

        // 1. Focus Ring
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[0] {
            let outset = MacMetrics.FocusRing.outset
            let expectedRect = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expectedRect)
            #expect(radius == MacMetrics.TextField.cornerRadius + 2)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.FocusRing.lineWidth)
        } else {
            Issue.record("Expected first call to be focus ring stroke, got \(ctx.calls[0])")
        }

        // 2. Fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected second call to be fill, got \(ctx.calls[1])")
        }

        // 3. Border
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[2] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.TextField.borderLineWidth)
        } else {
            Issue.record("Expected third call to be border stroke, got \(ctx.calls[2])")
        }
    }

    @Test("Disabled state: dimmed fill + border, no focus ring even if focused")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isDisabled: true)
        MacTextFieldPaint().paint(into: ctx, frame: frame, state: state)

        // Disabled state should have 2 calls: 1. Fill, 2. Border (no focus ring)
        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        // 1. Fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            
            let expectedColor = PaintColor(
                red: MacColors.controlBackground.red,
                green: MacColors.controlBackground.green,
                blue: MacColors.controlBackground.blue,
                alpha: 0.6
            )
            #expect(color == expectedColor)
        } else {
            Issue.record("Expected first call to be disabled fill, got \(ctx.calls[0])")
        }

        // 2. Border
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.TextField.cornerRadius)
            #expect(lineWidth == MacMetrics.TextField.borderLineWidth)
            
            let expectedColor = PaintColor(
                red: MacColors.separator.red,
                green: MacColors.separator.green,
                blue: MacColors.separator.blue,
                alpha: MacColors.separator.alpha * 0.5
            )
            #expect(color == expectedColor)
        } else {
            Issue.record("Expected second call to be disabled border, got \(ctx.calls[1])")
        }
    }

    @Test("Pressed / hovered / default flags are ignored")
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
        
        // Output should match the normal-state shape exactly (2 calls).
        #expect(ctx.calls.count == 2)
        
        // Quick check that it's the same as normal fill+border
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color == MacColors.controlBackground)
        }
        if case let .strokeRoundedRect(_, _, color, _) = ctx.calls[1] {
            #expect(color == MacColors.separator)
        }
    }
}
