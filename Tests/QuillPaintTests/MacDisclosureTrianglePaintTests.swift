import Foundation
import Testing
@testable import QuillPaint

@Suite("MacDisclosureTrianglePaint rendering")
struct MacDisclosureTrianglePaintTests {
    private let frame = PaintRect(
        x: 0,
        y: 0,
        width: MacMetrics.DisclosureTriangle.regularSize,
        height: MacMetrics.DisclosureTriangle.regularSize
    )

    @Test("Collapsed state draws a centered right-pointing chevron")
    func collapsedState() {
        let ctx = RecordingPaintContext()
        MacDisclosureTrianglePaint(isExpanded: false).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        let glyphFrame = MacDisclosureTrianglePaint.collapsedGlyphFrame(in: frame)
        let top = PaintPoint(x: glyphFrame.minX, y: glyphFrame.minY)
        let mid = PaintPoint(x: glyphFrame.maxX, y: glyphFrame.midY)
        let bottom = PaintPoint(x: glyphFrame.minX, y: glyphFrame.maxY)

        if case let .strokeLine(from, to, color, lineWidth) = ctx.calls[0] {
            #expect(from == top)
            #expect(to == mid)
            #expect(color == MacColors.disclosureTriangle)
            #expect(lineWidth == MacMetrics.DisclosureTriangle.lineWidth)
        } else {
            Issue.record("Expected first call to be collapsed chevron top arm")
        }

        if case let .strokeLine(from, to, color, lineWidth) = ctx.calls[1] {
            #expect(from == mid)
            #expect(to == bottom)
            #expect(color == MacColors.disclosureTriangle)
            #expect(lineWidth == MacMetrics.DisclosureTriangle.lineWidth)
        } else {
            Issue.record("Expected second call to be collapsed chevron bottom arm")
        }
    }

    @Test("Expanded state rotates the glyph into a down-pointing chevron")
    func expandedState() {
        let ctx = RecordingPaintContext()
        MacDisclosureTrianglePaint(isExpanded: true).paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        let glyphFrame = MacDisclosureTrianglePaint.expandedGlyphFrame(in: frame)
        let left = PaintPoint(x: glyphFrame.minX, y: glyphFrame.minY)
        let mid = PaintPoint(x: glyphFrame.midX, y: glyphFrame.maxY)
        let right = PaintPoint(x: glyphFrame.maxX, y: glyphFrame.minY)

        if case let .strokeLine(from, to, color, lineWidth) = ctx.calls[0] {
            #expect(from == left)
            #expect(to == mid)
            #expect(color == MacColors.disclosureTriangle)
            #expect(lineWidth == MacMetrics.DisclosureTriangle.lineWidth)
        } else {
            Issue.record("Expected first call to be expanded chevron left arm")
        }

        if case let .strokeLine(from, to, color, lineWidth) = ctx.calls[1] {
            #expect(from == mid)
            #expect(to == right)
            #expect(color == MacColors.disclosureTriangle)
            #expect(lineWidth == MacMetrics.DisclosureTriangle.lineWidth)
        } else {
            Issue.record("Expected second call to be expanded chevron right arm")
        }
    }

    @Test("Disabled state uses disabled disclosure color")
    func disabledState() {
        let ctx = RecordingPaintContext()
        MacDisclosureTrianglePaint().paint(into: ctx, frame: frame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.count == 2)
        for call in ctx.calls {
            if case let .strokeLine(_, _, color, lineWidth) = call {
                #expect(color == MacColors.disabledDisclosureTriangle)
                #expect(lineWidth == MacMetrics.DisclosureTriangle.lineWidth)
            } else {
                Issue.record("Expected disclosure triangle to draw only strokeLine calls")
            }
        }
    }
}
