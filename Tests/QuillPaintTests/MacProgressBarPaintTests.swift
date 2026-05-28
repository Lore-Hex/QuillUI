import Foundation
import Testing
@testable import QuillPaint

@Suite("MacProgressBarPaint rendering")
struct MacProgressBarPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 100, height: 6)

    @Test("Empty state: only track")
    func emptyState() {
        let ctx = RecordingPaintContext()
        MacProgressBarPaint(progress: 0).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 1)
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.ProgressBar.cornerRadius)
            #expect(color == MacColors.progressBarTrack)
        } else {
            Issue.record("Expected track fill, got \(ctx.calls[0])")
        }
    }

    @Test("Half progress: track + half fill")
    func halfProgress() {
        let ctx = RecordingPaintContext()
        MacProgressBarPaint(progress: 0.5).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        
        // Track
        if case let .fillRoundedRect(rect, _, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(color == MacColors.progressBarTrack)
        }

        // Fill
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[1] {
            let expectedFill = PaintRect(x: frame.minX, y: frame.minY, width: 50, height: 6)
            #expect(rect == expectedFill)
            #expect(radius == MacMetrics.ProgressBar.cornerRadius)
            #expect(color == MacColors.progressBarFill)
        } else {
            Issue.record("Expected fill, got \(ctx.calls[1])")
        }
    }

    @Test("Full progress: track + full fill")
    func fullProgress() {
        let ctx = RecordingPaintContext()
        MacProgressBarPaint(progress: 1.0).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        if case let .fillRoundedRect(rect, _, _) = ctx.calls[1] {
            #expect(rect == frame)
        }
    }

    @Test("Disabled state: dimmed track and fill")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDisabled: true)
        MacProgressBarPaint(progress: 0.5).paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 2)
        
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha == MacColors.progressBarTrack.alpha * 0.5)
        }
        
        if case let .fillRoundedRect(_, _, color) = ctx.calls[1] {
            #expect(color.alpha == MacColors.progressBarFill.alpha * 0.5)
        }
    }
}
