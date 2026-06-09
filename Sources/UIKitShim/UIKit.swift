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

#if canImport(AppKit) && !os(Linux)
import AppKit
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIFont = NSFont
public typealias UIScreen = NSScreen
#else
// Linux: no AppKit/UIKit fonts. Provide the UIFont surface upstream UI uses
// (scaled system fonts, the `.rounded` design). Metrics are identity on Linux.
public final class UIFont: Equatable, @unchecked Sendable {
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
    // UIFont(name:size:) — failable in UIKit; inert here (no font lookup on
    // Linux), so it never actually returns nil. SSK force-unwraps it
    // (AvatarBuilder's "Inter" text-avatar font).
    public convenience init?(name: String, size: CGFloat) {
        self.init(pointSize: size, fontName: name)
    }
    // UIFont.withSize(_:) — same font (name/descriptor) at a new point size.
    public func withSize(_ size: CGFloat) -> UIFont {
        UIFont(descriptor: fontDescriptor, size: size)
    }
    // UIFont.lineHeight / .capHeight — real font metrics. There is no font engine
    // on Linux, so these are typographic approximations derived from pointSize
    // (system-font ratios: lineHeight ≈ 1.2·pointSize, capHeight ≈ 0.7·pointSize).
    // SSK uses lineHeight for text-height measurement (String+SSK.height(for:)) and
    // capHeight for vertical image-attachment centering; both degrade to approximate
    // layout on Linux (HONEST STATUS: no exact glyph metrics).
    public var lineHeight: CGFloat { pointSize * 1.2 }
    public var capHeight: CGFloat { pointSize * 0.7 }
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
extension UIFont {
    // Equatable so SSK value types that embed a UIFont (e.g.
    // StyleDisplayConfiguration / MentionDisplayConfiguration in BodyRanges)
    // can synthesize Equatable. Compared by the inert shim's identifying
    // fields; there is no real font backing on Linux.
    public static func == (lhs: UIFont, rhs: UIFont) -> Bool {
        lhs.pointSize == rhs.pointSize
            && lhs.fontName == rhs.fontName
            && lhs.fontDescriptor.symbolicTraits == rhs.fontDescriptor.symbolicTraits
    }
}

public final class UIFontDescriptor: @unchecked Sendable {
    public let name: String
    // Symbolic traits requested on this descriptor. Inert on Linux (no real
    // font substitution) but round-tripped so `withSymbolicTraits` composes
    // and UIFont's Equatable can distinguish bold/italic variants.
    public var symbolicTraits: SymbolicTraits
    public init(name: String = ".AppleSystemUIFont", symbolicTraits: SymbolicTraits = []) {
        self.name = name
        self.symbolicTraits = symbolicTraits
    }
    public enum SystemDesign: Equatable, Sendable { case `default`, rounded, serif, monospaced }
    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
        UIFontDescriptor(
            name: design == .rounded ? ".AppleSystemUIFontRounded-Regular" : name,
            symbolicTraits: symbolicTraits
        )
    }
    // Mirror of UIKit's UIFontDescriptor.SymbolicTraits. Bit values match the
    // platform constants so any compared/persisted raw values stay stable.
    public struct SymbolicTraits: OptionSet, Sendable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        public static let traitItalic = SymbolicTraits(rawValue: 1 << 0)
        public static let traitBold = SymbolicTraits(rawValue: 1 << 1)
        public static let traitExpanded = SymbolicTraits(rawValue: 1 << 5)
        public static let traitCondensed = SymbolicTraits(rawValue: 1 << 6)
        public static let traitMonoSpace = SymbolicTraits(rawValue: 1 << 10)
        public static let traitVertical = SymbolicTraits(rawValue: 1 << 11)
        public static let traitUIOptimized = SymbolicTraits(rawValue: 1 << 12)
        public static let traitTightLeading = SymbolicTraits(rawValue: 1 << 15)
        public static let traitLooseLeading = SymbolicTraits(rawValue: 1 << 16)
    }
    public func withSymbolicTraits(_ traits: SymbolicTraits) -> UIFontDescriptor? {
        UIFontDescriptor(name: name, symbolicTraits: symbolicTraits.union(traits))
    }
}
public final class UIFontMetrics: @unchecked Sendable {
    public static let `default` = UIFontMetrics()
    public func scaledValue(for value: CGFloat) -> CGFloat { value }
}
#endif

// MARK: - UIApplication (macOS-shape)

public class UIApplication: NSObject, @unchecked Sendable {
    @MainActor public static let shared = UIApplication()
    @MainActor @discardableResult public func open(
        _ url: URL,
        options: [AnyHashable: Any] = [:],
        completionHandler: ((Bool) -> Void)? = nil
    ) -> Bool {
        #if canImport(AppKit) && !os(Linux)
        let didOpen = NSWorkspace.shared.open(url)
        completionHandler?(didOpen)
        return didOpen
        #elseif os(Linux)
        let didOpen = QuillWorkspace.open(url)
        completionHandler?(didOpen)
        return didOpen
        #else
        completionHandler?(false)
        return false
        #endif
    }
    // Async form used by SwiftUI/UIKit real source (`await UIApplication.shared.open(url)`).
    // Disambiguate to the completion-handler overload to avoid recursing into itself.
    @MainActor @discardableResult public func open(_ url: URL) async -> Bool {
        open(url, options: [:], completionHandler: nil)
    }
    @MainActor public func registerForRemoteNotifications() {
        QuillNotificationService.shared.registerForRemoteNotifications()
    }
    @MainActor public func unregisterForRemoteNotifications() {
        QuillNotificationService.shared.unregisterForRemoteNotifications()
    }
    @MainActor public var isRegisteredForRemoteNotifications: Bool {
        QuillNotificationService.shared.remoteNotificationsRegistered
    }
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

public extension NSParagraphStyle {
    /// Inert on Linux: returns .natural (no per-language BiDi resolution yet).
    /// SSK's String.naturalTextAlignment switches over the result.
    class func defaultWritingDirection(forLanguage language: String?) -> NSWritingDirection {
        return .natural
    }
}

// NSTextAttachment: an inline image/data attachment in an attributed string.
// swift-corelibs Foundation has no NSTextAttachment; SSK (String+SSK) builds one
// to embed a templated image. Inert holder of image/bounds; rendering deferred.
open class NSTextAttachment: NSObject {
    public var image: UIImage?
    public var bounds: CGRect
    public var contents: Data?
    public override init() {
        self.image = nil
        self.bounds = .zero
        self.contents = nil
        super.init()
    }
}

public extension UIImage {
    enum RenderingMode: Int, Sendable {
        case automatic = 0
        case alwaysOriginal = 1
        case alwaysTemplate = 2
    }
    /// Inert on Linux: returns self (no template tinting). SSK uses
    /// .alwaysTemplate for theme-tinted glyphs; the original image suffices.
    func withRenderingMode(_ renderingMode: RenderingMode) -> UIImage {
        return self
    }
}

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

// Mirror of UIKit's NSUnderlineStyle. Modeled as an OptionSet (matching the
// platform, where line styles and patterns combine) with the standard raw
// values; SSK uses `.single.rawValue` for strikethrough/underline attributes.
public struct NSUnderlineStyle: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = NSUnderlineStyle(rawValue: 0x01)
    public static let thick = NSUnderlineStyle(rawValue: 0x02)
    public static let double = NSUnderlineStyle(rawValue: 0x09)
    public static let patternSolid: NSUnderlineStyle = []
    public static let patternDot = NSUnderlineStyle(rawValue: 0x0100)
    public static let patternDash = NSUnderlineStyle(rawValue: 0x0200)
    public static let patternDashDot = NSUnderlineStyle(rawValue: 0x0300)
    public static let patternDashDotDot = NSUnderlineStyle(rawValue: 0x0400)
    public static let byWord = NSUnderlineStyle(rawValue: 0x8000)
}

public extension NSAttributedString {
    /// NSAttributedString(attachment:) -- wraps a text attachment in an attributed
    /// string with the attachment attribute under the U+FFFC object-replacement
    /// character (matches Apple). Image rendering is inert; the attribute is set.
    convenience init(attachment: NSTextAttachment) {
        self.init(string: "\u{FFFC}", attributes: [.attachment: attachment])
    }
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
    nonisolated public static let current = UIDevice()
    // nonisolated init so the nonisolated `current` default value (UIDevice())
    // can be evaluated off the main actor; UIDevice has no isolated stored state.
    nonisolated public override init() { super.init() }
    nonisolated public var userInterfaceIdiom: UIUserInterfaceIdiom { .mac }
    public var name: String {
        #if canImport(AppKit)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Mac"
        #endif
    }
    /// Inert device-info strings (AppVersion reads these). nonisolated so
    /// off-main-actor callers can read them (Strings are Sendable).
    nonisolated public var systemVersion: String { "1.0" }
    nonisolated public var model: String { "QuillOS" }

    #if os(Linux)
    /// Battery monitoring is unavailable on QuillOS; this notification name
    /// exists (inert -- never posted) so SignalServiceKit's
    /// DeviceBatteryLevelManager compiles. `nonisolated` so the file-scope
    /// Notification.Name extension that aliases it can be evaluated off the main
    /// actor. Raw value matches Apple's.
    nonisolated public static let batteryLevelDidChangeNotification = Notification.Name("UIDeviceBatteryLevelDidChangeNotification")

    /// Proximity sensor is unavailable on QuillOS. The notification name exists
    /// (inert -- never posted); proximityState is always false; enabling
    /// monitoring is a no-op. SignalServiceKit's ProximityMonitoringManager uses
    /// these. nonisolated static (Sendable) like the battery name.
    nonisolated public static let proximityStateDidChangeNotification = Notification.Name("UIDeviceProximityStateDidChangeNotification")
    nonisolated public var proximityState: Bool { false }
    nonisolated public var isProximityMonitoringEnabled: Bool {
        get { false }
        set { _ = newValue }
    }

    /// KVC setter used only by UIDevice+FeatureSupport.ows_setOrientation's
    /// programmatic-rotation hack (`setValue(_:forKey:"orientation")`). On Apple
    /// this resolves to NSObject's Objective-C KVC; swift-corelibs-foundation's
    /// NSObject has no KVC ("value of type 'UIDevice' has no member 'setValue'"),
    /// so this inert stand-in lets SSK compile. Programmatic device rotation is
    /// meaningless on QuillOS (the GTK/Qt window manager owns orientation), so it
    /// is a no-op. Linux-only: on macOS the real NSObject KVC is used (an
    /// unconditional method here would conflict with the @objc superclass one).
    public func setValue(_ value: Any?, forKey key: String) {
        _ = value
        _ = key
    }
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
    nonisolated(unsafe) public var isOn: Bool = false
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
    let lines = width > 0 ? CGFloat(ceil(Double(singleLineWidth / width))) : 1
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

#if canImport(AppKit) && !os(Linux)
// On macOS, NSEvent.ModifierFlags is the analogue.
public typealias UIKeyModifierFlags = NSEvent.ModifierFlags
#endif

#endif // !os(iOS)
