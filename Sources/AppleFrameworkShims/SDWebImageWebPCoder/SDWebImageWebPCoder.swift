//
// QuillUI Linux shim for `SDWebImageWebPCoder` (the WebP coder plugin).
//
// SignalServiceKit encodes attachment thumbnails to WebP via SDImageWebPCoder.
// There's no libwebp-backed coder on Linux, so this is INERT: `encodedData`
// returns nil (the caller throws / falls back), and the shared coders register
// as no-ops. SDImageFormat / SDImageCoderOption are declared here (not in the
// SDWebImage core shim) because the only consumer that names them
// (AttachmentThumbnailServiceImpl) imports just `SDWebImageWebPCoder`. HONEST
// STATUS: WebP thumbnails are not produced on Linux.
//
import Foundation
import QuillFoundation  // UIImage (encodedData input)

public enum SDImageFormat: Int, Sendable {
    case undefined = -1
    case JPEG = 0
    case PNG
    case GIF
    case TIFF
    case webP
    case HEIC
    case HEIF
    case PDF
    case SVG
    case BMP
}

public struct SDImageCoderOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let encodeWebPMethod = SDImageCoderOption(rawValue: "encodeWebPMethod")
    public static let encodeMaxFileSize = SDImageCoderOption(rawValue: "encodeMaxFileSize")
    public static let encodeMaxPixelSize = SDImageCoderOption(rawValue: "encodeMaxPixelSize")
    public static let encodeCompressionQuality = SDImageCoderOption(rawValue: "encodeCompressionQuality")
    public static let decodeScaleFactor = SDImageCoderOption(rawValue: "decodeScaleFactor")
    public static let encodeFirstFrameOnly = SDImageCoderOption(rawValue: "encodeFirstFrameOnly")
}

public final class SDImageWebPCoder: @unchecked Sendable {
    public static let shared = SDImageWebPCoder()
    public init() {}
    /// Inert: no WebP encoder on Linux -> returns nil (caller throws/falls back).
    public func encodedData(
        with image: UIImage?,
        format: SDImageFormat,
        options: [SDImageCoderOption: Any]?
    ) -> Data? {
        nil
    }
}

/// The ImageIO-backed Apple WebP coder (registered alongside the libwebp one on
/// Apple). Inert here too.
public final class SDImageAWebPCoder: @unchecked Sendable {
    public static let shared = SDImageAWebPCoder()
    public init() {}
    public func encodedData(
        with image: UIImage?,
        format: SDImageFormat,
        options: [SDImageCoderOption: Any]?
    ) -> Data? {
        nil
    }
}
