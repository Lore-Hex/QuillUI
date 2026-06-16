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
    func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                endAngle: CGFloat, clockwise: Bool)
    func fillPath()
    func strokePath()
    func clip()
    func clip(to rect: CGRect)

    /// `image` is the CGContext.draw(_:in:) argument (typed Any in the shadow);
    /// implementations downcast to CGImage and draw `quillBGRAPixels` if set.
    func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality)
}

public protocol QuillCGImageProducingBackend: AnyObject {
    func quillMakeImage() -> CGImage?
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

public final class QuillBitmapCGContextBackend: QuillCGContextBackend, QuillCGImageProducingBackend {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    private var pixels: [UInt8]
    private var fillRGBA: [CGFloat] = [0, 0, 0, 1]
    private var strokeRGBA: [CGFloat] = [0, 0, 0, 1]
    private var alpha: CGFloat = 1

    public init(width: Int, height: Int, opaque: Bool = false) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.bytesPerRow = self.width * 4
        let backgroundAlpha: UInt8 = opaque ? 255 : 0
        self.pixels = [UInt8](repeating: 0, count: self.height * self.bytesPerRow)
        if opaque {
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index + 3] = backgroundAlpha
            }
        }
    }

    public func quillMakeImage() -> CGImage? {
        let image = CGImage()
        image.width = width
        image.height = height
        image.quillBytesPerRow = bytesPerRow
        image.quillBGRAPixels = pixels
        image.quillUTType = "public.png"
        return image
    }

    public func saveGState() {}
    public func restoreGState() {}
    public func translateBy(x: CGFloat, y: CGFloat) { _ = (x, y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { _ = (x, y) }
    public func rotate(by angle: CGFloat) { _ = angle }
    public func setFillColor(_ rgba: [CGFloat]) { fillRGBA = normalized(rgba) }
    public func setStrokeColor(_ rgba: [CGFloat]) { strokeRGBA = normalized(rgba) }
    public func setLineWidth(_ width: CGFloat) { _ = width }
    public func setLineCap(_ cap: CGLineCap) { _ = cap }
    public func setLineJoin(_ join: CGLineJoin) { _ = join }
    public func setAlpha(_ alpha: CGFloat) { self.alpha = clamp(alpha) }

    public func fill(_ rect: CGRect) { fillRect(rect, rgba: fillRGBA) }
    public func fillEllipse(in rect: CGRect) { fillEllipseRect(rect, rgba: fillRGBA) }
    public func stroke(_ rect: CGRect) { strokeRect(rect, rgba: strokeRGBA) }
    public func strokeEllipse(in rect: CGRect) { stroke(rect) }
    public func clear(_ rect: CGRect) { clearRect(rect) }
    public func strokeLineSegments(between points: [CGPoint]) { _ = points }
    public func beginPath() {}
    public func closePath() {}
    public func move(to point: CGPoint) { _ = point }
    public func addLine(to point: CGPoint) { _ = point }
    public func addRect(_ rect: CGRect) { _ = rect }
    public func addEllipse(in rect: CGRect) { _ = rect }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                       endAngle: CGFloat, clockwise: Bool) {
        _ = (center, radius, startAngle, endAngle, clockwise)
    }
    public func fillPath() {}
    public func strokePath() {}
    public func clip() {}
    public func clip(to rect: CGRect) { _ = rect }

    public func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality) {
        _ = interpolationQuality
        let cgImage: CGImage?
        if let image = image as? CGImage {
            cgImage = image
        } else if let image = image as? RSImage {
            cgImage = image.cgImage
        } else {
            cgImage = nil
        }
        guard
            let cgImage,
            cgImage.width > 0,
            cgImage.height > 0,
            let sourcePixels = cgImage.quillBGRAPixels,
            cgImage.quillBytesPerRow > 0
        else {
            return
        }

        let target = clampedRect(rect)
        guard target.width > 0, target.height > 0 else { return }
        for y in 0..<target.height {
            let sourceY = min(cgImage.height - 1, max(0, y * cgImage.height / target.height))
            for x in 0..<target.width {
                let sourceX = min(cgImage.width - 1, max(0, x * cgImage.width / target.width))
                let sourceOffset = sourceY * cgImage.quillBytesPerRow + sourceX * 4
                guard sourceOffset + 3 < sourcePixels.count else { continue }
                let destinationOffset = (target.y + y) * bytesPerRow + (target.x + x) * 4
                blendPremultipliedBGRA(
                    b: sourcePixels[sourceOffset + 0],
                    g: sourcePixels[sourceOffset + 1],
                    r: sourcePixels[sourceOffset + 2],
                    a: UInt8(Double(sourcePixels[sourceOffset + 3]) * Double(alpha)),
                    at: destinationOffset
                )
            }
        }
    }

    private struct PixelRect {
        var x: Int
        var y: Int
        var width: Int
        var height: Int
    }

    private func normalized(_ rgba: [CGFloat]) -> [CGFloat] {
        let components = rgba + [0, 0, 0, 1]
        return [
            clamp(components[0]),
            clamp(components[1]),
            clamp(components[2]),
            clamp(components[3]),
        ]
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(1, max(0, value))
    }

    private func clampedRect(_ rect: CGRect) -> PixelRect {
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxX = min(width, Int(rect.maxX.rounded(.up)))
        let maxY = min(height, Int(rect.maxY.rounded(.up)))
        return PixelRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    private func premultipliedBGRA(_ rgba: [CGFloat]) -> (b: UInt8, g: UInt8, r: UInt8, a: UInt8) {
        let effectiveAlpha = clamp(rgba[3] * alpha)
        let a = UInt8((effectiveAlpha * 255).rounded())
        let r = UInt8((clamp(rgba[0]) * effectiveAlpha * 255).rounded())
        let g = UInt8((clamp(rgba[1]) * effectiveAlpha * 255).rounded())
        let b = UInt8((clamp(rgba[2]) * effectiveAlpha * 255).rounded())
        return (b, g, r, a)
    }

    private func fillRect(_ rect: CGRect, rgba: [CGFloat]) {
        let target = clampedRect(rect)
        guard target.width > 0, target.height > 0 else { return }
        let color = premultipliedBGRA(rgba)
        for y in target.y..<(target.y + target.height) {
            for x in target.x..<(target.x + target.width) {
                blendPremultipliedBGRA(b: color.b, g: color.g, r: color.r, a: color.a, at: y * bytesPerRow + x * 4)
            }
        }
    }

    private func fillEllipseRect(_ rect: CGRect, rgba: [CGFloat]) {
        let target = clampedRect(rect)
        guard target.width > 0, target.height > 0 else { return }
        let color = premultipliedBGRA(rgba)
        let radiusX = max(0.5, Double(target.width) / 2)
        let radiusY = max(0.5, Double(target.height) / 2)
        let centerX = Double(target.x) + radiusX
        let centerY = Double(target.y) + radiusY
        for y in target.y..<(target.y + target.height) {
            for x in target.x..<(target.x + target.width) {
                let dx = (Double(x) + 0.5 - centerX) / radiusX
                let dy = (Double(y) + 0.5 - centerY) / radiusY
                if dx * dx + dy * dy <= 1 {
                    blendPremultipliedBGRA(b: color.b, g: color.g, r: color.r, a: color.a, at: y * bytesPerRow + x * 4)
                }
            }
        }
    }

    private func strokeRect(_ rect: CGRect, rgba: [CGFloat]) {
        let target = clampedRect(rect)
        guard target.width > 0, target.height > 0 else { return }
        fillRect(CGRect(x: CGFloat(target.x), y: CGFloat(target.y), width: CGFloat(target.width), height: 1), rgba: rgba)
        fillRect(
            CGRect(
                x: CGFloat(target.x),
                y: CGFloat(target.y + target.height - 1),
                width: CGFloat(target.width),
                height: 1
            ),
            rgba: rgba
        )
        fillRect(CGRect(x: CGFloat(target.x), y: CGFloat(target.y), width: 1, height: CGFloat(target.height)), rgba: rgba)
        fillRect(
            CGRect(
                x: CGFloat(target.x + target.width - 1),
                y: CGFloat(target.y),
                width: 1,
                height: CGFloat(target.height)
            ),
            rgba: rgba
        )
    }

    private func clearRect(_ rect: CGRect) {
        let target = clampedRect(rect)
        guard target.width > 0, target.height > 0 else { return }
        for y in target.y..<(target.y + target.height) {
            for x in target.x..<(target.x + target.width) {
                let offset = y * bytesPerRow + x * 4
                pixels[offset + 0] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }
    }

    private func blendPremultipliedBGRA(b: UInt8, g: UInt8, r: UInt8, a: UInt8, at offset: Int) {
        guard offset + 3 < pixels.count else { return }
        let inverseAlpha = 255 - Int(a)
        pixels[offset + 0] = UInt8(min(255, Int(b) + Int(pixels[offset + 0]) * inverseAlpha / 255))
        pixels[offset + 1] = UInt8(min(255, Int(g) + Int(pixels[offset + 1]) * inverseAlpha / 255))
        pixels[offset + 2] = UInt8(min(255, Int(r) + Int(pixels[offset + 2]) * inverseAlpha / 255))
        pixels[offset + 3] = UInt8(min(255, Int(a) + Int(pixels[offset + 3]) * inverseAlpha / 255))
    }
}
#endif
