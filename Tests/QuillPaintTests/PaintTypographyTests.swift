import Foundation
import Testing
@testable import QuillPaint

@Suite("QuillPaint Typography")
struct PaintTypographyTests {
    private let frame = PaintRect(x: 0, y: 0, width: 80, height: 22)

    @Test("MacFontResolution returns SF Pro Text by default")
    func fontResolution() {
        #expect(MacFontResolution.bestAvailableFamily == "SF Pro Text")
    }

    @Test("MacFonts are 13pt")
    func fontSizes() {
        #expect(MacFonts.controlLabel.size == 13)
        #expect(MacFonts.controlLabelEmphasized.size == 13)
        #expect(MacFonts.titlebarTitle.size == 13)
    }

    @Test("MacButtonPaint with label calls drawText")
    func labeledButton() {
        let ctx = RecordingPaintContext()
        let label = "OK"
        MacButtonPaint(label: label).paint(into: ctx, frame: frame, state: .normal)

        // Normal button: focus ring(none) + fill + border + text = 3 calls
        #expect(ctx.calls.count == 3)
        
        let lastCall = ctx.calls.last
        if case let .drawText(string, at, font, color) = lastCall {
            #expect(string == label)
            #expect(font == MacFonts.controlLabel)
            #expect(color == MacColors.controlText)
            
            // Center calculation verification (using RecordingPaintContext heuristic)
            // RecordingPaintContext.measureText returns width: label.count * 7 = 14, height: 13
            // midX = 40, midY = 11
            // x = 40 - (14 / 2) = 33
            // y = 11 + (13 / 2) - 1.0 = 11 + 6.5 - 1.0 = 16.5
            #expect(at.x == 33.0)
            #expect(at.y == 16.5)
        } else {
            Issue.record("Expected final call to be drawText, got \(String(describing: lastCall))")
        }
    }

    @Test("Default labeled button uses emphasized font and white color")
    func defaultLabeledButton() {
        let ctx = RecordingPaintContext()
        let label = "OK"
        let state = PaintControlState(isDefault: true)
        MacButtonPaint(label: label).paint(into: ctx, frame: frame, state: state)

        // Default button: fill + text = 2 calls (no border)
        #expect(ctx.calls.count == 2)
        
        if case let .drawText(_, _, font, color) = ctx.calls.last {
            #expect(font == MacFonts.controlLabelEmphasized)
            #expect(color == MacColors.defaultButtonText)
        } else {
            Issue.record("Expected drawText call")
        }
    }

    @Test("Disabled labeled button uses disabled color")
    func disabledLabeledButton() {
        let ctx = RecordingPaintContext()
        let label = "Cancel"
        let state = PaintControlState(isDisabled: true)
        MacButtonPaint(label: label).paint(into: ctx, frame: frame, state: state)

        if case let .drawText(_, _, _, color) = ctx.calls.last {
            #expect(color == MacColors.disabledControlText)
        } else {
            Issue.record("Expected drawText call")
        }
    }
}
