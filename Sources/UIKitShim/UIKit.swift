// UIKit shim. Provides the iOS UIKit surface for upstream apps that
// `import UIKit` (Ice Cubes, NetNewsWire iOS, …) when compiled on
// platforms where Apple's real UIKit isn't available (macOS without
// Catalyst, Linux). Inlines the high-traffic types directly so
// consumers don't need to depend on QuillFoundation/QuillUIKit
// transitively.

@_exported import Foundation
@_exported import QuillFoundation
@_exported import QuillUIKit
// Re-export the UserNotifications shim so the many `import UIKit`-only SSK files
// (e.g. ExperienceUpgradeManifest) still resolve UNUserNotificationCenter & co.
// now that QuillUIKit's stub was removed in favor of the dedicated shim.
@_exported import UserNotifications
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

// Not @MainActor: these are inert no-op shims (no real haptics on Linux), and
// SSK's HapticFeedback constructs them from nonisolated contexts. Dropping the
// isolation only relaxes (never breaks main-actor callers) and keeps macOS green.
public class UIImpactFeedbackGenerator: NSObject {
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

public class UISelectionFeedbackGenerator: NSObject {
    public override init() {}
    public func prepare() {
        recordUIKitFallback(operation: "hapticPrepare", api: "UISelectionFeedbackGenerator.prepare")
    }
    public func selectionChanged() {
        recordUIKitFallback(operation: "selectionChanged", api: "UISelectionFeedbackGenerator.selectionChanged")
    }
}

public class UINotificationFeedbackGenerator: NSObject {
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

    #if os(Linux)
    /// Battery monitoring is unavailable on QuillOS; this notification name
    /// exists (inert -- never posted) so SignalServiceKit's
    /// DeviceBatteryLevelManager compiles. `nonisolated` so the file-scope
    /// Notification.Name extension that aliases it can be evaluated off the main
    /// actor. Raw value matches Apple's.
    nonisolated public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")
    #endif
}

#if os(Linux)
public extension Notification.Name {
    /// ProcessInfo low-power-mode-changed notification (Foundation on Apple). Its
    /// sole SignalServiceKit consumer (DeviceBatteryLevelManager) imports UIKit,
    /// so the inert Linux shim lives here; never posted on QuillOS. Raw value
    /// matches Apple's. Linux-gated because macOS Foundation already defines it.
    static let NSProcessInfoPowerStateDidChange = Notification.Name("NSProcessInfoPowerStateDidChangeNotification")
}
#endif

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

// MARK: - NSDirectionalEdgeInsets
//
// Leading/trailing (writing-direction-relative) inset geometry. SSK reaches it
// via `import UIKit`; only the base value-holder is needed (SSK adds its own
// hMargin/vMargin/margin convenience inits in an extension).
public struct NSDirectionalEdgeInsets: Equatable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat
    public init(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
    public static let zero = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
}

// MARK: - UISwitch + UIInterfaceOrientationMask

/// `UISwitch: UIControl`. SSK only references it as a callback parameter type
/// (`switchDidChange(_ sender: UISwitch)` reading `.isOn`); never instantiated here.
@MainActor open class UISwitch: UIControl {
    public var isOn: Bool = false
    public func setOn(_ on: Bool, animated: Bool) { isOn = on }
}

/// UIBezierPath. Inert on Linux (no real geometry recorded): `.cgPath` is an
/// opaque handle that the inert CGContext drawing shim accepts as `Any`. SSK uses
/// `UIBezierPath(ovalIn:)` + `.cgPath` for avatar clipping.
public final class UIBezierPath {
    public let cgPath: CGPath
    public var lineWidth: CGFloat = 1
    public init() { self.cgPath = CGPath() }
    public init(ovalIn rect: CGRect) { self.cgPath = CGPath() }
    public init(rect: CGRect) { self.cgPath = CGPath() }
    public init(roundedRect rect: CGRect, cornerRadius: CGFloat) { self.cgPath = CGPath() }
    public init(cgPath: CGPath) { self.cgPath = cgPath }
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addArc(withCenter center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    public func close() {}
    public func append(_ bezierPath: UIBezierPath) {}
    public func addClip() {}
    public func fill() {}
    public func stroke() {}
}

public enum UIDeviceOrientation: Int, Sendable {
    case unknown, portrait, portraitUpsideDown, landscapeLeft, landscapeRight, faceUp, faceDown
    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
    public var isFlat: Bool { self == .faceUp || self == .faceDown }
    public var isValidInterfaceOrientation: Bool { isPortrait || isLandscape }
}

public struct UIInterfaceOrientationMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let portrait = UIInterfaceOrientationMask(rawValue: 1 << 1)
    public static let portraitUpsideDown = UIInterfaceOrientationMask(rawValue: 1 << 2)
    public static let landscapeRight = UIInterfaceOrientationMask(rawValue: 1 << 3)
    public static let landscapeLeft = UIInterfaceOrientationMask(rawValue: 1 << 4)
    public static let landscape: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]
    public static let all: UIInterfaceOrientationMask = [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight]
    public static let allButUpsideDown: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
}

// MARK: - UIGraphicsImageRenderer (Linux: placeholder images)
//
// SignalServiceKit renders avatars/thumbnails into a renderer context. On Linux
// nothing is rasterized: the context's CGContext is the inert no-op from
// QuillFoundation and `.image{}` returns a blank placeholder UIImage of the
// requested size. Faithful image generation needs a real raster backend
// (Cairo/Skia) -- deferred. HONEST STATUS: produced images are blank.
//
// Gated to Linux: macOS has no UIGraphicsImageRenderer and a real CGContext
// (no `init()`), so this block must not compile there -- keeps the package green
// for local `swift build` / `swift test` on macOS.
#if os(Linux)

// MARK: - NSString/String drawing (UIKit text rendering; Linux shim)
//
// AvatarBuilder + String+SSK measure and draw strings. swift-corelibs has no
// glyph layout, so boundingRect returns a rough estimate (from the .font
// attribute when present) and draw(...) is inert -- enough to compile and lay
// out roughly. Real rasterization is deferred to a Cairo/Pango paint layer.

public struct NSStringDrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let usesLineFragmentOrigin = NSStringDrawingOptions(rawValue: 1 << 0)
    public static let usesFontLeading = NSStringDrawingOptions(rawValue: 1 << 1)
    public static let usesDeviceMetrics = NSStringDrawingOptions(rawValue: 1 << 3)
    public static let truncatesLastVisibleLine = NSStringDrawingOptions(rawValue: 1 << 5)
}

public final class NSStringDrawingContext {
    public init() {}
    public var minimumScaleFactor: CGFloat = 0
    public var actualScaleFactor: CGFloat = 1
    public var totalBounds: CGRect = .zero
}

private func quillEstimatedTextRect(_ s: String, proposed: CGSize, attributes: [NSAttributedString.Key: Any]?) -> CGRect {
    let fontSize = (attributes?[.font] as? UIFont)?.pointSize ?? 13
    let charWidth = fontSize * 0.6
    let lineHeight = fontSize * 1.2
    let singleLineWidth = CGFloat(s.count) * charWidth
    let width = min(proposed.width, max(singleLineWidth, charWidth))
    let lines = width > 0 ? (singleLineWidth / width).rounded(.up) : 1
    let height = min(proposed.height, max(lines, 1) * lineHeight)
    return CGRect(x: 0, y: 0, width: width, height: max(height, lineHeight))
}

public extension String {
    func boundingRect(with size: CGSize,
                      options: NSStringDrawingOptions = [],
                      attributes: [NSAttributedString.Key: Any]? = nil,
                      context: NSStringDrawingContext? = nil) -> CGRect {
        _ = (options, context)
        return quillEstimatedTextRect(self, proposed: size, attributes: attributes)
    }
    func draw(at point: CGPoint, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        _ = (point, attributes) // inert: glyph rasterization deferred on Linux
    }
    func draw(in rect: CGRect, withAttributes attributes: [NSAttributedString.Key: Any]? = nil) {
        _ = (rect, attributes)
    }
}

public final class UIGraphicsImageRendererFormat {
    public var scale: CGFloat = 1
    public var opaque: Bool = false
    public var prefersExtendedRange: Bool = false
    public init() {}
    public static var `default`: UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
    public static func preferred() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

public final class UIGraphicsImageRendererContext {
    public let cgContext: CGContext
    public let format: UIGraphicsImageRendererFormat
    public init(cgContext: CGContext, format: UIGraphicsImageRendererFormat) {
        self.cgContext = cgContext
        self.format = format
    }
    public func fill(_ rect: CGRect) {}
    public func fill(_ rect: CGRect, blendMode: CGBlendMode) {}
    public func stroke(_ rect: CGRect) {}
    public func stroke(_ rect: CGRect, blendMode: CGBlendMode) {}
    public func clip(to rect: CGRect) {}
}

public final class UIGraphicsImageRenderer {
    public let size: CGSize
    public let format: UIGraphicsImageRendererFormat

    public init(size: CGSize, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) {
        self.size = size
        self.format = format
    }
    public convenience init(bounds: CGRect, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) {
        self.init(size: bounds.size, format: format)
    }

    private func runActions(_ actions: (UIGraphicsImageRendererContext) -> Void) {
        actions(UIGraphicsImageRendererContext(cgContext: CGContext(), format: format))
    }

    /// Returns a blank placeholder image of `size` (nothing is rasterized).
    public func image(_ actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        runActions(actions)
        return UIImage(size: size)
    }
    public func pngData(_ actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        runActions(actions)
        return Data()
    }
    public func jpegData(withCompressionQuality quality: CGFloat, actions: (UIGraphicsImageRendererContext) -> Void) -> Data {
        runActions(actions)
        return Data()
    }
}

// MARK: - Imperative UIGraphics* C-API (the pre-UIGraphicsImageRenderer style)
//
// AvatarBuilder still uses the old Begin/GetCurrentContext/GetImage/End flow. A
// minimal current-context stack backs it: the inert CGContext records nothing and
// the produced image is a blank placeholder of the begun size. Inert -- gated to
// Linux (these don't exist on macOS, and CGContext() is Linux-only).
nonisolated(unsafe) private var _uiGraphicsContextStack: [(context: CGContext, size: CGSize)] = []

public func UIGraphicsBeginImageContextWithOptions(_ size: CGSize, _ opaque: Bool, _ scale: CGFloat) {
    _uiGraphicsContextStack.append((CGContext(), size))
}
public func UIGraphicsBeginImageContext(_ size: CGSize) {
    _uiGraphicsContextStack.append((CGContext(), size))
}
public func UIGraphicsGetCurrentContext() -> CGContext? {
    _uiGraphicsContextStack.last?.context
}
public func UIGraphicsGetImageFromCurrentImageContext() -> UIImage? {
    guard let top = _uiGraphicsContextStack.last else { return nil }
    return UIImage(size: top.size)
}
public func UIGraphicsEndImageContext() {
    if !_uiGraphicsContextStack.isEmpty { _uiGraphicsContextStack.removeLast() }
}
public func UIGraphicsPushContext(_ context: CGContext) {}
public func UIGraphicsPopContext() {}
#endif

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
