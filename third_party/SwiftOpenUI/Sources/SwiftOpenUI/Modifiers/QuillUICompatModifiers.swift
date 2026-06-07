import Foundation

// SwiftUI View-modifier surface MOVED here from QuillUI/UpstreamCompatibility so a
// single canonical declaration is visible to BOTH QuillUI (via @_exported import
// SwiftOpenUI) and vendored real source (DesignSystem, which imports SwiftOpenUI
// through the SwiftUI shadow). These are metadata-passthrough modifiers that GTK
// does not render from here, so they are no-ops on Linux. (Having two copies — in
// QuillUI and here — makes their use ambiguous, hence the move.)
public struct AccessibilityChildBehavior: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }
    public static let ignore = AccessibilityChildBehavior("ignore")
    public static let combine = AccessibilityChildBehavior("combine")
    public static let contain = AccessibilityChildBehavior("contain")
}

extension View {
    public func contentShape<S: Shape>(_ shape: S) -> some View { self }
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View { self }
    public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View { self }
    public func allowsHitTesting(_ enabled: Bool) -> some View { self }
    public func listRowSeparator(_ visibility: Visibility, edges: Edge.Set = .all) -> some View { self }
    public func accessibilityLabel<S>(_ label: S) -> some View { self }
    public func accessibilityValue<S>(_ value: S) -> some View { self }
    public func listRowInsets(_ insets: EdgeInsets?) -> some View { self }
}
