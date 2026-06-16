// V4L2 capture backend (#515) — real Linux camera frames for the capture
// surface (#506).
//
// `QuillV4L2Camera` drives the Video4Linux2 kernel API through the CV4L2
// shim: it enumerates /dev/video* nodes (QUERYCAP, keeping devices with
// VIDEO_CAPTURE+STREAMING), negotiates a packed-YUYV format, maps the
// kernel's buffer ring, and runs a poll+DQBUF loop on a serial
// DispatchQueue, delivering each frame as a BGRA `CVPixelBuffer` plus a
// `CMTime` taken from the kernel's capture timestamp.
//
// The pure-Swift YUYV→BGRA converter and the /dev/video* name parser live
// OUTSIDE the CV4L2 guard so they compile (and unit-test) everywhere the
// AVFoundation shadow module builds, with or without the C shim target.

#if os(Linux)
import Foundation
import Dispatch
import CoreVideo
import CoreMedia
#if canImport(CV4L2)
import CV4L2
import Glibc
#endif

// MARK: - YUYV → BGRA conversion (standalone, pure Swift)

/// Converts packed YUYV 4:2:2 (`Y0 U Y1 V`, four bytes per two-pixel
/// macropixel) into 32-bit BGRA using the integer BT.601 video-range
/// matrix (Y 16…235, chroma centered on 128), with channel clamping.
/// Strides are in bytes; rows may carry padding on either side. Returns
/// false (writing nothing) for geometry the buffers cannot satisfy —
/// V4L2 YUYV frames always have even width.
@discardableResult
public func quillConvertYUYVToBGRA(
    source: UnsafeRawBufferPointer,
    sourceBytesPerRow: Int,
    destination: UnsafeMutableRawBufferPointer,
    destinationBytesPerRow: Int,
    width: Int,
    height: Int
) -> Bool {
    guard width > 0, height > 0, width.isMultiple(of: 2),
          sourceBytesPerRow >= width * 2,
          destinationBytesPerRow >= width * 4,
          source.count >= (height - 1) * sourceBytesPerRow + width * 2,
          destination.count >= (height - 1) * destinationBytesPerRow + width * 4
    else { return false }

    for row in 0..<height {
        var sourceOffset = row * sourceBytesPerRow
        var destinationOffset = row * destinationBytesPerRow
        for _ in 0..<(width / 2) {
            let y0 = Int(source[sourceOffset])
            let u = Int(source[sourceOffset + 1]) - 128
            let y1 = Int(source[sourceOffset + 2])
            let v = Int(source[sourceOffset + 3]) - 128
            quillWriteBT601Pixel(luma: y0, chromaU: u, chromaV: v,
                                 into: destination, at: destinationOffset)
            quillWriteBT601Pixel(luma: y1, chromaU: u, chromaV: v,
                                 into: destination, at: destinationOffset + 4)
            sourceOffset += 4
            destinationOffset += 8
        }
    }
    return true
}

/// One BT.601 video-range YCbCr → BGRA pixel (the classic fixed-point
/// matrix: R = 1.164·(Y−16) + 1.596·(V−128), etc., scaled by 256).
@inline(__always)
private func quillWriteBT601Pixel(
    luma: Int, chromaU u: Int, chromaV v: Int,
    into destination: UnsafeMutableRawBufferPointer, at offset: Int
) {
    let c = 298 * (luma - 16)
    let r = (c + 409 * v + 128) >> 8
    let g = (c - 100 * u - 208 * v + 128) >> 8
    let b = (c + 516 * u + 128) >> 8
    destination[offset] = quillClampToUInt8(b)
    destination[offset + 1] = quillClampToUInt8(g)
    destination[offset + 2] = quillClampToUInt8(r)
    destination[offset + 3] = 255
}

@inline(__always)
private func quillClampToUInt8(_ value: Int) -> UInt8 {
    UInt8(min(255, max(0, value)))
}

// MARK: - /dev/video* discovery parsing (standalone, pure Swift)

/// Pure half of device discovery: given directory entries (normally from
/// listing `/dev`), returns the full paths of `video<N>` capture nodes
/// sorted by node number. Entries like `videoX`, `video`, `card0`, or
/// `media0` are not capture nodes and are skipped.
public func quillV4L2VideoDevicePaths(
    directoryEntries: [String],
    directory: String = "/dev"
) -> [String] {
    directoryEntries
        .compactMap { entry -> (index: Int, path: String)? in
            guard entry.hasPrefix("video") else { return nil }
            let suffix = entry.dropFirst("video".count)
            guard !suffix.isEmpty,
                  suffix.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let index = Int(suffix)
            else { return nil }
            return (index, directory + "/" + entry)
        }
        .sorted { $0.index < $1.index }
        .map(\.path)
}

// MARK: - Device + format descriptions

/// Identity snapshot of one /dev/video* capture node (from VIDIOC_QUERYCAP).
public struct QuillV4L2DeviceInfo: Sendable {
    public let path: String
    public let driver: String
    public let card: String
    public init(path: String, driver: String, card: String) {
        self.path = path
        self.driver = driver
        self.card = card
    }
}

public struct QuillV4L2FrameSize: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// One pixel format a device offers (from VIDIOC_ENUM_FMT), with its
/// discrete frame sizes (from VIDIOC_ENUM_FRAMESIZES; stepwise ranges are
/// reported as their min/max extremes).
public struct QuillV4L2PixelFormat: Sendable {
    public let fourCC: UInt32
    public let name: String
    public let frameSizes: [QuillV4L2FrameSize]
    public init(fourCC: UInt32, name: String, frameSizes: [QuillV4L2FrameSize]) {
        self.fourCC = fourCC
        self.name = name
        self.frameSizes = frameSizes
    }
}

/// Packed-YUYV fourcc ('Y','U','Y','V' little-endian). The kernel's
/// V4L2_PIX_FMT_YUYV is a function-like macro Swift cannot import, so the
/// value is spelled out.
public let quillV4L2PixelFormatYUYV: UInt32 = 0x5659_5559

/// Legalizes a requested YUYV capture size before it is sent to a V4L2
/// driver. YUYV is two pixels per macropixel, so odd widths are rounded up.
public func quillV4L2SanitizedCaptureSize(width: Int, height: Int) -> QuillV4L2FrameSize {
    let minimumWidth = max(2, width)
    let evenWidth = minimumWidth.isMultiple(of: 2) ? minimumWidth : minimumWidth + 1
    return QuillV4L2FrameSize(width: evenWidth, height: max(1, height))
}

/// Chooses the supported frame size nearest to the requested one. Exact
/// matches win, then larger-or-equal sizes, then the closest smaller size.
public func quillV4L2BestFrameSize(
    _ sizes: [QuillV4L2FrameSize],
    requestedWidth: Int,
    requestedHeight: Int
) -> QuillV4L2FrameSize? {
    let requested = quillV4L2SanitizedCaptureSize(width: requestedWidth, height: requestedHeight)
    return Array(Set(sizes)).sorted { lhs, rhs in
        quillV4L2FrameSizeScore(lhs, requested: requested)
            < quillV4L2FrameSizeScore(rhs, requested: requested)
    }.first
}

/// From an advertised format list, chooses the best YUYV capture size. Returns
/// nil when the camera does not advertise YUYV, because the live converter only
/// handles that pixel format today.
public func quillV4L2PreferredYUYVCaptureSize(
    formats: [QuillV4L2PixelFormat],
    requestedWidth: Int,
    requestedHeight: Int
) -> QuillV4L2FrameSize? {
    let yuyvFormats = formats.filter { $0.fourCC == quillV4L2PixelFormatYUYV }
    guard !yuyvFormats.isEmpty else { return nil }

    let sizes = yuyvFormats.flatMap(\.frameSizes)
    return quillV4L2BestFrameSize(sizes, requestedWidth: requestedWidth, requestedHeight: requestedHeight)
        ?? quillV4L2SanitizedCaptureSize(width: requestedWidth, height: requestedHeight)
}

private func quillV4L2FrameSizeScore(
    _ size: QuillV4L2FrameSize,
    requested: QuillV4L2FrameSize
) -> (Int, Int64, Int64, Int, Int) {
    let exactPenalty = size == requested ? 0 : 1
    let smallerPenalty = (size.width < requested.width || size.height < requested.height) ? 1 : 0
    let lhsArea = Int64(size.width) * Int64(size.height)
    let requestedArea = Int64(requested.width) * Int64(requested.height)
    let areaDelta = abs(lhsArea - requestedArea)
    let aspectDelta = abs(Int64(size.width) * Int64(requested.height)
        - Int64(requested.width) * Int64(size.height))
    return (exactPenalty, Int64(smallerPenalty), areaDelta + aspectDelta, size.width, size.height)
}

#if canImport(CV4L2)

// Capability bits (plain #defines in videodev2.h; declared locally so the
// Swift side does not depend on macro importability or signedness).
private let quillV4L2CapVideoCapture: UInt32 = 0x0000_0001 // V4L2_CAP_VIDEO_CAPTURE
private let quillV4L2CapStreaming: UInt32 = 0x0400_0000 // V4L2_CAP_STREAMING
private let quillV4L2CapDeviceCaps: UInt32 = 0x8000_0000 // V4L2_CAP_DEVICE_CAPS

/// NUL-terminated fixed-size C char array (imported as a homogeneous tuple)
/// → String.
private func quillString<T>(fromFixedCArray value: T) -> String {
    withUnsafeBytes(of: value) { raw in
        String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}

// MARK: - Camera

/// A live V4L2 capture device. Lifecycle: `init?` opens the node,
/// `configure` negotiates YUYV at the requested size, `start` maps the
/// ring + begins streaming, `stop` tears it down. While streaming, the
/// capture loop keeps the camera alive (it owns a strong self reference),
/// so dropping the last external reference without calling `stop()` does
/// not interrupt delivery — `stop()` is the explicit off switch, exactly
/// like `AVCaptureSession.stopRunning`.
public final class QuillV4L2Camera: @unchecked Sendable {
    /// Converted BGRA frame + the kernel's capture timestamp.
    // @Sendable: invoked from the capture queue; conforms to the
    // Dispatch async closure requirements.
    public typealias FrameHandler = @Sendable (CVPixelBuffer, CMTime) -> Void

    public let devicePath: String
    /// Dimensions granted by VIDIOC_G_FMT (drivers may round the request).
    public private(set) var frameWidth: Int = 0
    public private(set) var frameHeight: Int = 0

    private let fd: Int32
    private var sourceBytesPerRow: Int = 0
    private var ring: [(base: UnsafeMutableRawPointer, length: Int)] = []
    private let captureQueue = DispatchQueue(label: "org.quillos.quillui.v4l2-capture")
    private let stateLock = NSLock()
    private var stopRequested = false
    private var streaming = false
    private let loopGroup = DispatchGroup()

    /// Opens the device node non-blocking (poll paces the capture loop).
    public init?(devicePath: String) {
        let fd = open(devicePath, O_RDWR | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        self.fd = fd
        self.devicePath = devicePath
    }

    deinit {
        stop()
        close(fd)
    }

    // MARK: Enumeration

    /// All /dev/video* nodes that are real capture devices: QUERYCAP must
    /// succeed and report VIDEO_CAPTURE + STREAMING (metadata/output nodes
    /// that share the video* namespace are filtered out here).
    public static func enumerateDevices(in directory: String = "/dev") -> [QuillV4L2DeviceInfo] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return quillV4L2VideoDevicePaths(directoryEntries: entries, directory: directory)
            .compactMap { path in
                let fd = open(path, O_RDWR | O_NONBLOCK)
                guard fd >= 0 else { return nil }
                defer { close(fd) }
                var capability = v4l2_capability()
                guard quill_v4l2_querycap(fd, &capability) == 0 else { return nil }
                let caps = (capability.capabilities & quillV4L2CapDeviceCaps) != 0
                    ? capability.device_caps
                    : capability.capabilities
                guard (caps & quillV4L2CapVideoCapture) != 0,
                      (caps & quillV4L2CapStreaming) != 0
                else { return nil }
                return QuillV4L2DeviceInfo(
                    path: path,
                    driver: quillString(fromFixedCArray: capability.driver),
                    card: quillString(fromFixedCArray: capability.card)
                )
            }
    }

    /// Pixel formats + frame sizes the device offers (ENUM_FMT/FRAMESIZES).
    public func supportedFormats() -> [QuillV4L2PixelFormat] {
        var formats: [QuillV4L2PixelFormat] = []
        var index: UInt32 = 0
        while true {
            var descriptor = v4l2_fmtdesc()
            descriptor.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
            descriptor.index = index
            guard quill_v4l2_enum_fmt(fd, &descriptor) == 0 else { break }
            formats.append(QuillV4L2PixelFormat(
                fourCC: descriptor.pixelformat,
                name: quillString(fromFixedCArray: descriptor.description),
                frameSizes: frameSizes(forPixelFormat: descriptor.pixelformat)
            ))
            index += 1
        }
        return formats
    }

    private func frameSizes(forPixelFormat pixelFormat: UInt32) -> [QuillV4L2FrameSize] {
        var sizes: [QuillV4L2FrameSize] = []
        var index: UInt32 = 0
        while true {
            var enumeration = v4l2_frmsizeenum()
            enumeration.pixel_format = pixelFormat
            enumeration.index = index
            guard quill_v4l2_enum_framesizes(fd, &enumeration) == 0 else { break }
            if enumeration.type == V4L2_FRMSIZE_TYPE_DISCRETE.rawValue {
                sizes.append(QuillV4L2FrameSize(
                    width: Int(enumeration.discrete.width),
                    height: Int(enumeration.discrete.height)))
                index += 1
            } else {
                // Stepwise/continuous ranges are a single entry; surface the
                // extremes so callers can still pick a sensible size.
                sizes.append(QuillV4L2FrameSize(
                    width: Int(enumeration.stepwise.min_width),
                    height: Int(enumeration.stepwise.min_height)))
                sizes.append(QuillV4L2FrameSize(
                    width: Int(enumeration.stepwise.max_width),
                    height: Int(enumeration.stepwise.max_height)))
                break
            }
        }
        return sizes
    }

    // MARK: Configuration

    /// Negotiates YUYV at the requested size (S_FMT), reads back what the
    /// driver granted (G_FMT — `frameWidth`/`frameHeight` reflect that),
    /// and requests the frame interval best-effort (S_PARM). Fails if the
    /// driver cannot do YUYV — the only format the converter handles.
    @discardableResult
    public func configure(width requestedWidth: Int, height requestedHeight: Int,
                          frameRate: Double = 30) -> Bool {
        let advertisedFormats = supportedFormats()
        let requestedSize: QuillV4L2FrameSize
        if advertisedFormats.isEmpty {
            requestedSize = quillV4L2SanitizedCaptureSize(
                width: requestedWidth,
                height: requestedHeight)
        } else {
            guard let preferred = quillV4L2PreferredYUYVCaptureSize(
                formats: advertisedFormats,
                requestedWidth: requestedWidth,
                requestedHeight: requestedHeight)
            else { return false }
            requestedSize = preferred
        }

        var format = v4l2_format()
        format.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
        format.fmt.pix.width = UInt32(requestedSize.width)
        format.fmt.pix.height = UInt32(requestedSize.height)
        format.fmt.pix.pixelformat = quillV4L2PixelFormatYUYV
        format.fmt.pix.field = V4L2_FIELD_NONE.rawValue
        guard quill_v4l2_s_fmt(fd, &format) == 0 else { return false }

        var granted = v4l2_format()
        granted.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
        guard quill_v4l2_g_fmt(fd, &granted) == 0,
              granted.fmt.pix.pixelformat == quillV4L2PixelFormatYUYV
        else { return false }
        frameWidth = Int(granted.fmt.pix.width)
        frameHeight = Int(granted.fmt.pix.height)
        sourceBytesPerRow = max(Int(granted.fmt.pix.bytesperline), frameWidth * 2)

        if frameRate > 0 {
            var parameters = v4l2_streamparm()
            parameters.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
            parameters.parm.capture.timeperframe = v4l2_fract(
                numerator: 1, denominator: UInt32(max(1, frameRate.rounded())))
            _ = quill_v4l2_s_parm(fd, &parameters) // best effort; not all drivers honor it
        }
        return frameWidth > 0 && frameHeight > 0
    }

    // MARK: Streaming

    /// Maps the mmap ring (REQBUFS/QUERYBUF/QBUF), turns streaming on, and
    /// starts the poll+DQBUF loop on the capture queue. The handler runs on
    /// that queue — hop queues before touching UI or delegate state.
    @discardableResult
    public func start(frameHandler: @escaping FrameHandler) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !streaming, frameWidth > 0, frameHeight > 0 else { return false }
        guard mapRing() else { return false }

        var bufferType = Int32(bitPattern: V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue)
        guard quill_v4l2_streamon(fd, &bufferType) == 0 else {
            unmapRing()
            return false
        }
        streaming = true
        stopRequested = false
        loopGroup.enter()
        captureQueue.async { self.captureLoop(frameHandler: frameHandler) }
        return true
    }

    /// Stops the capture loop (waits for it to exit), turns streaming off,
    /// and unmaps the ring. Safe to call when not streaming.
    public func stop() {
        stateLock.lock()
        guard streaming else {
            stateLock.unlock()
            return
        }
        stopRequested = true
        stateLock.unlock()

        loopGroup.wait()

        stateLock.lock()
        defer { stateLock.unlock() }
        var bufferType = Int32(bitPattern: V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue)
        _ = quill_v4l2_streamoff(fd, &bufferType)
        unmapRing()
        streaming = false
    }

    private func mapRing(bufferCount: UInt32 = 4) -> Bool {
        var request = v4l2_requestbuffers()
        request.count = bufferCount
        request.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
        request.memory = V4L2_MEMORY_MMAP.rawValue
        guard quill_v4l2_reqbufs(fd, &request) == 0, request.count >= 1 else { return false }

        for index in 0..<request.count {
            var buffer = v4l2_buffer()
            buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
            buffer.memory = V4L2_MEMORY_MMAP.rawValue
            buffer.index = index
            guard quill_v4l2_querybuf(fd, &buffer) == 0,
                  let base = mmap(nil, Int(buffer.length), PROT_READ | PROT_WRITE,
                                  MAP_SHARED, fd, off_t(buffer.m.offset)),
                  base != UnsafeMutableRawPointer(bitPattern: -1) // MAP_FAILED
            else {
                unmapRing()
                return false
            }
            ring.append((base: base, length: Int(buffer.length)))
            guard quill_v4l2_qbuf(fd, &buffer) == 0 else {
                unmapRing()
                return false
            }
        }
        return true
    }

    private func unmapRing() {
        for slot in ring {
            _ = munmap(slot.base, slot.length)
        }
        ring.removeAll()
    }

    private func captureLoop(frameHandler: FrameHandler) {
        while true {
            stateLock.lock()
            let shouldStop = stopRequested
            stateLock.unlock()
            if shouldStop { break }

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100) // 100ms tick so stop() stays responsive
            guard ready > 0, (descriptor.revents & Int16(POLLIN)) != 0 else { continue }

            var buffer = v4l2_buffer()
            buffer.type = V4L2_BUF_TYPE_VIDEO_CAPTURE.rawValue
            buffer.memory = V4L2_MEMORY_MMAP.rawValue
            guard quill_v4l2_dqbuf(fd, &buffer) == 0 else {
                if errno == EAGAIN { continue }
                break // unrecoverable (device unplugged, etc.)
            }

            let index = Int(buffer.index)
            if index < ring.count {
                let slot = ring[index]
                let pixelBuffer = CVPixelBuffer(width: frameWidth, height: frameHeight,
                                                pixelFormatType: kCVPixelFormatType_32BGRA)
                let converted = pixelBuffer.quillWithMutableBytes { destination -> Bool in
                    quillConvertYUYVToBGRA(
                        source: UnsafeRawBufferPointer(start: slot.base, count: slot.length),
                        sourceBytesPerRow: sourceBytesPerRow,
                        destination: destination,
                        destinationBytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                        width: frameWidth,
                        height: frameHeight)
                }
                if converted {
                    let timestamp = CMTime(
                        seconds: Double(buffer.timestamp.tv_sec)
                            + Double(buffer.timestamp.tv_usec) / 1_000_000,
                        preferredTimescale: 1_000_000)
                    frameHandler(pixelBuffer, timestamp)
                }
            }
            _ = quill_v4l2_qbuf(fd, &buffer) // hand the slot back to the driver
        }
        loopGroup.leave()
    }
}

#endif // canImport(CV4L2)

// MARK: - DiscoverySession backing

extension AVCaptureDevice {
    /// Real /dev/video* enumeration behind `DiscoverySession` (#515).
    /// Returns [] when the CV4L2 shim is not built or no capture nodes
    /// exist, preserving the previously inert discovery behavior. Devices
    /// carry their node path as `uniqueID` — the marker the session bridge
    /// keys on — and `.external` (USB cameras are the V4L2 mainline case).
    static func quillV4L2DiscoveredDevices() -> [AVCaptureDevice] {
        #if canImport(CV4L2)
        return QuillV4L2Camera.enumerateDevices().compactMap { info in
            guard let probe = QuillV4L2Camera(devicePath: info.path) else { return nil }
            let formats = probe.supportedFormats()
            // Prefer YUYV sizes (the format capture negotiates); fall back
            // to everything advertised so resolution pickers stay populated.
            let yuyvSizes = formats.first { $0.fourCC == quillV4L2PixelFormatYUYV }?.frameSizes
            let sizes = yuyvSizes ?? Array(Set(formats.flatMap(\.frameSizes)))

            let device = AVCaptureDevice()
            device.uniqueID = info.path
            device.localizedName = info.card.isEmpty ? info.path : info.card
            device.deviceType = .external
            device.formats = sizes
                .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
                .map { size in
                    AVCaptureDevice.Format(
                        formatDescription: CMFormatDescription(
                            codecType: quillV4L2PixelFormatYUYV,
                            dimensions: CMVideoDimensions(width: Int32(size.width),
                                                          height: Int32(size.height))),
                        videoSupportedFrameRateRanges: [
                            AVFrameRateRange(minFrameRate: 1, maxFrameRate: 30),
                        ])
                }
            if let best = device.formats.last {
                device.activeFormat = best
            }
            return device
        }
        #else
        return []
        #endif
    }
}

#endif // os(Linux)
