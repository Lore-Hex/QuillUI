import Foundation
import Testing
@testable import QuillPaint

@Suite("MacScrollerPaint rendering")
struct MacScrollerPaintTests {
    private let vFrame = PaintRect(x: 0, y: 0, width: 12, height: 100)
    private let hFrame = PaintRect(x: 0, y: 0, width: 100, height: 12)

    @Test("Knob positioning math (vertical)")
    func verticalKnobPositioning() {
        let ctx = RecordingPaintContext()
        // Coverage 0.5 on 100 height = 50 length.
        // Progress 0.5 = middle.
        // Travel = 100 - 50 = 50.
        // Knob Y = 0 + 50 * 0.5 = 25.
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0.5, coverage: 0.5)
        paint.paint(into: ctx, frame: vFrame, state: .normal)

        // Calls: 1. track, 2. knob
        #expect(ctx.calls.count == 2)
        guard ctx.calls.count >= 2 else { return }

        if case let .fillRoundedRect(rect, _, color) = ctx.calls[1] {
            #expect(rect.size.height == 50)
            #expect(rect.origin.y == 25)
            #expect(color == MacColors.scrollerKnob)
        } else {
            Issue.record("Expected second call to be knob fill")
        }
    }

    @Test("Knob positioning math (horizontal)")
    func horizontalKnobPositioning() {
        let ctx = RecordingPaintContext()
        // Coverage 0.2 of 100 = 20. But min length is 26.
        let paint = MacScrollerPaint(orientation: .horizontal, progress: 1.0, coverage: 0.2)
        paint.paint(into: ctx, frame: hFrame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count >= 2 else { return }

        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            #expect(rect.size.width == MacMetrics.Scroller.minKnobLength)
            // Progress 1.0 = end. Travel = 100 - 26 = 74.
            #expect(rect.origin.x == 74)
        } else {
            Issue.record("Expected second call to be knob fill")
        }
    }

    @Test("Hover state thickens the knob")
    func hoverThickens() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0, coverage: 1)
        
        // Normal
        paint.paint(into: ctx, frame: vFrame, state: .normal)
        guard let normalKnob = ctx.calls.last, 
              case let .fillRoundedRect(normalRect, _, _) = normalKnob else { return }
        #expect(normalRect.size.width == MacMetrics.Scroller.knobWidth)

        ctx.reset()
        // Hovered
        paint.paint(into: ctx, frame: vFrame, state: PaintControlState(isHovered: true))
        guard let hoveredKnob = ctx.calls.last, 
              case let .fillRoundedRect(hoveredRect, _, _) = hoveredKnob else { return }
        #expect(hoveredRect.size.width == MacMetrics.Scroller.knobWidth + 2)
    }

    @Test("Disabled state hides everything")
    func disabledHidesEverything() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint()
        paint.paint(into: ctx, frame: vFrame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.isEmpty)
    }

    @Test("Pressed state adds darkening overlay on top of knob")
    func pressedStateOverlay() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0.5, coverage: 0.5)
        paint.paint(into: ctx, frame: vFrame, state: PaintControlState(isPressed: true))

        // 1. track, 2. knob, 3. pressed overlay
        #expect(ctx.calls.count == 3)
        if case let .fillRoundedRect(_, _, color) = ctx.calls.last {
            #expect(color == MacColors.pressedOverlay)
        } else {
            Issue.record("Expected pressed overlay as the final call")
        }
    }
    
    @Test("Z-order: track is behind knob")
    func zOrder() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0, coverage: 1)
        paint.paint(into: ctx, frame: vFrame, state: .normal)
        
        #expect(ctx.calls.count == 2)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color == MacColors.scrollerTrack)
        }
        if case let .fillRoundedRect(_, _, color) = ctx.calls[1] {
            #expect(color == MacColors.scrollerKnob)
        }
    }
}
