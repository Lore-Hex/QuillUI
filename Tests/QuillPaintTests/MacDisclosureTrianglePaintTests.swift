import Foundation
import Testing
@testable import QuillPaint

@Suite("MacDisclosureTrianglePaint rendering")
struct MacDisclosureTrianglePaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 13, height: 13)

    @Test("Collapsed state: points right")
    func collapsedPointsRight() {
        let ctx = RecordingPaintContext()
        MacDisclosureTrianglePaint(isExpanded: false).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 1)
        guard let first = ctx.calls.first else { return }

        if case let .fillPolygon(points, color) = first {
            #expect(color == MacColors.secondaryLabel)
            #expect(points.count == 3)
            
            // Should be centered vertically and have a vertical left edge.
            let leftEdgeX = points[0].x
            #expect(points[1].x == leftEdgeX)
            #expect(points[2].x > leftEdgeX) // Vertex to the right
            #expect(points[2].y == frame.midY) // Vertex centered vertically
        } else {
            Issue.record("Expected fillPolygon call, got \(first)")
        }
    }

    @Test("Expanded state: points down")
    func expandedPointsDown() {
        let ctx = RecordingPaintContext()
        MacDisclosureTrianglePaint(isExpanded: true).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 1)
        guard let first = ctx.calls.first else { return }

        if case let .fillPolygon(points, color) = first {
            #expect(color == MacColors.secondaryLabel)
            #expect(points.count == 3)
            
            // Should be centered horizontally and have a horizontal top edge.
            let topEdgeY = points[0].y
            #expect(points[1].y == topEdgeY)
            #expect(points[2].y > topEdgeY) // Vertex below
            #expect(points[2].x == frame.midX) // Vertex centered horizontally
        } else {
            Issue.record("Expected fillPolygon call, got \(first)")
        }
    }

    @Test("Disabled state: uses disabled color")
    func disabledUsesCorrectColor() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDisabled: true)
        MacDisclosureTrianglePaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 1)
        guard let first = ctx.calls.first else { return }

        if case let .fillPolygon(_, color) = first {
            #expect(color == MacColors.disabledControlText)
        } else {
            Issue.record("Expected fillPolygon call, got \(first)")
        }
    }
}
