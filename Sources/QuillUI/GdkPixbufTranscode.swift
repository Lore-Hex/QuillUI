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
    defer { g_object_unref(loader) }

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
public func quillTranscodeImageDataToTIFF(_ source: Data) -> Data? {
    nil
}
#endif
