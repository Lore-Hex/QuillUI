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
    struct RenderBindingToken: Equatable {
        fileprivate let viewID: ObjectIdentifier
        fileprivate let generation: UInt64
    }

    private static var renderBindingGenerations: [ObjectIdentifier: UInt64] = [:]

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
        invalidateRenderBindingsRecursively(for: view)
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

    static func renderBindingToken(for view: UIView) -> RenderBindingToken {
        let viewID = ObjectIdentifier(view)
        return RenderBindingToken(
            viewID: viewID,
            generation: renderBindingGenerations[viewID, default: 0]
        )
    }

    static func isRenderBindingActive(_ token: RenderBindingToken, for view: UIView) -> Bool {
        token.viewID == ObjectIdentifier(view)
            && renderBindingGenerations[token.viewID, default: 0] == token.generation
    }

    static func gtkSizeRequestValue(_ value: CGFloat) -> gint {
        guard value.isFinite, value > 0, value <= 10_000 else {
            return -1
        }
        return gint(value.rounded(.up))
    }

    static func gtkCoordinateValue(_ value: CGFloat) -> gdouble {
        guard value.isFinite, abs(value) <= 10_000 else {
            return 0
        }
        return gdouble(value)
    }

    private static func invalidateRenderBindings(for view: UIView) {
        let viewID = ObjectIdentifier(view)
        renderBindingGenerations[viewID, default: 0] &+= 1
    }

    static func invalidateDescendantRenderBindings(for view: UIView) {
        for child in view.subviews {
            invalidateRenderBindingsRecursively(for: child)
        }
    }

    private static func invalidateRenderBindingsRecursively(for view: UIView) {
        invalidateRenderBindings(for: view)
        for child in view.subviews {
            invalidateRenderBindingsRecursively(for: child)
        }
    }

    private static func installMutationBridge(_ widget: GtkWidgetPtr, _ view: UIView) {
        let token = renderBindingToken(for: view)
        view.quillSetViewMutationHandler("SignalUIRender.widgetState") { updatedView in
            guard isRenderBindingActive(token, for: updatedView) else { return }
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
            let width = gtkSizeRequestValue(size.width)
            let height = gtkSizeRequestValue(size.height)
            if width > 0 || height > 0 {
                gtk_widget_set_size_request(
                    widget,
                    width,
                    height
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
        if let signalRules = signalColorOrGradientRules(for: view) {
            rules.append(contentsOf: signalRules)
        } else if let gradientRules = gradientLayerRules(in: layer) {
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

private enum ReflectedSignalColorOrGradient {
    case transparent
    case blur
    case solidColor(UIColor)
    case gradient(UIColor, UIColor, CGFloat)
}

private func signalColorOrGradientRules(for view: UIView) -> [String]? {
    guard String(describing: type(of: view)) == "CVColorOrGradientView" else { return nil }
    guard let value = reflectedSignalColorOrGradientValue(from: view) else { return nil }

    switch value {
    case .transparent:
        return []
    case .blur:
        return ["background-color: rgba(255, 255, 255, 0.82);"]
    case .solidColor(let color):
        guard let hex = uiColorHex(color) else { return [] }
        return ["background-color: \(hex);"]
    case .gradient(let color1, let color2, let angleRadians):
        guard let first = uiColorHex(color1), let second = uiColorHex(color2) else { return [] }
        return [
            "background-color: \(first);",
            "background-image: linear-gradient(\(cssGradientDirection(angleRadians: angleRadians)), \(first), \(second));",
        ]
    }
}

private func reflectedSignalColorOrGradientValue(from view: UIView) -> ReflectedSignalColorOrGradient? {
    var mirror: Mirror? = Mirror(reflecting: view)
    while let currentMirror = mirror {
        for child in currentMirror.children where child.label == "value" {
            if let value = parseSignalColorOrGradientValue(child.value) {
                return value
            }
        }
        mirror = currentMirror.superclassMirror
    }
    return nil
}

private func parseSignalColorOrGradientValue(_ value: Any) -> ReflectedSignalColorOrGradient? {
    let unwrapped = unwrapOptional(value) ?? value
    let mirror = Mirror(reflecting: unwrapped)
    guard mirror.displayStyle == .enum else { return nil }

    guard let caseChild = mirror.children.first else {
        if String(describing: unwrapped).contains("transparent") {
            return .transparent
        }
        return nil
    }

    switch caseChild.label {
    case "transparent":
        return .transparent
    case "blur":
        return .blur
    case "solidColor":
        guard let color = firstMirroredValue(of: UIColor.self, in: caseChild.value) else { return nil }
        return .solidColor(color)
    case "gradient":
        let colors = mirroredValues(of: UIColor.self, in: caseChild.value)
        guard colors.count >= 2,
              let angle = firstMirroredCGFloat(labeled: "angleRadians", in: caseChild.value) else {
            return nil
        }
        return .gradient(colors[0], colors[1], angle)
    default:
        return nil
    }
}

private func unwrapOptional(_ value: Any) -> Any? {
    let mirror = Mirror(reflecting: value)
    guard mirror.displayStyle == .optional else { return nil }
    return mirror.children.first?.value
}

private func firstMirroredValue<T>(of type: T.Type, in value: Any) -> T? {
    if let typed = value as? T { return typed }
    if let unwrapped = unwrapOptional(value) {
        return firstMirroredValue(of: type, in: unwrapped)
    }
    for child in Mirror(reflecting: value).children {
        if let typed = firstMirroredValue(of: type, in: child.value) {
            return typed
        }
    }
    return nil
}

private func mirroredValues<T>(of type: T.Type, in value: Any) -> [T] {
    var result: [T] = []
    collectMirroredValues(of: type, in: value, into: &result)
    return result
}

private func collectMirroredValues<T>(of type: T.Type, in value: Any, into result: inout [T]) {
    if let typed = value as? T {
        result.append(typed)
        return
    }
    if let unwrapped = unwrapOptional(value) {
        collectMirroredValues(of: type, in: unwrapped, into: &result)
        return
    }
    for child in Mirror(reflecting: value).children {
        collectMirroredValues(of: type, in: child.value, into: &result)
    }
}

private func firstMirroredCGFloat(labeled label: String, in value: Any) -> CGFloat? {
    if let unwrapped = unwrapOptional(value) {
        return firstMirroredCGFloat(labeled: label, in: unwrapped)
    }
    for child in Mirror(reflecting: value).children {
        guard child.label == label else { continue }
        if let value = child.value as? CGFloat {
            return value
        }
        if let value = child.value as? Double {
            return CGFloat(value)
        }
        if let value = child.value as? Float {
            return CGFloat(value)
        }
        if let unwrapped = unwrapOptional(child.value) {
            return firstMirroredCGFloat(labeled: label, in: unwrapped)
        }
    }
    return nil
}

private func cssGradientDirection(angleRadians: CGFloat) -> String {
    let normalized = angleRadians.truncatingRemainder(dividingBy: .pi * 2)
    let x = sin(normalized)
    let y = -cos(normalized)
    if abs(x) > abs(y) {
        return x >= 0 ? "to left" : "to right"
    }
    return y <= 0 ? "to bottom" : "to top"
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
