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

// MARK: - CGImagePropertyOrientation
//
// The EXIF-style orientation enum (raw UInt32, values 1...8 matching the EXIF
// spec). Lives in ImageIO on Apple. SignalServiceKit reads it from image
// metadata and extends it with `.uiImageOrientation`; that extension lives in
// SSK, so only the base enum is needed here.
public enum CGImagePropertyOrientation: UInt32, Sendable {
    case up = 1
    case upMirrored = 2
    case down = 3
    case downMirrored = 4
    case leftMirrored = 5
    case right = 6
    case rightMirrored = 7
    case left = 8
}

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

// MARK: - CGDataProvider direct-access surface
//
// CGDataProvider+SSK.swift builds a "direct" provider over a FileHandle so an
// attachment can be decoded without loading the whole file into memory. It uses
// the CGDataProviderDirectCallbacks struct and the
// CGDataProvider(directInfo:size:callbacks:) initializer. On Linux there is no
// CoreGraphics image pipeline to pull bytes through the provider, so the
// initializer is inert (it stores nothing and never invokes the callbacks); it
// exists only so the upstream `extension CGDataProvider { static func from }`
// and its call sites compile. The position parameter of getBytesAtPosition is
// typed UInt64 (rather than Apple's off_t/Int64) to match the upstream closure,
// which compares it against FileHandle.offset() (a UInt64) directly.
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

extension CGDataProvider {
    public convenience init?(
        directInfo info: UnsafeMutableRawPointer?,
        size: Int64,
        callbacks: UnsafePointer<CGDataProviderDirectCallbacks>?
    ) {
        // Inert: no CoreGraphics consumer pulls bytes on Linux. The provider's
        // releaseInfo would normally balance the passRetained the caller does, so
        // release it here to avoid leaking the wrapper the caller handed us.
        if let info, let release = callbacks?.pointee.releaseInfo {
            release(info)
        }
        self.init()
    }
}
