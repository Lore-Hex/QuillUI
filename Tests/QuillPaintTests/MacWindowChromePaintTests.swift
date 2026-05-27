import Foundation
import Testing
@testable import QuillPaint

@Suite("MacWindowChromePaint chrome rendering")
struct MacWindowChromePaintTests {
    private let frame = PaintRect(x: 10, y: 5, width: 240, height: 28)

    @Test("Window chrome metric and color tokens match regular macOS titlebars")
    func metricAndColorTokens() {
        #expect(MacMetrics.WindowChrome.titlebarHeight == 28)
        #expect(MacMetrics.WindowChrome.trafficLightDiameter == 12)
        #expect(MacMetrics.WindowChrome.horizontalPadding == 20)
        #expect(MacMetrics.WindowChrome.buttonSpacing == 8)

        #expect(MacColors.windowCloseRed == PaintColor(r: 255, g: 95, b: 87))
        #expect(MacColors.windowMinimizeYellow == PaintColor(r: 254, g: 188, b: 46))
        #expect(MacColors.windowMaximizeGreen == PaintColor(r: 40, g: 200, b: 64))
    }

    @Test("Focused state draws background, colored traffic lights, and bottom hairline")
    func focusedTrafficLights() {
        let ctx = RecordingPaintContext()
        MacWindowChromePaint().paint(
            into: ctx,
            frame: frame,
            state: PaintControlState(isFocused: true)
        )

        #expect(ctx.calls.count == 5)
        guard ctx.calls.count == 5 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == 0)
            #expect(color == MacColors.windowChromeBackground)
        } else {
            Issue.record("Expected titlebar background fill, got \(ctx.calls[0])")
        }

        let expectedFrames = [
            PaintRect(x: 30, y: 13, width: 12, height: 12),
            PaintRect(x: 50, y: 13, width: 12, height: 12),
            PaintRect(x: 70, y: 13, width: 12, height: 12)
        ]
        let expectedColors = [
            MacColors.windowCloseRed,
            MacColors.windowMinimizeYellow,
            MacColors.windowMaximizeGreen
        ]

        for index in 0..<3 {
            if case let .fillRoundedRect(rect, radius, color) = ctx.calls[index + 1] {
                #expect(rect == expectedFrames[index])
                #expect(radius == MacMetrics.WindowChrome.trafficLightDiameter / 2)
                #expect(color == expectedColors[index])
            } else {
                Issue.record("Expected traffic-light fill at call \(index + 1), got \(ctx.calls[index + 1])")
            }
        }

        if case let .strokeLine(start, end, color, lineWidth) = ctx.calls[4] {
            #expect(start == PaintPoint(x: frame.minX, y: frame.maxY - 0.5))
            #expect(end == PaintPoint(x: frame.maxX, y: frame.maxY - 0.5))
            #expect(color == MacColors.windowChromeBorderBottom)
            #expect(lineWidth == MacMetrics.WindowChrome.borderLineWidth)
        } else {
            Issue.record("Expected bottom border hairline, got \(ctx.calls[4])")
        }
    }

    @Test("Unfocused state draws flat grey traffic-light dots")
    func unfocusedTrafficLightsAreGrey() {
        let ctx = RecordingPaintContext()
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 5)
        for call in ctx.calls[1...3] {
            if case let .fillRoundedRect(_, _, color) = call {
                #expect(color == MacColors.windowChromeUnfocusedDot)
            } else {
                Issue.record("Expected unfocused traffic-light dot, got \(call)")
            }
        }
    }

    @Test("Hovering traffic lights draws close, minimize, and maximize glyph strokes")
    func hoveringTrafficLightsDrawsGlyphs() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isHoveringTrafficLights: true)
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 10)
        let glyphCalls = ctx.calls.compactMap { call -> (PaintPoint, PaintPoint, PaintColor, Double)? in
            if case let .strokeLine(start, end, color, lineWidth) = call,
               color == MacWindowChromePaint.trafficLightGlyphColor {
                return (start, end, color, lineWidth)
            }
            return nil
        }

        #expect(glyphCalls.count == 5)
        for glyph in glyphCalls {
            #expect(glyph.2 == MacWindowChromePaint.trafficLightGlyphColor)
            #expect(glyph.3 == MacMetrics.WindowChrome.trafficLightGlyphLineWidth)
        }
    }

    @Test("Title paints a centered placeholder region until text rendering lands")
    func titlePaintsCenteredStub() {
        let ctx = RecordingPaintContext()
        MacWindowChromePaint(title: "QuillUI").paint(
            into: ctx,
            frame: frame,
            state: PaintControlState(isFocused: true)
        )

        #expect(ctx.calls.count == 6)
        guard ctx.calls.count == 6 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[4] {
            #expect(rect == MacWindowChromePaint.titleStubFrame(in: frame))
            #expect(radius == MacMetrics.WindowChrome.titleStubCornerRadius)
            #expect(color == MacWindowChromePaint.titleStubColor)
        } else {
            Issue.record("Expected centered title placeholder as call 4, got \(ctx.calls[4])")
        }
    }
}
