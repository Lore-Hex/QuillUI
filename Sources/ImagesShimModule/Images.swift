import Foundation
import RSCore

public final class IconImage: @unchecked Sendable {
    public let image: RSImage
    public let isSymbol: Bool
    public let isBackgroundSuppressed: Bool
    public let preferredColor: CGColor?

    public var isDark: Bool { false }
    public var isBright: Bool { false }

    public init(
        _ image: RSImage,
        isSymbol: Bool = false,
        isBackgroundSuppressed: Bool = false,
        preferredColor: CGColor? = nil
    ) {
        self.image = image
        self.isSymbol = isSymbol
        self.isBackgroundSuppressed = isBackgroundSuppressed
        self.preferredColor = preferredColor
    }
}

public enum IconSize: Int, CaseIterable, Sendable {
    case small = 1
    case medium = 2
    case large = 3

    public var size: CGSize {
        switch self {
        case .small:
            return CGSize(width: 24, height: 24)
        case .medium:
            return CGSize(width: 36, height: 36)
        case .large:
            return CGSize(width: 48, height: 48)
        }
    }
}
