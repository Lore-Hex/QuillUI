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
#else
// Linux: no AppKit/UIKit fonts. Provide the UIFont surface upstream UI uses
// (scaled system fonts, the `.rounded` design). Metrics are identity on Linux.
public final class UIFont {
    public let pointSize: CGFloat
    public let fontName: String
    public let fontDescriptor: UIFontDescriptor
    public init(descriptor: UIFontDescriptor, size: CGFloat) {
        self.pointSize = size; self.fontName = descriptor.name; self.fontDescriptor = descriptor
    }
    init(pointSize: CGFloat, fontName: String) {
        self.pointSize = pointSize; self.fontName = fontName
        self.fontDescriptor = UIFontDescriptor(name: fontName)
    }
    public static func systemFont(ofSize size: CGFloat) -> UIFont {
        UIFont(pointSize: size, fontName: ".AppleSystemUIFont")
    }
    public static func systemFont(ofSize size: CGFloat, weight: Weight) -> UIFont {
        UIFont(pointSize: size, fontName: ".AppleSystemUIFont")
    }
    public struct Weight: Equatable, Sendable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let ultraLight = Weight(rawValue: -0.8)
        public static let thin = Weight(rawValue: -0.6)
        public static let light = Weight(rawValue: -0.4)
        public static let regular = Weight(rawValue: 0)
        public static let medium = Weight(rawValue: 0.23)
        public static let semibold = Weight(rawValue: 0.3)
        public static let bold = Weight(rawValue: 0.4)
        public static let heavy = Weight(rawValue: 0.56)
        public static let black = Weight(rawValue: 0.62)
    }
}
public final class UIFontDescriptor {
    public let name: String
    public init(name: String = ".AppleSystemUIFont") { self.name = name }
    public enum SystemDesign: Equatable, Sendable { case `default`, rounded, serif, monospaced }
    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
        UIFontDescriptor(name: design == .rounded ? ".AppleSystemUIFontRounded-Regular" : name)
    }
}
public final class UIFontMetrics {
    public static let `default` = UIFontMetrics()
    public func scaledValue(for value: CGFloat) -> CGFloat { value }
}
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
    // Async form used by SwiftUI/UIKit real source (`await UIApplication.shared.open(url)`).
    // Disambiguate to the completion-handler overload to avoid recursing into itself.
    @MainActor @discardableResult public func open(_ url: URL) async -> Bool {
        open(url, options: [:], completionHandler: nil)
    }
    @MainActor public func registerForRemoteNotifications() {}
    public enum LaunchOptionsKey: Hashable { case remoteNotification }
    @MainActor public var connectedScenes: Set<UIScene> = []
    @MainActor public var applicationState: UIApplicationState { .active }
    @MainActor public func setAlternateIconName(_ name: String?, completionHandler: ((Error?) -> Void)? = nil) {
        completionHandler?(nil)
    }
    @MainActor public var alternateIconName: String? { nil }
}

public enum UIApplicationState: Int { case active, inactive, background }

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

// MARK: - UI* extras Ice Cubes references

#if canImport(AppKit)
// On macOS, NSEvent.ModifierFlags is the analogue.
public typealias UIKeyModifierFlags = NSEvent.ModifierFlags
#endif

#endif // !os(iOS)
