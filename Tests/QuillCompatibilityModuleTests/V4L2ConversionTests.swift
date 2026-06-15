#if os(Linux)
import Testing
import Foundation
import AVFoundation
import CoreVideo

// Fixture tests for the V4L2 capture backend's pure-Swift pieces (#515):
// the BT.601 YUYV→BGRA converter and the /dev/video* discovery parser.
// No camera hardware needed — the only device-touching test gates on the
// actual presence of /dev/video* nodes (absent in CI).

/// Runs the converter over array fixtures, returning nil when it rejects
/// the geometry.
private func convert(
    _ yuyv: [UInt8], width: Int, height: Int,
    sourceBytesPerRow: Int? = nil,
    destinationBytesPerRow: Int? = nil
) -> [UInt8]? {
    let sourceStride = sourceBytesPerRow ?? width * 2
    let destinationStride = destinationBytesPerRow ?? width * 4
    var bgra = [UInt8](repeating: 0, count: destinationStride * height)
    let converted = yuyv.withUnsafeBytes { source in
        bgra.withUnsafeMutableBytes { destination in
            quillConvertYUYVToBGRA(
                source: source, sourceBytesPerRow: sourceStride,
                destination: destination, destinationBytesPerRow: destinationStride,
                width: width, height: height)
        }
    }
    return converted ? bgra : nil
}

/// Thread-safe sink for the V4L2 capture callback, which fires on the camera's
/// background queue. Records the frame count and the first frame's BGRA byte
/// checksum, and lets the test block until a target count or a timeout.
private final class LiveFrameCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let sem = DispatchSemaphore(value: 0)
    private var count = 0
    private var target = 0
    private(set) var firstChecksum: UInt64 = 0

    func record(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        count += 1
        if count == 1 {
            firstChecksum = pixelBuffer.quillWithReadOnlyBytes { raw in
                var sum: UInt64 = 0
                var i = 0
                while i < raw.count { sum &+= UInt64(raw[i]); i += 997 }
                return sum
            }
        }
        let reached = target > 0 && count >= target
        lock.unlock()
        if reached { sem.signal() }
    }

    func waitForFrames(_ n: Int, timeout seconds: Double) -> Bool {
        lock.lock()
        target = n
        let already = count >= n
        lock.unlock()
        if already { return true }
        return sem.wait(timeout: .now() + seconds) == .success
    }
}

struct V4L2ConversionTests {

    @Test func lumaExtremesAndMacropixelByteOrder() throws {
        // One YUYV macropixel [Y0 U Y1 V]: Y0=16 (video black), Y1=235
        // (video white), neutral chroma. Distinct Y0/Y1 also pins down the
        // packing order — a YVYU/UYVY mixup would fail this.
        let bgra = try #require(convert([16, 128, 235, 128], width: 2, height: 1))
        #expect(Array(bgra[0..<4]) == [0, 0, 0, 255])
        #expect(Array(bgra[4..<8]) == [255, 255, 255, 255])
    }

    @Test func saturatedPrimariesWithinTolerance() throws {
        // Classic BT.601 video-range encodings of the saturated primaries.
        let cases: [(yuyv: [UInt8], bgr: [Int], name: String)] = [
            ([81, 90, 81, 240], [0, 0, 255], "red"),
            ([145, 54, 145, 34], [0, 255, 0], "green"),
            ([41, 240, 41, 110], [255, 0, 0], "blue"),
        ]
        for testCase in cases {
            let bgra = try #require(convert(testCase.yuyv, width: 2, height: 1))
            for pixel in 0..<2 {
                for channel in 0..<3 {
                    let actual = Int(bgra[pixel * 4 + channel])
                    #expect(abs(actual - testCase.bgr[channel]) <= 2,
                            "\(testCase.name) pixel \(pixel) channel \(channel): \(actual)")
                }
                #expect(bgra[pixel * 4 + 3] == 255)
            }
        }
    }

    @Test func grayRampIsNeutralMonotonicAndFullRange() throws {
        // Every video-range luma 16...235 with neutral chroma: output must
        // stay exactly gray (R==G==B), ramp monotonically, match the BT.601
        // 255/219 scaling within ±2, and hit both 0 and 255 endpoints.
        let lumas = Array(UInt8(16)...UInt8(235)) // 220 values — even width
        var yuyv: [UInt8] = []
        for luma in lumas {
            yuyv.append(luma)
            yuyv.append(128)
        }
        let width = lumas.count
        let bgra = try #require(convert(yuyv, width: width, height: 1))

        var previous = -1
        for pixel in 0..<width {
            let b = Int(bgra[pixel * 4])
            let g = Int(bgra[pixel * 4 + 1])
            let r = Int(bgra[pixel * 4 + 2])
            #expect(b == g && g == r, "pixel \(pixel) not gray: \(b) \(g) \(r)")
            let expected = Int((Double(Int(lumas[pixel]) - 16) * 255.0 / 219.0).rounded())
            #expect(abs(r - expected) <= 2, "pixel \(pixel): \(r) vs \(expected)")
            #expect(r >= previous)
            previous = r
        }
        #expect(bgra[2] == 0) // Y=16 → black
        #expect(bgra[(width - 1) * 4 + 2] == 255) // Y=235 → white
    }

    @Test func respectsSourceAndDestinationStrides() throws {
        // 2x2 frame: 4 bytes of source row padding (0xAA/0xBB sentinels) and
        // a 12-byte destination stride. Padding must never leak into pixels,
        // and the destination's padding bytes must stay untouched (zeroed).
        let row0: [UInt8] = [16, 128, 235, 128, 0xAA, 0xAA, 0xAA, 0xAA]
        let row1: [UInt8] = [235, 128, 16, 128, 0xBB, 0xBB, 0xBB, 0xBB]
        let bgra = try #require(convert(row0 + row1, width: 2, height: 2,
                                        sourceBytesPerRow: 8,
                                        destinationBytesPerRow: 12))
        #expect(Array(bgra[0..<8]) == [0, 0, 0, 255, 255, 255, 255, 255])
        #expect(Array(bgra[8..<12]) == [0, 0, 0, 0]) // destination padding untouched
        #expect(Array(bgra[12..<20]) == [255, 255, 255, 255, 0, 0, 0, 255])
    }

    @Test func rejectsGeometryTheBuffersCannotSatisfy() {
        // Odd width (YUYV is two pixels per macropixel).
        #expect(convert([16, 128, 235, 128], width: 1, height: 1) == nil)
        // Source too small for the claimed size.
        #expect(convert([16, 128], width: 2, height: 1) == nil)
        // Stride smaller than a row.
        #expect(convert([16, 128, 235, 128], width: 2, height: 1,
                        sourceBytesPerRow: 2) == nil)
        // Degenerate dimensions.
        #expect(convert([], width: 0, height: 0) == nil)
    }

    @Test func devVideoDiscoveryParser() {
        // Only video<N> entries are capture-node candidates; ordering is by
        // node number, not lexicographic (video10 sorts after video2).
        let entries = ["video10", "card0", "video0", "media1", "video2",
                       "videoX", "video", "snd", "v4l-subdev0"]
        #expect(quillV4L2VideoDevicePaths(directoryEntries: entries) ==
                ["/dev/video0", "/dev/video2", "/dev/video10"])
        #expect(quillV4L2VideoDevicePaths(directoryEntries: []).isEmpty)
        #expect(quillV4L2VideoDevicePaths(directoryEntries: ["video7"],
                                          directory: "/tmp/devsim") ==
                ["/tmp/devsim/video7"])
    }

    #if canImport(CV4L2)
    @Test func deviceEnumerationOnHostsWithCameras() {
        // CI has no /dev/video* nodes, so this only exercises QUERYCAP
        // where a node actually exists.
        guard FileManager.default.fileExists(atPath: "/dev/video0") else { return }
        for device in QuillV4L2Camera.enumerateDevices() {
            #expect(device.path.hasPrefix("/dev/video"))
            #expect(!device.card.isEmpty || !device.driver.isEmpty)
        }
    }

    @Test func liveCaptureDeliversConvertedBGRAFrames() throws {
        // Skips where there is no real V4L2 capture node (CI containers can't
        // load v4l2loopback, so /dev/video0 is absent). On a real-kernel host —
        // a physical webcam, or the v4l2loopback virtual cam stood up by
        // scripts/linux-v4l2-live-capture-check.sh — this drives the FULL live
        // path through QuillV4L2Camera: enumerate (QUERYCAP) -> configure
        // (S_FMT/G_FMT YUYV) -> mmap ring (REQBUFS/QUERYBUF/QBUF) -> STREAMON ->
        // poll+DQBUF loop -> YUYV->BGRA -> CVPixelBuffer. Proves SolderScope's
        // camera capture works end-to-end against a live device, not just the
        // pure-Swift converter fixtures above.
        guard FileManager.default.fileExists(atPath: "/dev/video0") else { return }
        let info = try #require(QuillV4L2Camera.enumerateDevices().first)
        let camera = try #require(QuillV4L2Camera(devicePath: info.path))
        try #require(camera.configure(width: 1280, height: 720, frameRate: 30))
        #expect(camera.frameWidth > 0 && camera.frameHeight > 0)

        let collector = LiveFrameCollector()
        let started = camera.start { pixelBuffer, _ in collector.record(pixelBuffer) }
        #expect(started)
        let gotFrames = collector.waitForFrames(3, timeout: 10)
        camera.stop()

        #expect(gotFrames, "expected >=3 frames from \(info.path) within 10s")
        // Non-zero checksum proves the delivered BGRA buffer carries real,
        // converted pixels rather than an all-zero/blank frame.
        #expect(collector.firstChecksum != 0, "captured BGRA frame should carry real pixels")
    }
    #endif
}
#endif
