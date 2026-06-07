import SwiftOpenUI

// SwiftUI's `RedactionReasons` + `EnvironmentValues.redactionReasons`, used by
// vendored DesignSystem (`@Environment(\.redactionReasons)` in AvatarView to
// show a placeholder while loading). Surfaced to vendored real source through
// the SwiftUI shim's re-export of QuillSwiftUICompatibility. No GTK redaction
// rendering yet — the value is readable so view bodies type-check and branch.
public struct RedactionReasons: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let placeholder = RedactionReasons(rawValue: 1 << 0)
    public static let privacy = RedactionReasons(rawValue: 1 << 1)
    public static let invalidated = RedactionReasons(rawValue: 1 << 2)
}

private struct RedactionReasonsKey: EnvironmentKey {
    static let defaultValue = RedactionReasons()
}

extension EnvironmentValues {
    public var redactionReasons: RedactionReasons {
        get { self[RedactionReasonsKey.self] }
        set { self[RedactionReasonsKey.self] = newValue }
    }
}
