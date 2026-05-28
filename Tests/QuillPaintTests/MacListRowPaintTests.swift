import Foundation
import Testing
@testable import QuillPaint

@Suite("MacListRowPaint chrome rendering")
struct MacListRowPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 220, height: 44)

    @Test("Normal row draws a 6 point rounded background")
    func normalRowChrome() {
        let ctx = RecordingPaintContext()
        MacListRowPaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 1)
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls.first {
            #expect(rect == frame)
            #expect(radius == MacMetrics.ListRow.cornerRadius)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected normal list row to draw a rounded fill")
        }
    }

    @Test("Selected row uses accent fill and white text tokens")
    func selectedRowChrome() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isSelected: true)
        MacListRowPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 1)
        if case let .fillRoundedRect(_, radius, color) = ctx.calls.first {
            #expect(radius == MacMetrics.ListRow.cornerRadius)
            #expect(color == MacColors.accent)
        } else {
            Issue.record("Expected selected list row to draw a rounded accent fill")
        }

        #expect(MacListRowPaint.primaryTextColor(for: state) == MacColors.defaultButtonText)
        #expect(MacListRowPaint.secondaryTextColor(for: state) == MacColors.defaultButtonText)
    }

    @Test("Hovered row applies the shared 6 percent black overlay")
    func hoveredRowOverlay() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isHovered: true)
        MacListRowPaint().paint(into: ctx, frame: frame, state: state)

        #expect(MacColors.hoveredOverlay.alpha == 0.06)
        #expect(ctx.calls.count == 2)
        if case let .fillRoundedRect(_, radius, color) = ctx.calls.last {
            #expect(radius == MacMetrics.ListRow.cornerRadius)
            #expect(color == MacColors.hoveredOverlay)
        } else {
            Issue.record("Expected hover overlay as the final list-row draw call")
        }

        let effective = MacListRowPaint.effectiveFillColor(for: state)
        #expect(abs(effective.red - 0.94) < 0.0001)
        #expect(abs(effective.green - 0.94) < 0.0001)
        #expect(abs(effective.blue - 0.94) < 0.0001)
        #expect(effective.alpha == 1)
    }

    @Test("Selected row suppresses hover overlay")
    func selectedSuppressesHoverOverlay() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isHovered: true, isSelected: true)
        MacListRowPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 1)
        if case let .fillRoundedRect(_, _, color) = ctx.calls.first {
            #expect(color == MacColors.accent)
        }
    }
}
