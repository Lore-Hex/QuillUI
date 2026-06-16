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
@_exported import func QuillFoundation.CGColorSpaceCreateDeviceRGB
@_exported import func QuillFoundation.CGColorSpaceCreateDeviceGray
#endif
