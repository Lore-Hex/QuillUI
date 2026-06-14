import Foundation
import QuillFoundation
// CGImagePropertyOrientation (ImageIO) and CVPixelBuffer (CoreVideo) are the
// argument types of VNImageRequestHandler's init overloads SignalUI drives
// (ImageEditorViewController+Blur.swift's face detection passes a
// CGImagePropertyOrientation; ScanQRCodeViewController passes a CVPixelBuffer).
import ImageIO
import CoreVideo

open class VNRequest: @unchecked Sendable {
    // @MainActor (not @Sendable): SignalUI's VNDetectFaceRectanglesRequest
    // completion closure (ImageEditorViewController+Blur) calls @MainActor members
    // (faceDetectionFailed, self.view); an @MainActor handler type makes that
    // closure literal infer @MainActor. Inert on Linux (requests never run a
    // detector), and `complete()` invokes it via `assumeIsolated`.
    public typealias CompletionHandler = @MainActor (VNRequest, Error?) -> Void
    public typealias ProgressHandler = @Sendable (VNRequest, Double, Error?) -> Void

    public var results: [Any]?
    public var progressHandler: ProgressHandler?

    private let completionHandler: CompletionHandler?
    private var isCancelled = false

    public init(completionHandler: CompletionHandler? = nil) {
        self.completionHandler = completionHandler
    }

    open func cancel() {
        isCancelled = true
    }

    func complete(error: Error? = nil) {
        guard !isCancelled else { return }
        progressHandler?(self, 1.0, error)
        // completionHandler is @MainActor; on Linux detection never runs, and any
        // call would be on the main thread (UI-driven), so assume isolation.
        let handler = completionHandler
        MainActor.assumeIsolated { handler?(self, error) }
    }
}

public enum VNRequestTextRecognitionLevel: Sendable {
    case accurate
    case fast
}

public let VNRecognizeTextRequestRevision1 = 1
public let VNRecognizeTextRequestRevision2 = 2
public let VNRecognizeTextRequestRevision3 = 3

public final class VNRecognizeTextRequest: VNRequest, @unchecked Sendable {
    public var preferBackgroundProcessing = false
    public var usesLanguageCorrection = false
    public var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    public var revision = VNRecognizeTextRequestRevision1
    public var automaticallyDetectsLanguage = false

    public override init(completionHandler: CompletionHandler? = nil) {
        super.init(completionHandler: completionHandler)
    }
}

public final class VNImageRequestHandler: @unchecked Sendable {
    // The source the handler was built over. On Apple these are distinct init
    // overloads (cgImage:, cvPixelBuffer:, ciImage:, url:, data:). Inert on Linux,
    // so the stored source is unused -- perform() never produces observations.
    public let cgImage: CGImage?

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public init(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        options: [VNImageOption: Any] = [:]
    ) {
        _ = (orientation, options)
        self.cgImage = cgImage
    }

    public init(
        cvPixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        options: [VNImageOption: Any] = [:]
    ) {
        _ = (cvPixelBuffer, orientation, options)
        self.cgImage = nil
    }

    public func perform(_ requests: [VNRequest]) throws {
        for request in requests {
            request.results = []
            request.complete()
        }
    }
}

// VNImageOption keys (e.g. `.ciContext`, `.properties`). Upstream constructs
// handlers with an empty options dictionary; the keys exist for signature
// fidelity only.
public struct VNImageOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let properties = VNImageOption(rawValue: "VNImageOptionProperties")
    public static let cameraIntrinsics = VNImageOption(rawValue: "VNImageOptionCameraIntrinsics")
    public static let ciContext = VNImageOption(rawValue: "VNImageOptionCIContext")
}

open class VNObservation: @unchecked Sendable {
    public var boundingBox: CGRect

    public init(boundingBox: CGRect = .zero) {
        self.boundingBox = boundingBox
    }
}

// MARK: - Face detection
//
// SignalUI's auto-blur (ImageEditorViewController+Blur.swift) builds a
// VNDetectFaceRectanglesRequest, runs it through a VNImageRequestHandler, and
// reads `request.results as? [VNFaceObservation]`, mapping each observation's
// `boundingBox`. On Apple the hierarchy is
// VNObservation -> VNDetectedObjectObservation -> VNFaceObservation. Detection is
// INERT on Linux (perform() yields no results), so auto-blur simply finds no
// faces; the types exist so the upstream compiles unmodified.

open class VNDetectedObjectObservation: VNObservation, @unchecked Sendable {
    public override init(boundingBox: CGRect = .zero) {
        super.init(boundingBox: boundingBox)
    }
}

public final class VNFaceObservation: VNDetectedObjectObservation, @unchecked Sendable {
    public override init(boundingBox: CGRect = .zero) {
        super.init(boundingBox: boundingBox)
    }
}

/// Base class for requests that operate on a single image. On Apple this sits
/// between VNRequest and the concrete image requests; modeled as a thin pass-through.
open class VNImageBasedRequest: VNRequest, @unchecked Sendable {
    public override init(completionHandler: CompletionHandler? = nil) {
        super.init(completionHandler: completionHandler)
    }
}

public final class VNDetectFaceRectanglesRequest: VNImageBasedRequest, @unchecked Sendable {
    public var revision = 1

    public override init(completionHandler: CompletionHandler? = nil) {
        super.init(completionHandler: completionHandler)
    }
}

public final class VNRecognizedTextObservation: VNObservation, @unchecked Sendable {
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomLeft: CGPoint
    public var bottomRight: CGPoint

    private let candidates: [VNRecognizedText]

    public init(
        boundingBox: CGRect = .zero,
        topLeft: CGPoint = .zero,
        topRight: CGPoint = .zero,
        bottomLeft: CGPoint = .zero,
        bottomRight: CGPoint = .zero,
        candidates: [VNRecognizedText] = []
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
        self.candidates = candidates
        super.init(boundingBox: boundingBox)
    }

    public func topCandidates(_ maxCandidateCount: Int) -> [VNRecognizedText] {
        Array(candidates.prefix(max(0, maxCandidateCount)))
    }
}

public final class VNRecognizedText: @unchecked Sendable {
    public let string: String
    public let confidence: Float

    public init(string: String, confidence: Float = 1.0) {
        self.string = string
        self.confidence = confidence
    }
}
