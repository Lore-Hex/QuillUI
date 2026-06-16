// Vision barcode-detection surface -- Linux shim for SignalUI's QR scanning
// (SignalUI/ViewControllers/ScanQRCodeViewController.swift's
// QRCodeSampleBufferScanner builds a VNDetectBarcodesRequest, filters the
// results to VNBarcodeObservation with `.qr` symbology, and reads the
// payload).
//
// Like the rest of the Vision shim, detection is INERT on Linux: the request
// handler produces no observations, so the scanner simply never reports a QR
// code. The types exist so the upstream code compiles unmodified.
//
// NOTE: on Apple, `VNBarcodeObservation.barcodeDescriptor` is CoreImage's
// `CIBarcodeDescriptor`. The Vision shim target's dependency list has no
// CoreImage edge (Package.swift, signalAppleFrameworkShims loop -> default
// ["QuillFoundation"]), so the property is typed `AnyObject?` here; upstream's
// `is`/`as?` casts against CI descriptor classes still typecheck.

import Foundation
import QuillFoundation

public struct VNBarcodeSymbology: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let qr = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyQR")
    public static let aztec = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyAztec")
    public static let code128 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyCode128")
    public static let dataMatrix = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyDataMatrix")
    public static let ean13 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyEAN13")
    public static let pdf417 = VNBarcodeSymbology(rawValue: "VNBarcodeSymbologyPDF417")
}

public final class VNDetectBarcodesRequest: VNRequest, @unchecked Sendable {
    /// The symbologies the request should detect (upstream sets `[.qr]`).
    /// Inert on Linux -- the shim's request handler never produces results.
    public var symbologies: [VNBarcodeSymbology] = []

    public override init(completionHandler: CompletionHandler? = nil) {
        super.init(completionHandler: completionHandler)
    }
}

open class VNBarcodeObservation: VNObservation, @unchecked Sendable {
    public let symbology: VNBarcodeSymbology
    /// The decoded string payload, when the symbology carries one.
    public let payloadStringValue: String?
    /// `CIBarcodeDescriptor` on Apple; `AnyObject` here (see header note).
    public let barcodeDescriptor: AnyObject?
    /// `VNConfidence` (a Float typealias) on Apple.
    public let confidence: Float

    public init(
        symbology: VNBarcodeSymbology,
        payloadStringValue: String? = nil,
        barcodeDescriptor: AnyObject? = nil,
        confidence: Float = 1.0,
        boundingBox: CGRect = .zero
    ) {
        self.symbology = symbology
        self.payloadStringValue = payloadStringValue
        self.barcodeDescriptor = barcodeDescriptor
        self.confidence = confidence
        super.init(boundingBox: boundingBox)
    }
}
