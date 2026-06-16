import Foundation

#if os(Linux)
import CGdkPixbuf
#endif

public enum QuillBitmapImageCodec {
    public static func utType(forPathExtension pathExtension: String) -> String? {
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

    public static func formatName(for type: String?) -> String? {
        switch type?.lowercased() {
        case "public.jpeg", "jpeg", "jpg", "image/jpeg": return "jpeg"
        case "public.png", "png", "image/png": return "png"
        case "public.tiff", "tiff", "tif", "image/tiff": return "tiff"
        default: return nil
        }
    }

    public static func decode(_ data: Data, preferredUTType: String? = nil) -> CGImage? {
        decodeWithType(data, preferredUTType: preferredUTType)?.image
    }

    public static func decodeWithType(
        _ data: Data,
        preferredUTType: String? = nil
    ) -> (image: CGImage, utType: String?)? {
        #if os(Linux)
        guard let decoded = decodePixbuf(from: data) else { return nil }
        defer { g_object_unref(gpointer(decoded.pixbuf)) }
        guard let image = cgImage(from: decoded.pixbuf, utType: preferredUTType ?? decoded.utType) else {
            return nil
        }
        return (image, image.quillUTType)
        #else
        _ = (data, preferredUTType)
        return nil
        #endif
    }

    public static func thumbnail(
        from data: Data,
        maxPixelSize: Int,
        preferredUTType: String? = nil
    ) -> CGImage? {
        #if os(Linux)
        guard let decoded = decodePixbuf(from: data) else { return nil }
        defer { g_object_unref(gpointer(decoded.pixbuf)) }
        let width = Int(gdk_pixbuf_get_width(decoded.pixbuf))
        let height = Int(gdk_pixbuf_get_height(decoded.pixbuf))
        guard width > 0, height > 0 else { return nil }
        let sourceType = preferredUTType ?? decoded.utType

        guard maxPixelSize > 0, max(width, height) > maxPixelSize else {
            return cgImage(from: decoded.pixbuf, utType: sourceType)
        }

        let scale = Double(maxPixelSize) / Double(max(width, height))
        let targetWidth = max(1, Int((Double(width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(height) * scale).rounded()))
        guard let scaled = gdk_pixbuf_scale_simple(
            decoded.pixbuf,
            gint(targetWidth),
            gint(targetHeight),
            GDK_INTERP_BILINEAR
        ) else {
            return nil
        }
        defer { g_object_unref(gpointer(scaled)) }
        return cgImage(from: scaled, utType: sourceType)
        #else
        _ = (data, maxPixelSize, preferredUTType)
        return nil
        #endif
    }

    public static func encode(
        _ image: CGImage,
        type: String,
        compressionQuality: CGFloat? = nil
    ) -> Data? {
        #if os(Linux)
        guard let pixbuf = pixbuf(from: image) else { return nil }
        defer { g_object_unref(gpointer(pixbuf)) }
        return encodePixbuf(pixbuf, type: type, compressionQuality: compressionQuality)
        #else
        _ = (image, type, compressionQuality)
        return nil
        #endif
    }

    public static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        #if os(Linux)
        let targetWidth = max(1, Int(size.width.rounded()))
        let targetHeight = max(1, Int(size.height.rounded()))
        guard let pixbuf = pixbuf(from: image) else { return nil }
        defer { g_object_unref(gpointer(pixbuf)) }
        guard let scaled = gdk_pixbuf_scale_simple(
            pixbuf,
            gint(targetWidth),
            gint(targetHeight),
            GDK_INTERP_BILINEAR
        ) else {
            return nil
        }
        defer { g_object_unref(gpointer(scaled)) }
        return cgImage(from: scaled, utType: image.quillUTType)
        #else
        _ = (image, size)
        return nil
        #endif
    }
}

#if os(Linux)
private extension QuillBitmapImageCodec {
    static func utType(forPixbufFormat name: String?) -> String? {
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

    static func pixbufFormatName(_ format: OpaquePointer?) -> String? {
        guard let format else { return nil }
        guard let rawName = gdk_pixbuf_format_get_name(format) else { return nil }
        defer { g_free(rawName) }
        return String(cString: rawName)
    }

    static func decodePixbuf(from source: Data) -> (pixbuf: OpaquePointer, utType: String?)? {
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
        let formatName = pixbufFormatName(gdk_pixbuf_loader_get_format(loader))
        return (pixbuf, utType(forPixbufFormat: formatName))
    }

    static func cgImage(from pixbuf: OpaquePointer, utType: String?) -> CGImage? {
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

    static func copyPixbufDroppingAlpha(_ source: OpaquePointer) -> OpaquePointer? {
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

    static func pixbuf(from image: CGImage) -> OpaquePointer? {
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

    static func encodePixbuf(_ pixbuf: OpaquePointer, type: String, compressionQuality: CGFloat?) -> Data? {
        let format = formatName(for: type)
        guard let format else { return nil }
        _ = compressionQuality

        var encodedPixbuf = pixbuf
        var ownsEncodedPixbuf = false
        if format == "jpeg", gdk_pixbuf_get_has_alpha(pixbuf) != 0 {
            guard let rgbPixbuf = copyPixbufDroppingAlpha(pixbuf) else { return nil }
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
}
#endif
