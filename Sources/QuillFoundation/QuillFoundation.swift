// QuillFoundation
// =================
// Cross-platform Foundation re-exports plus the small set of Foundation-shaped
// types that don't fit anywhere more specific. Anything UIKit-, WebKit-, or
// NetNewsWire-RSCore-shaped lives in QuillUIKit / QuillWebKit / QuillRS.
//
// On macOS / iOS this is mostly a thin re-export. On Linux this is also where
// CGFloat / CGPoint / CGSize / CGRect originate (since Foundation on Linux
// doesn't ship CoreGraphics).

@_exported import Foundation
#if canImport(FoundationNetworking)
@_exported import FoundationNetworking
#endif
#if os(Linux)
import Glibc
import QuillKit
#endif

#if canImport(ObjectiveC)
import ObjectiveC
#else
// Linux: no Objective-C runtime. Provide a Selector stub so the many
// UIKit-shaped APIs in QuillUIKit (UIBarButtonItem, UICommand, etc.)
// can be declared without conditional compilation around each one.
public struct Selector: Hashable, Sendable {
    public let name: String
    public init(_ name: String = "") { self.name = name }
}
#endif

public protocol QuillSelectorDispatching: AnyObject {
    func quillPerform(_ selector: Selector, with sender: Any?)
}

public extension QuillSelectorDispatching {
    func quillPerform(_ selector: Selector, with sender: Any?) {}
}

// MARK: - Apple-platform image / color / font / screen typealiases

#if os(macOS)
@_exported import AppKit
@_exported import CoreGraphics

public typealias RSImage = NSImage
public typealias RSColor = NSColor
public typealias RSFont = NSFont
public typealias RSScreen = NSScreen
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIWindow = NSWindow

public extension NSImage {
    func dataRepresentation() -> Data? {
        return self.tiffRepresentation
    }
    static var smartBadgeTemplateName: String { "NSActionTemplate" }
    func tinted(with color: NSColor) -> NSImage { self }
    static func image(with data: Data, imageResultBlock: @escaping (NSImage?) -> Void) {
        imageResultBlock(NSImage(data: data))
    }
    static func image(data: Data) async -> NSImage? {
        return NSImage(data: data)
    }
    static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    func maskWithColor(color: CGColor) -> NSImage? { self }

    convenience init?(systemName: String, withConfiguration: Any? = nil) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }

    struct SymbolConfiguration {
        public init(pointSize: CGFloat, weight: Any) {}
        public init(textStyle: Any) {}
    }
}

public extension NSScreen {
    static var maxScreenScale: CGFloat { 2.0 }
}

#elseif os(iOS)
@_exported import UIKit
@_exported import CoreGraphics

public typealias RSImage = UIImage
public typealias RSColor = UIColor
public typealias RSFont = UIFont
public typealias RSScreen = UIScreen

public extension UIImage {
    func dataRepresentation() -> Data? { self.pngData() }
    func tinted(with color: UIColor) -> UIImage { self }
    static func image(with data: Data, imageResultBlock: @escaping (UIImage?) -> Void) {
        imageResultBlock(UIImage(data: data))
    }
    static func image(data: Data) async -> UIImage? { UIImage(data: data) }
    static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    func maskWithColor(color: CGColor) -> UIImage? { self }
}

public extension UIScreen {
    static var maxScreenScale: CGFloat { 2.0 }
}
#else

// MARK: - Linux native types
//
// CGFloat / CGPoint / CGSize / CGRect are provided by Foundation on
// Linux since Swift 5.1 — declaring our own causes "ambiguous for type
// lookup" in upstream code. CGImage is the only Apple type we still
// stub here (Linux Foundation has no equivalent).

public struct QuillCFAllocator: Sendable {
    public init() {}
}

public let kCFAllocatorDefault = QuillCFAllocator()
public let kCFBooleanTrue: NSNumber = NSNumber(value: true)
public let kCFBooleanFalse: NSNumber = NSNumber(value: false)

public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent = 0
    case absoluteColorimetric = 1
    case relativeColorimetric = 2
    case perceptual = 3
    case saturation = 4
}

public class CGImage: Equatable, @unchecked Sendable {
    /// Raw premultiplied-BGRA pixel backing (Cairo ARGB32 byte order on
    /// little-endian). Optional: a nil value keeps the historical "blank
    /// image" semantics. The V4L2 capture path and CIContext.createCGImage
    /// populate it; the Cairo CGContext backend draws it.
    public var quillBGRAPixels: [UInt8]?
    public var quillBytesPerRow: Int = 0

    public init() {}

    // PNG/JPEG decode inits (SSK's UIImage+Attachment). The dataProviderSource is
    // a CGDataProvider (defined in the ImageIO shim, which depends on us) -- typed
    // `Any` to dodge the cross-module dependency. Real decoding needs libpng/
    // libjpeg/Cairo; deferred, so these return a blank CGImage (never nil) -- the
    // attachment pipeline compiles and proceeds (image content is not yet real).
    public convenience init?(pngDataProviderSource source: Any,
                             decode: [CGFloat]?,
                             shouldInterpolate: Bool,
                             intent: CGColorRenderingIntent) {
        self.init()
        _ = (source, decode, shouldInterpolate, intent)
    }
    public convenience init?(jpegDataProviderSource source: Any,
                             decode: [CGFloat]?,
                             shouldInterpolate: Bool,
                             intent: CGColorRenderingIntent) {
        self.init()
        _ = (source, decode, shouldInterpolate, intent)
    }

    public convenience init?(
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bitsPerPixel: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        bitmapInfo: CGBitmapInfo,
        provider: Any,
        decode: UnsafePointer<CGFloat>?,
        shouldInterpolate: Bool,
        intent: CGColorRenderingIntent
    ) {
        self.init()
        self.width = width
        self.height = height
        _ = (bitsPerComponent, bitsPerPixel, bytesPerRow, space, bitmapInfo, provider, decode, shouldInterpolate, intent)
    }

    // Pixel dimensions + cropping (BadgeAssets spritesheets, image utilities).
    // Inert decode means dimensions are 0 and cropping yields a blank sub-image
    // until a real decoder (libpng/Cairo) lands.
    public var width: Int = 0
    public var height: Int = 0
    public func cropping(to rect: CGRect) -> CGImage? {
        _ = rect
        return CGImage()
    }

    public static func == (lhs: CGImage, rhs: CGImage) -> Bool {
        lhs === rhs
    }
}

// NSHashTable (weak/strong object collection; Linux shim). swift-corelibs has no
// NSHashTable. SSK uses it for a weak set of message-pipeline stages. Weak
// semantics are deferred -- this holds STRONG refs (could retain-cycle; revisit
// if it matters) which is enough to compile + behave for the bounded usage
// (.weakObjects / add / remove / allObjects). ObjectType is unconstrained to
// match `NSHashTable<SomeProtocol>`; identity uses `as AnyObject` (valid for the
// class instances actually stored).
public final class NSHashTable<ObjectType>: @unchecked Sendable {
    private var storage: [ObjectType] = []
    public init() {}
    public static func weakObjects() -> NSHashTable<ObjectType> { NSHashTable<ObjectType>() }
    public func add(_ object: ObjectType?) {
        guard let object else { return }
        storage.append(object)
    }
    public func remove(_ object: ObjectType?) {
        guard let object else { return }
        storage.removeAll { ($0 as AnyObject) === (object as AnyObject) }
    }
    public func contains(_ object: ObjectType?) -> Bool {
        guard let object else { return false }
        return storage.contains { ($0 as AnyObject) === (object as AnyObject) }
    }
    public func removeAllObjects() { storage.removeAll() }
    public var allObjects: [ObjectType] { storage }
    public var count: Int { storage.count }
}

// Opaque path types (Linux). SSK builds UIBezierPaths and reads `.cgPath`; the
// CGContext drawing shim takes paths as `Any`, so these only need to exist as
// inert handles (no real geometry is recorded).
public class CGPath {
    public init() {}

    public convenience init(
        roundedRect rect: CGRect,
        cornerWidth: CGFloat,
        cornerHeight: CGFloat,
        transform: UnsafePointer<CGAffineTransform>?
    ) {
        self.init()
        _ = (rect, cornerWidth, cornerHeight, transform)
    }

    public func copy() -> CGPath? { self }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? {
        _ = transform
        return self
    }
    public func contains(_ point: CGPoint) -> Bool {
        _ = point
        return false
    }
}
public final class CGMutablePath: CGPath {
    public override init() { super.init() }
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }
    public func addRect(_ rect: CGRect) {}
    public func addEllipse(in rect: CGRect) {}
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {}
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {}
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {}
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {}
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {}
    public func addPath(_ path: CGPath) { _ = path }
    public func addPath(_ path: CGPath, transform: CGAffineTransform) { _ = (path, transform) }
    public func closeSubpath() {}
}

// MARK: - CGAffineTransform (Linux)
//
// Pure 2-D affine math — no platform dependency — so this is a FAITHFUL
// implementation (not an inert stub). swift-corelibs Foundation ships the other
// CG geometry types (CGFloat/CGSize/CGRect/CGPoint) but NOT CGAffineTransform,
// so SSK's image/avatar geometry (e.g. a vertical-flip transform) needs it here.
public struct CGAffineTransform: Equatable, Sendable {
    public var a: CGFloat
    public var b: CGFloat
    public var c: CGFloat
    public var d: CGFloat
    public var tx: CGFloat
    public var ty: CGFloat

    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init() { self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0) }
    public init(translationX tx: CGFloat, y ty: CGFloat) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }
    public init(scaleX sx: CGFloat, y sy: CGFloat) {
        self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }
    public init(rotationAngle angle: CGFloat) {
        let cosA = CGFloat(cos(Double(angle)))
        let sinA = CGFloat(sin(Double(angle)))
        self.init(a: cosA, b: sinA, c: -sinA, d: cosA, tx: 0, ty: 0)
    }

    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    public var isIdentity: Bool { self == .identity }

    /// `t1.concatenating(t2)` = t1 followed by t2 (matrix product t1 * t2).
    public func concatenating(_ t: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(
            a: a * t.a + b * t.c,
            b: a * t.b + b * t.d,
            c: c * t.a + d * t.c,
            d: c * t.b + d * t.d,
            tx: tx * t.a + ty * t.c + t.tx,
            ty: tx * t.b + ty * t.d + t.ty
        )
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(translationX: x, y: y).concatenating(self)
    }
    public func scaledBy(x: CGFloat, y: CGFloat) -> CGAffineTransform {
        CGAffineTransform(scaleX: x, y: y).concatenating(self)
    }
    public func rotated(by angle: CGFloat) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: angle).concatenating(self)
    }
    public func inverted() -> CGAffineTransform {
        let det = a * d - b * c
        if det == 0 { return self }
        let inv = 1 / det
        return CGAffineTransform(
            a: d * inv,
            b: -b * inv,
            c: -c * inv,
            d: a * inv,
            tx: (c * ty - d * tx) * inv,
            ty: (b * tx - a * ty) * inv
        )
    }
}

// CGPoint.applying(_:) — apply an affine transform to a point. swift-corelibs
// ships CGPoint but not this method (it lives in CoreGraphics on Apple); SSK's
// UIView+OWS.applyingInverse needs it. Faithful CGPointApplyAffineTransform math.
public extension CGPoint {
    func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

// MARK: - CoreGraphics drawing shim (Linux)
//
// SignalServiceKit's avatar/thumbnail rendering (AvatarBuilder, UIImage+OWS)
// draws into a CGContext obtained from a UIGraphicsImageRenderer. CoreGraphics
// rasterization is unavailable on Linux, so this is an INERT no-op context:
// nothing is drawn, and the renderer returns a blank placeholder image of the
// requested size. Color / gradient / path / image arguments are typed `Any?`
// to avoid coupling drawing to a concrete raster backend and the optional
// CGGradient/CGPath value-holders. A real raster backend (Cairo/Skia) is a
// later milestone. HONEST STATUS: avatars render blank on Linux.

public enum CGInterpolationQuality: Int32, Sendable {
    case `default` = 0, none = 1, low = 2, high = 3, medium = 4
}

public enum CGBlendMode: Int32, Sendable {
    case normal = 0, multiply, screen, overlay, darken, lighten, colorDodge,
         colorBurn, softLight, hardLight, difference, exclusion, hue, saturation,
         color, luminosity, clear, copy, sourceIn, sourceOut, sourceAtop,
         destinationOver, destinationIn, destinationOut, destinationAtop, xor,
         plusDarker, plusLighter
}

public struct CGGradientDrawingOptions: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1 << 0)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 1 << 1)
}

public final class CGColorSpace: Equatable {
    public enum Model: Int32, Sendable {
        case unknown = -1
        case monochrome = 0
        case rgb = 1
        case cmyk = 2
        case lab = 3
        case deviceN = 4
        case indexed = 5
        case pattern = 6
    }

    public let name: String?

    public init() {
        self.name = nil
    }

    public init?(name: String) {
        self.name = name
    }

    public var model: Model { .rgb }

    public static let displayP3 = "kCGColorSpaceDisplayP3"

    public static func == (lhs: CGColorSpace, rhs: CGColorSpace) -> Bool {
        lhs === rhs
    }
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace() }

public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat

    public init() {
        self.init(dx: 0, dy: 0)
    }

    public init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    public static let zero = CGVector()
}

public final class CGGradient {
    /// Inert: no color stops are retained (nothing is drawn on Linux).
    public init?(colorsSpace space: Any?, colors: Any?, locations: Any?) {}
    public init?(colorsSpace space: CGColorSpace?, colors: Any, locations: UnsafePointer<CGFloat>?) {}
}

// Pixel-format flags for a CGContext bitmap context. Raw values match Apple's
// <CoreGraphics/CGImage.h> so callers that OR them into a UInt32 bitmapInfo (e.g.
// BlurHash: byteOrder32Big | premultipliedLast) get the right bits. Inert on
// Linux -- no real bitmap is allocated.
public struct CGBitmapInfo: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let alphaInfoMask = CGBitmapInfo(rawValue: 0x1F)
    public static let floatInfoMask = CGBitmapInfo(rawValue: 0xF00)
    public static let floatComponents = CGBitmapInfo(rawValue: 1 << 8)
    public static let byteOrderMask = CGBitmapInfo(rawValue: 0x7000)
    public static let byteOrderDefault = CGBitmapInfo(rawValue: 0 << 12)
    public static let byteOrder16Little = CGBitmapInfo(rawValue: 1 << 12)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder16Big = CGBitmapInfo(rawValue: 3 << 12)
    public static let byteOrder32Big = CGBitmapInfo(rawValue: 4 << 12)
}

public enum CGImageAlphaInfo: UInt32, Sendable {
    case none = 0
    case premultipliedLast = 1
    case premultipliedFirst = 2
    case last = 3
    case first = 4
    case noneSkipLast = 5
    case noneSkipFirst = 6
    case alphaOnly = 7
}

public enum CGLineCap: Int32, Sendable {
    case butt = 0
    case round = 1
    case square = 2
}

public enum CGLineJoin: Int32, Sendable {
    case miter = 0
    case round = 1
    case bevel = 2
}

public enum CGPathFillRule: Int32, Sendable {
    case winding = 0
    case evenOdd = 1
}

public final class CGContext {
    /// Pluggable real-drawing backend (see CGContextBackend.swift). nil keeps
    /// the historical compile-only no-op behavior.
    public var quillBackend: QuillCGContextBackend?

    public convenience init(quillBackend: QuillCGContextBackend) {
        self.init()
        self.quillBackend = quillBackend
    }

    public var width: Int = 0
    public var height: Int = 0
    public var bitsPerComponent: Int = 8
    public var bitsPerPixel: Int = 32
    public var bytesPerRow: Int = 0
    public var bitmapInfo: CGBitmapInfo = []
    public var colorSpace: CGColorSpace?
    public var textMatrix: CGAffineTransform = .identity
    public var textPosition: CGPoint = .zero

    public init() {}

    /// Bitmap-context initializer. Inert on Linux: no pixel buffer is allocated
    /// and nothing is drawn (the draw/fill methods are no-ops), so makeImage()
    /// returns nil. Exists so the upstream raster paths (BlurHash) compile. The
    /// init itself never returns nil.
    public convenience init?(
        data: UnsafeMutableRawPointer?,
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        bitmapInfo: UInt32
    ) {
        self.init()
        self.width = width
        self.height = height
        self.bitsPerComponent = bitsPerComponent
        self.bitsPerPixel = bitsPerComponent * 4
        self.bytesPerRow = bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = CGBitmapInfo(rawValue: bitmapInfo)
    }

    public convenience init?(
        data: UnsafeMutableRawPointer?,
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bytesPerRow: Int,
        space: CGColorSpace,
        bitmapInfo: UInt32,
        releaseCallback: Any?,
        releaseInfo: Any?
    ) {
        self.init(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: bitmapInfo
        )
        _ = (releaseCallback, releaseInfo)
    }

    /// Inert: there is no backing bitmap on Linux, so no image is produced.
    public func makeImage() -> CGImage? { nil }

    public var interpolationQuality: CGInterpolationQuality = .default

    public func setFillColor(_ color: Any?) {}
    public func setFillColor(_ color: RSCGColor) { quillBackend?.setFillColor(quillNormalizedRGBA(color)) }
    public func setFillColor(_ color: RSCGColor?) { if let color { quillBackend?.setFillColor(quillNormalizedRGBA(color)) } }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { quillBackend?.setFillColor([red, green, blue, alpha]) }
    public func setStrokeColor(_ color: Any?) {}
    public func setStrokeColor(_ color: RSCGColor) { quillBackend?.setStrokeColor(quillNormalizedRGBA(color)) }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) { quillBackend?.setStrokeColor([red, green, blue, alpha]) }
    public func setLineWidth(_ width: CGFloat) { quillBackend?.setLineWidth(width) }
    public func setLineCap(_ cap: CGLineCap) { quillBackend?.setLineCap(cap) }
    public func setLineJoin(_ join: CGLineJoin) { quillBackend?.setLineJoin(join) }
    public func setMiterLimit(_ limit: CGFloat) {}
    public func setShadow(offset: CGSize, blur: CGFloat) {}
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {}
    public func setAllowsAntialiasing(_ allowsAntialiasing: Bool) {}
    public func setShouldAntialias(_ shouldAntialias: Bool) {}
    public func setAllowsFontSmoothing(_ allowsFontSmoothing: Bool) {}
    public func setShouldSmoothFonts(_ shouldSmoothFonts: Bool) {}
    public func setAllowsFontSubpixelPositioning(_ allowsFontSubpixelPositioning: Bool) {}
    public func setShouldSubpixelPositionFonts(_ shouldSubpixelPositionFonts: Bool) {}
    public func setAllowsFontSubpixelQuantization(_ allowsFontSubpixelQuantization: Bool) {}
    public func setShouldSubpixelQuantizeFonts(_ shouldSubpixelQuantizeFonts: Bool) {}
    public func setAlpha(_ alpha: CGFloat) { quillBackend?.setAlpha(alpha) }
    public func setBlendMode(_ mode: CGBlendMode) {}

    public func fill(_ rect: CGRect) { quillBackend?.fill(rect) }
    public func fill(_ rects: [CGRect]) { for r in rects { quillBackend?.fill(r) } }
    public func fillEllipse(in rect: CGRect) { quillBackend?.fillEllipse(in: rect) }
    public func fillPath() { quillBackend?.fillPath() }
    public func fillPath(using rule: CGPathFillRule) { _ = rule }
    public func clear(_ rect: CGRect) { quillBackend?.clear(rect) }
    public func stroke(_ rect: CGRect) { quillBackend?.stroke(rect) }
    public func strokeEllipse(in rect: CGRect) { quillBackend?.strokeEllipse(in: rect) }
    public func strokeLineSegments(between points: [CGPoint]) { quillBackend?.strokeLineSegments(between: points) }
    public func strokePath() { quillBackend?.strokePath() }

    public func beginPath() { quillBackend?.beginPath() }
    public func closePath() { quillBackend?.closePath() }
    public func move(to point: CGPoint) { quillBackend?.move(to: point) }
    public func addLine(to point: CGPoint) { quillBackend?.addLine(to: point) }
    public func addRect(_ rect: CGRect) { quillBackend?.addRect(rect) }
    public func addRects(_ rects: [CGRect]) {}
    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }
    public func addEllipse(in rect: CGRect) { quillBackend?.addEllipse(in: rect) }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {}
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {}
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) { quillBackend?.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise) }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {}
    public func addPath(_ path: Any?) {}
    public func clip() { quillBackend?.clip() }
    public func clip(using rule: CGPathFillRule) { _ = rule }
    public func clip(to rect: CGRect) { quillBackend?.clip(to: rect) }
    public func resetClip() {}
    // CGContext.clip(to:mask:) — clips to a rect using an image mask. Inert on
    // Linux (no real raster). SSK: AvatarBuilder masks a tinted icon.
    public func clip(to rect: CGRect, mask image: Any) {}

    public func saveGState() { quillBackend?.saveGState() }
    public func restoreGState() { quillBackend?.restoreGState() }
    public func beginTransparencyLayer(auxiliaryInfo: Any?) {}
    public func endTransparencyLayer() {}
    public func endPage() {}
    public func translateBy(x: CGFloat, y: CGFloat) { quillBackend?.translateBy(x: x, y: y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { quillBackend?.scaleBy(x: x, y: y) }
    public func rotate(by angle: CGFloat) { quillBackend?.rotate(by: angle) }
    // `CGAffineTransform` is absent from swift-corelibs Foundation on this
    // toolchain, so the param is typed `Any` (the op is an inert no-op anyway).
    public func concatenate(_ transform: Any) {}

    public func draw(_ image: Any, in rect: CGRect) { quillBackend?.draw(image, in: rect, interpolationQuality: interpolationQuality) }
    public func drawLinearGradient(_ gradient: Any?, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {}
    public func drawRadialGradient(_ gradient: Any?, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {}
}

public typealias CGWindowID = UInt32

public struct CGWindowListOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let optionAll = CGWindowListOption(rawValue: 0)
    public static let optionIncludingWindow = CGWindowListOption(rawValue: 1 << 0)
}

public struct CGWindowImageOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let `default` = CGWindowImageOption(rawValue: 0)
    public static let boundsIgnoreFraming = CGWindowImageOption(rawValue: 1 << 0)
}

public func CGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage? {
    _ = (screenBounds, listOption, windowID, imageOption)
    return nil
}

@discardableResult
public func sysctlbyname(
    _ name: UnsafePointer<CChar>!,
    _ oldp: UnsafeMutableRawPointer!,
    _ oldlenp: UnsafeMutablePointer<Int>!,
    _ newp: UnsafeMutableRawPointer!,
    _ newlen: Int
) -> Int32 {
    oldlenp?.pointee = 0
    _ = (name, oldp, newp, newlen)
    return -1
}

// `open` (not just `public`) so framework shims can subclass it — e.g.
// SDWebImage's SDAnimatedImage: UIImage. On Apple, UIImage/NSImage are open too.
public enum QuillResourceLookup {
    public static let commonImageExtensions: [String] = [
        "png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "tif", "svg"
    ]

    public static func path(
        forResource name: String,
        candidateExtensions: [String] = [],
        subdirectories: [String] = []
    ) -> String? {
        guard !name.isEmpty else { return nil }

        let roots = resourceRoots()
        let searchSubdirectories = [""] + subdirectories.filter { !$0.isEmpty }
        for root in roots {
            for subdirectory in searchSubdirectories {
                let directory = subdirectory.isEmpty
                    ? root
                    : root.appendingPathComponent(subdirectory, isDirectory: true)
                for candidate in candidateNames(for: name, extensions: candidateExtensions) {
                    let url = directory.appendingPathComponent(candidate)
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                       !isDirectory.boolValue {
                        return url.path
                    }
                }
            }
        }

        return nil
    }

    public static func data(
        forResource name: String,
        candidateExtensions: [String] = []
    ) -> Data? {
        guard let path = path(forResource: name, candidateExtensions: candidateExtensions) else {
            return nil
        }
        return FileManager.default.contents(atPath: path)
    }

    private static func candidateNames(for name: String, extensions: [String]) -> [String] {
        let url = URL(fileURLWithPath: name)
        guard url.pathExtension.isEmpty else { return [name] }

        var candidates = [name]
        for ext in extensions where !ext.isEmpty {
            candidates.append("\(name).\(ext)")
        }
        return candidates
    }

    private static func resourceRoots() -> [URL] {
        var roots: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return
            }
            guard seen.insert(standardized.path).inserted else { return }
            roots.append(standardized)
        }

        if let raw = ProcessInfo.processInfo.environment["QUILLUI_RESOURCE_DIRS"] {
            for part in raw.split(separator: ":", omittingEmptySubsequences: true) {
                append(URL(fileURLWithPath: String(part), isDirectory: true))
            }
        }

        if let executableDirectory = executableDirectory() {
            append(executableDirectory)
            append(executableDirectory.appendingPathComponent("Resources", isDirectory: true))

            if let entries = try? FileManager.default.contentsOfDirectory(
                at: executableDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for entry in entries where entry.pathExtension == "resources" || entry.pathExtension == "bundle" {
                    append(entry)
                    append(entry.appendingPathComponent("Resources", isDirectory: true))
                    append(entry
                        .appendingPathComponent("Contents", isDirectory: true)
                        .appendingPathComponent("Resources", isDirectory: true))
                }
            }
        }

        append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true))

        return roots
    }

    private static func executableDirectory() -> URL? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = readlink("/proc/self/exe", &buffer, buffer.count - 1)
        guard count > 0 else { return nil }
        let path = String(decoding: buffer.prefix(Int(count)).map(UInt8.init(bitPattern:)), as: UTF8.self)
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }
}

public enum QuillImageCompositingOperation: Sendable {
    case copy
    case sourceOver
}

open class RSImage: NSObject, @unchecked Sendable {
    public enum ResizingMode: Int, Sendable {
        case tile
        case stretch
    }

    public override init() {}
    public init?(data: Data) {
        super.init()
        self.data = data
    }
    public init?(named name: String) {
        super.init()
        if let data = QuillResourceLookup.data(
            forResource: name,
            candidateExtensions: QuillResourceLookup.commonImageExtensions
        ) {
            self.data = data
        } else {
            self.size = CGSize(width: 32, height: 32)
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillFoundation",
                operation: "NSImage(named:)",
                severity: .warning,
                message: "NSImage(named:) could not find '\(name)' in QUILLUI_RESOURCE_DIRS, SwiftPM .resources directories, or bundled Resources; returning a 32x32 placeholder image."
            )
        }
    }
    public init?(systemName: String, withConfiguration: Any? = nil) {
        super.init()
        self.size = CGSize(width: 32, height: 32)
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillFoundation",
            operation: "NSImage(systemName:)",
            severity: .warning,
            message: "NSImage(systemName:) returns a 32x32 placeholder image for '\(systemName)' on Linux; SF Symbol assets are not loaded through AppKit yet."
        )
    }
    public init(size: CGSize) {
        super.init()
        self.size = size
    }
    public struct SymbolConfiguration {
        public init(pointSize: CGFloat, weight: Any) {}
        public init(textStyle: Any) {}
    }
    public var size: CGSize = CGSize(width: 0, height: 0)
    /// Raw image bytes when the instance was constructed from
    /// `init?(data:)`. Mirrors the `NSImage(data:)` source-
    /// compatibility shape — readers reach back to the original
    /// bytes for re-encoding (e.g. `tiffRepresentation`).
    public var data: Data?
    public var capInsets: NSEdgeInsets = NSEdgeInsets()
    public var resizingMode: ResizingMode = .tile
    public func pngData() -> Data? { data }
    public func dataRepresentation() -> Data? { data }
    /// Disfavored so QuillUI's gdk-pixbuf-backed `RSImage.tiffRepresentation`
    /// extension wins wherever both modules are visible; Telegram package
    /// islands that only see QuillFoundation get this passthrough.
    @_disfavoredOverload
    public var tiffRepresentation: Data? { data }
    public func addRepresentation(_ imageRep: Any) { _ = imageRep }
    public func tinted(with: Any) -> RSImage { self }
    public static func image(with data: Data, imageResultBlock: @escaping (RSImage?) -> Void) {
        imageResultBlock(RSImage(data: data))
    }
    public static func image(data: Data) async -> RSImage? { RSImage(data: data) }
    public static func scaledImageData(_ data: Data, maxPixelSize: Int) -> Data? { data }
    public static var smartBadgeTemplateName: String { "" }
    public func maskWithColor(color: Any) -> RSImage? { self }
    public func resizableImage(withCapInsets capInsets: NSEdgeInsets, resizingMode: ResizingMode = .tile) -> RSImage {
        self.capInsets = capInsets
        self.resizingMode = resizingMode
        return self
    }

    public func lockFocus() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillFoundation",
            operation: "NSImage.lockFocus",
            severity: .warning,
            message: "NSImage.lockFocus is currently a no-op on Linux; bitmap drawing contexts are not implemented yet."
        )
    }

    public func lockFocusFlipped(_ flipped: Bool) {
        _ = flipped
        lockFocus()
    }

    public func unlockFocus() {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillFoundation",
            operation: "NSImage.unlockFocus",
            severity: .warning,
            message: "NSImage.unlockFocus is currently a no-op on Linux; bitmap drawing contexts are not implemented yet."
        )
    }

    public func draw(
        in destinationRect: CGRect,
        from sourceRect: CGRect,
        operation: QuillImageCompositingOperation,
        fraction: Double
    ) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillFoundation",
            operation: "NSImage.draw",
            severity: .warning,
            message: "NSImage.draw is currently a no-op on Linux; image compositing needs a real bitmap backend."
        )
    }

    // MARK: UIImage source-compat surface (Linux placeholders)
    public convenience init?(contentsOfFile path: String) {
        self.init()
        self.size = CGSize(width: 32, height: 32)
    }
    public func jpegData(compressionQuality: CGFloat) -> Data? { data }
    public var cgImage: CGImage? { nil }
    public func cgImage(forProposedRect rect: UnsafeMutablePointer<CGRect>?, context: Any?, hints: [AnyHashable: Any]?) -> CGImage? {
        _ = (rect, context, hints)
        return cgImage
    }
    public var scale: CGFloat { 1 }

    public enum Orientation: Int, Sendable {
        case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored
    }
    public var imageOrientation: Orientation { .up }

    public func withTintColor(_ color: Any) -> RSImage { self }
    // Typed overload so a leading-dot color literal (e.g. `.white`) resolves its
    // contextual base. SSK: AvatarBuilder.releaseNotesIcon does
    // `UIImage(named:)!.withTintColor(.white)`. Inert (returns self).
    public func withTintColor(_ color: RSColor) -> RSImage { self }
    public func draw(in rect: CGRect) {}
    public func draw(at point: CGPoint) {}

    /// `UIImage(cgImage:scale:orientation:)` source-compat. On Linux the backing
    /// CGImage is opaque (no raster), so this records the requested scale but
    /// holds a placeholder size; callers that re-encode get an empty image.
    public convenience init(cgImage: CGImage, scale: CGFloat = 1, orientation: Orientation = .up) {
        self.init()
        self.size = CGSize(width: 0, height: 0)
    }

    public convenience init(cgImage: CGImage, size: CGSize) {
        self.init()
        self.size = size
    }
}
public typealias UIImage = RSImage

public struct RSCGColor: Equatable, Sendable {
    public var components: [CGFloat]?
    public var numberOfComponents: Int { components?.count ?? 0 }
    public static var typeID: UInt { 0 }

    public init(components: [CGFloat]?) {
        self.components = components
    }

    public static let clear = RSCGColor(components: [0, 0, 0, 0])
    public static let white = RSCGColor(components: [1, 1, 1, 1])
    public static let black = RSCGColor(components: [0, 0, 0, 1])

    /// Apple's sRGB convenience initializer (`CGColor(red:green:blue:alpha:)`).
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(components: [red, green, blue, alpha])
    }

    /// Apple's grayscale convenience initializer.
    public init(gray: CGFloat, alpha: CGFloat) {
        self.init(components: [gray, gray, gray, alpha])
    }
}
public typealias CGColor = RSCGColor

public class RSColor: NSObject, @unchecked Sendable {
    // Phase B: real RGBA storage so callers get sensible values back
    // from .redComponent / .cgColor / etc. Stored under underscore-
    // prefixed names so static peers like `NSColor.red` (an extension)
    // don't shadow the instance accessors at lookup.
    public let _red: CGFloat
    public let _green: CGFloat
    public let _blue: CGFloat
    public let _alpha: CGFloat

    public override init() {
        self._red = 0; self._green = 0; self._blue = 0; self._alpha = 1
    }
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self._red = red; self._green = green; self._blue = blue; self._alpha = alpha
    }

    /// Apple's UIColor(hue:saturation:brightness:alpha:) -- standard HSB->RGB
    /// conversion, delegating to the RGBA designated init. (UIColor+OWS blending.)
    public convenience init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {
        let h = (hue - floor(hue)) * 6
        let i = floor(h)
        let f = h - i
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        let r: CGFloat, g: CGFloat, b: CGFloat
        switch Int(i) % 6 {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    /// UIColor.setFill() sets this color as the fill color in the current UIKit
    /// graphics context. There is no graphics context on Linux (UIGraphicsImageRenderer
    /// is inert), so this is a no-op — UIImage+OWS's solid-color image render degrades
    /// to a blank image. HONEST STATUS: no rasterized fills on Linux.
    public func setFill() {}

    public static let clear = RSColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = RSColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = RSColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let orange = RSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)

    /// Returns a 4-tuple [R, G, B, A]. Matches the CGColor.components shape.
    public var cgColor: RSCGColor { RSCGColor(components: [_red, _green, _blue, _alpha]) }
    public func set() {}
    public var components: [CGFloat]? { [_red, _green, _blue, _alpha] }
    public var numberOfComponents: Int { 4 }

    /// Apple's UIColor.getRed(_:green:blue:alpha:) -- write the stored RGBA into
    /// the out-pointers. SSK's UIColor.components() builds on it. Always succeeds.
    @discardableResult
    public func getRed(
        _ red: UnsafeMutablePointer<CGFloat>,
        green: UnsafeMutablePointer<CGFloat>,
        blue: UnsafeMutablePointer<CGFloat>,
        alpha: UnsafeMutablePointer<CGFloat>
    ) -> Bool {
        red.pointee = _red
        green.pointee = _green
        blue.pointee = _blue
        alpha.pointee = _alpha
        return true
    }

    @discardableResult
    public func getRed(
        _ red: UnsafeMutablePointer<CGFloat>?,
        green: UnsafeMutablePointer<CGFloat>?,
        blue: UnsafeMutablePointer<CGFloat>?,
        alpha: UnsafeMutablePointer<CGFloat>?
    ) -> Bool {
        red?.pointee = _red
        green?.pointee = _green
        blue?.pointee = _blue
        alpha?.pointee = _alpha
        return true
    }

    /// Apple's UIColor.getHue(_:saturation:brightness:alpha:) -- standard RGB->HSB
    /// conversion over the stored components. Always succeeds.
    @discardableResult
    public func getHue(
        _ hue: UnsafeMutablePointer<CGFloat>,
        saturation: UnsafeMutablePointer<CGFloat>,
        brightness: UnsafeMutablePointer<CGFloat>,
        alpha: UnsafeMutablePointer<CGFloat>
    ) -> Bool {
        let r = _red, g = _green, b = _blue
        let maxV = max(r, max(g, b))
        let minV = min(r, min(g, b))
        let delta = maxV - minV
        var h: CGFloat = 0
        if delta != 0 {
            if maxV == r { h = (g - b) / delta; if h < 0 { h += 6 } }
            else if maxV == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
        }
        hue.pointee = h
        saturation.pointee = maxV == 0 ? 0 : delta / maxV
        brightness.pointee = maxV
        alpha.pointee = _alpha
        return true
    }

    @discardableResult
    public func getHue(
        _ hue: UnsafeMutablePointer<CGFloat>?,
        saturation: UnsafeMutablePointer<CGFloat>?,
        brightness: UnsafeMutablePointer<CGFloat>?,
        alpha: UnsafeMutablePointer<CGFloat>?
    ) -> Bool {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        _ = getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue?.pointee = h
        saturation?.pointee = s
        brightness?.pointee = b
        alpha?.pointee = a
        return true
    }
}
public typealias UIColor = RSColor

public class RSFont: NSObject, @unchecked Sendable {
    public let pointSize: CGFloat
    public init(pointSize: CGFloat) { self.pointSize = pointSize }
    public override init() { self.pointSize = 13 }
    public static func systemFont(ofSize size: CGFloat) -> RSFont { RSFont(pointSize: size) }
    public enum Weight { case ultraLight, light, regular, medium, semibold, bold, heavy, black }

    // UIFont descriptor surface (SSK's bold/italic body-range styling).
    public var fontDescriptor: UIFontDescriptor { UIFontDescriptor() }
    public convenience init(descriptor: UIFontDescriptor, size: CGFloat) {
        self.init(pointSize: size)
    }

    // UIFont(name:size:) is failable on UIKit (nil if the named font is absent).
    // The named font is unavailable on the Linux shim, so we return a font at the
    // requested size (callers fall back / force-unwrap; keeping it failable lets
    // `UIFont(name:size:)!` type-check).
    public convenience init?(name: String, size: CGFloat) {
        self.init(pointSize: size)
        _ = name
    }

    public func withSize(_ size: CGFloat) -> RSFont { RSFont(pointSize: size) }

    // Approximate metrics (the real values come from the font's glyph table,
    // unavailable here). lineHeight ~1.2x, capHeight ~0.7x point size -- enough
    // for the SSK avatar/text-measurement call sites to compile and lay out.
    public var lineHeight: CGFloat { pointSize * 1.2 }
    public var capHeight: CGFloat { pointSize * 0.7 }
    public var ascender: CGFloat { pointSize * 0.95 }
    public var descender: CGFloat { -pointSize * 0.25 }
}
// NOTE: no `UIFont` alias here. The UIKit shim owns the Linux UIFont class
// (since #427), and SignalServiceKit sees BOTH modules (QuillFoundation is
// re-exported through UIKit→QuartzCore), so a second public UIFont made every
// unqualified `UIFont` in SSK ambiguous. RSFont remains QuillFoundation's
// own font type for RS*-namespace consumers (NetNewsWire-family code).

// MARK: - UIFontDescriptor (Linux)
//
// On iOS this lives in UIKit; it's declared here (re-exported by UIKitShim) so
// QuillFoundation's RSFont.fontDescriptor can return it. The trait set is inert
// (no real font substitution on Linux) but withSymbolicTraits round-trips the
// requested traits so callers get a non-nil descriptor + a same-size font back.
public final class UIFontDescriptor: @unchecked Sendable {
    public struct SystemDesign: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }
        public static let `default` = SystemDesign(rawValue: "default")
        public static let rounded = SystemDesign(rawValue: "rounded")
        public static let monospaced = SystemDesign(rawValue: "monospaced")
        public static let serif = SystemDesign(rawValue: "serif")
    }

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
    public var symbolicTraits: SymbolicTraits
    public init(symbolicTraits: SymbolicTraits = []) {
        self.symbolicTraits = symbolicTraits
    }
    public func withSymbolicTraits(_ traits: SymbolicTraits) -> UIFontDescriptor? {
        UIFontDescriptor(symbolicTraits: symbolicTraits.union(traits))
    }

    public func withDesign(_ design: SystemDesign) -> UIFontDescriptor? {
        _ = design
        return self
    }
}

public extension CGSize {
    func equalTo(_ other: CGSize) -> Bool { self == other }
}

public extension CGPoint {
    func equalTo(_ other: CGPoint) -> Bool { self == other }
}

public extension CGRect {
    func applying(_ transform: CGAffineTransform) -> CGRect {
        offsetBy(dx: transform.tx, dy: transform.ty)
    }

    func fill() {}
}

public class RSScreen: NSObject, @unchecked Sendable {
    public static let main = RSScreen()
    public let bounds: CGRect
    public override init() {
        // Phase B: read real geometry from environment if available.
        // Honors GDK_SCALE / QUILL_SCREEN env vars; falls back to a
        // sane default so headless tools that just probe .bounds get
        // a non-degenerate rect.
        let env = ProcessInfo.processInfo.environment
        if let s = env["QUILL_SCREEN"],
           let parts = Optional(s.split(separator: "x")), parts.count == 2,
           let w = Double(parts[0]), let h = Double(parts[1]) {
            self.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        } else {
            self.bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
    }
    public static var maxScreenScale: CGFloat { 2.0 }
    public var backingScaleFactor: CGFloat {
        Double(ProcessInfo.processInfo.environment["GDK_SCALE"] ?? "1").map { CGFloat($0) } ?? 1
    }
    /// `UIScreen.scale` source-compat (SSK avatar/thumbnail pixel math).
    public var scale: CGFloat { backingScaleFactor }
    /// Pixel-space bounds (points * scale); SSK reads .nativeBounds.height for
    /// device-class heuristics.
    public var nativeBounds: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale)
    }
    public var nativeScale: CGFloat { scale }
    public var visibleFrame: CGRect { bounds }
    public var frame: CGRect { bounds }
    public var depth: Int { 32 }
    public var deviceDescription: [String: Any] { [:] }
}
public typealias UIScreen = RSScreen

// Disfavored: glibc 2.36+ exports the arc4random family, and both
// declarations are visible wherever Glibc is (often transitively) imported.
// The attribute lets the libc declaration win instead of erroring as
// ambiguous, while these stay available when only QuillFoundation is visible.
@_disfavoredOverload
public func arc4random() -> UInt32 {
    UInt32.random(in: UInt32.min...UInt32.max)
}

@_disfavoredOverload
public func arc4random_uniform(_ upperBound: UInt32) -> UInt32 {
    guard upperBound > 0 else {
        return 0
    }
    return UInt32.random(in: 0..<upperBound)
}
#endif

// MARK: - CGImage luminance (Linux shim for the netnewswire port)

// The generated netnewswire app compiles its own RSCore.ImageLuminanceType and
// CGImage.calculateLuminanceType(). On macOS those are in scope, so defining
// ours too makes `.dark`/`.bright` ambiguous and breaks local `swift build` /
// `swift test` for the whole package. Quill itself never uses these symbols --
// they exist only so the port resolves on Linux (where RSCore is not in scope).
// Scope the shim to Linux so it can't collide with RSCore on macOS.
#if os(Linux)
public enum ImageLuminanceType: Int, Sendable {
    case regular, dark, bright
}

public extension CGImage {
    func calculateLuminanceType() -> ImageLuminanceType? { .regular }
}
#endif

// MARK: - Darwin time-scale constants (Linux shim)

// <mach/clock_types.h>/<time.h> on Darwin define these as `unsigned long long`
// (UInt64). swift-corelibs-foundation does not vend them on Linux, yet SSK uses
// them for monotonic-clock and millisecond math (MonotonicDate, OWSReceiptManager,
// RemoteConfigManager, TSMessage, ...). Faithful values, Linux-gated so they
// can't collide with Darwin's own definitions on macOS/iOS.
#if os(Linux)
public let NSEC_PER_SEC: UInt64 = 1_000_000_000
public let NSEC_PER_MSEC: UInt64 = 1_000_000
public let NSEC_PER_USEC: UInt64 = 1_000
public let USEC_PER_SEC: UInt64 = 1_000_000
public let MSEC_PER_SEC: UInt64 = 1_000
#endif

// MARK: - Localization

#if !os(macOS) && !os(iOS)
public func NSLocalizedString(_ key: String, comment: String) -> String { key }
#endif

// MARK: - SQL placeholder helper
//
// `NSString.rs_SQLValueList(withPlaceholders:)` is canonically declared
// upstream in RSDatabaseObjC's NSString+RSDatabase.h. We don't redeclare
// it here — doing so caused a "type of expression is ambiguous" error
// in SyncDatabase / ArticlesDatabase where both definitions were visible.

// MARK: - Bootstrapping

public enum QuillBootstrapper {
    public static func bootstrap() {}
}
