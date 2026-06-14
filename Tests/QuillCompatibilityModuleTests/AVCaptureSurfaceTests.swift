#if os(Linux)
import Testing
import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import CoreMedia

// Conformance tests for the capture/writer surface (#506) and the CoreImage
// frame pipeline (#516) — Apple-style call sites compiled and exercised the
// way SolderScope's CaptureManager/FrameProcessor/RecordingManager use them.

private final class RecordingDelegate: AVCaptureVideoDataOutputSampleBufferDelegate {
    var frames = 0
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
    }
    // didDrop intentionally NOT implemented — the protocol default covers it
    // (Apple's optional-method semantics).
}

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

    @Test func assetWriterLifecycle() async throws {
        let url = URL(fileURLWithPath: "/tmp/quill-avwriter-test.mov")
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
        #expect(adaptor.append(CVPixelBuffer(width: 4, height: 4, pixelFormatType: kCVPixelFormatType_32BGRA),
                               withPresentationTime: CMTime(value: 1, timescale: 30)))
        input.markAsFinished()
        // Deterministic finalize: the callback form finishes on a detached
        // thread, so await the async overload rather than racing a flag.
        await writer.finishWriting()
        #expect(writer.status == .completed)
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
}
#endif
