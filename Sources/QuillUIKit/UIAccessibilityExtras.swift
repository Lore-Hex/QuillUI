// QuillUIKit · UIAccessibility
// ============================
// The UIAccessibility namespace (assistive-technology status, notification
// posting, coordinate conversion), the UIAccessibilityTraits option set, and
// UIColor.accessibilityName for platforms without Apple's UIKit. The stored
// per-element accessibility properties (accessibilityLabel & co.) live in the
// class bodies in QuillUIKit.swift — subclasses override them, and overrides
// need class-body members; everything here is the support surface around
// them.
//
// HONEST LINUX SEMANTICS: there is no assistive-technology bridge (no
// VoiceOver, no AT-SPI wiring yet), so the status flags report "feature
// off" — upstream's standard-path branches are the ones that run (e.g.
// SignalUI's blur effects stay ON because isReduceTransparencyEnabled is
// false) — and post(notification:argument:) has no receiver. The traits and
// element properties are faithful STATE for a future AT-SPI bridge to read.

// Foundation imported directly (not just via QuillFoundation's re-export) so
// the `Foundation.Notification.Name` qualifications below — needed because
// the nested UIAccessibility.Notification shadows Foundation's inside the
// namespace — resolve. Same pattern as UIGeometryExtras.swift.
import Foundation
import QuillFoundation

#if !os(iOS)

// MARK: - UIAccessibilityTraits

/// How an element behaves for assistive technologies. Apple's raw values
/// (UIAccessibilityTraits is a UInt64 option set in the ObjC headers), kept
/// exactly so combined/persisted values stay stable. Signal inserts .button
/// (CVCapsuleLabel) and uses .adjustable (AttachmentApproval's media-quality
/// control).
public struct UIAccessibilityTraits: OptionSet, Sendable {
    public var rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let none = UIAccessibilityTraits([])
    public static let button = UIAccessibilityTraits(rawValue: 1 << 0)
    public static let link = UIAccessibilityTraits(rawValue: 1 << 1)
    public static let image = UIAccessibilityTraits(rawValue: 1 << 2)
    public static let selected = UIAccessibilityTraits(rawValue: 1 << 3)
    public static let playsSound = UIAccessibilityTraits(rawValue: 1 << 4)
    public static let keyboardKey = UIAccessibilityTraits(rawValue: 1 << 5)
    public static let staticText = UIAccessibilityTraits(rawValue: 1 << 6)
    public static let summaryElement = UIAccessibilityTraits(rawValue: 1 << 7)
    public static let notEnabled = UIAccessibilityTraits(rawValue: 1 << 8)
    public static let updatesFrequently = UIAccessibilityTraits(rawValue: 1 << 9)
    public static let searchField = UIAccessibilityTraits(rawValue: 1 << 10)
    public static let startsMediaSession = UIAccessibilityTraits(rawValue: 1 << 11)
    public static let adjustable = UIAccessibilityTraits(rawValue: 1 << 12)
    public static let allowsDirectInteraction = UIAccessibilityTraits(rawValue: 1 << 13)
    public static let causesPageTurn = UIAccessibilityTraits(rawValue: 1 << 14)
    public static let tabBar = UIAccessibilityTraits(rawValue: 1 << 15)
    public static let header = UIAccessibilityTraits(rawValue: 1 << 16)
}

// MARK: - UIAccessibility

/// Caseless-enum namespace, the same shape the UIKit Swift overlay uses.
/// Statics are nonisolated (they are on Apple too) so both @MainActor view
/// code and plain helpers (ConversationStyle's static bubble math) can read
/// them.
public enum UIAccessibility {

    // Assistive-technology / system-setting status. All report "off" — see
    // the file header. Get-only computed vars (not lets) to match Apple's
    // declarations and to leave room for a real settings bridge later.
    public static var isVoiceOverRunning: Bool { false }
    public static var isReduceMotionEnabled: Bool { false }
    public static var isReduceTransparencyEnabled: Bool { false }
    public static var isBoldTextEnabled: Bool { false }
    public static var isDarkerSystemColorsEnabled: Bool { false }

    /// UIAccessibilityNotifications (uint32_t in the ObjC headers), Apple's
    /// raw values.
    public struct Notification: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let screenChanged = Notification(rawValue: 1000)
        public static let layoutChanged = Notification(rawValue: 1001)
        public static let announcement = Notification(rawValue: 1008)
        public static let pageScrolled = Notification(rawValue: 1009)
    }

    /// No-op: there is no assistive technology to receive the notification
    /// on Linux (announcements included).
    public static func post(notification: Notification, argument: Any?) {
        _ = notification
        _ = argument
    }

    // NSNotification names observers subscribe to (SpoilerRenderer watches
    // reduceTransparency). Nothing posts them on Linux yet — a settings
    // bridge would. Strings are UIKit's constant names.
    public static let announcementDidFinishNotification =
        Foundation.Notification.Name("UIAccessibilityAnnouncementDidFinishNotification")
    public static let voiceOverStatusDidChangeNotification =
        Foundation.Notification.Name("UIAccessibilityVoiceOverStatusDidChangeNotification")
    public static let reduceMotionStatusDidChangeNotification =
        Foundation.Notification.Name("UIAccessibilityReduceMotionStatusDidChangeNotification")
    public static let reduceTransparencyStatusDidChangeNotification =
        Foundation.Notification.Name("UIAccessibilityReduceTransparencyStatusDidChangeNotification")

    /// Apple maps the rect from the view's coordinate space into screen
    /// coordinates. The shim's geometry (UIViewGeometry.swift) treats the
    /// view tree's root as the screen origin, so converting to nil (root)
    /// is the same mapping. @MainActor because it reads view geometry.
    @MainActor public static func convertToScreenCoordinates(_ rect: CGRect, in view: UIView) -> CGRect {
        view.convert(rect, to: nil)
    }
}

// MARK: - UIColor.accessibilityName

#if os(Linux)
// Linux-only: UIColor is RSColor (QuillFoundation) with public RGBA storage;
// on macOS UIColor aliases real NSColor, which has no such member to match.
public extension UIColor {
    /// Apple's UIColor.accessibilityName: a human-readable color name for
    /// VoiceOver (Signal labels chat-color swatches with it). The shim
    /// derives a coarse English name from the stored RGBA — a grayscale
    /// ladder, then hue buckets. Deterministic and honest, though Apple's
    /// localized vocabulary is richer.
    var accessibilityName: String {
        if _alpha == 0 { return "clear" }
        let maxC = max(_red, _green, _blue)
        let minC = min(_red, _green, _blue)
        let delta = maxC - minC
        if delta < 0.08 { // achromatic
            switch maxC {
            case ..<0.15: return "black"
            case ..<0.4: return "dark gray"
            case ..<0.7: return "gray"
            case ..<0.92: return "light gray"
            default: return "white"
            }
        }
        // Standard RGB→hue (degrees).
        var hue: CGFloat
        if maxC == _red {
            hue = (_green - _blue) / delta
        } else if maxC == _green {
            hue = 2 + (_blue - _red) / delta
        } else {
            hue = 4 + (_red - _green) / delta
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        switch hue {
        case ..<15: return "red"
        case ..<45: return "orange"
        case ..<70: return "yellow"
        case ..<160: return "green"
        case ..<200: return "cyan"
        case ..<255: return "blue"
        case ..<290: return "purple"
        case ..<335: return "pink"
        default: return "red"
        }
    }
}
#endif // os(Linux)

#endif // !os(iOS)
