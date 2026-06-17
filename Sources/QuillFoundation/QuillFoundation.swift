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

// QuillSelectorDispatching
// ========================
// The single canonical target-action dispatch contract on Linux (there is no
// Objective-C runtime to `perform` a `Selector` dynamically). The AppKit/UIKit
// source-lowering (QuillSourceLowering.AppKitLowering) rewrites `#selector(x)`
// -> `Selector("x")` and injects a `quillPerform(_:with:)` into the class body
// of every class that declared `@objc` action methods. Dispatch sites
// (UIControl.sendActions, NSControl.sendAction, UIGestureRecognizer, Timer,
// CADisplayLink, UndoManager) call
// `(target as? QuillSelectorDispatching)?.quillPerform(selector, with: sender)`.
//
// DISPATCH MUST BE DYNAMIC. The injected `quillPerform` is a real **class-body**
// method (NOT an extension method): extension methods are statically dispatched,
// so a subclass override declared in an extension can never be reached through a
// superclass-typed reference — the very bug this protocol's prior shape caused.
// The override chain is rooted at a class-body witness on the Apple-framework
// base classes that originate target-action: `UIResponder` (the whole
// UIView/UIViewController forest), plus the NSObject-direct UIKit/AVFoundation
// roots (`UIPresentationController`, `UIBarButtonItem`, `UIGestureRecognizer`,
// `AVPlayer`). On Linux `NSObject` is swift-corelibs-Foundation's and cannot be
// given an overridable member (a non-`@objc` method added in an extension of a
// foreign-module class is not overridable, and there is no @objc dynamism on
// Linux), so the base lives on the Quill shim roots instead — which is exactly
// where target-action originates on Apple platforms too.
//
// The lowering therefore emits, per class:
//   * super IS `NSObject` (a chain root): `: QuillSelectorDispatching` plus a
//     class-body witness with NO `override` — it newly conforms.
//   * super is anything else (a shim base, or another lowered class, possibly
//     through transparent intermediates): an `override func quillPerform` with
//     NO conformance clause, whose `default:` calls `super.quillPerform(...)`.
// This makes the per-class redundant-conformance and cannot-override-from-
// extension diagnostics structurally impossible: a subclass never restates the
// conformance, and the witness it overrides is a real (inherited) class member.
//
// On Apple platforms this is dormant — real target-action goes through the ObjC
// runtime — but compiles unmodified, keeping macOS `swift build`/`swift test`
// green.
public protocol QuillSelectorDispatching: AnyObject {
    /// Invoke the action identified by `selector`, passing the firing control as
    /// `sender`. The lowering injects a class-body witness that switches on
    /// `selector.name`; the no-op default below is the existential fail-safe so
    /// `(x as? QuillSelectorDispatching)?.quillPerform(...)` on a type with no
    /// matching case (or that reaches the base) does nothing rather than trapping.
    ///
    /// Witnesses are emitted `public`: a witness must be at least as accessible
    /// as its conformance, and lowered SignalUI has public/open conformers.
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

public class CGImage: Hashable, @unchecked Sendable {
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
        self.quillBytesPerRow = bytesPerRow
        _ = (bitsPerComponent, bitsPerPixel, space, bitmapInfo, provider, decode, shouldInterpolate, intent)
    }

    // Pixel dimensions + cropping (BadgeAssets spritesheets, image utilities).
    public var width: Int = 0
    public var height: Int = 0
    public var bytesPerRow: Int { quillBytesPerRow }
    public func cropping(to rect: CGRect) -> CGImage? {
        guard let crop = Self.pixelCropBounds(for: rect, imageWidth: width, imageHeight: height),
              let croppedBytesPerRow = Self.bytesPerRow(forPixelWidth: crop.width),
              let croppedPixelCount = Self.byteCount(height: crop.height, bytesPerRow: croppedBytesPerRow) else {
            return nil
        }

        let cropped = CGImage()
        cropped.width = crop.width
        cropped.height = crop.height
        cropped.quillBytesPerRow = croppedBytesPerRow
        guard let sourcePixels = quillBGRAPixels else { return cropped }
        guard let sourceBytesPerRow = quillResolvedBytesPerRow,
              let sourcePixelCount = Self.byteCount(height: height, bytesPerRow: sourceBytesPerRow),
              sourcePixels.count >= sourcePixelCount else {
            return nil
        }

        var croppedPixels = [UInt8](repeating: 0, count: croppedPixelCount)
        let rowByteCount = croppedBytesPerRow
        for y in 0..<crop.height {
            let sourceOffset = (crop.y + y) * sourceBytesPerRow + crop.x * Self.bytesPerPixel
            let destinationOffset = y * croppedBytesPerRow
            guard sourceOffset >= 0, sourceOffset + rowByteCount <= sourcePixels.count else { return nil }
            croppedPixels.replaceSubrange(
                destinationOffset..<(destinationOffset + rowByteCount),
                with: sourcePixels[sourceOffset..<(sourceOffset + rowByteCount)]
            )
        }
        cropped.quillBGRAPixels = croppedPixels
        return cropped
    }

    private static let bytesPerPixel = 4

    private var quillResolvedBytesPerRow: Int? {
        guard let minimumBytesPerRow = Self.bytesPerRow(forPixelWidth: width) else { return nil }
        let rowBytes = quillBytesPerRow > 0 ? quillBytesPerRow : minimumBytesPerRow
        guard rowBytes >= minimumBytesPerRow else { return nil }
        return rowBytes
    }

    private static func pixelCropBounds(
        for rect: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard imageWidth > 0, imageHeight > 0,
              rect.minX.isFinite, rect.minY.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else {
            return nil
        }

        let minX = Int(max(0, min(CGFloat(imageWidth), floor(rect.minX))))
        let minY = Int(max(0, min(CGFloat(imageHeight), floor(rect.minY))))
        let maxX = Int(max(0, min(CGFloat(imageWidth), ceil(rect.maxX))))
        let maxY = Int(max(0, min(CGFloat(imageHeight), ceil(rect.maxY))))
        guard minX < maxX, minY < maxY else { return nil }
        return (minX, minY, maxX - minX, maxY - minY)
    }

    private static func bytesPerRow(forPixelWidth width: Int) -> Int? {
        guard width >= 0 else { return nil }
        let result = width.multipliedReportingOverflow(by: bytesPerPixel)
        return result.overflow ? nil : result.partialValue
    }

    private static func byteCount(height: Int, bytesPerRow: Int) -> Int? {
        guard height >= 0, bytesPerRow >= 0 else { return nil }
        let result = height.multipliedReportingOverflow(by: bytesPerRow)
        return result.overflow ? nil : result.partialValue
    }

    public static func == (lhs: CGImage, rhs: CGImage) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

public typealias CFURL = URL

public final class CGDataProvider: @unchecked Sendable {
    public let data: Data?
    public let url: URL?

    public init() {
        self.data = nil
        self.url = nil
    }

    public init?(data: Data) {
        self.data = data
        self.url = nil
    }

    public init?(url: CFURL) {
        self.data = nil
        self.url = url
    }

    public init?(
        dataInfo info: UnsafeMutableRawPointer?,
        data: UnsafeRawPointer,
        size: Int,
        releaseData: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, Int) -> Void)?
    ) {
        self.data = Data(bytes: data, count: size)
        self.url = nil
        _ = (info, releaseData)
    }
}

public struct CGDataProviderDirectCallbacks {
    public var version: UInt32
    public var getBytePointer: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeRawPointer?)?
    public var releaseBytePointer: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> Void)?
    public var getBytesAtPosition: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer, UInt64, Int) -> Int)?
    public var releaseInfo: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?

    public init(
        version: UInt32,
        getBytePointer: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafeRawPointer?)?,
        releaseBytePointer: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> Void)?,
        getBytesAtPosition: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer, UInt64, Int) -> Int)?,
        releaseInfo: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
    ) {
        self.version = version
        self.getBytePointer = getBytePointer
        self.releaseBytePointer = releaseBytePointer
        self.getBytesAtPosition = getBytesAtPosition
        self.releaseInfo = releaseInfo
    }
}

public extension CGDataProvider {
    convenience init?(
        directInfo info: UnsafeMutableRawPointer?,
        size: Int64,
        callbacks: UnsafePointer<CGDataProviderDirectCallbacks>?
    ) {
        // Inert: no CoreGraphics consumer pulls bytes on Linux. The provider's
        // releaseInfo normally balances the caller's passRetained wrapper.
        if let info, let release = callbacks?.pointee.releaseInfo {
            release(info)
        }
        self.init()
        _ = size
    }
}

public final class CGFont: @unchecked Sendable {
    public let postScriptName: CFString?
    public let fullName: CFString?

    public init?(_ name: CFString) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.postScriptName = trimmed
        self.fullName = trimmed
    }

    public init?(_ dataProvider: CGDataProvider) {
        if let url = dataProvider.url {
            let name = url.deletingPathExtension().lastPathComponent
            self.postScriptName = name.isEmpty ? url.lastPathComponent : name
            self.fullName = self.postScriptName
        } else {
            self.postScriptName = "Imported Font"
            self.fullName = "Imported Font"
        }
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

// CoreGraphics path recording and path-element introspection. On Apple these
// are CoreGraphics types; here they live beside the Linux geometry shims and are
// re-exported by the CoreGraphics module. Euclid's `Path(CGPath)` reads them via
// `applyWithBlock`, and CGContext uses the recorded elements for path drawing.
public enum CGPathElementType: Int32, Sendable {
    case moveToPoint = 0
    case addLineToPoint = 1
    case addQuadCurveToPoint = 2
    case addCurveToPoint = 3
    case closeSubpath = 4
}

public struct CGPathElement {
    public var type: CGPathElementType
    /// Points buffer; length depends on `type` (1 for move/line, 2 for quad,
    /// 3 for cubic, 0 for close), as on macOS.
    public var points: UnsafeMutablePointer<CGPoint>
    public init(type: CGPathElementType, points: UnsafeMutablePointer<CGPoint>) {
        self.type = type
        self.points = points
    }
}

public typealias CGPathApplierFunction = (UnsafeMutableRawPointer?, UnsafePointer<CGPathElement>) -> Void

fileprivate typealias CGPathStorageElement = (type: CGPathElementType, points: [CGPoint])

public class CGPath: Hashable, @unchecked Sendable {
    private static let geometryTolerance: CGFloat = 0.0001

    /// Recorded path elements (type + its points), so the path is iterable.
    fileprivate var elements: [CGPathStorageElement] = []

    public init() {}

    public static func == (lhs: CGPath, rhs: CGPath) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public var isEmpty: Bool { elements.isEmpty }

    public var currentPoint: CGPoint {
        Self.currentPoint(in: elements) ?? .zero
    }

    public var boundingBox: CGRect {
        Self.boundingBox(for: elements.flatMap(\.points))
    }

    public var boundingBoxOfPath: CGRect {
        Self.boundingBox(for: Self.pathBoundingPoints(in: elements))
    }

    public convenience init(rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        elements = Self.applying(transform?.pointee, to: Self.rectElements(rect))
    }

    public convenience init(ellipseIn rect: CGRect, transform: UnsafePointer<CGAffineTransform>?) {
        self.init()
        elements = Self.applying(transform?.pointee, to: Self.ellipseElements(in: rect))
    }

    public convenience init(
        roundedRect rect: CGRect,
        cornerWidth: CGFloat,
        cornerHeight: CGFloat,
        transform: UnsafePointer<CGAffineTransform>?
    ) {
        self.init()
        elements = Self.applying(
            transform?.pointee,
            to: Self.roundedRectElements(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight)
        )
    }

    public func copy() -> CGPath? {
        let p = CGPath()
        p.elements = elements
        return p
    }
    public func copy(using transform: UnsafePointer<CGAffineTransform>?) -> CGPath? {
        let p = CGPath()
        p.elements = Self.applying(transform?.pointee, to: elements)
        return p
    }

    public func contains(_ point: CGPoint) -> Bool {
        contains(point, using: .winding, transform: .identity)
    }

    public func contains(
        _ point: CGPoint,
        using rule: CGPathFillRule = .winding,
        transform: CGAffineTransform = .identity
    ) -> Bool {
        let subpaths = flattenedSubpaths(transform: transform)
        if Self.pointIsOnBoundary(point, subpaths: subpaths) {
            return true
        }

        switch rule {
        case .evenOdd:
            return subpaths.reduce(false) { inside, subpath in
                inside != Self.subpathContainsEvenOdd(point, subpath: subpath)
            }
        case .winding:
            return subpaths.reduce(0) { winding, subpath in
                winding + Self.windingNumber(for: point, subpath: subpath)
            } != 0
        }
    }

    /// Iterate path elements (CGPath's `apply(info:function:)` / Swift's
    /// `applyWithBlock`). Each callback gets a pointer to a CGPathElement whose
    /// `points` buffer is valid only for that call, as on macOS.
    public func applyWithBlock(_ block: (UnsafePointer<CGPathElement>) -> Void) {
        for entry in elements {
            var pts = entry.points.isEmpty ? [CGPoint(x: 0, y: 0)] : entry.points
            pts.withUnsafeMutableBufferPointer { buf in
                var element = CGPathElement(type: entry.type, points: buf.baseAddress!)
                withUnsafePointer(to: &element) { block($0) }
            }
        }
    }

    public func apply(info: UnsafeMutableRawPointer?, function: CGPathApplierFunction) {
        applyWithBlock { elementPointer in
            function(info, elementPointer)
        }
    }

    fileprivate static func applying(
        _ transform: CGAffineTransform?,
        to elements: [CGPathStorageElement]
    ) -> [CGPathStorageElement] {
        guard let transform else { return elements }
        return elements.map { element in
            (element.type, element.points.map { $0.applying(transform) })
        }
    }

    fileprivate func flattenedSubpaths(transform: CGAffineTransform?) -> [[CGPoint]] {
        let transformPoint: (CGPoint) -> CGPoint = { point in
            guard let transform else { return point }
            return point.applying(transform)
        }
        var subpaths: [[CGPoint]] = []
        var current: [CGPoint] = []
        var currentPoint: CGPoint?
        var startPoint: CGPoint?

        func finishSubpath(closing: Bool) {
            if closing, let startPoint, current.last != startPoint {
                current.append(startPoint)
            }
            if !current.isEmpty {
                subpaths.append(current)
            }
            current = []
            currentPoint = nil
            startPoint = nil
        }

        for element in elements {
            switch element.type {
            case .moveToPoint:
                finishSubpath(closing: false)
                guard let point = element.points.first.map(transformPoint) else { continue }
                current = [point]
                currentPoint = point
                startPoint = point

            case .addLineToPoint:
                guard let point = element.points.first.map(transformPoint) else { continue }
                if current.isEmpty {
                    current = [point]
                    startPoint = point
                } else {
                    current.append(point)
                }
                currentPoint = point

            case .addQuadCurveToPoint:
                guard let from = currentPoint, element.points.count >= 2 else { continue }
                let control = transformPoint(element.points[0])
                let end = transformPoint(element.points[1])
                for step in 1...12 {
                    current.append(Self.quadPoint(from: from, control: control, end: end, t: CGFloat(step) / 12))
                }
                currentPoint = end

            case .addCurveToPoint:
                guard let from = currentPoint, element.points.count >= 3 else { continue }
                let control1 = transformPoint(element.points[0])
                let control2 = transformPoint(element.points[1])
                let end = transformPoint(element.points[2])
                for step in 1...16 {
                    current.append(Self.cubicPoint(from: from, control1: control1, control2: control2, end: end, t: CGFloat(step) / 16))
                }
                currentPoint = end

            case .closeSubpath:
                finishSubpath(closing: true)
            }
        }

        finishSubpath(closing: false)
        return subpaths
    }

    private static func boundingBox(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = Swift.min(minX, point.x)
            minY = Swift.min(minY, point.y)
            maxX = Swift.max(maxX, point.x)
            maxY = Swift.max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func subpathContainsEvenOdd(_ point: CGPoint, subpath: [CGPoint]) -> Bool {
        guard subpath.count >= 3 else { return false }
        let segments = segments(in: subpath)
        var inside = false
        for (a, b) in segments {
            if (a.y > point.y) != (b.y > point.y) {
                let x = a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if x > point.x {
                    inside.toggle()
                }
            }
        }
        return inside
    }

    private static func windingNumber(for point: CGPoint, subpath: [CGPoint]) -> Int {
        guard subpath.count >= 3 else { return 0 }
        let segments = segments(in: subpath)
        var winding = 0
        for (a, b) in segments {
            if a.y <= point.y {
                if b.y > point.y, isLeft(a, b, point) > 0 {
                    winding += 1
                }
            } else if b.y <= point.y, isLeft(a, b, point) < 0 {
                winding -= 1
            }
        }
        return winding
    }

    private static func pointIsOnBoundary(_ point: CGPoint, subpaths: [[CGPoint]]) -> Bool {
        subpaths.contains { subpath in
            segments(in: subpath).contains { pointIsOnSegment(point, $0.0, $0.1) }
        }
    }

    private static func segments(in subpath: [CGPoint]) -> [(CGPoint, CGPoint)] {
        guard subpath.count >= 2 else { return [] }
        return (0..<subpath.count).map { index in
            (subpath[index], subpath[(index + 1) % subpath.count])
        }
    }

    private static func pointIsOnSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Bool {
        let lengthSquared = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)
        if lengthSquared <= geometryTolerance * geometryTolerance {
            let dx = point.x - a.x
            let dy = point.y - a.y
            return dx * dx + dy * dy <= geometryTolerance * geometryTolerance
        }
        let cross = (point.y - a.y) * (b.x - a.x) - (point.x - a.x) * (b.y - a.y)
        guard abs(cross) <= geometryTolerance else { return false }
        let dot = (point.x - a.x) * (b.x - a.x) + (point.y - a.y) * (b.y - a.y)
        guard dot >= -geometryTolerance else { return false }
        return dot <= lengthSquared + geometryTolerance
    }

    private static func isLeft(_ a: CGPoint, _ b: CGPoint, _ point: CGPoint) -> CGFloat {
        (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
    }

    private static func quadPoint(from: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * from.x + 2 * mt * t * control.x + t * t * end.x,
            y: mt * mt * from.y + 2 * mt * t * control.y + t * t * end.y
        )
    }

    private static func cubicPoint(from: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * mt * from.x + 3 * mt * mt * t * control1.x + 3 * mt * t * t * control2.x + t * t * t * end.x,
            y: mt * mt * mt * from.y + 3 * mt * mt * t * control1.y + 3 * mt * t * t * control2.y + t * t * t * end.y
        )
    }

    private static func currentPoint(in elements: [CGPathStorageElement]) -> CGPoint? {
        var current: CGPoint?
        var subpathStart: CGPoint?

        for element in elements {
            switch element.type {
            case .moveToPoint:
                guard let point = element.points.first else { continue }
                current = point
                subpathStart = point

            case .addLineToPoint:
                guard let point = element.points.first else { continue }
                current = point
                if subpathStart == nil {
                    subpathStart = point
                }

            case .addQuadCurveToPoint:
                guard element.points.count >= 2 else { continue }
                current = element.points[1]
                if subpathStart == nil {
                    subpathStart = current
                }

            case .addCurveToPoint:
                guard element.points.count >= 3 else { continue }
                current = element.points[2]
                if subpathStart == nil {
                    subpathStart = current
                }

            case .closeSubpath:
                if let start = subpathStart {
                    current = start
                }
                subpathStart = current
            }
        }

        return current
    }

    private static func pathBoundingPoints(in elements: [CGPathStorageElement]) -> [CGPoint] {
        var points: [CGPoint] = []
        var current: CGPoint?
        var subpathStart: CGPoint?

        func include(_ point: CGPoint) {
            points.append(point)
        }

        for element in elements {
            switch element.type {
            case .moveToPoint:
                guard let point = element.points.first else { continue }
                include(point)
                current = point
                subpathStart = point

            case .addLineToPoint:
                guard let point = element.points.first else { continue }
                if let current {
                    include(current)
                }
                include(point)
                current = point
                if subpathStart == nil {
                    subpathStart = point
                }

            case .addQuadCurveToPoint:
                guard let from = current, element.points.count >= 2 else { continue }
                let control = element.points[0]
                let end = element.points[1]
                include(from)
                include(end)
                for t in quadraticExtrema(from: from, control: control, end: end) {
                    include(quadPoint(from: from, control: control, end: end, t: t))
                }
                current = end

            case .addCurveToPoint:
                guard let from = current, element.points.count >= 3 else { continue }
                let control1 = element.points[0]
                let control2 = element.points[1]
                let end = element.points[2]
                include(from)
                include(end)
                for t in cubicExtrema(from: from, control1: control1, control2: control2, end: end) {
                    include(cubicPoint(from: from, control1: control1, control2: control2, end: end, t: t))
                }
                current = end

            case .closeSubpath:
                if let current {
                    include(current)
                }
                if let start = subpathStart {
                    include(start)
                    current = start
                }
                subpathStart = current
            }
        }

        return points
    }

    private static func quadraticExtrema(from: CGPoint, control: CGPoint, end: CGPoint) -> [CGFloat] {
        [quadraticExtremum(from.x, control.x, end.x), quadraticExtremum(from.y, control.y, end.y)]
            .compactMap { $0 }
    }

    private static func quadraticExtremum(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat? {
        let denominator = p0 - 2 * p1 + p2
        guard abs(denominator) > geometryTolerance else { return nil }
        let t = (p0 - p1) / denominator
        return (t > 0 && t < 1) ? t : nil
    }

    private static func cubicExtrema(from: CGPoint, control1: CGPoint, control2: CGPoint, end: CGPoint) -> [CGFloat] {
        var values: [CGFloat] = []
        values.append(contentsOf: cubicExtrema(from.x, control1.x, control2.x, end.x))
        values.append(contentsOf: cubicExtrema(from.y, control1.y, control2.y, end.y))
        return values
    }

    private static func cubicExtrema(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> [CGFloat] {
        let a = -p0 + 3 * p1 - 3 * p2 + p3
        let b = 2 * (p0 - 2 * p1 + p2)
        let c = p1 - p0

        if abs(a) <= geometryTolerance {
            guard abs(b) > geometryTolerance else { return [] }
            let t = -c / b
            return (t > 0 && t < 1) ? [t] : []
        }

        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return [] }
        let root = discriminant.squareRoot()
        return [(-b + root) / (2 * a), (-b - root) / (2 * a)]
            .filter { $0 > 0 && $0 < 1 }
    }

    fileprivate static func arcCurveElements(
        center: CGPoint,
        radius: CGFloat,
        startAngle: CGFloat,
        endAngle: CGFloat,
        clockwise: Bool
    ) -> [CGPathStorageElement] {
        guard radius > 0, radius.isFinite else { return [] }
        let rawDelta = endAngle - startAngle
        var delta = rawDelta
        let fullTurn = CGFloat.pi * 2

        if abs(rawDelta) >= fullTurn {
            delta = clockwise ? -fullTurn : fullTurn
        } else if clockwise {
            while delta > 0 {
                delta -= fullTurn
            }
        } else {
            while delta < 0 {
                delta += fullTurn
            }
        }

        guard abs(delta) > geometryTolerance else { return [] }
        let segmentCount = max(1, Int(ceil(max(0, abs(delta) - geometryTolerance) / (CGFloat.pi / 2))))
        let segmentDelta = delta / CGFloat(segmentCount)
        var elements: [CGPathStorageElement] = []

        for segment in 0..<segmentCount {
            let a0 = startAngle + CGFloat(segment) * segmentDelta
            let a1 = a0 + segmentDelta
            let p0 = arcPoint(center: center, radius: radius, angle: a0)
            let p3 = arcPoint(center: center, radius: radius, angle: a1)
            let k = CGFloat(4.0 / 3.0) * tan(segmentDelta / 4)
            let c1 = CGPoint(
                x: p0.x - sin(a0) * radius * k,
                y: p0.y + cos(a0) * radius * k
            )
            let c2 = CGPoint(
                x: p3.x + sin(a1) * radius * k,
                y: p3.y - cos(a1) * radius * k
            )
            elements.append((.addCurveToPoint, [c1, c2, p3]))
        }

        return elements
    }

    fileprivate static func arcPoint(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    fileprivate static func pointsAreClose(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= geometryTolerance && abs(a.y - b.y) <= geometryTolerance
    }

    fileprivate static func normalizedVector(from start: CGPoint, to end: CGPoint) -> (x: CGFloat, y: CGFloat)? {
        normalizedVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    fileprivate static func normalizedVector(dx: CGFloat, dy: CGFloat) -> (x: CGFloat, y: CGFloat)? {
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > geometryTolerance else { return nil }
        return (dx / length, dy / length)
    }

    fileprivate static func rectElements(_ rect: CGRect) -> [CGPathStorageElement] {
        [
            (.moveToPoint, [CGPoint(x: rect.minX, y: rect.minY)]),
            (.addLineToPoint, [CGPoint(x: rect.maxX, y: rect.minY)]),
            (.addLineToPoint, [CGPoint(x: rect.maxX, y: rect.maxY)]),
            (.addLineToPoint, [CGPoint(x: rect.minX, y: rect.maxY)]),
            (.closeSubpath, []),
        ]
    }

    fileprivate static func roundedRectElements(
        _ rect: CGRect,
        cornerWidth: CGFloat,
        cornerHeight: CGFloat
    ) -> [CGPathStorageElement] {
        let radiusX = max(0, min(abs(cornerWidth), abs(rect.width) / 2))
        let radiusY = max(0, min(abs(cornerHeight), abs(rect.height) / 2))
        guard radiusX > 0, radiusY > 0 else {
            return rectElements(rect)
        }

        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let k = CGFloat(0.5522847498307936)
        let cX = radiusX * k
        let cY = radiusY * k

        if radiusX == abs(rect.width) / 2, radiusY == abs(rect.height) / 2 {
            return ellipseElements(in: rect)
        }

        return [
            (.moveToPoint, [CGPoint(x: minX + radiusX, y: minY)]),
            (.addLineToPoint, [CGPoint(x: maxX - radiusX, y: minY)]),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: maxX - radiusX + cX, y: minY),
                    CGPoint(x: maxX, y: minY + radiusY - cY),
                    CGPoint(x: maxX, y: minY + radiusY),
                ]
            ),
            (.addLineToPoint, [CGPoint(x: maxX, y: maxY - radiusY)]),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: maxX, y: maxY - radiusY + cY),
                    CGPoint(x: maxX - radiusX + cX, y: maxY),
                    CGPoint(x: maxX - radiusX, y: maxY),
                ]
            ),
            (.addLineToPoint, [CGPoint(x: minX + radiusX, y: maxY)]),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: minX + radiusX - cX, y: maxY),
                    CGPoint(x: minX, y: maxY - radiusY + cY),
                    CGPoint(x: minX, y: maxY - radiusY),
                ]
            ),
            (.addLineToPoint, [CGPoint(x: minX, y: minY + radiusY)]),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: minX, y: minY + radiusY - cY),
                    CGPoint(x: minX + radiusX - cX, y: minY),
                    CGPoint(x: minX + radiusX, y: minY),
                ]
            ),
            (.closeSubpath, []),
        ]
    }

    fileprivate static func ellipseElements(in rect: CGRect) -> [CGPathStorageElement] {
        let minX = rect.minX
        let midX = rect.midX
        let maxX = rect.maxX
        let minY = rect.minY
        let midY = rect.midY
        let maxY = rect.maxY
        let cX = abs(rect.width) / 2 * CGFloat(0.5522847498307936)
        let cY = abs(rect.height) / 2 * CGFloat(0.5522847498307936)

        return [
            (.moveToPoint, [CGPoint(x: midX, y: minY)]),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: midX + cX, y: minY),
                    CGPoint(x: maxX, y: midY - cY),
                    CGPoint(x: maxX, y: midY),
                ]
            ),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: maxX, y: midY + cY),
                    CGPoint(x: midX + cX, y: maxY),
                    CGPoint(x: midX, y: maxY),
                ]
            ),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: midX - cX, y: maxY),
                    CGPoint(x: minX, y: midY + cY),
                    CGPoint(x: minX, y: midY),
                ]
            ),
            (
                .addCurveToPoint,
                [
                    CGPoint(x: minX, y: midY - cY),
                    CGPoint(x: midX - cX, y: minY),
                    CGPoint(x: midX, y: minY),
                ]
            ),
            (.closeSubpath, []),
        ]
    }
}
public final class CGMutablePath: CGPath, @unchecked Sendable {
    public override init() { super.init() }
    public func move(to point: CGPoint) { elements.append((.moveToPoint, [point])) }
    public func addLine(to point: CGPoint) { elements.append((.addLineToPoint, [point])) }
    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }
    public func addRect(_ rect: CGRect) {
        elements.append(contentsOf: Self.rectElements(rect))
    }
    public func addRect(_ rect: CGRect, transform: CGAffineTransform) {
        elements.append(contentsOf: Self.applying(transform, to: Self.rectElements(rect)))
    }
    public func addRects(_ rects: [CGRect]) {
        for rect in rects {
            addRect(rect)
        }
    }
    public func addRects(_ rects: [CGRect], transform: CGAffineTransform) {
        for rect in rects {
            addRect(rect, transform: transform)
        }
    }
    public func addEllipse(in rect: CGRect) {
        elements.append(contentsOf: Self.ellipseElements(in: rect))
    }
    public func addEllipse(in rect: CGRect, transform: CGAffineTransform) {
        elements.append(contentsOf: Self.applying(transform, to: Self.ellipseElements(in: rect)))
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append((.addCurveToPoint, [control1, control2, end]))
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        elements.append((.addQuadCurveToPoint, [control, end]))
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        guard radius > 0, radius.isFinite else { return }
        let start = Self.arcPoint(center: center, radius: radius, angle: startAngle)
        if isEmpty {
            move(to: start)
        } else if !Self.pointsAreClose(currentPoint, start) {
            addLine(to: start)
        }
        elements.append(contentsOf: Self.arcCurveElements(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        ))
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {
        guard radius > 0, radius.isFinite else { return }
        guard !isEmpty else {
            move(to: tangent1End)
            return
        }

        let current = currentPoint
        let incoming = Self.normalizedVector(from: tangent1End, to: current)
        let outgoing = Self.normalizedVector(from: tangent1End, to: tangent2End)
        guard let incoming, let outgoing else {
            addLine(to: tangent1End)
            return
        }

        let dot = max(-1, min(1, incoming.x * outgoing.x + incoming.y * outgoing.y))
        let angle = acos(dot)
        guard angle > 0.0001, abs(CGFloat.pi - angle) > 0.0001 else {
            addLine(to: tangent1End)
            return
        }

        let tangentDistance = radius / tan(angle / 2)
        guard tangentDistance.isFinite else {
            addLine(to: tangent1End)
            return
        }

        let tangentStart = CGPoint(
            x: tangent1End.x + incoming.x * tangentDistance,
            y: tangent1End.y + incoming.y * tangentDistance
        )
        let tangentEnd = CGPoint(
            x: tangent1End.x + outgoing.x * tangentDistance,
            y: tangent1End.y + outgoing.y * tangentDistance
        )

        let bisector = Self.normalizedVector(
            dx: incoming.x + outgoing.x,
            dy: incoming.y + outgoing.y
        )
        guard let bisector else {
            addLine(to: tangent1End)
            return
        }

        let centerDistance = radius / sin(angle / 2)
        let center = CGPoint(
            x: tangent1End.x + bisector.x * centerDistance,
            y: tangent1End.y + bisector.y * centerDistance
        )
        let startAngle = atan2(tangentStart.y - center.y, tangentStart.x - center.x)
        let endAngle = atan2(tangentEnd.y - center.y, tangentEnd.x - center.x)
        let clockwise = incoming.x * outgoing.y - incoming.y * outgoing.x > 0

        if !Self.pointsAreClose(current, tangentStart) {
            addLine(to: tangentStart)
        }
        elements.append(contentsOf: Self.arcCurveElements(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        ))
    }
    public func addRoundedRect(in rect: CGRect, cornerWidth: CGFloat, cornerHeight: CGFloat) {
        elements.append(contentsOf: Self.roundedRectElements(rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight))
    }
    public func addPath(_ path: CGPath) { elements.append(contentsOf: path.elements) }
    public func addPath(_ path: CGPath, transform: CGAffineTransform) {
        elements.append(contentsOf: Self.applying(transform, to: path.elements))
    }
    public func closeSubpath() { elements.append((.closeSubpath, [])) }
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
    fileprivate let quillStops: [QuillGradientStop]

    public init?(colorsSpace space: Any?, colors: Any?, locations: Any?) {
        _ = space
        guard let parsedColors = Self.quillColors(from: colors), parsedColors.count >= 2 else {
            return nil
        }
        self.quillStops = Self.quillStops(colors: parsedColors, locations: Self.quillLocations(from: locations, count: parsedColors.count))
    }

    public init?(colorsSpace space: CGColorSpace?, colors: Any, locations: UnsafePointer<CGFloat>?) {
        _ = space
        guard let parsedColors = Self.quillColors(from: colors), parsedColors.count >= 2 else {
            return nil
        }
        let parsedLocations = locations.map { pointer in
            (0..<parsedColors.count).map { pointer[$0] }
        }
        self.quillStops = Self.quillStops(colors: parsedColors, locations: parsedLocations)
    }

    fileprivate func quillRGBA(at location: CGFloat) -> [CGFloat] {
        let location = Self.quillClampedUnit(location)
        guard let first = quillStops.first else {
            return [0, 0, 0, 1]
        }
        guard let last = quillStops.last else {
            return first.rgba
        }
        if location <= first.location {
            return first.rgba
        }
        if location >= last.location {
            return last.rgba
        }

        for index in 0..<(quillStops.count - 1) {
            let lower = quillStops[index]
            let upper = quillStops[index + 1]
            guard location >= lower.location, location <= upper.location else {
                continue
            }
            let span = upper.location - lower.location
            let amount = abs(span) <= 0.000001 ? 0 : (location - lower.location) / span
            return zip(lower.rgba, upper.rgba).map { start, end in
                start + (end - start) * amount
            }
        }

        return last.rgba
    }

    private static func quillStops(colors: [RSCGColor], locations: [CGFloat]?) -> [QuillGradientStop] {
        let resolvedLocations = locations?.count == colors.count
            ? locations!
            : quillEvenlySpacedLocations(count: colors.count)
        return zip(colors, resolvedLocations)
            .map { color, location in
                QuillGradientStop(location: quillClampedUnit(location), rgba: quillNormalizedRGBA(color))
            }
            .sorted { $0.location < $1.location }
    }

    private static func quillColors(from colors: Any?) -> [RSCGColor]? {
        switch colors {
        case let colors as [RSCGColor]:
            return colors
        case let colors as [Any]:
            let parsed = colors.compactMap { $0 as? RSCGColor }
            return parsed.count == colors.count ? parsed : nil
        case let colors as NSArray:
            let parsed = colors.compactMap { $0 as? RSCGColor }
            return parsed.count == colors.count ? parsed : nil
        default:
            return nil
        }
    }

    private static func quillLocations(from locations: Any?, count: Int) -> [CGFloat]? {
        switch locations {
        case let locations as [CGFloat]:
            return locations.count == count ? locations : nil
        case let locations as [Double]:
            return locations.count == count ? locations.map { CGFloat($0) } : nil
        case let locations as [NSNumber]:
            return locations.count == count ? locations.map { CGFloat(truncating: $0) } : nil
        case let locations as [Any]:
            let parsed = locations.compactMap { value -> CGFloat? in
                switch value {
                case let value as CGFloat:
                    return value
                case let value as Double:
                    return CGFloat(value)
                case let value as NSNumber:
                    return CGFloat(truncating: value)
                default:
                    return nil
                }
            }
            return parsed.count == count ? parsed : nil
        case .none:
            return nil
        default:
            return nil
        }
    }

    private static func quillEvenlySpacedLocations(count: Int) -> [CGFloat] {
        guard count > 1 else {
            return [0]
        }
        return (0..<count).map { CGFloat($0) / CGFloat(count - 1) }
    }

    private static func quillNormalizedRGBA(_ color: RSCGColor) -> [CGFloat] {
        let components = color.components ?? [0, 0, 0, 1]
        let rgba: [CGFloat]
        switch components.count {
        case 1:
            rgba = [components[0], components[0], components[0], 1]
        case 2:
            rgba = [components[0], components[0], components[0], components[1]]
        case 3:
            rgba = [components[0], components[1], components[2], 1]
        default:
            rgba = Array(components.prefix(4))
        }
        return rgba.map(quillClampedUnit)
    }

    private static func quillClampedUnit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return Swift.max(0, Swift.min(1, value))
    }
}

fileprivate struct QuillGradientStop {
    var location: CGFloat
    var rgba: [CGFloat]
}

// Pixel-format flags for a CGContext bitmap context. Raw values match Apple's
// <CoreGraphics/CGImage.h> so callers that OR them into a UInt32 bitmapInfo (e.g.
// BlurHash: byteOrder32Big | premultipliedLast) get the right bits.
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
    private var quillBitmapBytes: [UInt8]?
    private var quillFillRGBA: [CGFloat] = [0, 0, 0, 1]
    private var quillStrokeRGBA: [CGFloat] = [0, 0, 0, 1]
    private var quillLineWidth: CGFloat = 1
    private var quillLineCap: CGLineCap = .butt
    private var quillLineJoin: CGLineJoin = .miter
    private var quillMiterLimit: CGFloat = 10
    private var quillLineDashPhase: CGFloat = 0
    private var quillLineDashLengths: [CGFloat] = []
    private var quillAllowsAntialiasing: Bool = true
    private var quillShouldAntialias: Bool = true
    private var quillAllowsFontSmoothingState: Bool = true
    private var quillShouldSmoothFontsState: Bool = true
    private var quillAllowsFontSubpixelPositioningState: Bool = true
    private var quillShouldSubpixelPositionFontsState: Bool = true
    private var quillAllowsFontSubpixelQuantizationState: Bool = true
    private var quillShouldSubpixelQuantizeFontsState: Bool = true
    private var quillAlpha: CGFloat = 1
    private var quillBlendMode: CGBlendMode = .normal
    private var quillShadow: QuillShadow?
    private var quillCTM: CGAffineTransform = .identity
    private var quillClipRegions: [QuillClipRegion] = []
    private var quillStateStack: [QuillGraphicsState] = []
    private var quillTransparencyLayerStack: [QuillTransparencyLayer] = []
    private var quillCurrentPath = CGMutablePath()

    private struct QuillGraphicsState {
        var fillRGBA: [CGFloat]
        var strokeRGBA: [CGFloat]
        var lineWidth: CGFloat
        var lineCap: CGLineCap
        var lineJoin: CGLineJoin
        var miterLimit: CGFloat
        var lineDashPhase: CGFloat
        var lineDashLengths: [CGFloat]
        var allowsAntialiasing: Bool
        var shouldAntialias: Bool
        var allowsFontSmoothing: Bool
        var shouldSmoothFonts: Bool
        var allowsFontSubpixelPositioning: Bool
        var shouldSubpixelPositionFonts: Bool
        var allowsFontSubpixelQuantization: Bool
        var shouldSubpixelQuantizeFonts: Bool
        var alpha: CGFloat
        var blendMode: CGBlendMode
        var shadow: QuillShadow?
        var ctm: CGAffineTransform
        var clipRegions: [QuillClipRegion]
    }

    private typealias QuillPixelBounds = (minX: Int, minY: Int, maxX: Int, maxY: Int)

    private struct QuillBitmapImageSource {
        var width: Int
        var height: Int
        var bytesPerRow: Int
        var pixels: [UInt8]
    }

    private struct QuillPremultipliedBGRA {
        var blue: CGFloat
        var green: CGFloat
        var red: CGFloat
        var alpha: CGFloat
    }

    private struct QuillShadow {
        var offset: CGSize
        var blur: CGFloat
        var colorRGBA: [CGFloat]
    }

    private struct QuillTransparencyLayer {
        var parentBytes: [UInt8]
        var alpha: CGFloat
        var blendMode: CGBlendMode
        var shadow: QuillShadow?
        var clipRegions: [QuillClipRegion]
    }

    private enum QuillClipRegion {
        case path(path: CGPath, rule: CGPathFillRule, transform: CGAffineTransform)
        case mask(rect: CGRect, source: QuillBitmapImageSource, transform: CGAffineTransform)
    }

    private struct QuillStrokeSegment {
        var start: CGPoint
        var end: CGPoint
        var dashStart: CGFloat
        var joinsNext: Bool

        var length: CGFloat {
            let dx = end.x - start.x
            let dy = end.y - start.y
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    private struct QuillLineDash {
        var phase: CGFloat
        var lengths: [CGFloat]
        var cycleLength: CGFloat
    }

    public init() {}

    private static func quillResolvedBytesPerRow(
        width: Int,
        bitsPerComponent: Int,
        bytesPerRow: Int
    ) -> Int? {
        if bytesPerRow > 0 {
            return bytesPerRow
        }
        guard bitsPerComponent == 8 else {
            return nil
        }
        return quillPixelByteCount(width: width)
    }

    private static func quillPixelByteCount(width: Int) -> Int? {
        guard width > 0 else {
            return nil
        }
        let result = width.multipliedReportingOverflow(by: 4)
        return result.overflow ? nil : result.partialValue
    }

    private static func quillBitmapStorageByteCount(height: Int, bytesPerRow: Int) -> Int? {
        guard height > 0, bytesPerRow > 0 else {
            return nil
        }
        let result = height.multipliedReportingOverflow(by: bytesPerRow)
        return result.overflow ? nil : result.partialValue
    }

    private static func quillSupportsDirectBitmapDrawing(
        width: Int,
        height: Int,
        bitsPerComponent: Int,
        bitsPerPixel: Int,
        bytesPerRow: Int
    ) -> Bool {
        guard width > 0, height > 0, bitsPerComponent == 8, bitsPerPixel == 32,
              let minimumBytesPerRow = quillPixelByteCount(width: width)
        else {
            return false
        }
        return bytesPerRow >= minimumBytesPerRow
    }

    private var quillCanDrawCurrentBitmap: Bool {
        Self.quillSupportsDirectBitmapDrawing(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow
        )
    }

    private static func quillClampedUnit(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 0
        }
        return Swift.max(0, Swift.min(1, value))
    }

    private static func quillClampedByte(_ value: CGFloat) -> UInt8 {
        UInt8((quillClampedUnit(value) * 255).rounded())
    }

    private static func quillNormalizedFillRGBA(_ rgba: [CGFloat]) -> [CGFloat] {
        let red = rgba.indices.contains(0) ? rgba[0] : 0
        let green = rgba.indices.contains(1) ? rgba[1] : 0
        let blue = rgba.indices.contains(2) ? rgba[2] : 0
        let alpha = rgba.indices.contains(3) ? rgba[3] : 1
        return [
            quillClampedUnit(red),
            quillClampedUnit(green),
            quillClampedUnit(blue),
            quillClampedUnit(alpha),
        ]
    }

    private static func quillNormalizedDashLengths(_ lengths: [CGFloat]) -> [CGFloat] {
        guard !lengths.isEmpty,
              lengths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return []
        }
        return lengths.count.isMultiple(of: 2) ? lengths : lengths + lengths
    }

    private static func quillBitmapSource(from image: Any) -> QuillBitmapImageSource? {
        let cgImage: CGImage?
        switch image {
        case let image as CGImage:
            cgImage = image
        case let image as RSImage:
            cgImage = image.cgImage
        default:
            cgImage = nil
        }

        guard let cgImage,
              cgImage.width > 0,
              cgImage.height > 0,
              let pixels = cgImage.quillBGRAPixels,
              let minimumBytesPerRow = quillPixelByteCount(width: cgImage.width),
              cgImage.quillBytesPerRow >= minimumBytesPerRow,
              let requiredByteCount = quillBitmapStorageByteCount(
                height: cgImage.height,
                bytesPerRow: cgImage.quillBytesPerRow
              ),
              pixels.count >= requiredByteCount
        else {
            return nil
        }

        return QuillBitmapImageSource(
            width: cgImage.width,
            height: cgImage.height,
            bytesPerRow: cgImage.quillBytesPerRow,
            pixels: pixels
        )
    }

    private static func quillPremultipliedColor(
        from rgba: [CGFloat],
        alphaScale: CGFloat
    ) -> QuillPremultipliedBGRA? {
        let red = rgba.indices.contains(0) ? rgba[0] : 0
        let green = rgba.indices.contains(1) ? rgba[1] : 0
        let blue = rgba.indices.contains(2) ? rgba[2] : 0
        let alpha = rgba.indices.contains(3) ? rgba[3] : 1
        let sourceAlpha = quillClampedUnit(alpha * alphaScale)
        guard sourceAlpha > 0 else {
            return nil
        }

        return QuillPremultipliedBGRA(
            blue: blue * sourceAlpha,
            green: green * sourceAlpha,
            red: red * sourceAlpha,
            alpha: sourceAlpha
        )
    }

    private func quillPremultipliedColor(from rgba: [CGFloat]) -> QuillPremultipliedBGRA? {
        Self.quillPremultipliedColor(from: rgba, alphaScale: quillAlpha)
    }

    private func quillPremultipliedFillColor() -> QuillPremultipliedBGRA? {
        quillPremultipliedColor(from: quillFillRGBA)
    }

    private func quillPremultipliedStrokeColor() -> QuillPremultipliedBGRA? {
        quillPremultipliedColor(from: quillStrokeRGBA)
    }

    private func quillCompositePremultipliedBGRA(
        _ source: QuillPremultipliedBGRA,
        into pixels: UnsafeMutableBufferPointer<UInt8>,
        at offset: Int
    ) {
        Self.quillCompositePremultipliedBGRA(source, into: pixels, at: offset, blendMode: quillBlendMode)
    }

    private static func quillCompositePremultipliedBGRA(
        _ source: QuillPremultipliedBGRA,
        into pixels: UnsafeMutableBufferPointer<UInt8>,
        at offset: Int,
        blendMode: CGBlendMode = .normal
    ) {
        guard offset >= 0, offset + 3 < pixels.count else {
            return
        }
        let sourceAlpha = quillClampedUnit(source.alpha)
        if sourceAlpha <= 0, blendMode != .clear {
            return
        }

        let destination = QuillPremultipliedBGRA(
            blue: CGFloat(pixels[offset]) / 255,
            green: CGFloat(pixels[offset + 1]) / 255,
            red: CGFloat(pixels[offset + 2]) / 255,
            alpha: CGFloat(pixels[offset + 3]) / 255
        )
        let result = quillBlendedPremultipliedBGRA(source: source, destination: destination, mode: blendMode)

        pixels[offset] = quillClampedByte(result.blue)
        pixels[offset + 1] = quillClampedByte(result.green)
        pixels[offset + 2] = quillClampedByte(result.red)
        pixels[offset + 3] = quillClampedByte(result.alpha)
    }

    private static func quillBlendedPremultipliedBGRA(
        source: QuillPremultipliedBGRA,
        destination: QuillPremultipliedBGRA,
        mode: CGBlendMode
    ) -> QuillPremultipliedBGRA {
        let sourceAlpha = quillClampedUnit(source.alpha)
        let destinationAlpha = quillClampedUnit(destination.alpha)

        switch mode {
        case .clear:
            return QuillPremultipliedBGRA(blue: 0, green: 0, red: 0, alpha: 0)
        case .copy:
            return source
        case .sourceIn:
            return quillPremultiplied(source, multipliedBy: destinationAlpha)
        case .sourceOut:
            return quillPremultiplied(source, multipliedBy: 1 - destinationAlpha)
        case .sourceAtop:
            return quillAdd(
                quillPremultiplied(source, multipliedBy: destinationAlpha),
                quillPremultiplied(destination, multipliedBy: 1 - sourceAlpha)
            )
        case .destinationOver:
            return quillAdd(
                quillPremultiplied(source, multipliedBy: 1 - destinationAlpha),
                destination
            )
        case .destinationIn:
            return quillPremultiplied(destination, multipliedBy: sourceAlpha)
        case .destinationOut:
            return quillPremultiplied(destination, multipliedBy: 1 - sourceAlpha)
        case .destinationAtop:
            return quillAdd(
                quillPremultiplied(destination, multipliedBy: sourceAlpha),
                quillPremultiplied(source, multipliedBy: 1 - destinationAlpha)
            )
        case .xor:
            return quillAdd(
                quillPremultiplied(source, multipliedBy: 1 - destinationAlpha),
                quillPremultiplied(destination, multipliedBy: 1 - sourceAlpha)
            )
        case .plusLighter:
            return QuillPremultipliedBGRA(
                blue: Swift.min(1, source.blue + destination.blue),
                green: Swift.min(1, source.green + destination.green),
                red: Swift.min(1, source.red + destination.red),
                alpha: Swift.min(1, sourceAlpha + destinationAlpha)
            )
        case .plusDarker:
            return QuillPremultipliedBGRA(
                blue: Swift.max(0, source.blue + destination.blue - 1),
                green: Swift.max(0, source.green + destination.green - 1),
                red: Swift.max(0, source.red + destination.red - 1),
                alpha: Swift.max(0, sourceAlpha + destinationAlpha - 1)
            )
        case .normal:
            return quillSourceOver(source: source, destination: destination)
        case .hue, .saturation, .color, .luminosity:
            return quillBlendNonSeparable(source: source, destination: destination, mode: mode)
        default:
            return quillBlendSeparable(source: source, destination: destination, mode: mode)
        }
    }

    private static func quillSourceOver(
        source: QuillPremultipliedBGRA,
        destination: QuillPremultipliedBGRA
    ) -> QuillPremultipliedBGRA {
        let inverseSourceAlpha = 1 - quillClampedUnit(source.alpha)
        return QuillPremultipliedBGRA(
            blue: source.blue + destination.blue * inverseSourceAlpha,
            green: source.green + destination.green * inverseSourceAlpha,
            red: source.red + destination.red * inverseSourceAlpha,
            alpha: source.alpha + destination.alpha * inverseSourceAlpha
        )
    }

    private static func quillBlendSeparable(
        source: QuillPremultipliedBGRA,
        destination: QuillPremultipliedBGRA,
        mode: CGBlendMode
    ) -> QuillPremultipliedBGRA {
        let sourceAlpha = quillClampedUnit(source.alpha)
        let destinationAlpha = quillClampedUnit(destination.alpha)
        guard sourceAlpha > 0, destinationAlpha > 0 else {
            return quillSourceOver(source: source, destination: destination)
        }

        let sourceColor = quillUnpremultiplied(source)
        let destinationColor = quillUnpremultiplied(destination)
        let blended = QuillPremultipliedBGRA(
            blue: quillBlendChannel(source: sourceColor.blue, destination: destinationColor.blue, mode: mode),
            green: quillBlendChannel(source: sourceColor.green, destination: destinationColor.green, mode: mode),
            red: quillBlendChannel(source: sourceColor.red, destination: destinationColor.red, mode: mode),
            alpha: 1
        )

        return quillCompositeBlendedColor(
            blended,
            source: source,
            destination: destination,
            sourceAlpha: sourceAlpha,
            destinationAlpha: destinationAlpha
        )
    }

    private static func quillBlendNonSeparable(
        source: QuillPremultipliedBGRA,
        destination: QuillPremultipliedBGRA,
        mode: CGBlendMode
    ) -> QuillPremultipliedBGRA {
        let sourceAlpha = quillClampedUnit(source.alpha)
        let destinationAlpha = quillClampedUnit(destination.alpha)
        guard sourceAlpha > 0, destinationAlpha > 0 else {
            return quillSourceOver(source: source, destination: destination)
        }

        let sourceColor = quillUnpremultiplied(source)
        let destinationColor = quillUnpremultiplied(destination)
        let blended: QuillPremultipliedBGRA
        switch mode {
        case .hue:
            blended = quillSetLuminosity(
                quillSetSaturation(sourceColor, to: quillSaturation(destinationColor)),
                to: quillLuminosity(destinationColor)
            )
        case .saturation:
            blended = quillSetLuminosity(
                quillSetSaturation(destinationColor, to: quillSaturation(sourceColor)),
                to: quillLuminosity(destinationColor)
            )
        case .color:
            blended = quillSetLuminosity(sourceColor, to: quillLuminosity(destinationColor))
        case .luminosity:
            blended = quillSetLuminosity(destinationColor, to: quillLuminosity(sourceColor))
        default:
            blended = sourceColor
        }

        return quillCompositeBlendedColor(
            blended,
            source: source,
            destination: destination,
            sourceAlpha: sourceAlpha,
            destinationAlpha: destinationAlpha
        )
    }

    private static func quillCompositeBlendedColor(
        _ blended: QuillPremultipliedBGRA,
        source: QuillPremultipliedBGRA,
        destination: QuillPremultipliedBGRA,
        sourceAlpha: CGFloat,
        destinationAlpha: CGFloat
    ) -> QuillPremultipliedBGRA {
        let sourceScale = sourceAlpha * destinationAlpha
        return QuillPremultipliedBGRA(
            blue: source.blue * (1 - destinationAlpha) + destination.blue * (1 - sourceAlpha) + blended.blue * sourceScale,
            green: source.green * (1 - destinationAlpha) + destination.green * (1 - sourceAlpha) + blended.green * sourceScale,
            red: source.red * (1 - destinationAlpha) + destination.red * (1 - sourceAlpha) + blended.red * sourceScale,
            alpha: sourceAlpha + destinationAlpha * (1 - sourceAlpha)
        )
    }

    private static func quillBlendChannel(source: CGFloat, destination: CGFloat, mode: CGBlendMode) -> CGFloat {
        switch mode {
        case .multiply:
            return source * destination
        case .screen:
            return source + destination - source * destination
        case .overlay:
            return destination <= 0.5
                ? 2 * source * destination
                : 1 - 2 * (1 - source) * (1 - destination)
        case .darken:
            return Swift.min(source, destination)
        case .lighten:
            return Swift.max(source, destination)
        case .colorDodge:
            return source >= 1 ? 1 : Swift.min(1, destination / (1 - source))
        case .colorBurn:
            return source <= 0 ? 0 : 1 - Swift.min(1, (1 - destination) / source)
        case .softLight:
            if source <= 0.5 {
                return destination - (1 - 2 * source) * destination * (1 - destination)
            }
            let d = destination <= 0.25
                ? ((16 * destination - 12) * destination + 4) * destination
                : destination.squareRoot()
            return destination + (2 * source - 1) * (d - destination)
        case .hardLight:
            return source <= 0.5
                ? 2 * source * destination
                : 1 - 2 * (1 - source) * (1 - destination)
        case .difference:
            return abs(destination - source)
        case .exclusion:
            return source + destination - 2 * source * destination
        default:
            return source
        }
    }

    private static func quillLuminosity(_ color: QuillPremultipliedBGRA) -> CGFloat {
        0.3 * color.red + 0.59 * color.green + 0.11 * color.blue
    }

    private static func quillSaturation(_ color: QuillPremultipliedBGRA) -> CGFloat {
        Swift.max(color.red, color.green, color.blue) - Swift.min(color.red, color.green, color.blue)
    }

    private static func quillSetLuminosity(
        _ color: QuillPremultipliedBGRA,
        to luminosity: CGFloat
    ) -> QuillPremultipliedBGRA {
        let delta = luminosity - quillLuminosity(color)
        return quillClipColor(QuillPremultipliedBGRA(
            blue: color.blue + delta,
            green: color.green + delta,
            red: color.red + delta,
            alpha: 1
        ))
    }

    private static func quillClipColor(_ color: QuillPremultipliedBGRA) -> QuillPremultipliedBGRA {
        let luminosity = quillLuminosity(color)
        let minimum = Swift.min(color.red, color.green, color.blue)
        let maximum = Swift.max(color.red, color.green, color.blue)
        var red = color.red
        var green = color.green
        var blue = color.blue

        if minimum < 0, luminosity != minimum {
            red = luminosity + (red - luminosity) * luminosity / (luminosity - minimum)
            green = luminosity + (green - luminosity) * luminosity / (luminosity - minimum)
            blue = luminosity + (blue - luminosity) * luminosity / (luminosity - minimum)
        }

        if maximum > 1, maximum != luminosity {
            red = luminosity + (red - luminosity) * (1 - luminosity) / (maximum - luminosity)
            green = luminosity + (green - luminosity) * (1 - luminosity) / (maximum - luminosity)
            blue = luminosity + (blue - luminosity) * (1 - luminosity) / (maximum - luminosity)
        }

        return QuillPremultipliedBGRA(
            blue: quillClampedUnit(blue),
            green: quillClampedUnit(green),
            red: quillClampedUnit(red),
            alpha: 1
        )
    }

    private static func quillSetSaturation(
        _ color: QuillPremultipliedBGRA,
        to saturation: CGFloat
    ) -> QuillPremultipliedBGRA {
        var channels = [
            (keyPath: \QuillPremultipliedBGRA.red, value: color.red),
            (keyPath: \QuillPremultipliedBGRA.green, value: color.green),
            (keyPath: \QuillPremultipliedBGRA.blue, value: color.blue),
        ].sorted { lhs, rhs in lhs.value < rhs.value }

        if channels[2].value > channels[0].value {
            channels[1].value = (channels[1].value - channels[0].value) * saturation / (channels[2].value - channels[0].value)
            channels[2].value = saturation
        } else {
            channels[1].value = 0
            channels[2].value = 0
        }
        channels[0].value = 0

        var result = QuillPremultipliedBGRA(blue: 0, green: 0, red: 0, alpha: 1)
        for channel in channels {
            result[keyPath: channel.keyPath] = channel.value
        }
        return result
    }

    private static func quillPremultiplied(
        _ color: QuillPremultipliedBGRA,
        multipliedBy alpha: CGFloat
    ) -> QuillPremultipliedBGRA {
        let alpha = quillClampedUnit(alpha)
        return QuillPremultipliedBGRA(
            blue: color.blue * alpha,
            green: color.green * alpha,
            red: color.red * alpha,
            alpha: color.alpha * alpha
        )
    }

    private static func quillAdd(
        _ lhs: QuillPremultipliedBGRA,
        _ rhs: QuillPremultipliedBGRA
    ) -> QuillPremultipliedBGRA {
        QuillPremultipliedBGRA(
            blue: lhs.blue + rhs.blue,
            green: lhs.green + rhs.green,
            red: lhs.red + rhs.red,
            alpha: lhs.alpha + rhs.alpha
        )
    }

    private static func quillUnpremultiplied(_ color: QuillPremultipliedBGRA) -> QuillPremultipliedBGRA {
        let alpha = quillClampedUnit(color.alpha)
        guard alpha > 0 else {
            return QuillPremultipliedBGRA(blue: 0, green: 0, red: 0, alpha: 0)
        }
        return QuillPremultipliedBGRA(
            blue: quillClampedUnit(color.blue / alpha),
            green: quillClampedUnit(color.green / alpha),
            red: quillClampedUnit(color.red / alpha),
            alpha: alpha
        )
    }

    private static func quillPremultipliedColor(
        _ source: QuillPremultipliedBGRA,
        multipliedBy alpha: CGFloat
    ) -> QuillPremultipliedBGRA? {
        let alpha = quillClampedUnit(alpha)
        guard alpha > 0 else {
            return nil
        }
        guard alpha < 1 else {
            return source
        }
        return QuillPremultipliedBGRA(
            blue: source.blue * alpha,
            green: source.green * alpha,
            red: source.red * alpha,
            alpha: source.alpha * alpha
        )
    }

    private static func quillNormalizedRect(_ rect: CGRect) -> CGRect? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite
        else {
            return nil
        }

        let rectMaxX = rect.origin.x + rect.size.width
        let rectMaxY = rect.origin.y + rect.size.height
        guard rectMaxX.isFinite, rectMaxY.isFinite else {
            return nil
        }

        let minX = Swift.min(rect.origin.x, rectMaxX)
        let maxX = Swift.max(rect.origin.x, rectMaxX)
        let minY = Swift.min(rect.origin.y, rectMaxY)
        let maxY = Swift.max(rect.origin.y, rectMaxY)
        guard minX < maxX, minY < maxY else {
            return nil
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func quillInverse(_ transform: CGAffineTransform) -> CGAffineTransform? {
        let determinant = transform.a * transform.d - transform.b * transform.c
        guard determinant.isFinite, abs(determinant) > 0.000001 else {
            return nil
        }
        return transform.inverted()
    }

    private func quillPixelBounds(for rect: CGRect) -> QuillPixelBounds? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite
        else {
            return nil
        }

        let rectMaxX = rect.origin.x + rect.size.width
        let rectMaxY = rect.origin.y + rect.size.height
        guard rectMaxX.isFinite, rectMaxY.isFinite else {
            return nil
        }

        let rawMinX = Swift.min(rect.origin.x, rectMaxX)
        let rawMaxX = Swift.max(rect.origin.x, rectMaxX)
        let rawMinY = Swift.min(rect.origin.y, rectMaxY)
        let rawMaxY = Swift.max(rect.origin.y, rectMaxY)
        guard rawMinX < rawMaxX, rawMinY < rawMaxY else {
            return nil
        }

        let imageWidth = CGFloat(width)
        let imageHeight = CGFloat(height)
        let minX = Int(Swift.max(0, Swift.min(imageWidth, rawMinX.rounded(.down))))
        let minY = Int(Swift.max(0, Swift.min(imageHeight, rawMinY.rounded(.down))))
        let maxX = Int(Swift.max(0, Swift.min(imageWidth, rawMaxX.rounded(.up))))
        let maxY = Int(Swift.max(0, Swift.min(imageHeight, rawMaxY.rounded(.up))))
        guard minX < maxX, minY < maxY else {
            return nil
        }
        return (minX, minY, maxX, maxY)
    }

    private func quillDrawBitmapShadow(
        sourceBounds: QuillPixelBounds,
        alphaAtDevicePoint: (CGPoint) -> CGFloat
    ) {
        guard let shadow = quillShadow,
              quillCanDrawCurrentBitmap,
              shadow.offset.width.isFinite,
              shadow.offset.height.isFinite,
              let shadowColor = Self.quillPremultipliedColor(from: shadow.colorRGBA, alphaScale: 1),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        let blurRadius = quillShadowBlurRadius(shadow.blur)
        var alphaMask = [CGFloat](repeating: 0, count: width * height)
        for y in sourceBounds.minY..<sourceBounds.maxY {
            for x in sourceBounds.minX..<sourceBounds.maxX {
                let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let alpha = Self.quillClampedUnit(alphaAtDevicePoint(devicePoint) * quillBitmapClipAlpha(devicePoint))
                if alpha > 0 {
                    alphaMask[y * width + x] = alpha
                }
            }
        }

        if blurRadius > 0 {
            alphaMask = Self.quillBoxBlurredAlphaMask(alphaMask, width: width, height: height, radius: blurRadius)
        }

        guard let shadowBounds = quillShadowDestinationBounds(
            sourceBounds: sourceBounds,
            offset: shadow.offset,
            blurRadius: blurRadius
        ) else {
            return
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }

            for y in shadowBounds.minY..<shadowBounds.maxY {
                var offset = y * bytesPerRow + shadowBounds.minX * 4
                for x in shadowBounds.minX..<shadowBounds.maxX {
                    let sourceX = Int((CGFloat(x) + 0.5 - shadow.offset.width).rounded(.down))
                    let sourceY = Int((CGFloat(y) + 0.5 - shadow.offset.height).rounded(.down))
                    if sourceX >= 0, sourceX < width, sourceY >= 0, sourceY < height {
                        let maskAlpha = alphaMask[sourceY * width + sourceX]
                        if maskAlpha > 0 {
                            let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                            let clipAlpha = quillBitmapClipAlpha(devicePoint)
                            if let source = Self.quillPremultipliedColor(
                                shadowColor,
                                multipliedBy: maskAlpha * clipAlpha
                            ) {
                                quillCompositePremultipliedBGRA(source, into: pixels, at: offset)
                            }
                        }
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillShadowBlurRadius(_ blur: CGFloat) -> Int {
        guard blur.isFinite, blur > 0 else {
            return 0
        }
        return Int(Swift.min(CGFloat(Swift.max(width, height)), blur.rounded(.up)))
    }

    private func quillShadowDestinationBounds(
        sourceBounds: QuillPixelBounds,
        offset: CGSize,
        blurRadius: Int
    ) -> QuillPixelBounds? {
        let expansion = CGFloat(blurRadius)
        let minX = Int(Swift.max(0, Swift.min(
            CGFloat(width),
            (CGFloat(sourceBounds.minX) + offset.width - expansion).rounded(.down)
        )))
        let minY = Int(Swift.max(0, Swift.min(
            CGFloat(height),
            (CGFloat(sourceBounds.minY) + offset.height - expansion).rounded(.down)
        )))
        let maxX = Int(Swift.max(0, Swift.min(
            CGFloat(width),
            (CGFloat(sourceBounds.maxX) + offset.width + expansion).rounded(.up)
        )))
        let maxY = Int(Swift.max(0, Swift.min(
            CGFloat(height),
            (CGFloat(sourceBounds.maxY) + offset.height + expansion).rounded(.up)
        )))
        guard minX < maxX, minY < maxY else {
            return nil
        }
        return (minX, minY, maxX, maxY)
    }

    private static func quillBoxBlurredAlphaMask(
        _ mask: [CGFloat],
        width: Int,
        height: Int,
        radius: Int
    ) -> [CGFloat] {
        guard radius > 0, width > 0, height > 0, mask.count >= width * height else {
            return mask
        }

        var horizontal = [CGFloat](repeating: 0, count: width * height)
        for y in 0..<height {
            var left = 0
            var right = -1
            var sum: CGFloat = 0
            var count = 0
            for x in 0..<width {
                let targetRight = Swift.min(width - 1, x + radius)
                while right < targetRight {
                    right += 1
                    sum += mask[y * width + right]
                    count += 1
                }

                let targetLeft = Swift.max(0, x - radius)
                while left < targetLeft {
                    sum -= mask[y * width + left]
                    count -= 1
                    left += 1
                }

                horizontal[y * width + x] = count > 0 ? sum / CGFloat(count) : 0
            }
        }

        var blurred = [CGFloat](repeating: 0, count: width * height)
        for x in 0..<width {
            var top = 0
            var bottom = -1
            var sum: CGFloat = 0
            var count = 0
            for y in 0..<height {
                let targetBottom = Swift.min(height - 1, y + radius)
                while bottom < targetBottom {
                    bottom += 1
                    sum += horizontal[bottom * width + x]
                    count += 1
                }

                let targetTop = Swift.max(0, y - radius)
                while top < targetTop {
                    sum -= horizontal[top * width + x]
                    count -= 1
                    top += 1
                }

                blurred[y * width + x] = count > 0 ? Self.quillClampedUnit(sum / CGFloat(count)) : 0
            }
        }

        return blurred
    }

    private func quillCompositeTransparencyLayer(
        _ layerPixels: [UInt8],
        using layer: QuillTransparencyLayer
    ) {
        guard quillCanDrawCurrentBitmap,
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              layer.parentBytes.count >= requiredByteCount,
              layerPixels.count >= requiredByteCount
        else {
            quillBitmapBytes = layer.parentBytes
            return
        }

        quillBitmapBytes = layer.parentBytes
        quillAlpha = layer.alpha
        quillBlendMode = layer.blendMode
        quillShadow = layer.shadow
        quillClipRegions = layer.clipRegions

        let sourceBounds: QuillPixelBounds = (0, 0, width, height)
        quillDrawBitmapShadow(sourceBounds: sourceBounds) { devicePoint in
            let x = Int(devicePoint.x.rounded(.down))
            let y = Int(devicePoint.y.rounded(.down))
            guard x >= 0, x < width, y >= 0, y < height else {
                return 0
            }
            let offset = y * bytesPerRow + x * 4
            guard offset + 3 < layerPixels.count else {
                return 0
            }
            return (CGFloat(layerPixels[offset + 3]) / 255) * layer.alpha
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { destination in
            guard destination.count >= requiredByteCount else {
                return
            }

            for y in 0..<height {
                var offset = y * bytesPerRow
                for x in 0..<width {
                    let sourceAlpha = CGFloat(layerPixels[offset + 3]) / 255
                    if sourceAlpha > 0 {
                        let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                        let layerSource = QuillPremultipliedBGRA(
                            blue: CGFloat(layerPixels[offset]) / 255,
                            green: CGFloat(layerPixels[offset + 1]) / 255,
                            red: CGFloat(layerPixels[offset + 2]) / 255,
                            alpha: sourceAlpha
                        )
                        if let source = Self.quillPremultipliedColor(
                            layerSource,
                            multipliedBy: layer.alpha * quillBitmapClipAlpha(devicePoint)
                        ) {
                            quillCompositePremultipliedBGRA(source, into: destination, at: offset)
                        }
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillFillBitmap(_ rect: CGRect) {
        guard let source = quillPremultipliedFillColor() else {
            return
        }
        quillFillBitmap(rect, source: source)
    }

    private func quillFillBitmap(_ rect: CGRect, source: QuillPremultipliedBGRA) {
        guard quillCanDrawCurrentBitmap,
              let bounds = quillPixelBounds(for: rect.applying(quillCTM)),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        quillDrawBitmapShadow(sourceBounds: bounds) { _ in
            source.alpha
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }
            for y in bounds.minY..<bounds.maxY {
                var offset = y * bytesPerRow + bounds.minX * 4
                for x in bounds.minX..<bounds.maxX {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if let clippedSource = Self.quillPremultipliedColor(
                        source,
                        multipliedBy: quillBitmapClipAlpha(devicePoint)
                    ) {
                        quillCompositePremultipliedBGRA(clippedSource, into: pixels, at: offset)
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillFillBitmapPath(_ path: CGPath, using rule: CGPathFillRule) {
        guard let source = quillPremultipliedFillColor() else {
            return
        }
        quillFillBitmapPath(path, using: rule, source: source)
    }

    private func quillFillBitmapPath(_ path: CGPath, using rule: CGPathFillRule, source: QuillPremultipliedBGRA) {
        let userBounds = path.boundingBoxOfPath
        guard quillCanDrawCurrentBitmap,
              !path.isEmpty,
              !userBounds.isNull,
              let bounds = quillPixelBounds(for: userBounds.applying(quillCTM)),
              let inverseCTM = Self.quillInverse(quillCTM),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        quillDrawBitmapShadow(sourceBounds: bounds) { devicePoint in
            path.contains(devicePoint.applying(inverseCTM), using: rule, transform: .identity) ? source.alpha : 0
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }
            for y in bounds.minY..<bounds.maxY {
                var offset = y * bytesPerRow + bounds.minX * 4
                for x in bounds.minX..<bounds.maxX {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if path.contains(devicePoint.applying(inverseCTM), using: rule, transform: .identity),
                       let clippedSource = Self.quillPremultipliedColor(
                        source,
                        multipliedBy: quillBitmapClipAlpha(devicePoint)
                       ) {
                        quillCompositePremultipliedBGRA(clippedSource, into: pixels, at: offset)
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillStrokeBitmapShape(_ rect: CGRect, addShape: (CGMutablePath, CGRect) -> Void) {
        guard let userRect = Self.quillNormalizedRect(rect),
              quillLineWidth.isFinite,
              quillLineWidth > 0,
              let source = quillPremultipliedStrokeColor()
        else {
            return
        }

        let halfWidth = quillLineWidth / 2
        let path = CGMutablePath()
        addShape(path, CGRect(
            x: userRect.minX - halfWidth,
            y: userRect.minY - halfWidth,
            width: userRect.width + quillLineWidth,
            height: userRect.height + quillLineWidth
        ))

        let innerWidth = userRect.width - quillLineWidth
        let innerHeight = userRect.height - quillLineWidth
        if innerWidth > 0, innerHeight > 0 {
            addShape(path, CGRect(
                x: userRect.minX + halfWidth,
                y: userRect.minY + halfWidth,
                width: innerWidth,
                height: innerHeight
            ))
        }

        quillFillBitmapPath(path, using: .evenOdd, source: source)
    }

    private func quillStrokeBitmapRect(_ rect: CGRect) {
        quillStrokeBitmapShape(rect) { path, shapeRect in
            path.addRect(shapeRect)
        }
    }

    private func quillStrokeBitmapEllipse(_ rect: CGRect) {
        quillStrokeBitmapShape(rect) { path, shapeRect in
            path.addEllipse(in: shapeRect)
        }
    }

    private func quillStrokeBitmapPath(_ path: CGPath) {
        let segments = path
            .flattenedSubpaths(transform: quillCTM)
            .flatMap(Self.quillStrokeSegments(in:))
        quillStrokeBitmapSegments(segments)
    }

    private func quillStrokeBitmapLineSegments(between points: [CGPoint]) {
        quillStrokeBitmapSegments(Self.quillStrokeSegments(betweenPairsIn: points, transform: quillCTM))
    }

    private static func quillStrokeSegments(in subpath: [CGPoint]) -> [QuillStrokeSegment] {
        guard subpath.count >= 2 else {
            return []
        }

        var segments: [QuillStrokeSegment] = []
        var dashStart: CGFloat = 0
        for index in 0..<(subpath.count - 1) {
            let segment = QuillStrokeSegment(
                start: subpath[index],
                end: subpath[index + 1],
                dashStart: dashStart,
                joinsNext: index < subpath.count - 2
            )
            segments.append(segment)
            dashStart += segment.length
        }
        return segments
    }

    private static func quillStrokeSegments(
        betweenPairsIn points: [CGPoint],
        transform: CGAffineTransform
    ) -> [QuillStrokeSegment] {
        guard points.count >= 2 else {
            return []
        }

        var segments: [QuillStrokeSegment] = []
        for index in stride(from: 0, to: points.count - 1, by: 2) {
            segments.append(QuillStrokeSegment(
                start: points[index].applying(transform),
                end: points[index + 1].applying(transform),
                dashStart: 0,
                joinsNext: false
            ))
        }
        return segments
    }

    private func quillStrokeBitmapSegments(_ segments: [QuillStrokeSegment]) {
        guard quillCanDrawCurrentBitmap,
              let source = quillPremultipliedStrokeColor(),
              let lineWidth = quillDeviceLineWidth(),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        let drawableSegments = segments.filter(Self.quillStrokeSegmentIsFinite)
        let halfWidth = lineWidth / 2
        let lineCap = quillLineCap
        let lineJoin = quillLineJoin
        let miterLimit = quillMiterLimit
        let lineDash = quillDeviceLineDash()
        let boundsExpansion = Self.quillStrokeBoundsExpansion(
            segments: drawableSegments,
            halfWidth: halfWidth,
            lineJoin: lineJoin,
            miterLimit: miterLimit,
            lineDash: lineDash
        )
        guard let strokeBounds = Self.quillBounds(for: drawableSegments, expandedBy: boundsExpansion),
              let bounds = quillPixelBounds(for: strokeBounds)
        else {
            return
        }

        quillDrawBitmapShadow(sourceBounds: bounds) { devicePoint in
            Self.quillStrokeContains(
                devicePoint,
                segments: drawableSegments,
                halfWidth: halfWidth,
                lineCap: lineCap,
                lineJoin: lineJoin,
                miterLimit: miterLimit,
                lineDash: lineDash
            ) ? source.alpha : 0
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }
            for y in bounds.minY..<bounds.maxY {
                var offset = y * bytesPerRow + bounds.minX * 4
                for x in bounds.minX..<bounds.maxX {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    if Self.quillStrokeContains(
                           devicePoint,
                           segments: drawableSegments,
                           halfWidth: halfWidth,
                           lineCap: lineCap,
                           lineJoin: lineJoin,
                           miterLimit: miterLimit,
                           lineDash: lineDash
                       ),
                       let clippedSource = Self.quillPremultipliedColor(
                        source,
                        multipliedBy: quillBitmapClipAlpha(devicePoint)
                       ) {
                        quillCompositePremultipliedBGRA(clippedSource, into: pixels, at: offset)
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillDeviceLineWidth() -> CGFloat? {
        guard quillLineWidth.isFinite, quillLineWidth > 0 else {
            return nil
        }

        guard let scale = quillDeviceStrokeScale() else {
            return nil
        }
        return quillLineWidth * scale
    }

    private func quillDeviceLineDash() -> QuillLineDash? {
        guard !quillLineDashLengths.isEmpty,
              let scale = quillDeviceStrokeScale() else {
            return nil
        }
        let lengths = quillLineDashLengths.map { $0 * scale }
        let cycleLength = lengths.reduce(0, +)
        guard cycleLength > 0 else {
            return nil
        }
        return QuillLineDash(phase: quillLineDashPhase * scale, lengths: lengths, cycleLength: cycleLength)
    }

    private func quillDeviceStrokeScale() -> CGFloat? {
        let xScale = hypot(quillCTM.a, quillCTM.b)
        let yScale = hypot(quillCTM.c, quillCTM.d)
        let scale = Swift.max(xScale, yScale)
        guard scale.isFinite, scale > 0 else {
            return nil
        }
        return scale
    }

    private static func quillStrokeSegmentIsFinite(_ segment: QuillStrokeSegment) -> Bool {
        segment.start.x.isFinite && segment.start.y.isFinite &&
            segment.end.x.isFinite && segment.end.y.isFinite
    }

    private static func quillStrokeBoundsExpansion(
        segments: [QuillStrokeSegment],
        halfWidth: CGFloat,
        lineJoin: CGLineJoin,
        miterLimit: CGFloat,
        lineDash: QuillLineDash?
    ) -> CGFloat {
        guard lineDash == nil,
              lineJoin == .miter,
              quillHasAngledJoin(segments)
        else {
            return halfWidth
        }

        return halfWidth * Swift.max(1, miterLimit * 2)
    }

    private static func quillHasAngledJoin(_ segments: [QuillStrokeSegment]) -> Bool {
        for index in segments.indices.dropLast() where segments[index].joinsNext {
            let current = segments[index]
            let next = segments[index + 1]
            guard CGPath.pointsAreClose(current.end, next.start),
                  let incoming = CGPath.normalizedVector(from: current.start, to: current.end),
                  let outgoing = CGPath.normalizedVector(from: next.start, to: next.end)
            else {
                continue
            }

            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            if abs(cross) > 0.0001 {
                return true
            }
        }
        return false
    }

    private static func quillBounds(
        for segments: [QuillStrokeSegment],
        expandedBy expansion: CGFloat
    ) -> CGRect? {
        guard expansion.isFinite else {
            return nil
        }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for segment in segments {
            minX = Swift.min(minX, Swift.min(segment.start.x, segment.end.x))
            minY = Swift.min(minY, Swift.min(segment.start.y, segment.end.y))
            maxX = Swift.max(maxX, Swift.max(segment.start.x, segment.end.x))
            maxY = Swift.max(maxY, Swift.max(segment.start.y, segment.end.y))
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }

        return CGRect(
            x: minX - expansion,
            y: minY - expansion,
            width: maxX - minX + expansion * 2,
            height: maxY - minY + expansion * 2
        )
    }

    private static func quillStrokeContains(
        _ point: CGPoint,
        segments: [QuillStrokeSegment],
        halfWidth: CGFloat,
        lineCap: CGLineCap,
        lineJoin: CGLineJoin,
        miterLimit: CGFloat,
        lineDash: QuillLineDash?
    ) -> Bool {
        for segment in segments where quillStrokeContains(
            point,
            segment: segment,
            halfWidth: halfWidth,
            lineCap: lineCap,
            lineDash: lineDash
        ) {
            return true
        }

        guard lineDash == nil else {
            return false
        }

        switch lineJoin {
        case .round:
            return quillRoundJoinContains(point, segments: segments, halfWidth: halfWidth)
        case .bevel:
            return quillAngledJoinContains(point, segments: segments, halfWidth: halfWidth, miterLimit: 0)
        case .miter:
            return quillAngledJoinContains(point, segments: segments, halfWidth: halfWidth, miterLimit: miterLimit)
        }
    }

    private static func quillStrokeContains(
        _ point: CGPoint,
        segment: QuillStrokeSegment,
        halfWidth: CGFloat,
        lineCap: CGLineCap,
        lineDash: QuillLineDash?
    ) -> Bool {
        let dx = segment.end.x - segment.start.x
        let dy = segment.end.y - segment.start.y
        let lengthSquared = dx * dx + dy * dy
        let halfWidthSquared = halfWidth * halfWidth
        guard lengthSquared > 0.000001 else {
            return lineCap == .round && quillDistanceSquared(point, segment.start) <= halfWidthSquared
        }

        let projection = ((point.x - segment.start.x) * dx + (point.y - segment.start.y) * dy) / lengthSquared
        switch lineCap {
        case .butt:
            guard projection >= 0, projection <= 1 else {
                return false
            }
        case .square:
            let capExtension = halfWidth / sqrt(lengthSquared)
            guard projection >= -capExtension, projection <= 1 + capExtension else {
                return false
            }
        case .round:
            if projection < 0 {
                return quillDashAllowsEndpoint(segment.dashStart, lineDash: lineDash) &&
                    quillDistanceSquared(point, segment.start) <= halfWidthSquared
            }
            if projection > 1 {
                return quillDashAllowsEndpoint(segment.dashStart + segment.length, lineDash: lineDash) &&
                    quillDistanceSquared(point, segment.end) <= halfWidthSquared
            }
        }

        if let lineDash {
            let length = sqrt(lengthSquared)
            let clampedProjection = Swift.max(0, Swift.min(1, projection))
            let distanceAlongStroke = segment.dashStart + clampedProjection * length
            guard quillDashIsVisible(at: distanceAlongStroke, lineDash: lineDash) else {
                return false
            }
        }

        let closest = CGPoint(
            x: segment.start.x + projection * dx,
            y: segment.start.y + projection * dy
        )
        return quillDistanceSquared(point, closest) <= halfWidthSquared
    }

    private static func quillRoundJoinContains(
        _ point: CGPoint,
        segments: [QuillStrokeSegment],
        halfWidth: CGFloat
    ) -> Bool {
        let halfWidthSquared = halfWidth * halfWidth
        for index in segments.indices.dropLast() where segments[index].joinsNext {
            let current = segments[index]
            let next = segments[index + 1]
            if CGPath.pointsAreClose(current.end, next.start),
               quillDistanceSquared(point, current.end) <= halfWidthSquared {
                return true
            }
        }
        return false
    }

    private static func quillAngledJoinContains(
        _ point: CGPoint,
        segments: [QuillStrokeSegment],
        halfWidth: CGFloat,
        miterLimit: CGFloat
    ) -> Bool {
        for index in segments.indices.dropLast() where segments[index].joinsNext {
            let current = segments[index]
            let next = segments[index + 1]
            guard CGPath.pointsAreClose(current.end, next.start),
                  let incoming = CGPath.normalizedVector(from: current.start, to: current.end),
                  let outgoing = CGPath.normalizedVector(from: next.start, to: next.end)
            else {
                continue
            }

            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            guard abs(cross) > 0.0001 else {
                continue
            }

            let joint = current.end
            let outerSide: CGFloat = cross < 0 ? 1 : -1
            let currentNormal = CGPoint(x: -incoming.y * outerSide, y: incoming.x * outerSide)
            let nextNormal = CGPoint(x: -outgoing.y * outerSide, y: outgoing.x * outerSide)
            let currentOuter = CGPoint(
                x: joint.x + currentNormal.x * halfWidth,
                y: joint.y + currentNormal.y * halfWidth
            )
            let nextOuter = CGPoint(
                x: joint.x + nextNormal.x * halfWidth,
                y: joint.y + nextNormal.y * halfWidth
            )

            if miterLimit <= 0 {
                if quillPointIsInTriangle(point, joint, currentOuter, nextOuter) {
                    return true
                }
                continue
            }

            guard let miter = quillLineIntersection(
                point: currentOuter,
                direction: CGPoint(x: incoming.x, y: incoming.y),
                otherPoint: nextOuter,
                otherDirection: CGPoint(x: outgoing.x, y: outgoing.y)
            ) else {
                if quillPointIsInTriangle(point, joint, currentOuter, nextOuter) {
                    return true
                }
                continue
            }

            let allowedMiterDistance = miterLimit * halfWidth * 2
            if quillDistanceSquared(joint, miter) <= allowedMiterDistance * allowedMiterDistance {
                if quillPointIsInTriangle(point, currentOuter, miter, nextOuter) {
                    return true
                }
            } else if quillPointIsInTriangle(point, joint, currentOuter, nextOuter) {
                return true
            }
        }
        return false
    }

    private static func quillLineIntersection(
        point: CGPoint,
        direction: CGPoint,
        otherPoint: CGPoint,
        otherDirection: CGPoint
    ) -> CGPoint? {
        let denominator = direction.x * otherDirection.y - direction.y * otherDirection.x
        guard abs(denominator) > 0.0001 else {
            return nil
        }

        let dx = otherPoint.x - point.x
        let dy = otherPoint.y - point.y
        let scale = (dx * otherDirection.y - dy * otherDirection.x) / denominator
        return CGPoint(x: point.x + direction.x * scale, y: point.y + direction.y * scale)
    }

    private static func quillPointIsInTriangle(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let ab = quillSignedArea(point, a, b)
        let bc = quillSignedArea(point, b, c)
        let ca = quillSignedArea(point, c, a)
        let tolerance: CGFloat = 0.0001
        let hasNegative = ab < -tolerance || bc < -tolerance || ca < -tolerance
        let hasPositive = ab > tolerance || bc > tolerance || ca > tolerance
        return !(hasNegative && hasPositive)
    }

    private static func quillSignedArea(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (point.x - b.x) * (a.y - b.y) - (a.x - b.x) * (point.y - b.y)
    }

    private static func quillDashAllowsEndpoint(_ distance: CGFloat, lineDash: QuillLineDash?) -> Bool {
        guard let lineDash else {
            return true
        }
        return quillDashIsVisible(at: distance, lineDash: lineDash)
    }

    private static func quillDashIsVisible(at distance: CGFloat, lineDash: QuillLineDash) -> Bool {
        var position = (distance + lineDash.phase).truncatingRemainder(dividingBy: lineDash.cycleLength)
        if position < 0 {
            position += lineDash.cycleLength
        }

        var isVisible = true
        for length in lineDash.lengths {
            if position < length {
                return isVisible
            }
            position -= length
            isVisible.toggle()
        }
        return isVisible
    }

    private static func quillDistanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func quillClearBitmap(_ rect: CGRect) {
        guard quillCanDrawCurrentBitmap,
              let bounds = quillPixelBounds(for: rect.applying(quillCTM)),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }
            for y in bounds.minY..<bounds.maxY {
                var offset = y * bytesPerRow + bounds.minX * 4
                for x in bounds.minX..<bounds.maxX {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    let clipAlpha = quillBitmapClipAlpha(devicePoint)
                    if clipAlpha >= 0.999 {
                        pixels[offset] = 0
                        pixels[offset + 1] = 0
                        pixels[offset + 2] = 0
                        pixels[offset + 3] = 0
                    } else if clipAlpha > 0 {
                        let remainingAlpha = 1 - clipAlpha
                        pixels[offset] = Self.quillClampedByte(CGFloat(pixels[offset]) / 255 * remainingAlpha)
                        pixels[offset + 1] = Self.quillClampedByte(CGFloat(pixels[offset + 1]) / 255 * remainingAlpha)
                        pixels[offset + 2] = Self.quillClampedByte(CGFloat(pixels[offset + 2]) / 255 * remainingAlpha)
                        pixels[offset + 3] = Self.quillClampedByte(CGFloat(pixels[offset + 3]) / 255 * remainingAlpha)
                    }
                    offset += 4
                }
            }
        }
    }

    private func quillDrawBitmapImage(_ image: Any, in rect: CGRect) {
        guard quillCanDrawCurrentBitmap,
              let source = Self.quillBitmapSource(from: image),
              let userRect = Self.quillNormalizedRect(rect),
              let inverseCTM = Self.quillInverse(quillCTM),
              let bounds = quillPixelBounds(for: userRect.applying(quillCTM)),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        let userMaxX = userRect.origin.x + userRect.size.width
        let userMaxY = userRect.origin.y + userRect.size.height
        let globalAlpha = quillAlpha

        quillDrawBitmapShadow(sourceBounds: bounds) { devicePoint in
            let userPoint = devicePoint.applying(inverseCTM)
            guard userPoint.x >= userRect.origin.x,
                  userPoint.x < userMaxX,
                  userPoint.y >= userRect.origin.y,
                  userPoint.y < userMaxY
            else {
                return 0
            }

            let unitX = (userPoint.x - userRect.origin.x) / userRect.size.width
            let unitY = (userPoint.y - userRect.origin.y) / userRect.size.height
            let sourceX = Swift.max(0, Swift.min(source.width - 1, Int((unitX * CGFloat(source.width)).rounded(.down))))
            let sourceY = Swift.max(0, Swift.min(source.height - 1, Int((unitY * CGFloat(source.height)).rounded(.down))))
            let sourceOffset = sourceY * source.bytesPerRow + sourceX * 4
            guard sourceOffset + 3 < source.pixels.count else {
                return 0
            }
            return (CGFloat(source.pixels[sourceOffset + 3]) / 255) * globalAlpha
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { destination in
            guard destination.count >= requiredByteCount else {
                return
            }

            for y in bounds.minY..<bounds.maxY {
                var destinationOffset = y * bytesPerRow + bounds.minX * 4
                for x in bounds.minX..<bounds.maxX {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    let clipAlpha = quillBitmapClipAlpha(devicePoint)
                    guard clipAlpha > 0 else {
                        destinationOffset += 4
                        continue
                    }
                    let userPoint = devicePoint.applying(inverseCTM)
                    guard userPoint.x >= userRect.origin.x,
                          userPoint.x < userMaxX,
                          userPoint.y >= userRect.origin.y,
                          userPoint.y < userMaxY
                    else {
                        destinationOffset += 4
                        continue
                    }

                    let unitX = (userPoint.x - userRect.origin.x) / userRect.size.width
                    let unitY = (userPoint.y - userRect.origin.y) / userRect.size.height
                    let sourceX = Swift.max(0, Swift.min(source.width - 1, Int((unitX * CGFloat(source.width)).rounded(.down))))
                    let sourceY = Swift.max(0, Swift.min(source.height - 1, Int((unitY * CGFloat(source.height)).rounded(.down))))
                    let sourceOffset = sourceY * source.bytesPerRow + sourceX * 4
                    guard sourceOffset + 3 < source.pixels.count else {
                        destinationOffset += 4
                        continue
                    }

                    let sourceColor = QuillPremultipliedBGRA(
                        blue: (CGFloat(source.pixels[sourceOffset]) / 255) * globalAlpha,
                        green: (CGFloat(source.pixels[sourceOffset + 1]) / 255) * globalAlpha,
                        red: (CGFloat(source.pixels[sourceOffset + 2]) / 255) * globalAlpha,
                        alpha: (CGFloat(source.pixels[sourceOffset + 3]) / 255) * globalAlpha
                    )
                    if let clippedSource = Self.quillPremultipliedColor(sourceColor, multipliedBy: clipAlpha) {
                        quillCompositePremultipliedBGRA(clippedSource, into: destination, at: destinationOffset)
                    }
                    destinationOffset += 4
                }
            }
        }
    }

    private func quillDrawBitmapGradient(
        _ gradient: CGGradient,
        options: CGGradientDrawingOptions,
        locationForUserPoint: (CGPoint) -> CGFloat?
    ) {
        guard quillCanDrawCurrentBitmap,
              let inverseCTM = Self.quillInverse(quillCTM),
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              quillBitmapBytes != nil
        else {
            return
        }

        let sourceBounds: QuillPixelBounds = (0, 0, width, height)
        quillDrawBitmapShadow(sourceBounds: sourceBounds) { devicePoint in
            guard let rawLocation = locationForUserPoint(devicePoint.applying(inverseCTM)),
                  Self.quillGradientOptionsAllow(rawLocation, options: options)
            else {
                return 0
            }
            let rgba = gradient.quillRGBA(at: rawLocation)
            let alpha = rgba.indices.contains(3) ? rgba[3] : 1
            return Self.quillClampedUnit(alpha * quillAlpha)
        }

        quillBitmapBytes?.withUnsafeMutableBufferPointer { pixels in
            guard pixels.count >= requiredByteCount else {
                return
            }
            for y in 0..<height {
                var offset = y * bytesPerRow
                for x in 0..<width {
                    let devicePoint = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                    let clipAlpha = quillBitmapClipAlpha(devicePoint)
                    guard clipAlpha > 0,
                          let rawLocation = locationForUserPoint(devicePoint.applying(inverseCTM)),
                          Self.quillGradientOptionsAllow(rawLocation, options: options),
                          let source = quillPremultipliedColor(from: gradient.quillRGBA(at: rawLocation)),
                          let clippedSource = Self.quillPremultipliedColor(source, multipliedBy: clipAlpha)
                    else {
                        offset += 4
                        continue
                    }

                    quillCompositePremultipliedBGRA(clippedSource, into: pixels, at: offset)
                    offset += 4
                }
            }
        }
    }

    private func quillDrawBitmapLinearGradient(
        _ gradient: CGGradient,
        start: CGPoint,
        end: CGPoint,
        options: CGGradientDrawingOptions
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.000001 else {
            return
        }

        quillDrawBitmapGradient(gradient, options: options) { point in
            ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        }
    }

    private func quillDrawBitmapRadialGradient(
        _ gradient: CGGradient,
        startCenter: CGPoint,
        startRadius: CGFloat,
        endCenter: CGPoint,
        endRadius: CGFloat,
        options: CGGradientDrawingOptions
    ) {
        guard startRadius.isFinite, endRadius.isFinite, startRadius >= 0, endRadius >= 0 else {
            return
        }

        let centerDelta = CGPoint(x: endCenter.x - startCenter.x, y: endCenter.y - startCenter.y)
        let radiusDelta = endRadius - startRadius
        guard abs(centerDelta.x) > 0.000001 || abs(centerDelta.y) > 0.000001 || abs(radiusDelta) > 0.000001 else {
            return
        }

        quillDrawBitmapGradient(gradient, options: options) { point in
            Self.quillRadialGradientLocation(
                for: point,
                startCenter: startCenter,
                startRadius: startRadius,
                centerDelta: centerDelta,
                radiusDelta: radiusDelta
            )
        }
    }

    private static func quillGradientOptionsAllow(
        _ location: CGFloat,
        options: CGGradientDrawingOptions
    ) -> Bool {
        if location < 0, !options.contains(.drawsBeforeStartLocation) {
            return false
        }
        if location > 1, !options.contains(.drawsAfterEndLocation) {
            return false
        }
        return true
    }

    private static func quillRadialGradientLocation(
        for point: CGPoint,
        startCenter: CGPoint,
        startRadius: CGFloat,
        centerDelta: CGPoint,
        radiusDelta: CGFloat
    ) -> CGFloat? {
        let px = point.x - startCenter.x
        let py = point.y - startCenter.y
        let a = centerDelta.x * centerDelta.x + centerDelta.y * centerDelta.y - radiusDelta * radiusDelta
        let b = -2 * (px * centerDelta.x + py * centerDelta.y + startRadius * radiusDelta)
        let c = px * px + py * py - startRadius * startRadius

        if abs(a) <= 0.000001 {
            guard abs(b) > 0.000001 else {
                return nil
            }
            return -c / b
        }

        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else {
            return nil
        }

        let root = discriminant.squareRoot()
        let first = (-b - root) / (2 * a)
        let second = (-b + root) / (2 * a)
        return quillPreferredGradientRoot(first, second)
    }

    private static func quillPreferredGradientRoot(_ first: CGFloat, _ second: CGFloat) -> CGFloat? {
        let candidates = [first, second].filter(\.isFinite)
        if let inRange = candidates.filter({ $0 >= 0 && $0 <= 1 }).min(by: { abs($0 - 0.5) < abs($1 - 0.5) }) {
            return inRange
        }
        return candidates.min(by: { abs($0 - 0.5) < abs($1 - 0.5) })
    }

    private func quillBitmapClipAlpha(_ devicePoint: CGPoint) -> CGFloat {
        guard !quillClipRegions.isEmpty else {
            return 1
        }

        var alpha: CGFloat = 1
        for region in quillClipRegions {
            alpha *= Self.quillClipAlpha(for: region, at: devicePoint)
            if alpha <= 0 {
                return 0
            }
        }
        return Self.quillClampedUnit(alpha)
    }

    private static func quillClipAlpha(for region: QuillClipRegion, at devicePoint: CGPoint) -> CGFloat {
        switch region {
        case let .path(path, rule, transform):
            return path.contains(devicePoint, using: rule, transform: transform) ? 1 : 0
        case let .mask(rect, source, transform):
            guard let inverse = quillInverse(transform) else {
                return 0
            }
            let userPoint = devicePoint.applying(inverse)
            guard userPoint.x >= rect.minX, userPoint.x < rect.maxX,
                  userPoint.y >= rect.minY, userPoint.y < rect.maxY
            else {
                return 0
            }

            let unitX = (userPoint.x - rect.minX) / rect.width
            let unitY = (userPoint.y - rect.minY) / rect.height
            let sourceX = Swift.max(0, Swift.min(source.width - 1, Int((unitX * CGFloat(source.width)).rounded(.down))))
            let sourceY = Swift.max(0, Swift.min(source.height - 1, Int((unitY * CGFloat(source.height)).rounded(.down))))
            let sourceOffset = sourceY * source.bytesPerRow + sourceX * 4
            guard sourceOffset + 3 < source.pixels.count else {
                return 0
            }
            return CGFloat(source.pixels[sourceOffset + 3]) / 255
        }
    }

    private func quillAddClip(_ path: CGPath, using rule: CGPathFillRule) {
        guard !path.isEmpty else {
            return
        }

        quillClipRegions.append(.path(path: path, rule: rule, transform: quillCTM))
    }

    private func quillAddMaskClip(rect: CGRect, source: QuillBitmapImageSource) {
        guard let rect = Self.quillNormalizedRect(rect) else {
            return
        }

        quillClipRegions.append(.mask(rect: rect, source: source, transform: quillCTM))
    }

    /// Bitmap-context initializer. The supplied pixels are retained so
    /// `makeImage()` can return a CGImage instead of trapping callers that
    /// force-unwrap it. Nil data creates a zero-filled 8-bit BGRA buffer when the
    /// dimensions describe a supported 32-bpp bitmap.
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
        self.bytesPerRow = Self.quillResolvedBytesPerRow(
            width: width,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow
        ) ?? bytesPerRow
        self.colorSpace = space
        self.bitmapInfo = CGBitmapInfo(rawValue: bitmapInfo)
        guard width > 0, height > 0, self.bytesPerRow > 0,
              let count = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: self.bytesPerRow)
        else { return }

        if let data {
            quillBitmapBytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: count))
        } else if Self.quillSupportsDirectBitmapDrawing(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: self.bitsPerPixel,
            bytesPerRow: self.bytesPerRow
        ) {
            quillBitmapBytes = Array(repeating: 0, count: count)
        }
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

    public func makeImage() -> CGImage? {
        let image = CGImage()
        image.width = width
        image.height = height
        image.quillBytesPerRow = bytesPerRow
        image.quillBGRAPixels = quillBitmapBytes
        return image
    }

    public var interpolationQuality: CGInterpolationQuality = .default

    public var isPathEmpty: Bool { quillCurrentPath.isEmpty }
    public var currentPointOfPath: CGPoint { quillCurrentPath.currentPoint }
    public var pathBoundingBox: CGRect { quillCurrentPath.boundingBoxOfPath }
    public func copyPath() -> CGPath? {
        quillCurrentPath.isEmpty ? nil : quillCurrentPath.copy()
    }

    public func setFillColor(_ color: Any?) {
        if let color = color as? RSCGColor {
            setFillColor(color)
        }
    }
    public func setFillColor(_ color: RSCGColor) {
        let rgba = quillNormalizedRGBA(color)
        quillFillRGBA = Self.quillNormalizedFillRGBA(rgba)
        quillBackend?.setFillColor(rgba)
    }
    public func setFillColor(_ color: RSCGColor?) {
        if let color {
            setFillColor(color)
        }
    }
    public func setFillColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let rgba = [red, green, blue, alpha]
        quillFillRGBA = Self.quillNormalizedFillRGBA(rgba)
        quillBackend?.setFillColor(rgba)
    }
    public func setStrokeColor(_ color: Any?) {
        if let color = color as? RSCGColor {
            setStrokeColor(color)
        }
    }
    public func setStrokeColor(_ color: RSCGColor) {
        let rgba = quillNormalizedRGBA(color)
        quillStrokeRGBA = Self.quillNormalizedFillRGBA(rgba)
        quillBackend?.setStrokeColor(rgba)
    }
    public func setStrokeColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let rgba = [red, green, blue, alpha]
        quillStrokeRGBA = Self.quillNormalizedFillRGBA(rgba)
        quillBackend?.setStrokeColor(rgba)
    }
    public func setLineWidth(_ width: CGFloat) {
        quillLineWidth = width.isFinite ? Swift.max(0, width) : 0
        quillBackend?.setLineWidth(width)
    }
    public func setLineCap(_ cap: CGLineCap) {
        quillLineCap = cap
        quillBackend?.setLineCap(cap)
    }
    public func setLineJoin(_ join: CGLineJoin) {
        quillLineJoin = join
        quillBackend?.setLineJoin(join)
    }
    public func setMiterLimit(_ limit: CGFloat) {
        let sanitizedLimit = limit.isFinite ? Swift.max(0, limit) : 0
        quillMiterLimit = sanitizedLimit
        quillBackend?.setMiterLimit(sanitizedLimit)
    }
    public func setLineDash(phase: CGFloat, lengths: [CGFloat]) {
        let sanitizedLengths = Self.quillNormalizedDashLengths(lengths)
        quillLineDashPhase = phase.isFinite ? phase : 0
        quillLineDashLengths = sanitizedLengths
        quillBackend?.setLineDash(phase: quillLineDashPhase, lengths: sanitizedLengths)
    }
    public func setShadow(offset: CGSize, blur: CGFloat) {
        let colorRGBA: [CGFloat] = [0, 0, 0, CGFloat(1) / 3]
        quillShadow = QuillShadow(
            offset: offset,
            blur: blur,
            colorRGBA: colorRGBA
        )
        quillBackend?.setShadow(offset: offset, blur: blur, colorRGBA: colorRGBA)
    }
    public func setShadow(offset: CGSize, blur: CGFloat, color: CGColor?) {
        guard let color else {
            quillShadow = nil
            quillBackend?.setShadow(offset: offset, blur: blur, colorRGBA: nil)
            return
        }
        let colorRGBA = Self.quillNormalizedFillRGBA(quillNormalizedRGBA(color))
        quillShadow = QuillShadow(
            offset: offset,
            blur: blur,
            colorRGBA: colorRGBA
        )
        quillBackend?.setShadow(offset: offset, blur: blur, colorRGBA: colorRGBA)
    }
    private var quillEffectiveAntialiasing: Bool {
        quillAllowsAntialiasing && quillShouldAntialias
    }
    public var quillEffectiveFontSmoothing: Bool {
        quillAllowsFontSmoothingState && quillShouldSmoothFontsState
    }
    public var quillEffectiveFontSubpixelPositioning: Bool {
        quillAllowsFontSubpixelPositioningState && quillShouldSubpixelPositionFontsState
    }
    public var quillEffectiveFontSubpixelQuantization: Bool {
        quillAllowsFontSubpixelQuantizationState && quillShouldSubpixelQuantizeFontsState
    }
    public func setAllowsAntialiasing(_ allowsAntialiasing: Bool) {
        quillAllowsAntialiasing = allowsAntialiasing
        quillBackend?.setShouldAntialias(quillEffectiveAntialiasing)
    }
    public func setShouldAntialias(_ shouldAntialias: Bool) {
        quillShouldAntialias = shouldAntialias
        quillBackend?.setShouldAntialias(quillEffectiveAntialiasing)
    }
    public func setAllowsFontSmoothing(_ allowsFontSmoothing: Bool) {
        quillAllowsFontSmoothingState = allowsFontSmoothing
    }
    public func setShouldSmoothFonts(_ shouldSmoothFonts: Bool) {
        quillShouldSmoothFontsState = shouldSmoothFonts
    }
    public func setAllowsFontSubpixelPositioning(_ allowsFontSubpixelPositioning: Bool) {
        quillAllowsFontSubpixelPositioningState = allowsFontSubpixelPositioning
    }
    public func setShouldSubpixelPositionFonts(_ shouldSubpixelPositionFonts: Bool) {
        quillShouldSubpixelPositionFontsState = shouldSubpixelPositionFonts
    }
    public func setAllowsFontSubpixelQuantization(_ allowsFontSubpixelQuantization: Bool) {
        quillAllowsFontSubpixelQuantizationState = allowsFontSubpixelQuantization
    }
    public func setShouldSubpixelQuantizeFonts(_ shouldSubpixelQuantizeFonts: Bool) {
        quillShouldSubpixelQuantizeFontsState = shouldSubpixelQuantizeFonts
    }
    public func setAlpha(_ alpha: CGFloat) {
        quillAlpha = Self.quillClampedUnit(alpha)
        quillBackend?.setAlpha(alpha)
    }
    public func setBlendMode(_ mode: CGBlendMode) {
        quillBlendMode = mode
        quillBackend?.setBlendMode(mode)
    }

    public func fill(_ rect: CGRect) {
        quillBackend?.fill(rect)
        quillFillBitmap(rect)
    }
    public func fill(_ rects: [CGRect]) { for r in rects { fill(r) } }
    public func fillEllipse(in rect: CGRect) {
        quillBackend?.fillEllipse(in: rect)
        quillFillBitmapPath(CGPath(ellipseIn: rect, transform: nil), using: .winding)
    }
    public func fillPath() {
        quillBackend?.fillPath()
        quillFillBitmapPath(quillCurrentPath, using: .winding)
        clearCurrentPath()
    }
    public func fillPath(using rule: CGPathFillRule) {
        quillBackend?.fillPath(using: rule)
        quillFillBitmapPath(quillCurrentPath, using: rule)
        clearCurrentPath()
    }
    public func clear(_ rect: CGRect) {
        quillBackend?.clear(rect)
        quillClearBitmap(rect)
    }
    public func stroke(_ rect: CGRect) {
        quillBackend?.stroke(rect)
        quillStrokeBitmapRect(rect)
    }
    public func strokeEllipse(in rect: CGRect) {
        quillBackend?.strokeEllipse(in: rect)
        quillStrokeBitmapEllipse(rect)
    }
    public func strokeLineSegments(between points: [CGPoint]) {
        quillBackend?.strokeLineSegments(between: points)
        quillStrokeBitmapLineSegments(between: points)
    }
    public func strokePath() {
        quillBackend?.strokePath()
        quillStrokeBitmapPath(quillCurrentPath)
        clearCurrentPath()
    }

    public func beginPath() {
        quillCurrentPath = CGMutablePath()
        quillBackend?.beginPath()
    }
    public func closePath() {
        quillCurrentPath.closeSubpath()
        quillBackend?.closePath()
    }
    public func move(to point: CGPoint) {
        quillCurrentPath.move(to: point)
        quillBackend?.move(to: point)
    }
    public func addLine(to point: CGPoint) {
        quillCurrentPath.addLine(to: point)
        quillBackend?.addLine(to: point)
    }
    public func addRect(_ rect: CGRect) {
        quillCurrentPath.addRect(rect)
        quillBackend?.addRect(rect)
    }
    public func addRects(_ rects: [CGRect]) {
        for rect in rects {
            addRect(rect)
        }
    }
    public func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }
    public func addEllipse(in rect: CGRect) {
        quillCurrentPath.addEllipse(in: rect)
        quillBackend?.addEllipse(in: rect)
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {
        quillCurrentPath.addCurve(to: end, control1: control1, control2: control2)
        quillBackend?.addCurve(to: end, control1: control1, control2: control2)
    }
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {
        quillCurrentPath.addQuadCurve(to: end, control: control)
        quillBackend?.addQuadCurve(to: end, control: control)
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat, clockwise: Bool) {
        quillCurrentPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
        quillBackend?.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
    }
    public func addArc(tangent1End: CGPoint, tangent2End: CGPoint, radius: CGFloat) {
        let previousCount = quillCurrentPath.elements.count
        quillCurrentPath.addArc(tangent1End: tangent1End, tangent2End: tangent2End, radius: radius)
        for element in quillCurrentPath.elements.dropFirst(previousCount) {
            appendPathElementToBackend(element)
        }
    }
    public func addPath(_ path: CGPath) {
        appendPath(path)
    }
    public func addPath(_ path: Any?) {
        guard let path = path as? CGPath else { return }
        appendPath(path)
    }
    private func appendPath(_ path: CGPath) {
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                move(to: element.points[0])
            case .addLineToPoint:
                addLine(to: element.points[0])
            case .addQuadCurveToPoint:
                addQuadCurve(to: element.points[1], control: element.points[0])
            case .addCurveToPoint:
                addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1])
            case .closeSubpath:
                closePath()
            }
        }
    }

    private func appendPathElementToBackend(_ element: CGPathStorageElement) {
        switch element.type {
        case .moveToPoint:
            guard let point = element.points.first else { return }
            quillBackend?.move(to: point)
        case .addLineToPoint:
            guard let point = element.points.first else { return }
            quillBackend?.addLine(to: point)
        case .addQuadCurveToPoint:
            guard element.points.count >= 2 else { return }
            quillBackend?.addQuadCurve(to: element.points[1], control: element.points[0])
        case .addCurveToPoint:
            guard element.points.count >= 3 else { return }
            quillBackend?.addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1])
        case .closeSubpath:
            quillBackend?.closePath()
        }
    }
    public func clip() {
        quillBackend?.clip()
        if let path = quillCurrentPath.copy() {
            quillAddClip(path, using: .winding)
        }
        clearCurrentPath()
    }
    public func clip(using rule: CGPathFillRule) {
        quillBackend?.clip(using: rule)
        if let path = quillCurrentPath.copy() {
            quillAddClip(path, using: rule)
        }
        clearCurrentPath()
    }
    public func clip(to rect: CGRect) {
        quillBackend?.clip(to: rect)
        guard let normalizedRect = Self.quillNormalizedRect(rect) else {
            return
        }

        quillAddClip(CGPath(rect: normalizedRect, transform: nil), using: .winding)
    }
    public func resetClip() {
        quillClipRegions.removeAll()
    }
    public func clip(to rect: CGRect, mask image: Any) {
        guard let source = Self.quillBitmapSource(from: image) else {
            return
        }
        quillAddMaskClip(rect: rect, source: source)
    }

    public func saveGState() {
        quillStateStack.append(QuillGraphicsState(
            fillRGBA: quillFillRGBA,
            strokeRGBA: quillStrokeRGBA,
            lineWidth: quillLineWidth,
            lineCap: quillLineCap,
            lineJoin: quillLineJoin,
            miterLimit: quillMiterLimit,
            lineDashPhase: quillLineDashPhase,
            lineDashLengths: quillLineDashLengths,
            allowsAntialiasing: quillAllowsAntialiasing,
            shouldAntialias: quillShouldAntialias,
            allowsFontSmoothing: quillAllowsFontSmoothingState,
            shouldSmoothFonts: quillShouldSmoothFontsState,
            allowsFontSubpixelPositioning: quillAllowsFontSubpixelPositioningState,
            shouldSubpixelPositionFonts: quillShouldSubpixelPositionFontsState,
            allowsFontSubpixelQuantization: quillAllowsFontSubpixelQuantizationState,
            shouldSubpixelQuantizeFonts: quillShouldSubpixelQuantizeFontsState,
            alpha: quillAlpha,
            blendMode: quillBlendMode,
            shadow: quillShadow,
            ctm: quillCTM,
            clipRegions: quillClipRegions
        ))
        quillBackend?.saveGState()
    }
    public func restoreGState() {
        if let state = quillStateStack.popLast() {
            quillFillRGBA = state.fillRGBA
            quillStrokeRGBA = state.strokeRGBA
            quillLineWidth = state.lineWidth
            quillLineCap = state.lineCap
            quillLineJoin = state.lineJoin
            quillMiterLimit = state.miterLimit
            quillLineDashPhase = state.lineDashPhase
            quillLineDashLengths = state.lineDashLengths
            quillAllowsAntialiasing = state.allowsAntialiasing
            quillShouldAntialias = state.shouldAntialias
            quillAllowsFontSmoothingState = state.allowsFontSmoothing
            quillShouldSmoothFontsState = state.shouldSmoothFonts
            quillAllowsFontSubpixelPositioningState = state.allowsFontSubpixelPositioning
            quillShouldSubpixelPositionFontsState = state.shouldSubpixelPositionFonts
            quillAllowsFontSubpixelQuantizationState = state.allowsFontSubpixelQuantization
            quillShouldSubpixelQuantizeFontsState = state.shouldSubpixelQuantizeFonts
            quillAlpha = state.alpha
            quillBlendMode = state.blendMode
            quillShadow = state.shadow
            quillCTM = state.ctm
            quillClipRegions = state.clipRegions
        }
        quillBackend?.restoreGState()
    }
    public func beginTransparencyLayer(auxiliaryInfo: Any?) {
        quillBackend?.beginTransparencyLayer(auxiliaryInfo: auxiliaryInfo)
        guard quillCanDrawCurrentBitmap,
              let currentBytes = quillBitmapBytes,
              let requiredByteCount = Self.quillBitmapStorageByteCount(height: height, bytesPerRow: bytesPerRow),
              currentBytes.count >= requiredByteCount
        else {
            return
        }

        quillTransparencyLayerStack.append(QuillTransparencyLayer(
            parentBytes: currentBytes,
            alpha: quillAlpha,
            blendMode: quillBlendMode,
            shadow: quillShadow,
            clipRegions: quillClipRegions
        ))
        quillBitmapBytes = Array(repeating: 0, count: requiredByteCount)
        quillAlpha = 1
        quillBlendMode = .normal
        quillShadow = nil
    }
    public func endTransparencyLayer() {
        quillBackend?.endTransparencyLayer()
        guard let layer = quillTransparencyLayerStack.popLast(),
              let layerPixels = quillBitmapBytes
        else {
            return
        }
        quillCompositeTransparencyLayer(layerPixels, using: layer)
    }
    public func endPage() {}
    public func translateBy(x: CGFloat, y: CGFloat) {
        quillCTM = quillCTM.translatedBy(x: x, y: y)
        quillBackend?.translateBy(x: x, y: y)
    }
    public func scaleBy(x: CGFloat, y: CGFloat) {
        quillCTM = quillCTM.scaledBy(x: x, y: y)
        quillBackend?.scaleBy(x: x, y: y)
    }
    public func rotate(by angle: CGFloat) {
        quillCTM = quillCTM.rotated(by: angle)
        quillBackend?.rotate(by: angle)
    }
    public func concatenate(_ transform: CGAffineTransform) {
        quillCTM = quillCTM.concatenating(transform)
        quillBackend?.concatenate(transform)
    }
    public func concatenate(_ transform: Any) {
        guard let transform = transform as? CGAffineTransform else { return }
        concatenate(transform)
    }

    public func draw(_ image: Any, in rect: CGRect) {
        quillBackend?.draw(image, in: rect, interpolationQuality: interpolationQuality)
        quillDrawBitmapImage(image, in: rect)
    }
    public func drawLinearGradient(_ gradient: Any?, start: CGPoint, end: CGPoint, options: CGGradientDrawingOptions) {
        guard let gradient = gradient as? CGGradient else {
            return
        }
        quillDrawBitmapLinearGradient(gradient, start: start, end: end, options: options)
    }
    public func drawRadialGradient(_ gradient: Any?, startCenter: CGPoint, startRadius: CGFloat, endCenter: CGPoint, endRadius: CGFloat, options: CGGradientDrawingOptions) {
        guard let gradient = gradient as? CGGradient else {
            return
        }
        quillDrawBitmapRadialGradient(
            gradient,
            startCenter: startCenter,
            startRadius: startRadius,
            endCenter: endCenter,
            endRadius: endRadius,
            options: options
        )
    }

    private func clearCurrentPath() {
        quillCurrentPath = CGMutablePath()
    }
}

public typealias CGWindowID = UInt32

public struct CGWindowListOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let optionAll: CGWindowListOption = []
    public static let optionIncludingWindow = CGWindowListOption(rawValue: 1 << 0)
}

public struct CGWindowImageOption: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let `default`: CGWindowImageOption = []
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
        "png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "tif", "svg", "pdf"
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

                if let assetPath = assetCatalogImagePath(for: name, under: directory) {
                    return assetPath
                }
            }
        }

        return nil
    }

    public static func imageSize(forResource name: String) -> CGSize? {
        guard let path = path(forResource: name, candidateExtensions: commonImageExtensions) else {
            return nil
        }
        return QuillImageMetadata.size(ofFileAt: path)
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

    public static func localizedString(
        forKey key: String,
        tableName: String? = nil,
        value: String = "",
        preferredLocalizations: [String] = []
    ) -> String {
        guard !key.isEmpty else { return value }
        let table = (tableName?.isEmpty == false ? tableName! : "Localizable")
        let roots = localizationRoots() + resourceRoots()

        for localization in localizationCandidates(preferredLocalizations) {
            for root in roots {
                for path in localizedStringTablePaths(tableName: table, localization: localization, under: root) {
                    guard let strings = QuillLocalizedStringTables.table(at: path),
                          let localized = strings[key] else {
                        continue
                    }
                    return localized
                }
            }
        }

        return value.isEmpty ? key : value
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

    private static func assetCatalogImagePath(for name: String, under directory: URL) -> String? {
        let assetName = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        guard !assetName.isEmpty else { return nil }

        let catalogRoots = imageCatalogRoots(under: directory)
        for catalogRoot in catalogRoots {
            let direct = catalogRoot.appendingPathComponent("\(assetName).imageset", isDirectory: true)
            if let path = imagePath(inImageset: direct) {
                return path
            }

            guard let enumerator = FileManager.default.enumerator(
                at: catalogRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let url as URL in enumerator where url.lastPathComponent == "\(assetName).imageset" {
                if let path = imagePath(inImageset: url) {
                    return path
                }
            }
        }
        return nil
    }

    private static func imageCatalogRoots(under directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return []
        }

        if directory.pathExtension == "xcassets" || fileManager.fileExists(
            atPath: directory.appendingPathComponent("Contents.json").path
        ) {
            return [directory]
        }

        let children = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.filter { child in
            child.pathExtension == "xcassets"
        }
    }

    private static func imagePath(inImageset imageset: URL) -> String? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: imageset.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let contentsURL = imageset.appendingPathComponent("Contents.json")
        guard let data = try? Data(contentsOf: contentsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let images = json["images"] as? [[String: Any]] else {
            return nil
        }

        for image in images {
            guard let filename = image["filename"] as? String, !filename.isEmpty else {
                continue
            }
            let imageURL = imageset.appendingPathComponent(filename)
            var imageIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: imageURL.path, isDirectory: &imageIsDirectory),
               !imageIsDirectory.boolValue {
                return imageURL.path
            }
        }
        return nil
    }

    private static func localizationCandidates(_ preferredLocalizations: [String]) -> [String] {
        var rawCandidates = preferredLocalizations
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["QUILLUI_LOCALE"], !override.isEmpty {
            rawCandidates.append(override)
        }
        if let language = environment["LANGUAGE"], !language.isEmpty {
            rawCandidates += language
                .split(separator: ":", omittingEmptySubsequences: true)
                .map(String.init)
        }
        if let lang = environment["LANG"], !lang.isEmpty {
            rawCandidates.append(lang)
        }
        rawCandidates += Locale.preferredLanguages
        rawCandidates += ["en", "Base"]

        var result: [String] = []
        var seen: Set<String> = []
        func append(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let withoutEncoding = trimmed.split(separator: ".", maxSplits: 1).first.map(String.init) ?? trimmed
            let withoutModifier = withoutEncoding.split(separator: "@", maxSplits: 1).first.map(String.init) ?? withoutEncoding
            let normalized = withoutModifier.replacingOccurrences(of: "-", with: "_").lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
            result.append(normalized)
            if let language = normalized.split(separator: "_", maxSplits: 1).first,
               language != normalized,
               seen.insert(String(language)).inserted {
                result.append(String(language))
            }
        }
        for candidate in rawCandidates {
            append(candidate)
        }
        return result
    }

    private static func localizedStringTablePaths(tableName: String, localization: String, under root: URL) -> [String] {
        let filename = tableName.hasSuffix(".strings") ? tableName : "\(tableName).strings"
        let lprojName = "\(localization).lproj"
        var candidates: [URL] = []

        if root.pathExtension.lowercased() == "lproj" {
            candidates.append(root.appendingPathComponent(filename))
        } else {
            candidates.append(root.appendingPathComponent(lprojName, isDirectory: true).appendingPathComponent(filename))
            candidates.append(root
                .appendingPathComponent("translations", isDirectory: true)
                .appendingPathComponent(lprojName, isDirectory: true)
                .appendingPathComponent(filename))
        }

        return candidates.map(\.path)
    }

    private static func localizationRoots() -> [URL] {
        guard let raw = ProcessInfo.processInfo.environment["QUILLUI_LOCALIZATION_DIRS"] else {
            return []
        }
        return raw
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
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

private enum QuillLocalizedStringTables {
    nonisolated(unsafe) private static var cachedTables: [String: [String: String]?] = [:]
    private static let lock = NSLock()

    static func table(at path: String) -> [String: String]? {
        lock.lock()
        if let cached = cachedTables[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let parsed = parseTable(at: path)

        lock.lock()
        cachedTables[path] = parsed
        lock.unlock()
        return parsed
    }

    private static func parseTable(at path: String) -> [String: String]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        if let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: String] {
            return plist
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parseLooseStrings(text)
    }

    private static func parseLooseStrings(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var index = text.startIndex

        func skipWhitespaceAndComments() {
            while index < text.endIndex {
                if text[index].isWhitespace {
                    index = text.index(after: index)
                    continue
                }
                if text[index] == "/" {
                    let next = text.index(after: index)
                    guard next < text.endIndex else { return }
                    if text[next] == "/" {
                        index = text.index(after: next)
                        while index < text.endIndex, text[index] != "\n" {
                            index = text.index(after: index)
                        }
                        continue
                    }
                    if text[next] == "*" {
                        index = text.index(after: next)
                        while index < text.endIndex {
                            if text[index] == "*" {
                                let slash = text.index(after: index)
                                if slash < text.endIndex, text[slash] == "/" {
                                    index = text.index(after: slash)
                                    break
                                }
                            }
                            index = text.index(after: index)
                        }
                        continue
                    }
                }
                return
            }
        }

        func parseQuotedString() -> String? {
            skipWhitespaceAndComments()
            guard index < text.endIndex, text[index] == "\"" else { return nil }
            index = text.index(after: index)
            var output = ""
            while index < text.endIndex {
                let character = text[index]
                index = text.index(after: index)
                if character == "\"" {
                    return output
                }
                if character == "\\", index < text.endIndex {
                    let escaped = text[index]
                    index = text.index(after: index)
                    switch escaped {
                    case "n": output.append("\n")
                    case "r": output.append("\r")
                    case "t": output.append("\t")
                    case "\"": output.append("\"")
                    case "\\": output.append("\\")
                    default: output.append(escaped)
                    }
                } else {
                    output.append(character)
                }
            }
            return nil
        }

        while index < text.endIndex {
            skipWhitespaceAndComments()
            guard let key = parseQuotedString() else { break }
            skipWhitespaceAndComments()
            guard index < text.endIndex, text[index] == "=" else { break }
            index = text.index(after: index)
            guard let value = parseQuotedString() else { break }
            result[key] = value
            skipWhitespaceAndComments()
            if index < text.endIndex, text[index] == ";" {
                index = text.index(after: index)
            }
        }

        return result
    }
}

private enum QuillImageMetadata {
    static func size(ofFileAt path: String) -> CGSize? {
        let url = URL(fileURLWithPath: path)
        switch url.pathExtension.lowercased() {
        case "pdf":
            return pdfPageSize(at: url)
        case "png":
            return pngPixelSize(at: url)
        default:
            return nil
        }
    }

    private static func pdfPageSize(at url: URL) -> CGSize? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let body = String(decoding: data, as: UTF8.self)
        let pattern = #"/(?:MediaBox|CropBox)\s*\[\s*([+-]?\d+(?:\.\d+)?)\s+([+-]?\d+(?:\.\d+)?)\s+([+-]?\d+(?:\.\d+)?)\s+([+-]?\d+(?:\.\d+)?)\s*\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              match.numberOfRanges == 5 else {
            return nil
        }

        func number(_ index: Int) -> CGFloat? {
            guard let range = Range(match.range(at: index), in: body) else { return nil }
            guard let value = Double(String(body[range])) else { return nil }
            return CGFloat(value)
        }

        guard let x0 = number(1), let y0 = number(2), let x1 = number(3), let y1 = number(4) else {
            return nil
        }
        let width = abs(x1 - x0)
        let height = abs(y1 - y0)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func pngPixelSize(at url: URL) -> CGSize? {
        guard let data = try? Data(contentsOf: url), data.count >= 24 else { return nil }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard Array(data.prefix(signature.count)) == signature else { return nil }

        func uint32(at offset: Int) -> UInt32 {
            data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }

        let width = uint32(at: 16)
        let height = uint32(at: 20)
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }
}

public enum QuillImageCompositingOperation: Sendable {
    case copy
    case sourceOver
}

open class RSImage: NSObject, NSSecureCoding, @unchecked Sendable {
    public static var supportsSecureCoding: Bool { true }

    public enum ResizingMode: Int, Sendable {
        case tile
        case stretch
    }

    public override init() {}
    public required init?(coder: NSCoder) {
        super.init()
        self.data = coder.decodeObject(forKey: "data") as? Data
    }

    public func encode(with coder: NSCoder) {
        coder.encode(data, forKey: "data")
    }

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
            if let size = QuillResourceLookup.imageSize(forResource: name) {
                self.size = size
            }
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

    public convenience init(imageLiteralResourceName name: String) {
        self.init(named: name)!
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
    private var quillBackingCGImage: CGImage?
    private var quillImageScale: CGFloat = 1
    private var quillFocusContext: CGContext?
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

    open override func copy() -> Any {
        let image = data.flatMap { RSImage(data: $0) } ?? RSImage()
        image.quillBackingCGImage = quillBackingCGImage
        image.quillImageScale = quillImageScale
        image.size = size
        image.capInsets = capInsets
        image.resizingMode = resizingMode
        return image
    }

    public func lockFocus() {
        quillBeginFocus(flipped: false)
    }

    public func lockFocusFlipped(_ flipped: Bool) {
        quillBeginFocus(flipped: flipped)
    }

    public func unlockFocus() {
        guard let context = quillFocusContext else {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillFoundation",
                operation: "NSImage.unlockFocus",
                severity: .warning,
                message: "NSImage.unlockFocus called without an active Linux focus context."
            )
            return
        }

        if QuillGraphicsContextState.currentContext === context {
            QuillGraphicsContextState.popContext()
        }
        quillBackingCGImage = context.makeImage()
        quillImageScale = 1
        data = nil
        quillFocusContext = nil
    }

    private func quillBeginFocus(flipped: Bool) {
        guard quillFocusContext == nil else {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillFoundation",
                operation: "NSImage.lockFocus",
                severity: .warning,
                message: "NSImage.lockFocus called while this image already has an active Linux focus context."
            )
            return
        }

        let pixelWidth = Int(size.width.rounded(.up))
        let pixelHeight = Int(size.height.rounded(.up))
        guard pixelWidth > 0, pixelHeight > 0 else {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillFoundation",
                operation: "NSImage.lockFocus",
                severity: .warning,
                message: "NSImage.lockFocus requires a positive image size on Linux."
            )
            return
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            QuillCompatibilityDiagnostics.shared.record(
                subsystem: "QuillFoundation",
                operation: "NSImage.lockFocus",
                severity: .warning,
                message: "NSImage.lockFocus could not create a Linux bitmap drawing context."
            )
            return
        }

        if let quillBackingCGImage {
            context.draw(
                quillBackingCGImage,
                in: CGRect(origin: .zero, size: CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
            )
        }
        if flipped {
            context.translateBy(x: 0, y: CGFloat(pixelHeight))
            context.scaleBy(x: 1, y: -1)
        }

        quillFocusContext = context
        QuillGraphicsContextState.pushContext(context)
    }

    private func quillRecordImageDrawFallback(_ message: String) {
        QuillCompatibilityDiagnostics.shared.record(
            subsystem: "QuillFoundation",
            operation: "NSImage.draw",
            severity: .warning,
            message: message
        )
    }

    public func draw(
        in destinationRect: CGRect,
        from sourceRect: CGRect,
        operation: QuillImageCompositingOperation,
        fraction: Double
    ) {
        guard let context = QuillGraphicsContextState.currentContext else {
            quillRecordImageDrawFallback("NSImage.draw skipped because no current bitmap graphics context is active on Linux.")
            return
        }
        guard let sourceImage = cgImage else {
            quillRecordImageDrawFallback("NSImage.draw skipped because the image has no CGImage bitmap backing on Linux.")
            return
        }

        let imageToDraw: CGImage
        if sourceRect.width > 0, sourceRect.height > 0, let cropped = sourceImage.cropping(to: sourceRect) {
            imageToDraw = cropped
        } else {
            imageToDraw = sourceImage
        }

        context.saveGState()
        switch operation {
        case .copy:
            context.setBlendMode(.copy)
        case .sourceOver:
            context.setBlendMode(.normal)
        }
        context.setAlpha(CGFloat(fraction))
        context.draw(imageToDraw, in: destinationRect)
        context.restoreGState()
    }

    // MARK: UIImage source-compat surface (Linux placeholders)
    public convenience init?(contentsOfFile path: String) {
        self.init()
        self.size = CGSize(width: 32, height: 32)
    }
    @_disfavoredOverload
    public convenience init?<T>(_ source: T) {
        self.init()
        self.size = CGSize(width: 32, height: 32)
        _ = source
    }
    public func jpegData(compressionQuality: CGFloat) -> Data? { data }
    public var cgImage: CGImage? { quillBackingCGImage }
    public func cgImage(forProposedRect rect: UnsafeMutablePointer<CGRect>?, context: Any?, hints: [AnyHashable: Any]?) -> CGImage? {
        _ = (rect, context, hints)
        return cgImage
    }
    public var scale: CGFloat { quillImageScale }

    public enum Orientation: Int, Sendable {
        case up, down, left, right, upMirrored, downMirrored, leftMirrored, rightMirrored
    }
    public var imageOrientation: Orientation { .up }

    /// `UIImage.withHorizontallyFlippedOrientation()` source-compat. On Apple this
    /// returns a copy whose `imageOrientation` is mirrored horizontally. The Linux
    /// image is opaque (no raster, orientation always reports `.up`), so this is
    /// inert and returns self. SignalUI: VideoTimelineView flips the left trim handle.
    public func withHorizontallyFlippedOrientation() -> RSImage { self }

    public func withTintColor(_ color: Any) -> RSImage { self }
    // Typed overload so a leading-dot color literal (e.g. `.white`) resolves its
    // contextual base. SSK: AvatarBuilder.releaseNotesIcon does
    // `UIImage(named:)!.withTintColor(.white)`. Inert (returns self).
    public func withTintColor(_ color: RSColor) -> RSImage { self }
    public func draw(in rect: CGRect) {
        guard let context = QuillGraphicsContextState.currentContext,
              let cgImage
        else {
            return
        }
        context.draw(cgImage, in: rect)
    }
    public func draw(at point: CGPoint) {
        draw(in: CGRect(origin: point, size: size))
    }

    /// `UIImage(cgImage:scale:orientation:)` source-compat. On Linux the backing
    /// CGImage carries Quill's raw BGRA backing when available.
    public convenience init(cgImage: CGImage, scale: CGFloat = 1, orientation: Orientation = .up) {
        self.init()
        let resolvedScale = scale.isFinite && scale > 0 ? scale : 1
        self.quillBackingCGImage = cgImage
        self.quillImageScale = resolvedScale
        self.size = CGSize(
            width: CGFloat(cgImage.width) / resolvedScale,
            height: CGFloat(cgImage.height) / resolvedScale
        )
        _ = orientation
    }

    public convenience init(cgImage: CGImage, size: CGSize) {
        self.init()
        self.quillBackingCGImage = cgImage
        self.size = size
    }
}
public typealias UIImage = RSImage

public struct RSCGColor: Equatable, Sendable {
    public var components: [CGFloat]?
    public var numberOfComponents: Int { components?.count ?? 0 }
    public var alpha: CGFloat { components?.last ?? 1 }
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

public enum QuillGraphicsContextState {
    nonisolated(unsafe) private static var contextStack: [CGContext] = []
    nonisolated(unsafe) private static var fillColorStack: [RSCGColor] = []
    nonisolated(unsafe) private static var activeFillColor: RSCGColor = .black

    public static var currentContext: CGContext? {
        contextStack.last
    }

    public static var currentFillColor: RSCGColor {
        activeFillColor
    }

    public static func pushContext(_ context: CGContext) {
        contextStack.append(context)
        fillColorStack.append(activeFillColor)
        activeFillColor = .black
        context.setFillColor(RSCGColor.black)
    }

    public static func popContext() {
        if !contextStack.isEmpty {
            contextStack.removeLast()
        }
        activeFillColor = fillColorStack.popLast() ?? .black
    }

    public static func setFillColor(_ color: RSCGColor) {
        activeFillColor = color
        currentContext?.setFillColor(color)
    }
}

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

    /// Apple's UIColor(white:alpha:) / NSColor(white:alpha:) grayscale
    /// convenience initializer. Declared on the class — the ONE owner — so every
    /// module that can see UIColor/RSColor resolves the same initializer. (It
    /// used to be declared twice, as extensions in QuillAppKit and in
    /// SignalServiceKitObjCPort; any module importing both, e.g. SignalUI, hit
    /// "ambiguous use of 'init(white:alpha:)'" on every call.)
    public convenience init(white: CGFloat, alpha: CGFloat) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    /// UIColor.setFill() sets this color as the fill color in the current UIKit
    /// graphics context when a UIGraphics renderer or image context is active.
    public func setFill() {
        QuillGraphicsContextState.setFillColor(cgColor)
    }

    public static let clear = RSColor(red: 0, green: 0, blue: 0, alpha: 0)
    public static let white = RSColor(red: 1, green: 1, blue: 1, alpha: 1)
    public static let black = RSColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let red = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
    public static let orange = RSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1)
    public static let label = RSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)
    public static let secondaryLabel = RSColor(red: 0.38, green: 0.38, blue: 0.40, alpha: 1)
    public static let tertiaryLabel = RSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)
    public static let systemBackground = RSColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1)
    public static let secondarySystemBackground = RSColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1)
    // Apple's light-mode grouped backgrounds are both #F2F2F7 (the dark
    // variants differ, but RSColor stores a single light value).
    public static let systemGroupedBackground = RSColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    public static let tertiarySystemGroupedBackground = RSColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    public static let systemGray = RSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)
    public static let systemGray2 = RSColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
    public static let systemBlue = RSColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
    public static let systemRed = RSColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1)
    public static let pink = RSColor(red: 1.00, green: 0.18, blue: 0.33, alpha: 1)

    /// Returns a 4-tuple [R, G, B, A]. Matches the CGColor.components shape.
    public var cgColor: RSCGColor { RSCGColor(components: [_red, _green, _blue, _alpha]) }
    public func set() {
        setFill()
    }
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
    public let fontName: String
    public init(pointSize: CGFloat, fontName: String = ".AppleSystemUIFont") {
        self.pointSize = pointSize
        self.fontName = fontName
    }
    public override init() {
        self.pointSize = 13
        self.fontName = ".AppleSystemUIFont"
    }
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
        self.init(pointSize: size, fontName: name)
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

    func applying(_ transform: CGAffineTransform) -> CGSize {
        CGSize(
            width: width * transform.a + height * transform.c,
            height: width * transform.b + height * transform.d
        )
    }

    // NOTE: `static func max(_:_:)` is NOT declared here. SignalServiceKit owns
    // the canonical `CGSize.max(_:_:)` (Util/OWSMath.swift, alongside ceil /
    // floor / round / add / scale). A twin here made every `CGSize.max($0, $1)`
    // in SignalUI ambiguous (64 errors) — one name, one owner.
}

public extension CGPoint {
    func equalTo(_ other: CGPoint) -> Bool { self == other }
}

public extension CGRect {
    func equalTo(_ other: CGRect) -> Bool { self == other }

    func applying(_ transform: CGAffineTransform) -> CGRect {
        guard !isNull else { return self }
        let points = [
            CGPoint(x: minX, y: minY).applying(transform),
            CGPoint(x: maxX, y: minY).applying(transform),
            CGPoint(x: minX, y: maxY).applying(transform),
            CGPoint(x: maxX, y: maxY).applying(transform),
        ]
        guard let first = points.first else { return self }
        let minX = points.dropFirst().reduce(first.x) { Swift.min($0, $1.x) }
        let minY = points.dropFirst().reduce(first.y) { Swift.min($0, $1.y) }
        let maxX = points.dropFirst().reduce(first.x) { Swift.max($0, $1.x) }
        let maxY = points.dropFirst().reduce(first.y) { Swift.max($0, $1.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func fill() {}
}

#if os(Linux)
public final class ListFormatter: Formatter {
    public var locale: Locale?

    public override init() {
        super.init()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func string(from items: [Any]) -> String? {
        items.map { "\($0)" }.joined(separator: ", ")
    }
}
#endif

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
    /// Pixel-space bounds. SSK's UIDevice+FeatureSupport switches on the EXACT
    /// `.nativeBounds.height` against known iPhone pixel heights and traps
    /// (owsFailDebug "unknown device format") on anything else. Report a real
    /// device profile (iPhone 16: 1179×2556) so those heuristics resolve; the GTK
    /// window's own size is independent (driven by view frames, not this).
    public var nativeBounds: CGRect {
        CGRect(x: 0, y: 0, width: 1179, height: 2556)
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
public func NSLocalizedString(_ key: String, comment: String) -> String {
    QuillResourceLookup.localizedString(forKey: key)
}
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
