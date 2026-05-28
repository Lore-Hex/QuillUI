import Foundation
import Testing
@testable import QuillPaint

@Suite("MacSpinnerPaint rendering")
struct MacSpinnerPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: MacMetrics.Spinner.regularSize, height: MacMetrics.Spinner.regularSize)

    @Test("Normal state draws 12 spokes with varying opacity")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacSpinnerPaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 12)
        
        // Verify a sample spoke (e.g., the first one at 12 o'clock)
        guard ctx.calls.count == 12 else { return }
        
        if case let .strokeLine(start, end, color, lineWidth) = ctx.calls[0] {
            let center = PaintPoint(x: frame.midX, y: frame.midY)
            let inner = MacMetrics.Spinner.innerRadius
            let outer = inner + MacMetrics.Spinner.spokeLength
            
            // 12 o'clock is -pi/2
            #expect(abs(start.x - (center.x + cos(-Double.pi / 2) * inner)) < 0.0001)
            #expect(abs(start.y - (center.y + sin(-Double.pi / 2) * inner)) < 0.0001)
            #expect(abs(end.x - (center.x + cos(-Double.pi / 2) * outer)) < 0.0001)
            #expect(abs(end.y - (center.y + sin(-Double.pi / 2) * outer)) < 0.0001)
            
            #expect(color == PaintColor(red: 0, green: 0, blue: 0, alpha: 1.0))
            #expect(lineWidth == MacMetrics.Spinner.spokeWidth)
        } else {
            Issue.record("Expected first call to be strokeLine, got \(ctx.calls[0])")
        }

        // Verify the fade trail (Spoke 1 is at 1 o'clock)
        if case let .strokeLine(_, _, color, _) = ctx.calls[1] {
            #expect(abs(color.alpha - 0.85) < 0.0001)
        }
        
        // Spoke 6 is at 6 o'clock
        if case let .strokeLine(_, _, color, _) = ctx.calls[6] {
            #expect(abs(color.alpha - 0.10) < 0.0001)
        }
    }

    @Test("Disabled state dims all spokes")
    func disabledState() {
        let ctx = RecordingPaintContext()
        MacSpinnerPaint().paint(into: ctx, frame: frame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.count == 12)
        guard ctx.calls.count == 12 else { return }

        if case let .strokeLine(_, _, color, _) = ctx.calls[0] {
            #expect(abs(color.alpha - 0.5) < 0.0001) // 1.0 * 0.5
        }
        
        if case let .strokeLine(_, _, color, _) = ctx.calls[1] {
            #expect(abs(color.alpha - (0.85 * 0.5)) < 0.0001)
        }
    }
}
