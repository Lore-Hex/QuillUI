// UIKit shim. Provides the iOS UIKit surface for upstream apps that
// `import UIKit` (Ice Cubes, NetNewsWire iOS, …) when compiled on
// platforms where Apple's real UIKit isn't available (macOS without
// Catalyst, Linux). Inlines the high-traffic types directly so
// consumers don't need to depend on QuillFoundation/QuillUIKit
// transitively.

@_exported import Foundation
@_exported import QuillFoundation
@_exported import QuillUIKit
import QuillKit

#if !os(iOS)

private func recordUIKitFallback(operation: String, api: String) {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "UIKit",
        operation: operation,
        message: "\(api) is a no-op on non-iOS platforms."
    )
}

#if canImport(AppKit)
import AppKit
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIFont = NSFont
public typealias UIScreen = NSScreen
#endif

// MARK: - UIApplication (macOS-shape)

public class UIApplication: NSObject {
    @MainActor public static let shared = UIApplication()
    @MainActor @discardableResult public func open(
        _ url: URL,
        options: [AnyHashable: Any] = [:],
        completionHandler: ((Bool) -> Void)? = nil
    ) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.open(url)
        #else
        return false
        #endif
    }
    @MainActor public func registerForRemoteNotifications() {}
    public enum LaunchOptionsKey: Hashable { case remoteNotification }
    @MainActor public var connectedScenes: Set<UIScene> = []
    @MainActor public var applicationState: UIApplicationState { .active }

    /// UIKit (and SignalServiceKit's AppContext) name the application-state enum
    /// `UIApplication.State`; `UIApplicationState` is its top-level alias on iOS.
    public typealias State = UIApplicationState

    // App-lifecycle notification names. Real UIKit members; SignalServiceKit's
    // lifecycle observers subscribe to these. No source posts them on Linux yet.
    public static let didBecomeActiveNotification = Notification.Name("UIApplicationDidBecomeActiveNotification")
    public static let willResignActiveNotification = Notification.Name("UIApplicationWillResignActiveNotification")
    public static let didEnterBackgroundNotification = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    public static let willEnterForegroundNotification = Notification.Name("UIApplicationWillEnterForegroundNotification")
    public static let willTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
    public static let didReceiveMemoryWarningNotification = Notification.Name("UIApplicationDidReceiveMemoryWarningNotification")
    public static let significantTimeChangeNotification = Notification.Name("UIApplicationSignificantTimeChangeNotification")

    @MainActor public func setAlternateIconName(_ name: String?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
    @MainActor public var alternateIconName: String? { nil }
}

public enum UIApplicationState: Int { case active, inactive, background }

// Text alignment. On iOS this lives in UIKit (and in AppKit on macOS, where
// QuillAppKit already mirrors it). SignalServiceKit reaches it via `import
// UIKit`, so it is mirrored here too. Case order matches QuillAppKit's.
public enum NSTextAlignment: Int, Sendable {
    case left, right, center, justified, natural
}

// Text layout enums + paragraph style (UIKit on iOS, AppKit on macOS). Mirrored
// here so SignalServiceKit's attributed-string code resolves them via import
// UIKit. Case order matches QuillAppKit's.
public enum NSLineBreakMode: Int, Sendable {
    case byWordWrapping, byCharWrapping, byClipping, byTruncatingHead, byTruncatingTail, byTruncatingMiddle
}

public enum NSWritingDirection: Int, Sendable {
    case natural = -1, leftToRight = 0, rightToLeft = 1
}

open class NSParagraphStyle: NSObject {
    nonisolated(unsafe) public static let `default` = NSParagraphStyle()
    public var alignment: NSTextAlignment = .natural
    public var lineBreakMode: NSLineBreakMode = .byWordWrapping
    public var lineSpacing: CGFloat = 0
    public var paragraphSpacing: CGFloat = 0
    public var firstLineHeadIndent: CGFloat = 0
    public var headIndent: CGFloat = 0
    public var tailIndent: CGFloat = 0
    public var lineHeightMultiple: CGFloat = 0
    public var minimumLineHeight: CGFloat = 0
    public var maximumLineHeight: CGFloat = 0
    public var baseWritingDirection: NSWritingDirection = .natural
    public var defaultTabInterval: CGFloat = 0
    public var tabStops: [Any]? = []
    public override init() { super.init() }
}

open class NSMutableParagraphStyle: NSParagraphStyle {}

// Standard attributed-string attribute keys (UIKit/AppKit additions; not in
// swift-corelibs Foundation). Raw values match Apple's.
public extension NSAttributedString.Key {
    static let font = NSAttributedString.Key(rawValue: "NSFont")
    static let foregroundColor = NSAttributedString.Key(rawValue: "NSColor")
    static let backgroundColor = NSAttributedString.Key(rawValue: "NSBackgroundColor")
    static let paragraphStyle = NSAttributedString.Key(rawValue: "NSParagraphStyle")
    static let underlineStyle = NSAttributedString.Key(rawValue: "NSUnderline")
    static let underlineColor = NSAttributedString.Key(rawValue: "NSUnderlineColor")
    static let strikethroughStyle = NSAttributedString.Key(rawValue: "NSStrikethrough")
    static let strikethroughColor = NSAttributedString.Key(rawValue: "NSStrikethroughColor")
    static let link = NSAttributedString.Key(rawValue: "NSLink")
    static let attachment = NSAttributedString.Key(rawValue: "NSAttachment")
    static let kern = NSAttributedString.Key(rawValue: "NSKern")
    static let baselineOffset = NSAttributedString.Key(rawValue: "NSBaselineOffset")
}

public class UIScene: NSObject {
    @MainActor public var delegate: Any?
}

// MARK: - Haptic feedback (no-op on non-iOS)

@MainActor public class UIImpactFeedbackGenerator: NSObject {
    public enum FeedbackStyle: Int { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle = .medium) {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UIImpactFeedbackGenerator.prepare")
    }
    public func impactOccurred() {
        recordUIKitFallback(operation: "impactOccurred", api: "UIImpactFeedbackGenerator.impactOccurred")
    }
    public func impactOccurred(intensity: CGFloat) {
        recordUIKitFallback(operation: "impactOccurred", api: "UIImpactFeedbackGenerator.impactOccurred(intensity:)")
    }
}

@MainActor public class UISelectionFeedbackGenerator: NSObject {
    public override init() {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UISelectionFeedbackGenerator.prepare")
    }
    public func selectionChanged() {
        recordUIKitFallback(operation: "selectionChanged", api: "UISelectionFeedbackGenerator.selectionChanged")
    }
}

@MainActor public class UINotificationFeedbackGenerator: NSObject {
    public enum FeedbackType: Int { case success, warning, error }
    public override init() {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UINotificationFeedbackGenerator.prepare")
    }
    public func notificationOccurred(_ type: FeedbackType) {
        recordUIKitFallback(operation: "notificationOccurred", api: "UINotificationFeedbackGenerator.notificationOccurred")
    }
}

// MARK: - UIDevice / UIScreen extras commonly used by iOS-only upstream

@MainActor public class UIDevice: NSObject {
    public static let current = UIDevice()
    public var userInterfaceIdiom: UIUserInterfaceIdiom { .mac }
    public var name: String {
        #if canImport(AppKit)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Mac"
        #endif
    }
}

public enum UIUserInterfaceIdiom: Int, Sendable {
    case unspecified = -1, phone = 0, pad = 1, tv = 2, carPlay = 3, mac = 5, vision = 6
}

// MARK: - UIEdgeInsets
//
// Layout-inset geometry (UIKit on iOS; NSEdgeInsets on macOS). SignalServiceKit
// reaches it via `import UIKit`. Only the raw four-edge value-holder lives here;
// SSK's own `UIEdgeInsets(margin:)` convenience init is an extension that builds
// on this base.
public struct UIEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat
    public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
    public static let zero = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
}

// MARK: - NSTextStorage (TextKit)
//
// On iOS NSTextStorage lives in UIKit. SignalServiceKit's
// EditableMessageBodyTextStorage subclasses it and overrides the primitive
// attributed-string methods plus the editing hooks, so it must exist (and be
// open) here. Backed by NSMutableAttributedString; editing notifications are
// inert on Linux.

public struct NSTextStorageEditActions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let editedAttributes = NSTextStorageEditActions(rawValue: 1 << 0)
    public static let editedCharacters = NSTextStorageEditActions(rawValue: 1 << 1)
}

open class NSTextStorage: NSMutableAttributedString {
    /// NSTextStorage.EditActions is the nested spelling used by callers.
    public typealias EditActions = NSTextStorageEditActions

    public weak var delegate: AnyObject?

    open func processEditing() {}

    open func edited(_ editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {}

    // beginEditing()/endEditing() are inherited from NSMutableAttributedString.
    // fixAttributes(in:) is not exposed there, so declare it for the subclass.
    open func fixAttributes(in range: NSRange) {}
}

// MARK: - UI* extras Ice Cubes references

#if canImport(AppKit)
// On macOS, NSEvent.ModifierFlags is the analogue.
public typealias UIKeyModifierFlags = NSEvent.ModifierFlags
#endif

#endif // !os(iOS)
