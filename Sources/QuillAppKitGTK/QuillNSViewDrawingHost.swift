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

import CGTK
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
        if let prev = stack.popLast() { state = prev }
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
        applySource(state.fill)
        cairo_fill(cr)
    }

    public func fillPath(using rule: CGPathFillRule) {
        withFillRule(rule) {
            fillPath()
        }
    }

    public func strokePath() {
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

        // Cairo's ARGB32 stride contract: must match
        // cairo_format_stride_for_width (word-aligned). Camera/decoder BGRA
        // buffers are width*4 which satisfies it; reject anything else rather
        // than hand cairo a mis-strided buffer.
        guard stride == Int(cairo_format_stride_for_width(CAIRO_FORMAT_ARGB32, Int32(width))) else { return }
        pixels.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            // Note: this call never returns nil — failures come back as an
            // error surface, so check the status.
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

            cairo_save(cr)
            // CG semantics: image row 0 maps to the rect's MAX-Y edge in the
            // CURRENT user space (which is why raw CGContext.draw renders
            // images "upside-down" in flipped contexts on Apple too). Flip
            // vertically around the rect so the mapping matches exactly.
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
}

// MARK: - GtkDrawingArea-backed NSView

private final class _DrawingHostBox {
    let view: NSView
    /// Cleared by the GTK destroy notify so the invalidation handler can
    /// never queue_draw a dangling widget (re-renders replace the area).
    var area: OpaquePointer?
    private var dragStarts: [_DrawingHostButton: CGPoint] = [:]
    private var lastPointerLocation: CGPoint?
    private var lastMagnifyScale: CGFloat?
    private var cursorRectBounds: NSRect?
    private weak var currentCursor: NSCursor?
    init(view: NSView) { self.view = view }

    @MainActor
    func syncViewSize(width: Int32, height: Int32) {
        let bounds = NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        view.frame = bounds
        view.bounds = bounds
        if cursorRectBounds != bounds {
            view.discardCursorRects()
            view.resetCursorRects()
            cursorRectBounds = bounds
        }
    }

    @MainActor
    func beginDrag(button: _DrawingHostButton, at location: CGPoint) {
        lastPointerLocation = location
        dragStarts[button] = location
        dispatch(type: button.downEventType, location: location)
        applyCursor(NSCursor.current)
    }

    @MainActor
    func updateDrag(button: _DrawingHostButton, offsetX: CGFloat, offsetY: CGFloat) {
        guard let start = dragStarts[button] else { return }
        let location = CGPoint(x: start.x + offsetX, y: start.y + offsetY)
        lastPointerLocation = location
        dispatch(type: button.draggedEventType, location: location)
    }

    @MainActor
    func endDrag(button: _DrawingHostButton, offsetX: CGFloat, offsetY: CGFloat) {
        defer { dragStarts[button] = nil }
        guard let start = dragStarts[button] else { return }
        let location = CGPoint(x: start.x + offsetX, y: start.y + offsetY)
        lastPointerLocation = location
        dispatch(type: button.upEventType, location: location)
        updateCursor(at: location)
    }

    @MainActor
    func doubleClick(button: _DrawingHostButton, at location: CGPoint) {
        lastPointerLocation = location
        dispatch(type: button.downEventType, location: location, clickCount: 2)
    }

    @MainActor
    func enter(at location: CGPoint) {
        updateCursor(at: location)
        dispatch(type: .mouseEntered, location: location)
    }

    @MainActor
    func move(to location: CGPoint) {
        updateCursor(at: location)
        dispatch(type: .mouseMoved, location: location)
        dispatch(type: .cursorUpdate, location: location)
    }

    @MainActor
    func leave() {
        lastPointerLocation = nil
        clearCursor()
        dispatch(type: .mouseExited, location: .zero)
    }

    @MainActor
    @discardableResult
    func scroll(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        let location = lastPointerLocation ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let event = event(type: .scrollWheel, location: location)
        // GTK's positive Y scroll is down; AppKit's positive scrollingDeltaY is
        // up. Keep both delta fields populated because AppKit clients read both.
        event.scrollingDeltaX = deltaX
        event.scrollingDeltaY = -deltaY
        event.deltaX = deltaX
        event.deltaY = -deltaY
        event.hasPreciseScrollingDeltas = true
        dispatch(event)
        return true
    }

    @MainActor
    func beginMagnifyGesture() {
        lastMagnifyScale = 1
    }

    @MainActor
    @discardableResult
    func magnify(scale: CGFloat) -> Bool {
        guard scale > 0 else { return false }
        let previousScale = lastMagnifyScale ?? 1
        lastMagnifyScale = scale

        let magnification = (scale / previousScale) - 1
        guard abs(magnification) > 0.0001 else { return true }

        let location = lastPointerLocation ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let event = event(type: .magnify, location: location)
        event.magnification = magnification
        dispatch(event)
        return true
    }

    @MainActor
    func endMagnifyGesture() {
        lastMagnifyScale = nil
    }

    @MainActor
    private func updateCursor(at gtkLocation: CGPoint) {
        guard let area else { return }
        let widget = UnsafeMutablePointer<GtkWidget>(area)
        syncViewSize(width: gtk_widget_get_width(widget), height: gtk_widget_get_height(widget))
        lastPointerLocation = gtkLocation

        let viewPoint = NSPoint(
            x: gtkLocation.x,
            y: view.isFlipped ? gtkLocation.y : max(0, boundsHeight - gtkLocation.y)
        )
        applyCursor(view.quillCursor(at: viewPoint))
    }

    @MainActor
    func clearCursor() {
        applyCursor(nil)
    }

    private var boundsHeight: CGFloat {
        view.bounds.size.height
    }

    @MainActor
    private func applyCursor(_ cursor: NSCursor?) {
        if currentCursor === cursor {
            return
        }
        currentCursor = cursor

        guard let area else { return }
        let widget = UnsafeMutableRawPointer(area)
        guard let cursor else {
            NSCursor.arrow.set()
            quill_widget_clear_cursor(widget)
            return
        }
        cursor.set()
        if let name = quillGTKCursorName(for: cursor) {
            name.withCString { quill_widget_set_cursor_name(widget, $0) }
        } else {
            quill_widget_clear_cursor(widget)
        }
    }

    @MainActor
    private func dispatch(type: NSEvent.EventType, location: CGPoint, clickCount: Int = 1) {
        dispatch(event(type: type, location: location, clickCount: clickCount))
    }

    @MainActor
    private func event(type: NSEvent.EventType, location: CGPoint, clickCount: Int = 1) -> NSEvent {
        let event = NSEvent()
        event.type = type
        event.locationInWindow = location
        event.window = view.window
        event.clickCount = clickCount
        return event
    }

    @MainActor
    private func dispatch(_ event: NSEvent) {
        if let window = view.window,
           window.firstResponder === view || window.makeFirstResponder(view) {
            event.window = window
            NSApplication.shared.sendEvent(event)
        } else {
            dispatchDirectly(event)
        }
        if event.quillShouldInvalidateDrawingHost {
            view.needsDisplay = true
        }
    }

    @MainActor
    private func dispatchDirectly(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            view.mouseDown(with: event)
        case .leftMouseUp:
            view.mouseUp(with: event)
        case .rightMouseDown:
            view.rightMouseDown(with: event)
        case .rightMouseUp:
            view.rightMouseUp(with: event)
        case .leftMouseDragged:
            view.mouseDragged(with: event)
        case .rightMouseDragged:
            view.rightMouseDragged(with: event)
        case .mouseMoved:
            view.mouseMoved(with: event)
        case .mouseEntered:
            view.mouseEntered(with: event)
        case .mouseExited:
            view.mouseExited(with: event)
        case .cursorUpdate:
            view.cursorUpdate(with: event)
        case .scrollWheel:
            view.scrollWheel(with: event)
        case .magnify:
            view.magnify(with: event)
        case .smartMagnify:
            view.smartMagnify(with: event)
        case .keyDown:
            view.keyDown(with: event)
        case .keyUp:
            view.keyUp(with: event)
        case .flagsChanged:
            view.flagsChanged(with: event)
        case .appKitDefined, .systemDefined, .applicationDefined, .periodic:
            break
        }
    }
}

private extension NSEvent {
    var quillShouldInvalidateDrawingHost: Bool {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
             .leftMouseDragged, .rightMouseDragged,
             .scrollWheel, .magnify, .smartMagnify:
            true
        case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
             .keyDown, .keyUp, .flagsChanged,
             .appKitDefined, .systemDefined, .applicationDefined, .periodic:
            false
        }
    }
}

private enum _DrawingHostButton: Int, Hashable {
    case left = 1
    case right = 3

    var downEventType: NSEvent.EventType {
        switch self {
        case .left: .leftMouseDown
        case .right: .rightMouseDown
        }
    }

    var draggedEventType: NSEvent.EventType {
        switch self {
        case .left: .leftMouseDragged
        case .right: .rightMouseDragged
        }
    }

    var upEventType: NSEvent.EventType {
        switch self {
        case .left: .leftMouseUp
        case .right: .rightMouseUp
        }
    }

    var gtkButton: guint {
        guint(rawValue)
    }
}

private final class _DrawingHostContext {
    let host: _DrawingHostBox
    let button: _DrawingHostButton?

    init(host: _DrawingHostBox, button: _DrawingHostButton? = nil) {
        self.host = host
        self.button = button
    }
}

private func quillGtkDrawHostContext(from userData: gpointer?) -> _DrawingHostContext? {
    guard let userData else { return nil }
    return Unmanaged<_DrawingHostContext>.fromOpaque(userData).takeUnretainedValue()
}

private func quillRetainedGtkDrawHostContext(
    _ host: _DrawingHostBox,
    button: _DrawingHostButton? = nil
) -> gpointer {
    Unmanaged.passRetained(_DrawingHostContext(host: host, button: button)).toOpaque()
}

private func quillReleaseGtkDrawHostContext(_ userData: gpointer?) {
    guard let userData else { return }
    Unmanaged<_DrawingHostContext>.fromOpaque(userData).release()
}

private func quillInstallGtkDrawHostInputControllers(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox
) {
    quillInstallGtkDrawHostDragController(on: widget, host: host, button: .left)
    quillInstallGtkDrawHostDragController(on: widget, host: host, button: .right)
    quillInstallGtkDrawHostClickController(on: widget, host: host, button: .left)
    quillInstallGtkDrawHostMotionController(on: widget, host: host)
    quillInstallGtkDrawHostScrollController(on: widget, host: host)
    quillInstallGtkDrawHostMagnifyController(on: widget, host: host)
}

private func quillInstallGtkDrawHostDragController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox,
    button: _DrawingHostButton
) {
    let gesture = gtk_gesture_drag_new()!
    gtk_swift_gesture_single_set_button(gesture, button.gtkButton)

    g_signal_connect_data(
        gpointer(gesture),
        "drag-begin",
        unsafeBitCast({ (_: gpointer?, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData), let button = context.button else { return }
            MainActor.assumeIsolated {
                context.host.beginDrag(button: button, at: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host, button: button),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(gesture),
        "drag-update",
        unsafeBitCast({ (_: gpointer?, offsetX: gdouble, offsetY: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData), let button = context.button else { return }
            MainActor.assumeIsolated {
                context.host.updateDrag(button: button, offsetX: CGFloat(offsetX), offsetY: CGFloat(offsetY))
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host, button: button),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(gesture),
        "drag-end",
        unsafeBitCast({ (_: gpointer?, offsetX: gdouble, offsetY: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData), let button = context.button else { return }
            MainActor.assumeIsolated {
                context.host.endDrag(button: button, offsetX: CGFloat(offsetX), offsetY: CGFloat(offsetY))
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host, button: button),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_capture_gesture(widget, gesture)
}

private func quillInstallGtkDrawHostClickController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox,
    button: _DrawingHostButton
) {
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, button.gtkButton)

    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, nPress: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard nPress >= 2,
                  let context = quillGtkDrawHostContext(from: userData),
                  let button = context.button
            else { return }
            MainActor.assumeIsolated {
                context.host.doubleClick(button: button, at: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host, button: button),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_capture_gesture(widget, gesture)
}

private func quillInstallGtkDrawHostMotionController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox
) {
    let controller = gtk_swift_motion_capture_controller()!

    g_signal_connect_data(
        controller,
        "enter",
        unsafeBitCast({ (_: gpointer?, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.enter(at: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        controller,
        "motion",
        unsafeBitCast({ (_: gpointer?, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        controller,
        "leave",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.leave()
            }
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_event_controller(widget, controller)
}

private func quillInstallGtkDrawHostScrollController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox
) {
    let controller = gtk_swift_scroll_capture_controller()!

    g_signal_connect_data(
        controller,
        "scroll",
        unsafeBitCast({ (_: gpointer?, deltaX: gdouble, deltaY: gdouble, userData: gpointer?) -> gboolean in
            guard let context = quillGtkDrawHostContext(from: userData) else { return 0 }
            return MainActor.assumeIsolated {
                context.host.scroll(deltaX: CGFloat(deltaX), deltaY: CGFloat(deltaY)) ? 1 : 0
            }
        } as @convention(c) (gpointer?, gdouble, gdouble, gpointer?) -> gboolean, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_event_controller(widget, controller)
}

private func quillInstallGtkDrawHostMagnifyController(
    on widget: UnsafeMutablePointer<GtkWidget>,
    host: _DrawingHostBox
) {
    let gesture = gtk_gesture_zoom_new()!

    g_signal_connect_data(
        gpointer(gesture),
        "begin",
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.beginMagnifyGesture()
            }
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(gesture),
        "scale-changed",
        unsafeBitCast({ (_: gpointer?, scale: gdouble, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                _ = context.host.magnify(scale: CGFloat(scale))
            }
        } as @convention(c) (gpointer?, gdouble, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(gesture),
        "end",
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.endMagnifyGesture()
            }
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    g_signal_connect_data(
        gpointer(gesture),
        "cancel",
        unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
            guard let context = quillGtkDrawHostContext(from: userData) else { return }
            MainActor.assumeIsolated {
                context.host.endMagnifyGesture()
            }
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        quillRetainedGtkDrawHostContext(host),
        { userData, _ in quillReleaseGtkDrawHostContext(userData) },
        GConnectFlags(rawValue: 0)
    )

    gtk_swift_add_capture_multitouch_gesture(widget, gesture)
}

private let _quillGTKCursorNames: [(cursor: NSCursor, name: String)] = [
    (.arrow, "default"),
    (.crosshair, "crosshair"),
    (.openHand, "grab"),
    (.closedHand, "grabbing"),
    (.pointingHand, "pointer"),
    (.iBeam, "text"),
    (.iBeamCursorForVerticalLayout, "text"),
    (.resizeLeft, "ew-resize"),
    (.resizeRight, "ew-resize"),
    (.resizeLeftRight, "ew-resize"),
    (.resizeUp, "ns-resize"),
    (.resizeDown, "ns-resize"),
    (.resizeUpDown, "ns-resize"),
    (.operationNotAllowed, "not-allowed"),
    (.dragCopy, "copy"),
    (.dragLink, "alias"),
    (.contextualMenu, "context-menu"),
]

private func quillGTKCursorName(for cursor: NSCursor) -> String? {
    _quillGTKCursorNames.first { $0.cursor === cursor }?.name
}

extension NSView {
    /// A GtkDrawingArea that renders this view's `draw(_:)` through a
    /// Cairo-backed CGContext, with `needsDisplay` wired to queue_draw.
    /// Returns nil when GTK can't initialize (headless without a display).
    public func ensureGtkCustomDrawWidget() -> OpaquePointer? {
        guard QuillGTK.ensureInitialized() else { return nil }

        guard let area = gtk_drawing_area_new() else { return nil }
        gtk_widget_set_hexpand(area, 1)
        gtk_widget_set_vexpand(area, 1)
        gtk_widget_set_focusable(area, 1)
        gtk_widget_set_can_target(area, 1)
        let request = quillGtkCustomDrawSizeRequest()
        if request.width > 0 || request.height > 0 {
            gtk_widget_set_size_request(
                area,
                request.width > 0 ? gint(request.width) : -1,
                request.height > 0 ? gint(request.height) : -1
            )
        }

        let box = _DrawingHostBox(view: self)
        let userData = Unmanaged.passRetained(box).toOpaque()

        gtk_drawing_area_set_draw_func(
            UnsafeMutablePointer<GtkDrawingArea>(OpaquePointer(area)),
            { _, cr, width, height, userData in
                guard let cr, let userData else { return }
                let box = Unmanaged<_DrawingHostBox>.fromOpaque(userData).takeUnretainedValue()
                let view = box.view

                // GtkDrawingArea draw funcs run on the GTK main loop == the
                // main thread; NSView (frame/bounds/isFlipped/draw) is
                // @MainActor via NSResponder, so assume the isolation that is
                // true by construction.
                MainActor.assumeIsolated {
                    box.syncViewSize(width: width, height: height)
                    let bounds = view.bounds

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
                }
            },
            userData,
            { userData in
                guard let userData else { return }
                let box = Unmanaged<_DrawingHostBox>.fromOpaque(userData)
                box.takeUnretainedValue().area = nil
                box.release()
            }
        )

        let areaPointer = OpaquePointer(area)
        box.area = areaPointer
        quillInstallGtkDrawHostInputControllers(on: area, host: box)
        // The handler holds the box strongly (it outlives GTK's user-data ref);
        // after widget destruction box.area is nil and this becomes a no-op.
        quillDisplayInvalidationHandler = {
            guard let live = box.area else { return }
            gtk_widget_queue_draw(UnsafeMutablePointer<GtkWidget>(live))
        }
        return areaPointer
    }

    private func quillGtkCustomDrawSizeRequest() -> (width: Int, height: Int) {
        let intrinsic = intrinsicContentSize
        let width = quillGtkPositivePixelCount(
            intrinsic.width != NSView.noIntrinsicMetric ? intrinsic.width : 0,
            bounds.width,
            frame.width
        )
        let height = quillGtkPositivePixelCount(
            intrinsic.height != NSView.noIntrinsicMetric ? intrinsic.height : 0,
            bounds.height,
            frame.height
        )
        return (width, height)
    }

    private func quillGtkPositivePixelCount(_ values: CGFloat...) -> Int {
        for value in values where value > 0 {
            return max(1, Int(value.rounded(.up)))
        }
        return 0
    }
}

// MARK: - Widget lifetime helpers for the SwiftUI representable mount

/// Take a strong (sunk) reference so a cached widget survives the teardown of
/// the render tree it was last parented in.
public func quillGtkRetainWidget(_ widget: OpaquePointer) {
    g_object_ref_sink(UnsafeMutableRawPointer(widget))
}

public func quillGtkReleaseWidget(_ widget: OpaquePointer) {
    g_object_unref(UnsafeMutableRawPointer(widget))
}

/// Detach a cached widget from its previous parent (if any) so the renderer
/// can insert it into the freshly built tree.
public func quillGtkDetachFromParent(_ widget: OpaquePointer) {
    let w = UnsafeMutablePointer<GtkWidget>(widget)
    if gtk_widget_get_parent(w) != nil {
        gtk_widget_unparent(w)
    }
}

#endif
