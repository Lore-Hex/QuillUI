#if os(Linux)
import Testing
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia
import Glibc

// Conformance tests for the capture/writer surface (#506) and the CoreImage
// frame pipeline (#516) — Apple-style call sites compiled and exercised the
// way SolderScope's CaptureManager/FrameProcessor/RecordingManager use them.

private final class RecordingDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    private let lock = NSLock()
    private var storedFrames = 0
    private var storedLastImageSize: CGSize?

    var frames: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedFrames
    }

    var lastImageSize: CGSize? {
        lock.lock()
        defer { lock.unlock() }
        return storedLastImageSize
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock()
        defer { lock.unlock() }
        storedFrames += 1
        if let imageBuffer = sampleBuffer.imageBuffer {
            storedLastImageSize = CGSize(width: imageBuffer.width, height: imageBuffer.height)
        }
    }
    // didDrop intentionally NOT implemented — the protocol default covers it
    // (Apple's optional-method semantics).
}

@Suite(.serialized)
struct AVCaptureSurfaceTests {

    @Test func captureSessionGraphAssembles() throws {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        let device = AVCaptureDevice()
        device.deviceType = .external
        let input = try AVCaptureDeviceInput(device: device)
        #expect(session.canAddInput(input))
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let delegate = RecordingDelegate()
        output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "capture"))
        #expect(session.canAddOutput(output))
        session.addOutput(output)
        session.commitConfiguration()

        session.startRunning()
        #expect(session.isRunning)
        #expect(session.inputs.count == 1)
        #expect(session.outputs.count == 1)

        session.removeOutput(output)
        session.removeInput(input)
        session.stopRunning()
        #expect(session.outputs.isEmpty)
        #expect(session.inputs.isEmpty)
        #expect(!session.isRunning)
    }

    @Test func deviceConfigurationSurface() throws {
        let device = AVCaptureDevice()
        device.formats = [AVCaptureDevice.Format(
            videoSupportedFrameRateRanges: [AVFrameRateRange(minFrameRate: 5, maxFrameRate: 60)])]
        try device.lockForConfiguration()
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
        device.unlockForConfiguration()
        #expect(device.formats[0].videoSupportedFrameRateRanges[0].maxFrameRate == 60)
        #expect(AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
        #expect(discovery.devices.isEmpty) // until #515 enumerates /dev/video*
    }

    @Test func syntheticCameraDiscoveryIsOptIn() {
        withSyntheticCameraEnvironment(width: 640, height: 480, fps: 15) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external], mediaType: .video, position: .unspecified)
            let synthetic = discovery.devices.first { $0.uniqueID == "quill-synthetic://camera" }
            #expect(synthetic?.localizedName == "Quill Synthetic Microscope")
            #expect(synthetic?.deviceType == .external)
            #expect(synthetic?.formats.first?.formatDescription.dimensions.width == 640)
            #expect(synthetic?.formats.first?.formatDescription.dimensions.height == 480)
            #expect(synthetic?.formats.first?.videoSupportedFrameRateRanges.first?.maxFrameRate == 15)
        }
    }

    @Test func syntheticCaptureSessionDeliversFrames() async throws {
        let delegate = RecordingDelegate()
        try await withSyntheticCameraEnvironment(width: 96, height: 64, fps: 20) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external], mediaType: .video, position: .unspecified)
            let device = try #require(discovery.devices.first { $0.uniqueID == "quill-synthetic://camera" })

            let session = AVCaptureSession()
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(delegate, queue: DispatchQueue(label: "synthetic-capture-test"))

            session.beginConfiguration()
            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            defer { session.stopRunning() }

            for _ in 0..<40 where delegate.frames < 2 {
                try await Task.sleep(nanoseconds: 25_000_000)
            }
        }
        #expect(delegate.frames >= 2)
        #expect(delegate.lastImageSize == CGSize(width: 96, height: 64))
    }

    @Test func assetWriterLifecycle() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-avwriter-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        #expect(writer.outputURL == url)

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        #expect(writer.canAdd(input))
        writer.add(input)

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)

        // startWriting() spins up the real ffmpeg H.264 encoder (rung 4). Hosts
        // without ffmpeg — including the Linux CI image, which doesn't apt-install
        // it — instead get the shim's documented `.failed` contract with the
        // "needs ffmpeg" error. Assert whichever path the environment yields so
        // the suite is green with or without the encoder, while still exercising
        // the full encode wherever ffmpeg is present (dev machines / SolderScope).
        guard writer.startWriting() else {
            #expect(writer.status == .failed)
            #expect(writer.error != nil)
            return
        }
        writer.startSession(atSourceTime: CMTime(value: 0, timescale: 600))
        // The appended frame must match the writer's configured geometry
        // (AVVideoWidthKey/HeightKey above): the Linux ffmpeg-backed encoder
        // is launched as a fixed-size rawvideo pipe and rejects a mismatched
        // frame (encoder.appendFrame guards pixelBuffer.width/height == the
        // configured width/height). A 4x4 buffer only ever "passed" on macOS,
        // whose shim append path is inert-true. Feed a real 1280x720 frame.
        #expect(adaptor.append(CVPixelBuffer(width: 1280, height: 720, pixelFormatType: kCVPixelFormatType_32BGRA),
                               withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        // finishWriting is asynchronous on both platforms: Apple delivers the
        // completion off the calling thread, and the Linux shim detaches a
        // thread that closes the ffmpeg stdin pipe and waitUntilExit()s the
        // encoder. Await the async form so encoding is fully finalized before
        // asserting. Reading a plain `var finished` on the next line was a
        // race that only ever passed on macOS — whose shim path completes
        // synchronously — and on Linux additionally left the detached encoder
        // thread running into suite teardown (a likely SIGILL source).
        await writer.finishWriting()
        #expect(writer.status == .completed)
        let movie = try #require(FileManager.default.contents(atPath: url.path))
        #expect(movie.count > 500)
        #expect(Array(movie[4..<8]) == Array("ftyp".utf8))
    }

    @Test("real-time writer can consume synthetic capture frames without manual appends",
          .enabled(if: AVCaptureSurfaceTests.ffmpegPresent))
    func realtimeWriterConsumesSyntheticCaptureFramesWithoutManualAppends() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-synthetic-recording-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await withSyntheticCameraEnvironment(width: 96, height: 64, fps: 20) {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            )
            let device = try #require(discovery.devices.first { $0.uniqueID == "quill-synthetic://camera" })

            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 96,
                AVVideoHeightKey: 64,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 400_000,
                    AVVideoExpectedSourceFrameRateKey: 20,
                ],
            ])
            input.expectsMediaDataInRealTime = true
            #expect(writer.canAdd(input))
            writer.add(input)
            #expect(writer.startWriting())
            writer.startSession(atSourceTime: .zero)

            let session = AVCaptureSession()
            session.beginConfiguration()
            session.addInput(try AVCaptureDeviceInput(device: device))
            session.addOutput(AVCaptureVideoDataOutput())
            session.commitConfiguration()
            session.startRunning()
            try await Task.sleep(nanoseconds: 700_000_000)
            session.stopRunning()

            input.markAsFinished()
            await writer.finishWriting()
            #expect(writer.status == .completed)
        }

        let movie = try #require(FileManager.default.contents(atPath: outputURL.path))
        #expect(movie.count > 500)
        #expect(Array(movie[4..<8]) == Array("ftyp".utf8))
    }

    @Test func ciImagePixelPipelineRoundTrips() {
        // Synthetic 4x2 BGRA frame with a recognizable gradient.
        let width = 4, height = 2
        let buffer = CVPixelBuffer(width: width, height: height,
                                   pixelFormatType: kCVPixelFormatType_32BGRA)
        buffer.quillWithMutableBytes { raw in
            for i in 0..<(width * height * 4) { raw[i] = UInt8(i % 251) }
        }

        let ciImage = CIImage(cvPixelBuffer: buffer)
        #expect(ciImage.extent == CGRect(x: 0, y: 0, width: 4, height: 2))

        let context = CIContext(options: [.useSoftwareRenderer: true])
        // Full-extent round trip.
        let full = context.createCGImage(ciImage, from: ciImage.extent)
        #expect(full != nil)
        #expect(full?.width == 4 && full?.height == 2)
        #expect(full?.quillBGRAPixels?.prefix(8).map { Int($0) } == [0, 1, 2, 3, 4, 5, 6, 7])

        // Cropped: second row, columns 1..<3 (byte offset = stride + 4).
        let crop = context.createCGImage(ciImage, from: CGRect(x: 1, y: 1, width: 2, height: 1))
        #expect(crop?.width == 2 && crop?.height == 1)
        #expect(crop?.quillBGRAPixels?.first == UInt8((width * 4 + 4) % 251))

        // Placeholder CIImages keep the historical "no frame" nil.
        #expect(context.createCGImage(CIImage(), from: .zero) == nil)
    }

    @Test func cvPixelBufferBaseAddressMutatesStableStorage() throws {
        let buffer = CVPixelBuffer(width: 2, height: 2, pixelFormatType: kCVPixelFormatType_32BGRA)
        #expect(CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess)
        let base = try #require(CVPixelBufferGetBaseAddress(buffer))
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for index in 0..<16 {
            bytes[index] = UInt8(240 - index)
        }
        #expect(CVPixelBufferUnlockBaseAddress(buffer, []) == kCVReturnSuccess)

        let ciImage = CIImage(cvPixelBuffer: buffer)
        let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent)
        #expect(cgImage?.quillBGRAPixels?.prefix(8).map { Int($0) } == [240, 239, 238, 237, 236, 235, 234, 233])
    }

    static var ffmpegPresent: Bool {
        if let override = ProcessInfo.processInfo.environment["QUILL_FFMPEG"],
           FileManager.default.isExecutableFile(atPath: override) {
            return true
        }
        return ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

private func withSyntheticCameraEnvironment<R>(
    width: Int,
    height: Int,
    fps: Int,
    _ body: () throws -> R
) rethrows -> R {
    let previous = syntheticCameraEnvironmentSnapshot()
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA", "1", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_WIDTH", "\(width)", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT", "\(height)", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_FPS", "\(fps)", 1)
    defer { restoreSyntheticCameraEnvironment(previous) }
    return try body()
}

private func withSyntheticCameraEnvironment<R>(
    width: Int,
    height: Int,
    fps: Int,
    _ body: () async throws -> R
) async rethrows -> R {
    let previous = syntheticCameraEnvironmentSnapshot()
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA", "1", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_WIDTH", "\(width)", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT", "\(height)", 1)
    setenv("QUILL_AVFOUNDATION_SYNTHETIC_FPS", "\(fps)", 1)
    defer { restoreSyntheticCameraEnvironment(previous) }
    return try await body()
}

private func syntheticCameraEnvironmentSnapshot() -> [String: String?] {
    [
        "QUILL_AVFOUNDATION_SYNTHETIC_CAMERA": getenvString("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA"),
        "QUILL_AVFOUNDATION_SYNTHETIC_WIDTH": getenvString("QUILL_AVFOUNDATION_SYNTHETIC_WIDTH"),
        "QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT": getenvString("QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT"),
        "QUILL_AVFOUNDATION_SYNTHETIC_FPS": getenvString("QUILL_AVFOUNDATION_SYNTHETIC_FPS"),
    ]
}

private func restoreSyntheticCameraEnvironment(_ snapshot: [String: String?]) {
    for (key, value) in snapshot {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}

private func getenvString(_ key: String) -> String? {
    getenv(key).map { String(cString: $0) }
}
#endif
