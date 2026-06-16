//
//  CALayer.swift
//  QuillUI · AppleFrameworkShims/QuartzCore
//
//  Core Animation's layer model for Linux (QuillOS).
//
//  This file provides:
//    - CAMediaTiming protocol
//    - CALayer: a FUNCTIONAL model layer — real geometry math
//      (bounds/position/anchorPoint with a computed `frame`), a real layer
//      hierarchy, coordinate conversion, hit testing, display/layout
//      bookkeeping, a mini key-value-coding table for animation key paths,
//      and animation bookkeeping wired to QuartzCoreAnimationEngine
//      (CAAnimation.swift).
//    - CALayerDelegate (+ no-op default implementations)
//    - CAAction protocol (+ NSNull conformance)
//    - CALayerContentsGravity, CALayerCornerCurve, CALayerContentsFilter,
//      CACornerMask, kCAOnOrderIn / kCAOnOrderOut, CACurrentMediaTime()
//
//  Honest Linux semantics: this is a MODEL + TIMING layer only. There is no
//  compositor and no pixel rendering yet — compositing arrives later via
//  QuillPaint. Concretely:
//    - display() never fabricates a CGContext; it forwards to the delegate.
//    - render(in:) is inert.
//    - presentation() returns the model layer (there are no interpolated
//      in-flight values to snapshot), so model == presentation.
//    - frame and coordinate conversion ignore `transform` (documented at the
//      members); bounds.origin scroll offsets ARE honored.
//    - Implicit actions are NOT auto-dispatched on property mutation;
//      explicit animations added via add(_:forKey:) run through the module's
//      animation engine, which provides real asynchronous completion timing
//      on DispatchQueue.main.
//

import Foundation
import QuillFoundation

// MARK: - Time

/// Real monotonic clock (the corelibs equivalent of Darwin's
/// mach_absolute_time-based CACurrentMediaTime).
public func CACurrentMediaTime() -> CFTimeInterval {
    return ProcessInfo.processInfo.systemUptime
}

// MARK: - Action event names

public let kCAOnOrderIn: String = "onOrderIn"
public let kCAOnOrderOut: String = "onOrderOut"

// MARK: - CAMediaTiming

public protocol CAMediaTiming {
    var beginTime: CFTimeInterval { get set }
    var duration: CFTimeInterval { get set }
    var speed: Float { get set }
    var timeOffset: CFTimeInterval { get set }
    var repeatCount: Float { get set }
    var repeatDuration: CFTimeInterval { get set }
    var autoreverses: Bool { get set }
    var fillMode: CAMediaTimingFillMode { get set }
}

// MARK: - CAAction

public protocol CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?)
}

/// Per Apple, an NSNull supplied as an action means "do nothing" — it
/// explicitly suppresses any action for the event.
extension NSNull: CAAction {
    public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
        // Intentionally empty: NSNull is the canonical "no action" action.
    }
}

// MARK: - CALayerDelegate

public protocol CALayerDelegate: AnyObject {
    func display(_ layer: CALayer)
    func draw(_ layer: CALayer, in ctx: CGContext)
    func layerWillDraw(_ layer: CALayer)
    func layoutSublayers(of layer: CALayer)
    func action(for layer: CALayer, forKey event: String) -> CAAction?
}

// Default no-op implementations stand in for Objective-C optional methods.
extension CALayerDelegate {
    public func display(_ layer: CALayer) {}
    public func draw(_ layer: CALayer, in ctx: CGContext) {}
    public func layerWillDraw(_ layer: CALayer) {}
    public func layoutSublayers(of layer: CALayer) {}
    public func action(for layer: CALayer, forKey event: String) -> CAAction? { return nil }
}

// MARK: - String-constant types

public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let top = CALayerContentsGravity(rawValue: "top")
    public static let bottom = CALayerContentsGravity(rawValue: "bottom")
    public static let left = CALayerContentsGravity(rawValue: "left")
    public static let right = CALayerContentsGravity(rawValue: "right")
    public static let topLeft = CALayerContentsGravity(rawValue: "topLeft")
    public static let topRight = CALayerContentsGravity(rawValue: "topRight")
    public static let bottomLeft = CALayerContentsGravity(rawValue: "bottomLeft")
    public static let bottomRight = CALayerContentsGravity(rawValue: "bottomRight")
    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
}

public struct CALayerCornerCurve: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

public struct CALayerContentsFilter: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let linear = CALayerContentsFilter(rawValue: "linear")
    public static let nearest = CALayerContentsFilter(rawValue: "nearest")
    public static let trilinear = CALayerContentsFilter(rawValue: "trilinear")
}

public struct CALayerContentsFormat: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let RGBA8Uint = CALayerContentsFormat(rawValue: "RGBA8")
    public static let RGBA16Float = CALayerContentsFormat(rawValue: "RGBAh")
    public static let gray8Uint = CALayerContentsFormat(rawValue: "Gray8")
}

public struct CAEdgeAntialiasingMask: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let layerLeftEdge = CAEdgeAntialiasingMask(rawValue: 1 << 0)
    public static let layerRightEdge = CAEdgeAntialiasingMask(rawValue: 1 << 1)
    public static let layerBottomEdge = CAEdgeAntialiasingMask(rawValue: 1 << 2)
    public static let layerTopEdge = CAEdgeAntialiasingMask(rawValue: 1 << 3)
}

public struct CACornerMask: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let layerMinXMinYCorner = CACornerMask(rawValue: 1 << 0)
    public static let layerMaxXMinYCorner = CACornerMask(rawValue: 1 << 1)
    public static let layerMinXMaxYCorner = CACornerMask(rawValue: 1 << 2)
    public static let layerMaxXMaxYCorner = CACornerMask(rawValue: 1 << 3)
}

// MARK: - CALayer

open class CALayer: NSObject, CAMediaTiming {

    // MARK: Initializers

    /// Keep the initializer non-`required`, matching Apple source semantics:
    /// existing CALayer subclasses commonly declare a plain `override init()`.
    /// Dynamic layer creation belongs in the view framework's factory layer,
    /// not in a source-breaking initializer requirement on every subclass.
    public override init() {
        super.init()
    }

    /// Apple's presentation/shadow-copy initializer: copies every model
    /// property when `layer` is a CALayer. Hierarchy (sublayers/superlayer)
    /// and in-flight animations are NOT copied, matching Apple's contract.
    public init(layer: Any) {
        super.init()
        guard let other = layer as? CALayer else { return }
        // Geometry
        bounds = other.bounds
        position = other.position
        anchorPoint = other.anchorPoint
        anchorPointZ = other.anchorPointZ
        isGeometryFlipped = other.isGeometryFlipped
        zPosition = other.zPosition
        transform = other.transform
        sublayerTransform = other.sublayerTransform
        // Appearance
        opacity = other.opacity
        isHidden = other.isHidden
        backgroundColor = other.backgroundColor
        borderColor = other.borderColor
        borderWidth = other.borderWidth
        cornerRadius = other.cornerRadius
        cornerCurve = other.cornerCurve
        maskedCorners = other.maskedCorners
        masksToBounds = other.masksToBounds
        isDoubleSided = other.isDoubleSided
        isOpaque = other.isOpaque
        allowsGroupOpacity = other.allowsGroupOpacity
        allowsEdgeAntialiasing = other.allowsEdgeAntialiasing
        style = other.style
        filters = other.filters
        compositingFilter = other.compositingFilter
        name = other.name
        // Contents
        contents = other.contents
        contentsRect = other.contentsRect
        contentsCenter = other.contentsCenter
        contentsGravity = other.contentsGravity
        contentsScale = other.contentsScale
        minificationFilter = other.minificationFilter
        magnificationFilter = other.magnificationFilter
        shouldRasterize = other.shouldRasterize
        rasterizationScale = other.rasterizationScale
        drawsAsynchronously = other.drawsAsynchronously
        needsDisplayOnBoundsChange = other.needsDisplayOnBoundsChange
        contentsFormat = other.contentsFormat
        edgeAntialiasingMask = other.edgeAntialiasingMask
        // Shadow
        shadowColor = other.shadowColor
        shadowOpacity = other.shadowOpacity
        shadowRadius = other.shadowRadius
        shadowOffset = other.shadowOffset
        shadowPath = other.shadowPath
        // References
        mask = other.mask
        actions = other.actions
        delegate = other.delegate
        // CAMediaTiming
        beginTime = other.beginTime
        duration = other.duration
        speed = other.speed
        timeOffset = other.timeOffset
        repeatCount = other.repeatCount
        repeatDuration = other.repeatDuration
        autoreverses = other.autoreverses
        fillMode = other.fillMode
    }

    // MARK: Geometry

    /// Interior coordinate space. `bounds.origin` behaves as a scroll offset,
    /// exactly like Apple's model — coordinate conversion honors it.
    open var bounds: CGRect = .zero {
        didSet {
            // Apple invalidates on ANY bounds change, origin included:
            // scrolling is bounds.origin mutation and fires layout every
            // frame, and needsDisplayOnBoundsChange keys off the whole rect.
            if oldValue != bounds {
                setNeedsLayout()
                if needsDisplayOnBoundsChange { setNeedsDisplay() }
            }
        }
    }

    /// Location of the anchor point in the superlayer's coordinate space.
    open var position: CGPoint = .zero

    /// Unit-space anchor; (0.5, 0.5) = center, per Apple.
    open var anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)

    open var zPosition: CGFloat = 0
    open var anchorPointZ: CGFloat = 0
    open var isGeometryFlipped: Bool = false

    open func contentsAreFlipped() -> Bool {
        // Walks isGeometryFlipped up the chain on Apple; no compositor here,
        // and flips are unset in practice, so the model answer is false.
        return false
    }

    /// Computed from bounds/position/anchorPoint per Apple's definition.
    /// LIMITATION: `transform` is ignored — Apple folds the transform into
    /// the returned frame; nothing consumes the transform on Linux yet.
    /// (On Apple, setting frame with a non-identity transform is undefined.)
    open var frame: CGRect {
        get {
            let size = bounds.size
            return CGRect(
                x: position.x - anchorPoint.x * size.width,
                y: position.y - anchorPoint.y * size.height,
                width: size.width,
                height: size.height)
        }
        set {
            bounds.size = newValue.size
            position = CGPoint(
                x: newValue.origin.x + anchorPoint.x * newValue.size.width,
                y: newValue.origin.y + anchorPoint.y * newValue.size.height)
        }
    }

    open var transform: CATransform3D = CATransform3DIdentity
    open var sublayerTransform: CATransform3D = CATransform3DIdentity

    /// The 2D slice of `transform`.
    open func affineTransform() -> CGAffineTransform {
        return CATransform3DGetAffineTransform(transform)
    }

    open func setAffineTransform(_ m: CGAffineTransform) {
        transform = CATransform3DMakeAffineTransform(m)
    }

    // MARK: Appearance (model values; QuillPaint will consume these)

    open var opacity: Float = 1
    open var isHidden: Bool = false
    open var backgroundColor: CGColor?
    /// Opaque black default, per Apple.
    open var borderColor: CGColor? = CGColor.black
    open var borderWidth: CGFloat = 0
    open var cornerRadius: CGFloat = 0
    open var cornerCurve: CALayerCornerCurve = .circular
    open var maskedCorners: CACornerMask = [
        .layerMinXMinYCorner, .layerMaxXMinYCorner,
        .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
    ]
    open var masksToBounds: Bool = false
    open var isDoubleSided: Bool = true
    open var isOpaque: Bool = false
    open var allowsGroupOpacity: Bool = true
    open var allowsEdgeAntialiasing: Bool = false
    open var style: [AnyHashable: Any]?
    open var filters: [Any]?
    open var compositingFilter: Any?
    open var name: String?

    // MARK: Shadow

    /// Opaque black default, per Apple.
    open var shadowColor: CGColor? = CGColor.black
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 3
    open var shadowOffset: CGSize = CGSize(width: 0, height: -3)
    open var shadowPath: CGPath?

    // MARK: Contents

    open var contents: Any?
    open var contentsRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsCenter: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    open var contentsGravity: CALayerContentsGravity = .resize
    open var contentsScale: CGFloat = 1
    open var minificationFilter: CALayerContentsFilter = .linear
    open var magnificationFilter: CALayerContentsFilter = .linear
    open var shouldRasterize: Bool = false
    open var rasterizationScale: CGFloat = 1
    open var drawsAsynchronously: Bool = false
    open var needsDisplayOnBoundsChange: Bool = false
    open var contentsFormat: CALayerContentsFormat = .RGBA8Uint
    open var edgeAntialiasingMask: CAEdgeAntialiasingMask = [
        .layerLeftEdge, .layerRightEdge, .layerBottomEdge, .layerTopEdge,
    ]

    open func preferredFrameSize() -> CGSize {
        return bounds.size
    }

    // MARK: Hierarchy

    private var _sublayers: [CALayer] = []

    /// nil when there are no sublayers, per Apple. Setting replaces the whole
    /// array: old sublayers are detached, new ones adopted in order.
    open var sublayers: [CALayer]? {
        get { return _sublayers.isEmpty ? nil : _sublayers }
        set {
            for layer in _sublayers { layer.superlayer = nil }
            _sublayers.removeAll()
            for layer in newValue ?? [] { addSublayer(layer) }
        }
    }

    open private(set) weak var superlayer: CALayer?

    open var mask: CALayer?

    open weak var delegate: CALayerDelegate?

    open var actions: [String: CAAction]?

    open func addSublayer(_ layer: CALayer) {
        layer.removeFromSuperlayer()
        _sublayers.append(layer)
        layer.superlayer = self
        setNeedsLayout()
    }

    open func insertSublayer(_ layer: CALayer, at idx: UInt32) {
        layer.removeFromSuperlayer()
        let index = min(Int(idx), _sublayers.count)
        _sublayers.insert(layer, at: index)
        layer.superlayer = self
        setNeedsLayout()
    }

    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        layer.removeFromSuperlayer()
        if let sibling = sibling, let index = _sublayers.firstIndex(where: { $0 === sibling }) {
            _sublayers.insert(layer, at: index)
        } else {
            _sublayers.insert(layer, at: 0)
        }
        layer.superlayer = self
        setNeedsLayout()
    }

    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        layer.removeFromSuperlayer()
        if let sibling = sibling, let index = _sublayers.firstIndex(where: { $0 === sibling }) {
            _sublayers.insert(layer, at: index + 1)
        } else {
            _sublayers.append(layer)
        }
        layer.superlayer = self
        setNeedsLayout()
    }

    open func replaceSublayer(_ oldLayer: CALayer, with newLayer: CALayer) {
        guard oldLayer.superlayer === self else { return }
        newLayer.removeFromSuperlayer()
        guard let index = _sublayers.firstIndex(where: { $0 === oldLayer }) else { return }
        oldLayer.superlayer = nil
        _sublayers[index] = newLayer
        newLayer.superlayer = self
        setNeedsLayout()
    }

    open func removeFromSuperlayer() {
        guard let parent = superlayer else { return }
        parent._sublayers.removeAll { $0 === self }
        superlayer = nil
        parent.setNeedsLayout()
    }

    // MARK: Coordinate conversion
    //
    // LIMITATION: conversion ignores `transform`/`sublayerTransform` (nothing
    // applies them yet) but DOES honor bounds.origin scroll offsets, so
    // scroll-layer-style content offsets convert correctly. A nil layer
    // argument means the root (absolute) coordinate space.

    /// Offset from this layer's bounds space to the root coordinate space:
    /// per hop, content shifts by frame.origin - bounds.origin.
    private func absoluteOffset() -> CGPoint {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var node: CALayer? = self
        while let layer = node {
            let frame = layer.frame
            x += frame.origin.x - layer.bounds.origin.x
            y += frame.origin.y - layer.bounds.origin.y
            node = layer.superlayer
        }
        return CGPoint(x: x, y: y)
    }

    open func convert(_ p: CGPoint, from l: CALayer?) -> CGPoint {
        let from = l?.absoluteOffset() ?? .zero
        let to = absoluteOffset()
        return CGPoint(x: p.x + from.x - to.x, y: p.y + from.y - to.y)
    }

    open func convert(_ p: CGPoint, to l: CALayer?) -> CGPoint {
        let from = absoluteOffset()
        let to = l?.absoluteOffset() ?? .zero
        return CGPoint(x: p.x + from.x - to.x, y: p.y + from.y - to.y)
    }

    open func convert(_ r: CGRect, from l: CALayer?) -> CGRect {
        let origin = convert(r.origin, from: l)
        return CGRect(x: origin.x, y: origin.y, width: r.size.width, height: r.size.height)
    }

    open func convert(_ r: CGRect, to l: CALayer?) -> CGRect {
        let origin = convert(r.origin, to: l)
        return CGRect(x: origin.x, y: origin.y, width: r.size.width, height: r.size.height)
    }

    /// Identity on Linux: all layers share one clock. Speed/timeOffset time
    /// warping is handled inside the animation engine instead.
    open func convertTime(_ t: CFTimeInterval, from l: CALayer?) -> CFTimeInterval {
        return t
    }

    open func convertTime(_ t: CFTimeInterval, to l: CALayer?) -> CFTimeInterval {
        return t
    }

    // MARK: Hit testing

    /// `p` is in this layer's own bounds coordinate space.
    open func contains(_ p: CGPoint) -> Bool {
        return CALayer.rect(bounds, contains: p)
    }

    /// `p` is in the SUPERLAYER's coordinate space, per Apple. Hidden layers
    /// are skipped; sublayers are searched topmost-first (later siblings are
    /// frontmost; zPosition is ignored, matching the model-only z-order);
    /// the deepest hit wins; self is returned when the point is contained but
    /// no sublayer claims it.
    open func hitTest(_ p: CGPoint) -> CALayer? {
        guard !isHidden else { return nil }
        let frame = self.frame
        let local = CGPoint(
            x: p.x - frame.origin.x + bounds.origin.x,
            y: p.y - frame.origin.y + bounds.origin.y)
        guard CALayer.rect(bounds, contains: local) else { return nil }
        for sublayer in _sublayers.reversed() {
            if let hit = sublayer.hitTest(local) {
                return hit
            }
        }
        return self
    }

    /// Half-open containment matching CGRectContainsPoint.
    private static func rect(_ r: CGRect, contains p: CGPoint) -> Bool {
        return p.x >= r.origin.x && p.y >= r.origin.y
            && p.x < r.origin.x + r.size.width
            && p.y < r.origin.y + r.size.height
    }

    // MARK: Display bookkeeping
    //
    // There is no backing store on Linux yet, so display() cannot fabricate a
    // CGContext. The needsDisplay flag and the delegate display path are
    // real; rasterization arrives with QuillPaint.

    private var _needsDisplay: Bool = false

    open func setNeedsDisplay() {
        _needsDisplay = true
    }

    /// Dirty-rect granularity is not tracked (no compositor yet); the whole
    /// layer is flagged.
    open func setNeedsDisplay(_ r: CGRect) {
        _needsDisplay = true
    }

    open func needsDisplay() -> Bool {
        return _needsDisplay
    }

    open func displayIfNeeded() {
        guard _needsDisplay else { return }
        _needsDisplay = false
        display()
    }

    /// Forwards to the delegate's display(_:). No CGContext is created here —
    /// delegates that draw via draw(_:in:) will receive contexts once
    /// QuillPaint provides real rasterization.
    open func display() {
        delegate?.display(self)
    }

    /// Called with a real CGContext by future rendering code (or directly by
    /// consumers); forwards to the delegate.
    open func draw(in ctx: CGContext) {
        delegate?.draw(self, in: ctx)
    }

    /// Inert on Linux: there is no rasterizer yet, so nothing is rendered
    /// into the context. Apple's signature is kept so callers type-check.
    open func render(in ctx: CGContext) {
        // Intentionally empty until QuillPaint provides rasterization.
    }

    open class func needsDisplay(forKey key: String) -> Bool {
        // No custom properties trigger redisplay by default, per Apple.
        return false
    }

    // MARK: Layout bookkeeping

    private var _needsLayout: Bool = false

    open func setNeedsLayout() {
        _needsLayout = true
    }

    open func needsLayout() -> Bool {
        return _needsLayout
    }

    /// Apple semantics: climb to the TOPMOST ancestor that needs layout, then
    /// lay out the flagged subtree from there down.
    open func layoutIfNeeded() {
        var target: CALayer = self
        var node = superlayer
        while let layer = node {
            if layer._needsLayout { target = layer }
            node = layer.superlayer
        }
        target.layoutFlaggedSubtree()
    }

    private func layoutFlaggedSubtree() {
        if _needsLayout {
            _needsLayout = false
            layoutSublayers()
        }
        for sublayer in _sublayers {
            sublayer.layoutFlaggedSubtree()
        }
    }

    open func layoutSublayers() {
        delegate?.layoutSublayers(of: self)
    }

    // MARK: Animations
    //
    // Storage is ordered (Telegram-style code relies on animationKeys()
    // order). Timing and completion are owned by QuartzCoreAnimationEngine
    // (CAAnimation.swift), which fires delegate callbacks asynchronously on
    // DispatchQueue.main and calls back into _animationDidComplete(key:) for
    // animations with isRemovedOnCompletion.

    private var animationEntries: [(key: String, animation: CAAnimation)] = []
    private var animationKeyCounter: Int = 0

    open func add(_ anim: CAAnimation, forKey key: String?) {
        let usedKey: String
        if let key = key {
            usedKey = key
            // Adding under an existing key replaces (and cancels) the old
            // animation, per Apple.
            if let index = animationEntries.firstIndex(where: { $0.key == usedKey }) {
                let old = animationEntries.remove(at: index)
                QuartzCoreAnimationEngine.didRemove(old.animation, forKey: old.key, from: self)
            }
        } else {
            animationKeyCounter += 1
            usedKey = "quill.animation.\(animationKeyCounter)"
        }
        animationEntries.append((key: usedKey, animation: anim))
        QuartzCoreAnimationEngine.didAdd(anim, forKey: usedKey, to: self)
    }

    /// Non-Apple convenience kept for existing QuillUI call sites.
    @available(*, deprecated, renamed: "add(_:forKey:)")
    public func add(_ anim: CAAnimation, forKeyPath keyPath: String?) {
        add(anim, forKey: keyPath)
    }

    open func animation(forKey key: String) -> CAAnimation? {
        return animationEntries.first(where: { $0.key == key })?.animation
    }

    open func animationKeys() -> [String]? {
        guard !animationEntries.isEmpty else { return nil }
        return animationEntries.map { $0.key }
    }

    open func removeAnimation(forKey key: String) {
        guard let index = animationEntries.firstIndex(where: { $0.key == key }) else { return }
        let entry = animationEntries.remove(at: index)
        QuartzCoreAnimationEngine.didRemove(entry.animation, forKey: entry.key, from: self)
    }

    open func removeAllAnimations() {
        let entries = animationEntries
        animationEntries.removeAll()
        for entry in entries {
            QuartzCoreAnimationEngine.didRemove(entry.animation, forKey: entry.key, from: self)
        }
    }

    /// Engine → layer: an animation whose isRemovedOnCompletion is true has
    /// finished. Drops only the bookkeeping entry; must NOT re-enter the
    /// engine (the engine already knows it completed).
    internal func _animationDidComplete(key: String) {
        animationEntries.removeAll { $0.key == key }
    }

    /// Engine → layer: this animation OBJECT was re-added elsewhere (Apple
    /// copies on add; this shim reschedules the same object), so this layer's
    /// bookkeeping pair is dead — animationKeys()/animation(forKey:) must stop
    /// reporting it, and deinit must not cancel the new owner's schedule.
    /// Identity-checked so a same-key replace never strips a fresh entry.
    internal func _animationWasDisplaced(key: String, animation: CAAnimation) {
        animationEntries.removeAll { $0.key == key && $0.animation === animation }
    }

    deinit {
        // Never-completing animations (speed <= 0, infinite repeatCount)
        // would otherwise pin their engine entries forever once the layer
        // goes away. Deliberately bypasses the open removeAllAnimations()
        // (no overridable calls from deinit) and fires no delegate
        // callbacks; the engine path never touches the dying layer. The
        // ownership token restricts the cancel to schedules this layer still
        // owns — an animation object re-added to ANOTHER layer must keep
        // running there (the engine re-keyed it to the new owner).
        let ownership = ObjectIdentifier(self)
        for entry in animationEntries {
            QuartzCoreAnimationEngine.cancelForLayerDeinit(entry.animation, ownedBy: ownership)
        }
        animationEntries.removeAll()
    }

    // MARK: Presentation / model

    /// Model == presentation on Linux: with no render server there are no
    /// interpolated in-flight values to snapshot, so the model layer itself
    /// is returned. (Apple returns a copy with animated values applied.)
    open func presentation() -> Self? {
        return self
    }

    open func model() -> Self {
        return self
    }

    // MARK: Actions

    /// Resolution order: delegate → actions dictionary → nil. An NSNull at
    /// either step means "explicitly no action" (Apple contract). NOTE:
    /// implicit actions are not auto-dispatched on property mutation yet;
    /// this lookup serves explicit action(forKey:) callers.
    open func action(forKey event: String) -> CAAction? {
        if let delegateAction = delegate?.action(for: self, forKey: event) {
            return delegateAction is NSNull ? nil : delegateAction
        }
        if let entry = actions?[event] {
            if entry is NSNull { return nil }
            return entry as? CAAction
        }
        return nil
    }

    // MARK: KVO shim

    /// corelibs Foundation has no KVO; some ported code calls this after
    /// mutating layer-adjacent state. Accepted as a harmless no-op hook.
    open func didChangeValue(forKey key: String) {
        // Intentionally empty.
    }

    // MARK: CAMediaTiming conformance (stored, per-layer timing space)

    open var beginTime: CFTimeInterval = 0
    open var duration: CFTimeInterval = 0
    open var speed: Float = 1
    open var timeOffset: CFTimeInterval = 0
    open var repeatCount: Float = 0
    open var repeatDuration: CFTimeInterval = 0
    open var autoreverses: Bool = false
    open var fillMode: CAMediaTimingFillMode = .removed

    fileprivate static func scalar(_ value: Any?) -> CGFloat? {
        if let n = value as? NSNumber { return CGFloat(n.doubleValue) }
        if let v = value as? CGFloat { return v }
        if let v = value as? Double { return CGFloat(v) }
        if let v = value as? Float { return CGFloat(v) }
        if let v = value as? Int { return CGFloat(v) }
        return nil
    }

    fileprivate static func boolean(_ value: Any?) -> Bool? {
        if let n = value as? NSNumber { return n.boolValue }
        if let b = value as? Bool { return b }
        return nil
    }
}

// MARK: - Mini key-value coding
//
// QuillFoundation's NSObject extension owns the Apple-named KVC entry points
// (value(forKey:)/setValue(_:forKey:)/…) — extension methods can be neither
// overridden nor shadowed from another module — and forwards them to the
// QuillKeyValueCoding protocol. CALayer adopts it here with an explicit key
// table: animation code addresses layers by key path constantly, so this is
// load-bearing. Scalars are boxed as NSNumber; geometry/transform values
// travel as their Swift structs. Unknown keys return nil / no-op (no
// NSUnknownKeyException machinery, and probing optional keys is common).

extension CALayer: QuillKeyValueCoding {

    public func quillValue(forKey key: String) -> Any? {
        switch key {
        case "opacity": return NSNumber(value: opacity)
        case "position": return position
        case "bounds": return bounds
        case "frame": return frame
        case "transform": return transform
        case "sublayerTransform": return sublayerTransform
        case "cornerRadius": return NSNumber(value: Double(cornerRadius))
        case "zPosition": return NSNumber(value: Double(zPosition))
        case "anchorPoint": return anchorPoint
        case "backgroundColor": return backgroundColor
        case "hidden": return NSNumber(value: isHidden)
        case "shadowOpacity": return NSNumber(value: shadowOpacity)
        case "shadowRadius": return NSNumber(value: Double(shadowRadius))
        default: return nil
        }
    }

    public func quillValue(forKeyPath keyPath: String) -> Any? {
        switch keyPath {
        case "position.x": return NSNumber(value: Double(position.x))
        case "position.y": return NSNumber(value: Double(position.y))
        case "bounds.origin": return bounds.origin
        case "bounds.origin.x": return NSNumber(value: Double(bounds.origin.x))
        case "bounds.origin.y": return NSNumber(value: Double(bounds.origin.y))
        case "bounds.size": return bounds.size
        case "bounds.size.width": return NSNumber(value: Double(bounds.size.width))
        case "bounds.size.height": return NSNumber(value: Double(bounds.size.height))
        // Transform sub-key-paths animation code reads constantly. Derived
        // from the matrix the same way Apple's CAValueFunction family maps
        // them (scale from m11/m22, z-rotation from atan2(m12, m11),
        // translation from m41/m42); shear-free assumptions documented.
        case "transform.scale":
            return NSNumber(value: Double((transform.m11 + transform.m22) / 2))
        case "transform.scale.x": return NSNumber(value: Double(transform.m11))
        case "transform.scale.y": return NSNumber(value: Double(transform.m22))
        case "transform.scale.z": return NSNumber(value: Double(transform.m33))
        case "transform.rotation", "transform.rotation.z":
            return NSNumber(value: Double(atan2(Double(transform.m12), Double(transform.m11))))
        case "transform.translation.x": return NSNumber(value: Double(transform.m41))
        case "transform.translation.y": return NSNumber(value: Double(transform.m42))
        case "transform.translation.z": return NSNumber(value: Double(transform.m43))
        default: return quillValue(forKey: keyPath)
        }
    }

    public func quillSetValue(_ value: Any?, forKey key: String) {
        switch key {
        case "opacity":
            if let v = CALayer.scalar(value) { opacity = Float(v) }
        case "position":
            if let v = value as? CGPoint { position = v }
        case "bounds":
            if let v = value as? CGRect { bounds = v }
        case "frame":
            if let v = value as? CGRect { frame = v }
        case "transform":
            if let v = value as? CATransform3D {
                transform = v
            } else if let boxed = value as? NSValue {
                // Animation code conventionally boxes transforms in NSValue.
                transform = boxed.caTransform3DValue
            }
        case "sublayerTransform":
            if let v = value as? CATransform3D {
                sublayerTransform = v
            } else if let boxed = value as? NSValue {
                sublayerTransform = boxed.caTransform3DValue
            }
        case "cornerRadius":
            if let v = CALayer.scalar(value) { cornerRadius = v }
        case "zPosition":
            if let v = CALayer.scalar(value) { zPosition = v }
        case "anchorPoint":
            if let v = value as? CGPoint { anchorPoint = v }
        case "backgroundColor":
            if value == nil || value is NSNull {
                backgroundColor = nil
            } else if let v = value as? CGColor {
                backgroundColor = v
            }
        case "hidden":
            if let v = CALayer.boolean(value) { isHidden = v }
        case "shadowOpacity":
            if let v = CALayer.scalar(value) { shadowOpacity = Float(v) }
        case "shadowRadius":
            if let v = CALayer.scalar(value) { shadowRadius = v }
        default:
            break // Unknown key: deliberate no-op (no exception machinery).
        }
    }

    public func quillSetValue(_ value: Any?, forKeyPath keyPath: String) {
        switch keyPath {
        case "position.x":
            if let v = CALayer.scalar(value) { position.x = v }
        case "position.y":
            if let v = CALayer.scalar(value) { position.y = v }
        case "bounds.origin":
            if let v = value as? CGPoint { bounds.origin = v }
        case "bounds.origin.x":
            if let v = CALayer.scalar(value) { bounds.origin.x = v }
        case "bounds.origin.y":
            if let v = CALayer.scalar(value) { bounds.origin.y = v }
        case "bounds.size":
            if let v = value as? CGSize { bounds.size = v }
        case "bounds.size.width":
            if let v = CALayer.scalar(value) { bounds.size.width = v }
        case "bounds.size.height":
            if let v = CALayer.scalar(value) { bounds.size.height = v }
        // Transform sub-key-path WRITES, mirroring the getters above (Apple's
        // CAValueFunction mapping; same shear-free assumption). Rotation and
        // scale rebuild the matrix from the decomposed scale/rotation/
        // translation; translation writes go straight to m41/m42/m43.
        case "transform.scale":
            if let v = CALayer.scalar(value) { quillRebuildTransform(scaleX: v, scaleY: v, scaleZ: v) }
        case "transform.scale.x":
            if let v = CALayer.scalar(value) { quillRebuildTransform(scaleX: v) }
        case "transform.scale.y":
            if let v = CALayer.scalar(value) { quillRebuildTransform(scaleY: v) }
        case "transform.scale.z":
            if let v = CALayer.scalar(value) { quillRebuildTransform(scaleZ: v) }
        case "transform.rotation", "transform.rotation.z":
            if let v = CALayer.scalar(value) { quillRebuildTransform(rotationZ: v) }
        case "transform.translation.x":
            if let v = CALayer.scalar(value) { transform.m41 = v }
        case "transform.translation.y":
            if let v = CALayer.scalar(value) { transform.m42 = v }
        case "transform.translation.z":
            if let v = CALayer.scalar(value) { transform.m43 = v }
        default:
            quillSetValue(value, forKey: keyPath)
        }
    }

    /// Rebuilds `transform` with the given components replaced, decomposing
    /// the current matrix the same way the transform.* getters do (scale from
    /// the basis-vector magnitudes m11/m22/m33, z-rotation from atan2(m12,
    /// m11), translation from m41/m42/m43 — valid under the documented
    /// shear-free assumption).
    private func quillRebuildTransform(
        scaleX: CGFloat? = nil, scaleY: CGFloat? = nil, scaleZ: CGFloat? = nil,
        rotationZ: CGFloat? = nil
    ) {
        let currentRotation = CGFloat(atan2(Double(transform.m12), Double(transform.m11)))
        let cosR = CGFloat(cos(Double(currentRotation)))
        // Recover signed scale: m11 = sx*cos(r), so divide out the rotation
        // unless cos(r) ~ 0, where m12 = sx*sin(r) is the stable choice.
        let sinR = CGFloat(sin(Double(currentRotation)))
        let currentSX = abs(cosR) > 0.0001 ? transform.m11 / cosR : transform.m12 / sinR
        let currentSY = abs(cosR) > 0.0001 ? transform.m22 / cosR : -transform.m21 / sinR
        let sx = scaleX ?? currentSX
        let sy = scaleY ?? currentSY
        let sz = scaleZ ?? transform.m33
        let rz = rotationZ ?? currentRotation
        let tx = transform.m41, ty = transform.m42, tz = transform.m43
        var rebuilt = CATransform3DMakeRotation(rz, 0, 0, 1)
        rebuilt = CATransform3DConcat(CATransform3DMakeScale(sx, sy, sz), rebuilt)
        rebuilt.m41 = tx; rebuilt.m42 = ty; rebuilt.m43 = tz
        transform = rebuilt
    }

}
