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

public class CIImage {
    /// The image's bounds. Inert (no pixels); only read to pass to createCGImage,
    /// which returns nil anyway.
    public var extent: CGRect { CGRect.zero }
}

public class CIFilter {
    /// `CIFilter(name:)` is failable on Apple. Here it succeeds (so the caller's guard
    /// passes) but the filter has no Core Image backend, so `outputImage` is nil.
    public init?(name: String) {}

    public func setDefaults() {}
    public func setValue(_ value: Any?, forKey key: String) {}

    /// No rendering backend -> no output image.
    public var outputImage: CIImage? { nil }
}

public class CIContext {
    public init() {}

    /// No rasterizer on Linux -> nil. The caller treats nil as "QR unavailable".
    public func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? { nil }
}
