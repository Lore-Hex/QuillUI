import Foundation
import Testing
@testable import QuillPaint

@Suite("MacSegmentedControlPaint rendering")
struct MacSegmentedControlPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 150, height: 22)

    @Test("Normal state: 3 segments, first selected")
    func normalStateFirstSelected() {
        let ctx = RecordingPaintContext()
        let paint = MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 0)
        paint.paint(into: ctx, frame: frame, state: .normal)

        // 1. Background fill
        // 2. Outer border stroke
        // 3. Segment 0 selection fill
        // 4. Separator between 1 and 2
        // 5. Label "One"
        // 6. Label "Two"
        // 7. Label "Three"
        #expect(ctx.calls.count == 7)

        // Background
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.SegmentedControl.cornerRadius)
            #expect(color == MacColors.control)
        } else {
            Issue.record("Expected background fill")
        }

        // Outer border
        if case let .strokeRoundedRect(rect, radius, color, _) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.SegmentedControl.cornerRadius)
            #expect(color == MacColors.separator)
        } else {
            Issue.record("Expected outer border stroke")
        }

        // Selection fill (Segment 0)
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[2] {
            let segmentWidth = 150.0 / 3.0
            // Inset by 1
            let expectedRect = PaintRect(x: 1, y: 1, width: segmentWidth - 2, height: 20)
            #expect(rect == expectedRect)
            #expect(radius == MacMetrics.SegmentedControl.cornerRadius - 1)
            #expect(color == MacColors.controlBackground)
        } else {
            Issue.record("Expected selection fill")
        }

        // Separator between 1 and 2
        if case let .strokeLine(from, _, color, _) = ctx.calls[3] {
            #expect(from.x == 100.0)
            #expect(color == MacColors.separator)
        } else {
            Issue.record("Expected separator")
        }
    }

    @Test("Normal state: 3 segments, middle selected")
    func normalStateMiddleSelected() {
        let ctx = RecordingPaintContext()
        let paint = MacSegmentedControlPaint(segments: ["One", "Two", "Three"], selectedIndex: 1)
        paint.paint(into: ctx, frame: frame, state: .normal)

        // 1. Background fill
        // 2. Outer border stroke
        // 3. Segment 1 selection fill
        // 4. Label "One"
        // 5. Label "Two"
        // 6. Label "Three"
        // (Separators are hidden because they are adjacent to selected segment)
        #expect(ctx.calls.count == 6)
    }

    @Test("Focused state draws focus ring first")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let paint = MacSegmentedControlPaint(segments: ["A", "B"], selectedIndex: 0)
        paint.paint(into: ctx, frame: frame, state: PaintControlState(isFocused: true))

        #expect(ctx.calls.count > 0)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, _, color, _) = first {
            let outset = MacMetrics.FocusRing.outset
            #expect(rect == frame.insetBy(dx: -outset, dy: -outset))
            #expect(color == MacColors.focusRing)
        } else {
            Issue.record("Expected focus ring as first call")
        }
    }

    @Test("Disabled state uses dimmed colors")
    func disabledState() {
        let ctx = RecordingPaintContext()
        let paint = MacSegmentedControlPaint(segments: ["One"], selectedIndex: 0)
        paint.paint(into: ctx, frame: frame, state: PaintControlState(isDisabled: true))

        // Background should be dimmed (alpha 0.5)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.red == MacColors.control.red)
            #expect(color.alpha == 0.5)
        }

        // Selection fill should be dimmed
        if case let .fillRoundedRect(_, _, color) = ctx.calls[2] {
            #expect(color.alpha == 0.5)
        }

        // Label should be disabled color
        if case let .drawText(_, _, _, color) = ctx.calls.last {
            #expect(color == MacColors.disabledControlText)
        }
    }

    @Test("Default state uses accented selection")
    func accentedSelection() {
        let ctx = RecordingPaintContext()
        let paint = MacSegmentedControlPaint(segments: ["One"], selectedIndex: 0)
        paint.paint(into: ctx, frame: frame, state: PaintControlState(isDefault: true))

        // Selection fill (3rd call) should be accent color
        if case let .fillRoundedRect(_, _, color) = ctx.calls[2] {
            #expect(color == MacColors.accent)
        } else {
            Issue.record("Expected accented selection fill")
        }

        // Label should be default text color
        if case let .drawText(_, _, _, color) = ctx.calls.last {
            #expect(color == MacColors.defaultButtonText)
        }
    }
}
