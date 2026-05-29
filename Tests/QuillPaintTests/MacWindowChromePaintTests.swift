import Foundation
import Testing
@testable import QuillPaint

@Suite("MacWindowChromePaint Tests")
struct MacWindowChromePaintTests {
    private let frame = PaintRect(x: 0, y: 0, width: 400, height: MacMetrics.WindowChrome.titlebarHeight)

    @Test("Titlebar geometry and background")
    func titlebarGeometry() {
        let ctx = RecordingPaintContext()
        let chrome = MacWindowChromePaint()
        chrome.paint(into: ctx, frame: frame, state: .normal)

        // 1. Background
        // 2. Bottom border
        // 3. Close dot
        // 4. Minimize dot
        // 5. Maximize dot
        #expect(ctx.calls.count >= 2)
        
        // Verify background fill matches the titlebar height
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls[0] {
            #expect(rect == frame)
            #expect(rect.size.height == MacMetrics.WindowChrome.titlebarHeight)
            #expect(radius == 0)
            #expect(color == MacColors.windowChromeBackground)
        } else {
            Issue.record("First call should be background fill")
        }

        // Verify bottom border
        if case let .strokeLine(start, end, color, width) = ctx.calls[1] {
            #expect(start.y == frame.maxY - 1)
            #expect(end.y == frame.maxY - 1)
            #expect(start.x == frame.minX)
            #expect(end.x == frame.maxX)
            #expect(color == MacColors.windowChromeBorderBottom)
            #expect(width == 1)
        } else {
            Issue.record("Second call should be bottom border stroke")
        }
    }

    @Test("Traffic light geometry (diameter, spacing, positions)")
    func trafficLightGeometry() {
        let ctx = RecordingPaintContext()
        let chrome = MacWindowChromePaint()
        chrome.paint(into: ctx, frame: frame, state: .normal)

        #expect(ctx.calls.count == 5)
        
        let diameter = MacMetrics.WindowChrome.trafficLightDiameter
        let spacing = MacMetrics.WindowChrome.trafficLightSpacing
        let padding = MacMetrics.WindowChrome.horizontalPadding
        let centerY = frame.minY + (MacMetrics.WindowChrome.titlebarHeight / 2)
        let expectedY = centerY - (diameter / 2)
        let expectedRadius = diameter / 2

        // Close button
        if case let .fillRoundedRect(rect, radius, _) = ctx.calls[2] {
            #expect(rect.minX == frame.minX + padding)
            #expect(rect.minY == expectedY)
            #expect(rect.size.width == diameter)
            #expect(rect.size.height == diameter)
            #expect(radius == expectedRadius)
        } else {
            Issue.record("Expected close dot at index 2")
        }

        // Minimize button
        if case let .fillRoundedRect(rect, radius, _) = ctx.calls[3] {
            let closeMaxX = frame.minX + padding + diameter
            #expect(rect.minX == closeMaxX + spacing)
            #expect(rect.minY == expectedY)
            #expect(rect.size.width == diameter)
            #expect(rect.size.height == diameter)
            #expect(radius == expectedRadius)
        } else {
            Issue.record("Expected minimize dot at index 3")
        }

        // Maximize button
        if case let .fillRoundedRect(rect, radius, _) = ctx.calls[4] {
            let closeMaxX = frame.minX + padding + diameter
            let minimizeMaxX = closeMaxX + spacing + diameter
            #expect(rect.minX == minimizeMaxX + spacing)
            #expect(rect.minY == expectedY)
            #expect(rect.size.width == diameter)
            #expect(rect.size.height == diameter)
            #expect(radius == expectedRadius)
        } else {
            Issue.record("Expected maximize dot at index 4")
        }
    }

    @Test("Traffic light colors: Focused vs Unfocused")
    func trafficLightColors() {
        let focusedCtx = RecordingPaintContext()
        MacWindowChromePaint().paint(into: focusedCtx, frame: frame, state: PaintControlState(isFocused: true))

        #expect(focusedCtx.calls.count == 5)
        #expect(extractColor(focusedCtx.calls[2]) == MacColors.windowCloseRed)
        #expect(extractColor(focusedCtx.calls[3]) == MacColors.windowMinimizeYellow)
        #expect(extractColor(focusedCtx.calls[4]) == MacColors.windowMaximizeGreen)

        let unfocusedCtx = RecordingPaintContext()
        MacWindowChromePaint().paint(into: unfocusedCtx, frame: frame, state: PaintControlState(isFocused: false))

        #expect(unfocusedCtx.calls.count == 5)
        let unfocusedColor = MacColors.windowChromeUnfocusedDot
        #expect(extractColor(unfocusedCtx.calls[2]) == unfocusedColor)
        #expect(extractColor(unfocusedCtx.calls[3]) == unfocusedColor)
        #expect(extractColor(unfocusedCtx.calls[4]) == unfocusedColor)
    }

    @Test("Traffic light hover state (isHoveringTrafficLights)")
    func hoverState() {
        let ctx = RecordingPaintContext()
        let state = PaintControlState(isFocused: true, isHoveringTrafficLights: true)
        MacWindowChromePaint().paint(into: ctx, frame: frame, state: state)

        // 5 base calls + glyphs
        // Close: 2 strokeLines (X)
        // Minimize: 1 strokeLine (-)
        // Maximize: 2 strokeLines (+)
        // Total: 5 + 5 = 10 calls
        #expect(ctx.calls.count == 10)

        let glyphColor = PaintColor(r: 0, g: 0, b: 0, a: 128)
        
        // Verify glyph calls are strokeLines with correct color
        for i in 5..<10 {
            if case let .strokeLine(_, _, color, width) = ctx.calls[i] {
                #expect(color == glyphColor)
                #expect(width == 1)
            } else {
                Issue.record("Expected strokeLine for glyph at index \(i)")
            }
        }
    }

    @Test("Title stub rendering")
    func titleStub() {
        let ctx = RecordingPaintContext()
        MacWindowChromePaint(title: "Quill").paint(into: ctx, frame: frame, state: .normal)

        // 5 base calls + 1 title stub = 6 calls
        #expect(ctx.calls.count == 6)
        
        if case let .fillRoundedRect(rect, radius, color) = ctx.calls.last {
            #expect(radius == 2)
            #expect(color == MacColors.separator)
            #expect(rect.size.width == 60)
            #expect(rect.size.height == 12)
            // Should be centered
            #expect(abs(rect.midX - frame.midX) < 0.001)
            #expect(abs(rect.midY - (frame.minY + MacMetrics.WindowChrome.titlebarHeight / 2)) < 0.001)
        } else {
            Issue.record("Expected title stub fill rounded rect")
        }
    }

    private func extractColor(_ call: RecordingPaintContext.DrawCall) -> PaintColor? {
        if case let .fillRoundedRect(_, _, color) = call {
            return color
        }
        return nil
    }
}
