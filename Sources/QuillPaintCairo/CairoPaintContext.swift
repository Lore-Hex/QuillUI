import QuillPaint

#if QUILLPAINT_HAS_CAIRO
#if canImport(CCairo)
import CCairo

/// `PaintContext` adapter that draws into a Cairo context.
///
/// The adapter uses the caller-provided `cairo_t` as-is. Callers that create a
/// bottom-left-origin surface should install the standard top-left paint-space
/// transform before drawing:
/// `cairo_translate(cr, 0, surfaceHeight); cairo_scale(cr, 1, -1)`.
public final class CairoPaintContext: PaintContext {
    public let cairoContext: OpaquePointer

    public init(cairoContext: OpaquePointer) {
        self.cairoContext = cairoContext
    }

    public func fillRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor) {
        cairo_save(cairoContext)
        setSource(color)
        addRoundedRectPath(rect, cornerRadius: cornerRadius)
        cairo_fill(cairoContext)
        cairo_restore(cairoContext)
    }

    public func strokeRoundedRect(_ rect: PaintRect, cornerRadius: Double, color: PaintColor, lineWidth: Double) {
        cairo_save(cairoContext)
        setSource(color)
        cairo_set_line_width(cairoContext, lineWidth)
        addRoundedRectPath(rect, cornerRadius: cornerRadius)
        cairo_stroke(cairoContext)
        cairo_restore(cairoContext)
    }

    public func strokeLine(from start: PaintPoint, to end: PaintPoint, color: PaintColor, lineWidth: Double) {
        cairo_save(cairoContext)
        setSource(color)
        cairo_set_line_width(cairoContext, lineWidth)
        cairo_new_path(cairoContext)
        cairo_move_to(cairoContext, start.x, start.y)
        cairo_line_to(cairoContext, end.x, end.y)
        cairo_stroke(cairoContext)
        cairo_restore(cairoContext)
    }

    private func setSource(_ color: PaintColor) {
        cairo_set_source_rgba(
            cairoContext,
            color.red,
            color.green,
            color.blue,
            color.alpha
        )
    }

    private func addRoundedRectPath(_ rect: PaintRect, cornerRadius: Double) {
        cairo_new_path(cairoContext)

        guard rect.size.width > 0, rect.size.height > 0 else {
            return
        }

        let radius = max(0, min(cornerRadius, rect.size.width / 2, rect.size.height / 2))
        if radius == 0 {
            cairo_rectangle(cairoContext, rect.minX, rect.minY, rect.size.width, rect.size.height)
            return
        }

        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        let halfPi = Double.pi / 2

        cairo_new_sub_path(cairoContext)
        cairo_arc(cairoContext, maxX - radius, minY + radius, radius, -halfPi, 0)
        cairo_arc(cairoContext, maxX - radius, maxY - radius, radius, 0, halfPi)
        cairo_arc(cairoContext, minX + radius, maxY - radius, radius, halfPi, Double.pi)
        cairo_arc(cairoContext, minX + radius, minY + radius, radius, Double.pi, 3 * halfPi)
        cairo_close_path(cairoContext)
    }
}

#endif
#endif
