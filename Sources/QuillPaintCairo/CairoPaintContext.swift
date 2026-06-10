import Foundation
import QuillPaint

#if canImport(CCairo)
import CCairo

/// `PaintContext` adapter that draws into a Cairo context (`cairo_t*`).
///
/// Coordinate system note: by default, Cairo's surface origin (for image
/// surfaces and GTK) matches the top-left convention of `PaintPoint`.
/// However, raw Cairo contexts (like PostScript/PDF) use a bottom-left
/// origin. To match the macOS-reference output, the caller should ensure
/// the context is set up with a top-left origin.
public final class CairoPaintContext: PaintContext {
    public let pointer: OpaquePointer // cairo_t *

    public init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    public convenience init(cr: OpaquePointer) {
        self.init(pointer: cr)
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        cairo_save(pointer)
        applyColor(color)
        appendRoundedRect(rect, cornerRadius: cornerRadius)
        cairo_fill(pointer)
        cairo_restore(pointer)
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        cairo_save(pointer)
        applyColor(color)
        cairo_set_line_width(pointer, lineWidth)
        appendRoundedRect(rect, cornerRadius: cornerRadius)
        cairo_stroke(pointer)
        cairo_restore(pointer)
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        cairo_save(pointer)
        applyColor(color)
        cairo_set_line_width(pointer, lineWidth)
        cairo_move_to(pointer, start.x, start.y)
        cairo_line_to(pointer, end.x, end.y)
        cairo_stroke(pointer)
        cairo_restore(pointer)
    }

    public func drawText(_ string: String, at point: PaintPoint, font: PaintFont, color: PaintColor) {
        guard !string.isEmpty else { return }
        let resolvedFont = MacFontResolution.resolve(font)
        let family = resolvedFont.family == MacFontResolution.systemDefaultFamily
            ? "Sans"
            : resolvedFont.family

        cairo_save(pointer)
        applyColor(color)
        // Cairo's "toy" text API is sufficient for the simple single-run labels
        // QuillPaint draws (button titles, etc.). Heavier i18n/shaping would use
        // Pango, but that's out of scope for the macOS-parity control set.
        cairo_select_font_face(
            pointer,
            family,
            CAIRO_FONT_SLANT_NORMAL,
            resolvedFont.weight >= 600 ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL
        )
        cairo_set_font_size(pointer, resolvedFont.size)
        // `cairo_show_text` positions glyphs on the baseline; `point` is the
        // top-left typographic origin, so drop down by the font ascent.
        var extents = cairo_font_extents_t()
        cairo_font_extents(pointer, &extents)
        cairo_move_to(pointer, point.x, point.y + extents.ascent)
        cairo_show_text(pointer, string)
        cairo_restore(pointer)
    }

    private func applyColor(_ color: PaintColor) {
        cairo_set_source_rgba(pointer, color.red, color.green, color.blue, color.alpha)
    }

    private func appendRoundedRect(_ rect: PaintRect, cornerRadius: Double) {
        let x = rect.origin.x
        let y = rect.origin.y
        let w = rect.size.width
        let h = rect.size.height
        let r = min(cornerRadius, min(w / 2, h / 2))

        if r <= 0 {
            cairo_rectangle(pointer, x, y, w, h)
            return
        }

        cairo_new_path(pointer)
        cairo_move_to(pointer, x + r, y)
        cairo_line_to(pointer, x + w - r, y)
        cairo_arc(pointer, x + w - r, y + r, r, -Double.pi / 2, 0)
        cairo_line_to(pointer, x + w, y + h - r)
        cairo_arc(pointer, x + w - r, y + h - r, r, 0, Double.pi / 2)
        cairo_line_to(pointer, x + r, y + h)
        cairo_arc(pointer, x + r, y + h - r, r, Double.pi / 2, Double.pi)
        cairo_line_to(pointer, x, y + r)
        cairo_arc(pointer, x + r, y + r, r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(pointer)
    }
}
#endif
