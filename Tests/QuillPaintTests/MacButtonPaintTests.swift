import Foundation
import Testing
@testable import QuillPaint

@Suite("MacButtonPaint chrome rendering")
struct MacButtonPaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 80, height: 22)

    @Test("Normal state: fill + border, no focus ring, no overlay")
    func normalState() {
        let ctx = RecordingPaintContext()
        MacButtonPaint().paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 2)
        guard ctx.calls.count == 2 else { return }

        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Button.cornerRadius)
            #expect(color == MacColors.control)
        } else {
            Issue.record("Expected first call to be fillRoundedRect, got \(ctx.calls[0])")
        }

        if case let .strokeRoundedRect(rect, radius, color, lineWidth) = ctx.calls[1] {
            #expect(rect == frame)
            #expect(radius == MacMetrics.Button.cornerRadius)
            #expect(color == MacColors.separator)
            #expect(lineWidth == MacMetrics.Button.borderLineWidth)
        } else {
            Issue.record("Expected second call to be strokeRoundedRect, got \(ctx.calls[1])")
        }
    }

    @Test("Focused state draws focus ring behind chrome")
    func focusedDrawsRingFirst() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3)
        guard let first = ctx.calls.first else { return }
        if case let .strokeRoundedRect(rect, _, color, lineWidth) = first {
            let outset = MacMetrics.Button.focusRingOutset
            let expected = frame.insetBy(dx: -outset, dy: -outset)
            #expect(rect == expected)
            #expect(color == MacColors.focusRing)
            #expect(lineWidth == MacMetrics.Button.focusRingLineWidth)
        } else {
            Issue.record("Expected first call to be the focus ring stroke, got \(first)")
        }
    }

    @Test("Default state uses accent fill and omits border")
    func defaultButtonFillIsAccent() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isDefault: true)
        MacButtonPaint().paint(into: ctx, frame: frame, state: state)

        // Default buttons draw only fill (no border, no overlay since not pressed).
        #expect(ctx.calls.count == 1)
        guard let first = ctx.calls.first else { return }
        if case let .fillRoundedRect(_, _, color) = first {
            #expect(color == MacColors.defaultButtonFill)
        } else {
            Issue.record("Expected default button to draw fillRoundedRect, got \(first)")
        }
    }

    @Test("Pressed state adds darkening overlay on top of chrome")
    func pressedStateOverlay() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true)
        MacButtonPaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 3)
        if case let .fillRoundedRect(_, _, color) = ctx.calls.last {
            #expect(color == MacColors.pressedOverlay)
        } else {
            Issue.record("Expected pressed overlay as the final call, got \(String(describing: ctx.calls.last))")
        }
    }

    @Test("Disabled state suppresses focus ring and pressed overlay")
    func disabledSuppressesAffordances() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true, isFocused: true, isDisabled: true)
        MacButtonPaint().paint(into: ctx, frame: frame, state: state)

        // Disabled draws only the dimmed fill + border. No focus ring, no
        // pressed overlay, no hover overlay.
        #expect(ctx.calls.count == 2)
        for call in ctx.calls {
            switch call {
            case .strokeRoundedRect(_, _, MacColors.focusRing, _):
                Issue.record("Disabled buttons must not draw a focus ring")
            case .fillRoundedRect(_, _, MacColors.pressedOverlay):
                Issue.record("Disabled buttons must not draw a pressed overlay")
            default:
                continue
            }
        }
    }

    @Test("Hover overlay only fires when not pressed and not disabled")
    func hoverOverlay() {
        let ctx = RecordingPaintContext()
        MacButtonPaint().paint(into: ctx, frame: frame, state: PaintControlState(isHovered: true))
        #expect(ctx.calls.count == 3)
        if case let .fillRoundedRect(_, _, color) = ctx.calls.last {
            #expect(color == MacColors.hoveredOverlay)
        } else {
            Issue.record("Expected hover overlay as the final call")
        }
    }

    @Test("Pressed + hover: pressed overlay wins, hover suppressed")
    func pressedSuppressesHover() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isPressed: true, isHovered: true)
        MacButtonPaint().paint(into: ctx, frame: frame, state: state)
        #expect(ctx.calls.count == 3)
        if case let .fillRoundedRect(_, _, color) = ctx.calls.last {
            #expect(color == MacColors.pressedOverlay)
        }
    }
}

@Suite("PaintRect geometry helpers")
struct PaintRectTests {
    @Test("insetBy shrinks rect symmetrically")
    func insetByShrinks() {
        let rect = PaintRect(x: 10, y: 20, width: 100, height: 50)
        let inset = rect.insetBy(dx: 5, dy: 2)
        #expect(inset == PaintRect(x: 15, y: 22, width: 90, height: 46))
    }

    @Test("Negative inset grows rect (used for focus ring outset)")
    func negativeInsetGrows() {
        let rect = PaintRect(x: 10, y: 10, width: 20, height: 20)
        let grown = rect.insetBy(dx: -3, dy: -3)
        #expect(grown == PaintRect(x: 7, y: 7, width: 26, height: 26))
    }

    @Test("min/max/mid accessors")
    func extents() {
        let rect = PaintRect(x: 10, y: 20, width: 100, height: 50)
        #expect(rect.minX == 10)
        #expect(rect.minY == 20)
        #expect(rect.maxX == 110)
        #expect(rect.maxY == 70)
        #expect(rect.midX == 60)
        #expect(rect.midY == 45)
    }
}
