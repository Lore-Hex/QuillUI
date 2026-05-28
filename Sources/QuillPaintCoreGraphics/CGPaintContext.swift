import Foundation
import QuillPaint

#if canImport(CoreGraphics)
import CoreGraphics

#if canImport(CoreText)
import CoreText
#endif

/// `PaintContext` adapter that draws into a `CGContext`. The CoreGraphics
/// backend is Apple-only — its primary use is generating Mac-reference
/// snapshots from the same paint code that the GTK Cairo and Qt Skia
/// backends will use on Linux. Same source → same pixels.
///
/// Coordinate system note: the adapter draws using the caller-provided
/// CGContext as-is. If you want PaintPoint's top-left origin to match
/// what users see, install a flip transform on the context before
/// constructing this adapter — `MacReferenceRenderer` does this for you.
public final class CGPaintContext: PaintContext {
    public let cgContext: CGContext

    public init(cgContext: CGContext) {
        self.cgContext = cgContext
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        let cgRect = Self.cgRect(from: rect)
        let path = CGPath(
            roundedRect: cgRect,
            cornerWidth: CGFloat(cornerRadius),
            cornerHeight: CGFloat(cornerRadius),
            transform: nil
        )
        cgContext.saveGState()
        cgContext.setFillColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        cgContext.addPath(path)
        cgContext.fillPath()
        cgContext.restoreGState()
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        let cgRect = Self.cgRect(from: rect)
        let path = CGPath(
            roundedRect: cgRect,
            cornerWidth: CGFloat(cornerRadius),
            cornerHeight: CGFloat(cornerRadius),
            transform: nil
        )
        cgContext.saveGState()
        cgContext.setStrokeColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        cgContext.setLineWidth(CGFloat(lineWidth))
        cgContext.addPath(path)
        cgContext.strokePath()
        cgContext.restoreGState()
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        cgContext.saveGState()
        cgContext.setStrokeColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        cgContext.setLineWidth(CGFloat(lineWidth))
        cgContext.move(to: CGPoint(x: start.x, y: start.y))
        cgContext.addLine(to: CGPoint(x: end.x, y: end.y))
        cgContext.strokePath()
        cgContext.restoreGState()
    }

    public func fillPolygon(_ points: [PaintPoint], color: PaintColor) {
        guard points.count >= 3 else { return }
        cgContext.saveGState()
        cgContext.setFillColor(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
        cgContext.beginPath()
        cgContext.move(to: CGPoint(x: points[0].x, y: points[0].y))
        for point in points.dropFirst() {
            cgContext.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        cgContext.closePath()
        cgContext.fillPath()
        cgContext.restoreGState()
    }

    public func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {
        guard !string.isEmpty else { return }

        #if canImport(CoreText)
        let ctFont = Self.coreTextFont(from: font)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: string,
                attributes: [
                    kCTFontAttributeName as NSAttributedString.Key: ctFont,
                    kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(
                        red: CGFloat(color.red),
                        green: CGFloat(color.green),
                        blue: CGFloat(color.blue),
                        alpha: CGFloat(color.alpha)
                    )
                ]
            )
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let lineHeight = ascent + descent + leading

        cgContext.saveGState()
        cgContext.textMatrix = .identity
        cgContext.translateBy(x: CGFloat(point.x), y: CGFloat(point.y) + lineHeight)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.textPosition = CGPoint(x: 0, y: descent + leading / 2)
        CTLineDraw(line, cgContext)
        cgContext.restoreGState()
        #endif
    }

    private static func cgRect(from rect: PaintRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    #if canImport(CoreText)
    private static func coreTextFont(from font: PaintFont) -> CTFont {
        let resolved = MacFontResolution.resolve(font)
        let traits: [String: Any] = [
            kCTFontWeightTrait as String: coreTextWeight(from: resolved.weight)
        ]
        var attributes: [String: Any] = [
            kCTFontTraitsAttribute as String: traits
        ]
        if resolved.family != MacFontResolution.systemDefaultFamily {
            attributes[kCTFontFamilyNameAttribute as String] = resolved.family
        }

        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, CGFloat(resolved.size), nil)
    }

    private static func coreTextWeight(from weight: Int) -> CGFloat {
        switch max(100, min(900, weight)) {
        case 100: return -0.80
        case 200: return -0.60
        case 300: return -0.40
        case 400: return 0.00
        case 500: return 0.23
        case 600: return 0.30
        case 700: return 0.40
        case 800: return 0.56
        default: return 0.62
        }
    }
    #endif
}

#endif
