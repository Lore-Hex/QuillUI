#if os(Linux)
import BackendGTK4
import CGTK
import Foundation
import QuillPaint
import QuillPaintCairo

private let quillSliderHookInstaller: Void = {
    BackendGTK4.quill_gtk_slider_paint_hook = { scale, isVertical in
        setupQuillSliderChrome(scale: scale, isVertical: isVertical)
    }
}()

public func installQuillSliderHook() {
    _ = quillSliderHookInstaller
}

public func setupQuillSliderChrome(scale: OpaquePointer, isVertical: Bool) -> OpaquePointer {
    let scaleWidget = quillGTKWidgetPointer(scale)
    let overlay = gtk_overlay_new()!
    let chrome = gtk_drawing_area_new()!

    configureQuillSliderContainer(overlay, control: scaleWidget, isVertical: isVertical)
    configureQuillSliderChromeWidget(chrome, isVertical: isVertical)
    configureQuillSliderNativeControl(scaleWidget, isVertical: isVertical)
    applyQuillSliderCSS(to: scaleWidget)

    gtk_overlay_set_child(OpaquePointer(overlay), chrome)
    gtk_overlay_add_overlay(OpaquePointer(overlay), scaleWidget)

    let chromeBox = makeQuillSliderChrome(control: scaleWidget, chrome: chrome, isVertical: isVertical)
    chromeBox.installDrawFunc()
    chromeBox.connectStateFlagsChanged(on: scaleWidget)
    chromeBox.connectNotify("notify::sensitive", on: scaleWidget)
    chromeBox.connectVoidSignal("value-changed", on: scaleWidget)

    return OpaquePointer(overlay)
}

/// Live 0...1 progress of the native scale, derived from its current value and
/// range so the painted knob tracks the real interactive value.
private func quillSliderProgress(_ control: UnsafeMutablePointer<GtkWidget>) -> Double {
    let range = quillSliderRangePointer(control)
    let value = gtk_range_get_value(range)
    guard let adjustment = gtk_range_get_adjustment(range) else { return 0 }
    let lower = gtk_adjustment_get_lower(adjustment)
    let upper = gtk_adjustment_get_upper(adjustment)
    let span = upper - lower
    guard span > 0 else { return 0 }
    let progress = (value - lower) / span
    return min(max(progress, 0), 1)
}

/// Build the shared painted-chrome host for a slider. The render closure drives
/// `MacSliderPaint` with the live progress read off the native scale.
private func makeQuillSliderChrome(
    control: UnsafeMutablePointer<GtkWidget>,
    chrome: UnsafeMutablePointer<GtkWidget>,
    isVertical: Bool
) -> QuillGTKPaintedChrome {
    let orientation: MacSliderPaint.Orientation = isVertical ? .vertical : .horizontal
    return QuillGTKPaintedChrome(
        chrome: chrome,
        frameProvider: QuillGTKPaintedChrome.fullFrame,
        stateProvider: {
            quillGTKPaintState(of: control)
        },
        render: { context, frame, state in
            MacSliderPaint(
                orientation: orientation,
                progress: quillSliderProgress(control)
            ).paint(into: context, frame: frame, state: state)
        }
    )
}

private func configureQuillSliderContainer(
    _ overlay: UnsafeMutablePointer<GtkWidget>,
    control: UnsafeMutablePointer<GtkWidget>,
    isVertical: Bool
) {
    if isVertical {
        gtk_widget_set_size_request(overlay, gint(MacMetrics.Slider.regularHeight), -1)
        gtk_widget_set_vexpand(overlay, 1)
        gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)
        gtk_widget_set_halign(overlay, GTK_ALIGN_CENTER)
    } else {
        gtk_widget_set_size_request(overlay, -1, gint(MacMetrics.Slider.regularHeight))
        gtk_widget_set_hexpand(overlay, 1)
        gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
        gtk_widget_set_valign(overlay, GTK_ALIGN_CENTER)
    }
    gtk_widget_set_can_focus(overlay, 0)
    gtk_widget_set_sensitive(overlay, gtk_widget_get_sensitive(control))
}

private func configureQuillSliderChromeWidget(
    _ chrome: UnsafeMutablePointer<GtkWidget>,
    isVertical: Bool
) {
    gtk_swift_drawing_area_set_content_height(chrome, gint(MacMetrics.Slider.regularHeight))
    gtk_widget_set_hexpand(chrome, 1)
    gtk_widget_set_vexpand(chrome, 1)
    gtk_widget_set_halign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_valign(chrome, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(chrome, 0)
    gtk_widget_set_can_focus(chrome, 0)
}

private func configureQuillSliderNativeControl(
    _ control: UnsafeMutablePointer<GtkWidget>,
    isVertical: Bool
) {
    gtk_widget_set_hexpand(control, 1)
    gtk_widget_set_vexpand(control, 1)
    gtk_widget_set_halign(control, GTK_ALIGN_FILL)
    gtk_widget_set_valign(control, GTK_ALIGN_FILL)
    gtk_widget_set_opacity(control, 0.001)
    gtk_widget_set_can_target(control, 1)
    gtk_widget_set_can_focus(control, 1)
}

/// Strip the native scale's track/trough/slider chrome so only the painted
/// macOS slider shows through; the transparent scale stays interactive on top.
private func applyQuillSliderCSS(to scale: UnsafeMutablePointer<GtkWidget>) {
    let css = """
    scale.quill-paint-slider,
    scale.quill-paint-slider trough,
    scale.quill-paint-slider trough highlight,
    scale.quill-paint-slider trough fill,
    scale.quill-paint-slider slider {
        background: transparent;
        background-image: none;
        border: none;
        box-shadow: none;
        outline: none;
        min-height: 0;
        min-width: 0;
    }
    """
    quillGTKApplyCSS(css, to: scale, cssClass: "quill-paint-slider")
}

private func quillSliderRangePointer(
    _ ptr: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkRange> {
    UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: GtkRange.self)
}
#endif
