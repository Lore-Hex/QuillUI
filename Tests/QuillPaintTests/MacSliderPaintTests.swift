import Foundation
import Testing
@testable import QuillPaint

@Suite("MacSliderPaint rendering")
struct MacSliderPaintTests {
    private let horizontalFrame = PaintRect(x: 0, y: 0, width: 100, height: 22)
    private let verticalFrame = PaintRect(x: 0, y: 0, width: 22, height: 100)

    @Test("Horizontal mid-progress positions correctly")
    func horizontalMid() {
        let ctx = RecordingPaintContext()
        let paint = MacSliderPaint(orientation: .horizontal, progress: 0.5)
        paint.paint(into: ctx, frame: horizontalFrame, state: .normal)

        // Expect: 1. track fill, 2. knob fill, 3. knob border
        #expect(ctx.calls.count == 3)
        guard ctx.calls.count == 3 else { return }

        // 1. Track
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect.size.height == MacMetrics.Slider.trackThickness)
            #expect(rect.midY == horizontalFrame.midY)
            #expect(rect.size.width == 100 - MacMetrics.Slider.knobDiameter)
            #expect(radius == MacMetrics.Slider.trackCornerRadius)
            #expect(color == MacColors.sliderTrack)
        } else {
            Issue.record("Expected track fill, got \(ctx.calls[0])")
        }

        // 2. Knob Fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            #expect(rect.midX == horizontalFrame.midX)
            #expect(rect.midY == horizontalFrame.midY)
            #expect(rect.size.width == MacMetrics.Slider.knobDiameter)
            #expect(radius == MacMetrics.Slider.knobDiameter / 2)
            #expect(color == MacColors.sliderKnobFill)
        } else {
            Issue.record("Expected knob fill, got \(ctx.calls[1])")
        }
    }

    @Test("Vertical orientation mirrors horizontal positioning")
    func verticalMid() {
        let ctx = RecordingPaintContext()
        let paint = MacSliderPaint(orientation: .vertical, progress: 0.5)
        paint.paint(into: ctx, frame: verticalFrame, state: .normal)

        #expect(ctx.calls.count == 3)
        guard ctx.calls.count == 3 else { return }

        // 1. Track
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[0] {
            #expect(rect.size.width == MacMetrics.Slider.trackThickness)
            #expect(rect.midX == verticalFrame.midX)
            #expect(rect.size.height == 100 - MacMetrics.Slider.knobDiameter)
        }

        // 2. Knob Fill
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            #expect(rect.midX == verticalFrame.midX)
            #expect(rect.midY == verticalFrame.midY)
            #expect(rect.size.height == MacMetrics.Slider.knobDiameter)
        }
    }

    @Test("Focused state adds focus ring around knob")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let paint = MacSliderPaint(orientation: .horizontal, progress: 0.5)
        paint.paint(into: ctx, frame: horizontalFrame, state: PaintControlState(isFocused: true))

        // Expect: 1. track fill, 2. focus ring, 3. knob fill, 4. knob border
        #expect(ctx.calls.count == 4)
        guard ctx.calls.count == 4 else { return }

        if case let .strokeRoundedRect(rect, radius, color, width) = ctx.calls[1] {
            let knobDiameter = MacMetrics.Slider.knobDiameter
            let outset = MacMetrics.Slider.focusRingOutset
            #expect(rect.size.width == knobDiameter + 2 * outset)
            #expect(radius == (knobDiameter + 2 * outset) / 2)
            #expect(color == MacColors.focusRing)
            #expect(width == MacMetrics.FocusRing.lineWidth)
        } else {
            Issue.record("Expected focus ring stroke, got \(ctx.calls[1])")
        }
    }

    @Test("Disabled state uses translucent colors")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let paint = MacSliderPaint(orientation: .horizontal, progress: 0.5)
        paint.paint(into: ctx, frame: horizontalFrame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.count == 3)
        guard ctx.calls.count == 3 else { return }

        // Track color
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha < MacColors.sliderTrack.alpha)
        }

        // Knob fill color
        if case let .fillRoundedRect(_, _, color) = ctx.calls[1] {
            #expect(color.alpha < 1.0)
        }
    }

    @Test("Progress is clamped to [0, 1]")
    func progressClamping() {
        let ctx = RecordingPaintContext()
        
        let over = MacSliderPaint(orientation: .horizontal, progress: 1.5)
        over.paint(into: ctx, frame: horizontalFrame, state: .normal)
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            #expect(rect.maxX == horizontalFrame.maxX)
        }
        
        ctx.reset()
        let under = MacSliderPaint(orientation: .horizontal, progress: -0.5)
        under.paint(into: ctx, frame: horizontalFrame, state: .normal)
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            #expect(rect.minX == horizontalFrame.minX)
        }
    }
}
