#if os(Linux)
// On Apple platforms these type names are OWNED by CoreGraphics — a file with
// only `import CoreGraphics` (the Apple-faithful import for pure-geometry /
// pure-drawing files, e.g. SolderScope's ViewTransform.swift) resolves all of
// them. QuillUI's canonical implementations live in QuillFoundation, so
// re-export them here. Selective per-decl re-exports (not the whole module):
// QuillFoundation also carries NS*/utility additions that `import CoreGraphics`
// must not drag into scope. Re-exporting the same canonical types keeps a
// single identity — files importing Foundation + QuillFoundation + CoreGraphics
// in any combination see no ambiguity.
@_exported import struct QuillFoundation.CGAffineTransform
@_exported import class QuillFoundation.CGPath
@_exported import class QuillFoundation.CGMutablePath
@_exported import class QuillFoundation.CGContext
@_exported import class QuillFoundation.CGImage
@_exported import class QuillFoundation.CGColorSpace
@_exported import class QuillFoundation.CGGradient
@_exported import struct QuillFoundation.CGVector
@_exported import typealias QuillFoundation.CGColor
@_exported import struct QuillFoundation.RSCGColor
@_exported import enum QuillFoundation.CGBlendMode
@_exported import enum QuillFoundation.CGLineCap
@_exported import enum QuillFoundation.CGLineJoin
@_exported import enum QuillFoundation.CGPathFillRule
@_exported import enum QuillFoundation.CGInterpolationQuality
@_exported import struct QuillFoundation.CGBitmapInfo
@_exported import enum QuillFoundation.CGImageAlphaInfo
@_exported import struct QuillFoundation.CGGradientDrawingOptions
@_exported import enum QuillFoundation.CGColorRenderingIntent
// CGPoint/CGSize/CGRect/CGVector/CGFloat are owned by CoreGraphics on Apple,
// but on Linux they live in (swift-corelibs) Foundation, not QuillFoundation.
// A pure-geometry file with only `import CoreGraphics` (Euclid+CoreGraphics,
// SolderScope's ViewTransform, …) still expects them in scope, so surface the
// Foundation ones here — same canonical identity, no NS* leakage.
@_exported import struct Foundation.CGPoint
@_exported import struct Foundation.CGSize
@_exported import struct Foundation.CGRect
@_exported import struct Foundation.CGFloat
@_exported import enum QuillFoundation.CGPathElementType
@_exported import struct QuillFoundation.CGPathElement
@_exported import func QuillFoundation.CGColorSpaceCreateDeviceRGB
@_exported import func QuillFoundation.CGColorSpaceCreateDeviceGray
// CFTypeRef is canonical in QuillKit — re-export it (don't redeclare, or
// files that already see QuillKit's via AppKit get an ambiguous lookup).
@_exported import typealias QuillKit.CFTypeRef

// CoreFoundation type-identity sliver Euclid's defaultMaterialLookup needs (it
// compares a material against CGImage.typeID / CGColor.typeID to detect image /
// colour contents). CFTypeID / CFGetTypeID are not vended to `import
// CoreGraphics`-only files, so model them here.
public typealias CFTypeID = UInt

public extension CGImage {
    static var typeID: CFTypeID { 1 }
}
// NOTE: RSCGColor (== CGColor) already declares `static var typeID` in
// QuillFoundation, so it is NOT redeclared here (that caused an ambiguous
// `CGColor.typeID` lookup).

public func CFGetTypeID(_ cf: CFTypeRef) -> CFTypeID {
    // CGColor is a value type on QuillOS, so only CGImage reaches here as an
    // object; everything else (NSColor, …) falls through to 0.
    cf is CGImage ? CGImage.typeID : 0
}
#endif
