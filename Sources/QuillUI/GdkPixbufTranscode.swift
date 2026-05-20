// Linux-only: GdkPixbuf-backed image format transcoding.
//
// Real Apple AppKit image helpers decode the source image (PNG/JPEG/GIF/etc.)
// into pixel data before transcoding, scaling, or recompressing. To match that
// behavior on Linux we route arbitrary input bytes through gdk-pixbuf, which is
// the standard image codec in the GTK ecosystem and is already pulled in
// transitively by libgtk-4-dev (a hard dependency of SwiftOpenUI's GTK backend).
//
// This file is intentionally tiny and dependency-free aside from CGdkPixbuf
// and Foundation so the parity work can land without touching the rest of
// QuillUI.

#if os(Linux)
import Foundation
import CGdkPixbuf

/// Output container format requested when rendering a synthesized image
/// through gdk-pixbuf.
@_spi(QuillTesting)
public enum QuillEncodedImageFormat: String, Sendable {
    case jpeg
    case png
    case tiff
}

private func quillDecodePixbuf(from source: Data) -> OpaquePointer? {
    guard !source.isEmpty else { return nil }

    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(gpointer(loader)) }

    let writeOK = source.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        guard let base = raw.baseAddress else { return false }
        let bytes = base.assumingMemoryBound(to: guchar.self)
        var error: UnsafeMutablePointer<GError>? = nil
        let ok = gdk_pixbuf_loader_write(loader, bytes, gsize(raw.count), &error)
        if let error {
            g_error_free(error)
        }
        return ok != 0
    }
    guard writeOK else { return nil }

    var closeError: UnsafeMutablePointer<GError>? = nil
    let closeOK = gdk_pixbuf_loader_close(loader, &closeError)
    if let closeError {
        g_error_free(closeError)
    }
    guard closeOK != 0 else { return nil }

    guard let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
    _ = g_object_ref(gpointer(pixbuf))
    return pixbuf
}

private func quillCompositeOverWhite(_ component: guchar, alpha: Int) -> guchar {
    let inverseAlpha = 255 - alpha
    let blended = (Int(component) * alpha + 255 * inverseAlpha + 127) / 255
    return guchar(blended)
}

private func quillCopyPixbufDroppingAlpha(_ source: OpaquePointer) -> OpaquePointer? {
    let width = Int(gdk_pixbuf_get_width(source))
    let height = Int(gdk_pixbuf_get_height(source))
    guard width > 0, height > 0 else { return nil }

    guard let destination = gdk_pixbuf_new(
        GDK_COLORSPACE_RGB,
        /*has_alpha:*/ 0,
        8,
        gint(width),
        gint(height)
    ) else {
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
            destinationPixel[0] = quillCompositeOverWhite(sourcePixel[0], alpha: alpha)
            destinationPixel[1] = quillCompositeOverWhite(sourcePixel[1], alpha: alpha)
            destinationPixel[2] = quillCompositeOverWhite(sourcePixel[2], alpha: alpha)
        }
    }

    return destination
}

private func quillEncodePixbuf(
    _ pixbuf: OpaquePointer,
    as format: QuillEncodedImageFormat
) -> Data? {
    var encodedPixbuf = pixbuf
    var ownsEncodedPixbuf = false

    if case .jpeg = format, gdk_pixbuf_get_has_alpha(pixbuf) != 0 {
        guard let rgbPixbuf = quillCopyPixbufDroppingAlpha(pixbuf) else { return nil }
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

    let saveOK = format.rawValue.withCString { typeCString -> Int32 in
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
    if let error {
        g_error_free(error)
    }
    guard saveOK != 0, let buffer else { return nil }

    let result = Data(bytes: UnsafeRawPointer(buffer), count: Int(bufferSize))
    g_free(buffer)
    return result
}

/// Synthesize a solid-color image at the given size and encode it via
/// gdk-pixbuf in the requested container format.
///
/// This is the Linux backing for the subset of `ImageRenderer` we currently
/// support: when `ImageRenderer.content` is a `Color`, we extract the RGBA
/// components and render a real-pixels image at the requested size. More
/// complex SwiftUI view trees use the opt-in GTK offscreen rasterizer gated
/// by `QUILLUI_ENABLE_GTK_OFFSCREEN_RENDER=1`.
///
/// Returns `nil` if `width` or `height` is non-positive, if `gdk_pixbuf_new`
/// fails (low memory, hostile dimensions), or if the encoder fails. Each
/// failure path frees any GError it produces.
@_spi(QuillTesting)
public func quillRenderSolidColorImage(
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double,
    width: Int,
    height: Int,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    guard width > 0, height > 0 else { return nil }

    // 8-bit RGBA pixbuf. has_alpha = TRUE so the gdk_pixbuf_fill RGBA
    // packing is honored and we get a proper 4-channel image.
    guard let pixbuf = gdk_pixbuf_new(
        GDK_COLORSPACE_RGB,
        /*has_alpha:*/ 1,
        8,
        gint(width),
        gint(height)
    ) else {
        return nil
    }
    defer { g_object_unref(gpointer(pixbuf)) }

    // gdk_pixbuf_fill takes an RGBA quad packed as 0xRRGGBBAA in the
    // pixbuf's native byte order.
    func clamp(_ v: Double) -> UInt32 {
        UInt32(max(0, min(255, Int((v * 255.0).rounded()))))
    }
    let r = clamp(red)
    let g = clamp(green)
    let b = clamp(blue)
    let a = clamp(alpha)
    let rgba: UInt32 = (r << 24) | (g << 16) | (b << 8) | a
    gdk_pixbuf_fill(pixbuf, guint32(rgba))

    return quillEncodePixbuf(pixbuf, as: format)
}

/// Transcode arbitrary image bytes (PNG/JPEG/GIF/BMP/TIFF/WebP/etc.) into
/// TIFF. Returns nil if the bytes don't decode as a recognized image, mirroring
/// Apple's `NSImage(data:).tiffRepresentation` failure semantics.
///
/// The receiving Data is treated as a complete in-memory image; gdk-pixbuf's
/// loader writes happen in a single pass with no buffering on the caller side.
@_spi(QuillTesting)
public func quillTranscodeImageDataToTIFF(_ source: Data) -> Data? {
    guard let pixbuf = quillDecodePixbuf(from: source) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }
    return quillEncodePixbuf(pixbuf, as: .tiff)
}

@_spi(QuillTesting)
public func quillScaleImageDataToHeight(
    _ source: Data,
    height targetHeight: Int,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    guard targetHeight > 0 else { return nil }
    guard let pixbuf = quillDecodePixbuf(from: source) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }

    let originalWidth = Int(gdk_pixbuf_get_width(pixbuf))
    let originalHeight = Int(gdk_pixbuf_get_height(pixbuf))
    guard originalWidth > 0, originalHeight > 0 else { return nil }

    let scaledWidth = max(1, Int((Double(originalWidth) * Double(targetHeight) / Double(originalHeight)).rounded()))
    guard let scaled = gdk_pixbuf_scale_simple(
        pixbuf,
        gint(scaledWidth),
        gint(targetHeight),
        GDK_INTERP_BILINEAR
    ) else {
        return nil
    }
    defer { g_object_unref(gpointer(scaled)) }

    return quillEncodePixbuf(scaled, as: format)
}

@_spi(QuillTesting)
public func quillCompressImageDataToJPEG(_ source: Data) -> Data? {
    guard let pixbuf = quillDecodePixbuf(from: source) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }
    return quillEncodePixbuf(pixbuf, as: .jpeg)
}
#else
import Foundation

@_spi(QuillTesting)
public enum QuillEncodedImageFormat: String, Sendable {
    case jpeg
    case png
    case tiff
}

@_spi(QuillTesting)
public func quillRenderSolidColorImage(
    red: Double,
    green: Double,
    blue: Double,
    alpha: Double,
    width: Int,
    height: Int,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    nil
}

@_spi(QuillTesting)
public func quillTranscodeImageDataToTIFF(_ source: Data) -> Data? {
    nil
}

@_spi(QuillTesting)
public func quillScaleImageDataToHeight(
    _ source: Data,
    height targetHeight: Int,
    format: QuillEncodedImageFormat = .png
) -> Data? {
    nil
}

@_spi(QuillTesting)
public func quillCompressImageDataToJPEG(_ source: Data) -> Data? {
    nil
}
#endif
