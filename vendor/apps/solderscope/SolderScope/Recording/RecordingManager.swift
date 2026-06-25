import AVFoundation
import CoreImage
import Combine

@MainActor
final class RecordingManager: ObservableObject {
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var duration: TimeInterval = 0

    private nonisolated(unsafe) var assetWriter: AVAssetWriter?
    private nonisolated(unsafe) var videoInput: AVAssetWriterInput?
    private nonisolated(unsafe) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private nonisolated(unsafe) var startTime: CMTime?
    private nonisolated(unsafe) var frameCount: Int64 = 0
    private var durationTimer: Timer?

    private let recordingQueue = DispatchQueue(label: "com.solderscope.recording", qos: .userInitiated)

    // MARK: - Configuration

    struct Configuration {
        var codec: AVVideoCodecType = .h264
        var bitrate: Int = 10_000_000 // 10 Mbps
        var keyFrameInterval: Int = 30
        var outputDirectory: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    private var configuration = Configuration()

    // MARK: - Public API

    func startRecording(from captureManager: CaptureManager, resolution: CGSize) async {
        guard !isRecording else {
            Logger.recording.warning("Already recording")
            return
        }

        let filename = generateFilename()
        let outputURL = configuration.outputDirectory.appendingPathComponent(filename)

        do {
            try await setupAssetWriter(outputURL: outputURL, resolution: resolution)
            isRecording = true
            startDurationTimer()
            Logger.recording.info("Recording started: \(filename)")
        } catch {
            Logger.recording.error("Failed to start recording: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        isRecording = false
        stopDurationTimer()

        recordingQueue.async { [weak self] in
            self?.finalizeRecording()
        }
    }

    func writeFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRecording,
              let adaptor = pixelBufferAdaptor,
              let input = videoInput,
              input.isReadyForMoreMediaData else {
            return
        }

        recordingQueue.async { [weak self] in
            guard let self = self else { return }

            let presentationTime: CMTime
            if let start = self.startTime {
                presentationTime = CMTimeSubtract(timestamp, start)
            } else {
                self.startTime = timestamp
                presentationTime = .zero
            }

            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                self.frameCount += 1
            } else {
                Logger.recording.warning("Failed to append frame")
            }
        }
    }

    // MARK: - Private

    private func setupAssetWriter(outputURL: URL, resolution: CGSize) async throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Video settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: configuration.codec,
            AVVideoWidthKey: Int(resolution.width),
            AVVideoHeightKey: Int(resolution.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: configuration.bitrate,
                AVVideoMaxKeyFrameIntervalKey: configuration.keyFrameInterval,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        // Pixel buffer attributes
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(resolution.width),
            kCVPixelBufferHeightKey as String: Int(resolution.height)
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        if writer.canAdd(input) {
            writer.add(input)
        } else {
            throw RecordingError.cannotAddInput
        }

        if !writer.startWriting() {
            throw RecordingError.cannotStartWriting(writer.error)
        }

        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor
        self.startTime = nil
        self.frameCount = 0
    }

    private nonisolated func finalizeRecording() {
        guard let writer = assetWriter else { return }

        videoInput?.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)

        writer.finishWriting {
            if writer.status == .completed {
                Logger.recording.info("Recording saved: \(writer.outputURL.lastPathComponent) (\(self.frameCount) frames)")
            } else if let error = writer.error {
                Logger.recording.error("Recording failed: \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()

        // Cleanup
        assetWriter = nil
        videoInput = nil
        pixelBufferAdaptor = nil

        Task { @MainActor in
            self.duration = 0
        }
    }

    private func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        return "SolderScope_\(timestamp).mov"
    }

    private func startDurationTimer() {
        let startDate = Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.duration = Date().timeIntervalSince(startDate)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case cannotAddInput
    case cannotStartWriting(Error?)

    var errorDescription: String? {
        switch self {
        case .cannotAddInput:
            return "Cannot add video input to asset writer"
        case .cannotStartWriting(let error):
            return "Cannot start writing: \(error?.localizedDescription ?? "unknown error")"
        }
    }
}
