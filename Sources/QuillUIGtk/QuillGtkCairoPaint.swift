#if os(Linux)
import Foundation
import CGTK
import QuillPaint

public final class QuillGtkCairoPaintContext: PaintContext {
    public let cairoContext: OpaquePointer

    public init(cairoContext: OpaquePointer) {
        self.cairoContext = cairoContext
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        gtk_swift_cairo_save(cairoContext)
        setSource(color)
        addRoundedRect(rect, cornerRadius: cornerRadius)
        gtk_swift_cairo_fill(cairoContext)
        gtk_swift_cairo_restore(cairoContext)
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        gtk_swift_cairo_save(cairoContext)
        setSource(color)
        gtk_swift_cairo_set_line_width(cairoContext, lineWidth)
        addRoundedRect(rect, cornerRadius: cornerRadius)
        gtk_swift_cairo_stroke(cairoContext)
        gtk_swift_cairo_restore(cairoContext)
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        gtk_swift_cairo_save(cairoContext)
        setSource(color)
        gtk_swift_cairo_set_line_width(cairoContext, lineWidth)
        gtk_swift_cairo_new_path(cairoContext)
        gtk_swift_cairo_move_to(cairoContext, start.x, start.y)
        gtk_swift_cairo_line_to(cairoContext, end.x, end.y)
        gtk_swift_cairo_stroke(cairoContext)
        gtk_swift_cairo_restore(cairoContext)
    }

    private func setSource(_ color: PaintColor) {
        gtk_swift_cairo_set_source_rgba(
            cairoContext,
            color.red,
            color.green,
            color.blue,
            color.alpha
        )
    }

    private func addRoundedRect(_ rect: PaintRect, cornerRadius: Double) {
        let width = max(0, rect.size.width)
        let height = max(0, rect.size.height)
        let radius = min(max(0, cornerRadius), min(width, height) / 2)
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.minX + width
        let maxY = rect.minY + height

        gtk_swift_cairo_new_path(cairoContext)

        guard radius > 0 else {
            gtk_swift_cairo_rectangle(cairoContext, minX, minY, width, height)
            return
        }

        gtk_swift_cairo_move_to(cairoContext, minX + radius, minY)
        gtk_swift_cairo_line_to(cairoContext, maxX - radius, minY)
        gtk_swift_cairo_arc(cairoContext, maxX - radius, minY + radius, radius, -Double.pi / 2, 0)
        gtk_swift_cairo_line_to(cairoContext, maxX, maxY - radius)
        gtk_swift_cairo_arc(cairoContext, maxX - radius, maxY - radius, radius, 0, Double.pi / 2)
        gtk_swift_cairo_line_to(cairoContext, minX + radius, maxY)
        gtk_swift_cairo_arc(cairoContext, minX + radius, maxY - radius, radius, Double.pi / 2, Double.pi)
        gtk_swift_cairo_line_to(cairoContext, minX, minY + radius)
        gtk_swift_cairo_arc(cairoContext, minX + radius, minY + radius, radius, Double.pi, 3 * Double.pi / 2)
        gtk_swift_cairo_close_path(cairoContext)
    }
}

public struct QuillGtkCairoImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data

    public init(width: Int, height: Int, rgba: Data) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

public enum QuillGtkCairoButtonRenderer {
    public static func renderButtonImage(
        size: PaintSize = PaintSize(width: 80, height: 22),
        state: PaintControlState = .normal,
        margin: Double = 8,
        scale: Double = 2
    ) -> QuillGtkCairoImage? {
        guard scale > 0 else { return nil }

        let canvas = PaintSize(
            width: size.width + 2 * margin,
            height: size.height + 2 * margin
        )
        let pixelWidth = max(1, Int((canvas.width * scale).rounded()))
        let pixelHeight = max(1, Int((canvas.height * scale).rounded()))

        guard let surface = cairo_image_surface_create(
            CAIRO_FORMAT_ARGB32,
            gint(pixelWidth),
            gint(pixelHeight)
        ) else {
            return nil
        }
        defer { cairo_surface_destroy(surface) }

        guard let cairoContext = cairo_create(surface) else {
            return nil
        }
        defer { cairo_destroy(cairoContext) }

        cairo_set_operator(cairoContext, CAIRO_OPERATOR_CLEAR)
        cairo_paint(cairoContext)
        cairo_set_operator(cairoContext, CAIRO_OPERATOR_OVER)
        cairo_scale(cairoContext, scale, scale)

        let context = QuillGtkCairoPaintContext(cairoContext: cairoContext)
        MacButtonPaint().paint(
            into: context,
            frame: PaintRect(x: margin, y: margin, width: size.width, height: size.height),
            state: state
        )

        guard let rgba = straightRGBA(fromARGB32Surface: surface, width: pixelWidth, height: pixelHeight) else {
            return nil
        }

        return QuillGtkCairoImage(width: pixelWidth, height: pixelHeight, rgba: rgba)
    }

    private static func straightRGBA(
        fromARGB32Surface surface: OpaquePointer,
        width: Int,
        height: Int
    ) -> Data? {
        cairo_surface_flush(surface)
        guard let sourcePixels = cairo_image_surface_get_data(surface) else {
            return nil
        }

        let sourceStride = Int(cairo_image_surface_get_stride(surface))
        var rgba = Data(count: width * height * 4)

        rgba.withUnsafeMutableBytes { rawBuffer in
            guard let destination = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            for y in 0..<height {
                let sourceRow = sourcePixels.advanced(by: y * sourceStride)
                let destinationRow = destination.advanced(by: y * width * 4)

                for x in 0..<width {
                    let pixel = UnsafeRawPointer(sourceRow.advanced(by: x * 4)).load(as: UInt32.self)
                    let alpha = (pixel >> 24) & 0xFF
                    let red = (pixel >> 16) & 0xFF
                    let green = (pixel >> 8) & 0xFF
                    let blue = pixel & 0xFF
                    let destinationPixel = destinationRow.advanced(by: x * 4)

                    destinationPixel[0] = unpremultipliedByte(red, alpha: alpha)
                    destinationPixel[1] = unpremultipliedByte(green, alpha: alpha)
                    destinationPixel[2] = unpremultipliedByte(blue, alpha: alpha)
                    destinationPixel[3] = UInt8(alpha)
                }
            }
        }

        return rgba
    }

    private static func unpremultipliedByte(_ component: UInt32, alpha: UInt32) -> UInt8 {
        guard alpha > 0 else { return 0 }
        return UInt8(min(255, (component * 255 + alpha / 2) / alpha))
    }
}
#endif
