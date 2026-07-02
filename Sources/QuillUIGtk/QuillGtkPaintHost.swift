#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint
import QuillPaintCairo

// MARK: - Shared GTK painted-control foundation
//
// The QuillPaint GTK hooks (button, text field, text editor, toggle) all
// follow the same recipe: stack a `GtkDrawingArea` (which paints the macOS
// chrome via a `PaintControl` + Cairo) under a transparent native widget
// inside a `GtkOverlay`, then redraw the drawing area whenever the native
// widget's interaction state changes.
//
// Everything below the per-control overlay layout is identical machinery and
// previously existed as three near-identical copies. This file is the single
// home for it:
//   * `quillGTKWidgetPointer` — OpaquePointer → GtkWidget* cast
//   * `quillGTKStateFlagsContain` — GtkStateFlags membership test
//   * `QuillGTKPaintedChrome` — a generic chrome box parameterized by a
//     state provider and a render closure, owning the draw-func and the
//     redraw-signal wiring.
//
// Per-control overlay assembly (which children, what CSS, sizing) stays in
// the per-control files — only the parts that were byte-for-byte duplicated
// move here. The rendered draw calls are unchanged.

/// Reinterpret a GTK `OpaquePointer` (as the SwiftOpenUI backend hands us) as
/// a typed `GtkWidget` pointer.
func quillGTKWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

/// True if `flags` contains `flag`. `GtkStateFlags` is an `OptionSet`-style
/// bitmask; the raw widths differ across the API surface so we normalize
/// through `UInt32`.
func quillGTKStateFlagsContain(_ flags: GtkStateFlags, _ flag: GtkStateFlags) -> Bool {
    (UInt32(flags.rawValue) & UInt32(flag.rawValue)) != 0
}

/// Build a `PaintControlState` from a widget's live GTK state.
///
/// This is the common flag→state mapping the button/text-field/toggle boxes
/// each hand-rolled. Per-control specifics (a toggle's selected state, a
/// button's `isDefault`) are layered on by the caller via the `overrides`
/// closure, which receives the base state and returns the final one.
func quillGTKPaintState(
    of widget: UnsafeMutablePointer<GtkWidget>,
    treatActiveAsPressed: Bool = true,
    overrides: (inout PaintControlState) -> Void = { _ in }
) -> PaintControlState {
    let flags = gtk_widget_get_state_flags(widget)
    var state = PaintControlState(
        isPressed: treatActiveAsPressed
            && quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_ACTIVE),
        isFocused: quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUS_WITHIN)
            || quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_FOCUSED),
        isDisabled: gtk_widget_get_sensitive(widget) == 0,
        isHovered: quillGTKStateFlagsContain(flags, GTK_STATE_FLAG_PRELIGHT)
    )
    overrides(&state)
    return state
}

/// Generic painted-chrome host shared by every QuillPaint GTK hook.
///
/// It owns:
///   * the `GtkDrawingArea` (`chrome`) that paints control chrome,
///   * a `stateProvider` returning the current `PaintControlState`,
///   * a `frameProvider` mapping the drawing-area pixel size to the paint
///     frame (controls differ: buttons fill `0,0,w,h`; text fields inset by
///     half a pixel for crisp 1px borders),
///   * a `render` closure that draws into a `PaintContext`.
///
/// Installing the draw func and connecting redraw signals are methods here so
/// the three former copies of that GObject retain/release dance live once.
final class QuillGTKPaintedChrome {
    let chrome: UnsafeMutablePointer<GtkWidget>
    private let stateProvider: () -> PaintControlState
    private let frameProvider: (_ width: Double, _ height: Double) -> PaintRect
    private let render: (PaintContext, PaintRect, PaintControlState) -> Void

    init(
        chrome: UnsafeMutablePointer<GtkWidget>,
        frameProvider: @escaping (_ width: Double, _ height: Double) -> PaintRect = QuillGTKPaintedChrome.fullFrame,
        stateProvider: @escaping () -> PaintControlState,
        render: @escaping (PaintContext, PaintRect, PaintControlState) -> Void
    ) {
        self.chrome = chrome
        self.frameProvider = frameProvider
        self.stateProvider = stateProvider
        self.render = render
    }

    /// `frameProvider` that fills the whole drawing area (`0, 0, w, h`).
    /// Matches the button and toggle hooks.
    static let fullFrame: (Double, Double) -> PaintRect = { width, height in
        PaintRect(x: 0, y: 0, width: width, height: height)
    }

    /// `frameProvider` inset by half a pixel on every side so a 1px stroked
    /// border lands on the pixel grid. Matches the text field/editor hook.
    static let halfPixelInsetFrame: (Double, Double) -> PaintRect = { width, height in
        PaintRect(x: 0.5, y: 0.5, width: max(0, width - 1), height: max(0, height - 1))
    }

    var paintState: PaintControlState { stateProvider() }

    func queueDraw() {
        gtk_widget_queue_draw(chrome)
    }

    private func draw(cr: OpaquePointer, width: Double, height: Double) {
        render(CairoPaintContext(cr: cr), frameProvider(width, height), stateProvider())
    }

    /// Attach the Cairo draw function to the drawing area. The chrome box is
    /// retained for the lifetime of the drawing area and released by GTK's
    /// destroy notify.
    func installDrawFunc() {
        let retained = Unmanaged.passRetained(self).toOpaque()
        gtk_swift_drawing_area_set_draw_func(
            chrome,
            { (_: UnsafeMutablePointer<GtkWidget>?,
               cr: OpaquePointer?,
               width: gint,
               height: gint,
               userData: gpointer?) in
                guard let cr, let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .draw(cr: cr, width: Double(width), height: Double(height))
            },
            retained,
            { userData in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>.fromOpaque(userData).release()
            }
        )
    }

    /// Connect `state-flags-changed` on `widget` so the chrome repaints when
    /// the native widget's interaction state changes.
    func connectStateFlagsChanged(on widget: UnsafeMutablePointer<GtkWidget>) {
        let retained = Unmanaged.passRetained(self).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            "state-flags-changed",
            unsafeBitCast({ (_: gpointer?, _: GtkStateFlags, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .queueDraw()
            } as @convention(c) (gpointer?, GtkStateFlags, gpointer?) -> Void, to: GCallback.self),
            retained,
            { userData, _ in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>.fromOpaque(userData).release()
            },
            GConnectFlags(rawValue: 0)
        )
    }

    /// Connect a `notify::<property>` signal on `widget` so the chrome
    /// repaints when that GObject property changes (e.g. `notify::sensitive`,
    /// `notify::active`).
    func connectNotify(_ signal: String, on widget: UnsafeMutablePointer<GtkWidget>) {
        let retained = Unmanaged.passRetained(self).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            signal,
            unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .queueDraw()
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            retained,
            { userData, _ in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>.fromOpaque(userData).release()
            },
            GConnectFlags(rawValue: 0)
        )
    }

    /// Connect a plain no-argument signal (e.g. a check button's `toggled`)
    /// so the chrome repaints.
    func connectVoidSignal(_ signal: String, on widget: UnsafeMutablePointer<GtkWidget>) {
        let retained = Unmanaged.passRetained(self).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            signal,
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .queueDraw()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            retained,
            { userData, _ in
                guard let userData else { return }
                Unmanaged<QuillGTKPaintedChrome>.fromOpaque(userData).release()
            },
            GConnectFlags(rawValue: 0)
        )
    }
}

/// Install a custom GTK CSS provider string on `widget`'s display and add
/// `cssClass` to the widget. Shared by every hook that styles its
/// transparent native widget. The provider is unref'd after the display
/// takes its own reference, matching the previous per-hook code.
func quillGTKApplyCSS(
    _ css: String,
    to widget: UnsafeMutablePointer<GtkWidget>,
    cssClass: String
) {
    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(widget) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(widget, cssClass)
    g_object_unref(gpointer(provider))
}
#endif
