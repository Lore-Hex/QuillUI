// Renderer.swift — the UIKit→GTK4 render walk.
// =============================================
// Turns a laid-out QuillUIKit `UIView` hierarchy into a GtkWidget tree so that
// Signal-iOS's own UIKit views can DISPLAY on Linux (not just compile). This is
// the integration core that the per-type mappers (Mappers/*.swift) plug into.
//
// Architecture (verdict: approach A — widget mapping): a registry of
// `UIViewGtkMapper`s, tried most-specific-first; the matched mapper builds the
// GtkWidget for one view and recurses into children via `UIKitGtkRenderContext`.
// Container layout uses GtkBox (UIStackView/UITableView, sidestepping the
// constraint solver) and GtkFixed (generic frame-positioned views). CALayer
// styling (background/cornerRadius) is applied via per-widget CSS.

import CGTK
import CGTKBridge
import QuillUIKit
import UIKit
import QuillFoundation
import QuartzCore
import Foundation

public typealias GtkWidgetPtr = UnsafeMutablePointer<GtkWidget>

/// Per-render services the walker hands to every mapper.
@MainActor public struct UIKitGtkRenderContext {
    /// Recurse: render a child `UIView` (via the registry) → its widget, or nil
    /// (hidden / zero-size views render nothing).
    public let render: (UIView) -> GtkWidgetPtr?
    /// Apply the view's CALayer styling (backgroundColor, cornerRadius, border,
    /// alpha) to `widget` via a per-widget CSS provider.
    public let applyLayerStyle: (GtkWidgetPtr, UIView) -> Void
    /// Measure a string for a font (for intrinsic content sizing).
    public let measureText: (String, UIFont?, CGFloat) -> CGSize
}

/// One mapper handles one (family of) `UIView` type(s). Most-specific wins.
@MainActor public protocol UIViewGtkMapper {
    static func handles(_ view: UIView) -> Bool
    static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr
}

/// The render engine: owns the mapper registry + the recursion + the shared
/// context closures.
@MainActor public enum UIKitGtkRenderer {

    /// Registration order = match priority. Specific types first; the generic
    /// frame-positioned `UIView` fallback (handles == true) must be LAST.
    static let mappers: [UIViewGtkMapper.Type] = [
        UILabelGtkMapper.self,
        UIImageViewGtkMapper.self,
        UITableViewGtkMapper.self,
        UITableViewCellGtkMapper.self,
        UIStackViewGtkMapper.self,
        GenericViewGtkMapper.self,   // fallback — must be last
    ]

    /// Render a full UIView tree to a GtkWidget. Returns nil for hidden views.
    public static func render(_ view: UIView) -> GtkWidgetPtr? {
        if view.isHidden { return nil }
        let ctx = UIKitGtkRenderContext(
            render: { Self.render($0) },
            applyLayerStyle: { Self.applyLayerStyle($0, $1) },
            measureText: { Self.measureText($0, $1, $2) }
        )
        for mapper in mappers where mapper.handles(view) {
            let widget = mapper.make(view, ctx)
            // alpha → opacity; hidden already filtered.
            if view.alpha < 0.999 {
                gtk_widget_set_opacity(widget, gdouble(view.alpha))
            }
            return widget
        }
        return nil
    }

    // MARK: - CALayer styling → CSS

    private static var cssClassCounter = 0

    /// Style a widget from the view's CALayer: backgroundColor, cornerRadius,
    /// border. GTK4 has no per-widget style context, so we mint a unique CSS
    /// class, load a provider for the default display, and tag the widget.
    static func applyLayerStyle(_ widget: GtkWidgetPtr, _ view: UIView) {
        let layer = view.layer
        var rules: [String] = []
        if let bg = layer.backgroundColor, let hex = cgColorHex(bg) {
            rules.append("background-color: \(hex);")
        } else if let bg = view.backgroundColor, let hex = uiColorHex(bg) {
            rules.append("background-color: \(hex);")
        }
        if layer.cornerRadius > 0 {
            rules.append("border-radius: \(Int(layer.cornerRadius))px;")
        }
        if layer.borderWidth > 0, let bc = layer.borderColor, let hex = cgColorHex(bc) {
            rules.append("border: \(Int(layer.borderWidth))px solid \(hex);")
        }
        guard !rules.isEmpty else { return }

        if ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DUMP"] == "1" {
            FileHandle.standardError.write(Data(
                "applyLayerStyle \(type(of: view)) -> \(rules.joined(separator: " "))\n".utf8))
        }

        cssClassCounter += 1
        let cls = "qrender\(cssClassCounter)"
        let css = ".\(cls) { \(rules.joined(separator: " ")) }"
        let provider = gtk_css_provider_new()
        css.withCString { cstr in
            gtk_css_provider_load_from_string(provider, cstr)
        }
        if let display = gdk_display_get_default() {
            gtk_style_context_add_provider_for_display(
                display,
                OpaquePointer(provider),
                guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
            )
        }
        cls.withCString { gtk_widget_add_css_class(widget, $0) }
        g_object_unref(provider)
    }

    // MARK: - Text measurement (Pango)

    /// Measure a string at a font. Uses a throwaway Pango layout for accuracy;
    /// falls back to a width/height heuristic if Pango is unavailable.
    static func measureText(_ text: String, _ font: UIFont?, _ maxWidth: CGFloat) -> CGSize {
        let pointSize = font?.pointSize ?? 17
        // Heuristic: ~0.55em average glyph advance, 1.2 line height. Good enough
        // for GtkLabel intrinsic sizing (the label auto-sizes itself anyway; this
        // only seeds the frame for the GtkFixed path).
        let charW = pointSize * 0.55
        let oneLine = CGFloat(text.count) * charW
        if maxWidth > 0, oneLine > maxWidth {
            let lines = ceil(oneLine / maxWidth)
            return CGSize(width: maxWidth, height: ceil(lines * pointSize * 1.2))
        }
        return CGSize(width: ceil(oneLine), height: ceil(pointSize * 1.2))
    }
}

// MARK: - Color helpers
//
// ALPHA MATTERS: Signal's cell config sets `contentView.backgroundColor = .clear`
// (RGBA 0,0,0,0). An alpha-blind "#RRGGBB" turns that fully-transparent color into
// OPAQUE BLACK, painting black rectangles over everything. So these emit a CSS
// color that honors alpha — and return nil for a fully-transparent color so the
// caller paints no background at all (lets the parent/section card show through).

/// Build a CSS color string from RGBA channels (0...1). nil if fully transparent.
private func cssColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> String? {
    if a <= 0.004 { return nil }  // ~transparent → no paint
    let ri = Int((r * 255).rounded()), gi = Int((g * 255).rounded()), bi = Int((b * 255).rounded())
    if a >= 0.996 {
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
    return String(format: "rgba(%d, %d, %d, %.3f)", ri, gi, bi, Double(a))
}

/// UIColor (RSColor on Linux) → CSS color honoring alpha; nil if transparent.
func uiColorHex(_ color: UIColor) -> String? {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return cssColor(r, g, b, a)
}

/// CGColor → CSS color honoring alpha; nil if transparent.
func cgColorHex(_ color: CGColor) -> String? {
    let comps = color.components ?? []
    if comps.count >= 4 {
        return cssColor(comps[0], comps[1], comps[2], comps[3])
    }
    if comps.count == 3 {
        return cssColor(comps[0], comps[1], comps[2], 1)
    }
    if comps.count == 2 { // grayscale + alpha
        return cssColor(comps[0], comps[0], comps[0], comps[1])
    }
    return nil
}
