import Foundation
import Testing
@testable import QuillPaint

@Suite("MacWindowChromePaint rendering")
struct MacWindowChromePaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 400, height: 28)

    @Test("Focused state: background, border, and colored traffic lights")
    func focusedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true)
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: state)

        // Calls expected:
        // 1. fillRect (background)
        // 2. strokeLine (bottom border)
        // 3. fillRoundedRect (close)
        // 4. fillRoundedRect (minimize)
        // 5. fillRoundedRect (maximize)
        #expect(ctx.calls.count == 5)
        guard ctx.calls.count == 5 else { return }

        // Verify background
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(radius == 0)
            #expect(color == MacColors.windowChromeBackground)
        } else {
            Issue.record("Expected first call to be background fill, got \(ctx.calls[0])")
        }

        // Verify colored traffic lights
        let closeColor: PaintColor? = {
            if case let .fillRoundedRect(_, _, color) = ctx.calls[2] { return color }
            return nil
        }()
        #expect(closeColor == MacColors.windowCloseRed)

        let minimizeColor: PaintColor? = {
            if case let .fillRoundedRect(_, _, color) = ctx.calls[3] { return color }
            return nil
        }()
        #expect(minimizeColor == MacColors.windowMinimizeYellow)

        let maximizeColor: PaintColor? = {
            if case let .fillRoundedRect(_, _, color) = ctx.calls[4] { return color }
            return nil
        }()
        #expect(maximizeColor == MacColors.windowMaximizeGreen)
    }

    @Test("Unfocused state: background, border, and grey traffic lights")
    func unfocusedState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: false)
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: state)

        #expect(ctx.calls.count == 5)
        
        let unfocusedColor = MacColors.windowChromeUnfocusedDot
        for i in 2...4 {
            if case let .fillRoundedRect(_, _, color) = ctx.calls[i] {
                #expect(color == unfocusedColor)
            } else {
                Issue.record("Expected traffic light fill at index \(i)")
            }
        }
    }

    @Test("Hovering traffic lights draws glyphs")
    func hoveringTrafficLights() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isHoveringTrafficLights: true)
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: state)

        // Previous 5 calls + glyph calls:
        // Close: 2 lines
        // Minimize: 1 line
        // Maximize: 2 lines
        // Total: 5 + 2 + 1 + 2 = 10 calls
        #expect(ctx.calls.count == 10)
        
        // Check that some strokeLines were called after the traffic light fills
        var strokeLineCount = 0
        for call in ctx.calls {
            if case .strokeLine = call {
                strokeLineCount += 1
            }
        }
        // 1 for border, 5 for glyphs = 6
        #expect(strokeLineCount == 6)
    }

    @Test("Title stub draws an extra fill call")
    func titleStub() {
        let ctx = RecordingPaintContext()
        MacWindowChromePaint(title: "My Window").paint(into: ctx, frame: frame, state: .normal)

        // 1 (bg) + 1 (border) + 3 (lights) + 1 (title stub) = 6 calls
        #expect(ctx.calls.count == 6)
        
        if case let .fillRoundedRect(_, radius, color) = ctx.calls.last {
            #expect(radius == 2)
            #expect(color == MacColors.separator)
        } else {
            Issue.record("Expected title stub fill as last call")
        }
    }
}
