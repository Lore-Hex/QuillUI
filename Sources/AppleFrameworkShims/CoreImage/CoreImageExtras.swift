//
// CoreImage filter keys + barcode descriptors — second slice of the Linux
// CoreImage shim (CoreImage.swift holds the inert CIImage/CIFilter/CIContext
// core). Drivers:
//   • SignalUI/UIKitExtensions/UIImage+Blur.swift — CIImage(cgImage:),
//     CIFilter(name:parameters:) with the kCIInput* keys (CIAffineClamp,
//     CIGaussianBlur, CIConstantColorGenerator, CI*Compositing, CIVibrance,
//     CIExposureAdjust).
//   • SignalUI/ViewControllers/ScanQRCodeViewController.swift — casts Vision's
//     `VNBarcodeObservation.barcodeDescriptor: AnyObject?` to
//     `CIQRCodeDescriptor` and reads errorCorrectedPayload/symbolVersion.
//
// Same posture as CoreImage.swift: INERT. Filters built with parameters still
// produce no `outputImage` (no Core Image backend on Linux), so upstream's
// guard-let chains bail — blur/tint effects are unavailable. The QR descriptor
// is a faithful data holder, but the Linux Vision shim never produces one, so
// camera QR scanning never fires (cameras don't exist here anyway).
//
import Foundation
import QuillFoundation

// MARK: - Filter input keys (Apple: global `String` constants)

public let kCIInputImageKey = "inputImage"
public let kCIInputBackgroundImageKey = "inputBackgroundImage"
public let kCIInputTargetImageKey = "inputTargetImage"
public let kCIInputMaskImageKey = "inputMaskImage"
public let kCIInputColorKey = "inputColor"
public let kCIInputRadiusKey = "inputRadius"
public let kCIInputAmountKey = "inputAmount"
public let kCIInputEVKey = "inputEV"
public let kCIInputIntensityKey = "inputIntensity"
public let kCIInputScaleKey = "inputScale"
public let kCIInputAspectRatioKey = "inputAspectRatio"
public let kCIInputCenterKey = "inputCenter"
public let kCIInputAngleKey = "inputAngle"
public let kCIInputWidthKey = "inputWidth"
public let kCIInputSharpnessKey = "inputSharpness"
public let kCIInputSaturationKey = "inputSaturation"
public let kCIInputBrightnessKey = "inputBrightness"
public let kCIInputContrastKey = "inputContrast"
public let kCIInputTimeKey = "inputTime"
public let kCIInputTransformKey = "inputTransform"
public let kCIOutputImageKey = "outputImage"

// MARK: - CIFilter(name:parameters:) / CIImage(cgImage:)

public extension CIFilter {
    /// Apple's keyed-parameters initializer. Parameters are forwarded to
    /// `setValue(_:forKey:)` (a no-op in the inert core), so the filter
    /// constructs but still yields no output image.
    convenience init?(name: String, parameters params: [String: Any]?) {
        self.init(name: name)
        if let params {
            for (key, value) in params {
                setValue(value, forKey: key)
            }
        }
    }
}

public extension CIImage {
    /// Inert wrap of a CGImage: no pixel storage behind it, `extent` stays
    /// zero, and any render through CIContext returns nil.
    convenience init(cgImage image: CGImage) {
        _ = image
        self.init()
    }

    convenience init?(image: RSImage) {
        _ = image
        self.init()
    }

    func applyingFilter(_ filterName: String, parameters: [String: Any] = [:]) -> CIImage {
        _ = (filterName, parameters)
        return self
    }
}

// MARK: - Barcode descriptors

/// Abstract base (Apple: NSObject subclass, NSCopying/NSSecureCoding).
/// Vision's Linux shim stores descriptors as `AnyObject?`, so upstream's
/// `is` / `as?` casts against these classes typecheck unchanged.
open class CIBarcodeDescriptor: NSObject {
    public override init() { super.init() }
}

open class CIQRCodeDescriptor: CIBarcodeDescriptor {
    /// Apple raw values are the ASCII codes of the level letters.
    public enum ErrorCorrectionLevel: Int32, Sendable {
        case levelL = 76 // "L" — 7% recovery
        case levelM = 77 // "M" — 15%
        case levelQ = 81 // "Q" — 25%
        case levelH = 72 // "H" — 30%
    }

    public let errorCorrectedPayload: Data
    public let symbolVersion: Int
    public let maskPattern: UInt8
    public let errorCorrectionLevel: ErrorCorrectionLevel

    public init?(
        payload errorCorrectedPayload: Data,
        symbolVersion: Int,
        maskPattern: UInt8,
        errorCorrectionLevel: ErrorCorrectionLevel
    ) {
        // QR symbol versions are 1...40 (Apple's initializer is failable for
        // out-of-range descriptors).
        guard (1...40).contains(symbolVersion) else { return nil }
        self.errorCorrectedPayload = errorCorrectedPayload
        self.symbolVersion = symbolVersion
        self.maskPattern = maskPattern
        self.errorCorrectionLevel = errorCorrectionLevel
        super.init()
    }
}

// MARK: - Legacy CIDetector QR surface

public let CIDetectorTypeQRCode = "CIDetectorTypeQRCode"
public let CIDetectorAccuracy = "CIDetectorAccuracy"
public let CIDetectorAccuracyHigh = "CIDetectorAccuracyHigh"

open class CIFeature: NSObject {}

open class CIQRCodeFeature: CIFeature {
    public let messageString: String?

    public init(messageString: String? = nil) {
        self.messageString = messageString
        super.init()
    }
}

open class CIDetector: NSObject {
    public init?(ofType type: String, context: CIContext?, options: [String: Any]?) {
        _ = (type, context, options)
        super.init()
    }

    open func features(in image: CIImage) -> [CIFeature] {
        _ = image
        return []
    }
}
