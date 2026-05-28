import Foundation
import QuillPaint

#if os(Linux)
import CGTK
/// Cairo-backed implementation of `PaintContext`.
public final class CairoPaintContext: PaintContext {
    private let cr: OpaquePointer

    public init(cr: OpaquePointer) {
        self.cr = cr
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        gtk_swift_cairo_set_source_rgba(cr, color.red, color.green, color.blue, color.alpha)
        if cornerRadius > 0 {
            addRoundedRectPath(rect: rect, cornerRadius: cornerRadius)
            gtk_swift_cairo_fill(cr)
        } else {
            gtk_swift_cairo_rectangle(cr, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
            gtk_swift_cairo_fill(cr)
        }
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        gtk_swift_cairo_set_source_rgba(cr, color.red, color.green, color.blue, color.alpha)
        gtk_swift_cairo_set_line_width(cr, lineWidth)
        if cornerRadius > 0 {
            addRoundedRectPath(rect: rect, cornerRadius: cornerRadius)
            gtk_swift_cairo_stroke(cr)
        } else {
            gtk_swift_cairo_rectangle(cr, rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
            gtk_swift_cairo_stroke(cr)
        }
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        gtk_swift_cairo_set_source_rgba(cr, color.red, color.green, color.blue, color.alpha)
        gtk_swift_cairo_set_line_width(cr, lineWidth)
        gtk_swift_cairo_move_to(cr, start.x, start.y)
        gtk_swift_cairo_line_to(cr, end.x, end.y)
        gtk_swift_cairo_stroke(cr)
    }

    public func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {
        // TODO(quillui): wire GTK/Cairo text rendering. This needs cairo text
        // shims added to CGTK (gtk_swift_cairo_select_font_face / set_font_size /
        // show_text / font_extents); until those exist this is a no-op so the
        // type conforms to PaintContext. Button labels will not render on the
        // GTK backend yet. The macOS-reference renderer (CGPaintContext) and the
        // standalone QuillPaintCairo context both implement drawText fully.
        _ = (string, point, font, color)
    }

    private func addRoundedRectPath(rect: PaintRect, cornerRadius: Double) {
        let x = rect.origin.x
        let y = rect.origin.y
        let w = rect.size.width
        let h = rect.size.height
        let r = cornerRadius

        // Cairo arc: x, y, radius, angle1, angle2
        // Angles are in radians. 0 is to the right, Y grows down.
        gtk_swift_cairo_new_path(cr)
        gtk_swift_cairo_move_to(cr, x + r, y)
        gtk_swift_cairo_line_to(cr, x + w - r, y)
        gtk_swift_cairo_arc(cr, x + w - r, y + r, r, -Double.pi / 2, 0)
        gtk_swift_cairo_line_to(cr, x + w, y + h - r)
        gtk_swift_cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
        gtk_swift_cairo_line_to(cr, x + r, y + h)
        gtk_swift_cairo_arc(cr, x + r, y + h - r, r, Double.pi / 2, Double.pi)
        gtk_swift_cairo_line_to(cr, x, y + r)
        gtk_swift_cairo_arc(cr, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        gtk_swift_cairo_close_path(cr)
    }
}
#endif
