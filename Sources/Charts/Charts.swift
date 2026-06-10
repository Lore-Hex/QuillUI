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

public extension Chart {
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
