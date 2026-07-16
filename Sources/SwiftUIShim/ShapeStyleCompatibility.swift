import SwiftOpenUI
import QuillSwiftUICompatibility

public protocol ShapeStyle {}

public struct AnyShapeStyle: ShapeStyle {
    public let quillView: AnyView
    public let quillColor: Color

    public init<S: ShapeStyle>(_ style: S) {
        if let erased = style as? AnyShapeStyle {
            quillView = erased.quillView
            quillColor = erased.quillColor
        } else {
            quillView = quillShapeStyleView(style)
            quillColor = quillShapeStyleColor(style)
        }
    }
}

extension Color: ShapeStyle {}
extension LinearGradient: ShapeStyle {}
extension RadialGradient: ShapeStyle {}
extension Material: ShapeStyle {}

public extension ShapeStyle where Self == Material {
    static var bar: Material { .bar }
    static var ultraThinMaterial: Material { .ultraThinMaterial }
    static var thinMaterial: Material { .thinMaterial }
    static var regularMaterial: Material { .regularMaterial }
    static var thickMaterial: Material { .thickMaterial }
    static var ultraThickMaterial: Material { .ultraThickMaterial }
}

private func quillShapeStyleView<S: ShapeStyle>(_ style: S) -> AnyView {
    if let color = style as? Color {
        return AnyView(color)
    }
    if let gradient = style as? LinearGradient {
        return AnyView(gradient)
    }
    if let gradient = style as? RadialGradient {
        return AnyView(gradient)
    }
    if let erased = style as? AnyShapeStyle {
        return erased.quillView
    }
    if let material = style as? Material {
        return AnyView(material)
    }
    return AnyView(Color.clear)
}

private func quillShapeStyleColor<S: ShapeStyle>(_ style: S) -> Color {
    if let color = style as? Color {
        return color
    }
    if let gradient = style as? LinearGradient {
        return gradient.gradient.quillShapeStyleAverageColor
    }
    if let gradient = style as? RadialGradient {
        return gradient.gradient.quillShapeStyleAverageColor
    }
    if let erased = style as? AnyShapeStyle {
        return erased.quillColor
    }
    if let material = style as? Material {
        return Color.white.opacity(material.opacityValue * 0.92)
    }
    return .clear
}

private struct AccessibilityReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    var accessibilityReduceMotion: Bool {
        get { self[AccessibilityReduceMotionKey.self] }
        set { self[AccessibilityReduceMotionKey.self] = newValue }
    }
}

private extension Gradient {
    var quillShapeStyleAverageColor: Color {
        guard !stops.isEmpty else { return .clear }
        let totals = stops.reduce((red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)) { result, stop in
            (
                red: result.red + stop.color.red,
                green: result.green + stop.color.green,
                blue: result.blue + stop.color.blue,
                alpha: result.alpha + stop.color.alpha
            )
        }
        let count = Double(stops.count)
        return Color(
            red: totals.red / count,
            green: totals.green / count,
            blue: totals.blue / count,
            opacity: totals.alpha / count
        )
    }
}

public extension View {
    @_disfavoredOverload
    func background<S: ShapeStyle>(_ style: S) -> BackgroundView<Self, AnyView> {
        background(quillShapeStyleView(style))
    }

    func foregroundStyle<S: ShapeStyle>(_ style: S) -> ForegroundColorView<Self> {
        foregroundColor(quillShapeStyleColor(style))
    }
}

public extension Shape {
    func fill<S: ShapeStyle>(_ style: S) -> FilledShape<Self> {
        fill(quillShapeStyleColor(style))
    }
}
