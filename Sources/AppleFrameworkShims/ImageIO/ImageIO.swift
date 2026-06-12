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
@_exported import CoreFoundation
import QuillFoundation

// MARK: - Opaque source types

public class CGImageSource {}
public class CGDataProvider {
    public init() {}
    public init?(data: Data) {
        _ = data
    }
    public init?(
        dataInfo info: UnsafeMutableRawPointer?,
        data: UnsafeRawPointer,
        size: Int,
        releaseData: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer, Int) -> Void)?
    ) {
        _ = (info, data, size, releaseData)
    }
}

public extension CGImage {
    var utType: String? { nil }
}

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

// Takes `Data` (not `CFData`): swift-corelibs has no Data<->CFData bridge, so
// `someData as CFData` fails at call sites. Inert (returns nil on Linux). The
// fetch-patch drops the `as CFData` casts at the SSK call sites.
public func CGImageSourceCreateWithData(_ data: Data, _ options: Any?) -> CGImageSource? { nil }

public func CGImageSourceCreateWithDataProvider(_ provider: CGDataProvider, _ options: Any?) -> CGImageSource? { nil }

// Takes URL (not CFURL): swift-corelibs has no URL<->CFURL bridge, so callers
// can't write `url as CFURL`; the fetch-patch drops that cast and passes the URL.
public func CGImageSourceCreateWithURL(_ url: URL, _ options: Any?) -> CGImageSource? { nil }

public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int { 0 }

public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> CGImage? { nil }

public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> CGImage? { nil }

// options takes `Any?` (not CFDictionary?) so SSK callers can pass a native
// [String: Any] / [String: Bool] without an `as CFDictionary` bridge (absent on
// swift-corelibs). Returns [String: Any]? (not CFDictionary?) so the callers'
// `as? [String: Any]` / `as? [String: AnyObject]` resolve. Inert (nil) on Linux.
public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> [String: Any]? { nil }

// MARK: - kCGImageSource* / kCGImageProperty* constants
//
// Real ImageIO declares these as CFStringRef. On Linux a String literal is not
// convertible to CFString (and a CFString global is not Sendable), so these are
// plain Strings -- SSK only ever uses them via `as String` or as dictionary
// keys, both of which a String satisfies. The values are arbitrary (no metadata
// dictionary is ever populated on Linux).

public let kCGImageSourceShouldCache: String = "kCGImageSourceShouldCache"
public let kCGImageSourceShouldAllowFloat: String = "kCGImageSourceShouldAllowFloat"
public let kCGImageSourceCreateThumbnailFromImageAlways: String = "kCGImageSourceCreateThumbnailFromImageAlways"
public let kCGImageSourceCreateThumbnailWithTransform: String = "kCGImageSourceCreateThumbnailWithTransform"
public let kCGImageSourceThumbnailMaxPixelSize: String = "kCGImageSourceThumbnailMaxPixelSize"

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

// MARK: - CGImageDestination (image writing)
//
// SignalServiceKit's BadgeAssets writes a sprite-sheet PNG via CGImageDestination.
// ImageIO has no encoder on Linux, so this is INERT: creation returns nil and the
// add/finalize calls are no-ops, so the upstream guard on the nil destination
// short-circuits and no file is written. HONEST STATUS: badge sprite sheets are not
// generated on Linux yet (a real PNG encoder would be needed). Like
// CGImageSourceCreateWithURL, the create takes URL (not CFURL): swift-corelibs has no
// URL<->CFURL bridge, so the fetch-patch drops `as CFURL` at the call site.

public class CGImageDestination {}

// `type` is the UTI string (e.g. "public.png"). Apple's signature is CFString, but
// swift-corelibs has no String<->CFString bridge so the upstream `UTType.png.identifier
// as CFString` cast can't compile; the shim takes String and the fetch-patch drops the
// cast. Inert anyway (nil destination), so the value is unused.
public func CGImageDestinationCreateWithURL(
    _ url: URL,
    _ type: String,
    _ count: Int,
    _ options: Any?
) -> CGImageDestination? { nil }

public func CGImageDestinationCreateWithData(
    _ data: NSMutableData,
    _ type: String,
    _ count: Int,
    _ options: Any?
) -> CGImageDestination? {
    _ = data
    _ = type
    _ = count
    _ = options
    return nil
}

public func CGImageDestinationAddImage(
    _ idst: CGImageDestination,
    _ image: CGImage,
    _ properties: Any?
) {}

public let kCGImageDestinationLossyCompressionQuality: String = "kCGImageDestinationLossyCompressionQuality"

@discardableResult
public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool { false }
