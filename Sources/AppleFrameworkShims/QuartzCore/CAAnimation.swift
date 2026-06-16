//
//  CAAnimation.swift
//  QuartzCore shim — Apple-framework shims for QuillUI on Linux (QuillOS).
//
//  This file provides the Core Animation *timing engine*: the animation
//  class hierarchy (CAAnimation → CAPropertyAnimation → CABasicAnimation →
//  CASpringAnimation, plus CAKeyframeAnimation, CAAnimationGroup and
//  CATransition), CAMediaTimingFunction and the string-constant types,
//  CATransaction with real stack/completion semantics, and the internal
//  QuartzCoreAnimationEngine that CALayer calls from add/removeAnimation.
//
//  Honest Linux semantics
//  ----------------------
//  There is no compositor or pixel rendering behind this module yet
//  (compositing arrives later via QuillPaint). What IS real here:
//
//   * Model state: animations carry their full Apple-shaped configuration,
//     so unmodified Signal-iOS / Telegram-iOS-style code compiles and
//     behaves sensibly.
//   * Timing: adding an animation to a layer schedules real, cancellable
//     work on the main queue. `animationDidStart` fires asynchronously on
//     the next main-queue hop; `animationDidStop(_:finished:)` fires after
//     the animation's computed wall-clock duration (duration / speed,
//     scaled for repeats and autoreverse). Completion-chained animation
//     patterns therefore actually chain instead of re-entering synchronously.
//   * Transactions: CATransaction.begin/commit maintain a real stack with
//     inherited disableActions/animationDuration, and a transaction's
//     completion block fires only after every animation registered while it
//     was open has completed (or on the next main-queue hop after commit
//     when none were registered).
//
//  Documented divergences from Apple:
//
//   * No frame-by-frame value interpolation and no presentation-layer
//     sampling — this engine models the *lifecycle* of an animation, not
//     per-frame output.
//   * Animations are NOT copied when added to a layer (Apple copies). The
//     object you add is the object whose delegate fires; re-adding the same
//     object (or adding it to a second layer) reschedules it rather than
//     running two independent copies.
//   * CATransaction keeps ONE global lock-guarded stack rather than Apple's
//     per-thread stacks; QuillUI drives Core Animation from the main thread.
//   * `speed <= 0` simply never completes here (Apple pauses the animation
//     at its current time); infinite `repeatCount` never auto-completes and
//     runs until removed (matching Apple).
//

import Foundation
import Dispatch
import QuillFoundation

// MARK: - String-constant types

/// How an animation's effect applies outside its active duration.
/// Stored faithfully; not yet consumed by a presentation clock.
public struct CAMediaTimingFillMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let removed = CAMediaTimingFillMode(rawValue: "removed")
    public static let forwards = CAMediaTimingFillMode(rawValue: "forwards")
    public static let backwards = CAMediaTimingFillMode(rawValue: "backwards")
    public static let both = CAMediaTimingFillMode(rawValue: "both")
}

public struct CAMediaTimingFunctionName: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
}

public struct CAAnimationCalculationMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let linear = CAAnimationCalculationMode(rawValue: "linear")
    public static let discrete = CAAnimationCalculationMode(rawValue: "discrete")
    public static let paced = CAAnimationCalculationMode(rawValue: "paced")
    public static let cubic = CAAnimationCalculationMode(rawValue: "cubic")
    public static let cubicPaced = CAAnimationCalculationMode(rawValue: "cubicPaced")
}

public struct CATransitionType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let fade = CATransitionType(rawValue: "fade")
    public static let moveIn = CATransitionType(rawValue: "moveIn")
    public static let push = CATransitionType(rawValue: "push")
    public static let reveal = CATransitionType(rawValue: "reveal")
}

public struct CATransitionSubtype: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let fromRight = CATransitionSubtype(rawValue: "fromRight")
    public static let fromLeft = CATransitionSubtype(rawValue: "fromLeft")
    public static let fromTop = CATransitionSubtype(rawValue: "fromTop")
    public static let fromBottom = CATransitionSubtype(rawValue: "fromBottom")
}

// MARK: - CAMediaTimingFunction

/// A cubic Bézier timing curve. The control points are stored for real so
/// `getControlPoint(at:values:)` is correct today and the future QuillPaint
/// compositor can sample the curve without API changes.
open class CAMediaTimingFunction: NSObject {

    /// p1 and p2 of the Bézier; p0 = (0,0) and p3 = (1,1) are implicit.
    private let c1x: Float, c1y: Float, c2x: Float, c2y: Float

    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
        self.c1x = c1x
        self.c1y = c1y
        self.c2x = c2x
        self.c2y = c2y
        super.init()
    }

    public convenience init(name: CAMediaTimingFunctionName) {
        switch name {
        case .linear:        self.init(controlPoints: 0.0, 0.0, 1.0, 1.0)
        case .easeIn:        self.init(controlPoints: 0.42, 0.0, 1.0, 1.0)
        case .easeOut:       self.init(controlPoints: 0.0, 0.0, 0.58, 1.0)
        case .easeInEaseOut: self.init(controlPoints: 0.42, 0.0, 0.58, 1.0)
        default:             self.init(controlPoints: 0.25, 0.1, 0.25, 1.0) // .default and unknown names
        }
    }

    /// Writes the x and y of control point `idx` into `ptr[0]` and `ptr[1]`.
    /// p0 = (0,0), p1, p2, p3 = (1,1). Out-of-range indices are ignored
    /// (Apple raises an Objective-C exception; there is no ObjC runtime here).
    open func getControlPoint(at idx: Int, values ptr: UnsafeMutablePointer<Float>) {
        switch idx {
        case 0: ptr[0] = 0.0; ptr[1] = 0.0
        case 1: ptr[0] = c1x; ptr[1] = c1y
        case 2: ptr[0] = c2x; ptr[1] = c2y
        case 3: ptr[0] = 1.0; ptr[1] = 1.0
        default: break
        }
    }
}

// MARK: - CAAnimationDelegate

/// On Apple these are optional Objective-C protocol methods; with no ObjC
/// runtime they are modeled as requirements with no-op default
/// implementations, so conformers implement only what they need.
public protocol CAAnimationDelegate: AnyObject {
    func animationDidStart(_ anim: CAAnimation)
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool)
}

public extension CAAnimationDelegate {
    func animationDidStart(_ anim: CAAnimation) {}
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {}
}

// MARK: - CAAnimation

open class CAAnimation: NSObject, CAMediaTiming, @unchecked Sendable {

    // MARK: CAMediaTiming
    // Stored faithfully. The engine uses duration/speed/repeatCount/
    // repeatDuration/autoreverses for scheduling; beginTime, timeOffset and
    // fillMode are model-only until a presentation clock exists (QuillPaint).
    open var beginTime: CFTimeInterval = 0
    open var duration: CFTimeInterval = 0
    open var speed: Float = 1
    open var timeOffset: CFTimeInterval = 0
    open var repeatCount: Float = 0
    open var repeatDuration: CFTimeInterval = 0
    open var autoreverses: Bool = false
    open var fillMode: CAMediaTimingFillMode = .removed

    /// Apple retains the animation delegate — unusually, this is a STRONG
    /// reference ("The delegate object is retained by the receiver",
    /// CAAnimation docs). One-shot completion-delegate objects that nothing
    /// else retains (the standard Telegram/Signal chaining pattern) depend
    /// on this, so we match Apple exactly. The animation itself is released
    /// once it completes and is removed, breaking the chain.
    open var delegate: CAAnimationDelegate?

    /// The timing curve. Lives on CAAnimation (not on subclasses), matching
    /// Apple's hierarchy. Stored faithfully; not yet sampled per-frame.
    open var timingFunction: CAMediaTimingFunction?

    /// When true (the default), the engine tells the layer to drop the
    /// animation after it finishes (`_animationDidComplete(key:)`).
    open var isRemovedOnCompletion: Bool = true

    public override init() {
        super.init()
    }

    // MARK: Mini key-value coding
    //
    // corelibs NSObject has no KVC, but tagging animations is a standard
    // pattern (`anim.setValue(id, forKey: "animationID")` then reading it in
    // animationDidStop to tell chained animations apart). A lock-guarded
    // side dictionary keeps that working; any key round-trips.

    fileprivate let _kvLock = NSLock()
    fileprivate var _kvStorage: [String: Any] = [:]
}

// QuillFoundation's NSObject extension owns the Apple-named KVC entry points
// and forwards them through QuillKeyValueCoding. CAAnimation's adoption backs
// them with the side dictionary: any key round-trips, which is exactly what
// the tag-the-animation pattern needs.
extension CAAnimation: QuillKeyValueCoding {

    public func quillSetValue(_ value: Any?, forKey key: String) {
        _kvLock.lock()
        defer { _kvLock.unlock() }
        if let value {
            _kvStorage[key] = value
        } else {
            _kvStorage.removeValue(forKey: key)
        }
    }

    public func quillValue(forKey key: String) -> Any? {
        _kvLock.lock()
        defer { _kvLock.unlock() }
        return _kvStorage[key]
    }
}

/// On Apple, CAAnimation adopts CAAction: supplying an animation in a layer's
/// `actions` dictionary (or returning one from the delegate) makes the
/// triggered action add the animation to the layer under the event key.
extension CAAnimation: CAAction {
    public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
        (anObject as? CALayer)?.add(self, forKey: event)
    }
}

// MARK: - CAPropertyAnimation

open class CAPropertyAnimation: CAAnimation {

    /// Key path of the animated property on the layer. Model-only: there is
    /// no per-frame interpolation of the named property on Linux yet.
    open var keyPath: String?
    open var isAdditive: Bool = false
    open var isCumulative: Bool = false

    public convenience init(keyPath path: String?) {
        self.init()
        self.keyPath = path
    }
}

// MARK: - CABasicAnimation

open class CABasicAnimation: CAPropertyAnimation {
    open var fromValue: Any?
    open var toValue: Any?
    open var byValue: Any?
}

// MARK: - CASpringAnimation

open class CASpringAnimation: CABasicAnimation {

    open var mass: CGFloat = 1
    open var stiffness: CGFloat = 100
    open var damping: CGFloat = 10
    open var initialVelocity: CGFloat = 0

    /// Estimated time for the spring to settle: when the motion envelope
    /// decays below ~0.1% of its initial displacement. As on Apple, this
    /// does NOT automatically become `duration`; callers typically write
    /// `animation.duration = animation.settlingDuration`.
    open var settlingDuration: CFTimeInterval {
        let m = Double(max(mass, 1e-6))
        let k = Double(max(stiffness, 1e-6))
        let c = Double(damping)
        guard c > 0 else { return .greatestFiniteMagnitude } // undamped: never settles
        // -ln(0.001): target envelope threshold of 0.1%.
        let logThreshold = 6.907755278982137
        let discriminant = c * c - 4 * m * k
        let decay: Double
        if discriminant >= 0 {
            // Critically damped / overdamped: the slowest exponent dominates.
            decay = (c - discriminant.squareRoot()) / (2 * m)
        } else {
            // Underdamped: the oscillation envelope decays at c / 2m.
            decay = c / (2 * m)
        }
        guard decay > 1e-9 else { return .greatestFiniteMagnitude }
        return logThreshold / decay
    }
}

// MARK: - CAKeyframeAnimation

public struct CAAnimationRotationMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let rotateAuto = CAAnimationRotationMode(rawValue: "auto")
    public static let rotateAutoReverse = CAAnimationRotationMode(rawValue: "autoReverse")
}

open class CAKeyframeAnimation: CAPropertyAnimation {
    open var values: [Any]?
    open var keyTimes: [NSNumber]?
    open var timingFunctions: [CAMediaTimingFunction]?
    open var calculationMode: CAAnimationCalculationMode = .linear
    /// Optional geometry path for position keyframes. Stored faithfully;
    /// not sampled per-frame on Linux yet.
    open var path: CGPath?
    open var rotationMode: CAAnimationRotationMode?
    // Cubic-calculation tuning arrays (model-only, like the curve itself).
    open var tensionValues: [NSNumber]?
    open var continuityValues: [NSNumber]?
    open var biasValues: [NSNumber]?
}

// MARK: - CAAnimationGroup

open class CAAnimationGroup: CAAnimation {
    /// Child animations. Their individual timing is not independently
    /// modeled; the group itself starts and completes per its own timing
    /// like any other CAAnimation, which is what delegate-chained group
    /// patterns observe.
    open var animations: [CAAnimation]?
}

// MARK: - CATransition

open class CATransition: CAAnimation {
    open var type: CATransitionType = .fade
    open var subtype: CATransitionSubtype?
    open var startProgress: Float = 0
    open var endProgress: Float = 1
    // timingFunction is inherited from CAAnimation, matching Apple.
}

// MARK: - Main-queue hop helper

/// corelibs Dispatch requires `@Sendable` blocks for `async(execute:)`, but
/// Core Animation's completion blocks are non-Sendable by API contract (as on
/// Apple). Every block routed through here both originates from and runs on
/// the main queue, so the hop is made through an @unchecked Sendable box.
private struct _QuillMainQueueBlock: @unchecked Sendable {
    let run: () -> Void
}

internal func quartzCoreMainAsync(_ block: @escaping () -> Void) {
    let boxed = _QuillMainQueueBlock(run: block)
    DispatchQueue.main.async { boxed.run() }
}

// MARK: - CATransaction

/// One begin/commit nesting level. All fields are mutated only under
/// CATransaction's lock (including post-commit `pendingAnimations` updates
/// reported by the animation engine), hence @unchecked Sendable.
internal final class _CATransactionRecord: @unchecked Sendable {
    var disableActions: Bool
    var animationDuration: CFTimeInterval
    var animationTimingFunction: CAMediaTimingFunction?
    var completionBlock: (() -> Void)?
    /// Number of animations added while this transaction was open (anywhere
    /// on the stack — nested begin/commit pairs form one transaction group,
    /// so an outer record also counts animations added inside nested
    /// transactions) that have not yet completed or been removed.
    var pendingAnimations: Int = 0
    var isCommitted: Bool = false
    /// True once the OUTERMOST transaction of this record's group has
    /// committed. On Apple nothing in a nested group commits — and no
    /// completion block can fire — until the outermost commit().
    var groupCommitted: Bool = false

    init(disableActions: Bool,
         animationDuration: CFTimeInterval,
         animationTimingFunction: CAMediaTimingFunction?) {
        self.disableActions = disableActions
        self.animationDuration = animationDuration
        self.animationTimingFunction = animationTimingFunction
    }
}

/// Real transaction semantics for the shim.
///
/// Simplifications (documented): Apple keeps one transaction stack PER
/// THREAD plus an implicit run-loop transaction; this shim keeps ONE global,
/// NSLock-guarded stack, and models the implicit transaction only as default
/// values (duration 0.25 s, actions enabled). Writes made with no open
/// transaction are dropped; `setCompletionBlock` with no open transaction is
/// treated as a one-shot implicit transaction whose block fires on the next
/// main-queue hop.
open class CATransaction: NSObject {

    private static let _lock = NSLock()
    nonisolated(unsafe) private static var _stack: [_CATransactionRecord] = []
    /// Records popped by non-outermost commit()s, parked until the outermost
    /// commit of their group arrives (nested begin/commit pairs are ONE
    /// transaction group on Apple; nothing settles early).
    nonisolated(unsafe) private static var _awaitingGroup: [_CATransactionRecord] = []

    /// Implicit-transaction default duration, used when the stack is empty.
    private static let _defaultDuration: CFTimeInterval = 0.25

    // MARK: Public API

    public class func begin() {
        _lock.lock()
        defer { _lock.unlock() }
        let inherited = _stack.last
        _stack.append(_CATransactionRecord(
            disableActions: inherited?.disableActions ?? false,
            animationDuration: inherited?.animationDuration ?? _defaultDuration,
            animationTimingFunction: inherited?.animationTimingFunction
        ))
    }

    public class func commit() {
        _lock.lock()
        guard let record = _stack.popLast() else {
            _lock.unlock()
            return // unbalanced commit: ignore
        }
        record.isCommitted = true
        // A nested commit only parks its record: the GROUP commits — and
        // completion blocks become eligible — at the outermost commit().
        guard _stack.isEmpty else {
            _awaitingGroup.append(record)
            _lock.unlock()
            return
        }
        var group = _awaitingGroup
        group.append(record)
        _awaitingGroup = []
        var due: [() -> Void] = []
        for member in group {
            member.groupCommitted = true
            if member.pendingAnimations <= 0, let block = member.completionBlock {
                member.completionBlock = nil
                due.append(block)
            }
        }
        _lock.unlock()
        // Completion contract: no pending animations at group-commit time
        // means the block fires on the next main-queue hop (inner records
        // first — they committed first). Otherwise the engine fires it when
        // the last animation registered against that record completes.
        for block in due { quartzCoreMainAsync(block) }
    }

    /// On Apple this pushes pending model changes to the render server.
    /// There is no render server on Linux yet (compositing arrives with
    /// QuillPaint), so this is a no-op.
    public class func flush() {}

    /// No-ops: all shim transaction state is already internally lock-guarded.
    public class func lock() {}
    public class func unlock() {}

    public class func disableActions() -> Bool {
        _lock.lock()
        defer { _lock.unlock() }
        return _stack.last?.disableActions ?? false
    }

    public class func setDisableActions(_ flag: Bool) {
        _lock.lock()
        defer { _lock.unlock() }
        // With no open transaction the write is dropped (Apple would absorb
        // it into the implicit run-loop transaction, which is not modeled).
        _stack.last?.disableActions = flag
    }

    public class func animationDuration() -> CFTimeInterval {
        _lock.lock()
        defer { _lock.unlock() }
        return _stack.last?.animationDuration ?? _defaultDuration
    }

    public class func setAnimationDuration(_ dur: CFTimeInterval) {
        _lock.lock()
        defer { _lock.unlock() }
        _stack.last?.animationDuration = dur
    }

    public class func animationTimingFunction() -> CAMediaTimingFunction? {
        _lock.lock()
        defer { _lock.unlock() }
        return _stack.last?.animationTimingFunction
    }

    public class func setAnimationTimingFunction(_ function: CAMediaTimingFunction?) {
        _lock.lock()
        defer { _lock.unlock() }
        _stack.last?.animationTimingFunction = function
    }

    public class func completionBlock() -> (() -> Void)? {
        _lock.lock()
        defer { _lock.unlock() }
        return _stack.last?.completionBlock
    }

    public class func setCompletionBlock(_ block: (() -> Void)?) {
        _lock.lock()
        if let top = _stack.last {
            top.completionBlock = block
            _lock.unlock()
            return
        }
        guard let block else {
            _lock.unlock()
            return
        }
        // No open transaction: model Apple's implicit run-loop transaction.
        // Push a synthetic record — so animations added later in this same
        // run-loop turn register against it and gate the block — and commit
        // it on the next main-queue hop (the shim's stand-in for "end of the
        // current run-loop pass").
        let implicit = _CATransactionRecord(
            disableActions: false,
            animationDuration: _defaultDuration,
            animationTimingFunction: nil)
        implicit.completionBlock = block
        _stack.append(implicit)
        _lock.unlock()
        DispatchQueue.main.async { _commitImplicit(implicit) }
    }

    /// Commits the synthetic implicit transaction created by
    /// setCompletionBlock-with-no-begin. Tolerates the record having already
    /// been popped by an (unbalanced) explicit commit(): settling is
    /// idempotent because the completion block is taken exactly once.
    private static func _commitImplicit(_ record: _CATransactionRecord) {
        _lock.lock()
        if let index = _stack.firstIndex(where: { $0 === record }) {
            _stack.remove(at: index)
        }
        record.isCommitted = true
        // The implicit record is its own group (it is only ever pushed onto
        // an empty stack), so group commit coincides with this commit.
        record.groupCommitted = true
        var due: (() -> Void)? = nil
        if record.pendingAnimations <= 0, let block = record.completionBlock {
            record.completionBlock = nil
            due = block
        }
        _lock.unlock()
        due?() // already on the main queue
    }

    // MARK: Internal hooks for QuartzCoreAnimationEngine

    /// Registers one in-flight animation against EVERY open transaction —
    /// nested begin/commit pairs form one group on Apple, and an outer
    /// transaction's completion block waits for animations added while a
    /// nested transaction was open. Returns the records the engine must
    /// later report completion or removal to (empty when no transaction is
    /// open).
    internal static func _noteAnimationScheduled() -> [_CATransactionRecord] {
        _lock.lock()
        defer { _lock.unlock() }
        for record in _stack { record.pendingAnimations += 1 }
        return _stack
    }

    /// Reports that an animation registered with `record` completed or was
    /// removed. Returns the transaction's completion block if this was the
    /// last pending animation of a record whose GROUP has committed; the
    /// caller is responsible for invoking it on the main queue.
    internal static func _noteAnimationFinished(_ record: _CATransactionRecord) -> (() -> Void)? {
        _lock.lock()
        defer { _lock.unlock() }
        record.pendingAnimations -= 1
        guard record.isCommitted,
              record.groupCommitted,
              record.pendingAnimations <= 0,
              let block = record.completionBlock
        else { return nil }
        record.completionBlock = nil
        return block
    }
}

// MARK: - QuartzCoreAnimationEngine (internal)

/// The module-internal scheduler behind CALayer.add(_:forKey:) and
/// removeAnimation(forKey:)/removeAllAnimations(). It owns no pixels: it
/// models WHEN an animation starts and stops, drives CAAnimationDelegate
/// callbacks asynchronously on the main queue, asks the layer to drop
/// finished animations, and settles CATransaction completion blocks.
///
/// Scheduling model: wall-clock main-queue timers. `beginTime`, `timeOffset`
/// and `fillMode` are stored on the animation but not factored into
/// scheduling — there is no presentation clock until QuillPaint lands.
internal enum QuartzCoreAnimationEngine {

    private struct PendingEntry {
        /// Strong reference: keeps the animation (and its retained delegate)
        /// alive while in flight, and guarantees the ObjectIdentifier key
        /// cannot be recycled by a new allocation while the entry exists.
        let animation: CAAnimation
        /// nil for animations that never auto-complete (speed <= 0 or
        /// infinite repeatCount); those stay pending until removed.
        let workItem: DispatchWorkItem?
        /// Every transaction that was open when the animation was added
        /// (nested transactions form one group; each open record counts it).
        let transactions: [_CATransactionRecord]
        /// The layer that owns this schedule. Weak reference for the
        /// displacement callback; the identity token gates deinit-cancel so
        /// a dying former owner cannot kill the schedule after the same
        /// animation object was re-added to a different layer.
        weak var owner: CALayer?
        let ownerID: ObjectIdentifier
        let key: String
    }

    private static let _lock = NSLock()
    /// Keyed by animation object identity (per the module contract). NOTE
    /// (divergence): Apple copies animations on add; this shim does not, so
    /// one animation object has at most one in-flight schedule. Re-adding it
    /// — including to a different layer — silently cancels and replaces the
    /// previous schedule.
    nonisolated(unsafe) private static var _pending: [ObjectIdentifier: PendingEntry] = [:]

    // MARK: Cross-file contract (called by CALayer.swift)

    @MainActor static func didAdd(_ animation: CAAnimation, forKey key: String, to layer: CALayer) {
        // Replace any previous schedule for this same object (see NOTE on
        // `_pending`). The old schedule is cancelled without delegate
        // callbacks; its transaction bookkeeping is still settled, and the
        // PREVIOUS owner's (key, animation) bookkeeping pair is dropped so
        // its animationKeys() stops reporting a schedule it no longer owns
        // and its deinit cannot cancel the new owner's schedule. Skipped for
        // a same-layer same-key re-add, where the fresh pair must survive.
        if let stale = takeEntry(for: animation) {
            stale.workItem?.cancel()
            settle(stale.transactions)
            if let previousOwner = stale.owner,
               !(previousOwner === layer && stale.key == key) {
                previousOwner._animationWasDisplaced(key: stale.key, animation: animation)
            }
        }

        let records = CATransaction._noteAnimationScheduled()

        // didStart fires asynchronously, matching Apple: it must never run
        // inside the caller's add(_:forKey:) stack frame.
        quartzCoreMainAsync {
            animation.delegate?.animationDidStart(animation)
        }

        // speed <= 0: Apple pauses the animation at its current time; this
        // shim has no presentation clock, so it simply never auto-completes.
        // Infinite repeatCount runs until explicitly removed (as on Apple).
        let neverCompletes = animation.speed <= 0
            || animation.repeatCount.isInfinite
            || animation.repeatCount >= Float.greatestFiniteMagnitude

        if neverCompletes {
            _lock.lock()
            _pending[ObjectIdentifier(animation)] = PendingEntry(
                animation: animation, workItem: nil, transactions: records,
                owner: layer, ownerID: ObjectIdentifier(layer), key: key)
            _lock.unlock()
            return
        }

        // Effective wall-clock duration:
        //   single pass  = animation.duration, else the current transaction's
        //                  animationDuration (default 0.25 s);
        //   full run     = single pass × (autoreverses ? 2 : 1)
        //                              × (repeatCount > 0 ? repeatCount : 1),
        //                  unless repeatDuration > 0, which overrides the
        //                  repeat arithmetic outright;
        //   everything scaled by `speed` (repeatDuration is measured in the
        //   animation's speed-scaled local time, so it is scaled too).
        let base = animation.duration > 0 ? animation.duration : CATransaction.animationDuration()
        let speedFactor = Double(max(animation.speed, 0.0001))
        let total: CFTimeInterval
        if animation.repeatDuration > 0 {
            total = animation.repeatDuration / speedFactor
        } else {
            let cycles = animation.repeatCount > 0 ? Double(animation.repeatCount) : 1
            total = (base * (animation.autoreverses ? 2 : 1) * cycles) / speedFactor
        }

        let item = DispatchWorkItem { [weak layer] in
            // Single-take settles the race with didRemove: if removal won
            // (cancel() can miss an already-dequeued item), the entry is
            // gone and the removal path owns the callbacks.
            guard let entry = takeEntry(for: animation) else { return }
            let blocks = takeDueBlocks(entry.transactions)
            Task { @MainActor in
                // Drop the layer's bookkeeping entry BEFORE the delegate fires:
                // didStop handlers routinely re-add an animation under the same
                // key, and removal-after would silently strip the new one.
                if animation.isRemovedOnCompletion {
                    layer?._animationDidComplete(key: key)
                }
                animation.delegate?.animationDidStop(animation, finished: true)
                for block in blocks { block() } // already on main; after didStop
            }
        }

        _lock.lock()
        _pending[ObjectIdentifier(animation)] = PendingEntry(
            animation: animation, workItem: item, transactions: records,
            owner: layer, ownerID: ObjectIdentifier(layer), key: key)
        _lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + total, execute: item)
    }

    @MainActor static func didRemove(_ animation: CAAnimation, forKey key: String, from layer: CALayer) {
        // No entry: the animation already completed (its callbacks fired) or
        // was never scheduled — nothing to do, and crucially no duplicate
        // animationDidStop.
        guard let entry = takeEntry(for: animation) else { return }
        entry.workItem?.cancel()
        let blocks = takeDueBlocks(entry.transactions)
        quartzCoreMainAsync {
            animation.delegate?.animationDidStop(animation, finished: false)
            for block in blocks { block() } // after didStop, per Apple order
        }
    }

    /// CALayer.deinit teardown: cancels any pending schedule for `animation`
    /// WITHOUT delegate callbacks and without touching the deinitializing
    /// layer (passing it here would risk resurrection — hence the identity
    /// token). Only the schedule's CURRENT owner may cancel it: if the same
    /// animation object was re-added to another layer, the schedule belongs
    /// to that layer now and the former owner's deinit must leave it alone.
    /// Never-completing entries (speed <= 0, infinite repeatCount) would
    /// otherwise pin the engine table forever. Transaction bookkeeping is
    /// still settled.
    static func cancelForLayerDeinit(_ animation: CAAnimation, ownedBy layerID: ObjectIdentifier) {
        guard let entry = takeEntry(for: animation, ifOwnedBy: layerID) else { return }
        entry.workItem?.cancel()
        settle(entry.transactions)
    }

    // MARK: Helpers

    /// Atomically removes and returns the pending entry for `animation`,
    /// optionally only when owned by the given layer identity.
    private static func takeEntry(
        for animation: CAAnimation,
        ifOwnedBy layerID: ObjectIdentifier? = nil
    ) -> PendingEntry? {
        _lock.lock()
        defer { _lock.unlock() }
        let id = ObjectIdentifier(animation)
        guard let entry = _pending[id] else { return nil }
        if let layerID, entry.ownerID != layerID { return nil }
        return _pending.removeValue(forKey: id)
    }

    /// Collects the completion blocks that became due from finishing one
    /// animation across all its registered transaction records.
    private static func takeDueBlocks(_ records: [_CATransactionRecord]) -> [() -> Void] {
        records.compactMap { CATransaction._noteAnimationFinished($0) }
    }

    /// Settles transaction bookkeeping for a cancelled schedule, firing any
    /// now-due completion blocks on the main queue.
    private static func settle(_ records: [_CATransactionRecord]) {
        for block in takeDueBlocks(records) { quartzCoreMainAsync(block) }
    }
}
