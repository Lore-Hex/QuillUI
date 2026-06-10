import Foundation
@_exported import CoreFoundation
@_exported import CoreVideo
@_exported import AudioToolbox
@_exported import QuillFoundation

public typealias CMTimeValue = Int64
public typealias CMTimeScale = Int32
public typealias CMTimeEpoch = Int64
public typealias CMVideoCodecType = UInt32
public typealias CMItemCount = Int

public let noErr: OSStatus = 0
public let kCMBlockBufferNoErr: OSStatus = 0
public let kCMAttachmentMode_ShouldPropagate: CMAttachmentMode = 1
public let kCMSampleAttachmentKey_DisplayImmediately = "DisplayImmediately"
public let kCMSampleAttachmentKey_DoNotDisplay = "DoNotDisplay"
public let kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding = "ResetDecoderBeforeDecoding"
public let kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration = "EndsPreviousSampleDuration"

public let kCMVideoCodecType_MPEG4Video: CMVideoCodecType = 0x6d70_3476 // "mp4v"
public let kCMVideoCodecType_H264: CMVideoCodecType = 0x6176_6331 // "avc1"
public let kCMVideoCodecType_HEVC: CMVideoCodecType = 0x6876_6331 // "hvc1"
public let kCMVideoCodecType_AV1: CMVideoCodecType = 0x6176_3031 // "av01"

public struct CMTimeFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let valid = CMTimeFlags(rawValue: 1 << 0)
    public static let hasBeenRounded = CMTimeFlags(rawValue: 1 << 1)
    public static let positiveInfinity = CMTimeFlags(rawValue: 1 << 2)
    public static let negativeInfinity = CMTimeFlags(rawValue: 1 << 3)
    public static let indefinite = CMTimeFlags(rawValue: 1 << 4)
}

public struct CMTime: Sendable, Equatable, Hashable {
    public var value: CMTimeValue
    public var timescale: CMTimeScale
    public var flags: CMTimeFlags
    public var epoch: CMTimeEpoch

    public init(value: CMTimeValue, timescale: CMTimeScale, flags: CMTimeFlags = .valid, epoch: CMTimeEpoch = 0) {
        self.value = value
        self.timescale = timescale
        self.flags = flags
        self.epoch = epoch
    }

    public init(seconds: Double, preferredTimescale: CMTimeScale) {
        self.init(value: CMTimeValue(seconds * Double(preferredTimescale)), timescale: preferredTimescale)
    }

    public var seconds: Double {
        guard timescale != 0 else { return 0 }
        return Double(value) / Double(timescale)
    }

    public static let zero = CMTime(value: 0, timescale: 1)
    public static let invalid = CMTime(value: 0, timescale: 0, flags: [])
    public static let indefinite = CMTime(value: 0, timescale: 0, flags: .indefinite)
}

public let kCMTimeZero = CMTime.zero
public let kCMTimeInvalid = CMTime.invalid
public let kCMTimeIndefinite = CMTime.indefinite

public func CMTimeMake(value: CMTimeValue, timescale: CMTimeScale) -> CMTime {
    CMTime(value: value, timescale: timescale)
}

public func CMTimeMakeWithSeconds(_ seconds: Double, preferredTimescale: CMTimeScale) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: preferredTimescale)
}

public func CMTimeGetSeconds(_ time: CMTime) -> Double {
    time.seconds
}

public enum CMTimeRoundingMethod: Int32, Sendable {
    case roundHalfAwayFromZero = 1
    case roundTowardZero = 2
    case roundAwayFromZero = 3
    case quickTime = 4
    case roundTowardPositiveInfinity = 5
    case roundTowardNegativeInfinity = 6
}

public func CMTimeCompare(_ lhs: CMTime, _ rhs: CMTime) -> Int32 {
    if lhs.seconds < rhs.seconds { return -1 }
    if lhs.seconds > rhs.seconds { return 1 }
    return 0
}

public func CMTimeAdd(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    let scale = lhs.timescale != 0 ? lhs.timescale : max(rhs.timescale, 1)
    return CMTime(seconds: lhs.seconds + rhs.seconds, preferredTimescale: scale)
}

public func CMTimeSubtract(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    let scale = lhs.timescale != 0 ? lhs.timescale : max(rhs.timescale, 1)
    return CMTime(seconds: lhs.seconds - rhs.seconds, preferredTimescale: scale)
}

public func CMTimeMaximum(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
    CMTimeCompare(lhs, rhs) >= 0 ? lhs : rhs
}

public func CMTimeConvertScale(_ time: CMTime, timescale: CMTimeScale, method: CMTimeRoundingMethod) -> CMTime {
    _ = method
    return CMTime(seconds: time.seconds, preferredTimescale: timescale)
}

public final class CMBlockBuffer: @unchecked Sendable {
    public var memoryBlock: UnsafeMutableRawPointer?
    public var dataLength: Int

    public init(memoryBlock: UnsafeMutableRawPointer? = nil, dataLength: Int = 0) {
        self.memoryBlock = memoryBlock
        self.dataLength = dataLength
    }
}

public final class CMSampleBuffer: @unchecked Sendable {
    public var dataBuffer: CMBlockBuffer?
    public var formatDescription: CMFormatDescription?
    public var timingInfo: [CMSampleTimingInfo]
    public var sampleCount: CMItemCount
    public var sampleSizes: [Int]
    public var imageBuffer: CVImageBuffer?
    public let attachments: NSMutableArray

    public init(
        dataBuffer: CMBlockBuffer? = nil,
        formatDescription: CMFormatDescription? = nil,
        timingInfo: [CMSampleTimingInfo] = [],
        sampleCount: CMItemCount = 0,
        sampleSizes: [Int] = [],
        imageBuffer: CVImageBuffer? = nil
    ) {
        self.dataBuffer = dataBuffer
        self.formatDescription = formatDescription
        self.timingInfo = timingInfo
        self.sampleCount = sampleCount
        self.sampleSizes = sampleSizes
        self.imageBuffer = imageBuffer
        self.attachments = NSMutableArray(object: NSMutableDictionary())
    }
}

public final class CMFormatDescription: @unchecked Sendable {
    public var codecType: CMVideoCodecType?
    public var dimensions: CMVideoDimensions
    public var audioStreamBasicDescription: AudioStreamBasicDescription?

    public init(
        codecType: CMVideoCodecType? = nil,
        dimensions: CMVideoDimensions = CMVideoDimensions(),
        audioStreamBasicDescription: AudioStreamBasicDescription? = nil
    ) {
        self.codecType = codecType
        self.dimensions = dimensions
        self.audioStreamBasicDescription = audioStreamBasicDescription
    }
}

public typealias CMVideoFormatDescription = CMFormatDescription
public typealias CMAudioFormatDescription = CMFormatDescription
public typealias CMAttachmentMode = UInt32

public final class CMClock: @unchecked Sendable {
    public init() {}
}

public typealias CMClockOrTimebase = AnyObject

public final class CMTimebase: @unchecked Sendable {
    public var rate: Double
    public var time: CMTime
    public var master: CMClockOrTimebase?

    public init(rate: Double = 0, time: CMTime = .zero, master: CMClockOrTimebase? = nil) {
        self.rate = rate
        self.time = time
        self.master = master
    }
}

public struct CMTimeRange: Sendable, Equatable {
    public var start: CMTime
    public var duration: CMTime

    public init(start: CMTime, duration: CMTime) {
        self.start = start
        self.duration = duration
    }
}

public func CMTimeRangeMake(start: CMTime, duration: CMTime) -> CMTimeRange {
    CMTimeRange(start: start, duration: duration)
}

public struct CMSampleTimingInfo: Sendable {
    public var duration: CMTime
    public var presentationTimeStamp: CMTime
    public var decodeTimeStamp: CMTime

    public init(duration: CMTime = .invalid, presentationTimeStamp: CMTime = .zero, decodeTimeStamp: CMTime = .invalid) {
        self.duration = duration
        self.presentationTimeStamp = presentationTimeStamp
        self.decodeTimeStamp = decodeTimeStamp
    }
}

public struct CMVideoDimensions: Sendable {
    public var width: Int32
    public var height: Int32

    public init(width: Int32 = 0, height: Int32 = 0) {
        self.width = width
        self.height = height
    }
}

public func CMSampleBufferGetDataBuffer(_ sbuf: CMSampleBuffer) -> CMBlockBuffer? {
    sbuf.dataBuffer
}

public func CMSampleBufferGetNumSamples(_ sbuf: CMSampleBuffer) -> CMItemCount {
    sbuf.sampleCount
}

public func CMSampleBufferInvalidate(_ sbuf: CMSampleBuffer) {
    _ = sbuf
}

public func CMSampleBufferGetFormatDescription(_ sbuf: CMSampleBuffer) -> CMFormatDescription? {
    sbuf.formatDescription
}

public func CMVideoFormatDescriptionGetDimensions(_ formatDescription: CMVideoFormatDescription) -> CMVideoDimensions {
    formatDescription.dimensions
}

public func CMSampleBufferGetDuration(_ sbuf: CMSampleBuffer) -> CMTime {
    sbuf.timingInfo.first?.duration ?? .invalid
}

public func CMSampleBufferGetPresentationTimeStamp(_ sbuf: CMSampleBuffer) -> CMTime {
    sbuf.timingInfo.first?.presentationTimeStamp ?? .zero
}

public func CMSampleBufferGetImageBuffer(_ sbuf: CMSampleBuffer) -> CVImageBuffer? {
    sbuf.imageBuffer
}

public func CMSampleBufferGetSampleAttachmentsArray(_ sbuf: CMSampleBuffer, createIfNecessary: Bool) -> NSMutableArray? {
    _ = createIfNecessary
    return sbuf.attachments
}

public func CMSetAttachment(_ target: AnyObject, key: NSString, value: AnyObject, attachmentMode: CMAttachmentMode) {
    _ = attachmentMode
    if let sampleBuffer = target as? CMSampleBuffer {
        let dictionary: NSMutableDictionary
        if let existing = sampleBuffer.attachments.firstObject as? NSMutableDictionary {
            dictionary = existing
        } else {
            dictionary = NSMutableDictionary()
            sampleBuffer.attachments.add(dictionary)
        }
        dictionary[key] = value
    }
}

public func CMBlockBufferGetDataPointer(
    _ buffer: CMBlockBuffer,
    atOffset offset: Int,
    lengthAtOffsetOut: UnsafeMutablePointer<Int>?,
    totalLengthOut: UnsafeMutablePointer<Int>?,
    dataPointerOut: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
) -> OSStatus {
    guard let memoryBlock = buffer.memoryBlock else {
        lengthAtOffsetOut?.pointee = 0
        totalLengthOut?.pointee = 0
        dataPointerOut?.pointee = nil
        return -1
    }
    let clampedOffset = min(max(0, offset), buffer.dataLength)
    lengthAtOffsetOut?.pointee = buffer.dataLength - clampedOffset
    totalLengthOut?.pointee = buffer.dataLength
    dataPointerOut?.pointee = memoryBlock.advanced(by: clampedOffset).assumingMemoryBound(to: Int8.self)
    return noErr
}

public func CMBlockBufferGetDataLength(_ buffer: CMBlockBuffer) -> Int {
    buffer.dataLength
}

public func CMBlockBufferCopyDataBytes(
    _ buffer: CMBlockBuffer,
    atOffset offset: Int,
    dataLength: Int,
    destination: UnsafeMutableRawPointer
) -> OSStatus {
    guard let memoryBlock = buffer.memoryBlock else {
        return -1
    }
    let clampedOffset = min(max(0, offset), buffer.dataLength)
    let clampedLength = min(max(0, dataLength), buffer.dataLength - clampedOffset)
    memcpy(destination, memoryBlock.advanced(by: clampedOffset), clampedLength)
    return noErr
}

public func CMBlockBufferCreateWithMemoryBlock(
    allocator: Any?,
    memoryBlock: UnsafeMutableRawPointer?,
    blockLength: Int,
    blockAllocator: Any?,
    customBlockSource: Any?,
    offsetToData: Int,
    dataLength: Int,
    flags: UInt32,
    blockBufferOut: inout CMBlockBuffer?
) -> OSStatus {
    _ = (allocator, blockAllocator, customBlockSource, offsetToData, flags)
    blockBufferOut = CMBlockBuffer(memoryBlock: memoryBlock, dataLength: min(blockLength, dataLength))
    return noErr
}

public func CMVideoFormatDescriptionCreate(
    allocator: Any?,
    codecType: CMVideoCodecType,
    width: Int32,
    height: Int32,
    extensions: Any?,
    formatDescriptionOut: inout CMVideoFormatDescription?
) -> OSStatus {
    _ = (allocator, extensions)
    formatDescriptionOut = CMFormatDescription(
        codecType: codecType,
        dimensions: CMVideoDimensions(width: width, height: height)
    )
    return noErr
}

public func CMVideoFormatDescriptionCreateForImageBuffer(
    allocator: Any?,
    imageBuffer: CVImageBuffer,
    formatDescriptionOut: inout CMVideoFormatDescription?
) -> OSStatus {
    _ = allocator
    formatDescriptionOut = CMFormatDescription(
        dimensions: CMVideoDimensions(
            width: Int32(CVPixelBufferGetWidth(imageBuffer)),
            height: Int32(CVPixelBufferGetHeight(imageBuffer))
        )
    )
    return noErr
}

public func CMAudioFormatDescriptionCreate(
    allocator: Any?,
    asbd: UnsafePointer<AudioStreamBasicDescription>,
    layoutSize: Int,
    layout: UnsafePointer<AudioChannelLayout>?,
    magicCookieSize: Int,
    magicCookie: UnsafeRawPointer?,
    extensions: Any?,
    formatDescriptionOut: inout CMAudioFormatDescription?
) -> OSStatus {
    _ = (allocator, layoutSize, layout, magicCookieSize, magicCookie, extensions)
    formatDescriptionOut = CMFormatDescription(audioStreamBasicDescription: asbd.pointee)
    return noErr
}

public func CMAudioFormatDescriptionGetStreamBasicDescription(_ desc: CMAudioFormatDescription) -> UnsafePointer<AudioStreamBasicDescription>? {
    guard let streamDescription = desc.audioStreamBasicDescription else {
        return nil
    }
    let pointer = UnsafeMutablePointer<AudioStreamBasicDescription>.allocate(capacity: 1)
    pointer.initialize(to: streamDescription)
    return UnsafePointer(pointer)
}

public func CMSampleBufferCreate(
    allocator: Any?,
    dataBuffer: CMBlockBuffer?,
    dataReady: Bool,
    makeDataReadyCallback: Any?,
    refcon: UnsafeMutableRawPointer?,
    formatDescription: CMFormatDescription?,
    sampleCount: CMItemCount,
    sampleTimingEntryCount: CMItemCount,
    sampleTimingArray: UnsafePointer<CMSampleTimingInfo>?,
    sampleSizeEntryCount: CMItemCount,
    sampleSizeArray: UnsafePointer<Int>?,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    _ = (allocator, dataReady, makeDataReadyCallback, refcon)
    let timings = (0..<sampleTimingEntryCount).map { index in
        sampleTimingArray?[index] ?? CMSampleTimingInfo()
    }
    let sizes = (0..<sampleSizeEntryCount).map { index in
        sampleSizeArray?[index] ?? 0
    }
    sampleBufferOut = CMSampleBuffer(
        dataBuffer: dataBuffer,
        formatDescription: formatDescription,
        timingInfo: timings,
        sampleCount: sampleCount,
        sampleSizes: sizes
    )
    return noErr
}

public func CMSampleBufferCreateForImageBuffer(
    allocator: Any?,
    imageBuffer: CVImageBuffer,
    dataReady: Bool,
    makeDataReadyCallback: Any?,
    refcon: UnsafeMutableRawPointer?,
    formatDescription: CMVideoFormatDescription,
    sampleTiming: UnsafePointer<CMSampleTimingInfo>,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    _ = (allocator, dataReady, makeDataReadyCallback, refcon)
    sampleBufferOut = CMSampleBuffer(
        formatDescription: formatDescription,
        timingInfo: [sampleTiming.pointee],
        sampleCount: 1,
        imageBuffer: imageBuffer
    )
    return noErr
}

public func CMSampleBufferCreateReadyWithImageBuffer(
    allocator: Any?,
    imageBuffer: CVImageBuffer,
    formatDescription: CMVideoFormatDescription,
    sampleTiming: UnsafePointer<CMSampleTimingInfo>,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    CMSampleBufferCreateForImageBuffer(
        allocator: allocator,
        imageBuffer: imageBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDescription,
        sampleTiming: sampleTiming,
        sampleBufferOut: &sampleBufferOut
    )
}

public func CMAudioSampleBufferCreateReadyWithPacketDescriptions(
    allocator: Any?,
    dataBuffer: CMBlockBuffer,
    formatDescription: CMAudioFormatDescription,
    sampleCount: CMItemCount,
    presentationTimeStamp: CMTime,
    packetDescriptions: UnsafePointer<Any>?,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    _ = (allocator, packetDescriptions)
    let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: presentationTimeStamp, decodeTimeStamp: .invalid)
    sampleBufferOut = CMSampleBuffer(
        dataBuffer: dataBuffer,
        formatDescription: formatDescription,
        timingInfo: [timing],
        sampleCount: sampleCount
    )
    return noErr
}

public func CMSampleBufferGetSampleTimingInfoArray(
    _ sbuf: CMSampleBuffer,
    entryCount: CMItemCount,
    arrayToFill: UnsafeMutablePointer<CMSampleTimingInfo>?,
    entriesNeededOut: UnsafeMutablePointer<CMItemCount>?
) -> OSStatus {
    entriesNeededOut?.pointee = sbuf.timingInfo.count
    guard let arrayToFill else {
        return noErr
    }
    for index in 0..<min(entryCount, sbuf.timingInfo.count) {
        arrayToFill[index] = sbuf.timingInfo[index]
    }
    return noErr
}

public func CMSampleBufferCreateCopyWithNewTiming(
    allocator: Any?,
    sampleBuffer: CMSampleBuffer,
    sampleTimingEntryCount: CMItemCount,
    sampleTimingArray: UnsafePointer<CMSampleTimingInfo>?,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    _ = allocator
    let timings = (0..<sampleTimingEntryCount).map { index in
        sampleTimingArray?[index] ?? CMSampleTimingInfo()
    }
    sampleBufferOut = CMSampleBuffer(
        dataBuffer: sampleBuffer.dataBuffer,
        formatDescription: sampleBuffer.formatDescription,
        timingInfo: timings,
        sampleCount: sampleBuffer.sampleCount,
        sampleSizes: sampleBuffer.sampleSizes,
        imageBuffer: sampleBuffer.imageBuffer
    )
    return noErr
}

public func CMSampleBufferCreateCopy(
    allocator: Any?,
    sampleBuffer: CMSampleBuffer,
    sampleBufferOut: inout CMSampleBuffer?
) -> OSStatus {
    _ = allocator
    sampleBufferOut = CMSampleBuffer(
        dataBuffer: sampleBuffer.dataBuffer,
        formatDescription: sampleBuffer.formatDescription,
        timingInfo: sampleBuffer.timingInfo,
        sampleCount: sampleBuffer.sampleCount,
        sampleSizes: sampleBuffer.sampleSizes,
        imageBuffer: sampleBuffer.imageBuffer
    )
    return noErr
}

public func CMClockGetHostTimeClock() -> CMClock {
    CMClock()
}

public func CMSyncGetTime(_ clockOrTimebase: CMClockOrTimebase) -> CMTime {
    if let timebase = clockOrTimebase as? CMTimebase {
        return timebase.time
    }
    return CMTime(seconds: ProcessInfo.processInfo.systemUptime, preferredTimescale: 1_000_000)
}

public func CMTimebaseCreateWithMasterClock(
    allocator: Any?,
    masterClock: CMClock,
    timebaseOut: inout CMTimebase?
) -> OSStatus {
    _ = allocator
    timebaseOut = CMTimebase(master: masterClock)
    return noErr
}

public func CMTimebaseCreateWithSourceClock(
    allocator: Any?,
    sourceClock: CMClock?,
    timebaseOut: inout CMTimebase?
) -> OSStatus {
    _ = allocator
    timebaseOut = CMTimebase(master: sourceClock ?? CMClockGetHostTimeClock())
    return noErr
}

public func CMTimebaseGetMaster(_ timebase: CMTimebase) -> CMClockOrTimebase? {
    timebase.master
}

public func CMTimebaseGetRate(_ timebase: CMTimebase) -> Double {
    timebase.rate
}

@discardableResult
public func CMTimebaseSetRate(_ timebase: CMTimebase, rate: Double) -> OSStatus {
    timebase.rate = rate
    return noErr
}

public func CMTimebaseGetTime(_ timebase: CMTimebase) -> CMTime {
    timebase.time
}

@discardableResult
public func CMTimebaseSetTime(_ timebase: CMTimebase, time: CMTime) -> OSStatus {
    timebase.time = time
    return noErr
}

@discardableResult
public func CMTimebaseSetRateAndAnchorTime(
    _ timebase: CMTimebase,
    rate: Double,
    anchorTime: CMTime,
    immediateMasterTime: CMTime
) -> OSStatus {
    _ = immediateMasterTime
    timebase.rate = rate
    timebase.time = anchorTime
    return noErr
}

@discardableResult
public func CMTimebaseAddTimer(_ timebase: CMTimebase, timer: CFRunLoopTimer, runloop: CFRunLoop) -> OSStatus {
    _ = (timebase, timer, runloop)
    return noErr
}

@discardableResult
public func CMTimebaseRemoveTimer(_ timebase: CMTimebase, timer: CFRunLoopTimer) -> OSStatus {
    _ = (timebase, timer)
    return noErr
}

@discardableResult
public func CMTimebaseSetTimerNextFireTime(_ timebase: CMTimebase, timer: CFRunLoopTimer, fireTime: CMTime, flags: UInt32) -> OSStatus {
    _ = (timebase, timer, fireTime, flags)
    return noErr
}

@discardableResult
public func CMAudioDeviceClockCreateFromAudioDeviceID(allocator: Any?, deviceID: AudioDeviceID, clockOut: inout CMClock?) -> OSStatus {
    _ = (allocator, deviceID)
    clockOut = CMClock()
    return noErr
}

@discardableResult
public func CMAudioDeviceClockCreate(allocator: Any?, clockOut: inout CMClock?) -> OSStatus {
    _ = allocator
    clockOut = CMClock()
    return noErr
}

@discardableResult
public func CMAudioDeviceClockCreate(allocator: Any?, deviceUID: CFString?, clockOut: inout CMClock?) -> OSStatus {
    _ = (allocator, deviceUID)
    clockOut = CMClock()
    return noErr
}
