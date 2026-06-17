#if os(Linux)
import Foundation

// Pluggable drawing backend for the CGContext shadow. The shadow's methods
// have always been compile-only no-ops; with a backend installed they become
// REAL drawing calls. First backend: Cairo (QuillAppKitGTK), powering custom
// `NSView.draw(_:)` content inside GtkDrawingAreas — the path SolderScope's
// MicroscopeNSView renders through. QuillFoundation stays dependency-free:
// the protocol lives here, implementations live with their toolkits.
//
// Colors cross the boundary as normalized RGBA component arrays (the shadow
// RSCGColor's gray/gray+alpha/rgb/rgba forms are normalized by CGContext
// before forwarding).
public protocol QuillCGContextBackend: AnyObject {
    func saveGState()
    func restoreGState()

    func translateBy(x: CGFloat, y: CGFloat)
    func scaleBy(x: CGFloat, y: CGFloat)
    func rotate(by angle: CGFloat)

    func setFillColor(_ rgba: [CGFloat])
    func setStrokeColor(_ rgba: [CGFloat])
    func setLineWidth(_ width: CGFloat)
    func setLineCap(_ cap: CGLineCap)
    func setLineJoin(_ join: CGLineJoin)
    func setAlpha(_ alpha: CGFloat)

    func fill(_ rect: CGRect)
    func fillEllipse(in rect: CGRect)
    func stroke(_ rect: CGRect)
    func strokeEllipse(in rect: CGRect)
    func clear(_ rect: CGRect)
    func strokeLineSegments(between points: [CGPoint])

    func beginPath()
    func closePath()
    func move(to point: CGPoint)
    func addLine(to point: CGPoint)
    func addRect(_ rect: CGRect)
    func addEllipse(in rect: CGRect)
    func addQuadCurve(to end: CGPoint, control: CGPoint)
    func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint)
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                endAngle: CGFloat, clockwise: Bool)
    func fillPath()
    func fillPath(using rule: CGPathFillRule)
    func strokePath()
    func clip()
    func clip(using rule: CGPathFillRule)
    func clip(to rect: CGRect)

    /// `image` is the CGContext.draw(_:in:) argument (typed Any in the shadow);
    /// implementations downcast to CGImage and draw `quillBGRAPixels` if set.
    func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality)
}

extension CGContext {
    /// Normalize the shadow CGColor's component forms to RGBA.
    func quillNormalizedRGBA(_ color: RSCGColor) -> [CGFloat] {
        let c = color.components ?? [0, 0, 0, 1]
        switch c.count {
        case 1: return [c[0], c[0], c[0], 1]
        case 2: return [c[0], c[0], c[0], c[1]]
        case 3: return [c[0], c[1], c[2], 1]
        default: return Array(c.prefix(4))
        }
    }
}
#endif
