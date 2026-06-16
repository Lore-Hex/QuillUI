// QuillUIKit · UIVisualEffect family
// ==================================
// UIVisualEffect / UIBlurEffect / UIVibrancyEffect / UIGlassEffect and
// UIVisualEffectView for platforms without Apple's UIKit. Upstream UIKit
// code (SignalUI's OWSNavigationBar, RoundMediaButton, CircleBlurView,
// Theme.barBlurEffect, …) constructs these effects, swaps them in and out
// of UIVisualEffectView.effect, and parents content under contentView.
//
// Honest Linux semantics: every effect is a CONFIG RECORD, not a renderer.
// There is no compositor pass that blurs, vibrancy-tints, or glass-renders —
// the stored style/tint/interactivity is exactly what the caller set, kept
// for a future native render pass to consume. What IS functional is
// UIVisualEffectView's documented structure: `contentView` is a real subview
// created at init (content added to it participates in the ordinary view
// hierarchy), and `effect` is swappable at any time, including to nil
// (Signal's blur-on/blur-off paths assign both ways).
//
// UIVisualEffectView's declaration lives here (moved from QuillUIKit.swift's
// one-line stub): subclassers (SignalUI's CircleBlurView) override
// `init(effect:)` and call up through it, which requires an `open` class
// whose `init(effect:)` is a DESIGNATED initializer in the class body —
// no extension can provide that.

import QuillFoundation
import QuillKit

#if !os(iOS)

// MARK: - UIVisualEffect

/// Abstract base of the effect family. NSObject-rooted like UIKit's, so
/// enums with effect payloads (OWSNavigationBar.BackgroundStyle) get their
/// synthesized Equatable through NSObject identity.
@MainActor open class UIVisualEffect: NSObject {
    public override init() { super.init() }
}

// MARK: - UIBlurEffect

@MainActor open class UIBlurEffect: UIVisualEffect {

    /// Raw values match UIKit's ObjC enum (3 is tvOS-only `extraDark`,
    /// omitted on iOS and here).
    public enum Style: Int, Sendable {
        case extraLight = 0
        case light = 1
        case dark = 2
        case regular = 4
        case prominent = 5
        case systemUltraThinMaterial = 6
        case systemThinMaterial = 7
        case systemMaterial = 8
        case systemThickMaterial = 9
        case systemChromeMaterial = 10
        case systemUltraThinMaterialLight = 11
        case systemThinMaterialLight = 12
        case systemMaterialLight = 13
        case systemThickMaterialLight = 14
        case systemChromeMaterialLight = 15
        case systemUltraThinMaterialDark = 16
        case systemThinMaterialDark = 17
        case systemMaterialDark = 18
        case systemThickMaterialDark = 19
        case systemChromeMaterialDark = 20
    }

    /// Recorded but inert: nothing blurs on Linux yet.
    public let style: Style

    public init(style: Style) {
        self.style = style
        super.init()
    }
}

// MARK: - UIVibrancyEffect

/// UIVibrancyEffectStyle (iOS 13+). Raw values match UIKit's ObjC enum.
public enum UIVibrancyEffectStyle: Int, Sendable {
    case label = 0
    case secondaryLabel = 1
    case tertiaryLabel = 2
    case quaternaryLabel = 3
    case fill = 4
    case secondaryFill = 5
    case tertiaryFill = 6
    case separator = 7
}

@MainActor open class UIVibrancyEffect: UIVisualEffect {

    /// The blur this vibrancy rides on. Real UIKit keeps these private;
    /// exposed here so a future render pass (or a test) can read the config.
    public let blurEffect: UIBlurEffect
    public let vibrancyStyle: UIVibrancyEffectStyle?

    public init(blurEffect: UIBlurEffect) {
        self.blurEffect = blurEffect
        self.vibrancyStyle = nil
        super.init()
    }

    public init(blurEffect: UIBlurEffect, style: UIVibrancyEffectStyle) {
        self.blurEffect = blurEffect
        self.vibrancyStyle = style
        super.init()
    }
}

// MARK: - UIGlassEffect

/// iOS 26 "Liquid Glass". Signal builds these behind `if #available(iOS 26…)`
/// guards; on Linux availability checks pass, so the type must exist and
/// hold its config like the others.
@MainActor open class UIGlassEffect: UIVisualEffect {

    public enum Style: Int, Sendable {
        case regular = 0
        case clear = 1
    }

    public let style: Style

    /// Recorded but inert: no glass reacts to touches on Linux.
    open var isInteractive: Bool = false

    /// Recorded but inert: nothing tints on Linux.
    open var tintColor: UIColor?

    public override init() {
        self.style = .regular
        super.init()
    }

    public init(style: Style) {
        self.style = style
        super.init()
    }
}

// MARK: - UIVisualEffectView

@MainActor open class UIVisualEffectView: UIView {

    /// Swappable at any time, including to nil (Signal's blur-on/off paths
    /// assign both ways). Recorded but inert: nothing renders the effect.
    open var effect: UIVisualEffect?

    private let _contentView = UIView()

    /// Real subview, created at init, exactly like UIKit's structure:
    /// content the caller parents under it participates in the ordinary
    /// view hierarchy (hit-testing, traversal) even though the effect
    /// itself renders nothing.
    open var contentView: UIView { _contentView }

    public init(effect: UIVisualEffect?) {
        self.effect = effect
        super.init(frame: .zero)
        addSubview(_contentView)
    }

    public convenience init() {
        self.init(effect: nil)
    }

    // Own designated init suppresses inheritance of UIView's
    // required init?(coder:); restate it.
    public required init?(coder: NSCoder) {
        self.effect = nil
        super.init(coder: coder)
        addSubview(_contentView)
    }
}

#endif // !os(iOS)
