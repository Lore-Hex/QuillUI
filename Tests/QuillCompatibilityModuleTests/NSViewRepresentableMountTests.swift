#if os(Linux)
import Testing
import SwiftUI
import QuillFoundation

// The NSViewRepresentable GTK mount, minus GTK: CGContext's pluggable
// backend (QuillCGContextBackend) is what the GtkDrawingArea draw func
// renders through — these tests prove the forwarding and the host-body
// wiring without needing a display.

private final class RecordingBackend: QuillCGContextBackend {
    var ops: [String] = []
    private func rec(_ s: String) { ops.append(s) }

    func saveGState() { rec("save") }
    func restoreGState() { rec("restore") }
    func translateBy(x: CGFloat, y: CGFloat) { rec("translate(\(Int(x)),\(Int(y)))") }
    func scaleBy(x: CGFloat, y: CGFloat) { rec("scale(\(x),\(y))") }
    func rotate(by angle: CGFloat) { rec("rotate") }
    func concatenate(_ transform: CGAffineTransform) {
        rec("concat(\(Int(transform.a)),\(Int(transform.d)),\(Int(transform.tx)),\(Int(transform.ty)))")
    }
    func setFillColor(_ rgba: [CGFloat]) { rec("fillColor\(rgba)") }
    func setStrokeColor(_ rgba: [CGFloat]) { rec("strokeColor\(rgba)") }
    func setLineWidth(_ width: CGFloat) { rec("lineWidth(\(Int(width)))") }
    func setLineCap(_ cap: CGLineCap) { rec("lineCap") }
    func setLineJoin(_ join: CGLineJoin) { rec("lineJoin") }
    func setAlpha(_ alpha: CGFloat) { rec("alpha(\(alpha))") }
    func fill(_ rect: CGRect) { rec("fill(\(Int(rect.width))x\(Int(rect.height)))") }
    func fillEllipse(in rect: CGRect) { rec("fillEllipse") }
    func stroke(_ rect: CGRect) { rec("strokeRect") }
    func strokeEllipse(in rect: CGRect) { rec("strokeEllipse") }
    func clear(_ rect: CGRect) { rec("clear") }
    func strokeLineSegments(between points: [CGPoint]) { rec("segments(\(points.count))") }
    func beginPath() { rec("beginPath") }
    func closePath() { rec("closePath") }
    func move(to point: CGPoint) { rec("move") }
    func addLine(to point: CGPoint) { rec("line") }
    func addRect(_ rect: CGRect) { rec("addRect") }
    func addEllipse(in rect: CGRect) { rec("addEllipse") }
    func addQuadCurve(to end: CGPoint, control: CGPoint) { rec("quad") }
    func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) { rec("curve") }
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                endAngle: CGFloat, clockwise: Bool) { rec("arc") }
    func fillPath() { rec("fillPath") }
    func fillPath(using rule: CGPathFillRule) { rec("fillPath(\(rule))") }
    func strokePath() { rec("strokePath") }
    func clip() { rec("clip") }
    func clip(using rule: CGPathFillRule) { rec("clip(\(rule))") }
    func clip(to rect: CGRect) { rec("clipRect") }
    func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality) { rec("drawImage") }
}

@MainActor
struct NSViewRepresentableMountTests {

    @Test func cgContextForwardsToBackend() {
        let backend = RecordingBackend()
        let ctx = CGContext(quillBackend: backend)

        // The exact shape of SolderScope's MicroscopeNSView.draw preamble.
        ctx.setFillColor(CGColor(components: [0, 0, 0, 1]))
        ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        ctx.saveGState()
        ctx.translateBy(x: 160, y: 120)
        ctx.rotate(by: 0.5)
        ctx.concatenate(CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 4, ty: 5))
        ctx.restoreGState()

        #expect(backend.ops == [
            "fillColor[0.0, 0.0, 0.0, 1.0]",
            "fill(320x240)",
            "save",
            "translate(160,120)",
            "rotate",
            "concat(2,3,4,5)",
            "restore",
        ])
    }

    @Test func cgContextForwardsPathCurvesToBackend() {
        let backend = RecordingBackend()
        let ctx = CGContext(quillBackend: backend)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 2, y: 0))
        path.addQuadCurve(to: CGPoint(x: 4, y: 0), control: CGPoint(x: 3, y: 1))
        path.addCurve(
            to: CGPoint(x: 8, y: 0),
            control1: CGPoint(x: 5, y: 2),
            control2: CGPoint(x: 7, y: 2)
        )
        path.closeSubpath()

        ctx.addRects([
            CGRect(x: 0, y: 0, width: 1, height: 1),
            CGRect(x: 1, y: 1, width: 2, height: 2),
        ])
        ctx.addPath(path)
        ctx.addQuadCurve(to: CGPoint(x: 1, y: 1), control: CGPoint(x: 0, y: 1))
        ctx.addCurve(to: CGPoint(x: 3, y: 1), control1: CGPoint(x: 1, y: 2), control2: CGPoint(x: 2, y: 2))
        ctx.move(to: .zero)
        ctx.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 2)
        ctx.fillPath(using: .evenOdd)
        ctx.clip(using: .evenOdd)

        #expect(backend.ops == [
            "addRect",
            "addRect",
            "move",
            "line",
            "quad",
            "curve",
            "closePath",
            "quad",
            "curve",
            "move",
            "line",
            "curve",
            "fillPath(evenOdd)",
            "clip(evenOdd)",
        ])
    }

    @Test func colorFormsNormalizeToRGBA() {
        let backend = RecordingBackend()
        let ctx = CGContext(quillBackend: backend)

        ctx.setFillColor(CGColor(components: [0.25, 1]))        // gray+alpha
        ctx.setStrokeColor(CGColor(components: [0.1, 0.2, 0.3])) // rgb
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)  // components

        #expect(backend.ops == [
            "fillColor[0.25, 0.25, 0.25, 1.0]",
            "strokeColor[0.1, 0.2, 0.3, 1.0]",
            "fillColor[1.0, 0.0, 0.0, 0.5]",
        ])
    }

    @Test func backendlessContextStaysInert() {
        // No backend installed → historical no-op behavior (nothing crashes).
        let ctx = CGContext()
        ctx.setFillColor(CGColor.black)
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        ctx.saveGState()
        ctx.restoreGState()
    }

    @Test func representableDefaultBodyIsTheGTKHost() {
        @MainActor
        struct Probe: NSViewRepresentable {
            func makeNSView(context: Context) -> NSView { NSView() }
            func updateNSView(_ nsView: NSView, context: Context) {}
        }
        // Apple parity: the conformer declares no body; rendering enters
        // through the framework. Here the framework hook IS the host leaf.
        let body = Probe().body
        #expect(String(describing: type(of: body)).contains("QuillNSViewRepresentableHostView"))
    }

    @Test func coordinatorPatternCompilesAndFlows() {
        final class Delegate { var pinged = false }
        @MainActor
        struct Probe: NSViewRepresentable {
            func makeCoordinator() -> Delegate { Delegate() }
            func makeNSView(context: Context) -> NSView {
                context.coordinator.pinged = true
                return NSView()
            }
            func updateNSView(_ nsView: NSView, context: Context) {}
        }
        let probe = Probe()
        let coordinator = probe.makeCoordinator()
        let context = NSViewRepresentableContext<Probe>(coordinator: coordinator)
        _ = probe.makeNSView(context: context)
        #expect(coordinator.pinged)
    }
}
#endif
