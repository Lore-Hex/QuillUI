//
// QuillUI Linux shim for `CoreImage` — placeholder so `import CoreImage` resolves on
// Linux. Concrete symbols are added as SignalServiceKit references surface
// (behavior deferred). Part of the Signal-iOS -> QuillOS port.
//
import Foundation
import QuillFoundation

// MARK: - CIImage / CIFilter / CIContext
//
// SignalServiceKit's CombinedFingerprints renders the safety-number QR via
// `CIFilter(name: "CIQRCodeGenerator")` -> outputImage -> CIContext.createCGImage.
// There is no Core Image pipeline on Linux, so this is INERT: the filter constructs
// but produces no output image, and createCGImage returns nil, so the upstream
// `guard let` chain bails and `buildQRImage()` returns nil. HONEST STATUS: the
// safety-number QR code is not generated on Linux yet (a real QR encoder would be
// needed). The type surface exists only so the upstream Swift compiles.

open class CIImage {
    public init() {}

    /// The image's bounds. Inert (no pixels); only read to pass to createCGImage,
    /// which returns nil anyway.
    open var extent: CGRect { CGRect.zero }
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

    public convenience init?(color: RSColor) {
        self.init(red: color._red, green: color._green, blue: color._blue, alpha: color._alpha)
    }

    public convenience init(cgColor: CGColor) {
        let components = cgColor.components ?? [0, 0, 0, 1]
        let red = components.indices.contains(0) ? components[0] : 0
        let green = components.indices.contains(1) ? components[1] : red
        let blue = components.indices.contains(2) ? components[2] : red
        let alpha = components.indices.contains(3) ? components[3] : 1
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

open class CIContext {
    public init() {}

    /// No rasterizer on Linux -> nil. The caller treats nil as "QR unavailable".
    open func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? { nil }
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
