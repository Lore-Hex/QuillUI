import SwiftUI

public struct Chart<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
    public var body: some View { EmptyView() }
}

public struct BarMark: View {
    public init(x: Any, y: Any) {}
    public var body: some View { EmptyView() }
}

public struct LineMark: View {
    public init(x: Any, y: Any) {}
    public var body: some View { EmptyView() }
}

public struct PointMark: View {
    public init(x: Any, y: Any) {}
    public var body: some View { EmptyView() }
}

public struct AreaMark: View {
    public init(x: Any, y: Any) {}
    public var body: some View { EmptyView() }
}

public struct RuleMark: View {
    public init(y: Any) {}
    public var body: some View { EmptyView() }
}

public struct SectorMark: View {
    public init(angle: Any) {}
    public var body: some View { EmptyView() }
}

public enum PlottableValue<Value> {
    case value(String, Value)
}

public func value<Value>(_ label: String, _ value: Value) -> PlottableValue<Value> {
    .value(label, value)
}
