import Foundation
import QuillKit

public typealias CGFloat = Double
public typealias TimeInterval = Foundation.TimeInterval

public final class UIGestureRecognizer: @unchecked Sendable {
    public enum State: Int, Sendable {
        case possible
        case began
        case changed
        case ended
        case cancelled
        case failed
    }

    public init() {}
}

public final class UIImage: @unchecked Sendable {
    public var data: Data?

    public init?(data: Data) {
        self.data = data
    }
}

public final class UIPasteboard: @unchecked Sendable {
    public static let general = UIPasteboard()
    public var string: String? {
        get { QuillClipboard.shared.string() }
        set { QuillClipboard.shared.setString(newValue) }
    }
    public var image: UIImage?

    public init() {}
}

public final class UIControl: @unchecked Sendable {
    public struct State: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let normal: State = []
        public static let highlighted = State(rawValue: 1 << 0)
        public static let disabled = State(rawValue: 1 << 1)
        public static let selected = State(rawValue: 1 << 2)
        public static let focused = State(rawValue: 1 << 3)
        public static let application = State(rawValue: 0x00FF_0000)
        public static let reserved = State(rawValue: 0xFF00_0000)
    }

    public init() {}
}

public final class UIImpactFeedbackGenerator: @unchecked Sendable {
    public enum FeedbackStyle: Sendable {
        case light
        case medium
    }

    public init(style: FeedbackStyle) {}
    public func impactOccurred() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "UIKit",
            operation: "impactOccurred",
            severity: .info,
            message: "Haptic feedback is recorded as a diagnostic fallback until a native Linux backend is attached."
        )
    }
}

public final class UIView: @unchecked Sendable {
    public struct AnimationOptions: OptionSet, Sendable {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        public static let layoutSubviews = AnimationOptions(rawValue: 1 << 0)
        public static let allowUserInteraction = AnimationOptions(rawValue: 1 << 1)
        public static let beginFromCurrentState = AnimationOptions(rawValue: 1 << 2)
        public static let repeatAnimation = AnimationOptions(rawValue: 1 << 3)
        public static let autoreverse = AnimationOptions(rawValue: 1 << 4)
        public static let overrideInheritedDuration = AnimationOptions(rawValue: 1 << 5)
        public static let overrideInheritedCurve = AnimationOptions(rawValue: 1 << 6)
        public static let allowAnimatedContent = AnimationOptions(rawValue: 1 << 7)
        public static let showHideTransitionViews = AnimationOptions(rawValue: 1 << 8)
        public static let overrideInheritedOptions = AnimationOptions(rawValue: 1 << 9)
        public static let curveEaseInOut = AnimationOptions(rawValue: 0 << 16)
        public static let curveEaseIn = AnimationOptions(rawValue: 1 << 16)
        public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16)
        public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
        public static let transitionFlipFromLeft = AnimationOptions(rawValue: 1 << 20)
        public static let transitionFlipFromRight = AnimationOptions(rawValue: 2 << 20)
        public static let transitionCurlUp = AnimationOptions(rawValue: 3 << 20)
        public static let transitionCurlDown = AnimationOptions(rawValue: 4 << 20)
        public static let transitionCrossDissolve = AnimationOptions(rawValue: 5 << 20)
        public static let transitionFlipFromTop = AnimationOptions(rawValue: 6 << 20)
        public static let transitionFlipFromBottom = AnimationOptions(rawValue: 7 << 20)
        public static let preferredFramesPerSecondDefault = AnimationOptions(rawValue: 0 << 24)
        public static let preferredFramesPerSecond60 = AnimationOptions(rawValue: 3 << 24)
        public static let preferredFramesPerSecond30 = AnimationOptions(rawValue: 7 << 24)
    }

    public init() {}

    public static func animate(
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }

    public static func animate(
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0,
        usingSpringWithDamping dampingRatio: CGFloat,
        initialSpringVelocity velocity: CGFloat,
        options: AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        animations()
        completion?(true)
    }
}

public final class UINotificationFeedbackGenerator: @unchecked Sendable {
    public enum FeedbackType: Sendable {
        case success
        case warning
        case error
    }

    public init() {}
    public func notificationOccurred(_ notificationType: FeedbackType) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "UIKit",
            operation: "notificationOccurred",
            severity: .info,
            message: "Notification haptic feedback is recorded as a diagnostic fallback until a native Linux backend is attached."
        )
    }
}

public enum UIResponder {
    public static let keyboardWillShowNotification = Notification.Name("UIResponder.keyboardWillShowNotification")
    public static let keyboardWillHideNotification = Notification.Name("UIResponder.keyboardWillHideNotification")
}

public final class UIScrollView: @unchecked Sendable {
    public enum ContentInsetAdjustmentBehavior: Int, Sendable {
        case automatic
        case scrollableAxes
        case never
        case always
    }

    public init() {}
}

public enum UIUserInterfaceStyle: Int, Sendable {
    case unspecified
    case light
    case dark
}

public final class UISplitViewController: @unchecked Sendable {
    public enum DisplayMode: Int, Sendable {
        case automatic
        case secondaryOnly
        case oneBesideSecondary
        case oneOverSecondary
        case twoBesideSecondary
        case twoOverSecondary
        case twoDisplaceSecondary
    }

    public enum DisplayModeButtonVisibility: Int, Sendable {
        case automatic
        case never
        case always
    }

    public enum SplitBehavior: Int, Sendable {
        case automatic
        case tile
        case overlay
        case displace
    }

    public enum Column: Int, Sendable {
        case primary
        case supplementary
        case secondary
        case compact
        case inspector
    }

    public enum Style: Int, Sendable {
        case unspecified
        case doubleColumn
        case tripleColumn
    }

    public enum PrimaryEdge: Int, Sendable {
        case leading
        case trailing
    }

    public enum BackgroundStyle: Int, Sendable {
        case none
        case sidebar
    }

    public enum LayoutEnvironment: Int, Sendable {
        case none
        case expanded
        case collapsed
    }

    public init() {}
}
