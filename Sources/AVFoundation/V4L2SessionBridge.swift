// AVCaptureSession ↔ V4L2 wiring (#515).
//
// When `startRunning()` is called on a session whose inputs include a device
// whose `uniqueID` is a /dev/video* path (the marker `DiscoverySession`'s
// V4L2 enumeration sets), this bridge spins up a `QuillV4L2Camera` and feeds
// its converted BGRA frames — wrapped in `CMSampleBuffer`s — to every
// `AVCaptureVideoDataOutput`'s delegate on that output's callback queue:
// the same delivery contract capture apps (SolderScope's CaptureManager)
// already rely on from Apple's AVFoundation. Sessions without a /dev/video*
// input keep the previous inert behavior.

#if os(Linux)
import Foundation
import Dispatch
import CoreMedia
import CoreVideo

extension AVCaptureSession {
    /// Called from `startRunning()`. No-op unless the CV4L2 shim is built
    /// and the session references a /dev/video* device.
    func quillV4L2StartIfAvailable() {
        #if canImport(CV4L2)
        guard quillV4L2Bridge == nil,
              let bridge = QuillV4L2SessionBridge(session: self)
        else { return }
        quillV4L2Bridge = bridge
        bridge.start()
        #endif
    }

    /// Called from `stopRunning()`; tears down the live camera if one is
    /// attached.
    func quillV4L2StopIfAvailable() {
        #if canImport(CV4L2)
        (quillV4L2Bridge as? QuillV4L2SessionBridge)?.stop()
        quillV4L2Bridge = nil
        #endif
    }
}

#if canImport(CV4L2)

/// Per-session coordinator: one camera, fanned out to the session's video
/// data outputs. Created in `startRunning()`, released in `stopRunning()`.
// @unchecked Sendable: stored state is immutable after init and the
// camera serializes its own mutation; the frame handler closure hops
// the bridge across the capture queue.
final class QuillV4L2SessionBridge: @unchecked Sendable {
    private let camera: QuillV4L2Camera
    private let routes: [(output: AVCaptureVideoDataOutput, connection: AVCaptureConnection)]
    private let formatDescription: CMFormatDescription
    /// Apple's API requires a non-nil queue in
    /// `setSampleBufferDelegate(_:queue:)`; this covers outputs that were
    /// configured without one anyway.
    private let fallbackQueue = DispatchQueue(label: "org.quillos.quillui.v4l2-delivery")

    /// Fails (leaving the session inert) when there is no /dev/video* input,
    /// no video data output, the node cannot be opened, or YUYV negotiation
    /// fails.
    init?(session: AVCaptureSession) {
        let devicePath = session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device.uniqueID }
            .first { $0.hasPrefix("/dev/video") }
        guard let devicePath else { return nil }

        let videoOutputs = session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }
        guard !videoOutputs.isEmpty else { return nil }

        guard let camera = QuillV4L2Camera(devicePath: devicePath) else { return nil }
        let requested = Self.requestedSize(for: session)
        guard camera.configure(width: requested.width, height: requested.height) else {
            return nil
        }

        self.camera = camera
        self.formatDescription = CMFormatDescription(
            dimensions: CMVideoDimensions(width: Int32(camera.frameWidth),
                                          height: Int32(camera.frameHeight)))
        self.routes = videoOutputs.map { output in
            if output.connections.isEmpty {
                output.connections.append(AVCaptureConnection())
            }
            return (output, output.connections[0])
        }
    }

    deinit {
        camera.stop()
    }

    func start() {
        camera.start { [weak self] pixelBuffer, presentationTime in
            self?.deliver(pixelBuffer, at: presentationTime)
        }
    }

    func stop() {
        camera.stop()
    }

    /// Preferred capture size: the input device's active format when it has
    /// real dimensions (capture apps set `activeFormat` under
    /// `lockForConfiguration()` before starting), else the session preset,
    /// else 720p.
    private static func requestedSize(for session: AVCaptureSession) -> (width: Int, height: Int) {
        for input in session.inputs {
            guard let deviceInput = input as? AVCaptureDeviceInput else { continue }
            let dimensions = deviceInput.device.activeFormat.formatDescription.dimensions
            if dimensions.width > 0, dimensions.height > 0 {
                return (Int(dimensions.width), Int(dimensions.height))
            }
        }
        switch session.sessionPreset {
        case .hd4K3840x2160: return (3840, 2160)
        case .hd1920x1080: return (1920, 1080)
        case .hd1280x720: return (1280, 720)
        case .vga640x480, .low: return (640, 480)
        default: return (1280, 720)
        }
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer, at presentationTime: CMTime) {
        let timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid)
        let sampleBuffer = CMSampleBuffer(
            formatDescription: formatDescription,
            timingInfo: [timing],
            sampleCount: 1,
            imageBuffer: pixelBuffer)
        for route in routes {
            guard let delegate = route.output.sampleBufferDelegate else { continue }
            let queue = route.output.sampleBufferCallbackQueue ?? fallbackQueue
            let output = route.output
            let connection = route.connection
            // The delegate protocol is not Sendable (Apple parity); delivery
            // is serialized per-output on its callback queue, so the hop is
            // a formality.
            let box = QuillV4L2DeliverySendableBox(
                delegate: delegate, output: output,
                sampleBuffer: sampleBuffer, connection: connection)
            queue.async {
                box.delegate.captureOutput(box.output, didOutput: box.sampleBuffer, from: box.connection)
            }
        }
    }
}

#endif // canImport(CV4L2)
#endif // os(Linux)

/// Crossing the per-output callback queue with non-Sendable AVFoundation
/// surface values (Apple's delegate types are not Sendable either; delivery
/// order is preserved by the serial queue).
private struct QuillV4L2DeliverySendableBox: @unchecked Sendable {
    let delegate: any AVCaptureVideoDataOutputSampleBufferDelegate
    let output: AVCaptureVideoDataOutput
    let sampleBuffer: CMSampleBuffer
    let connection: AVCaptureConnection
}
