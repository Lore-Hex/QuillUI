//
// QuillUI Linux shim for `ImageIO`.
//
// SignalServiceKit reads image metadata (dimensions, orientation, color model,
// frame count) via CGImageSource. ImageIO is unavailable on Linux, so these are
// inert: the create functions return nil and property/count queries report
// "no image". Image metadata is therefore unavailable on Linux until a real
// decoder is bridged (deferred) -- callers already handle the nil/zero results.
//
// The surface mirrors the exact free functions and kCGImage* constants SSK
// references so the upstream Swift compiles. CGImage comes from QuillFoundation.
//
import Foundation
import CoreFoundation
import QuillFoundation

// MARK: - Opaque source types

public class CGImageSource {}
public class CGDataProvider {}

// MARK: - Create / query functions
//
// Inert: no image is ever decoded on Linux. Signatures match Core Graphics'
// C functions (unlabeled positional arguments).

public func CGImageSourceCreateWithData(_ data: CFData, _ options: CFDictionary?) -> CGImageSource? { nil }

public func CGImageSourceCreateWithDataProvider(_ provider: CGDataProvider, _ options: CFDictionary?) -> CGImageSource? { nil }

public func CGImageSourceCreateWithURL(_ url: CFURL, _ options: CFDictionary?) -> CGImageSource? { nil }

public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { 0 }

public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CGImage? { nil }

public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: CFDictionary?) -> CFDictionary? { nil }

// MARK: - kCGImageSource* / kCGImageProperty* constants
//
// Real ImageIO declares these as CFStringRef. On Linux a String literal is not
// convertible to CFString (and a CFString global is not Sendable), so these are
// plain Strings -- SSK only ever uses them via `as String` or as dictionary
// keys, both of which a String satisfies. The values are arbitrary (no metadata
// dictionary is ever populated on Linux).

public let kCGImageSourceShouldCache: String = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldAllowFloat: String = "kCGImageSourceShouldAllowFloat"

public let kCGImagePropertyOrientation: String = "Orientation"
public let kCGImagePropertyPixelWidth: String = "PixelWidth"
public let kCGImagePropertyPixelHeight: String = "PixelHeight"
public let kCGImagePropertyHasAlpha: String = "HasAlpha"
public let kCGImagePropertyDepth: String = "Depth"
public let kCGImagePropertyColorModel: String = "ColorModel"
public let kCGImagePropertyColorModelRGB: String = "RGB"
public let kCGImagePropertyColorModelGray: String = "Gray"
