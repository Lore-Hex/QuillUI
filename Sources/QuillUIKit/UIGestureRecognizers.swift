//===----------------------------------------------------------------------===//
//
//  UIGestureRecognizers.swift
//  QuillUIKit — UIKit-shaped gesture recognizers for Linux
//
//  The UIGestureRecognizer family with Apple-faithful API surface:
//  the base class (state machine, target/action registration, view
//  attachment, failure requirements, the UIGestureRecognizerSubclass
//  policy hooks), the concrete tap / long-press / pan / pinch
//  recognizers, the delegate protocol, and the UIView attachment
//  extension (addGestureRecognizer / removeGestureRecognizer /
//  gestureRecognizers).
//
//  Honest Linux semantics:
//    - There is no event backend yet (no touches, no hit-testing, no
//      compositor input). Recognizers are a faithful MODEL: every
//      configuration property is stored with Apple's defaults, targets
//      and failure requirements are recorded, and views genuinely own
//      their attached recognizers — but nothing ever transitions a
//      recognizer out of `.possible` on its own, and no action fires.
//    - Action tokens are the repo's opaque `Selector`s (the
//      source-lowering pass rewrites `#selector(...)` into
//      `Selector("name")` and synthesizes QuillSelectorDispatching
//      conformances). When an event backend lands, dispatch goes
//      through `quillPerform`, exactly as CADisplayLink already does.
//    - The `touchesBegan(_:with:)` family from UIGestureRecognizerSubclass
//      is NOT declared yet: it needs UITouch / UIEvent, which the shims
//      don't define. (SignalUI's PermissiveGestureRecognizer,
//      DirectionalPanGestureRecognizer, and
//      ImageEditorPinchGestureRecognizer override those methods, so
//      their files stay red until UITouch/UIEvent + the touches hooks
//      arrive — they must be added to the class body here, since `open`
//      members can't be introduced in extensions.)
//
//===----------------------------------------------------------------------===//

import QuillFoundation

#if !os(iOS)

// MARK: - UIGestureRecognizer

/// The base class for concrete gesture recognizers.
///
/// A recognizer is attached to (at most) one view via
/// `UIView.addGestureRecognizer(_:)` and reports its progress through
/// `state`. On Linux the recognition machinery is inert until an event
/// backend exists — see the file header for exactly what is and isn't real.
@MainActor open class UIGestureRecognizer: NSObject {

    /// The current state of the recognition state machine.
    public enum State: Int, Sendable {
        case possible
        case began
        case changed
        case ended
        case cancelled
        case failed

        /// Apple's alias for `.ended`: discrete gestures (taps) read
        /// `.recognized`. A static member, as on Apple, so upstream
        /// `state == .recognized` comparisons compile. (It is not a `case`,
        /// so it can't appear as a switch pattern — Apple's can't either.)
        public static var recognized: State { .ended }
    }

    // MARK: State

    /// The recognizer's current state. Apple exposes the setter to
    /// subclasses via the UIGestureRecognizerSubclass category; here it is
    /// simply settable, which is what upstream subclasses (e.g. Signal's
    /// DirectionalPanGestureRecognizer setting `.cancelled`) need.
    open var state: State = .possible

    /// Whether the recognizer participates in recognition. On Apple,
    /// disabling an actively-recognizing gesture transitions it to
    /// `.cancelled`; with no recognition running on Linux, this is plain
    /// stored configuration.
    open var isEnabled: Bool = true

    /// The view the recognizer is attached to, set by
    /// `UIView.addGestureRecognizer(_:)` below. Weak, mirroring Apple's
    /// non-owning backref (the VIEW retains its recognizers, not vice
    /// versa).
    public fileprivate(set) weak var view: UIView?

    /// The delegate consulted (on Apple) at recognition-gating moments.
    /// Stored faithfully; nothing consults it until an event backend exists.
    open weak var delegate: UIGestureRecognizerDelegate?

    /// Whether recognized touches are withheld from the view's normal
    /// touch handling. Stored configuration only, like everything else here.
    open var cancelsTouchesInView: Bool = true

    // MARK: Target / action

    /// One registered target/action pair. The target is weak: UIKit does
    /// not retain gesture targets (which is why the ubiquitous
    /// `UITapGestureRecognizer(target: self, ...)` pattern doesn't leak),
    /// and neither do we.
    private struct TargetAction {
        weak var target: AnyObject?
        let action: Selector
    }

    private var targetActions: [TargetAction] = []

    /// The live registered target/action pairs (zeroed targets filtered
    /// out). `quill`-prefixed cross-module introspection for the future
    /// event backend, in the style of `NSLayoutConstraint.quillActive`:
    /// dispatch will resolve each action through
    /// `QuillSelectorDispatching.quillPerform`, as CADisplayLink does.
    public var quillTargetActions: [(target: AnyObject, action: Selector)] {
        targetActions.compactMap { pair in
            pair.target.map { (target: $0, action: pair.action) }
        }
    }

    // MARK: Init

    /// Creates a gesture recognizer with one target/action pair.
    ///
    /// `action` is one of the repo's opaque `Selector` tokens on Linux
    /// (e.g. `Selector("didTapBackdrop(_:)")` produced by the
    /// source-lowering pass from upstream `#selector` call sites).
    public init(target: Any?, action: Selector?) {
        super.init()
        if let target = target, let action = action {
            addTarget(target, action: action)
        }
    }

    public convenience override init() {
        self.init(target: nil, action: nil)
    }

    /// Adds a target/action pair. Duplicate pairs are ignored, as on Apple.
    open func addTarget(_ target: Any, action: Selector) {
        let object = target as AnyObject
        let alreadyRegistered = targetActions.contains {
            $0.target === object && $0.action == action
        }
        guard !alreadyRegistered else { return }
        targetActions.append(TargetAction(target: object, action: action))
    }

    /// Removes matching target/action pairs. `nil` is a wildcard for either
    /// position, matching Apple: `removeTarget(nil, action: nil)` clears
    /// every pair.
    open func removeTarget(_ target: Any?, action: Selector?) {
        let object = target.map { $0 as AnyObject }
        targetActions.removeAll { pair in
            let targetMatches = object == nil || pair.target === object!
            let actionMatches = action == nil || pair.action == action!
            return targetMatches && actionMatches
        }
    }

    // MARK: Touch geometry

    /// The number of touches involved in the gesture. No event backend on
    /// Linux means no live touches, so this is always 0.
    open var numberOfTouches: Int { 0 }

    /// The centroid of the involved touches in `view`'s coordinate system.
    /// With no event backend there are never touches to average, so this
    /// returns `.zero`. Upstream only consults it inside action handlers
    /// (e.g. ActionSheetController.didTapBackdrop), which cannot run until
    /// gestures can actually fire.
    open func location(in view: UIView?) -> CGPoint {
        _ = view
        return .zero
    }

    /// The location of a specific touch. Same honesty as `location(in:)`:
    /// no touches exist, so `.zero`.
    open func location(ofTouch touchIndex: Int, in view: UIView?) -> CGPoint {
        _ = touchIndex
        _ = view
        return .zero
    }

    // MARK: Inter-recognizer relationships

    private struct WeakRecognizer {
        weak var value: UIGestureRecognizer?
    }

    /// Recognizers this one is required to wait on, recorded by
    /// `require(toFail:)`. Weak — Apple does not retain the other
    /// recognizer. Stored so a future event backend can honor the ordering;
    /// nothing reads it yet.
    private var failureRequirements: [WeakRecognizer] = []

    /// Creates a dependency: this recognizer waits for
    /// `otherGestureRecognizer` to fail before it can begin (e.g. Signal's
    /// single-tap deferring to double-tap in ImageEditorView).
    open func require(toFail otherGestureRecognizer: UIGestureRecognizer) {
        failureRequirements.append(WeakRecognizer(value: otherGestureRecognizer))
    }

    // MARK: Subclass hooks (UIGestureRecognizerSubclass surface)

    // These are the relationship-policy overrides from Apple's
    // UIGestureRecognizerSubclass category, with Apple's default returns.
    // Upstream subclasses override them (PermissiveGestureRecognizer
    // overrides all four). The touches* family that belongs alongside them
    // is deliberately absent — see the file header.

    /// Whether this recognizer is allowed to prevent another from
    /// recognizing. Apple's default: true.
    open func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = preventedGestureRecognizer
        return true
    }

    /// Whether another recognizer is allowed to prevent this one.
    /// Apple's default: true.
    open func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = preventingGestureRecognizer
        return true
    }

    /// Dynamic counterpart of `require(toFail:)`. Apple's default: false.
    open func shouldRequireFailure(of otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = otherGestureRecognizer
        return false
    }

    /// The mirror-image hook. Apple's default: false.
    open func shouldBeRequiredToFail(by otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        _ = otherGestureRecognizer
        return false
    }

    /// Called (on Apple) when the recognition cycle completes, before the
    /// state returns to `.possible`. Subclasses override to clear
    /// per-gesture state; the base implementation does nothing.
    open func reset() {}
}

// MARK: - UIGestureRecognizerDelegate

/// Fine-grained gating of gesture recognition. All members are
/// "optional" in the Apple sense: declared as requirements and defaulted
/// below with Apple's default answers, so conformers implement only what
/// they care about (the UIScrollViewDelegate pattern used elsewhere in
/// this module).
///
/// The `gestureRecognizer(_:shouldReceive:)` members (UITouch / UIPress /
/// UIEvent flavors) are omitted until those types exist in the shims.
/// Upstream conformers that implement them still compile — an extra
/// method on a conforming type is harmless — it just isn't part of the
/// protocol contract yet.
public protocol UIGestureRecognizerDelegate: AnyObject {
    @MainActor func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool
}

public extension UIGestureRecognizerDelegate {
    @MainActor func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    @MainActor func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

// MARK: - Concrete recognizers

/// A discrete recognizer for single or multiple taps. Configuration is
/// faithfully stored (Apple defaults); recognition awaits an event backend.
open class UITapGestureRecognizer: UIGestureRecognizer {
    /// Taps required for recognition. Apple's default: 1.
    open var numberOfTapsRequired: Int = 1
    /// Fingers required per tap. Apple's default: 1.
    open var numberOfTouchesRequired: Int = 1
}

/// A continuous recognizer for press-and-hold gestures.
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    /// Seconds a touch must be held before the gesture begins.
    /// Apple's default: 0.5. (Signal's LinkingTextView reads this to tell
    /// text-interaction long-presses apart from its own.)
    open var minimumPressDuration: TimeInterval = 0.5
}

/// A continuous recognizer for dragging.
open class UIPanGestureRecognizer: UIGestureRecognizer {

    /// The accumulated translation. With no event backend this changes
    /// only via `setTranslation(_:in:)`; a future backend accumulates into
    /// the same storage. Tracked in a single coordinate space — the
    /// `in view:` parameters below are accepted for API fidelity but there
    /// is no live geometry to convert between yet.
    private var panTranslation: CGPoint = .zero

    /// The translation of the pan in `view`'s coordinate system.
    open func translation(in view: UIView?) -> CGPoint {
        _ = view
        return panTranslation
    }

    /// Overwrites the current translation. Apple lets clients re-zero this
    /// mid-gesture to consume movement incrementally; the reset is honored.
    open func setTranslation(_ translation: CGPoint, in view: UIView?) {
        _ = view
        panTranslation = translation
    }

    /// The velocity of the pan in points per second. No live touches, so
    /// always `.zero`.
    open func velocity(in view: UIView?) -> CGPoint {
        _ = view
        return .zero
    }
}

/// A continuous recognizer for two-finger pinching.
open class UIPinchGestureRecognizer: UIGestureRecognizer {
    /// The scale factor relative to the touches' initial span. Settable,
    /// as on Apple (clients re-zero it to 1 between increments).
    /// Apple's default: 1.
    open var scale: CGFloat = 1

    /// The pinch velocity in scale factor per second. Read-only on Apple;
    /// with no live touches it is always 0.
    open var velocity: CGFloat { 0 }
}

// MARK: - UIView gesture attachment

/// Side table mapping a view (by ObjectIdentifier) to its attached
/// recognizers. UIView (QuillUIKit.swift) knows nothing about gestures;
/// keeping the storage out-of-line here lets this file own the whole
/// gesture surface without touching the view class.
///
/// Retention parity with Apple: on Apple the VIEW retains its attached
/// recognizers (which is why upstream can write
/// `addGestureRecognizer(UITapGestureRecognizer(...))` without keeping a
/// reference). The table plays that retaining role. The cost of the
/// side-table design is lifetime precision: an entry for a deallocated
/// view lingers until the next attach (which sweeps entries whose
/// recognizers' weak `view` backrefs have all zeroed), and the getter
/// filters by `view === self` so a recycled heap address can never
/// inherit a dead view's recognizers.
@MainActor private var viewGestureRecognizers: [ObjectIdentifier: [UIGestureRecognizer]] = [:]

/// Drops side-table entries whose view has deallocated (every recognizer's
/// weak backref has zeroed) and empty leftovers. Called on each attach to
/// keep the table bounded by the number of live gesture-bearing views.
@MainActor private func pruneDeadViewEntries() {
    viewGestureRecognizers = viewGestureRecognizers.filter { _, recognizers in
        recognizers.contains { $0.view != nil }
    }
}

extension UIView {

    /// The gesture recognizers currently attached to the view, or nil if
    /// none were ever attached. (Apple declares this `open var`; extension
    /// members can't be `open`, so it is `public` — no upstream code
    /// overrides it.)
    public var gestureRecognizers: [UIGestureRecognizer]? {
        get {
            guard let stored = viewGestureRecognizers[ObjectIdentifier(self)] else { return nil }
            // Filter on read: see the side-table comment — this is the
            // address-reuse guard.
            return stored.filter { $0.view === self }
        }
        set {
            // Apple semantics: assignment replaces the entire set.
            for recognizer in gestureRecognizers ?? [] {
                recognizer.view = nil
            }
            viewGestureRecognizers[ObjectIdentifier(self)] = nil
            for recognizer in newValue ?? [] {
                addGestureRecognizer(recognizer)
            }
        }
    }

    /// Attaches a recognizer. A recognizer belongs to at most one view, so
    /// attaching one that's already attached elsewhere moves it (Apple
    /// semantics). Re-adding to the same view is a no-op.
    public func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        pruneDeadViewEntries()
        if let previous = gestureRecognizer.view, previous !== self {
            previous.removeGestureRecognizer(gestureRecognizer)
        }
        var current = gestureRecognizers ?? []
        guard !current.contains(where: { $0 === gestureRecognizer }) else { return }
        current.append(gestureRecognizer)
        viewGestureRecognizers[ObjectIdentifier(self)] = current
        gestureRecognizer.view = self
    }

    /// Detaches a recognizer (releasing the view's strong hold on it).
    /// Ignored if the recognizer isn't attached to this view, as on Apple.
    public func removeGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.view === self else { return }
        var current = gestureRecognizers ?? []
        current.removeAll { $0 === gestureRecognizer }
        viewGestureRecognizers[ObjectIdentifier(self)] = current
        gestureRecognizer.view = nil
    }
}

#endif // !os(iOS)
