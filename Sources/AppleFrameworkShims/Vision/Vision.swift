import Foundation
import QuillFoundation

open class VNRequest: @unchecked Sendable {
    public typealias CompletionHandler = @Sendable (VNRequest, Error?) -> Void
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
        completionHandler?(self, error)
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
    public let cgImage: CGImage

    public init(cgImage: CGImage) {
        self.cgImage = cgImage
    }

    public func perform(_ requests: [VNRequest]) throws {
        for request in requests {
            request.results = []
            request.complete()
        }
    }
}

open class VNObservation: @unchecked Sendable {
    public var boundingBox: CGRect

    public init(boundingBox: CGRect = .zero) {
        self.boundingBox = boundingBox
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
