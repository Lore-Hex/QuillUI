import Foundation
import Testing
@testable import QuillPaint

@Suite("MacSwitchPaint rendering")
struct MacSwitchPaintTests {
    private let frame = PaintRect(
        x: 0,
        y: 0,
        width: MacMetrics.Switch.width,
        height: MacMetrics.Switch.height
    )

    @Test("Off state: pill background + border + knob on left")
    func offState() {
        let ctx = RecordingPaintContext()
        MacSwitchPaint(isOn: false).paint(into: ctx, frame: frame, state: .normal)

        // Expected calls:
        // 1. Pill fill (white)
        // 2. Pill border (separator)
        // 3. Knob fill (white)
        // 4. Knob border (subtle grey)
        #expect(ctx.calls.count == 4)
        
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Switch.cornerRadius)
            #expect(color == MacColors.controlBackground)
        }
        
        if case let .strokeRoundedRect(rect, _, color, _) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(color == MacColors.separator)
        }
        
        if case let .fillRoundedRect(rect, _, color) = ctx.calls[2] {
            let expectedKnobX = frame.minX + MacMetrics.Switch.knobInset
            #expect(rect.minX == expectedKnobX)
            #expect(rect.size.width == MacMetrics.Switch.knobDiameter)
            #expect(color == PaintColor(r: 255, g: 255, b: 255))
        }
    }

    @Test("On state: accent pill background (no border) + knob on right")
    func onState() {
        let ctx = RecordingPaintContext()
        MacSwitchPaint(isOn: true).paint(into: ctx, frame: frame, state: .normal)

        // Expected calls:
        // 1. Pill fill (accent)
        // 2. Knob fill (white)
        // 3. Knob border (subtle grey)
        #expect(ctx.calls.count == 3)
        
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Switch.cornerRadius)
            #expect(color == MacColors.accent)
        }
        
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            let expectedKnobX = frame.maxX - MacMetrics.Switch.knobInset - MacMetrics.Switch.knobDiameter
            #expect(rect.minX == expectedKnobX)
        }
    }

    @Test("Focused state draws focus ring")
    func focusedDrawsRing() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacSwitchPaint(isOn: false).paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 5) // Focus ring + pill fill + pill border + knob fill + knob border
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, _, color, _) = first {
            let outset = MacMetrics.FocusRing.outset
            let expected = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(color == MacColors.focusRing)
        } else {
            Issue.record("Expected focus ring as first call")
        }
    }

    @Test("Disabled state uses dimmed colors")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDisabled: true)
        
        // Test ON disabled
        MacSwitchPaint(isOn: true).paint(into: ctx, frame: frame, state: state)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
            #expect(color.red == MacColors.accent.red)
        }
        
        // Test OFF disabled
        ctx.reset()
        MacSwitchPaint(isOn: false).paint(into: ctx, frame: frame, state: state)
        // Disabled OFF should not have a border (matches button logic where disabled is just fill)
        // Actually my implementation only draws border if !isOn && !isDisabled.
        #expect(ctx.calls.count == 3) // Pill fill + knob fill + knob border
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == 0.5)
            #expect(color.red == MacColors.control.red)
        }
    }
}
