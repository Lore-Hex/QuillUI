// QuillNSViewDrawingHost.swift
// ============================
// Custom-draw NSView content on GTK: a GtkDrawingArea whose draw func runs the
// view's `draw(_:)` against a Cairo-backed CGContext (QuillFoundation's
// pluggable QuillCGContextBackend). This is the rendering path for
// NSViewRepresentable (SwiftUI) hosts — e.g. SolderScope's MicroscopeNSView —
// and for any NSView subclass that paints with NSGraphicsContext.current.
//
// Threading: everything here runs on the GTK main loop thread (the process
// main thread), matching AppKit's main-thread drawing contract.

#if os(Linux)

import CGtk4
import AppKit
import QuillFoundation
import Foundation

// MARK: - Cairo-backed CGContext drawing

/// CGContext semantics on top of cairo_t. CG keeps separate fill/stroke
/// colors and a global alpha; cairo has a single source — so colors are
/// stored here and applied at fill/stroke time. cairo_save/restore does NOT
/// save the current path (matching CG's path-survives-state behavior), but
/// does save source/CTM/clip, which mirrors CG's gstate.
public final class CairoCGContextBackend: QuillCGContextBackend {
    private let cr: OpaquePointer
    private struct State {
        var fill: [CGFloat] = [0, 0, 0, 1]
        var stroke: [CGFloat] = [0, 0, 0, 1]
        var alpha: CGFloat = 1
    }
    private var state = State()
    private var stack: [State] = []

    public init(cr: OpaquePointer) {
        self.cr = cr
    }

    private func applySource(_ rgba: [CGFloat]) {
        cairo_set_source_rgba(cr,
                              Double(rgba[0]), Double(rgba[1]), Double(rgba[2]),
                              Double(rgba[3] * state.alpha))
    }

    public func saveGState() {
        cairo_save(cr)
        stack.append(state)
    }

    public func restoreGState() {
        cairo_restore(cr)
        if let prev = stack.popLast() { state = prev }
    }

    public func translateBy(x: CGFloat, y: CGFloat) { cairo_translate(cr, Double(x), Double(y)) }
    public func scaleBy(x: CGFloat, y: CGFloat) { cairo_scale(cr, Double(x), Double(y)) }
    public func rotate(by angle: CGFloat) { cairo_rotate(cr, Double(angle)) }

    public func setFillColor(_ rgba: [CGFloat]) { state.fill = rgba }
    public func setStrokeColor(_ rgba: [CGFloat]) { state.stroke = rgba }
    public func setLineWidth(_ width: CGFloat) { cairo_set_line_width(cr, Double(width)) }
    public func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }

    public func setLineCap(_ cap: CGLineCap) {
        switch cap {
        case .butt: cairo_set_line_cap(cr, CAIRO_LINE_CAP_BUTT)
        case .round: cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
        case .square: cairo_set_line_cap(cr, CAIRO_LINE_CAP_SQUARE)
        }
    }

    public func setLineJoin(_ join: CGLineJoin) {
        switch join {
        case .miter: cairo_set_line_join(cr, CAIRO_LINE_JOIN_MITER)
        case .round: cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
        case .bevel: cairo_set_line_join(cr, CAIRO_LINE_JOIN_BEVEL)
        }
    }

    public func fill(_ rect: CGRect) {
        applySource(state.fill)
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_fill(cr)
    }

    public func stroke(_ rect: CGRect) {
        applySource(state.stroke)
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_stroke(cr)
    }

    private func appendEllipsePath(in rect: CGRect) {
        // Build the path under a saved CTM; cairo retains the path across
        // cairo_restore, so the later stroke keeps a uniform line width.
        cairo_save(cr)
        cairo_translate(cr, Double(rect.midX), Double(rect.midY))
        cairo_scale(cr, Double(rect.size.width / 2), Double(rect.size.height / 2))
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0, 0, 1, 0, 2 * Double.pi)
        cairo_restore(cr)
    }

    public func fillEllipse(in rect: CGRect) {
        applySource(state.fill)
        appendEllipsePath(in: rect)
        cairo_fill(cr)
    }

    public func strokeEllipse(in rect: CGRect) {
        applySource(state.stroke)
        appendEllipsePath(in: rect)
        cairo_stroke(cr)
    }

    public func clear(_ rect: CGRect) {
        cairo_save(cr)
        cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR)
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_fill(cr)
        cairo_restore(cr)
    }

    public func strokeLineSegments(between points: [CGPoint]) {
        applySource(state.stroke)
        var i = 0
        while i + 1 < points.count {
            cairo_move_to(cr, Double(points[i].x), Double(points[i].y))
            cairo_line_to(cr, Double(points[i + 1].x), Double(points[i + 1].y))
            i += 2
        }
        cairo_stroke(cr)
    }

    public func beginPath() { cairo_new_path(cr) }
    public func closePath() { cairo_close_path(cr) }
    public func move(to point: CGPoint) { cairo_move_to(cr, Double(point.x), Double(point.y)) }
    public func addLine(to point: CGPoint) { cairo_line_to(cr, Double(point.x), Double(point.y)) }

    public func addRect(_ rect: CGRect) {
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
    }

    public func addEllipse(in rect: CGRect) { appendEllipsePath(in: rect) }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                       endAngle: CGFloat, clockwise: Bool) {
        if clockwise {
            cairo_arc_negative(cr, Double(center.x), Double(center.y),
                               Double(radius), Double(startAngle), Double(endAngle))
        } else {
            cairo_arc(cr, Double(center.x), Double(center.y),
                      Double(radius), Double(startAngle), Double(endAngle))
        }
    }

    public func fillPath() {
        applySource(state.fill)
        cairo_fill(cr)
    }

    public func strokePath() {
        applySource(state.stroke)
        cairo_stroke(cr)
    }

    public func clip() { cairo_clip(cr) }

    public func clip(to rect: CGRect) {
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_clip(cr)
    }

    public func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality) {
        guard let cgImage = image as? CGImage,
              var pixels = cgImage.quillBGRAPixels,
              cgImage.width > 0, cgImage.height > 0 else { return }
        let stride = cgImage.quillBytesPerRow > 0 ? cgImage.quillBytesPerRow : cgImage.width * 4
        let width = cgImage.width
        let height = cgImage.height

        pixels.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            guard let surface = cairo_image_surface_create_for_data(
                base.assumingMemoryBound(to: UInt8.self),
                CAIRO_FORMAT_ARGB32,
                Int32(width), Int32(height), Int32(stride)
            ) else { return }
            defer { cairo_surface_destroy(surface) }

            cairo_save(cr)
            cairo_translate(cr, Double(rect.origin.x), Double(rect.origin.y))
            cairo_scale(cr, Double(rect.size.width) / Double(width),
                        Double(rect.size.height) / Double(height))
            cairo_set_source_surface(cr, surface, 0, 0)
            if let pattern = cairo_get_source(cr) {
                let filter: cairo_filter_t =
                    (interpolationQuality == .none) ? CAIRO_FILTER_NEAREST : CAIRO_FILTER_GOOD
                cairo_pattern_set_filter(pattern, filter)
            }
            cairo_rectangle(cr, 0, 0, Double(width), Double(height))
            cairo_fill(cr)
            cairo_restore(cr)
        }
    }
}

// MARK: - GtkDrawingArea-backed NSView

private final class _DrawingHostBox {
    let view: NSView
    init(view: NSView) { self.view = view }
}

extension NSView {
    /// A GtkDrawingArea that renders this view's `draw(_:)` through a
    /// Cairo-backed CGContext, with `needsDisplay` wired to queue_draw.
    /// Returns nil when GTK can't initialize (headless without a display).
    public func ensureGtkCustomDrawWidget() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }

        let area = gtk_drawing_area_new()
        gtk_widget_set_hexpand(area, 1)
        gtk_widget_set_vexpand(area, 1)

        let box = _DrawingHostBox(view: self)
        let userData = Unmanaged.passRetained(box).toOpaque()

        gtk_drawing_area_set_draw_func(
            UnsafeMutablePointer<GtkDrawingArea>(OpaquePointer(area)),
            { _, cr, width, height, userData in
                guard let cr, let userData else { return }
                let box = Unmanaged<_DrawingHostBox>.fromOpaque(userData).takeUnretainedValue()
                let view = box.view

                let bounds = NSRect(x: 0, y: 0,
                                    width: CGFloat(width), height: CGFloat(height))
                view.frame = bounds
                view.bounds = bounds

                let backend = CairoCGContextBackend(cr: cr)
                // AppKit's default coordinate space is bottom-left; flipped
                // views (isFlipped == true) draw top-left like GTK/Cairo.
                if !view.isFlipped {
                    cairo_translate(cr, 0, Double(height))
                    cairo_scale(cr, 1, -1)
                }
                let cgContext = CGContext(quillBackend: backend)
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(
                    cgContext: cgContext, flipped: view.isFlipped)
                view.draw(bounds)
                NSGraphicsContext.current = previous
            },
            userData,
            { userData in
                guard let userData else { return }
                Unmanaged<_DrawingHostBox>.fromOpaque(userData).release()
            }
        )

        let areaPointer = OpaquePointer(area)
        quillDisplayInvalidationHandler = { [weak self] in
            _ = self
            gtk_widget_queue_draw(area)
        }
        return areaPointer
    }
}

#endif
