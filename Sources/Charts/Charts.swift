import SwiftUI

public struct ChartProxy: Sendable {
    public var plotFrame: CGRect? { CGRect(x: 0, y: 0, width: 320, height: 180) }
    public init() {}

    public func position<Value>(forX value: Value) -> Double? {
        _ = value
        return nil
    }
}

public struct Chart<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public init<Data: RandomAccessCollection>(_ data: Data, @ViewBuilder content: (Data.Element) -> Content) {}
    public var body: some View { EmptyView() }
}

public enum Visibility: Sendable {
    case automatic
    case visible
    case hidden
}

public struct InterpolationMethod: Sendable {
    public init() {}
    public static let catmullRom = InterpolationMethod()
}

public struct BarMark: View {
    public init(x: PlottableValue, y: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct LineMark: View {
    public init(x: PlottableValue, y: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct PointMark: View {
    public init(x: PlottableValue, y: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct AreaMark: View {
    public init(x: PlottableValue, y: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct RuleMark: View {
    public init(y: PlottableValue) {}
    public init(x: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct RectangleMark: View {
    public init(xStart: PlottableValue, xEnd: PlottableValue, yStart: PlottableValue, yEnd: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct SectorMark: View {
    public init(angle: PlottableValue) {}
    public var body: some View { EmptyView() }
}

public struct PlottableValue: Sendable {
    public let label: String
    public init(label: String) {
        self.label = label
    }

    public static func value<Value>(_ label: String, _ value: Value) -> PlottableValue {
        _ = value
        return PlottableValue(label: label)
    }
}

public extension AreaMark {
    func interpolationMethod(_ method: InterpolationMethod) -> some View {
        _ = method
        return self
    }
}

public extension LineMark {
    func interpolationMethod(_ method: InterpolationMethod) -> some View {
        _ = method
        return self
    }
}

// On Apple's Swift Charts these modifiers are declared on `View`, not on the
// `Chart` value, so they work anywhere in a chart-modifier chain (after the
// first modifier the chain type is `some View`, not `Chart`). Declaring them on
// `Chart` only made vendored real source fail with "value of type 'some View'
// has no member 'chartXSelection'" (IceCubes AccountMetricsComponents). `Chart`
// conforms to `View`, so these still apply to a `Chart` directly.
public extension View {
    func chartLegend(_ visibility: Visibility) -> Self {
        _ = visibility
        return self
    }

    func chartXAxis(_ visibility: Visibility) -> Self {
        _ = visibility
        return self
    }

    func chartYAxis(_ visibility: Visibility) -> Self {
        _ = visibility
        return self
    }

    func chartXAxis<AxisContent: View>(@ViewBuilder content: () -> AxisContent) -> Self {
        _ = content()
        return self
    }

    func chartYAxis<AxisContent: View>(@ViewBuilder content: () -> AxisContent) -> Self {
        _ = content()
        return self
    }

    func chartOverlay<OverlayContent: View>(@ViewBuilder content: (ChartProxy) -> OverlayContent) -> Self {
        _ = content(ChartProxy())
        return self
    }

    func chartXSelection<Value>(value: Binding<Value?>) -> Self {
        _ = value
        return self
    }

    func chartXScale(range: ChartScaleRange) -> Self {
        _ = range
        return self
    }

    func chartYScale<Domain>(domain: Domain) -> Self {
        _ = domain
        return self
    }
}

public enum AxisMarkPosition: Sendable {
    case automatic
    case leading
    case trailing
}

public struct AxisMarks<Content: View>: View {
    public init(position: AxisMarkPosition = .automatic) where Content == EmptyView {}
    public init<Data: RandomAccessCollection>(values: Data, @ViewBuilder content: (Data.Element) -> Content) {}
    public var body: some View { EmptyView() }
}

public struct AxisValueLabel: View {
    public init(format: DateFormatStyle, centered: Bool = false) {
        _ = format
        _ = centered
    }

    public var body: some View { EmptyView() }
}

public struct ChartScaleRange: Sendable {
    public init() {}

    public static func plotDimension(startPadding: Double = 0, endPadding: Double = 0) -> ChartScaleRange {
        _ = startPadding
        _ = endPadding
        return ChartScaleRange()
    }
}

public extension View {
    func symbol(_ shape: ChartSymbolShape) -> Self {
        _ = shape
        return self
    }

    func symbol<S: Shape>(_ shape: S) -> Self {
        _ = shape
        return self
    }

    func lineStyle(_ style: StrokeStyle) -> Self {
        _ = style
        return self
    }
}

public struct ChartSymbolShape: Sendable {
    public init() {}
    public static let circle = ChartSymbolShape()
}

// MARK: - ChartContent

/// Apple's Swift Charts `ChartContent` protocol. Vendored real source uses it
/// for `@ChartContentBuilder`-built properties (e.g. IceCubes
/// `AccountMetricsComponents.selectedRuleMark: some ChartContent`). It refines
/// `View` so that a value typed `some ChartContent` still satisfies the `View`
/// requirement of a `Chart { … }` `@ViewBuilder` content closure (an opaque
/// `some ChartContent` would otherwise erase the underlying `View` conformance,
/// breaking `ViewBuilder.buildPartialBlock`).
public protocol ChartContent: View {}

/// Type-erased terminal for `@ChartContentBuilder`.
public struct AnyChartContent: ChartContent {
    public init() {}
    public var body: some View { EmptyView() }
}

extension BarMark: ChartContent {}
extension LineMark: ChartContent {}
extension PointMark: ChartContent {}
extension AreaMark: ChartContent {}
extension RuleMark: ChartContent {}
extension RectangleMark: ChartContent {}
extension SectorMark: ChartContent {}

@resultBuilder
public enum ChartContentBuilder {
    // Marks and ForEach-of-marks arrive as `View`s; collapse the whole block to
    // a single type-erased terminal (rendering is inert in the shim).
    public static func buildExpression<V: View>(_ expression: V) -> AnyChartContent {
        _ = expression
        return AnyChartContent()
    }
    public static func buildExpression(_ expression: AnyChartContent) -> AnyChartContent { expression }
    public static func buildBlock(_ components: AnyChartContent...) -> AnyChartContent { AnyChartContent() }
    public static func buildOptional(_ component: AnyChartContent?) -> AnyChartContent { AnyChartContent() }
    public static func buildEither(first: AnyChartContent) -> AnyChartContent { first }
    public static func buildEither(second: AnyChartContent) -> AnyChartContent { second }
    public static func buildArray(_ components: [AnyChartContent]) -> AnyChartContent { AnyChartContent() }
    public static func buildLimitedAvailability(_ component: AnyChartContent) -> AnyChartContent { component }
}
