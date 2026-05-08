import Foundation
import QuillKit

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
