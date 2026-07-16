import Foundation

// SwiftUI View-modifier / type surface used by vendored real source
// (DesignSystem) that SwiftOpenUI doesn't yet provide. No-ops on Linux where
// the modifier has no visual effect (preview layout, accessibility).
//
// NOTE: contentShape / onHover / accessibilityElement (+ AccessibilityChildBehavior)
// already live in QuillUI's UpstreamCompatibility — they are NOT duplicated here
// (doing so makes their use ambiguous inside QuillUI).

public enum PreviewLayout: Sendable {
    case device
    case sizeThatFits
    case fixed(width: CGFloat, height: CGFloat)
}

extension View {
    public func accessibilityHidden(_ hidden: Bool) -> some View { self }
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
