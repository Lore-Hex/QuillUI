#if os(Linux)
import Testing
import SwiftUI
@_spi(QuillTesting) import QuillUI
import Foundation

// Visual proof for the NSViewRepresentable GTK mount: a custom-draw NSView
// (the SolderScope MicroscopeNSView pattern — fills, transforms,
// NSGraphicsContext.current.cgContext) hosted by SwiftUI must produce real,
// structured pixels through GtkDrawingArea + the Cairo CGContext backend.
//
// Gated like the other offscreen-render suites: requires a display (Xvfb in
// the smoke harness) and QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1; otherwise the
// render call returns nil and the tests pass vacuously (same convention as
// the parity suites).

@MainActor
private final class CrosshairView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Black background (SolderScope's exact preamble)
        ctx.setFillColor(CGColor(components: [0, 0, 0, 1]))
        ctx.fill(bounds)
        // Red vertical + green horizontal crosshair through the center,
        // drawn under a translate to exercise the transform path.
        ctx.saveGState()
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        ctx.setFillColor(CGColor(components: [1, 0, 0, 1]))
        ctx.fill(CGRect(x: -2, y: -bounds.midY, width: 4, height: bounds.height))
        ctx.setFillColor(CGColor(components: [0, 1, 0, 1]))
        ctx.fill(CGRect(x: -bounds.midX, y: -2, width: bounds.width, height: 4))
        ctx.restoreGState()
        // Stroked circle exercises the path API.
        ctx.setStrokeColor(CGColor(components: [1, 1, 0, 1]))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: bounds.midX - 30, y: bounds.midY - 30,
                                     width: 60, height: 60))
    }
}

@MainActor
private final class SolidBlackView: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(CGColor(components: [0, 0, 0, 1]))
        ctx.fill(bounds)
    }
}

@MainActor
private struct CrosshairProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> CrosshairView { CrosshairView() }
    func updateNSView(_ nsView: CrosshairView, context: Context) {}
}

@MainActor
private struct SolidProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> SolidBlackView { SolidBlackView() }
    func updateNSView(_ nsView: SolidBlackView, context: Context) {}
}

@MainActor
private final class ReuseCountingView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private struct ReuseProbe: NSViewRepresentable {
    nonisolated(unsafe) static var makeCount = 0
    nonisolated(unsafe) static var updateCount = 0

    func makeNSView(context: Context) -> ReuseCountingView {
        Self.makeCount += 1
        return ReuseCountingView()
    }
    func updateNSView(_ nsView: ReuseCountingView, context: Context) {
        Self.updateCount += 1
    }
}

@MainActor
struct RepresentableRenderSmokeTests {

    @Test func secondRenderReusesTheMountedNSView() throws {
        guard quillRenderViewToImage(ReuseProbe(), width: 60, height: 40) != nil else {
            return // no display / flag off
        }
        _ = quillRenderViewToImage(ReuseProbe(), width: 60, height: 40)
        // Apple lifecycle: ONE makeNSView per mount identity, updateNSView on
        // every subsequent render. Without the mount registry this is 2/2
        // (remount per render — the camera-view-resets-every-frame bug).
        #expect(ReuseProbe.makeCount == 1)
        #expect(ReuseProbe.updateCount == 2)
    }

    @Test func customDrawRepresentableProducesStructuredPixels() throws {
        guard let crosshair = quillRenderViewToImage(CrosshairProbe(), width: 240, height: 200) else {
            return // no display / flag off — covered by the Xvfb smoke harness
        }
        let solid = quillRenderViewToImage(SolidProbe(), width: 240, height: 200)

        // A real render produces a non-trivial PNG…
        #expect(crosshair.count > 300)
        // …whose content is structurally different from a solid fill — i.e.
        // the crosshair/circle actually painted through the Cairo backend.
        if let solid {
            #expect(crosshair != solid)
            #expect(crosshair.count > solid.count)
        }

        // Artifact for humans (and for the campaign log).
        let out = ProcessInfo.processInfo.environment["QUILL_REPRESENTABLE_SMOKE_OUT"]
        if let out, !out.isEmpty {
            try? crosshair.write(to: URL(fileURLWithPath: out))
        }
    }
}
#endif
