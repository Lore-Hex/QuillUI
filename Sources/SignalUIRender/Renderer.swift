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
        CustomDrawnTextGtkMapper.self,
        UITextViewGtkMapper.self,
        UIButtonGtkMapper.self,
        UIImageViewGtkMapper.self,
        UISwitchGtkMapper.self,
        UITableViewGtkMapper.self,
        UITableViewCellGtkMapper.self,
        UICollectionViewGtkMapper.self,
        UICollectionViewCellGtkMapper.self,
        UIStackViewGtkMapper.self,
        GenericViewGtkMapper.self,   // fallback — must be last
    ]

    /// Render a full UIView tree to a GtkWidget. Returns nil for hidden views.
    public static func render(_ view: UIView) -> GtkWidgetPtr? {
        if view.isHidden { return nil }
        view.layoutIfNeeded()
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
            installMutationBridge(widget, view)
            applyAccessibilityHints(widget, view)
            return widget
        }
        return nil
    }

    private static func installMutationBridge(_ widget: GtkWidgetPtr, _ view: UIView) {
        view.quillSetViewMutationHandler("SignalUIRender.widgetState") { updatedView in
            gtk_widget_set_visible(widget, updatedView.isHidden ? 0 : 1)
            gtk_widget_set_opacity(widget, gdouble(max(0, min(1, updatedView.alpha))))
            let isSensitive: Bool
            if let control = updatedView as? UIControl {
                isSensitive = updatedView.isUserInteractionEnabled && control.isEnabled
            } else {
                isSensitive = updatedView.isUserInteractionEnabled
            }
            gtk_widget_set_sensitive(widget, isSensitive ? 1 : 0)
            let size = updatedView.bounds.size != .zero ? updatedView.bounds.size : updatedView.frame.size
            if size.width > 0 || size.height > 0 {
                gtk_widget_set_size_request(
                    widget,
                    size.width > 0 ? gint(size.width) : -1,
                    size.height > 0 ? gint(size.height) : -1
                )
            }
        }
        view.quillNotifyViewMutation()
    }

    /// Render hints carried on `accessibilityIdentifier` (a property views already
    /// expose, so the demo can tag views without a custom UIView subclass):
    ///   "qspacer"      → hexpand (a flexible gap that pushes a chat bubble to one side)
    ///   "qclass:NAME"  → add CSS class NAME (styled in the global stylesheet)
    private static func applyAccessibilityHints(_ widget: GtkWidgetPtr, _ view: UIView) {
        guard let id = view.accessibilityIdentifier else { return }
        if id == "qspacer" {
            gtk_widget_set_hexpand(widget, 1)
        } else if id.hasPrefix("qclass:") {
            let cls = String(id.dropFirst("qclass:".count))
            cls.withCString { gtk_widget_add_css_class(widget, $0) }
            // A composer text field fills the available width beside the Send button.
            if cls == "qfield" {
                gtk_widget_set_hexpand(widget, 1)
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
        }
    }

    // MARK: - CALayer styling → CSS

    private static var cssClassCounter = 0

    /// Style a widget from the view's CALayer: backgroundColor, cornerRadius,
    /// border. GTK4 has no per-widget style context, so we mint a unique CSS
    /// class, load a provider for the default display, and tag the widget.
    static func applyLayerStyle(_ widget: GtkWidgetPtr, _ view: UIView) {
        let layer = view.layer
        var rules: [String] = []
        if let gradientRules = gradientLayerRules(in: layer) {
            rules.append(contentsOf: gradientRules)
        } else if let bg = layer.backgroundColor, let hex = cgColorHex(bg) {
            rules.append("background-color: \(hex);")
        } else if let bg = view.backgroundColor, let hex = uiColorHex(bg) {
            rules.append("background-color: \(hex);")
        } else if view is UIVisualEffectView {
            rules.append("background-color: rgba(255, 255, 255, 0.82);")
        }
        if layer.cornerRadius > 0 {
            rules.append("border-radius: \(Int(layer.cornerRadius))px;")
        } else if layer.mask != nil {
            let radius = maskedLayerCornerRadius(for: view)
            if radius > 0 {
                rules.append("border-radius: \(radius)px;")
            }
        }
        if layer.borderWidth > 0, let bc = layer.borderColor, let hex = cgColorHex(bc) {
            rules.append("border: \(Int(layer.borderWidth))px solid \(hex);")
        } else if view is UIVisualEffectView, layer.cornerRadius > 0 {
            rules.append("border: 1px solid rgba(60, 60, 67, 0.18);")
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

private func gradientLayerRules(in layer: CALayer) -> [String]? {
    guard let gradient = firstGradientLayer(in: layer),
          let colors = gradient.colors?.compactMap({ $0 as? CGColor }),
          !colors.isEmpty else {
        return nil
    }

    let stops = colors.compactMap(cgColorHex)
    guard let fallback = stops.first else { return nil }

    var rules = ["background-color: \(fallback);"]
    if stops.count >= 2 {
        let direction = gradientDirection(from: gradient)
        rules.append("background-image: linear-gradient(\(direction), \(stops.joined(separator: ", ")));")
    }
    return rules
}

private func firstGradientLayer(in layer: CALayer) -> CAGradientLayer? {
    for sublayer in layer.sublayers ?? [] {
        if let gradient = sublayer as? CAGradientLayer,
           gradient.colors?.isEmpty == false {
            return gradient
        }
    }
    return nil
}

private func gradientDirection(from gradient: CAGradientLayer) -> String {
    let dx = gradient.endPoint.x - gradient.startPoint.x
    let dy = gradient.endPoint.y - gradient.startPoint.y
    if abs(dx) > abs(dy) {
        return dx >= 0 ? "to right" : "to left"
    }
    return dy >= 0 ? "to bottom" : "to top"
}

@MainActor private func maskedLayerCornerRadius(for view: UIView) -> Int {
    let size = view.bounds.size != .zero ? view.bounds.size : view.frame.size
    let shorterSide = min(size.width, size.height)
    guard shorterSide.isFinite, shorterSide > 0 else { return 0 }
    return Int(min(22, max(8, shorterSide / 3)).rounded())
}
