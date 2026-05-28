import Foundation
import Testing
@testable import QuillPaint

@Suite("MacPopUpButtonPaint chrome rendering")
struct MacPopUpButtonPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 120, height: 22)

    @Test("Normal state: fill + border + indicator, no focus ring, no overlay")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacPopUpButtonPaint().paint(into: ctx, frame: frame, state: .normal)

        // 1. Fill
        // 2. Border
        // 3-6. Indicator (4 lines for up/down arrows)
        #expect(ctx.calls.count == 6)
        
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.PopUpButton.cornerRadius)
            #expect(color == MacColors.control)
        } else {
            Issue.record("Expected first call to be fillRoundedRect")
        }
        
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.PopUpButton.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.PopUpButton.borderLineWidth)
        } else {
            Issue.record("Expected second call to be strokeRoundedRect")
        }
    }

    @Test("Focused state draws focus ring behind chrome")
    func focusedDrawsRingFirst() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacPopUpButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 7)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, _, color, lineWidth) = first {
            let outset = MacMetrics.PopUpButton.focusRingOutset
            let expected = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.PopUpButton.focusRingLineWidth)
        } else {
            Issue.record("Expected first call to be focus ring")
        }
    }

    @Test("Pressed state adds darkening overlay on top of chrome")
    func pressedStateOverlay() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true)
        MacPopUpButtonPaint().paint(into: ctx, frame: frame, state: state)

        // Fill, Border, Overlay, Indicator (4 lines) = 7 calls
        #expect(ctx.calls.count == 7)
        if case let .fillRoundedRect(_, _, color) = ctx.calls[2] {
            #expect(color == MacColors.pressedOverlay)
        } else {
            Issue.record("Expected third call to be pressed overlay")
        }
    }

    @Test("Labeled pop-up button draws leading control text")
    func labeledPopUpButtonDrawsText() {
        let ctx = RecordingPaintContext()
        MacPopUpButtonPaint(label: "Selection").paint(into: ctx, frame: frame, state: .normal)

        // Fill, Border, Text, Indicator (4 lines) = 7 calls
        #expect(ctx.calls.count == 7)
        let textCall = ctx.calls[2]
        if case let .drawText(string, point, font, color) = textCall {
            let size = PaintTextMetrics.measure("Selection", font: MacFonts.controlLabel)
            let expected = PaintPoint(
                x: frame.minX + MacMetrics.PopUpButton.labelLeadingPadding,
                y: frame.midY - size.height / 2 + MacMetrics.PopUpButton.labelVerticalOpticalOffset
            )
            #expect(string == "Selection")
            #expect(point == expected)
            #expect(font == MacFonts.controlLabel)
            #expect(color == MacColors.controlText)
        } else {
            Issue.record("Expected third call to be drawText")
        }
    }

    @Test("Indicator geometry check")
    func indicatorGeometry() {
        let ctx = RecordingPaintContext()
        MacPopUpButtonPaint().paint(into: ctx, frame: frame, state: .normal)
        
        // 0: fill, 1: border, 2-5: indicator.
        #expect(ctx.calls.count == 6)
        
        let indicatorColor = MacColors.controlText
        let centerX = frame.maxX - MacMetrics.PopUpButton.indicatorTrailingPadding
        let centerY = frame.midY
        let halfWidth = MacMetrics.PopUpButton.chevronWidth / 2
        let halfHeight = MacMetrics.PopUpButton.chevronHeight / 2
        let spacing = MacMetrics.PopUpButton.chevronSpacing / 2
        
        // Up arrow left stroke: call 2
        if case let .strokeLine(from, to, color, width) = ctx.calls[2] {
            let upCenterY = centerY - spacing - halfHeight
            #expect(from == PaintPoint(x: centerX - halfWidth, y: upCenterY + halfHeight))
            #expect(to == PaintPoint(x: centerX, y: upCenterY - halfHeight))
            #expect(color == indicatorColor)
            #expect(width == MacMetrics.PopUpButton.chevronLineWidth)
        } else {
            Issue.record("Expected call 2 to be up-arrow stroke")
        }
    }
}
