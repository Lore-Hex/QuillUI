#if os(Linux)
import Foundation
import Dispatch
import CoreMedia
import CoreVideo
import Glibc

extension AVCaptureSession {
    func quillSyntheticStartIfAvailable() {
        guard quillSyntheticBridge == nil,
              let bridge = QuillSyntheticCaptureBridge(session: self)
        else { return }
        quillSyntheticBridge = bridge
        bridge.start()
    }

    func quillSyntheticStopIfAvailable() {
        (quillSyntheticBridge as? QuillSyntheticCaptureBridge)?.stop()
        quillSyntheticBridge = nil
    }
}

private struct QuillSyntheticCaptureConfiguration: Sendable, Equatable {
    static let deviceID = "quill-synthetic://camera"

    var width: Int
    var height: Int
    var framesPerSecond: Int
    var localizedName: String

    static func current() -> QuillSyntheticCaptureConfiguration? {
        guard quillSyntheticCameraIsEnabled(quillSyntheticEnvironmentValue("QUILL_AVFOUNDATION_SYNTHETIC_CAMERA")) else {
            return nil
        }
        return QuillSyntheticCaptureConfiguration(
            width: quillSyntheticPositiveInteger(quillSyntheticEnvironmentValue("QUILL_AVFOUNDATION_SYNTHETIC_WIDTH")) ?? 640,
            height: quillSyntheticPositiveInteger(quillSyntheticEnvironmentValue("QUILL_AVFOUNDATION_SYNTHETIC_HEIGHT")) ?? 480,
            framesPerSecond: quillSyntheticPositiveInteger(quillSyntheticEnvironmentValue("QUILL_AVFOUNDATION_SYNTHETIC_FPS")) ?? 12,
            localizedName: quillSyntheticEnvironmentValue("QUILL_AVFOUNDATION_SYNTHETIC_NAME") ?? "Quill Synthetic Microscope"
        ).normalized()
    }

    func normalized() -> QuillSyntheticCaptureConfiguration {
        QuillSyntheticCaptureConfiguration(
            width: max(2, width),
            height: max(2, height),
            framesPerSecond: min(max(1, framesPerSecond), 60),
            localizedName: localizedName.isEmpty ? "Quill Synthetic Microscope" : localizedName
        )
    }

    static func deviceConfiguration(_ device: AVCaptureDevice) -> QuillSyntheticCaptureConfiguration {
        let dimensions = device.activeFormat.formatDescription.dimensions
        let frameRate = quillSyntheticFrameRate(for: device)
        return QuillSyntheticCaptureConfiguration(
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            framesPerSecond: frameRate,
            localizedName: device.localizedName
        ).normalized()
    }
}

extension AVCaptureDevice {
    static func quillDiscoveredCaptureDevices() -> [AVCaptureDevice] {
        quillSyntheticDiscoveredDevices() + quillV4L2DiscoveredDevices()
    }

    static func quillSyntheticDiscoveredDevices() -> [AVCaptureDevice] {
        guard let configuration = QuillSyntheticCaptureConfiguration.current() else { return [] }
        let device = AVCaptureDevice()
        device.uniqueID = QuillSyntheticCaptureConfiguration.deviceID
        device.localizedName = configuration.localizedName
        device.deviceType = .external
        let format = AVCaptureDevice.Format(
            formatDescription: CMFormatDescription(
                codecType: kCVPixelFormatType_32BGRA,
                dimensions: CMVideoDimensions(
                    width: Int32(configuration.width),
                    height: Int32(configuration.height)
                )
            ),
            videoSupportedFrameRateRanges: [
                AVFrameRateRange(
                    minFrameRate: 1,
                    maxFrameRate: Float64(configuration.framesPerSecond),
                    minFrameDuration: CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond)),
                    maxFrameDuration: CMTime(value: 1, timescale: 1)
                ),
            ]
        )
        device.formats = [format]
        device.activeFormat = format
        return [device]
    }
}

private final class QuillSyntheticCaptureBridge: @unchecked Sendable {
    private let configuration: QuillSyntheticCaptureConfiguration
    private let routes: [(output: AVCaptureVideoDataOutput, connection: AVCaptureConnection)]
    private let formatDescription: CMFormatDescription
    private let queue = DispatchQueue(label: "org.quillos.quillui.synthetic-camera")
    private let fallbackQueue = DispatchQueue(label: "org.quillos.quillui.synthetic-camera-delivery")
    private var timer: DispatchSourceTimer?
    private var frameIndex: Int64 = 0

    init?(session: AVCaptureSession) {
        let syntheticDevice = session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first { $0.uniqueID == QuillSyntheticCaptureConfiguration.deviceID }
        guard let syntheticDevice
        else { return nil }

        let videoOutputs = session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }
        guard !videoOutputs.isEmpty else { return nil }

        let configuration = QuillSyntheticCaptureConfiguration.deviceConfiguration(syntheticDevice)
        self.configuration = configuration
        self.formatDescription = CMFormatDescription(
            codecType: kCVPixelFormatType_32BGRA,
            dimensions: CMVideoDimensions(
                width: Int32(configuration.width),
                height: Int32(configuration.height)
            )
        )
        self.routes = videoOutputs.map { output in
            if output.connections.isEmpty {
                output.connections.append(AVCaptureConnection())
            }
            return (output, output.connections[0])
        }
    }

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let intervalNanoseconds = max(1, 1_000_000_000 / configuration.framesPerSecond)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(intervalNanoseconds))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }

    private func emitFrame() {
        let index = frameIndex
        frameIndex += 1
        let buffer = QuillSyntheticFrameFactory.makeFrame(
            width: configuration.width,
            height: configuration.height,
            frameIndex: index
        )
        let presentationTime = CMTime(
            value: index,
            timescale: CMTimeScale(configuration.framesPerSecond)
        )
        deliver(buffer, at: presentationTime)
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer, at presentationTime: CMTime) {
        let timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(configuration.framesPerSecond)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        let sampleBuffer = CMSampleBuffer(
            formatDescription: formatDescription,
            timingInfo: [timing],
            sampleCount: 1,
            imageBuffer: pixelBuffer
        )
        for route in routes {
            guard let delegate = route.output.sampleBufferDelegate else { continue }
            let queue = route.output.sampleBufferCallbackQueue ?? fallbackQueue
            let box = QuillSyntheticDeliveryBox(
                delegate: delegate,
                output: route.output,
                sampleBuffer: sampleBuffer,
                connection: route.connection
            )
            queue.async {
                box.delegate.captureOutput(box.output, didOutput: box.sampleBuffer, from: box.connection)
            }
        }
    }
}

private enum QuillSyntheticFrameFactory {
    static func makeFrame(width: Int, height: Int, frameIndex: Int64) -> CVPixelBuffer {
        let buffer = CVPixelBuffer(width: width, height: height, pixelFormatType: kCVPixelFormatType_32BGRA)
        buffer.quillWithMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let bytes = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let checker = ((x / 24) + (y / 24) + Int(frameIndex % 8)) & 1
                    let pulse = UInt8((Int(frameIndex) * 7 + x + y) & 0x3f)
                    bytes[offset + 0] = checker == 0 ? UInt8((x * 255) / max(1, width - 1)) : 32
                    bytes[offset + 1] = checker == 0 ? UInt8((y * 255) / max(1, height - 1)) : UInt8(160 + Int(pulse / 2))
                    bytes[offset + 2] = checker == 0 ? UInt8(80 + Int(pulse)) : 220
                    bytes[offset + 3] = 255
                }
            }
        }
        return buffer
    }
}

private struct QuillSyntheticDeliveryBox: @unchecked Sendable {
    let delegate: any AVCaptureVideoDataOutputSampleBufferDelegate
    let output: AVCaptureVideoDataOutput
    let sampleBuffer: CMSampleBuffer
    let connection: AVCaptureConnection
}

private func quillSyntheticCameraIsEnabled(_ value: String?) -> Bool {
    guard let value else { return false }
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on":
        return true
    default:
        return false
    }
}

private func quillSyntheticEnvironmentValue(_ key: String) -> String? {
    getenv(key).map { String(cString: $0) }
}

private func quillSyntheticFrameRate(for device: AVCaptureDevice) -> Int {
    let duration = device.activeVideoMinFrameDuration
    if duration.value > 0, duration.timescale > 0 {
        return Int((Double(duration.timescale) / Double(duration.value)).rounded())
    }
    let maxFrameRate = device.activeFormat.videoSupportedFrameRateRanges
        .map(\.maxFrameRate)
        .max() ?? 12
    return Int(maxFrameRate.rounded())
}

private func quillSyntheticPositiveInteger(_ value: String?) -> Int? {
    guard let value,
          let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
          parsed > 0
    else { return nil }
    return parsed
}
#endif
