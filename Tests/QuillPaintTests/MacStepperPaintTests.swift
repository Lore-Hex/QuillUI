import Foundation
import Testing
@testable import QuillPaint

@Suite("MacStepperPaint rendering")
struct MacStepperPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 13, height: 22)

    @Test("Normal state: fill, border, separator, up/down chevrons")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacStepperPaint().paint(into: ctx, frame: frame, state: .normal)

        // Expect:
        // 1. fillRoundedRect (capsule fill)
        // 2. strokeRoundedRect (capsule border)
        // 3. strokeLine (horizontal separator)
        // 4. strokeLine (up chevron part 1)
        // 5. strokeLine (up chevron part 2)
        // 6. strokeLine (down chevron part 1)
        // 7. strokeLine (down chevron part 2)
        #expect(ctx.calls.count == 7)
        guard ctx.calls.count == 7 else { return }

        // Check fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Stepper.cornerRadius)
            #expect(color == MacColors.control)
        } else {
            Issue.record("Expected fillRoundedRect for capsule fill")
        }

        // Check border
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Stepper.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.Stepper.borderLineWidth)
        } else {
            Issue.record("Expected strokeRoundedRect for capsule border")
        }

        // Check separator
        if case let .strokeLine(start, end, color, lineWidth) = ctx.calls[2] {
            #expect(start.y == 11)
            #expect(end.y == 11)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.Stepper.borderLineWidth)
        } else {
            Issue.record("Expected strokeLine for horizontal separator")
        }
    }

    @Test("Up pressed state adds top-half overlay")
    func upPressedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isUpPressed: true)
        MacStepperPaint().paint(into: ctx, frame: frame, state: state)

        // Expect 8 calls (overlay added at index 3)
        #expect(ctx.calls.count == 8)
        
        if case let .fillRoundedRect(rect, _, color) = ctx.calls[3] {
             // Wait, I used fillRect in my implementation, which is a convenience for fillRoundedRect with radius 0.
             // RecordingPaintContext records it as fillRoundedRect(rect, 0, color)
             #expect(rect.minY == 0)
             #expect(rect.size.height == 11)
             #expect(color == MacColors.pressedOverlay)
        } else {
            // Wait, let me check RecordingPaintContext again.
            // yes, it maps fillRect to fillRoundedRect with cornerRadius: 0
        }
    }

    @Test("Down pressed state adds bottom-half overlay")
    func downPressedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDownPressed: true)
        MacStepperPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 8)
        
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[3] {
            #expect(rect.minY == 11)
            #expect(rect.size.height == 11)
            #expect(radius == 0)
            #expect(color == MacColors.pressedOverlay)
        }
    }

    @Test("Disabled state uses dimmed colors and no overlays")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDisabled: true, isUpPressed: true)
        MacStepperPaint().paint(into: ctx, frame: frame, state: state)

        // No overlay, so 7 calls
        #expect(ctx.calls.count == 7)
        
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
        }
        
        // Check chevron color (last 4 calls)
        for i in 3...6 {
            if case let .strokeLine(_, _, color, _) = ctx.calls[i] {
                #expect(color == MacColors.disabledControlText)
            }
        }
    }

    @Test("Focused state draws focus ring first")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacStepperPaint().paint(into: ctx, frame: frame, state: state)

        // Focus ring is first, so 8 calls total
        #expect(ctx.calls.count == 8)
        if case let .strokeRoundedRect(_, _, color, _) = ctx.calls[0] {
            #expect(color == MacColors.focusRing)
        } else {
            Issue.record("Expected first call to be focus ring")
        }
    }
}
