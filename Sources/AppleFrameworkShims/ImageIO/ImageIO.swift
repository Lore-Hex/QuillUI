//
// QuillUI Linux shim for `ImageIO`.
//
// ImageIO is unavailable on Linux. QuillUI backs the app-facing subset with
// gdk-pixbuf so Swift apps can decode dimensions, downsample upload images, and
// encode JPEG/PNG/TIFF data without changing source.
//
// The surface mirrors the exact free functions and kCGImage* constants SSK
// references so the upstream Swift compiles. CGImage comes from QuillFoundation.
//
import Foundation
import CGdkPixbuf
@_exported import CoreFoundation
import QuillFoundation
@_exported import class QuillFoundation.CGDataProvider
@_exported import struct QuillFoundation.CGDataProviderDirectCallbacks

// MARK: - Opaque source types

public class CGImageSource {
    fileprivate let data: Data
    fileprivate let typeIdentifier: String?

    fileprivate init(data: Data, typeIdentifier: String?) {
        self.data = data
        self.typeIdentifier = typeIdentifier
    }
}
public class CGImageMetadata {}
public typealias CGMutableImageMetadata = CGImageMetadata

public class CGImageMetadataTag {}

public extension CGImage {
    var utType: String? { quillUTType }
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

// MARK: - gdk-pixbuf bridge

private func quillImageIOUTType(forExtension pathExtension: String) -> String? {
    switch pathExtension.lowercased() {
    case "jpg", "jpeg", "jpe": return "public.jpeg"
    case "png": return "public.png"
    case "gif": return "com.compuserve.gif"
    case "tif", "tiff": return "public.tiff"
    case "webp": return "org.webmproject.webp"
    case "bmp": return "com.microsoft.bmp"
    default: return nil
    }
}

private func quillImageIOUTType(forPixbufFormat name: String?) -> String? {
    switch name?.lowercased() {
    case "jpeg", "jpg": return "public.jpeg"
    case "png": return "public.png"
    case "gif": return "com.compuserve.gif"
    case "tiff", "tif": return "public.tiff"
    case "webp": return "org.webmproject.webp"
    case "bmp": return "com.microsoft.bmp"
    default: return nil
    }
}

private func quillImageIOPixbufFormatName(_ format: OpaquePointer?) -> String? {
    guard let format else { return nil }
    guard let rawName = gdk_pixbuf_format_get_name(format) else { return nil }
    defer { g_free(rawName) }
    return String(cString: rawName)
}

private func quillImageIOFormatName(for type: String?) -> String? {
    switch type?.lowercased() {
    case "public.jpeg", "jpeg", "jpg", "image/jpeg": return "jpeg"
    case "public.png", "png", "image/png": return "png"
    case "public.tiff", "tiff", "tif", "image/tiff": return "tiff"
    default: return nil
    }
}

private func quillImageIODecodePixbuf(from source: Data) -> (pixbuf: OpaquePointer, utType: String?)? {
    guard !source.isEmpty else { return nil }
    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(gpointer(loader)) }

    let writeOK = source.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        guard let base = raw.baseAddress else { return false }
        let bytes = base.assumingMemoryBound(to: guchar.self)
        var error: UnsafeMutablePointer<GError>? = nil
        let ok = gdk_pixbuf_loader_write(loader, bytes, gsize(raw.count), &error)
        if let error { g_error_free(error) }
        return ok != 0
    }
    guard writeOK else { return nil }

    var closeError: UnsafeMutablePointer<GError>? = nil
    let closeOK = gdk_pixbuf_loader_close(loader, &closeError)
    if let closeError { g_error_free(closeError) }
    guard closeOK != 0 else { return nil }

    guard let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
    _ = g_object_ref(gpointer(pixbuf))
    let formatName = quillImageIOPixbufFormatName(gdk_pixbuf_loader_get_format(loader))
    return (pixbuf, quillImageIOUTType(forPixbufFormat: formatName))
}

private func quillImageIOCGImage(from pixbuf: OpaquePointer, utType: String?) -> CGImage? {
    let width = Int(gdk_pixbuf_get_width(pixbuf))
    let height = Int(gdk_pixbuf_get_height(pixbuf))
    let channels = Int(gdk_pixbuf_get_n_channels(pixbuf))
    let rowStride = Int(gdk_pixbuf_get_rowstride(pixbuf))
    guard
        width > 0,
        height > 0,
        channels >= 3,
        rowStride > 0,
        let pixels = gdk_pixbuf_get_pixels(pixbuf)
    else {
        return nil
    }

    let destinationRowBytes = width * 4
    var bgra = [UInt8](repeating: 0, count: height * destinationRowBytes)
    for y in 0..<height {
        let sourceRow = pixels.advanced(by: y * rowStride)
        let destinationRow = y * destinationRowBytes
        for x in 0..<width {
            let sourcePixel = sourceRow.advanced(by: x * channels)
            let alpha = channels >= 4 ? UInt16(sourcePixel[3]) : 255
            let destination = destinationRow + x * 4
            bgra[destination + 0] = UInt8((UInt16(sourcePixel[2]) * alpha + 127) / 255)
            bgra[destination + 1] = UInt8((UInt16(sourcePixel[1]) * alpha + 127) / 255)
            bgra[destination + 2] = UInt8((UInt16(sourcePixel[0]) * alpha + 127) / 255)
            bgra[destination + 3] = UInt8(alpha)
        }
    }

    let image = CGImage()
    image.width = width
    image.height = height
    image.quillBytesPerRow = destinationRowBytes
    image.quillBGRAPixels = bgra
    image.quillUTType = utType
    return image
}

private func quillImageIOThumbnailPixbuf(_ pixbuf: OpaquePointer, options: Any?) -> OpaquePointer? {
    let width = Int(gdk_pixbuf_get_width(pixbuf))
    let height = Int(gdk_pixbuf_get_height(pixbuf))
    guard width > 0, height > 0 else { return nil }

    let maxPixelSize = quillImageIOIntOption(options, key: kCGImageSourceThumbnailMaxPixelSize)
    guard let maxPixelSize, maxPixelSize > 0, max(width, height) > maxPixelSize else {
        _ = g_object_ref(gpointer(pixbuf))
        return pixbuf
    }

    let scale = Double(maxPixelSize) / Double(max(width, height))
    let targetWidth = max(1, Int((Double(width) * scale).rounded()))
    let targetHeight = max(1, Int((Double(height) * scale).rounded()))
    return gdk_pixbuf_scale_simple(
        pixbuf,
        gint(targetWidth),
        gint(targetHeight),
        GDK_INTERP_BILINEAR
    )
}

private func quillImageIOIntOption(_ options: Any?, key: String) -> Int? {
    if let dict = options as? [String: Any] {
        return quillImageIOIntValue(dict[key])
    }
    if let dict = options as? NSDictionary {
        return quillImageIOIntValue(dict[key])
    }
    return nil
}

private func quillImageIOIntValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int: return value
    case let value as UInt: return Int(value)
    case let value as NSNumber: return value.intValue
    case let value as Double: return Int(value)
    case let value as Float: return Int(value)
    default: return nil
    }
}

private func quillImageIOCopyPixbufDroppingAlpha(_ source: OpaquePointer) -> OpaquePointer? {
    let width = Int(gdk_pixbuf_get_width(source))
    let height = Int(gdk_pixbuf_get_height(source))
    guard width > 0, height > 0 else { return nil }

    guard let destination = gdk_pixbuf_new(GDK_COLORSPACE_RGB, 0, 8, gint(width), gint(height)) else {
        return nil
    }
    guard
        let sourcePixels = gdk_pixbuf_get_pixels(source),
        let destinationPixels = gdk_pixbuf_get_pixels(destination)
    else {
        g_object_unref(gpointer(destination))
        return nil
    }

    let sourceStride = Int(gdk_pixbuf_get_rowstride(source))
    let destinationStride = Int(gdk_pixbuf_get_rowstride(destination))
    let sourceChannels = Int(gdk_pixbuf_get_n_channels(source))
    let destinationChannels = Int(gdk_pixbuf_get_n_channels(destination))
    guard sourceChannels >= 3, destinationChannels >= 3 else {
        g_object_unref(gpointer(destination))
        return nil
    }

    for y in 0..<height {
        let sourceRow = sourcePixels.advanced(by: y * sourceStride)
        let destinationRow = destinationPixels.advanced(by: y * destinationStride)
        for x in 0..<width {
            let sourcePixel = sourceRow.advanced(by: x * sourceChannels)
            let destinationPixel = destinationRow.advanced(by: x * destinationChannels)
            let alpha = sourceChannels >= 4 ? Int(sourcePixel[3]) : 255
            let inverseAlpha = 255 - alpha
            destinationPixel[0] = guchar((Int(sourcePixel[0]) * alpha + 255 * inverseAlpha + 127) / 255)
            destinationPixel[1] = guchar((Int(sourcePixel[1]) * alpha + 255 * inverseAlpha + 127) / 255)
            destinationPixel[2] = guchar((Int(sourcePixel[2]) * alpha + 255 * inverseAlpha + 127) / 255)
        }
    }
    return destination
}

private func quillImageIOPixbuf(from image: CGImage) -> OpaquePointer? {
    let width = image.width
    let height = image.height
    guard
        width > 0,
        height > 0,
        let sourcePixels = image.quillBGRAPixels,
        image.quillBytesPerRow > 0
    else {
        return nil
    }

    guard let pixbuf = gdk_pixbuf_new(GDK_COLORSPACE_RGB, 1, 8, gint(width), gint(height)) else {
        return nil
    }
    guard let destinationPixels = gdk_pixbuf_get_pixels(pixbuf) else {
        g_object_unref(gpointer(pixbuf))
        return nil
    }

    let destinationStride = Int(gdk_pixbuf_get_rowstride(pixbuf))
    for y in 0..<height {
        let destinationRow = destinationPixels.advanced(by: y * destinationStride)
        let sourceRow = y * image.quillBytesPerRow
        for x in 0..<width {
            let source = sourceRow + x * 4
            guard source + 3 < sourcePixels.count else {
                g_object_unref(gpointer(pixbuf))
                return nil
            }
            let alpha = Int(sourcePixels[source + 3])
            let destination = destinationRow.advanced(by: x * 4)
            if alpha > 0 {
                destination[0] = guchar(min(255, Int(sourcePixels[source + 2]) * 255 / alpha))
                destination[1] = guchar(min(255, Int(sourcePixels[source + 1]) * 255 / alpha))
                destination[2] = guchar(min(255, Int(sourcePixels[source + 0]) * 255 / alpha))
            } else {
                destination[0] = 0
                destination[1] = 0
                destination[2] = 0
            }
            destination[3] = guchar(alpha)
        }
    }
    return pixbuf
}

private func quillImageIOEncodePixbuf(_ pixbuf: OpaquePointer, type: String) -> Data? {
    let format = quillImageIOFormatName(for: type)
    guard let format else { return nil }

    var encodedPixbuf = pixbuf
    var ownsEncodedPixbuf = false
    if format == "jpeg", gdk_pixbuf_get_has_alpha(pixbuf) != 0 {
        guard let rgbPixbuf = quillImageIOCopyPixbufDroppingAlpha(pixbuf) else { return nil }
        encodedPixbuf = rgbPixbuf
        ownsEncodedPixbuf = true
    }
    defer {
        if ownsEncodedPixbuf {
            g_object_unref(gpointer(encodedPixbuf))
        }
    }

    var buffer: UnsafeMutablePointer<gchar>? = nil
    var bufferSize: gsize = 0
    var error: UnsafeMutablePointer<GError>? = nil

    let ok = format.withCString { typeCString in
        gdk_pixbuf_save_to_bufferv(
            encodedPixbuf,
            &buffer,
            &bufferSize,
            typeCString,
            nil,
            nil,
            &error
        )
    }
    if let error { g_error_free(error) }
    guard ok != 0, let buffer else { return nil }

    let data = Data(bytes: UnsafeRawPointer(buffer), count: Int(bufferSize))
    g_free(buffer)
    return data
}

private func quillImageIOEncodeImage(_ image: CGImage, type: String) -> Data? {
    guard let pixbuf = quillImageIOPixbuf(from: image) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }
    return quillImageIOEncodePixbuf(pixbuf, type: type)
}

// MARK: - Create / query functions

// Takes `Data` (not `CFData`): swift-corelibs has no Data<->CFData bridge, so
// `someData as CFData` fails at call sites. The
// fetch-patch drops the `as CFData` casts at the SSK call sites.
public func CGImageSourceCreateWithData(_ data: Data, _ options: Any?) -> CGImageSource? {
    _ = options
    guard let decoded = quillImageIODecodePixbuf(from: data) else { return nil }
    g_object_unref(gpointer(decoded.pixbuf))
    return CGImageSource(data: data, typeIdentifier: decoded.utType)
}

public func CGImageSourceCreateWithDataProvider(_ provider: CGDataProvider, _ options: Any?) -> CGImageSource? {
    if let data = provider.data {
        return CGImageSourceCreateWithData(data, options)
    }
    if let url = provider.url {
        return CGImageSourceCreateWithURL(url, options)
    }
    return nil
}

// Takes URL (not CFURL): swift-corelibs has no URL<->CFURL bridge, so callers
// can't write `url as CFURL`; the fetch-patch drops that cast and passes the URL.
public func CGImageSourceCreateWithURL(_ url: URL, _ options: Any?) -> CGImageSource? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let source = CGImageSourceCreateWithData(data, options) else { return nil }
    if source.typeIdentifier == nil {
        return CGImageSource(data: data, typeIdentifier: quillImageIOUTType(forExtension: url.pathExtension))
    }
    return source
}

public func CGImageSourceGetCount(_ isrc: CGImageSource) -> Int {
    _ = isrc
    return 1
}

public func CGImageSourceGetType(_ isrc: CGImageSource) -> String? { isrc.typeIdentifier }

public func CGImageSourceCreateImageAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> CGImage? {
    _ = options
    guard index == 0 else { return nil }
    guard let decoded = quillImageIODecodePixbuf(from: isrc.data) else { return nil }
    defer { g_object_unref(gpointer(decoded.pixbuf)) }
    return quillImageIOCGImage(from: decoded.pixbuf, utType: isrc.typeIdentifier ?? decoded.utType)
}

public func CGImageSourceCreateThumbnailAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> CGImage? {
    guard index == 0 else { return nil }
    guard let decoded = quillImageIODecodePixbuf(from: isrc.data) else { return nil }
    defer { g_object_unref(gpointer(decoded.pixbuf)) }
    guard let thumbnail = quillImageIOThumbnailPixbuf(decoded.pixbuf, options: options) else { return nil }
    defer { g_object_unref(gpointer(thumbnail)) }
    return quillImageIOCGImage(from: thumbnail, utType: isrc.typeIdentifier ?? decoded.utType)
}

// options takes `Any?` (not CFDictionary?) so SSK callers can pass a native
// [String: Any] / [String: Bool] without an `as CFDictionary` bridge (absent on
// swift-corelibs). Returns [String: Any]? (not CFDictionary?) so the callers'
// `as? [String: Any]` / `as? [String: AnyObject]` resolve.
public func CGImageSourceCopyPropertiesAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> [String: Any]? {
    _ = options
    guard let image = CGImageSourceCreateImageAtIndex(isrc, index, nil) else { return nil }
    return [
        kCGImagePropertyPixelWidth: image.width,
        kCGImagePropertyPixelHeight: image.height,
        kCGImagePropertyHasAlpha: true,
        kCGImagePropertyDepth: 8,
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
        kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue,
    ]
}

public func CGImageSourceCopyMetadataAtIndex(_ isrc: CGImageSource, _ index: Int, _ options: Any?) -> CGImageMetadata? { nil }

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
public let kCGImageSourceShouldCacheImmediately: String = "kCGImageSourceShouldCacheImmediately"
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

public let kCGImageMetadataPrefixTIFF: String = "tiff"
public let kCGImagePropertyTIFFOrientation: String = "Orientation"
public let kCGImageMetadataPrefixIPTCCore: String = "iptcCore"
public let kCGImagePropertyIPTCImageOrientation: String = "ImageOrientation"
public let kCGImageMetadataEnumerateRecursively: String = "kCGImageMetadataEnumerateRecursively"

public let kCFNull: String = "kCFNull"

// MARK: - CGImageMetadata

public func CGImageMetadataCreateMutable() -> CGMutableImageMetadata {
    CGImageMetadata()
}

@discardableResult
public func CGImageMetadataEnumerateTagsUsingBlock(
    _ metadata: CGImageMetadata,
    _ rootPath: String?,
    _ options: Any?,
    _ block: (String, CGImageMetadataTag) -> Bool
) -> Bool {
    _ = (metadata, rootPath, options, block)
    return true
}

public func CGImageMetadataTagCopyNamespace(_ tag: CGImageMetadataTag) -> String? {
    _ = tag
    return nil
}

public func CGImageMetadataTagCopyPrefix(_ tag: CGImageMetadataTag) -> String? {
    _ = tag
    return nil
}

public func CGImageMetadataRegisterNamespaceForPrefix(
    _ metadata: CGMutableImageMetadata,
    _ xmlns: String,
    _ prefix: String,
    _ error: Any?
) -> Bool {
    _ = (metadata, xmlns, prefix, error)
    return true
}

public func CGImageMetadataSetValueWithPath(
    _ metadata: CGMutableImageMetadata,
    _ parent: String?,
    _ path: String,
    _ value: Any?
) -> Bool {
    _ = (metadata, parent, path, value)
    return true
}

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
// MARK: - CGImageDestination (image writing)
//
// IceCubes and SignalServiceKit both use destination writers for upload and
// generated image paths. The Linux shim writes the first queued CGImage through
// gdk-pixbuf for PNG/JPEG/TIFF data or files. Like CGImageSourceCreateWithURL,
// the URL create function takes URL (not CFURL): swift-corelibs has no
// URL<->CFURL bridge, so source-lowering drops `as CFURL` at call sites.

public class CGImageDestination {
    fileprivate enum Sink {
        case data(NSMutableData)
        case url(URL)
    }

    fileprivate let sink: Sink
    fileprivate let type: String
    fileprivate var images: [(image: CGImage, properties: Any?)] = []

    fileprivate init(sink: Sink, type: String) {
        self.sink = sink
        self.type = type
    }
}

// `type` is the UTI string (e.g. "public.png"). Apple's signature is CFString, but
// swift-corelibs has no String<->CFString bridge so the upstream `UTType.png.identifier
// as CFString` cast can't compile; the shim takes String and the fetch-patch drops the
// cast.
public func CGImageDestinationCreateWithURL(
    _ url: URL,
    _ type: String,
    _ count: Int,
    _ options: Any?
) -> CGImageDestination? {
    _ = (count, options)
    guard quillImageIOFormatName(for: type) != nil else { return nil }
    return CGImageDestination(sink: .url(url), type: type)
}

public func CGImageDestinationCreateWithData(
    _ data: NSMutableData,
    _ type: String,
    _ count: Int,
    _ options: Any?
) -> CGImageDestination? {
    _ = (count, options)
    guard quillImageIOFormatName(for: type) != nil else { return nil }
    return CGImageDestination(sink: .data(data), type: type)
}

public func CGImageDestinationAddImage(
    _ idst: CGImageDestination,
    _ image: CGImage,
    _ properties: Any?
) {
    idst.images.append((image, properties))
}

public let kCGImageDestinationLossyCompressionQuality: String = "kCGImageDestinationLossyCompressionQuality"
public let kCGImageDestinationMergeMetadata: String = "kCGImageDestinationMergeMetadata"
public let kCGImageDestinationMetadata: String = "kCGImageDestinationMetadata"

@discardableResult
public func CGImageDestinationFinalize(_ idst: CGImageDestination) -> Bool {
    guard let first = idst.images.first else { return false }
    guard let encoded = quillImageIOEncodeImage(first.image, type: idst.type) else { return false }

    switch idst.sink {
    case .data(let data):
        data.setData(encoded)
        return true
    case .url(let url):
        do {
            try encoded.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

@discardableResult
public func CGImageDestinationCopyImageSource(
    _ idst: CGImageDestination,
    _ isrc: CGImageSource,
    _ options: Any?,
    _ error: Any?
) -> Bool {
    _ = error
    guard let image = CGImageSourceCreateImageAtIndex(isrc, 0, options) else { return false }
    CGImageDestinationAddImage(idst, image, nil)
    return CGImageDestinationFinalize(idst)
}
