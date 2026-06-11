import Foundation
import CoreMedia

public let FFMPEG_AVSEEK_SIZE: Int32 = 0x10000
public let FFMPEG_CONSTANT_AVERROR_EOF: Int32 = -541_478_725

public let FFMpegCodecIdH264: Int32 = 27
public let FFMpegCodecIdHEVC: Int32 = 173
public let FFMpegCodecIdMPEG4: Int32 = 12
public let FFMpegCodecIdVP9: Int32 = 167
public let FFMpegCodecIdVP8: Int32 = 139
public let FFMpegCodecIdAV1: Int32 = 226

public enum FFMpegAVSampleFormat: Int32 {
    case none = -1
    case u8 = 0
    case s16 = 1
    case s32 = 2
    case flt = 3
    case dbl = 4
    case u8p = 5
    case s16p = 6
    case s32p = 7
    case fltp = 8
    case dblp = 9
    case s64 = 10
    case s64p = 11
    case nb = 12
}

public let FFMPEG_AV_SAMPLE_FMT_NONE = FFMpegAVSampleFormat.none
public let FFMPEG_AV_SAMPLE_FMT_U8 = FFMpegAVSampleFormat.u8
public let FFMPEG_AV_SAMPLE_FMT_S16 = FFMpegAVSampleFormat.s16
public let FFMPEG_AV_SAMPLE_FMT_S32 = FFMpegAVSampleFormat.s32
public let FFMPEG_AV_SAMPLE_FMT_FLT = FFMpegAVSampleFormat.flt
public let FFMPEG_AV_SAMPLE_FMT_DBL = FFMpegAVSampleFormat.dbl
public let FFMPEG_AV_SAMPLE_FMT_U8P = FFMpegAVSampleFormat.u8p
public let FFMPEG_AV_SAMPLE_FMT_S16P = FFMpegAVSampleFormat.s16p
public let FFMPEG_AV_SAMPLE_FMT_S32P = FFMpegAVSampleFormat.s32p
public let FFMPEG_AV_SAMPLE_FMT_FLTP = FFMpegAVSampleFormat.fltp
public let FFMPEG_AV_SAMPLE_FMT_DBLP = FFMpegAVSampleFormat.dblp
public let FFMPEG_AV_SAMPLE_FMT_S64 = FFMpegAVSampleFormat.s64
public let FFMPEG_AV_SAMPLE_FMT_S64P = FFMpegAVSampleFormat.s64p
public let FFMPEG_AV_SAMPLE_FMT_NB = FFMpegAVSampleFormat.nb

public enum FFMpegAVCodecContextReceiveResult: UInt {
    case error = 0
    case notEnoughData = 1
    case success = 2
}

public enum FFMpegAVFormatStreamType: Int32 {
    case video = 0
    case audio = 1
}

public let FFMpegAVFormatStreamTypeVideo = FFMpegAVFormatStreamType.video
public let FFMpegAVFormatStreamTypeAudio = FFMpegAVFormatStreamType.audio

public struct FFMpegFpsAndTimebase {
    public var fps: CMTime
    public var timebase: CMTime

    public init(fps: CMTime, timebase: CMTime) {
        self.fps = fps
        self.timebase = timebase
    }
}

public struct FFMpegStreamMetrics {
    public var width: Int32
    public var height: Int32
    public var rotationAngle: Double
    public var extradata: UnsafeMutablePointer<UInt8>
    public var extradataSize: Int32

    public init(width: Int32, height: Int32, rotationAngle: Double, extradata: UnsafeMutablePointer<UInt8>, extradataSize: Int32) {
        self.width = width
        self.height = height
        self.rotationAngle = rotationAngle
        self.extradata = extradata
        self.extradataSize = extradataSize
    }
}

public struct FFMpegAVIndexEntry {
    public var pos: Int64
    public var timestamp: Int64
    public var isKeyframe: Bool
    public var size: Int32

    public init(pos: Int64 = 0, timestamp: Int64 = 0, isKeyframe: Bool = false, size: Int32 = 0) {
        self.pos = pos
        self.timestamp = timestamp
        self.isKeyframe = isKeyframe
        self.size = size
    }
}

public enum FFMpegAVFrameColorRange: UInt {
    case restricted = 0
    case full = 1
}

public enum FFMpegAVFramePixelFormat: UInt {
    case YUV = 0
    case YUVA = 1
}

public enum FFMpegAVFrameNativePixelFormat: UInt {
    case unknown = 0
    case videoToolbox = 1
}

private enum FFMpegEmptyByteBuffer {
    static let pointer: UnsafeMutablePointer<UInt8> = {
        let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        pointer.initialize(to: 0)
        return pointer
    }()
}

public final class FFMpegAVCodec: NSObject {
    public static func find(forId codecId: Int32, preferHardwareAccelerationCapable: Bool) -> FFMpegAVCodec? {
        FFMpegAVCodec(codecId: codecId)
    }

    private let codecId: Int32

    public init(codecId: Int32 = 0) {
        self.codecId = codecId
        super.init()
    }

    public func impl() -> UnsafeMutableRawPointer? {
        nil
    }
}

public final class FFMpegAVCodecContext: NSObject {
    private let codec: FFMpegAVCodec

    public init(codec: FFMpegAVCodec) {
        self.codec = codec
        super.init()
    }

    public func impl() -> UnsafeMutableRawPointer? {
        nil
    }

    public func channels() -> Int32 {
        2
    }

    public func sampleRate() -> Int32 {
        44_100
    }

    public func sampleFormat() -> FFMpegAVSampleFormat {
        .s16
    }

    public func open() -> Bool {
        true
    }

    public func sendEnd() -> Bool {
        true
    }

    public func setupHardwareAccelerationIfPossible() {
    }

    public func receive(into frame: FFMpegAVFrame) -> FFMpegAVCodecContextReceiveResult {
        .notEnoughData
    }

    public func flushBuffers() {
    }
}

public final class FFMpegAVFormatContext: NSObject {
    private var ioContext: FFMpegAVIOContext?
    private var forcedVideoCodecId: Int32?

    public override init() {
        super.init()
    }

    public func setIO(_ ioContext: FFMpegAVIOContext) {
        self.ioContext = ioContext
    }

    public func openInput(withDirectFilePath directFilePath: String?) -> Bool {
        false
    }

    public func findStreamInfo() -> Bool {
        false
    }

    public func seekFrame(forStreamIndex streamIndex: Int32, pts: Int64, positionOnKeyframe: Bool) {
    }

    public func seekFrame(forStreamIndex streamIndex: Int32, byteOffset: Int64) {
    }

    public func readFrame(into packet: FFMpegPacket) -> Bool {
        false
    }

    public func streamIndices(for type: FFMpegAVFormatStreamType) -> [NSNumber] {
        []
    }

    public func isAttachedPic(atStreamIndex streamIndex: Int32) -> Bool {
        false
    }

    public func codecId(atStreamIndex streamIndex: Int32) -> Int32 {
        forcedVideoCodecId ?? FFMpegCodecIdH264
    }

    public func duration() -> Double {
        0.0
    }

    public func startTime(atStreamIndex streamIndex: Int32) -> Int64 {
        0
    }

    public func duration(atStreamIndex streamIndex: Int32) -> Int64 {
        0
    }

    public func numberOfIndexEntries(atStreamIndex streamIndex: Int32) -> Int32 {
        0
    }

    public func fillIndexEntry(atStreamIndex streamIndex: Int32, entryIndex: Int32, outEntry: UnsafeMutablePointer<FFMpegAVIndexEntry>) -> Bool {
        outEntry.pointee = FFMpegAVIndexEntry()
        return false
    }

    public func codecParams(atStreamIndex streamIndex: Int32, to context: FFMpegAVCodecContext) -> Bool {
        true
    }

    public func fpsAndTimebase(forStreamIndex streamIndex: Int32, defaultTimeBase: CMTime) -> FFMpegFpsAndTimebase {
        FFMpegFpsAndTimebase(
            fps: CMTime(value: 1, timescale: 30),
            timebase: defaultTimeBase
        )
    }

    public func metricsForStream(at streamIndex: Int32) -> FFMpegStreamMetrics {
        FFMpegStreamMetrics(
            width: 1,
            height: 1,
            rotationAngle: 0.0,
            extradata: FFMpegEmptyByteBuffer.pointer,
            extradataSize: 0
        )
    }

    public func forceVideoCodecId(_ videoCodecId: Int32) {
        self.forcedVideoCodecId = videoCodecId
    }
}

public final class FFMpegAVFrame: NSObject {
    public let width: Int32
    public let height: Int32
    public let data: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>
    public let lineSize: UnsafeMutablePointer<Int>
    public var pts: Int64
    public var duration: Int64
    public let colorRange: FFMpegAVFrameColorRange
    public let pixelFormat: FFMpegAVFramePixelFormat

    private var allocatedPlanes: [UnsafeMutablePointer<UInt8>] = []

    public override convenience init() {
        self.init(pixelFormat: .YUV, width: 0, height: 0, allocatePlanes: false)
    }

    public convenience init(pixelFormat: FFMpegAVFramePixelFormat, width: Int32, height: Int32) {
        self.init(pixelFormat: pixelFormat, width: width, height: height, allocatePlanes: true)
    }

    private init(pixelFormat: FFMpegAVFramePixelFormat, width: Int32, height: Int32, allocatePlanes: Bool) {
        self.width = width
        self.height = height
        self.pts = 0
        self.duration = 0
        self.colorRange = .restricted
        self.pixelFormat = pixelFormat
        self.data = UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: 4)
        self.lineSize = UnsafeMutablePointer<Int>.allocate(capacity: 4)

        for index in 0 ..< 4 {
            self.data.advanced(by: index).initialize(to: nil)
            self.lineSize.advanced(by: index).initialize(to: 0)
        }

        super.init()

        if allocatePlanes {
            allocateImagePlanes(pixelFormat: pixelFormat, width: width, height: height)
        }
    }

    deinit {
        for plane in allocatedPlanes {
            plane.deallocate()
        }
        data.deinitialize(count: 4)
        data.deallocate()
        lineSize.deinitialize(count: 4)
        lineSize.deallocate()
    }

    public func impl() -> UnsafeMutableRawPointer? {
        nil
    }

    public func nativePixelFormat() -> FFMpegAVFrameNativePixelFormat {
        .unknown
    }

    private func allocateImagePlanes(pixelFormat: FFMpegAVFramePixelFormat, width: Int32, height: Int32) {
        let safeWidth = max(Int(width), 1)
        let safeHeight = max(Int(height), 1)

        func allocatePlane(index: Int, stride: Int, rows: Int) {
            let byteCount = max(stride * rows, 1)
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
            pointer.initialize(repeating: 0, count: byteCount)
            allocatedPlanes.append(pointer)
            data[index] = pointer
            lineSize[index] = stride
        }

        allocatePlane(index: 0, stride: safeWidth, rows: safeHeight)
        allocatePlane(index: 1, stride: max(safeWidth / 2, 1), rows: max(safeHeight / 2, 1))
        allocatePlane(index: 2, stride: max(safeWidth / 2, 1), rows: max(safeHeight / 2, 1))

        if pixelFormat == .YUVA {
            allocatePlane(index: 3, stride: safeWidth, rows: safeHeight)
        }
    }
}

public final class FFMpegAVIOContext: NSObject {
    public typealias ReadPacketCallback = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32
    public typealias WritePacketCallback = (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int32) -> Int32
    public typealias SeekCallback = (UnsafeMutableRawPointer?, Int64, Int32) -> Int64

    public let bufferSize: Int32
    public let opaqueContext: UnsafeMutableRawPointer?
    public let readPacket: ReadPacketCallback?
    public let writePacket: WritePacketCallback?
    public let seek: SeekCallback?
    public let isSeekable: Bool

    public init?(bufferSize: Int32, opaqueContext: UnsafeMutableRawPointer?, readPacket: ReadPacketCallback?, writePacket: WritePacketCallback?, seek: SeekCallback?, isSeekable: Bool) {
        self.bufferSize = bufferSize
        self.opaqueContext = opaqueContext
        self.readPacket = readPacket
        self.writePacket = writePacket
        self.seek = seek
        self.isSeekable = isSeekable
        super.init()
    }

    public func impl() -> UnsafeMutableRawPointer? {
        nil
    }
}

public final class FFMpegPacket: NSObject {
    public var pts: Int64 = 0
    public var dts: Int64 = 0
    public var duration: Int64 = 0
    public var streamIndex: Int32 = 0
    public var size: Int32 = 0
    public var data: UnsafeMutablePointer<UInt8> = FFMpegEmptyByteBuffer.pointer
    public var isKeyframe: Bool = false

    public override init() {
        super.init()
    }

    public func impl() -> UnsafeMutableRawPointer? {
        nil
    }

    public func send(toDecoder codecContext: FFMpegAVCodecContext) -> Int32 {
        0
    }

    public func reuse() {
    }
}

public final class FFMpegSWResample: NSObject {
    public init(sourceChannelCount: Int, sourceSampleRate: Int, sourceSampleFormat: FFMpegAVSampleFormat, destinationChannelCount: Int, destinationSampleRate: Int, destinationSampleFormat: FFMpegAVSampleFormat) {
        super.init()
    }

    public func resample(_ frame: FFMpegAVFrame) -> Data? {
        nil
    }
}

public final class FFMpegGlobals: NSObject {
    public static func initializeGlobals() {
    }
}

public final class FFMpegLiveMuxer: NSObject {
    public static func remux(_ path: String, to outPath: String, offsetSeconds: Double) -> Bool {
        false
    }
}

public final class FFMpegOpusTrimmer: NSObject {
    public static func trim(_ path: String, to outputPath: String, start: Double, end: Double) -> Bool {
        false
    }
}

public final class FFMpegRemuxer: NSObject {
    public static func remux(_ path: String, to outPath: String) -> Bool {
        false
    }
}

public final class FFMpegVideoWriter: NSObject {
    public override init() {
        super.init()
    }

    public func setup(withOutputPath outputPath: String, width: Int32, height: Int32, bitrate: Int64, framerate: Int32) -> Bool {
        false
    }

    public func encode(_ frame: FFMpegAVFrame) -> Bool {
        false
    }

    public func finalizeVideo() -> Bool {
        false
    }
}

public func fillDstPlane(_ dstPlane: UnsafeMutablePointer<UInt8>, _ srcPlane1: UnsafeMutablePointer<UInt8>, _ srcPlane2: UnsafeMutablePointer<UInt8>, _ srcPlaneSize: Int) {
    guard srcPlaneSize > 0 else {
        return
    }

    for index in 0 ..< srcPlaneSize {
        dstPlane[index * 2] = srcPlane1[index]
        dstPlane[index * 2 + 1] = srcPlane2[index]
    }
}
