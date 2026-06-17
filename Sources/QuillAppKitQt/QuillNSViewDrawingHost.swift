// QuillNSViewDrawingHost.swift
// ============================
// Custom-draw NSView content on Qt: a QWidget whose paintEvent renders into a
// Cairo image surface, then blits that surface through Qt. This intentionally
// parallels Sources/QuillAppKitGTK/QuillNSViewDrawingHost.swift so
// NSViewRepresentable drawing continues to flow through the shared
// CGContext(quillBackend:) abstraction.

#if os(Linux)

import AppKit
import CCairo
import CQuillAppKitQt
import Foundation
import QuillFoundation

// MARK: - Cairo-backed CGContext drawing

/// CGContext semantics on top of cairo_t. Keep this in sync with the GTK twin
/// unless/until the Cairo backend is factored into a shared toolkit-neutral
/// target.
public final class QtCairoCGContextBackend: QuillCGContextBackend {
    private let cr: OpaquePointer
    private struct State {
        var fill: [CGFloat] = [0, 0, 0, 1]
        var stroke: [CGFloat] = [0, 0, 0, 1]
        var alpha: CGFloat = 1
        var blendMode: CGBlendMode = .normal
        var shadow: Shadow?
    }
    private struct Shadow {
        var offset: CGSize
        var blur: CGFloat
        var colorRGBA: [CGFloat]
    }
    private var state = State()
    private var stack: [State] = []
    private var transparencyLayerStack: [State] = []

    public init(cr: OpaquePointer) {
        self.cr = cr
    }

    private func applySource(_ rgba: [CGFloat]) {
        cairo_set_source_rgba(cr,
                              Double(rgba[0]), Double(rgba[1]), Double(rgba[2]),
                              Double(rgba[3] * state.alpha))
    }

    private func applyShadowSource() -> Shadow? {
        guard let shadow = state.shadow else { return nil }
        let rgba = shadow.colorRGBA
        guard rgba.count >= 4 else { return nil }
        cairo_set_source_rgba(cr,
                              Double(rgba[0]), Double(rgba[1]), Double(rgba[2]),
                              Double(rgba[3] * state.alpha))
        return shadow
    }

    private func withShadow(_ draw: () -> Void) {
        guard let shadow = state.shadow else { return }
        cairo_save(cr)
        cairo_translate(cr, Double(shadow.offset.width), Double(shadow.offset.height))
        _ = applyShadowSource()
        draw()
        cairo_restore(cr)
    }

    private func drawShadowForCurrentPath(stroke: Bool, rule: CGPathFillRule = .winding) {
        guard state.shadow != nil, let path = cairo_copy_path(cr) else { return }
        defer { cairo_path_destroy(path) }
        cairo_save(cr)
        cairo_new_path(cr)
        if let shadow = applyShadowSource() {
            cairo_translate(cr, Double(shadow.offset.width), Double(shadow.offset.height))
            cairo_append_path(cr, path)
            withFillRule(rule) {
                stroke ? cairo_stroke(cr) : cairo_fill(cr)
            }
        }
        cairo_restore(cr)
    }

    private func setOperator(for mode: CGBlendMode) {
        cairo_set_operator(cr, Self.cairoOperator(for: mode))
    }

    private static func cairoOperator(for mode: CGBlendMode) -> cairo_operator_t {
        switch mode {
        case .clear: return CAIRO_OPERATOR_CLEAR
        case .copy: return CAIRO_OPERATOR_SOURCE
        case .sourceIn: return CAIRO_OPERATOR_IN
        case .sourceOut: return CAIRO_OPERATOR_OUT
        case .sourceAtop: return CAIRO_OPERATOR_ATOP
        case .destinationOver: return CAIRO_OPERATOR_DEST_OVER
        case .destinationIn: return CAIRO_OPERATOR_DEST_IN
        case .destinationOut: return CAIRO_OPERATOR_DEST_OUT
        case .destinationAtop: return CAIRO_OPERATOR_DEST_ATOP
        case .xor: return CAIRO_OPERATOR_XOR
        case .plusLighter: return CAIRO_OPERATOR_ADD
        case .multiply: return CAIRO_OPERATOR_MULTIPLY
        case .screen: return CAIRO_OPERATOR_SCREEN
        case .overlay: return CAIRO_OPERATOR_OVERLAY
        case .darken: return CAIRO_OPERATOR_DARKEN
        case .lighten: return CAIRO_OPERATOR_LIGHTEN
        case .colorDodge: return CAIRO_OPERATOR_COLOR_DODGE
        case .colorBurn: return CAIRO_OPERATOR_COLOR_BURN
        case .softLight: return CAIRO_OPERATOR_SOFT_LIGHT
        case .hardLight: return CAIRO_OPERATOR_HARD_LIGHT
        case .difference: return CAIRO_OPERATOR_DIFFERENCE
        case .exclusion: return CAIRO_OPERATOR_EXCLUSION
        case .hue: return CAIRO_OPERATOR_HSL_HUE
        case .saturation: return CAIRO_OPERATOR_HSL_SATURATION
        case .color: return CAIRO_OPERATOR_HSL_COLOR
        case .luminosity: return CAIRO_OPERATOR_HSL_LUMINOSITY
        case .normal, .plusDarker: return CAIRO_OPERATOR_OVER
        }
    }

    private func withFillRule(_ rule: CGPathFillRule, _ body: () -> Void) {
        let previous = cairo_get_fill_rule(cr)
        switch rule {
        case .winding:
            cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING)
        case .evenOdd:
            cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
        }
        body()
        cairo_set_fill_rule(cr, previous)
    }

    public func saveGState() {
        cairo_save(cr)
        stack.append(state)
    }

    public func restoreGState() {
        cairo_restore(cr)
        if let prev = stack.popLast() {
            state = prev
            setOperator(for: state.blendMode)
        }
    }

    public func translateBy(x: CGFloat, y: CGFloat) { cairo_translate(cr, Double(x), Double(y)) }
    public func scaleBy(x: CGFloat, y: CGFloat) { cairo_scale(cr, Double(x), Double(y)) }
    public func rotate(by angle: CGFloat) { cairo_rotate(cr, Double(angle)) }
    public func concatenate(_ transform: CGAffineTransform) {
        var matrix = cairo_matrix_t()
        cairo_matrix_init(
            &matrix,
            Double(transform.a),
            Double(transform.b),
            Double(transform.c),
            Double(transform.d),
            Double(transform.tx),
            Double(transform.ty)
        )
        cairo_transform(cr, &matrix)
    }

    public func setFillColor(_ rgba: [CGFloat]) { state.fill = rgba }
    public func setStrokeColor(_ rgba: [CGFloat]) { state.stroke = rgba }
    public func setLineWidth(_ width: CGFloat) { cairo_set_line_width(cr, Double(width)) }
    public func setMiterLimit(_ limit: CGFloat) { cairo_set_miter_limit(cr, Double(limit)) }
    public func setShouldAntialias(_ shouldAntialias: Bool) {
        cairo_set_antialias(cr, shouldAntialias ? CAIRO_ANTIALIAS_DEFAULT : CAIRO_ANTIALIAS_NONE)
    }
    public func setAlpha(_ alpha: CGFloat) { state.alpha = alpha }
    public func setBlendMode(_ mode: CGBlendMode) {
        state.blendMode = mode
        setOperator(for: mode)
    }
    public func setShadow(offset: CGSize, blur: CGFloat, colorRGBA: [CGFloat]?) {
        guard let colorRGBA else {
            state.shadow = nil
            return
        }
        state.shadow = Shadow(offset: offset, blur: blur, colorRGBA: colorRGBA)
    }

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
        withShadow {
            cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                            Double(rect.size.width), Double(rect.size.height))
            cairo_fill(cr)
        }
        applySource(state.fill)
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_fill(cr)
    }

    public func stroke(_ rect: CGRect) {
        withShadow {
            cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                            Double(rect.size.width), Double(rect.size.height))
            cairo_stroke(cr)
        }
        applySource(state.stroke)
        cairo_rectangle(cr, Double(rect.origin.x), Double(rect.origin.y),
                        Double(rect.size.width), Double(rect.size.height))
        cairo_stroke(cr)
    }

    private func appendEllipsePath(in rect: CGRect) {
        cairo_save(cr)
        cairo_translate(cr, Double(rect.midX), Double(rect.midY))
        cairo_scale(cr, Double(rect.size.width / 2), Double(rect.size.height / 2))
        cairo_new_sub_path(cr)
        cairo_arc(cr, 0, 0, 1, 0, 2 * Double.pi)
        cairo_restore(cr)
    }

    public func fillEllipse(in rect: CGRect) {
        withShadow {
            appendEllipsePath(in: rect)
            cairo_fill(cr)
        }
        applySource(state.fill)
        appendEllipsePath(in: rect)
        cairo_fill(cr)
    }

    public func strokeEllipse(in rect: CGRect) {
        withShadow {
            appendEllipsePath(in: rect)
            cairo_stroke(cr)
        }
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
        withShadow {
            var i = 0
            while i + 1 < points.count {
                cairo_move_to(cr, Double(points[i].x), Double(points[i].y))
                cairo_line_to(cr, Double(points[i + 1].x), Double(points[i + 1].y))
                i += 2
            }
            cairo_stroke(cr)
        }
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

    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        var currentX = 0.0
        var currentY = 0.0
        cairo_get_current_point(cr, &currentX, &currentY)
        let current = CGPoint(x: currentX, y: currentY)
        let control1 = CGPoint(
            x: current.x + (control.x - current.x) * 2 / 3,
            y: current.y + (control.y - current.y) * 2 / 3
        )
        let control2 = CGPoint(
            x: end.x + (control.x - end.x) * 2 / 3,
            y: end.y + (control.y - end.y) * 2 / 3
        )
        addCurve(to: end, control1: control1, control2: control2)
    }

    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        cairo_curve_to(
            cr,
            Double(control1.x), Double(control1.y),
            Double(control2.x), Double(control2.y),
            Double(end.x), Double(end.y)
        )
    }

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
        drawShadowForCurrentPath(stroke: false)
        applySource(state.fill)
        cairo_fill(cr)
    }

    public func fillPath(using rule: CGPathFillRule) {
        drawShadowForCurrentPath(stroke: false, rule: rule)
        applySource(state.fill)
        withFillRule(rule) { cairo_fill(cr) }
    }

    public func strokePath() {
        drawShadowForCurrentPath(stroke: true)
        applySource(state.stroke)
        cairo_stroke(cr)
    }

    public func clip() { cairo_clip(cr) }

    public func clip(using rule: CGPathFillRule) {
        withFillRule(rule) {
            cairo_clip(cr)
        }
    }

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

        guard stride == Int(cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(width))) else { return }
        pixels.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            let surface = cairo_image_surface_create_for_data(
                base.assumingMemoryBound(to: UInt8.self),
                CAIRO_FORMAT_ARGB32,
                Int32(width), Int32(height), Int32(stride)
            )
            guard let surface, cairo_surface_status(surface) == CAIRO_STATUS_SUCCESS else {
                if let surface { cairo_surface_destroy(surface) }
                return
            }
            defer { cairo_surface_destroy(surface) }

            if let shadow = state.shadow {
                cairo_save(cr)
                cairo_translate(cr, Double(rect.origin.x + shadow.offset.width), Double(rect.maxY + shadow.offset.height))
                cairo_scale(cr, Double(rect.size.width) / Double(width),
                            -Double(rect.size.height) / Double(height))
                _ = applyShadowSource()
                cairo_mask_surface(cr, surface, 0, 0)
                cairo_restore(cr)
            }

            cairo_save(cr)
            cairo_translate(cr, Double(rect.origin.x), Double(rect.maxY))
            cairo_scale(cr, Double(rect.size.width) / Double(width),
                        -Double(rect.size.height) / Double(height))
            cairo_set_source_surface(cr, surface, 0, 0)
            if let pattern = cairo_get_source(cr) {
                let filter: cairo_filter_t =
                    (interpolationQuality == .none) ? CAIRO_FILTER_NEAREST : CAIRO_FILTER_GOOD
                cairo_pattern_set_filter(pattern, filter)
            }
            cairo_rectangle(cr, 0, 0, Double(width), Double(height))
            cairo_clip(cr)
            cairo_paint_with_alpha(cr, Double(state.alpha))
            cairo_restore(cr)
        }
    }

    public func beginTransparencyLayer(auxiliaryInfo: Any?) {
        _ = auxiliaryInfo
        transparencyLayerStack.append(state)
        cairo_push_group(cr)
        state.alpha = 1
        state.blendMode = .normal
        state.shadow = nil
        setOperator(for: .normal)
    }

    public func endTransparencyLayer() {
        guard let layerState = transparencyLayerStack.popLast() else { return }
        cairo_pop_group_to_source(cr)
        state = layerState
        setOperator(for: state.blendMode)

        guard let groupPattern = cairo_get_source(cr) else { return }
        let referencedPattern = cairo_pattern_reference(groupPattern)
        if state.shadow != nil {
            cairo_save(cr)
            if let shadow = applyShadowSource() {
                cairo_translate(cr, Double(shadow.offset.width), Double(shadow.offset.height))
                cairo_mask(cr, referencedPattern)
            }
            cairo_restore(cr)
        }

        cairo_set_source(cr, referencedPattern)
        cairo_paint_with_alpha(cr, Double(state.alpha))
        cairo_pattern_destroy(referencedPattern)
    }
}

// MARK: - QWidget-backed NSView

private final class _QtDrawingHostBox {
    let view: NSView
    var widget: UnsafeMutableRawPointer?

    init(view: NSView) {
        self.view = view
    }
}

extension NSView {
    /// A QWidget that renders this view's `draw(_:)` through a Cairo-backed
    /// CGContext, with `needsDisplay` wired to QWidget::update().
    public func ensureQtCustomDrawWidget() -> UnsafeMutableRawPointer? {
        guard QuillQt.ensureInitialized() else { return nil }
        if let existing = qtWidgetHandle { return existing }

        let box = _QtDrawingHostBox(view: self)
        let userData = Unmanaged.passRetained(box).toOpaque()

        guard let widget = quill_appkit_qt_drawing_view_new(
            { cr, width, height, userData in
                guard let cr, let userData else { return }
                let box = Unmanaged<_QtDrawingHostBox>.fromOpaque(userData).takeUnretainedValue()
                let view = box.view

                MainActor.assumeIsolated {
                    let bounds = NSRect(x: 0, y: 0,
                                        width: CGFloat(width), height: CGFloat(height))
                    view.frame = bounds
                    view.bounds = bounds

                    let backend = QtCairoCGContextBackend(cr: OpaquePointer(cr))
                    if !view.isFlipped {
                        cairo_translate(OpaquePointer(cr), 0, Double(height))
                        cairo_scale(OpaquePointer(cr), 1, -1)
                    }
                    let cgContext = CGContext(quillBackend: backend)
                    let previous = NSGraphicsContext.current
                    NSGraphicsContext.current = NSGraphicsContext(
                        cgContext: cgContext, flipped: view.isFlipped)
                    view.draw(bounds)
                    NSGraphicsContext.current = previous
                }
            },
            userData,
            { userData in
                guard let userData else { return }
                let box = Unmanaged<_QtDrawingHostBox>.fromOpaque(userData)
                box.takeUnretainedValue().widget = nil
                box.release()
            }
        ) else {
            Unmanaged<_QtDrawingHostBox>.fromOpaque(userData).release()
            return nil
        }

        box.widget = widget
        qtWidgetHandle = widget
        quillDisplayInvalidationHandler = {
            guard let live = box.widget else { return }
            quill_appkit_qt_view_update(live)
        }
        return widget
    }
}

#endif
