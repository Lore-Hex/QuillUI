// QuillNSViewDrawingHostQt.swift
// ===============================
// Custom-draw NSView content on Qt: a QWidget whose paintEvent runs the
// view's `draw(_:)` against a QPainter-backed CGContext. This is the Qt
// sibling of QuillAppKitGTK's GtkDrawingArea host.

#if os(Linux)

import AppKit
import CQuillAppKitQt
import Foundation

public final class QtCGContextBackend: QuillCGContextBackend {
    private let paintContext: UnsafeMutableRawPointer

    public init(paintContext: UnsafeMutableRawPointer) {
        self.paintContext = paintContext
    }

    private func component(_ rgba: [CGFloat], _ index: Int, fallback: CGFloat) -> Double {
        Double(index < rgba.count ? rgba[index] : fallback)
    }

    public func saveGState() { quill_appkit_qt_paint_save(paintContext) }
    public func restoreGState() { quill_appkit_qt_paint_restore(paintContext) }
    public func translateBy(x: CGFloat, y: CGFloat) { quill_appkit_qt_paint_translate(paintContext, Double(x), Double(y)) }
    public func scaleBy(x: CGFloat, y: CGFloat) { quill_appkit_qt_paint_scale(paintContext, Double(x), Double(y)) }
    public func rotate(by angle: CGFloat) { quill_appkit_qt_paint_rotate(paintContext, Double(angle)) }

    public func setFillColor(_ rgba: [CGFloat]) {
        quill_appkit_qt_paint_set_fill_color(
            paintContext,
            component(rgba, 0, fallback: 0),
            component(rgba, 1, fallback: 0),
            component(rgba, 2, fallback: 0),
            component(rgba, 3, fallback: 1)
        )
    }

    public func setStrokeColor(_ rgba: [CGFloat]) {
        quill_appkit_qt_paint_set_stroke_color(
            paintContext,
            component(rgba, 0, fallback: 0),
            component(rgba, 1, fallback: 0),
            component(rgba, 2, fallback: 0),
            component(rgba, 3, fallback: 1)
        )
    }

    public func setLineWidth(_ width: CGFloat) { quill_appkit_qt_paint_set_line_width(paintContext, Double(width)) }
    public func setLineCap(_ cap: CGLineCap) { quill_appkit_qt_paint_set_line_cap(paintContext, cap.rawValue) }
    public func setLineJoin(_ join: CGLineJoin) { quill_appkit_qt_paint_set_line_join(paintContext, join.rawValue) }
    public func setAlpha(_ alpha: CGFloat) { quill_appkit_qt_paint_set_alpha(paintContext, Double(alpha)) }

    public func fill(_ rect: CGRect) {
        quill_appkit_qt_paint_fill_rect(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func fillEllipse(in rect: CGRect) {
        quill_appkit_qt_paint_fill_ellipse(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func stroke(_ rect: CGRect) {
        quill_appkit_qt_paint_stroke_rect(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func strokeEllipse(in rect: CGRect) {
        quill_appkit_qt_paint_stroke_ellipse(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func clear(_ rect: CGRect) {
        quill_appkit_qt_paint_clear_rect(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func strokeLineSegments(between points: [CGPoint]) {
        var pairs = points.flatMap { [Double($0.x), Double($0.y)] }
        pairs.withUnsafeBufferPointer { buffer in
            quill_appkit_qt_paint_stroke_line_segments(
                paintContext,
                buffer.baseAddress,
                Int32(points.count)
            )
        }
    }

    public func beginPath() { quill_appkit_qt_paint_begin_path(paintContext) }
    public func closePath() { quill_appkit_qt_paint_close_path(paintContext) }
    public func move(to point: CGPoint) { quill_appkit_qt_paint_move_to(paintContext, Double(point.x), Double(point.y)) }
    public func addLine(to point: CGPoint) { quill_appkit_qt_paint_add_line_to(paintContext, Double(point.x), Double(point.y)) }

    public func addRect(_ rect: CGRect) {
        quill_appkit_qt_paint_add_rect(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func addEllipse(in rect: CGRect) {
        quill_appkit_qt_paint_add_ellipse(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                       endAngle: CGFloat, clockwise: Bool) {
        quill_appkit_qt_paint_add_arc(
            paintContext,
            Double(center.x), Double(center.y), Double(radius),
            Double(startAngle), Double(endAngle), clockwise ? 1 : 0
        )
    }

    public func fillPath() { quill_appkit_qt_paint_fill_path(paintContext) }
    public func strokePath() { quill_appkit_qt_paint_stroke_path(paintContext) }
    public func clip() { quill_appkit_qt_paint_clip(paintContext) }

    public func clip(to rect: CGRect) {
        quill_appkit_qt_paint_clip_rect(
            paintContext,
            Double(rect.origin.x), Double(rect.origin.y),
            Double(rect.size.width), Double(rect.size.height)
        )
    }

    public func draw(_ image: Any, in rect: CGRect, interpolationQuality: CGInterpolationQuality) {
        guard let cgImage = image as? CGImage,
              var pixels = cgImage.quillBGRAPixels,
              cgImage.width > 0, cgImage.height > 0 else { return }
        let stride = cgImage.quillBytesPerRow > 0 ? cgImage.quillBytesPerRow : cgImage.width * 4

        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            saveGState()
            translateBy(x: rect.origin.x, y: rect.maxY)
            scaleBy(x: rect.size.width / CGFloat(cgImage.width),
                    y: -rect.size.height / CGFloat(cgImage.height))
            quill_appkit_qt_paint_draw_bgra_image(
                paintContext,
                base,
                Int32(cgImage.width),
                Int32(cgImage.height),
                Int32(stride),
                0,
                0,
                Double(cgImage.width),
                Double(cgImage.height),
                interpolationQuality == .none ? 1 : 0
            )
            restoreGState()
        }
    }
}

private final class _QtDrawingHostBox {
    let view: NSView
    var widget: OpaquePointer?

    init(view: NSView) {
        self.view = view
    }
}

private func quillQtRaw(_ widget: OpaquePointer) -> UnsafeMutableRawPointer {
    UnsafeMutableRawPointer(widget)
}

extension NSView {
    /// A QWidget that renders this view's `draw(_:)` through a QPainter-backed
    /// CGContext, with `needsDisplay` wired to QWidget.update().
    public func ensureQtCustomDrawWidget() -> OpaquePointer? {
        guard QuillQt.ensureInitialized() else { return nil }
        if let existing = qtWidgetHandle {
            return OpaquePointer(existing)
        }

        let box = _QtDrawingHostBox(view: self)
        let userData = Unmanaged.passRetained(box).toOpaque()

        let draw: quill_appkit_qt_draw_callback = { paintContext, width, height, userData in
            guard let paintContext, let userData else { return }
            let box = Unmanaged<_QtDrawingHostBox>.fromOpaque(userData).takeUnretainedValue()
            let view = box.view

            let bounds = NSRect(
                x: 0,
                y: 0,
                width: CGFloat(width),
                height: CGFloat(height)
            )
            view.frame = bounds
            view.bounds = bounds

            let backend = QtCGContextBackend(paintContext: paintContext)
            if !view.isFlipped {
                backend.translateBy(x: 0, y: CGFloat(height))
                backend.scaleBy(x: 1, y: -1)
            }

            let previous = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(
                cgContext: CGContext(quillBackend: backend),
                flipped: view.isFlipped
            )
            view.draw(bounds)
            NSGraphicsContext.current = previous
        }

        let destroy: quill_appkit_qt_destroy_callback = { userData in
            guard let userData else { return }
            let box = Unmanaged<_QtDrawingHostBox>.fromOpaque(userData)
            box.takeUnretainedValue().widget = nil
            box.release()
        }

        guard let rawWidget = quill_appkit_qt_custom_draw_view_new(draw, userData, destroy) else {
            Unmanaged<_QtDrawingHostBox>.fromOpaque(userData).release()
            return nil
        }

        let widget = OpaquePointer(rawWidget)
        qtWidgetHandle = rawWidget
        quill_appkit_qt_widget_mark_external_mount(rawWidget, 1)
        box.widget = widget
        quillDisplayInvalidationHandler = {
            guard let live = box.widget else { return }
            quill_appkit_qt_widget_update(quillQtRaw(live))
        }
        return widget
    }
}

public func quillQtDetachFromParent(_ widget: OpaquePointer) {
    quill_appkit_qt_widget_detach_from_parent(quillQtRaw(widget))
}

public func quillQtRetainWidget(_ widget: OpaquePointer) {
    quill_appkit_qt_widget_mark_external_mount(quillQtRaw(widget), 1)
}

public func quillQtReleaseWidget(_ widget: OpaquePointer) {
    quill_appkit_qt_widget_mark_external_mount(quillQtRaw(widget), 0)
    quill_appkit_qt_widget_delete(quillQtRaw(widget))
}

public func quillQtQueueDraw(_ widget: OpaquePointer) {
    quill_appkit_qt_widget_update(quillQtRaw(widget))
}

#endif
