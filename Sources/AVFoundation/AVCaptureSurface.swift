import Foundation
import CoreMedia
import CoreVideo

// AVFoundation capture-session + asset-writer compile surface (#506, with the
// SolderScope coverage-audit amendments). App-agnostic: faithful Apple
// signatures, inert behavior — the V4L2 backend (#515) gives the session real
// frames behind these same names. First conformance driver: SolderScope's
// CaptureManager/RecordingManager compile unmodified against this.

// MARK: - Capture session graph

public class AVCaptureSession: @unchecked Sendable {
    public struct Preset: RawRepresentable, Equatable, Hashable, Sendable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let high = Preset(rawValue: "AVCaptureSessionPresetHigh")
        public static let medium = Preset(rawValue: "AVCaptureSessionPresetMedium")
        public static let low = Preset(rawValue: "AVCaptureSessionPresetLow")
        public static let photo = Preset(rawValue: "AVCaptureSessionPresetPhoto")
        public static let hd1280x720 = Preset(rawValue: "AVCaptureSessionPreset1280x720")
        public static let hd1920x1080 = Preset(rawValue: "AVCaptureSessionPreset1920x1080")
        public static let hd4K3840x2160 = Preset(rawValue: "AVCaptureSessionPreset3840x2160")
        public static let vga640x480 = Preset(rawValue: "AVCaptureSessionPreset640x480")
    }

    public var sessionPreset: Preset = .high
    public private(set) var inputs: [AVCaptureInput] = []
    public private(set) var outputs: [AVCaptureOutput] = []
    public private(set) var isRunning: Bool = false

    public init() {}

    public func beginConfiguration() {}
    public func commitConfiguration() {}

    public func canSetSessionPreset(_ preset: Preset) -> Bool { true }

    public func canAddInput(_ input: AVCaptureInput) -> Bool { true }
    public func addInput(_ input: AVCaptureInput) { inputs.append(input) }
    public func removeInput(_ input: AVCaptureInput) {
        inputs.removeAll { $0 === input }
    }

    public func canAddOutput(_ output: AVCaptureOutput) -> Bool { true }
    public func addOutput(_ output: AVCaptureOutput) { outputs.append(output) }
    public func removeOutput(_ output: AVCaptureOutput) {
        outputs.removeAll { $0 === output }
    }

    public func startRunning() { isRunning = true }
    public func stopRunning() { isRunning = false }
}

open class AVCaptureInput: @unchecked Sendable {
    public init() {}
}

public class AVCaptureDeviceInput: AVCaptureInput, @unchecked Sendable {
    public let device: AVCaptureDevice
    public init(device: AVCaptureDevice) throws {
        self.device = device
        super.init()
    }
}

open class AVCaptureOutput: @unchecked Sendable {
    public init() {}
    public var connections: [AVCaptureConnection] = []
    public func connection(with mediaType: AVMediaType) -> AVCaptureConnection? {
        _ = mediaType
        return connections.first
    }
}

public class AVCaptureConnection: @unchecked Sendable {
    public var isEnabled: Bool = true
    public var isVideoMirrored: Bool = false
    public var isActive: Bool { isEnabled }
    public init() {}
}

// MARK: - Video data output + delegate

/// Class-constrained like Apple's (an @objc protocol there). Both delegate
/// methods are defaulted so implementing either subset compiles, matching
/// the optional-method semantics.
public protocol AVCaptureVideoDataOutputSampleBufferDelegate: AnyObject {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
    func captureOutput(_ output: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection)
}

extension AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {}
    public func captureOutput(_ output: AVCaptureOutput,
                              didDrop sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {}
}

public class AVCaptureVideoDataOutput: AVCaptureOutput, @unchecked Sendable {
    public var videoSettings: [String: Any]! = [:]
    public var alwaysDiscardsLateVideoFrames: Bool = true
    public private(set) weak var sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    public private(set) var sampleBufferCallbackQueue: DispatchQueue?

    public override init() { super.init() }

    public func setSampleBufferDelegate(
        _ sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?,
        queue sampleBufferCallbackQueue: DispatchQueue?
    ) {
        self.sampleBufferDelegate = sampleBufferDelegate
        self.sampleBufferCallbackQueue = sampleBufferCallbackQueue
    }

    public func availableVideoPixelFormatTypes() -> [OSType] {
        [kCVPixelFormatType_32BGRA]
    }
}

// Video-settings keys (subset used by capture pipelines).
public let kCVPixelBufferPixelFormatTypeKey: String = "PixelFormatType"
public let kCVPixelBufferWidthKey: String = "Width"
public let kCVPixelBufferHeightKey: String = "Height"

// MARK: - Device connect/disconnect notifications

extension Notification.Name {
    public static let AVCaptureDeviceWasConnected =
        Notification.Name("AVCaptureDeviceWasConnectedNotification")
    public static let AVCaptureDeviceWasDisconnected =
        Notification.Name("AVCaptureDeviceWasDisconnectedNotification")
}

// MARK: - Asset writer (recording)

public class AVAssetWriter: @unchecked Sendable {
    public enum Status: Int, Sendable {
        case unknown = 0, writing = 1, completed = 2, failed = 3, cancelled = 4
    }

    public let outputURL: URL
    public let outputFileType: AVFileType
    public private(set) var status: Status = .unknown
    public private(set) var error: Error?
    public private(set) var inputs: [AVAssetWriterInput] = []
    public var metadata: [Any] = []

    public init(outputURL: URL, fileType: AVFileType) throws {
        self.outputURL = outputURL
        self.outputFileType = fileType
    }

    public func canAdd(_ input: AVAssetWriterInput) -> Bool { status == .unknown }
    public func add(_ input: AVAssetWriterInput) { inputs.append(input) }

    public func startWriting() -> Bool {
        status = .writing
        return true
    }

    public func startSession(atSourceTime startTime: CMTime) { _ = startTime }
    public func endSession(atSourceTime endTime: CMTime) { _ = endTime }

    public func cancelWriting() { status = .cancelled }

    public func finishWriting(completionHandler handler: @escaping () -> Void) {
        status = .completed
        handler()
    }

    public func finishWriting() async {
        status = .completed
    }
}

public class AVAssetWriterInput: @unchecked Sendable {
    public let mediaType: AVMediaType
    public let outputSettings: [String: Any]?
    public var expectsMediaDataInRealTime: Bool = false
    public var isReadyForMoreMediaData: Bool { true }
    public private(set) var isFinished = false

    public init(mediaType: AVMediaType, outputSettings: [String: Any]?) {
        self.mediaType = mediaType
        self.outputSettings = outputSettings
    }

    public func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        _ = sampleBuffer
        return true
    }

    public func markAsFinished() { isFinished = true }
}

public class AVAssetWriterInputPixelBufferAdaptor: @unchecked Sendable {
    public let assetWriterInput: AVAssetWriterInput
    public let sourcePixelBufferAttributes: [String: Any]?
    public var pixelBufferPool: CVPixelBufferPool? { nil }

    public init(assetWriterInput: AVAssetWriterInput,
                sourcePixelBufferAttributes: [String: Any]?) {
        self.assetWriterInput = assetWriterInput
        self.sourcePixelBufferAttributes = sourcePixelBufferAttributes
    }

    public func append(_ pixelBuffer: CVPixelBuffer,
                       withPresentationTime presentationTime: CMTime) -> Bool {
        _ = (pixelBuffer, presentationTime)
        return true
    }
}

// MARK: - Video codec/settings constants

public struct AVVideoCodecType: RawRepresentable, Equatable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let h264 = AVVideoCodecType(rawValue: "avc1")
    public static let hevc = AVVideoCodecType(rawValue: "hvc1")
    public static let jpeg = AVVideoCodecType(rawValue: "jpeg")
    public static let proRes422 = AVVideoCodecType(rawValue: "apcn")
    public static let proRes4444 = AVVideoCodecType(rawValue: "ap4h")
}

public let AVVideoCodecKey = "AVVideoCodecKey"
public let AVVideoWidthKey = "AVVideoWidthKey"
public let AVVideoHeightKey = "AVVideoHeightKey"
public let AVVideoCompressionPropertiesKey = "AVVideoCompressionPropertiesKey"
public let AVVideoAverageBitRateKey = "AVVideoAverageBitRateKey"
public let AVVideoMaxKeyFrameIntervalKey = "AVVideoMaxKeyFrameIntervalKey"
public let AVVideoProfileLevelKey = "AVVideoProfileLevelKey"
public let AVVideoProfileLevelH264HighAutoLevel = "H264_High_AutoLevel"
public let AVVideoProfileLevelH264MainAutoLevel = "H264_Main_AutoLevel"
public let AVVideoExpectedSourceFrameRateKey = "AVVideoExpectedSourceFrameRateKey"
public let AVVideoQualityKey = "AVVideoQualityKey"
