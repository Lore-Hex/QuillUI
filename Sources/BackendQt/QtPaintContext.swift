// QtPaintContext.swift — QPainter-backed PaintContext for BackendQt.
//
// This is the Qt keystone for QuillPaint. QuillPaint draws macOS-style control
// chrome (filled / stroked rounded rects, lines, text runs) through its
// renderer-agnostic `PaintContext` protocol; QtPaintContext implements those
// four primitives by forwarding to the CQtBridge QPainter shims. It is the Qt
// analogue of QuillPaintCairo's `CairoPaintContext`:
//
//   * CairoPaintContext wraps a live `cairo_t *` handed in by a GtkDrawingArea
//     draw callback.
//   * QtPaintContext wraps a live `QPainter *` handed in by QuillQtPaintWidget's
//     paintEvent (surfaced through the bridge's paint callback as a `void *`).
//
// Lifetime: the QPainter handle is only valid for the duration of one paint
// callback. QtPaintContext must therefore be constructed inside the paint
// callback and discarded when it returns — never stored across paints. The
// paintable widget + callback wiring is the host's job (deferred per the
// keystone scope); this type only proves the bridge is *usable* as a
// PaintContext and compiles on the Qt backend.

#if canImport(CQtBridge)
import CQtBridge
import QuillPaint
import Foundation

/// `PaintContext` adapter that draws into a Qt `QPainter` via the CQtBridge
/// QPainter shims. Constructed with the opaque painter handle delivered to a
/// `quill_qt_bridge_paint_callback`.
///
/// `struct` (value type) intentionally — the painter handle is borrowed, not
/// owned, so there is nothing to deinit; `PaintContext` requires `AnyObject`,
/// so the conformance is provided by the boxing wrapper `QtPaintContextBox`
/// below, which is what callers hand to QuillPaint.
public struct QtPainter {
    /// The borrowed `QPainter *` (the bridge's `void *`). Valid only for the
    /// enclosing paint callback.
    public let handle: UnsafeMutableRawPointer

    public init(handle: UnsafeMutableRawPointer) {
        self.handle = handle
    }

    /// Convenience for callers holding the renderer's `OpaquePointer` form.
    public init(opaque: OpaquePointer) {
        self.handle = UnsafeMutableRawPointer(opaque)
    }
}

/// Reference-typed `PaintContext` over a `QtPainter`. QuillPaint's protocol is
/// `AnyObject`-constrained (so controls can hold a context across calls within
/// one paint), hence a `final class` rather than a bare struct.
public final class QtPaintContext: PaintContext {
    private let painter: QtPainter

    /// Construct from the bridge's raw `QPainter *` handle (the `void *`
    /// delivered to a paint callback).
    public init(painterHandle: UnsafeMutableRawPointer) {
        self.painter = QtPainter(handle: painterHandle)
    }

    /// Construct from the renderer's `OpaquePointer` handle convention.
    public convenience init(opaque: OpaquePointer) {
        self.init(painterHandle: UnsafeMutableRawPointer(opaque))
    }

    // MARK: - PaintContext

    public func fillRoundedRect(
        _ rect: PaintRect,
        cornerRadius: Double,
        color: PaintColor
    ) {
        quill_qt_painter_fill_rounded_rect(
            painter.handle,
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
            cornerRadius,
            color.red, color.green, color.blue, color.alpha
        )
    }

    public func strokeRoundedRect(
        _ rect: PaintRect,
        cornerRadius: Double,
        color: PaintColor,
        lineWidth: Double
    ) {
        quill_qt_painter_stroke_rounded_rect(
            painter.handle,
            rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
            cornerRadius,
            color.red, color.green, color.blue, color.alpha,
            lineWidth
        )
    }

    public func strokeLine(
        from start: PaintPoint,
        to end: PaintPoint,
        color: PaintColor,
        lineWidth: Double
    ) {
        quill_qt_painter_stroke_line(
            painter.handle,
            start.x, start.y, end.x, end.y,
            color.red, color.green, color.blue, color.alpha,
            lineWidth
        )
    }

    public func drawText(
        _ string: String,
        at point: PaintPoint,
        font: PaintFont,
        color: PaintColor
    ) {
        guard !string.isEmpty else { return }
        // Resolve the macOS font token to a locally-available family the same
        // way the Cairo backend does, so the two paths pick equivalent fonts.
        // (CALIBRATION RISK: QPainter and Cairo "toy" text use different
        // shapers, so per-glyph advances can diverge by a sub-pixel; the
        // bridge applies the same ascent-baseline drop + bold>=600 rule as the
        // Cairo path to keep them close. Fine-tuning is a follow-up, not a
        // keystone concern.)
        let resolved = MacFontResolution.resolve(font)
        let family = resolved.family == MacFontResolution.systemDefaultFamily
            ? ""  // empty -> bridge leaves QFont's default family
            : resolved.family

        string.withCString { cText in
            family.withCString { cFamily in
                quill_qt_painter_draw_text(
                    painter.handle,
                    cText,
                    point.x, point.y,
                    cFamily,
                    resolved.size,
                    Int32(resolved.weight),
                    color.red, color.green, color.blue, color.alpha
                )
            }
        }
    }
}

#endif
