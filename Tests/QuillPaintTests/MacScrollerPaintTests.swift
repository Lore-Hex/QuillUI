import Foundation
import Testing
@testable import QuillPaint

@Suite("MacScrollerPaint overlay rendering")
struct MacScrollerPaintTests {
    private let verticalFrame = PaintRect(x: 0, y: 0, width: 12, height: 100)

    @Test("Normal state draws track behind knob")
    func normalStateZOrder() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0.5, coverage: 0.25)
        paint.paint(into: ctx, frame: verticalFrame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        if case let .fillRoundedRect(rect, _, color) = ctx.calls[0] {
            #expect(rect == verticalFrame.insetBy(
                dx: MacMetrics.Scroller.trackInset,
                dy: MacMetrics.Scroller.trackInset
            ))
            #expect(color == MacColors.scrollerTrack)
        } else {
            Issue.record("Expected first call to be scroller track fill, got \(ctx.calls[0])")
        }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            #expect(rect == PaintRect(x: 3, y: 38, width: 6, height: 24))
            #expect(radius == MacMetrics.Scroller.knobCornerRadius)
            #expect(color == MacColors.scrollerKnob)
        } else {
            Issue.record("Expected second call to be scroller knob fill, got \(ctx.calls[1])")
        }
    }

    @Test("Progress and coverage are clamped before positioning")
    func progressAndCoverageClamp() {
        let track = verticalFrame.insetBy(
            dx: MacMetrics.Scroller.trackInset,
            dy: MacMetrics.Scroller.trackInset
        )

        let overMax = MacScrollerPaint.knobRect(
            orientation: .vertical,
            track: track,
            progress: 2,
            coverage: 0.5,
            state: .normal
        )
        #expect(overMax == PaintRect(x: 3, y: 50, width: 6, height: 48))

        let underMin = MacScrollerPaint.knobRect(
            orientation: .vertical,
            track: track,
            progress: -1,
            coverage: -0.2,
            state: .normal
        )
        #expect(underMin == PaintRect(x: 3, y: 2, width: 6, height: 24))
    }

    @Test("Horizontal geometry mirrors vertical geometry")
    func orientationSymmetry() {
        let verticalTrack = PaintRect(x: 0, y: 0, width: 12, height: 100).insetBy(
            dx: MacMetrics.Scroller.trackInset,
            dy: MacMetrics.Scroller.trackInset
        )
        let horizontalTrack = PaintRect(x: 0, y: 0, width: 100, height: 12).insetBy(
            dx: MacMetrics.Scroller.trackInset,
            dy: MacMetrics.Scroller.trackInset
        )

        let vertical = MacScrollerPaint.knobRect(
            orientation: .vertical,
            track: verticalTrack,
            progress: 0.25,
            coverage: 0.4,
            state: .normal
        )
        let horizontal = MacScrollerPaint.knobRect(
            orientation: .horizontal,
            track: horizontalTrack,
            progress: 0.25,
            coverage: 0.4,
            state: .normal
        )

        expectApproximatelyEqual(horizontal.origin.x, vertical.origin.y)
        expectApproximatelyEqual(horizontal.origin.y, vertical.origin.x)
        expectApproximatelyEqual(horizontal.size.width, vertical.size.height)
        expectApproximatelyEqual(horizontal.size.height, vertical.size.width)
    }

    @Test("Hovered and pressed states thicken the knob")
    func interactionStatesExpandKnob() {
        let track = verticalFrame.insetBy(
            dx: MacMetrics.Scroller.trackInset,
            dy: MacMetrics.Scroller.trackInset
        )
        let normal = MacScrollerPaint.knobRect(
            orientation: .vertical,
            track: track,
            progress: 0,
            coverage: 0.5,
            state: .normal
        )
        let hovered = MacScrollerPaint.knobRect(
            orientation: .vertical,
            track: track,
            progress: 0,
            coverage: 0.5,
            state: PaintControlState(isHovered: true)
        )
        let pressedColor = MacScrollerPaint.knobColor(for: PaintControlState(isPressed: true))

        #expect(hovered.size.width == normal.size.width + MacMetrics.Scroller.hoveredKnobExpansion)
        #expect(pressedColor.alpha > MacColors.scrollerKnob.alpha)
    }

    @Test("Disabled state hides the scroller entirely")
    func disabledHidesScroller() {
        let ctx = RecordingPaintContext()
        let paint = MacScrollerPaint(orientation: .vertical, progress: 0.5, coverage: 0.25)
        paint.paint(into: ctx, frame: verticalFrame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.isEmpty)
    }

    private func expectApproximatelyEqual(
        _ actual: Double,
        _ expected: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(actual - expected) < 0.000_001, sourceLocation: sourceLocation)
    }
}
