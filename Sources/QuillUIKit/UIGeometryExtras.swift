// UIGeometryExtras.swift
// ======================
// QuillUIKit — geometry/orientation/misc UIKit types for the SignalUI build:
//
//   - UIRectCorner (corner-mask OptionSet, raw values match Apple's)
//   - UIInterfaceOrientation + UIInterfaceOrientationMask (the Int enum and
//     its OptionSet companion; mask bits are `1 << orientation.rawValue`.
//     The mask moved here from UIKitShim/UIKit.swift so the UIViewController
//     class body can declare `supportedInterfaceOrientations`)
//   - UIUserInterfaceSizeClass + the UITraitCollection size-class surface
//     (UITraitCollection's class body is declared in QuillUIKit.swift —
//     another owner — so the size-class members are layered here as an
//     extension over a side table, the UIScrollViewExtras pattern)
//   - UIView.AnimationCurve + UITimingCurveProvider/UICubicTimingParameters/
//     UISpringTimingParameters + UIViewAnimatingState/Position
//   - UIViewPropertyAnimator (synchronous model — see its doc comment)
//   - UISlider (UIControl subclass; stored model only, no renderer)
//
// Honest Linux semantics, same MODEL-not-engine rules as the rest of the
// module: values are faithfully stored with Apple's defaults and shapes,
// but there is no animation backend (animator blocks run synchronously)
// and no compositor (nothing draws the slider).

import Foundation
import QuillFoundation

#if !os(iOS)

// MARK: - UIRectCorner

/// Which corners of a rectangle to round (UIBezierPath / maskedCorners
/// call sites). Raw values match Apple's; `allCorners` is `~0`, exactly
/// like UIKit's UIRectCornerAllCorners — not just the union of the four
/// named corners.
public struct UIRectCorner: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let topLeft = UIRectCorner(rawValue: 1 << 0)
    public static let topRight = UIRectCorner(rawValue: 1 << 1)
    public static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    public static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    public static let allCorners = UIRectCorner(rawValue: ~0)
}

// MARK: - UIInterfaceOrientation

/// Interface (not device) orientation. Raw values match Apple's — note the
/// deliberate UIKit swap: interface landscapeLeft (4) is *device*
/// landscapeRight, and vice versa. The companion UIInterfaceOrientationMask
/// below has bits that are `1 << rawValue` of these cases.
public enum UIInterfaceOrientation: Int, Sendable {
    case unknown = 0
    case portrait = 1
    case portraitUpsideDown = 2
    case landscapeRight = 3
    case landscapeLeft = 4

    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }
    public var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }
}

/// Orientation set. Bit values match Apple's (`1 << orientation.rawValue`).
/// Moved here from the UIKit shim module (which depends on this one and
/// re-exports it, so `import UIKit` consumers still resolve it): the
/// UIViewController class body in QuillUIKit.swift needs the type for
/// Apple's `open var supportedInterfaceOrientations`, which upstream
/// (OWSNavigationController & co.) overrides.
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

// MARK: - UIUserInterfaceSizeClass

/// Horizontal/vertical size classes. Raw values match Apple's.
public enum UIUserInterfaceSizeClass: Int, Sendable {
    case unspecified = 0
    case compact = 1
    case regular = 2
}

// MARK: - UITraitCollection size classes

/// Side-table storage for the size-class traits: UITraitCollection's class
/// body lives in QuillUIKit.swift (another owner) and extensions cannot add
/// stored properties, so explicitly-constructed size classes live here —
/// the UIScrollViewExtras side-table pattern. A weak `owner` backref guards
/// every read against ObjectIdentifier address reuse, and dead entries are
/// swept on write. UITraitCollection is not MainActor-bound on Apple, so the
/// table is lock-protected rather than actor-isolated.
private final class QuillTraitSizeClassStore: @unchecked Sendable {
    static let shared = QuillTraitSizeClassStore()

    private struct Entry {
        weak var owner: UITraitCollection?
        var horizontal: UIUserInterfaceSizeClass
        var vertical: UIUserInterfaceSizeClass
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]

    func sizeClasses(for traits: UITraitCollection) -> (horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[ObjectIdentifier(traits)], entry.owner === traits else { return nil }
        return (entry.horizontal, entry.vertical)
    }

    func set(horizontal: UIUserInterfaceSizeClass, vertical: UIUserInterfaceSizeClass, for traits: UITraitCollection) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { $0.value.owner != nil }
        entries[ObjectIdentifier(traits)] = Entry(owner: traits, horizontal: horizontal, vertical: vertical)
    }
}

extension UITraitCollection {
    /// DELIBERATE DEVIATION from Apple's default: a plain UITraitCollection()
    /// reports `.regular` (not `.unspecified`) for both size classes — every
    /// Linux/desktop window is a regular-by-regular environment, and Signal's
    /// layout code branches on `== .compact`, so the desktop answer falls out
    /// of the default. Explicit constructions below are stored faithfully.
    public var horizontalSizeClass: UIUserInterfaceSizeClass {
        QuillTraitSizeClassStore.shared.sizeClasses(for: self)?.horizontal ?? .regular
    }

    public var verticalSizeClass: UIUserInterfaceSizeClass {
        QuillTraitSizeClassStore.shared.sizeClasses(for: self)?.vertical ?? .regular
    }

    /// The unset axis defaults to `.regular` (Apple: `.unspecified`) — same
    /// desktop-default rationale as the computed properties above.
    public convenience init(horizontalSizeClass: UIUserInterfaceSizeClass) {
        self.init()
        QuillTraitSizeClassStore.shared.set(horizontal: horizontalSizeClass, vertical: .regular, for: self)
    }

    public convenience init(verticalSizeClass: UIUserInterfaceSizeClass) {
        self.init()
        QuillTraitSizeClassStore.shared.set(horizontal: .regular, vertical: verticalSizeClass, for: self)
    }
}

// MARK: - UIView.AnimationCurve

extension UIView {
    /// Timing-curve names. Raw values match Apple's UIViewAnimationCurve.
    /// Pure model on Linux: nothing interpolates, so the curve is recorded
    /// but never sampled.
    public enum AnimationCurve: Int, Sendable {
        case easeInOut = 0
        case easeIn = 1
        case easeOut = 2
        case linear = 3
    }
}

// MARK: - Timing curve providers

/// Apple's protocol also requires NSCoding & NSCopying; nothing on Linux
/// archives or copies timing parameters, so only the identity requirement
/// is kept.
public protocol UITimingCurveProvider: AnyObject {}

/// Cubic Bézier timing. Faithful STATE only: the curve/control points are
/// stored for any future animation backend, never sampled today.
public final class UICubicTimingParameters: NSObject, UITimingCurveProvider {
    public let animationCurve: UIView.AnimationCurve
    public let controlPoint1: CGPoint
    public let controlPoint2: CGPoint

    public override init() {
        self.animationCurve = .easeInOut
        self.controlPoint1 = .zero
        self.controlPoint2 = .zero
        super.init()
    }

    public init(animationCurve curve: UIView.AnimationCurve) {
        self.animationCurve = curve
        self.controlPoint1 = .zero
        self.controlPoint2 = .zero
        super.init()
    }

    public init(controlPoint1 point1: CGPoint, controlPoint2 point2: CGPoint) {
        self.animationCurve = .easeInOut
        self.controlPoint1 = point1
        self.controlPoint2 = point2
        super.init()
    }
}

/// Spring timing. Apple's public surface exposes only `initialVelocity`;
/// the spring constants are stored (internal) for honesty but, like the
/// cubic points, nothing integrates them on Linux.
public final class UISpringTimingParameters: NSObject, UITimingCurveProvider {
    public let initialVelocity: CGVector
    let dampingRatio: CGFloat
    let mass: CGFloat
    let stiffness: CGFloat
    let damping: CGFloat

    public override init() {
        self.initialVelocity = .zero
        self.dampingRatio = 1
        self.mass = 0
        self.stiffness = 0
        self.damping = 0
        super.init()
    }

    public convenience init(dampingRatio ratio: CGFloat) {
        self.init(dampingRatio: ratio, initialVelocity: .zero)
    }

    public init(dampingRatio ratio: CGFloat, initialVelocity velocity: CGVector) {
        self.initialVelocity = velocity
        self.dampingRatio = ratio
        self.mass = 0
        self.stiffness = 0
        self.damping = 0
        super.init()
    }

    public init(mass: CGFloat, stiffness: CGFloat, damping: CGFloat, initialVelocity velocity: CGVector) {
        self.initialVelocity = velocity
        self.dampingRatio = 1
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        super.init()
    }
}

// MARK: - UIViewAnimating state

/// Raw values match Apple's.
public enum UIViewAnimatingState: Int, Sendable {
    case inactive = 0
    case active = 1
    case stopped = 2
}

/// Raw values match Apple's.
public enum UIViewAnimatingPosition: Int, Sendable {
    case end = 0
    case start = 1
    case current = 2
}

// MARK: - UIViewPropertyAnimator

/// HONEST SYNCHRONOUS MODEL — there is no animation backend on Linux.
/// Duration, timing parameters, animation blocks, and completion blocks are
/// all faithfully stored with Apple's API shapes, but `startAnimation()`
/// runs every pending animation block immediately on the calling (main)
/// thread, jumps `fractionComplete` to its final value, and fires the
/// completion blocks synchronously at `.end` (`.start` when `isReversed`).
/// `startAnimation(afterDelay:)` ignores the delay; `continueAnimation` is
/// `startAnimation()`. Animations therefore always land in their final
/// state — the same "complete instantly" contract as UIView.animate in
/// QuillUIKit.swift — and interactive scrubbing via `fractionComplete` is
/// recorded but never rendered.
@MainActor open class UIViewPropertyAnimator: NSObject {
    public let duration: TimeInterval
    public private(set) var timingParameters: UITimingCurveProvider?
    open private(set) var state: UIViewAnimatingState = .inactive
    open private(set) var isRunning: Bool = false
    open var isReversed: Bool = false
    open var fractionComplete: CGFloat = 0
    open var isInterruptible: Bool = true
    open var isUserInteractionEnabled: Bool = true
    open var isManualHitTestingEnabled: Bool = false
    open var scrubsLinearly: Bool = true
    open var pausesOnCompletion: Bool = false

    private var animations: [() -> Void] = []
    private var completions: [(UIViewAnimatingPosition) -> Void] = []

    public override init() {
        self.duration = 0
        super.init()
    }

    public init(duration: TimeInterval, timingParameters parameters: UITimingCurveProvider) {
        self.duration = duration
        self.timingParameters = parameters
        super.init()
    }

    public convenience init(duration: TimeInterval, curve: UIView.AnimationCurve, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UICubicTimingParameters(animationCurve: curve))
        if let animations { addAnimations(animations) }
    }

    public convenience init(duration: TimeInterval, controlPoint1 point1: CGPoint, controlPoint2 point2: CGPoint, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UICubicTimingParameters(controlPoint1: point1, controlPoint2: point2))
        if let animations { addAnimations(animations) }
    }

    public convenience init(duration: TimeInterval, dampingRatio ratio: CGFloat, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UISpringTimingParameters(dampingRatio: ratio))
        if let animations { addAnimations(animations) }
    }

    open func addAnimations(_ animation: @escaping () -> Void) {
        animations.append(animation)
    }

    /// The delay factor is ignored (synchronous model); the block is queued
    /// like any other.
    open func addAnimations(_ animation: @escaping () -> Void, delayFactor: CGFloat) {
        animations.append(animation)
    }

    open func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) {
        completions.append(completion)
    }

    open func startAnimation() {
        guard state != .stopped else { return }
        state = .active
        isRunning = true
        let pendingAnimations = animations
        animations.removeAll()
        for block in pendingAnimations { block() }
        isRunning = false
        fractionComplete = isReversed ? 0 : 1
        // Apple returns a finished animator to .inactive and discharges its
        // completion blocks; same here, just synchronously.
        state = .inactive
        let position: UIViewAnimatingPosition = isReversed ? .start : .end
        let pendingCompletions = completions
        completions.removeAll()
        for completion in pendingCompletions { completion(position) }
    }

    /// The delay is not honored — see the class doc comment.
    open func startAnimation(afterDelay delay: TimeInterval) {
        startAnimation()
    }

    /// Activates without running (Apple's "pause an inactive animator"
    /// semantic). With no clock there is nothing to actually halt.
    open func pauseAnimation() {
        guard state != .stopped else { return }
        state = .active
        isRunning = false
    }

    open func stopAnimation(_ withoutFinishing: Bool) {
        isRunning = false
        if withoutFinishing {
            state = .inactive
            animations.removeAll()
            completions.removeAll()
        } else {
            state = .stopped
        }
    }

    /// Apple requires the animator to be `.stopped` first; accepted from any
    /// state here (the stricter precondition would only turn upstream's
    /// correct call orders into crashes).
    open func finishAnimation(at finalPosition: UIViewAnimatingPosition) {
        animations.removeAll()
        isRunning = false
        state = .inactive
        switch finalPosition {
        case .end: fractionComplete = 1
        case .start: fractionComplete = 0
        case .current: break
        }
        let pendingCompletions = completions
        completions.removeAll()
        for completion in pendingCompletions { completion(finalPosition) }
    }

    /// Synchronous model: equivalent to `startAnimation()`. The new timing
    /// parameters and duration factor have nothing to retime.
    open func continueAnimation(withTimingParameters parameters: UITimingCurveProvider?, durationFactor: CGFloat) {
        startAnimation()
    }

    /// Returns an animator that has ALREADY completed (synchronous model):
    /// the animations and completion run before this returns. Apple's
    /// signature returns `Self`; this returns the concrete class to keep the
    /// initializer non-required — call sites bind it identically.
    open class func runningPropertyAnimator(
        withDuration duration: TimeInterval,
        delay: TimeInterval,
        options: UIView.AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((UIViewAnimatingPosition) -> Void)? = nil
    ) -> UIViewPropertyAnimator {
        // Curve options live in bits 16–17 (see UIView.AnimationOptions);
        // .curveLinear is both bits, so test it before the single-bit curves.
        let curve: UIView.AnimationCurve
        if options.contains(.curveLinear) {
            curve = .linear
        } else if options.contains(.curveEaseOut) {
            curve = .easeOut
        } else if options.contains(.curveEaseIn) {
            curve = .easeIn
        } else {
            curve = .easeInOut
        }
        let animator = UIViewPropertyAnimator(duration: duration, curve: curve, animations: animations)
        if let completion { animator.addCompletion(completion) }
        animator.startAnimation(afterDelay: delay)
        return animator
    }
}

// MARK: - UISlider

/// Stored-model slider. Values, ranges, tints, and per-state images are
/// faithfully recorded; UIControl's target-action table dispatches
/// `.valueChanged` if anything ever calls `sendActions(for:)`, but with no
/// event backend nothing tracks touches, so the control never moves itself.
/// Programmatic `value`/`setValue` changes do NOT fire `.valueChanged`,
/// exactly like Apple.
@MainActor open class UISlider: UIControl {
    open var value: Float = 0
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
    open var minimumValueImage: UIImage?
    open var maximumValueImage: UIImage?
    open var isContinuous: Bool = true
    open var minimumTrackTintColor: UIColor?
    open var maximumTrackTintColor: UIColor?
    open var thumbTintColor: UIColor?
    // isTracking is inherited from UIControl (added to the UIControl class
    // body); UISlider no longer redeclares it — matching Apple, where
    // isTracking is a UIControl property UISlider inherits.

    private var thumbImages: [UInt: UIImage] = [:]
    private var minimumTrackImages: [UInt: UIImage] = [:]
    private var maximumTrackImages: [UInt: UIImage] = [:]

    /// `animated` is meaningless without an animation backend; the value is
    /// set immediately (which is also where Apple's animated set lands).
    open func setValue(_ value: Float, animated: Bool) {
        self.value = value
    }

    open func setThumbImage(_ image: UIImage?, for state: UIControl.State) {
        if let image {
            thumbImages[state.rawValue] = image
        } else {
            thumbImages.removeValue(forKey: state.rawValue)
        }
    }

    open func thumbImage(for state: UIControl.State) -> UIImage? {
        thumbImages[state.rawValue]
    }

    open var currentThumbImage: UIImage? {
        thumbImages[state.rawValue] ?? thumbImages[UIControl.State.normal.rawValue]
    }

    open func setMinimumTrackImage(_ image: UIImage?, for state: UIControl.State) {
        if let image {
            minimumTrackImages[state.rawValue] = image
        } else {
            minimumTrackImages.removeValue(forKey: state.rawValue)
        }
    }

    open func minimumTrackImage(for state: UIControl.State) -> UIImage? {
        minimumTrackImages[state.rawValue]
    }

    open var currentMinimumTrackImage: UIImage? {
        minimumTrackImages[state.rawValue] ?? minimumTrackImages[UIControl.State.normal.rawValue]
    }

    open func setMaximumTrackImage(_ image: UIImage?, for state: UIControl.State) {
        if let image {
            maximumTrackImages[state.rawValue] = image
        } else {
            maximumTrackImages.removeValue(forKey: state.rawValue)
        }
    }

    open func maximumTrackImage(for state: UIControl.State) -> UIImage? {
        maximumTrackImages[state.rawValue]
    }

    open var currentMaximumTrackImage: UIImage? {
        maximumTrackImages[state.rawValue] ?? maximumTrackImages[UIControl.State.normal.rawValue]
    }

    /// Layout override points for subclasses (ImageEditorSliderView & co.).
    /// With no renderer the base answers are simple geometry: the track is
    /// the full bounds, and the thumb is a zero-size point positioned
    /// proportionally along the track.
    open func trackRect(forBounds bounds: CGRect) -> CGRect {
        bounds
    }

    open func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {
        let span = maximumValue - minimumValue
        let fraction = span > 0 ? CGFloat((value - minimumValue) / span) : 0
        return CGRect(x: rect.minX + fraction * rect.width, y: rect.midY, width: 0, height: 0)
    }
}

#endif // !os(iOS)
