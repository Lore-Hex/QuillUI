/// An edge of a rectangle.
public enum Edge: Hashable, Sendable {
    case top
    case leading
    case bottom
    case trailing

    public var rawValue: Int {
        switch self {
        case .top: 1
        case .leading: 2
        case .bottom: 4
        case .trailing: 8
        }
    }

    public init(rawValue: Int) {
        switch rawValue {
        case 1: self = .top
        case 2: self = .leading
        case 4: self = .bottom
        case 8: self = .trailing
        default: self = .top
        }
    }

    /// A set of edges.
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]
        public static let all: Set = [.top, .leading, .bottom, .trailing]
    }
}

/// The inset distances for the sides of a rectangle.
public struct EdgeInsets: Equatable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}
