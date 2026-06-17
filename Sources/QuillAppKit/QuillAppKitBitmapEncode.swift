#if os(Linux)
import Foundation
@_implementationOnly import CGdkPixbuf

// Real raster encoding for NSBitmapImageRep (rung 4 of the SolderScope
// ladder): BGRA pixels (camera/snapshot path) or already-encoded container
// bytes (Enchanted's NSImage->JPEG path) go through gdk-pixbuf and come back
// as real PNG/JPEG/TIFF/BMP files. Mirrors QuillUI's GdkPixbufTranscode
// pattern; lives in QuillAppKit because NSBitmapImageRep is AppKit surface
// and QuillUI depends the other way.

enum QuillBitmapEncodeFormat: String {
    case png
    case jpeg
    case tiff
    case bmp
}

/// Build an 8-bit RGBA pixbuf from tightly-or-loosely packed BGRA rows.
private func quillPixbufFromBGRA(
    _ bgra: Data, width: Int, height: Int, bytesPerRow: Int
) -> OpaquePointer? {
    guard width > 0, height > 0, bytesPerRow >= width * 4,
          bgra.count >= bytesPerRow * (height - 1) + width * 4 else { return nil }
    guard let pixbuf = gdk_pixbuf_new(
        GDK_COLORSPACE_RGB, /*has_alpha:*/ 1, 8, gint(width), gint(height)
    ) else { return nil }
    guard let destination = gdk_pixbuf_get_pixels(pixbuf) else {
        g_object_unref(gpointer(pixbuf))
        return nil
    }
    let destinationStride = Int(gdk_pixbuf_get_rowstride(pixbuf))
    bgra.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let base = raw.baseAddress else { return }
        for y in 0..<height {
            let sourceRow = base.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            let destinationRow = destination.advanced(by: y * destinationStride)
            for x in 0..<width {
                let s = sourceRow.advanced(by: x * 4)
                let d = destinationRow.advanced(by: x * 4)
                // BGRA bytes are [b,g,r,a]; pixbuf wants [r,g,b,a].
                d[0] = s[2]
                d[1] = s[1]
                d[2] = s[0]
                d[3] = s[3]
            }
        }
    }
    return pixbuf
}

/// Decode arbitrary container bytes (PNG/JPEG/TIFF/...) into a pixbuf.
private func quillDecodePixbufFromData(_ source: Data) -> OpaquePointer? {
    guard let loader = gdk_pixbuf_loader_new() else { return nil }
    defer { g_object_unref(gpointer(loader)) }
    var ok = source.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
        guard let bytes = raw.bindMemory(to: guchar.self).baseAddress else { return false }
        var error: UnsafeMutablePointer<GError>? = nil
        let wrote = gdk_pixbuf_loader_write(loader, bytes, gsize(raw.count), &error)
        if let error { g_error_free(error) }
        return wrote != 0
    }
    var closeError: UnsafeMutablePointer<GError>? = nil
    let closed = gdk_pixbuf_loader_close(loader, &closeError)
    if let closeError { g_error_free(closeError) }
    ok = ok && closed != 0
    guard ok, let pixbuf = gdk_pixbuf_loader_get_pixbuf(loader) else { return nil }
    // The loader owns its pixbuf; retain so it survives the loader's unref.
    g_object_ref(gpointer(pixbuf))
    return pixbuf
}

/// JPEG can't carry alpha — composite over white exactly as QuillUI's
/// transcoder (and Apple's JPEG writer) does.
private func quillFlattenAlphaOverWhite(_ source: OpaquePointer) -> OpaquePointer? {
    let width = Int(gdk_pixbuf_get_width(source))
    let height = Int(gdk_pixbuf_get_height(source))
    guard width > 0, height > 0,
          let destination = gdk_pixbuf_new(GDK_COLORSPACE_RGB, 0, 8, gint(width), gint(height)),
          let sourcePixels = gdk_pixbuf_get_pixels(source),
          let destinationPixels = gdk_pixbuf_get_pixels(destination)
    else { return nil }
    let sourceStride = Int(gdk_pixbuf_get_rowstride(source))
    let destinationStride = Int(gdk_pixbuf_get_rowstride(destination))
    let sourceChannels = Int(gdk_pixbuf_get_n_channels(source))
    for y in 0..<height {
        let sRow = sourcePixels.advanced(by: y * sourceStride)
        let dRow = destinationPixels.advanced(by: y * destinationStride)
        for x in 0..<width {
            let s = sRow.advanced(by: x * sourceChannels)
            let d = dRow.advanced(by: x * 3)
            let alpha = sourceChannels >= 4 ? Int(s[3]) : 255
            let inverse = 255 - alpha
            d[0] = guchar((Int(s[0]) * alpha + 255 * inverse + 127) / 255)
            d[1] = guchar((Int(s[1]) * alpha + 255 * inverse + 127) / 255)
            d[2] = guchar((Int(s[2]) * alpha + 255 * inverse + 127) / 255)
        }
    }
    return destination
}

/// gdk_pixbuf_save_to_bufferv with NULL-terminated option arrays
/// (e.g. JPEG "quality", TIFF "compression").
private func quillSavePixbuf(
    _ pixbuf: OpaquePointer,
    format: QuillBitmapEncodeFormat,
    options: [(key: String, value: String)]
) -> Data? {
    var encodePixbuf = pixbuf
    var ownsEncodePixbuf = false
    if format == .jpeg, gdk_pixbuf_get_has_alpha(pixbuf) != 0 {
        guard let flattened = quillFlattenAlphaOverWhite(pixbuf) else { return nil }
        encodePixbuf = flattened
        ownsEncodePixbuf = true
    }
    defer { if ownsEncodePixbuf { g_object_unref(gpointer(encodePixbuf)) } }

    var keyPointers: [UnsafeMutablePointer<gchar>?] = options.map { strdup($0.key) }
    var valuePointers: [UnsafeMutablePointer<gchar>?] = options.map { strdup($0.value) }
    keyPointers.append(nil)
    valuePointers.append(nil)
    defer {
        keyPointers.compactMap { $0 }.forEach { free($0) }
        valuePointers.compactMap { $0 }.forEach { free($0) }
    }

    var buffer: UnsafeMutablePointer<gchar>? = nil
    var bufferSize: gsize = 0
    var error: UnsafeMutablePointer<GError>? = nil
    let saved = format.rawValue.withCString { typeCString in
        keyPointers.withUnsafeMutableBufferPointer { keys in
            valuePointers.withUnsafeMutableBufferPointer { values in
                gdk_pixbuf_save_to_bufferv(
                    encodePixbuf, &buffer, &bufferSize, typeCString,
                    keys.baseAddress, values.baseAddress, &error
                )
            }
        }
    }
    if let error { g_error_free(error) }
    guard saved != 0, let buffer else { return nil }
    let result = Data(bytes: UnsafeRawPointer(buffer), count: Int(bufferSize))
    g_free(buffer)
    return result
}

/// Encode raw BGRA pixels into a real image container.
func quillEncodeBGRAPixels(
    _ bgra: Data, width: Int, height: Int, bytesPerRow: Int,
    format: QuillBitmapEncodeFormat,
    options: [(key: String, value: String)] = []
) -> Data? {
    guard let pixbuf = quillPixbufFromBGRA(
        bgra, width: width, height: height, bytesPerRow: bytesPerRow
    ) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }
    return quillSavePixbuf(pixbuf, format: format, options: options)
}

/// Transcode already-encoded container bytes into the requested format.
func quillTranscodeEncodedImageData(
    _ source: Data,
    format: QuillBitmapEncodeFormat,
    options: [(key: String, value: String)] = []
) -> Data? {
    guard let pixbuf = quillDecodePixbufFromData(source) else { return nil }
    defer { g_object_unref(gpointer(pixbuf)) }
    return quillSavePixbuf(pixbuf, format: format, options: options)
}
#endif
