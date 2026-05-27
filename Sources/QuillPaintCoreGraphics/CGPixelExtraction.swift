import Foundation
import QuillPaint

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO

/// CG-side helpers for feeding `PixelComparator`: extract raw RGBA bytes
/// from a `CGImage` and load a PNG from disk into a `CGImage`.
///
/// These live in QuillPaintCoreGraphics (not QuillPaint) because they
/// require ImageIO + CoreGraphics, which are Apple-only. The
/// `PixelComparator` itself is Foundation-only and works on any platform.
public enum CGPixelExtraction {
    public enum Error: Swift.Error, CustomStringConvertible {
        case decodeFailed
        case contextCreationFailed

        public var description: String {
            switch self {
            case .decodeFailed: return "Failed to decode image from URL."
            case .contextCreationFailed: return "Failed to create RGBA bitmap context."
            }
        }
    }

    /// Decode a PNG (or any ImageIO-supported format) into a `CGImage`.
    public static func loadImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Error.decodeFailed
        }
        return image
    }

    /// Re-rasterize a `CGImage` into a packed RGBA8 byte buffer with
    /// premultiplied alpha and the requested dimensions. Suitable for
    /// feeding into `PixelComparator.compare`.
    public static func rawRGBA(from image: CGImage) throws -> Data {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw Error.contextCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Data(bytes)
    }
}

#endif
