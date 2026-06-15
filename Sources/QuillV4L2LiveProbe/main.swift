import Foundation
import AVFoundation
import CoreVideo

// QuillV4L2LiveProbe — a headless end-to-end exercise of QuillUI's REAL V4L2
// capture path (the same QuillV4L2Camera the SolderScope AVCaptureSession
// bridge drives) against a live /dev/video* device. Paired with
// scripts/linux-v4l2-loopback-smoke.sh, which stands up a v4l2loopback virtual
// webcam fed a test pattern by ffmpeg and runs this probe against it, so the
// camera path gets coverage on any host that can load a kernel module (real
// hardware, a dev VM, or a non-container CI runner). The probe is gated out of
// the default build graph (QUILLUI_V4L2_LIVE_PROBE=1) so it never adds cost to
// ordinary CI; the smoke script sets the flag.
//
// Pipeline exercised: device discovery (VIDIOC_QUERYCAP) -> open -> YUYV format
// negotiation (S_FMT/G_FMT) -> mmap ring (REQBUFS/QUERYBUF/QBUF) -> STREAMON ->
// poll+DQBUF loop -> YUYV->BGRA conversion -> CVPixelBuffer delivery.

func env(_ key: String) -> String? {
    let v = ProcessInfo.processInfo.environment[key]
    return (v?.isEmpty == false) ? v : nil
}

let devicePath = env("QUILLUI_V4L2_DEVICE") ?? "/dev/video0"
let targetFrames = env("QUILLUI_V4L2_FRAMES").flatMap(Int.init) ?? 10
let timeoutSeconds = env("QUILLUI_V4L2_TIMEOUT").flatMap(Double.init) ?? 15
let requestedWidth = env("QUILLUI_V4L2_WIDTH").flatMap(Int.init) ?? 1280
let requestedHeight = env("QUILLUI_V4L2_HEIGHT").flatMap(Int.init) ?? 720

// The capture callback fires on QuillV4L2Camera's background queue, so the
// frame state lives in a lock-guarded Sendable box (top-level vars are
// @MainActor-isolated under Swift 6 and cannot be mutated off the main actor).
final class CaptureProbe: @unchecked Sendable {
    private let lock = NSLock()
    let done = DispatchSemaphore(value: 0)
    let camera: QuillV4L2Camera
    let target: Int
    private(set) var frames = 0
    private(set) var firstChecksum: UInt64 = 0

    init(camera: QuillV4L2Camera, target: Int) {
        self.camera = camera
        self.target = target
    }

    func onFrame(_ pixelBuffer: CVPixelBuffer, _ time: CMTime) {
        lock.lock()
        frames += 1
        let n = frames
        if n == 1 {
            firstChecksum = pixelBuffer.quillWithReadOnlyBytes { raw in
                var sum: UInt64 = 0, i = 0
                while i < raw.count { sum &+= UInt64(raw[i]); i += 997 }
                return sum
            }
            print("first frame \(camera.frameWidth)x\(camera.frameHeight), ts=\(time.value)/\(time.timescale), BGRA byte-checksum=\(firstChecksum)")
        }
        lock.unlock()
        if n >= target { done.signal() }
    }

    var total: Int { lock.lock(); defer { lock.unlock() }; return frames }
    var checksum: UInt64 { lock.lock(); defer { lock.unlock() }; return firstChecksum }
}

print("=== QuillV4L2LiveProbe: \(devicePath) (want \(targetFrames) frames @ \(requestedWidth)x\(requestedHeight)) ===")

let devices = QuillV4L2Camera.enumerateDevices()
print("Discovered \(devices.count) capture device(s):")
for d in devices { print("  - \(d.path)  card=\"\(d.card)\"  driver=\"\(d.driver)\"") }
guard devices.contains(where: { $0.path == devicePath }) else {
    print("FAIL: \(devicePath) not enumerated as a capture device")
    exit(1)
}

guard let camera = QuillV4L2Camera(devicePath: devicePath) else {
    print("FAIL: could not open \(devicePath)")
    exit(1)
}

guard camera.configure(width: requestedWidth, height: requestedHeight, frameRate: 30) else {
    print("FAIL: configure() rejected YUYV \(requestedWidth)x\(requestedHeight)")
    exit(1)
}
print("configure -> ok; driver granted \(camera.frameWidth)x\(camera.frameHeight)")

let probe = CaptureProbe(camera: camera, target: targetFrames)
guard camera.start(frameHandler: { pb, t in probe.onFrame(pb, t) }) else {
    print("FAIL: start() could not begin streaming (mmap ring / STREAMON)")
    exit(1)
}
let waited = probe.done.wait(timeout: .now() + timeoutSeconds)
camera.stop()

let total = probe.total
let ok = total >= targetFrames && probe.checksum != 0
print("RESULT: captured \(total)/\(targetFrames) frame(s) at \(camera.frameWidth)x\(camera.frameHeight), checksum=\(probe.checksum) [\(waited == .success ? "OK" : "TIMEOUT")]")
if !ok {
    print("FAIL: expected >= \(targetFrames) frames with non-zero pixel data")
    exit(2)
}
print("PASS: live V4L2 capture + YUYV->BGRA conversion verified")
exit(0)
