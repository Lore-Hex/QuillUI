import SwiftOpenUI

// SwiftUI `LayoutDirection` + `EnvironmentValues.layoutDirection`, used by
// vendored DesignSystem (`.environment(\.layoutDirection, isRTL() ? .rightToLeft : .leftToRight)`).
// Surfaced to vendored source via the SwiftUI shim's re-export of QuillSwiftUICompatibility.
public enum LayoutDirection: Hashable, Sendable {
    case leftToRight
    case rightToLeft
}

private struct LayoutDirectionKey: EnvironmentKey {
    static let defaultValue = LayoutDirection.leftToRight
}

extension EnvironmentValues {
    public var layoutDirection: LayoutDirection {
        get { self[LayoutDirectionKey.self] }
        set { self[LayoutDirectionKey.self] = newValue }
    }
}
