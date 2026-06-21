//
//  CALayerSubclasses.swift
//  QuartzCore — QuillUI Apple-framework shim for Linux (QuillOS)
//
//  Specialized CALayer subclasses and their string-constant companion types:
//
//    - CAShapeLayer      + CAShapeLayerFillRule / CAShapeLayerLineCap /
//                          CAShapeLayerLineJoin
//    - CAGradientLayer   + CAGradientLayerType
//    - CATextLayer       + CATextLayerAlignmentMode / CATextLayerTruncationMode
//    - CAEmitterCell
//    - CAEmitterLayer    + CAEmitterLayerEmitterShape / CAEmitterLayerEmitterMode /
//                          CAEmitterLayerRenderMode
//    - CAReplicatorLayer
//    - CAScrollLayer     + CAScrollLayerScrollMode
//    - CAMetalLayer
//
//  Honest Linux semantics: this is a functional MODEL layer, not a renderer.
//  Properties carry Apple's real types (CGPath?, CGColor?, [NSNumber]?, ...),
//  geometry math is real, and every class here participates fully in the
//  CALayer hierarchy, CATransaction semantics, and the animation engine
//  implemented by sibling files (CALayer.swift / CAAnimation.swift). There is
//  NO pixel rendering or compositing on Linux yet — rasterization of shapes,
//  gradients, text, particles, replicas, and Metal drawables arrives later
//  via QuillPaint, which will consume the model state stored here. Where an
//  Apple default cannot be reproduced faithfully without a renderer (e.g.
//  CAShapeLayer.fillColor's opaque black), the deviation is called out inline.
//
//  These classes are `open` (matching Apple) so heavy subclassers
//  (Telegram-iOS-style code) compile and behave; the previous shim's `final`
//  on the emitter classes broke them.
//

import Foundation
import Metal

// MARK: - CAShapeLayer string constants

/// Fill rule constants for `CAShapeLayer.fillRule`.
public struct CAShapeLayerFillRule: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let nonZero = CAShapeLayerFillRule(rawValue: "non-zero")
    public static let evenOdd = CAShapeLayerFillRule(rawValue: "even-odd")
}

/// Line cap constants for `CAShapeLayer.lineCap`.
public struct CAShapeLayerLineCap: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let butt = CAShapeLayerLineCap(rawValue: "butt")
    public static let round = CAShapeLayerLineCap(rawValue: "round")
    public static let square = CAShapeLayerLineCap(rawValue: "square")
}

/// Line join constants for `CAShapeLayer.lineJoin`.
public struct CAShapeLayerLineJoin: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let miter = CAShapeLayerLineJoin(rawValue: "miter")
    public static let round = CAShapeLayerLineJoin(rawValue: "round")
    public static let bevel = CAShapeLayerLineJoin(rawValue: "bevel")
}

// MARK: - CAShapeLayer

/// A layer that draws a cubic Bezier spline in its coordinate space.
///
/// Model-only on Linux today: the path plus stroke/fill state is stored with
/// Apple's real types so geometry and animation logic in consumers runs
/// correctly; QuillPaint will rasterize `path` later.
open class CAShapeLayer: CALayer {
    /// The path defining the shape. Animatable on Apple; stored model state
    /// here.
    open var path: CGPath?

    /// The color used to fill the path. Opaque black default, per Apple.
    open var fillColor: CGColor? = CGColor.black

    open var fillRule: CAShapeLayerFillRule = .nonZero

    /// The color used to stroke the path. Apple's default is `nil` (no
    /// stroke), which the shim matches.
    open var strokeColor: CGColor?

    /// Relative location (0...1) at which to begin stroking the path.
    open var strokeStart: CGFloat = 0
    /// Relative location (0...1) at which to stop stroking the path.
    open var strokeEnd: CGFloat = 1

    open var lineWidth: CGFloat = 1
    open var miterLimit: CGFloat = 10
    open var lineCap: CAShapeLayerLineCap = .butt
    open var lineJoin: CAShapeLayerLineJoin = .miter
    open var lineDashPhase: CGFloat = 0
    open var lineDashPattern: [NSNumber]?

    public override init() { super.init() }

    /// Apple's built-in subclasses copy their own state in init(layer:) —
    /// the contract custom subclasses rely on when they override it and
    /// call super.
    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAShapeLayer else { return }
        path = other.path
        fillColor = other.fillColor
        fillRule = other.fillRule
        strokeColor = other.strokeColor
        strokeStart = other.strokeStart
        strokeEnd = other.strokeEnd
        lineWidth = other.lineWidth
        miterLimit = other.miterLimit
        lineCap = other.lineCap
        lineJoin = other.lineJoin
        lineDashPhase = other.lineDashPhase
        lineDashPattern = other.lineDashPattern
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "path": return path
        case "fillColor": return fillColor
        case "fillRule": return fillRule
        case "strokeColor": return strokeColor
        case "strokeStart": return NSNumber(value: Double(strokeStart))
        case "strokeEnd": return NSNumber(value: Double(strokeEnd))
        case "lineWidth": return NSNumber(value: Double(lineWidth))
        case "miterLimit": return NSNumber(value: Double(miterLimit))
        case "lineCap": return lineCap
        case "lineJoin": return lineJoin
        case "lineDashPhase": return NSNumber(value: Double(lineDashPhase))
        case "lineDashPattern": return lineDashPattern
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "path":
            path = value as? CGPath
        case "fillColor":
            fillColor = value is NSNull ? nil : value as? CGColor
        case "fillRule":
            if let v = value as? CAShapeLayerFillRule { fillRule = v }
            else if let raw = value as? String { fillRule = CAShapeLayerFillRule(rawValue: raw) }
        case "strokeColor":
            strokeColor = value is NSNull ? nil : value as? CGColor
        case "strokeStart":
            if let v = CALayer.scalar(value) { strokeStart = v }
        case "strokeEnd":
            if let v = CALayer.scalar(value) { strokeEnd = v }
        case "lineWidth":
            if let v = CALayer.scalar(value) { lineWidth = v }
        case "miterLimit":
            if let v = CALayer.scalar(value) { miterLimit = v }
        case "lineCap":
            if let v = value as? CAShapeLayerLineCap { lineCap = v }
            else if let raw = value as? String { lineCap = CAShapeLayerLineCap(rawValue: raw) }
        case "lineJoin":
            if let v = value as? CAShapeLayerLineJoin { lineJoin = v }
            else if let raw = value as? String { lineJoin = CAShapeLayerLineJoin(rawValue: raw) }
        case "lineDashPhase":
            if let v = CALayer.scalar(value) { lineDashPhase = v }
        case "lineDashPattern":
            lineDashPattern = value as? [NSNumber]
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

extension CAShapeLayer {
    /// Back-compat: the previous shim nested the fill-rule type as
    /// `CAShapeLayer.FillRule`. Apple's real name is the top-level
    /// `CAShapeLayerFillRule`; keep old call sites compiling.
    public typealias FillRule = CAShapeLayerFillRule
}

// MARK: - CAGradientLayer

/// Gradient style constants for `CAGradientLayer.type`.
public struct CAGradientLayerType: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let axial = CAGradientLayerType(rawValue: "axial")
    public static let radial = CAGradientLayerType(rawValue: "radial")
    public static let conic = CAGradientLayerType(rawValue: "conic")
}

/// A layer that draws a color gradient over its background color.
///
/// Model-only on Linux today: stops/geometry are stored faithfully for
/// QuillPaint to consume later.
open class CAGradientLayer: CALayer {
    /// An array of CGColor objects defining the gradient stops. Typed `[Any]?`
    /// to match Apple's signature exactly.
    open var colors: [Any]?

    /// Optional stop locations, each in 0...1, monotonically increasing.
    open var locations: [NSNumber]?

    /// Start point in the unit coordinate space. Apple default (0.5, 0).
    open var startPoint: CGPoint = CGPoint(x: 0.5, y: 0)
    /// End point in the unit coordinate space. Apple default (0.5, 1).
    open var endPoint: CGPoint = CGPoint(x: 0.5, y: 1)

    open var type: CAGradientLayerType = .axial

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAGradientLayer else { return }
        colors = other.colors
        locations = other.locations
        startPoint = other.startPoint
        endPoint = other.endPoint
        type = other.type
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "colors": return colors
        case "locations": return locations
        case "startPoint": return startPoint
        case "endPoint": return endPoint
        case "type": return type
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "colors":
            colors = value as? [Any]
        case "locations":
            locations = value as? [NSNumber]
        case "startPoint":
            if let v = value as? CGPoint { startPoint = v }
        case "endPoint":
            if let v = value as? CGPoint { endPoint = v }
        case "type":
            if let v = value as? CAGradientLayerType { type = v }
            else if let raw = value as? String { type = CAGradientLayerType(rawValue: raw) }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

extension CAGradientLayer {
    /// Back-compat: the previous shim nested this as
    /// `CAGradientLayer.LayerType` and in-repo code may reference it. Apple's
    /// real name is the top-level `CAGradientLayerType`.
    public typealias LayerType = CAGradientLayerType
}

// MARK: - CATextLayer string constants

/// Alignment constants for `CATextLayer.alignmentMode`.
public struct CATextLayerAlignmentMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let natural = CATextLayerAlignmentMode(rawValue: "natural")
    public static let left = CATextLayerAlignmentMode(rawValue: "left")
    public static let right = CATextLayerAlignmentMode(rawValue: "right")
    public static let center = CATextLayerAlignmentMode(rawValue: "center")
    public static let justified = CATextLayerAlignmentMode(rawValue: "justified")
}

/// Truncation constants for `CATextLayer.truncationMode`.
public struct CATextLayerTruncationMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let `none` = CATextLayerTruncationMode(rawValue: "none")
    public static let start = CATextLayerTruncationMode(rawValue: "start")
    public static let end = CATextLayerTruncationMode(rawValue: "end")
    public static let middle = CATextLayerTruncationMode(rawValue: "middle")
}

// MARK: - CATextLayer

/// A layer that provides simple text layout and rendering of plain or
/// attributed strings.
///
/// Model-only on Linux today: text content, font, and layout attributes are
/// stored faithfully; QuillPaint (with a real text shaper) draws them later.
open class CATextLayer: CALayer {
    /// The text to render — a String or NSAttributedString, per Apple.
    open var string: Any?

    /// The font. On Apple this is a CTFont, CGFont, or font-name string;
    /// typed `Any?` to match Apple's surface (CFTypeRef bridges as Any).
    open var font: Any?

    /// The font point size. Apple's documented default is 36 — the previous
    /// shim wrongly defaulted to 12; fixed here.
    open var fontSize: CGFloat = 36

    /// The text color. Opaque white default, per Apple.
    open var foregroundColor: CGColor? = CGColor.white

    /// Whether the text is wrapped to fit the layer bounds. Apple default
    /// false.
    open var isWrapped: Bool = false

    open var truncationMode: CATextLayerTruncationMode = .none
    open var alignmentMode: CATextLayerAlignmentMode = .natural

    /// Apple default false. No-op on Linux until rasterization exists.
    open var allowsFontSubpixelQuantization: Bool = false

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CATextLayer else { return }
        string = other.string
        font = other.font
        fontSize = other.fontSize
        foregroundColor = other.foregroundColor
        isWrapped = other.isWrapped
        truncationMode = other.truncationMode
        alignmentMode = other.alignmentMode
        allowsFontSubpixelQuantization = other.allowsFontSubpixelQuantization
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "string": return string
        case "font": return font
        case "fontSize": return NSNumber(value: Double(fontSize))
        case "foregroundColor": return foregroundColor
        case "wrapped", "isWrapped": return NSNumber(value: isWrapped)
        case "truncationMode": return truncationMode
        case "alignmentMode": return alignmentMode
        case "allowsFontSubpixelQuantization": return NSNumber(value: allowsFontSubpixelQuantization)
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "string":
            string = value is NSNull ? nil : value
        case "font":
            font = value is NSNull ? nil : value
        case "fontSize":
            if let v = CALayer.scalar(value) { fontSize = v }
        case "foregroundColor":
            foregroundColor = value is NSNull ? nil : value as? CGColor
        case "wrapped", "isWrapped":
            if let v = CALayer.boolean(value) { isWrapped = v }
        case "truncationMode":
            if let v = value as? CATextLayerTruncationMode { truncationMode = v }
            else if let raw = value as? String { truncationMode = CATextLayerTruncationMode(rawValue: raw) }
        case "alignmentMode":
            if let v = value as? CATextLayerAlignmentMode { alignmentMode = v }
            else if let raw = value as? String { alignmentMode = CATextLayerAlignmentMode(rawValue: raw) }
        case "allowsFontSubpixelQuantization":
            if let v = CALayer.boolean(value) { allowsFontSubpixelQuantization = v }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

// MARK: - CAEmitterCell

/// The definition of one species of particle emitted by a CAEmitterLayer.
///
/// Model-only on Linux today: the Apple-typed parameter set is stored so
/// particle configurations survive round-trips and animation key paths
/// resolve; QuillPaint's particle pass will simulate/draw them later.
/// `open` (matching Apple) — the previous shim's `final` broke subclassers.
open class CAEmitterCell: NSObject, CAMediaTiming {
    open var name: String?

    /// The particle image (a CGImage on Apple). Typed `Any?` per Apple.
    open var contents: Any?
    open var contentsScale: CGFloat = 1

    /// Particles created per second. Apple default 0.
    open var birthRate: Float = 0
    /// Particle lifetime in seconds. Apple default 0.
    open var lifetime: Float = 0
    open var lifetimeRange: Float = 0

    open var velocity: CGFloat = 0
    open var velocityRange: CGFloat = 0

    open var scale: CGFloat = 1
    open var scaleRange: CGFloat = 0
    open var scaleSpeed: CGFloat = 0

    open var alphaRange: Float = 0
    open var alphaSpeed: Float = 0

    /// Angle (radians) of the cone around the emission direction.
    open var emissionRange: CGFloat = 0
    /// Emission direction in the xy-plane (radians).
    open var emissionLongitude: CGFloat = 0
    /// Emission direction out of the xy-plane (radians).
    open var emissionLatitude: CGFloat = 0

    /// Rotation speed (radians/sec) of emitted particles.
    open var spin: CGFloat = 0
    open var spinRange: CGFloat = 0

    /// Constant acceleration applied to particles, per axis.
    open var xAcceleration: CGFloat = 0
    open var yAcceleration: CGFloat = 0
    open var zAcceleration: CGFloat = 0

    /// Particle tint. Opaque white default, per Apple.
    open var color: CGColor? = CGColor.white

    /// Per-channel color randomization range. Apple defaults 0.
    open var redRange: Float = 0
    open var greenRange: Float = 0
    open var blueRange: Float = 0

    /// Per-channel color change rate (per second). Apple defaults 0.
    open var redSpeed: Float = 0
    open var greenSpeed: Float = 0
    open var blueSpeed: Float = 0

    /// Whether this cell emits. Apple default true.
    open var isEnabled: Bool = true

    /// Nested cells: emitted particles can themselves emit, per Apple.
    open var emitterCells: [CAEmitterCell]?

    /// Cell style dictionary, per Apple's surface. Stored, not interpreted.
    open var style: [AnyHashable: Any]?

    open var beginTime: CFTimeInterval = 0
    open var duration: CFTimeInterval = 0
    open var speed: Float = 1
    open var timeOffset: CFTimeInterval = 0
    open var repeatCount: Float = 0
    open var repeatDuration: CFTimeInterval = 0
    open var autoreverses: Bool = false
    open var fillMode: CAMediaTimingFillMode = .removed
}

// MARK: - CAEmitterLayer string constants

/// Emitter shape constants for `CAEmitterLayer.emitterShape`.
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

/// Emitter mode constants for `CAEmitterLayer.emitterMode`.
public struct CAEmitterLayerEmitterMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let points = CAEmitterLayerEmitterMode(rawValue: "points")
    public static let outline = CAEmitterLayerEmitterMode(rawValue: "outline")
    public static let surface = CAEmitterLayerEmitterMode(rawValue: "surface")
    public static let volume = CAEmitterLayerEmitterMode(rawValue: "volume")
}

/// Render order constants for `CAEmitterLayer.renderMode`.
public struct CAEmitterLayerRenderMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let unordered = CAEmitterLayerRenderMode(rawValue: "unordered")
    public static let oldestFirst = CAEmitterLayerRenderMode(rawValue: "oldestFirst")
    public static let oldestLast = CAEmitterLayerRenderMode(rawValue: "oldestLast")
    public static let backToFront = CAEmitterLayerRenderMode(rawValue: "backToFront")
    public static let additive = CAEmitterLayerRenderMode(rawValue: "additive")
}

// MARK: - CAEmitterLayer

/// A layer that emits, animates, and renders a particle system.
///
/// Model-only on Linux today: the emitter configuration is stored faithfully
/// (no particles are simulated or drawn until QuillPaint). Inherits
/// `allowsGroupOpacity` from CALayer — the old duplicate declaration here was
/// dropped.
open class CAEmitterLayer: CALayer {
    open var emitterCells: [CAEmitterCell]?

    /// Center of the emission shape, in layer coordinates.
    open var emitterPosition: CGPoint = CGPoint(x: 0, y: 0)
    /// Z-component of the emission shape's center. Apple default 0.
    open var emitterZPosition: CGFloat = 0
    open var emitterSize: CGSize = CGSize(width: 0, height: 0)
    open var emitterDepth: CGFloat = 0

    open var emitterShape: CAEmitterLayerEmitterShape = .point
    open var emitterMode: CAEmitterLayerEmitterMode = .volume
    open var renderMode: CAEmitterLayerRenderMode = .unordered

    /// Whether particles keep 3D ordering. Apple default false.
    open var preservesDepth: Bool = false

    /// Multiplies the birth rate of each cell. Apple default 1.
    open var birthRate: Float = 1
    /// Multiplies the lifetime of each cell. Apple default 1.
    open var lifetime: Float = 1
    /// Multiplies the velocity of each cell. Apple default 1.
    open var velocity: Float = 1
    /// Multiplies the scale of each cell. Apple default 1.
    open var scale: Float = 1
    /// Multiplies the spin of each cell. Apple default 1.
    open var spin: Float = 1

    /// Seed for the particle randomizer. Apple default 0.
    open var seed: UInt32 = 0

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAEmitterLayer else { return }
        emitterCells = other.emitterCells
        emitterPosition = other.emitterPosition
        emitterZPosition = other.emitterZPosition
        emitterSize = other.emitterSize
        emitterDepth = other.emitterDepth
        emitterShape = other.emitterShape
        emitterMode = other.emitterMode
        renderMode = other.renderMode
        preservesDepth = other.preservesDepth
        birthRate = other.birthRate
        lifetime = other.lifetime
        velocity = other.velocity
        scale = other.scale
        spin = other.spin
        seed = other.seed
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "emitterCells": return emitterCells
        case "emitterPosition": return emitterPosition
        case "emitterZPosition": return NSNumber(value: Double(emitterZPosition))
        case "emitterSize": return emitterSize
        case "emitterDepth": return NSNumber(value: Double(emitterDepth))
        case "emitterShape": return emitterShape
        case "emitterMode": return emitterMode
        case "renderMode": return renderMode
        case "preservesDepth": return NSNumber(value: preservesDepth)
        case "birthRate": return NSNumber(value: birthRate)
        case "lifetime": return NSNumber(value: lifetime)
        case "velocity": return NSNumber(value: velocity)
        case "scale": return NSNumber(value: scale)
        case "spin": return NSNumber(value: spin)
        case "seed": return NSNumber(value: seed)
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "emitterCells":
            emitterCells = value as? [CAEmitterCell]
        case "emitterPosition":
            if let v = value as? CGPoint { emitterPosition = v }
        case "emitterZPosition":
            if let v = CALayer.scalar(value) { emitterZPosition = v }
        case "emitterSize":
            if let v = value as? CGSize { emitterSize = v }
        case "emitterDepth":
            if let v = CALayer.scalar(value) { emitterDepth = v }
        case "emitterShape":
            if let v = value as? CAEmitterLayerEmitterShape { emitterShape = v }
            else if let raw = value as? String { emitterShape = CAEmitterLayerEmitterShape(rawValue: raw) }
        case "emitterMode":
            if let v = value as? CAEmitterLayerEmitterMode { emitterMode = v }
            else if let raw = value as? String { emitterMode = CAEmitterLayerEmitterMode(rawValue: raw) }
        case "renderMode":
            if let v = value as? CAEmitterLayerRenderMode { renderMode = v }
            else if let raw = value as? String { renderMode = CAEmitterLayerRenderMode(rawValue: raw) }
        case "preservesDepth":
            if let v = CALayer.boolean(value) { preservesDepth = v }
        case "birthRate":
            if let v = CALayer.scalar(value) { birthRate = Float(v) }
        case "lifetime":
            if let v = CALayer.scalar(value) { lifetime = Float(v) }
        case "velocity":
            if let v = CALayer.scalar(value) { velocity = Float(v) }
        case "scale":
            if let v = CALayer.scalar(value) { scale = Float(v) }
        case "spin":
            if let v = CALayer.scalar(value) { spin = Float(v) }
        case "seed":
            if let n = value as? NSNumber { seed = n.uint32Value }
            else if let v = value as? UInt32 { seed = v }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

// MARK: - CAReplicatorLayer

/// A layer that creates a specified number of sublayer copies with varying
/// geometric, temporal, and color transformations.
///
/// Model-only on Linux today: replication parameters are stored faithfully;
/// QuillPaint will expand instances at composite time (the layer tree itself
/// is NOT physically duplicated, matching Apple).
open class CAReplicatorLayer: CALayer {
    /// Number of copies, including the original. Apple default 1.
    open var instanceCount: Int = 1

    /// Delay, in seconds, between replicated copies (offsets animation
    /// timing per instance on Apple).
    open var instanceDelay: CFTimeInterval = 0

    /// Transform applied between successive instances.
    open var instanceTransform: CATransform3D = CATransform3DIdentity

    /// Whether the layer maintains 3D state between instances. Apple
    /// default false.
    open var preservesDepth: Bool = false

    /// Tint applied to the first instance. Opaque white default, per Apple.
    open var instanceColor: CGColor? = CGColor.white

    /// Per-instance color component deltas. Apple defaults 0.
    open var instanceRedOffset: Float = 0
    open var instanceGreenOffset: Float = 0
    open var instanceBlueOffset: Float = 0
    open var instanceAlphaOffset: Float = 0

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAReplicatorLayer else { return }
        instanceCount = other.instanceCount
        instanceDelay = other.instanceDelay
        instanceTransform = other.instanceTransform
        preservesDepth = other.preservesDepth
        instanceColor = other.instanceColor
        instanceRedOffset = other.instanceRedOffset
        instanceGreenOffset = other.instanceGreenOffset
        instanceBlueOffset = other.instanceBlueOffset
        instanceAlphaOffset = other.instanceAlphaOffset
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "instanceCount": return NSNumber(value: instanceCount)
        case "instanceDelay": return NSNumber(value: instanceDelay)
        case "instanceTransform": return instanceTransform
        case "preservesDepth": return NSNumber(value: preservesDepth)
        case "instanceColor": return instanceColor
        case "instanceRedOffset": return NSNumber(value: instanceRedOffset)
        case "instanceGreenOffset": return NSNumber(value: instanceGreenOffset)
        case "instanceBlueOffset": return NSNumber(value: instanceBlueOffset)
        case "instanceAlphaOffset": return NSNumber(value: instanceAlphaOffset)
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "instanceCount":
            if let n = value as? NSNumber { instanceCount = n.intValue }
            else if let v = value as? Int { instanceCount = v }
        case "instanceDelay":
            if let v = CALayer.scalar(value) { instanceDelay = CFTimeInterval(v) }
        case "instanceTransform":
            if let v = value as? CATransform3D { instanceTransform = v }
            else if let boxed = value as? NSValue { instanceTransform = boxed.caTransform3DValue }
        case "preservesDepth":
            if let v = CALayer.boolean(value) { preservesDepth = v }
        case "instanceColor":
            instanceColor = value is NSNull ? nil : value as? CGColor
        case "instanceRedOffset":
            if let v = CALayer.scalar(value) { instanceRedOffset = Float(v) }
        case "instanceGreenOffset":
            if let v = CALayer.scalar(value) { instanceGreenOffset = Float(v) }
        case "instanceBlueOffset":
            if let v = CALayer.scalar(value) { instanceBlueOffset = Float(v) }
        case "instanceAlphaOffset":
            if let v = CALayer.scalar(value) { instanceAlphaOffset = Float(v) }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

// MARK: - CATransformLayer

/// A layer that preserves 3D sublayer transforms without drawing its own
/// flattened backing. Model-only on Linux: it behaves like CALayer for tree and
/// geometry storage, and QuillPaint can special-case its composition later.
open class CATransformLayer: CALayer {
    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
    }
}

// MARK: - CAScrollLayer

/// Scroll direction constants for `CAScrollLayer.scrollMode`.
public struct CAScrollLayerScrollMode: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public static let `none` = CAScrollLayerScrollMode(rawValue: "none")
    public static let vertically = CAScrollLayerScrollMode(rawValue: "vertically")
    public static let horizontally = CAScrollLayerScrollMode(rawValue: "horizontally")
    public static let both = CAScrollLayerScrollMode(rawValue: "both")
}

/// A layer that displays a scrollable but unclipped-by-scrollbars portion of
/// its sublayers.
///
/// Functional on Linux: scrolling is real geometry — it moves the layer's
/// bounds origin, which repositions sublayers exactly as on Apple. Only the
/// eventual clipping/drawing is deferred to QuillPaint. `scrollMode` is
/// stored for render-time/user-scroll policy; programmatic `scroll(to:)` is
/// not constrained by it (matching Apple).
open class CAScrollLayer: CALayer {
    open var scrollMode: CAScrollLayerScrollMode = .both

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAScrollLayer else { return }
        scrollMode = other.scrollMode
    }

    /// Scrolls so that `p` becomes the bounds origin.
    open func scroll(to p: CGPoint) { bounds.origin = p }

    /// Scrolls minimally so `r` becomes visible inside the current bounds.
    open func scroll(to r: CGRect) {
        var origin = bounds.origin
        if r.minX < bounds.minX {
            origin.x = r.minX
        } else if r.maxX > bounds.maxX {
            origin.x = r.maxX - bounds.width
        }
        if r.minY < bounds.minY {
            origin.y = r.minY
        } else if r.maxY > bounds.maxY {
            origin.y = r.maxY - bounds.height
        }
        bounds.origin = origin
    }

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "scrollMode": return scrollMode
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "scrollMode":
            if let v = value as? CAScrollLayerScrollMode { scrollMode = v }
            else if let raw = value as? String { scrollMode = CAScrollLayerScrollMode(rawValue: raw) }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}

// MARK: - CAMetalLayer

/// A layer that vends Metal drawables.
///
/// Functional against the Metal shim: `nextDrawable()` returns a real
/// CPU-backed shim texture sized to `drawableSize`, so render loops that
/// acquire/encode/present drawables run end-to-end. Nothing is presented to
/// an actual display yet — presentation is wired up when QuillPaint's
/// compositor lands.
open class CAMetalLayer: CALayer {
    open var device: MTLDevice?
    open var pixelFormat: MTLPixelFormat = .bgra8Unorm
    open var framebufferOnly: Bool = true
    open var presentsWithTransaction: Bool = false
    open var drawableSize: CGSize = CGSize(width: 1, height: 1)

    public override init() { super.init() }

    public required init(layer: Any) {
        super.init(layer: layer)
        guard let other = layer as? CAMetalLayer else { return }
        device = other.device
        pixelFormat = other.pixelFormat
        framebufferOnly = other.framebufferOnly
        presentsWithTransaction = other.presentsWithTransaction
        drawableSize = other.drawableSize
    }

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

    open override func quillValueForSubclassKey(_ key: String) -> Any? {
        switch key {
        case "pixelFormat": return pixelFormat
        case "framebufferOnly": return NSNumber(value: framebufferOnly)
        case "presentsWithTransaction": return NSNumber(value: presentsWithTransaction)
        case "drawableSize": return drawableSize
        default: return super.quillValueForSubclassKey(key)
        }
    }

    open override func quillSetValue(_ value: Any?, forSubclassKey key: String) -> Bool {
        switch key {
        case "pixelFormat":
            if let v = value as? MTLPixelFormat { pixelFormat = v }
        case "framebufferOnly":
            if let v = CALayer.boolean(value) { framebufferOnly = v }
        case "presentsWithTransaction":
            if let v = CALayer.boolean(value) { presentsWithTransaction = v }
        case "drawableSize":
            if let v = value as? CGSize { drawableSize = v }
        default:
            return super.quillSetValue(value, forSubclassKey: key)
        }
        return true
    }
}
