import Foundation
import QuillPaint

#if canImport(CoreGraphics)
import CoreGraphics
import CoreText

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

    public func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {
        cgContext.saveGState()

        // Flipped context handling for Core Text:
        // Core Text assumes a bottom-left coordinate system. Since our context is
        // already flipped for top-left (y grows down), we need to flip the text
        // matrix so the characters themselves aren't upside down.
        cgContext.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let ctFont = CTFontCreateWithName(font.family as CFString, CGFloat(font.size), nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: ctFont,
            kCTForegroundColorAttributeName: CGColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(color.alpha)
            ) as Any
        ]

        let attrString = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)

        cgContext.textPosition = CGPoint(x: point.x, y: point.y)
        CTLineDraw(line, cgContext)

        cgContext.restoreGState()
    }

    public func measureText(_ string: String, font: PaintFont) -> PaintSize {
        let ctFont = CTFontCreateWithName(font.family as CFString, CGFloat(font.size), nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: ctFont]
        let attrString = CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)

        let bounds = CTLineGetBoundsWithOptions(line, [])
        return PaintSize(width: Double(bounds.width), height: Double(bounds.height))
    }

    private static func cgRect(from rect: PaintRect) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.size.width,
            height: rect.size.height
        )
    }
}

#endif
