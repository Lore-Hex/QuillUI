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
        public static let inputPriority = Preset(rawValue: "AVCaptureSessionPresetInputPriority")
        public static let hd1280x720 = Preset(rawValue: "AVCaptureSessionPreset1280x720")
        public static let hd1920x1080 = Preset(rawValue: "AVCaptureSessionPreset1920x1080")
        public static let hd4K3840x2160 = Preset(rawValue: "AVCaptureSessionPreset3840x2160")
        public static let vga640x480 = Preset(rawValue: "AVCaptureSessionPreset640x480")
    }

    /// `.AVCaptureSessionWasInterrupted` userInfo reason codes (Apple raw values).
    public enum InterruptionReason: Int, Sendable {
        case videoDeviceNotAvailableInBackground = 1
        case audioDeviceInUseByAnotherClient = 2
        case videoDeviceInUseByAnotherClient = 3
        case videoDeviceNotAvailableWithMultipleForegroundApps = 4
        case videoDeviceNotAvailableDueToSystemPressure = 5
    }

    public var sessionPreset: Preset = .high
    public var isMultitaskingCameraAccessSupported: Bool { false }
    public var isMultitaskingCameraAccessEnabled: Bool = false

    /// V4L2 hook (#515): while running with a /dev/video* device input, holds
    /// the QuillV4L2SessionBridge feeding real frames to this session's video
    /// data outputs. AnyObject-typed so this file builds with or without the
    /// CV4L2 shim target.
    var quillV4L2Bridge: AnyObject?
    /// Deterministic fixture camera hook: while running with the opt-in
    /// synthetic device, holds the bridge feeding BGRA frames through the same
    /// AVCaptureVideoDataOutput delegate contract as real V4L2 hardware.
    var quillSyntheticBridge: AnyObject?
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

    public func startRunning() {
        isRunning = true
        // V4L2 backend (#515): begin real frame delivery when a /dev/video*
        // device is attached (no-op otherwise, preserving the inert surface).
        quillV4L2StartIfAvailable()
        quillSyntheticStartIfAvailable()
    }

    public func stopRunning() {
        quillSyntheticStopIfAvailable()
        quillV4L2StopIfAvailable()
        isRunning = false
    }
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

public enum AVCaptureVideoStabilizationMode: Int, Sendable {
    case off = 0
    case standard = 1
    case cinematic = 2
    case cinematicExtended = 3
    case previewOptimized = 4
    case auto = -1
}

public class AVCaptureConnection: @unchecked Sendable {
    public var isEnabled: Bool = true
    public var isVideoMirrored: Bool = false
    public var isActive: Bool { isEnabled }
    public var videoOrientation: AVCaptureVideoOrientation = .portrait
    public var isVideoOrientationSupported: Bool { false }
    public var preferredVideoStabilizationMode: AVCaptureVideoStabilizationMode = .off
    public var isVideoStabilizationSupported: Bool { false }
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

#if os(Linux)
final class QuillRealtimeMovieWriterRegistry: @unchecked Sendable {
    static let shared = QuillRealtimeMovieWriterRegistry()

    private struct Entry {
        weak var writer: AVAssetWriter?
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var lastCaptureFrame: CVPixelBuffer?

    func register(_ writer: AVAssetWriter) {
        lock.lock()
        entries[ObjectIdentifier(writer)] = Entry(writer: writer)
        lock.unlock()
    }

    func unregister(_ writer: AVAssetWriter) {
        lock.lock()
        entries.removeValue(forKey: ObjectIdentifier(writer))
        lock.unlock()
    }

    func appendCaptureFrame(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        lastCaptureFrame = pixelBuffer
        var staleKeys: [ObjectIdentifier] = []
        let activeWriters = entries.compactMap { key, entry -> AVAssetWriter? in
            guard let writer = entry.writer else {
                staleKeys.append(key)
                return nil
            }
            return writer
        }
        for key in staleKeys {
            entries.removeValue(forKey: key)
        }
        lock.unlock()

        for writer in activeWriters {
            writer.quillAppendAutomaticCaptureFrame(pixelBuffer)
        }
    }

    func latestCaptureFrame(matchingWidth width: Int, height: Int) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let lastCaptureFrame,
              lastCaptureFrame.width == width,
              lastCaptureFrame.height == height
        else {
            return nil
        }
        return lastCaptureFrame
    }
}
#endif

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

    #if os(Linux)
    /// Live H.264 encoder (rung 4) — created in `startWriting()` from the
    /// first video input's settings; nil when ffmpeg is unavailable.
    private var quillEncoder: QuillFFmpegMovieEncoder?
    private let quillFrameAppendLock = NSLock()
    private var quillManualFrameAppendCount = 0
    private var quillAutomaticCaptureFrameCount = 0
    private var quillEncodedFrameCount = 0
    private var quillVideoWidth: Int?
    private var quillVideoHeight: Int?

    private static func quillAutomaticCaptureFrameStride() -> Int {
        guard let value = ProcessInfo.processInfo.environment["QUILL_AVFOUNDATION_REALTIME_RECORDING_FRAME_STRIDE"],
              let stride = Int(value),
              stride > 1 else {
            return 1
        }
        return stride
    }
    #endif

    public func canAdd(_ input: AVAssetWriterInput) -> Bool { status == .unknown }
    public func add(_ input: AVAssetWriterInput) {
        inputs.append(input)
        input.quillWriter = self
    }

    public func startWriting() -> Bool {
        #if os(Linux)
        guard let videoInput = inputs.first(where: { $0.mediaType == .video }),
              let settings = videoInput.outputSettings,
              let width = settings[AVVideoWidthKey] as? Int,
              let height = settings[AVVideoHeightKey] as? Int else {
            // No video geometry to encode — keep the historical inert-success
            // shape so audio-only/compile-only callers proceed.
            status = .writing
            return true
        }
        let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any]
        let frameRate = (compression?[AVVideoExpectedSourceFrameRateKey] as? Double)
            ?? (compression?[AVVideoExpectedSourceFrameRateKey] as? Int).map(Double.init)
            ?? 30
        guard let encoder = QuillFFmpegMovieEncoder(
            outputURL: outputURL,
            width: width,
            height: height,
            framesPerSecond: frameRate,
            averageBitRate: compression?[AVVideoAverageBitRateKey] as? Int,
            maxKeyFrameInterval: compression?[AVVideoMaxKeyFrameIntervalKey] as? Int
        ) else {
            status = .failed
            error = NSError(
                domain: "QuillAVFoundation", code: 1, userInfo: [
                    NSLocalizedDescriptionKey:
                        "Movie encoding needs ffmpeg (apt install ffmpeg, or set QUILL_FFMPEG)."
                ])
            return false
        }
        quillEncoder = encoder
        quillVideoWidth = width
        quillVideoHeight = height
        status = .writing
        if videoInput.expectsMediaDataInRealTime {
            QuillRealtimeMovieWriterRegistry.shared.register(self)
            quillAppendLatestCaptureFrameIfAvailable()
        }
        return true
        #else
        status = .writing
        return true
        #endif
    }

    public func startSession(atSourceTime startTime: CMTime) { _ = startTime }
    public func endSession(atSourceTime endTime: CMTime) { _ = endTime }

    public func cancelWriting() {
        #if os(Linux)
        QuillRealtimeMovieWriterRegistry.shared.unregister(self)
        quillEncoder?.cancel()
        quillEncoder = nil
        #endif
        status = .cancelled
    }

    /// Frame entry point used by the input/adaptor `append` paths.
    internal func quillAppendFrame(_ pixelBuffer: CVPixelBuffer) -> Bool {
        quillAppendFrame(pixelBuffer, countsAsManualAppend: true)
    }

    internal func quillAppendAutomaticCaptureFrame(_ pixelBuffer: CVPixelBuffer) {
        _ = quillAppendFrame(pixelBuffer, countsAsManualAppend: false)
    }

    private func quillAppendFrame(_ pixelBuffer: CVPixelBuffer, countsAsManualAppend: Bool) -> Bool {
        guard status == .writing else { return false }
        #if os(Linux)
        quillFrameAppendLock.lock()
        if countsAsManualAppend {
            quillManualFrameAppendCount += 1
        }
        var shouldAppend = countsAsManualAppend || quillManualFrameAppendCount == 0
        if shouldAppend && !countsAsManualAppend {
            quillAutomaticCaptureFrameCount += 1
            let stride = Self.quillAutomaticCaptureFrameStride()
            shouldAppend = quillAutomaticCaptureFrameCount == 1
                || (quillAutomaticCaptureFrameCount - 1) % stride == 0
        }
        quillFrameAppendLock.unlock()
        guard shouldAppend else { return false }

        if let encoder = quillEncoder {
            return quillAppendFrameToEncoder(pixelBuffer, encoder: encoder)
        }
        #endif
        return true
    }

    #if os(Linux)
    private func quillAppendFrameToEncoder(_ pixelBuffer: CVPixelBuffer, encoder: QuillFFmpegMovieEncoder) -> Bool {
        let appended = encoder.appendFrame(pixelBuffer)
        if appended {
            quillFrameAppendLock.lock()
            quillEncodedFrameCount += 1
            quillFrameAppendLock.unlock()
        }
        return appended
    }

    private func quillHasEncodedFrames() -> Bool {
        quillFrameAppendLock.lock()
        defer { quillFrameAppendLock.unlock() }
        return quillEncodedFrameCount > 0
    }

    @discardableResult
    private func quillAppendLatestCaptureFrameIfAvailable() -> Bool {
        guard status == .writing,
              !quillHasEncodedFrames(),
              let encoder = quillEncoder,
              let width = quillVideoWidth,
              let height = quillVideoHeight,
              let frame = QuillRealtimeMovieWriterRegistry.shared.latestCaptureFrame(
                  matchingWidth: width,
                  height: height
              )
        else {
            return false
        }
        return quillAppendFrameToEncoder(frame, encoder: encoder)
    }

    private func quillAppendFinalFallbackFrameIfNeeded() {
        guard status == .writing,
              !quillHasEncodedFrames(),
              let encoder = quillEncoder,
              let width = quillVideoWidth,
              let height = quillVideoHeight
        else {
            return
        }
        if quillAppendLatestCaptureFrameIfAvailable() {
            return
        }
        _ = quillAppendFrameToEncoder(
            quillMakeFallbackMovieFrame(width: width, height: height),
            encoder: encoder
        )
    }

    private func quillMakeFallbackMovieFrame(width: Int, height: Int) -> CVPixelBuffer {
        let frame = CVPixelBuffer(
            width: width,
            height: height,
            pixelFormatType: kCVPixelFormatType_32BGRA
        )
        frame.quillWithMutableBytes { raw in
            for offset in stride(from: 0, to: raw.count, by: 4) {
                raw[offset] = 24
                if offset + 1 < raw.count { raw[offset + 1] = 24 }
                if offset + 2 < raw.count { raw[offset + 2] = 24 }
                if offset + 3 < raw.count { raw[offset + 3] = 255 }
            }
        }
        return frame
    }
    #endif

    public func finishWriting(completionHandler handler: @escaping () -> Void) {
        #if os(Linux)
        quillAppendFinalFallbackFrameIfNeeded()
        QuillRealtimeMovieWriterRegistry.shared.unregister(self)
        if let encoder = quillEncoder {
            // ffmpeg finalizes the container on stdin close; do the wait off
            // the caller's thread, exactly like Apple's async finish. The
            // handler crosses in a box (Apple marks the parameter @Sendable;
            // we keep the laxer historical signature for source compat).
            let writer = self
            let boxedHandler = QuillSendableCompletionBox(handler: handler)
            Thread.detachNewThread {
                let ok = encoder.finish()
                writer.status = ok ? .completed : .failed
                if !ok, writer.error == nil {
                    writer.error = NSError(
                        domain: "QuillAVFoundation", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: "ffmpeg exited with a failure while finalizing the recording."
                        ])
                }
                writer.quillEncoder = nil
                boxedHandler.handler()
            }
            return
        }
        #endif
        status = .completed
        handler()
    }

    public func finishWriting() async {
        await withCheckedContinuation { continuation in
            finishWriting { continuation.resume() }
        }
    }
}

public class AVAssetWriterInput: @unchecked Sendable {
    public let mediaType: AVMediaType
    public let outputSettings: [String: Any]?
    public var expectsMediaDataInRealTime: Bool = false
    public var isReadyForMoreMediaData: Bool { true }
    public private(set) var isFinished = false
    /// Back-reference set by `AVAssetWriter.add(_:)` so append paths reach
    /// the live encoder.
    internal weak var quillWriter: AVAssetWriter?

    public init(mediaType: AVMediaType, outputSettings: [String: Any]?) {
        self.mediaType = mediaType
        self.outputSettings = outputSettings
    }

    public func append(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let imageBuffer = sampleBuffer.imageBuffer else { return true }
        return quillWriter?.quillAppendFrame(imageBuffer) ?? true
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
        // Constant-frame-rate encode: the pipe carries no per-frame PTS, so
        // presentation times are accepted (Apple shape) but pacing comes from
        // the configured frame rate. SolderScope appends at camera delivery
        // rate with expectsMediaDataInRealTime, which matches.
        _ = presentationTime
        return assetWriterInput.quillWriter?.quillAppendFrame(pixelBuffer) ?? true
    }
}

/// Carries the finish-completion handler onto the finalizer thread (Apple's
/// own parameter is @Sendable; ours stays source-compatible and crosses in a
/// box — single hop, invoked exactly once).
private struct QuillSendableCompletionBox: @unchecked Sendable {
    let handler: () -> Void
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
