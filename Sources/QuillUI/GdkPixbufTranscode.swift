// Linux-only: GdkPixbuf-backed image format transcoding.
//
// Real Apple AppKit's `NSImage(data:).tiffRepresentation` decodes the source
// image (PNG/JPEG/GIF/etc.) into pixel data and re-encodes it as TIFF. To
// match that behavior on Linux we route arbitrary input bytes through
// gdk-pixbuf, which is the standard image codec in the GTK ecosystem and is
// already pulled in transitively by libgtk-4-dev (a hard dependency of
// SwiftOpenUI's GTK backend).
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
    case png
    case tiff
}

/// Synthesize a solid-color image at the given size and encode it via
/// gdk-pixbuf in the requested container format.
///
/// This is the Linux backing for the subset of `ImageRenderer` we currently
/// support: when `ImageRenderer.content` is a `Color`, we extract the RGBA
/// components and render a real-pixels image at the requested size. More
/// complex SwiftUI views still require offscreen GTK rasterization that is
/// not yet wired up; see the TODO on `ImageRenderer`.
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

    // Encode.
    var buffer: UnsafeMutablePointer<gchar>? = nil
    var bufferSize: gsize = 0
    var error: UnsafeMutablePointer<GError>? = nil
    let saveOK = format.rawValue.withCString { typeCString -> Int32 in
        gdk_pixbuf_save_to_bufferv(
            pixbuf,
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

/// Transcode arbitrary image bytes (PNG/JPEG/GIF/BMP/TIFF/WebP/etc.) into
/// TIFF. Returns nil if the bytes don't decode as a recognized image, mirroring
/// Apple's `NSImage(data:).tiffRepresentation` failure semantics.
///
/// The receiving Data is treated as a complete in-memory image; gdk-pixbuf's
/// loader writes happen in a single pass with no buffering on the caller side.
@_spi(QuillTesting)
public func quillTranscodeImageDataToTIFF(_ source: Data) -> Data? {
    guard !source.isEmpty else { return nil }

    // Decode: feed bytes into a GdkPixbufLoader, then close it to commit.
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

    // The pixbuf is owned by the loader and remains valid until the loader is
    // unref'd at function exit.
    guard let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }

    // Encode: ask gdk-pixbuf to save the pixbuf to a heap-allocated buffer in
    // TIFF format. Use the non-variadic `_save_to_bufferv` because Swift
    // can't call C variadic functions directly. Pass nil/nil for option
    // keys/values; defaults are fine for parity.
    var buffer: UnsafeMutablePointer<gchar>? = nil
    var bufferSize: gsize = 0
    var saveError: UnsafeMutablePointer<GError>? = nil

    let saveOK = "tiff".withCString { typeCString -> Int32 in
        gdk_pixbuf_save_to_bufferv(
            pixbuf,
            &buffer,
            &bufferSize,
            typeCString,
            nil,
            nil,
            &saveError
        )
    }
    if let saveError {
        g_error_free(saveError)
    }
    guard saveOK != 0, let buffer else { return nil }

    // Copy into a Swift-owned Data and free the gdk-pixbuf-allocated buffer.
    let result = Data(bytes: UnsafeRawPointer(buffer), count: Int(bufferSize))
    g_free(buffer)
    return result
}
#else
import Foundation

@_spi(QuillTesting)
public enum QuillEncodedImageFormat: String, Sendable {
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
#endif
