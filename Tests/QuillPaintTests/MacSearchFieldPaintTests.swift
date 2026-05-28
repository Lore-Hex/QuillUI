import Foundation
import Testing
@testable import QuillPaint

@Suite("MacSearchFieldPaint chrome rendering")
struct MacSearchFieldPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 140, height: 22)

    @Test("Normal state: fill + border + magnifier + placeholder")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacSearchFieldPaint(placeholder: "Search").paint(into: ctx, frame: frame, state: .normal)

        // 1. Fill
        // 2. Border
        // 3. Magnifier Circle
        // 4. Magnifier Handle
        // 5. Placeholder Text
        #expect(ctx.calls.count == 5)
        guard ctx.calls.count == 5 else { return }

        if case let .fillRoundedRect(rect, radius, _) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.SearchField.cornerRadius)
        }

        if case let .strokeRoundedRect(rect, radius, _, _) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.SearchField.cornerRadius)
        }

        // Magnifier circle
        if case .strokeRoundedRect = ctx.calls[2] {
        } else {
            Issue.record("Expected magnifier circle stroke")
        }

        // Magnifier handle
        if case .strokeLine = ctx.calls[3] {
        } else {
            Issue.record("Expected magnifier handle line")
        }

        // Placeholder text
        if case let .drawText(string, _, _, _) = ctx.calls[4] {
            #expect(string == "Search")
        } else {
            Issue.record("Expected placeholder text draw")
        }
    }

    @Test("Focused state draws focus ring behind chrome")
    func focusedDrawsRingFirst() {
        let ctx = RecordingPaintContext()
        MacSearchFieldPaint().paint(into: ctx, frame: frame, state: PaintControlState(isFocused: true))

        #expect(ctx.calls.count == 6)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = first {
            let outset = MacMetrics.FocusRing.outset
            let expected = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(radius == MacMetrics.SearchField.cornerRadius + 2)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.FocusRing.lineWidth)
        } else {
            Issue.record("Expected first call to be the focus ring stroke")
        }
    }

    @Test("Disabled state dims fill, border, and placeholder")
    func disabledDims() {
        let ctx = RecordingPaintContext()
        MacSearchFieldPaint().paint(into: ctx, frame: frame, state: PaintControlState(isDisabled: true))

        #expect(ctx.calls.count == 5)
        // Fill
        if case let .fillRoundedRect(_, _, color) = ctx.calls[0] {
            #expect(color.alpha < 1.0)
        }
        // Placeholder text
        if case let .drawText(_, _, _, color) = ctx.calls[4] {
            #expect(color == MacColors.disabledControlText)
        }
    }

    @Test("Empty placeholder suppresses text draw")
    func emptyPlaceholderSuppressesText() {
        let ctx = RecordingPaintContext()
        MacSearchFieldPaint(placeholder: "").paint(into: ctx, frame: frame, state: .normal)

        // Fill + Border + Circle + Handle (no text)
        #expect(ctx.calls.count == 4)
    }
}
