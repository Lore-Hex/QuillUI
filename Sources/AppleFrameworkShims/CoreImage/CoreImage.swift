//
// QuillUI Linux shim for `CoreImage` — placeholder so `import CoreImage` resolves on
// Linux. Concrete symbols are added as SignalServiceKit references surface
// (behavior deferred). Part of the Signal-iOS -> QuillOS port.
//
import Foundation
import QuillFoundation
import CoreVideo

// MARK: - CIImage / CIFilter / CIContext
//
// SignalServiceKit's CombinedFingerprints renders the safety-number QR via
// `CIFilter(name: "CIQRCodeGenerator")` -> outputImage -> CIContext.createCGImage.
// There is no Core Image pipeline on Linux, so this is INERT: the filter constructs
// but produces no output image, and createCGImage returns nil, so the upstream
// `guard let` chain bails and `buildQRImage()` returns nil. HONEST STATUS: the
// safety-number QR code is not generated on Linux yet (a real QR encoder would be
// needed). The type surface exists only so the upstream Swift compiles.

/// Pixel format for CIImage bitmap construction (Apple: a Int32 raw struct).
public struct CIFormat: RawRepresentable, Equatable, Hashable, Sendable {
    public var rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let BGRA8 = CIFormat(rawValue: 1)
    public static let RGBA8 = CIFormat(rawValue: 2)
    public static let ARGB8 = CIFormat(rawValue: 3)
    public static let RGBA16 = CIFormat(rawValue: 4)
}

open class CIImage {
    /// Real BGRA backing when constructed from a pixel buffer or bitmap data
    /// (the camera frame pipeline: CVPixelBuffer → CIImage →
    /// CIContext.createCGImage → CGContext.draw). nil = the historical inert
    /// placeholder.
    public internal(set) var quillBGRAPixels: [UInt8]?
    public internal(set) var quillBytesPerRow: Int = 0
    public internal(set) var quillSize: CGSize = .zero

    public init() {}

    /// Wrap a CoreVideo pixel buffer (BGRA after capture-side conversion).
    /// Copies the bytes — the buffer may be recycled into the capture ring.
    public init(cvPixelBuffer pixelBuffer: CVPixelBuffer) {
        let width = pixelBuffer.width
        let height = pixelBuffer.height
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        self.quillBGRAPixels = pixelBuffer.quillWithReadOnlyBytes { raw in
            Array(raw.prefix(bytesPerRow * height))
        }
        self.quillBytesPerRow = bytesPerRow
        self.quillSize = CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    /// Construct from raw bitmap bytes (FrameProcessor's frame-integration
    /// output path). Only .BGRA8 carries pixels; other formats keep the
    /// placeholder semantics.
    public init(bitmapData data: Data, bytesPerRow: Int, size: CGSize,
                format: CIFormat, colorSpace: CGColorSpace?) {
        _ = colorSpace
        if format == .BGRA8 {
            self.quillBGRAPixels = [UInt8](data)
            self.quillBytesPerRow = bytesPerRow
            self.quillSize = size
        }
    }

    /// The image's bounds — real when pixel-backed.
    open var extent: CGRect {
        CGRect(origin: .zero, size: quillSize)
    }
}

open class CIColor {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public convenience init(color: RSColor) {
        self.init(red: color._red, green: color._green, blue: color._blue, alpha: color._alpha)
    }

    public convenience init(cgColor: CGColor) {
        let components = cgColor.components ?? [0, 0, 0, 1]
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if components.count == 2 {
            red = components[0]
            green = components[0]
            blue = components[0]
            alpha = components[1]
        } else {
            red = components.indices.contains(0) ? components[0] : 0
            green = components.indices.contains(1) ? components[1] : red
            blue = components.indices.contains(2) ? components[2] : red
            alpha = components.indices.contains(3) ? components[3] : 1
        }
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

open class CIFilter {
    /// `CIFilter(name:)` is failable on Apple. Here it succeeds (so the caller's guard
    /// passes) but the filter has no Core Image backend, so `outputImage` is nil.
    public init?(name: String) {}
    public init() {}

    open func setDefaults() {}
    open func setValue(_ value: Any?, forKey key: String) {}

    /// No rendering backend -> no output image.
    open var outputImage: CIImage? { nil }
}

public struct CIVector: Sendable {
    public var x: CGFloat
    public var y: CGFloat
    public var z: CGFloat
    public var w: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
        self.z = 0
        self.w = 0
    }

    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

/// CIContext creation options (Apple: `CIContextOption`, a string-backed
/// struct). SolderScope (first community conformance app) constructs
/// `CIContext(options: [.priorityRequestLow: …, .useSoftwareRenderer: …])`.
public struct CIContextOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let priorityRequestLow = CIContextOption(rawValue: "kCIContextPriorityRequestLow")
    public static let useSoftwareRenderer = CIContextOption(rawValue: "kCIContextUseSoftwareRenderer")
    public static let workingColorSpace = CIContextOption(rawValue: "kCIContextWorkingColorSpace")
    public static let outputColorSpace = CIContextOption(rawValue: "kCIContextOutputColorSpace")
    public static let cacheIntermediates = CIContextOption(rawValue: "kCIContextCacheIntermediates")
    public static let name = CIContextOption(rawValue: "kCIContextName")
}

open class CIContext {
    public init() {}

    /// Options are accepted for signature fidelity; the Linux software path
    /// has no renderer toggles yet.
    public convenience init(options: [CIContextOption: Any]?) {
        self.init()
        _ = options
    }

    /// Real when the CIImage is pixel-backed (camera frames, bitmap inits):
    /// produces a CGImage whose quillBGRAPixels feed the Cairo draw path.
    /// Crops to `fromRect` (clamped to the image extent). Placeholder CIImages
    /// still return nil — callers treat that as "no frame yet".
    open func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? {
        guard let pixels = image.quillBGRAPixels, image.quillSize.width > 0 else { return nil }
        let srcWidth = Int(image.quillSize.width)
        let srcHeight = Int(image.quillSize.height)
        guard srcHeight > 0 else { return nil }
        let srcStride = image.quillBytesPerRow > 0 ? image.quillBytesPerRow : srcWidth * 4

        let crop = fromRect.intersection(CGRect(origin: .zero, size: image.quillSize))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1 else { return nil }
        let x = Int(crop.origin.x), y = Int(crop.origin.y)
        let w = Int(crop.width), h = Int(crop.height)

        let outStride = w * 4
        var out = [UInt8](repeating: 0, count: outStride * h)
        for row in 0..<h {
            let srcStart = (y + row) * srcStride + x * 4
            let srcEnd = srcStart + outStride
            guard srcEnd <= pixels.count else { break }
            out.replaceSubrange(row * outStride..<(row + 1) * outStride,
                                with: pixels[srcStart..<srcEnd])
        }

        let cgImage = CGImage()
        cgImage.width = w
        cgImage.height = h
        cgImage.quillBGRAPixels = out
        cgImage.quillBytesPerRow = outStride
        return cgImage
    }
}

open class CIColorKernel {
    public init?(source: String) {
        _ = source
    }

    open func apply(extent: CGRect, arguments: [Any]?) -> CIImage? {
        _ = (extent, arguments)
        return nil
    }
}
