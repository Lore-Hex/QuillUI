import Foundation

/// Horizontal alignment for children within a VStack.
public enum HorizontalAlignment {
    case leading
    case center
    case trailing
}

/// Vertical alignment for children within an HStack.
public enum VerticalAlignment {
    case top
    case center
    case bottom
    case firstTextBaseline
    case lastTextBaseline

    public init(_ id: any AlignmentID.Type) {
        _ = id
        self = .bottom
    }
}

public struct ViewDimensions {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat = 0, height: CGFloat = 0) {
        self.width = width
        self.height = height
    }
}

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
}

/// Two-dimensional alignment for ZStack and frame alignment.
public enum Alignment {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
}
