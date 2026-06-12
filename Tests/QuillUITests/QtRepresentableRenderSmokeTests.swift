#if os(Linux) && canImport(BackendQt) && canImport(QuillAppKitQt)
import Testing
import SwiftUI
import BackendQt
import Foundation

@MainActor
private final class QtCrosshairView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(components: [0, 0, 0, 1]))
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.setFillColor(CGColor(components: [1, 0, 0, 1]))
        ctx.fill(CGRect(x: -2, y: -bounds.midY, width: 4, height: bounds.height))
        ctx.setFillColor(CGColor(components: [0, 1, 0, 1]))
        ctx.fill(CGRect(x: -bounds.midX, y: -2, width: bounds.width, height: 4))
        ctx.restoreGState()

        ctx.setStrokeColor(CGColor(components: [1, 1, 0, 1]))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(
            x: bounds.midX - 30,
            y: bounds.midY - 30,
            width: 60,
            height: 60
        ))
    }
}

@MainActor
private final class QtSolidBlackView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(components: [0, 0, 0, 1]))
        ctx.fill(bounds)
    }
}

@MainActor
private struct QtCrosshairProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> QtCrosshairView { QtCrosshairView() }
    func updateNSView(_ nsView: QtCrosshairView, context: Context) {}
}

@MainActor
private struct QtSolidProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> QtSolidBlackView { QtSolidBlackView() }
    func updateNSView(_ nsView: QtSolidBlackView, context: Context) {}
}

@MainActor
private final class QtReuseCountingView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private struct QtReuseProbe: NSViewRepresentable {
    nonisolated(unsafe) static var makeCount = 0
    nonisolated(unsafe) static var updateCount = 0

    func makeNSView(context: Context) -> QtReuseCountingView {
        Self.makeCount += 1
        return QtReuseCountingView()
    }

    func updateNSView(_ nsView: QtReuseCountingView, context: Context) {
        Self.updateCount += 1
    }
}

@MainActor
@Suite("Qt NSViewRepresentable render smoke")
struct QtRepresentableRenderSmokeTests {
    @Test func secondRenderReusesTheMountedNSViewOnQt() throws {
        QtReuseProbe.makeCount = 0
        QtReuseProbe.updateCount = 0

        guard quillQtRenderViewToPNG(QtReuseProbe(), width: 60, height: 40) != nil else {
            return
        }
        _ = quillQtRenderViewToPNG(QtReuseProbe(), width: 60, height: 40)

        #expect(QtReuseProbe.makeCount == 1)
        #expect(QtReuseProbe.updateCount == 2)
    }

    @Test func customDrawRepresentableProducesStructuredQtPixels() throws {
        guard let crosshair = quillQtRenderViewToPNG(QtCrosshairProbe(), width: 240, height: 200) else {
            return
        }
        let solid = quillQtRenderViewToPNG(QtSolidProbe(), width: 240, height: 200)

        #expect(crosshair.count > 300)
        if let solid {
            #expect(crosshair != solid)
            #expect(crosshair.count > solid.count)
        }

        let out = ProcessInfo.processInfo.environment["QUILL_QT_REPRESENTABLE_SMOKE_OUT"]
        if let out, !out.isEmpty {
            try? crosshair.write(to: URL(fileURLWithPath: out))
        }
    }
}
#endif
