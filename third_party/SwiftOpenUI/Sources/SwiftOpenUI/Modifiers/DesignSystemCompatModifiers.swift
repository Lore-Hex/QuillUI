import Foundation

// SwiftUI View-modifier / type surface used by vendored real source
// (DesignSystem) that SwiftOpenUI doesn't yet provide. No-ops on Linux where
// the modifier has no visual effect (accessibility, hover, preview layout).

public enum PreviewLayout: Sendable {
    case device
    case sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
}

public struct AccessibilityChildBehavior: Equatable, Sendable {
    let raw: Int
    public static let ignore = AccessibilityChildBehavior(raw: 0)
    public static let combine = AccessibilityChildBehavior(raw: 1)
    public static let contain = AccessibilityChildBehavior(raw: 2)
}

extension View {
    public func accessibilityHidden(_ hidden: Bool) -> some View { self }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View { self }
    public func contentShape<S>(_ shape: S) -> some View { self }
    public func listRowBackground<V: View>(_ view: V?) -> some View { self }
    public func tint(_ tint: Color?) -> some View { self }
    public func previewLayout(_ value: PreviewLayout) -> some View { self }
}

extension Font {
    public func weight(_ weight: FontWeight) -> Font { self }
}

extension Color {
    public struct Resolved: Equatable, Sendable {
        public var red: Float
        public var green: Float
        public var blue: Float
        public var opacity: Float
    }
    public func resolve(in environment: EnvironmentValues) -> Resolved {
        Resolved(red: Float(red), green: Float(green), blue: Float(blue), opacity: Float(alpha))
    }
}
