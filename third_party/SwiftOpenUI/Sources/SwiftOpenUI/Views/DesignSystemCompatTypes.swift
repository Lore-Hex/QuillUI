import Foundation

// SwiftUI types used by vendored real source (DesignSystem) not yet in
// SwiftOpenUI. Additive; no behavioral effect on the Linux backend.

public protocol PreviewProvider {
    associatedtype Previews: View
    @MainActor static var previews: Previews { get }
}

public struct ViewDimensions: Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat = 0, height: CGFloat = 0) {
        self.width = width; self.height = height
    }
    public subscript(guide: HorizontalAlignment) -> CGFloat { 0 }
    public subscript(guide: VerticalAlignment) -> CGFloat { 0 }
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { nil }
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { nil }
}

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}
