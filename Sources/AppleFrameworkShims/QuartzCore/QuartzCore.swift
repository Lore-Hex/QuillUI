//
// QuillUI Linux shim for `QuartzCore`.
//
// SignalServiceKit uses QuartzCore mostly for monotonic timing
// (CACurrentMediaTime, in benchmarks / batch pacing) and, in two places, a
// CADisplayLink and a CAGradientLayer. CACurrentMediaTime is implemented
// faithfully via ProcessInfo.systemUptime (a monotonic clock, available on
// Linux); the layer/display-link types are inert (no rendering or frame
// callbacks on Linux). CGRect/CGPoint/CGContext come from QuillFoundation.
//
import Foundation
// Plain import: re-exporting all of corelibs CoreFoundation leaks its stub
// CFString/CFArray classes into every `import Cocoa` scope and collides with
// the bridged CF typealiases there (e.g. ServiceManagement.CFString). Only
// the CF names this shim's API surface needs are re-exported below.
import CoreFoundation
@_exported import Metal
@_exported import QuillFoundation

public typealias CFTimeInterval = CoreFoundation.CFTimeInterval

// MARK: - CACurrentMediaTime
//
// Real QuartzCore returns mach_absolute_time converted to seconds -- a monotonic
// clock. ProcessInfo.systemUptime is the equivalent monotonic source on Linux,
// so SSK's elapsed-time measurements are accurate (not stubbed).

public func CACurrentMediaTime() -> CFTimeInterval {
    ProcessInfo.processInfo.systemUptime
}

public let kCAOnOrderIn = "onOrderIn"
public let kCAOnOrderOut = "onOrderOut"

// MARK: - CALayer / CAGradientLayer
//
// Inert layer types. AvatarBuilder builds a gradient layer and renders it into
// a graphics context; on Linux render(in:) is a no-op (the avatar gradient is
// not painted until a real layer compositor is bridged).

open class CALayer: NSObject {
    open var frame: CGRect = .zero
    open var bounds: CGRect = .zero
    open var position: CGPoint = .zero
    open var anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    open var zPosition: CGFloat = 0
    open var opacity: Float = 1
    open var contentsScale: CGFloat = 1
    open var isOpaque: Bool = false
    open var shouldRasterize: Bool = false
    open var rasterizationScale: CGFloat = 1
    open var cornerRadius: CGFloat = 0
    open var masksToBounds: Bool = false
    open var isDoubleSided: Bool = true
    open var backgroundColor: CGColor?
    open var borderColor: CGColor?
    open var borderWidth: CGFloat = 0
    open var contents: Any?
    open var contentsRect: CGRect = CGRect(origin: .zero, size: CGSize(width: 1, height: 1))
    open var contentsGravity: CALayerContentsGravity = .resize
    open var shadowColor: CGColor?
    open var shadowOpacity: Float = 0
    open var shadowRadius: CGFloat = 0
    open var shadowOffset: CGSize = .zero
    open var sublayers: [CALayer]?
    public private(set) weak var superlayer: CALayer?
    open var mask: CALayer?
    open var actions: [String: Any]?
    public weak var delegate: CALayerDelegate?
    open var transform: CATransform3D = CATransform3DIdentity
    open var sublayerTransform: CATransform3D = CATransform3DIdentity
    open var name: String?
    open var filters: [Any]?
    open var compositingFilter: Any?
    open var cornerCurve: CALayerCornerCurve = .circular
    open var isHidden: Bool = false
    open var drawsAsynchronously: Bool = false

    public override init() { super.init() }

    public init(layer: Any) {
        _ = layer
        super.init()
    }

    open class func needsDisplay(forKey key: String) -> Bool {
        _ = key
        return false
    }

    // `ctx` is untyped: CGContext is not yet provided by the CoreGraphics shim,
    // and render is inert anyway (no compositor on Linux). When a CGContext
    // type lands this can be tightened to `render(in ctx: CGContext)`.
    open func render(in ctx: Any) {}
    open func draw(in ctx: CGContext) {}
    open func display() {}
    open func affineTransform() -> CGAffineTransform { .identity }
    open func setAffineTransform(_ transform: CGAffineTransform) { _ = transform }
    open func addSublayer(_ layer: CALayer) {
        var current = sublayers ?? []
        layer.superlayer = self
        current.append(layer)
        sublayers = current
    }
    open func insertSublayer(_ layer: CALayer, at index: UInt32) {
        var current = sublayers ?? []
        layer.superlayer = self
        current.insert(layer, at: min(Int(index), current.count))
        sublayers = current
    }
    open func insertSublayer(_ layer: CALayer, below sibling: CALayer?) {
        var current = sublayers ?? []
        layer.superlayer = self
        if let sibling, let index = current.firstIndex(where: { $0 === sibling }) {
            current.insert(layer, at: index)
        } else {
            current.append(layer)
        }
        sublayers = current
    }
    open func insertSublayer(_ layer: CALayer, above sibling: CALayer?) {
        var current = sublayers ?? []
        layer.superlayer = self
        if let sibling, let index = current.firstIndex(where: { $0 === sibling }) {
            current.insert(layer, at: min(index + 1, current.count))
        } else {
            current.append(layer)
        }
        sublayers = current
    }
    open func removeFromSuperlayer() {
        superlayer?.sublayers?.removeAll { $0 === self }
        superlayer = nil
    }
    open func didChangeValue(forKey key: String) { _ = key }
    open func action(forKey event: String) -> CAAction? {
        _ = event
        return nil
    }
    open func setNeedsDisplay() {}
    open func needsDisplay() -> Bool { false }
    open func displayIfNeeded() {}
    open func layoutIfNeeded() {}
    open func add(_ animation: CAAnimation, forKey key: String?) {
        animation.delegate?.animationDidStop(animation, finished: true)
    }
    open func add(_ animation: CAAnimation, forKeyPath keyPath: String?) {
        add(animation, forKey: keyPath)
    }
    open func animation(forKey key: String) -> CAAnimation? {
        _ = key
        return nil
    }
    open func animationKeys() -> [String]? { nil }
    open func convertTime(_ time: CFTimeInterval, from layer: CALayer?) -> CFTimeInterval {
        _ = layer
        return time
    }
    open func removeAnimation(forKey key: String) {
        _ = key
    }
    open func removeAllAnimations() {}
    open func presentation() -> Self? { self }
}

public struct CALayerCornerCurve: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let circular = CALayerCornerCurve(rawValue: "circular")
    public static let continuous = CALayerCornerCurve(rawValue: "continuous")
}

public protocol CALayerDelegate: AnyObject {
    func display(_ layer: CALayer)
    func draw(_ layer: CALayer, in ctx: CGContext)
    func layoutSublayers(of layer: CALayer)
    func action(for layer: CALayer, forKey event: String) -> CAAction?
}

open class CAMetalLayer: CALayer {
    open var device: MTLDevice?
    open var pixelFormat: MTLPixelFormat = .bgra8Unorm
    open var framebufferOnly: Bool = true
    open var presentsWithTransaction: Bool = false
    open var drawableSize: CGSize = CGSize(width: 1, height: 1)

    open func nextDrawable() -> CAMetalDrawable? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: max(1, Int(drawableSize.width)),
            height: max(1, Int(drawableSize.height)),
            mipmapped: false
        )
        let texture = device?.makeTexture(descriptor: descriptor) ?? QuillMTLTexture(descriptor: descriptor)
        return QuillMetalDrawable(texture: texture)
    }
}

public extension CALayerDelegate {
    func display(_ layer: CALayer) {}
    func draw(_ layer: CALayer, in ctx: CGContext) {}
    func layoutSublayers(of layer: CALayer) {}
    func action(for layer: CALayer, forKey event: String) -> CAAction? { nil }
}

public protocol CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?)
}

extension NSNull: CAAction {
    public func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
        _ = (event, anObject, dict)
    }
}

public struct CALayerContentsGravity: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let resize = CALayerContentsGravity(rawValue: "resize")
    public static let resizeAspect = CALayerContentsGravity(rawValue: "resizeAspect")
    public static let resizeAspectFill = CALayerContentsGravity(rawValue: "resizeAspectFill")
    public static let center = CALayerContentsGravity(rawValue: "center")
    public static let top = CALayerContentsGravity(rawValue: "top")
    public static let bottom = CALayerContentsGravity(rawValue: "bottom")
    public static let left = CALayerContentsGravity(rawValue: "left")
    public static let right = CALayerContentsGravity(rawValue: "right")
}

public struct CATransform3D: Equatable, Sendable {
    public var m11: CGFloat; public var m12: CGFloat; public var m13: CGFloat; public var m14: CGFloat
    public var m21: CGFloat; public var m22: CGFloat; public var m23: CGFloat; public var m24: CGFloat
    public var m31: CGFloat; public var m32: CGFloat; public var m33: CGFloat; public var m34: CGFloat
    public var m41: CGFloat; public var m42: CGFloat; public var m43: CGFloat; public var m44: CGFloat

    public init(
        m11: CGFloat, m12: CGFloat, m13: CGFloat, m14: CGFloat,
        m21: CGFloat, m22: CGFloat, m23: CGFloat, m24: CGFloat,
        m31: CGFloat, m32: CGFloat, m33: CGFloat, m34: CGFloat,
        m41: CGFloat, m42: CGFloat, m43: CGFloat, m44: CGFloat
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    public static let identity = CATransform3D(
        m11: 1, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: 1, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: 1, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1
    )
}

public let CATransform3DIdentity = CATransform3D.identity

public func CATransform3DMakeScale(_ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    CATransform3D(
        m11: sx, m12: 0, m13: 0, m14: 0,
        m21: 0, m22: sy, m23: 0, m24: 0,
        m31: 0, m32: 0, m33: sz, m34: 0,
        m41: 0, m42: 0, m43: 0, m44: 1
    )
}

public func CATransform3DMakeTranslation(_ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    CATransform3DTranslate(CATransform3DIdentity, tx, ty, tz)
}

public func CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    CATransform3DRotate(CATransform3DIdentity, angle, x, y, z)
}

public func CATransform3DTranslate(_ t: CATransform3D, _ tx: CGFloat, _ ty: CGFloat, _ tz: CGFloat) -> CATransform3D {
    var result = t
    result.m41 += tx
    result.m42 += ty
    result.m43 += tz
    return result
}

public func CATransform3DScale(_ t: CATransform3D, _ sx: CGFloat, _ sy: CGFloat, _ sz: CGFloat) -> CATransform3D {
    var result = t
    result.m11 *= sx
    result.m22 *= sy
    result.m33 *= sz
    return result
}

public func CATransform3DRotate(_ t: CATransform3D, _ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CATransform3D {
    _ = (angle, x, y, z)
    return t
}

public extension NSValue {
    convenience init(caTransform3D transform: CATransform3D) {
        _ = transform
        self.init()
    }
}

open class CAGradientLayer: CALayer {
    public struct LayerType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let axial = LayerType(rawValue: "axial")
        public static let radial = LayerType(rawValue: "radial")
        public static let conic = LayerType(rawValue: "conic")
    }

    public var colors: [Any]?
    public var locations: [NSNumber]?
    public var startPoint: CGPoint = CGPoint(x: 0.5, y: 0.0)
    public var endPoint: CGPoint = CGPoint(x: 0.5, y: 1.0)
    public var type: LayerType = .axial
}

open class CAShapeLayer: CALayer {
    public struct FillRule: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let nonZero = FillRule(rawValue: "non-zero")
        public static let evenOdd = FillRule(rawValue: "even-odd")
    }

    public var path: CGPath?
    public var fillColor: Any?
    public var strokeColor: Any?
    public var fillRule: FillRule = .nonZero
    public var lineWidth: CGFloat = 1
    public var lineCap: String = ""
    public var lineJoin: String = ""
    public var strokeStart: CGFloat = 0
    public var strokeEnd: CGFloat = 1
}

open class CATextLayer: CALayer {
    public var string: Any?
    public var font: Any?
    public var fontSize: CGFloat = 12
    public var foregroundColor: CGColor?
    public var alignmentMode: String = ""
    public var isWrapped: Bool = false
    public var truncationMode: String = ""
}

public final class CAEmitterCell: NSObject {
    public var name: String?
    public var contents: Any?
    public var contentsScale: CGFloat = 1
    public var birthRate: Float = 0
    public var lifetime: Float = 0
    public var lifetimeRange: Float = 0
    public var velocity: CGFloat = 0
    public var velocityRange: CGFloat = 0
    public var scale: CGFloat = 1
    public var scaleRange: CGFloat = 0
    public var scaleSpeed: CGFloat = 0
    public var alphaRange: Float = 0
    public var alphaSpeed: Float = 0
    public var emissionRange: CGFloat = 0
    public var color: CGColor?
    public override init() { super.init() }
}

public final class CAEmitterLayer: CALayer {
    public var emitterCells: [CAEmitterCell]?
    public var emitterPosition: CGPoint = .zero
    public var emitterSize: CGSize = .zero
    public var emitterShape: CAEmitterLayerEmitterShape = .point
    public var emitterMode: CAEmitterLayerEmitterMode = .points
    public var birthRate: Float = 1
    public var lifetime: Float = 1
    public var seed: UInt32 = 0
    public var allowsGroupOpacity: Bool = false
}

public struct CAEmitterLayerEmitterShape: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let point = CAEmitterLayerEmitterShape(rawValue: "point")
    public static let line = CAEmitterLayerEmitterShape(rawValue: "line")
    public static let rectangle = CAEmitterLayerEmitterShape(rawValue: "rectangle")
    public static let cuboid = CAEmitterLayerEmitterShape(rawValue: "cuboid")
    public static let circle = CAEmitterLayerEmitterShape(rawValue: "circle")
    public static let sphere = CAEmitterLayerEmitterShape(rawValue: "sphere")
}

public struct CAEmitterLayerEmitterMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let points = CAEmitterLayerEmitterMode(rawValue: "points")
    public static let outline = CAEmitterLayerEmitterMode(rawValue: "outline")
    public static let surface = CAEmitterLayerEmitterMode(rawValue: "surface")
    public static let volume = CAEmitterLayerEmitterMode(rawValue: "volume")
}

public protocol CAAnimationDelegate: AnyObject {
    func animationDidStart(_ anim: CAAnimation)
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool)
}

public extension CAAnimationDelegate {
    func animationDidStart(_ anim: CAAnimation) {}
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {}
}

public struct CAMediaTimingFunctionName: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
}

public struct CAMediaTimingFillMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let removed = CAMediaTimingFillMode(rawValue: "removed")
    public static let forwards = CAMediaTimingFillMode(rawValue: "forwards")
    public static let backwards = CAMediaTimingFillMode(rawValue: "backwards")
    public static let both = CAMediaTimingFillMode(rawValue: "both")
}

public final class CAMediaTimingFunction: NSObject {
    private var controlPoints: (Float, Float, Float, Float) = (0, 0, 1, 1)

    public init(name: CAMediaTimingFunctionName) {
        _ = name
        super.init()
    }

    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
        controlPoints = (c1x, c1y, c2x, c2y)
        super.init()
    }

    public func getControlPoint(at index: Int, values ptr: UnsafeMutablePointer<Float>) {
        let points = [controlPoints.0, controlPoints.1, controlPoints.2, controlPoints.3]
        ptr.pointee = points.indices.contains(index) ? points[index] : 0
        ptr.advanced(by: 1).pointee = points.indices.contains(index + 1) ? points[index + 1] : 0
    }
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

open class CAAnimation: NSObject {
    public weak var delegate: CAAnimationDelegate?
    public var duration: CFTimeInterval = 0
    public var beginTime: CFTimeInterval = 0
    public var timeOffset: CFTimeInterval = 0
    public var speed: Float = 1
    public var repeatCount: Float = 0
    public var autoreverses: Bool = false
    public var isRemovedOnCompletion: Bool = true
    public var fillMode: CAMediaTimingFillMode = .removed

    public override init() {
        super.init()
    }
}

open class CABasicAnimation: CAAnimation {
    public var keyPath: String?
    public var fromValue: Any?
    public var toValue: Any?
    public var byValue: Any?
    public var timingFunction: CAMediaTimingFunction?
    public var isAdditive: Bool = false

    public init(keyPath: String?) {
        self.keyPath = keyPath
        super.init()
    }

    public override init() {
        super.init()
    }
}

open class CAKeyframeAnimation: CAAnimation {
    public var keyPath: String?
    public var values: [Any]?
    public var keyTimes: [NSNumber]?
    public var timingFunction: CAMediaTimingFunction?
    public var timingFunctions: [CAMediaTimingFunction]?
    public var calculationMode: CAAnimationCalculationMode = .linear
    public var path: CGPath?
    public var isAdditive: Bool = false

    public init(keyPath: String?) {
        self.keyPath = keyPath
        super.init()
    }

    public override init() {
        super.init()
    }
}

open class CATransition: CAAnimation {
    public var type: CATransitionType = .fade
    public var subtype: CATransitionSubtype?
    public var timingFunction: CAMediaTimingFunction?
}

public final class CASpringAnimation: CABasicAnimation {
    public var mass: CGFloat = 1
    public var stiffness: CGFloat = 100
    public var damping: CGFloat = 10
    public var initialVelocity: CGFloat = 0
    public var settlingDuration: CFTimeInterval { duration }
}

public enum CATransaction {
    public static func begin() {}
    public static func commit() {}
    public static func flush() {}
    public static func setDisableActions(_ flag: Bool) { _ = flag }
    public static func disableActions() -> Bool { false }
    public static func setAnimationDuration(_ duration: CFTimeInterval) { _ = duration }
    public static func animationDuration() -> CFTimeInterval { 0 }
    public static func setCompletionBlock(_ block: (() -> Void)?) {
        block?()
    }
}

// MARK: - CADisplayLink
//
// Inert: no frame callbacks fire on Linux. `selector` is untyped (Any) so it
// accepts the same-module Selector token SSK passes without depending on it.

public final class CADisplayLink {
    public var isPaused: Bool = false
    public var preferredFramesPerSecond: Int = 0
    public var timestamp: CFTimeInterval = 0
    public var duration: CFTimeInterval = 0

    public init(target: Any, selector: Any) {}

    public func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func remove(from runloop: RunLoop, forMode mode: RunLoop.Mode) {}
    public func invalidate() {}
}
