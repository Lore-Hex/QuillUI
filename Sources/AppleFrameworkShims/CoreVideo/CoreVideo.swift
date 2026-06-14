import Foundation
@_exported import Metal
@_exported import QuillFoundation

public typealias CVReturn = Int32
public typealias CVOptionFlags = UInt64
public typealias OSType = UInt32

public final class CVImageBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let pixelFormatType: OSType
    private var storage: [UInt8]

    public init(width: Int, height: Int, pixelFormatType: OSType) {
        self.width = width
        self.height = height
        self.pixelFormatType = pixelFormatType
        self.storage = Array(repeating: 0, count: max(1, width * height * 4))
    }

    fileprivate func withBaseAddress<R>(_ body: (UnsafeMutableRawPointer?) -> R) -> R {
        storage.withUnsafeMutableBytes { buffer in
            body(buffer.baseAddress)
        }
    }

    /// Safe scoped read access for bridges (CoreImage's CIImage(cvPixelBuffer:)
    /// path and, eventually, encoders). Keeps `storage` private while letting
    /// other shims copy frame bytes without the escaping-pointer hazards of
    /// the C-style accessor functions.
    public func quillWithReadOnlyBytes<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
        storage.withUnsafeBytes(body)
    }

    /// Mutable scoped access — the V4L2 capture path (#515) writes converted
    /// BGRA frames through this.
    public func quillWithMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) -> R) -> R {
        storage.withUnsafeMutableBytes(body)
    }
}

/// Apple's CoreVideo models CVPixelBuffer as a typealias of CVImageBuffer;
/// mirroring that shape keeps `as CVImageBuffer` / `as CVPixelBuffer`
/// conversions in upstream sources compiling unchanged.
public typealias CVPixelBuffer = CVImageBuffer
public final class CVPixelBufferPool: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let pixelFormatType: OSType

    public init(width: Int, height: Int, pixelFormatType: OSType) {
        self.width = width
        self.height = height
        self.pixelFormatType = pixelFormatType
    }
}

public typealias CVDisplayLink = OpaquePointer

public let kCVReturnSuccess: CVReturn = 0
public let kCVReturnError: CVReturn = -6660
public let kCVReturnWouldExceedAllocationThreshold: CVReturn = -6689
public let kCVPixelFormatType_32ARGB: OSType = 0x00000020
public let kCVPixelFormatType_32BGRA: OSType = 0x42475241
public let kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: OSType = 0x34323066
public let kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: OSType = 0x34323076
public let kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar: OSType = 0x76306138
public let kCVPixelBufferIOSurfacePropertiesKey = "IOSurfaceProperties"
public let kCVPixelBufferPixelFormatTypeKey = "PixelFormatType"
public let kCVPixelBufferWidthKey = "Width"
public let kCVPixelBufferHeightKey = "Height"
public let kCVPixelBufferBytesPerRowAlignmentKey = "BytesPerRowAlignment"
public let kCVPixelBufferPoolMinimumBufferCountKey = "MinimumBufferCount"
public let kCVPixelBufferPoolAllocationThresholdKey = "AllocationThreshold"

public struct CVTimeStamp: Sendable {
    public init() {}
}

public struct CVPixelBufferLockFlags: OptionSet, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let readOnly = CVPixelBufferLockFlags(rawValue: 1 << 0)
}

public func CGMainDisplayID() -> UInt32 {
    0
}

public func CVDisplayLinkCreateWithCGDisplay(_ displayID: UInt32, _ displayLinkOut: inout CVDisplayLink?) -> CVReturn {
    _ = displayID
    displayLinkOut = OpaquePointer(bitPattern: 1)
    return kCVReturnSuccess
}

public func CVDisplayLinkSetOutputCallback(
    _ displayLink: CVDisplayLink,
    _ callback: @escaping (
        CVDisplayLink,
        UnsafePointer<CVTimeStamp>,
        UnsafePointer<CVTimeStamp>,
        CVOptionFlags,
        UnsafeMutablePointer<CVOptionFlags>,
        UnsafeMutableRawPointer?
    ) -> CVReturn,
    _ userInfo: UnsafeMutableRawPointer?
) -> CVReturn {
    _ = (displayLink, callback, userInfo)
    return kCVReturnSuccess
}

public func CVDisplayLinkSetCurrentCGDisplay(_ displayLink: CVDisplayLink, _ displayID: UInt32) -> CVReturn {
    _ = (displayLink, displayID)
    return kCVReturnSuccess
}

public func CVDisplayLinkIsRunning(_ displayLink: CVDisplayLink) -> Bool {
    _ = displayLink
    return false
}

public func CVDisplayLinkGetActualOutputVideoRefreshPeriod(_ displayLink: CVDisplayLink) -> Double {
    _ = displayLink
    return 1.0 / 60.0
}

public func CVDisplayLinkStart(_ displayLink: CVDisplayLink) -> CVReturn {
    _ = displayLink
    return kCVReturnSuccess
}

public func CVDisplayLinkStop(_ displayLink: CVDisplayLink) -> CVReturn {
    _ = displayLink
    return kCVReturnSuccess
}

public func CVPixelBufferCreate(
    _ allocator: Any?,
    _ width: Int,
    _ height: Int,
    _ pixelFormatType: OSType,
    _ pixelBufferAttributes: Any?,
    _ pixelBufferOut: inout CVPixelBuffer?
) -> CVReturn {
    _ = (allocator, width, height, pixelFormatType, pixelBufferAttributes)
    pixelBufferOut = CVPixelBuffer(width: width, height: height, pixelFormatType: pixelFormatType)
    return kCVReturnSuccess
}

public func CVPixelBufferLockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ lockFlags: CVPixelBufferLockFlags) -> CVReturn {
    _ = (pixelBuffer, lockFlags)
    return kCVReturnSuccess
}

public func CVPixelBufferUnlockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ lockFlags: CVPixelBufferLockFlags) -> CVReturn {
    _ = (pixelBuffer, lockFlags)
    return kCVReturnSuccess
}

public func CVPixelBufferGetBaseAddress(_ pixelBuffer: CVPixelBuffer) -> UnsafeMutableRawPointer? {
    pixelBuffer.withBaseAddress { $0 }
}

public func CVPixelBufferGetBytesPerRow(_ pixelBuffer: CVPixelBuffer) -> Int {
    max(1, pixelBuffer.width * 4)
}

public func CVPixelBufferGetPixelFormatType(_ pixelBuffer: CVPixelBuffer) -> OSType {
    pixelBuffer.pixelFormatType
}

public func CVPixelBufferGetDataSize(_ pixelBuffer: CVPixelBuffer) -> Int {
    CVPixelBufferGetBytesPerRow(pixelBuffer) * pixelBuffer.height
}

public func CVPixelBufferGetWidth(_ pixelBuffer: CVPixelBuffer) -> Int {
    pixelBuffer.width
}

public func CVPixelBufferGetHeight(_ pixelBuffer: CVPixelBuffer) -> Int {
    pixelBuffer.height
}

public func CVPixelBufferGetPlaneCount(_ pixelBuffer: CVPixelBuffer) -> Int {
    switch pixelBuffer.pixelFormatType {
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
        return 2
    case kCVPixelFormatType_420YpCbCr8VideoRange_8A_TriPlanar:
        return 3
    default:
        return 1
    }
}

public func CVPixelBufferGetWidthOfPlane(_ pixelBuffer: CVPixelBuffer, _ planeIndex: Int) -> Int {
    planeIndex == 0 ? pixelBuffer.width : max(1, pixelBuffer.width / 2)
}

public func CVPixelBufferGetHeightOfPlane(_ pixelBuffer: CVPixelBuffer, _ planeIndex: Int) -> Int {
    planeIndex == 0 ? pixelBuffer.height : max(1, pixelBuffer.height / 2)
}

public func CVPixelBufferGetBaseAddressOfPlane(_ pixelBuffer: CVPixelBuffer, _ planeIndex: Int) -> UnsafeMutableRawPointer? {
    _ = planeIndex
    return CVPixelBufferGetBaseAddress(pixelBuffer)
}

public func CVPixelBufferGetBytesPerRowOfPlane(_ pixelBuffer: CVPixelBuffer, _ planeIndex: Int) -> Int {
    planeIndex == 0 ? max(1, pixelBuffer.width) : max(1, pixelBuffer.width)
}

public func CVPixelBufferPoolCreate(
    _ allocator: Any?,
    _ poolAttributes: Any?,
    _ pixelBufferAttributes: Any?,
    _ poolOut: inout CVPixelBufferPool?
) -> CVReturn {
    _ = (allocator, poolAttributes)
    let attributes = pixelBufferAttributes as? [String: Any]
    let width = (attributes?[kCVPixelBufferWidthKey] as? NSNumber)?.intValue ?? 1
    let height = (attributes?[kCVPixelBufferHeightKey] as? NSNumber)?.intValue ?? 1
    let pixelFormat = (attributes?[kCVPixelBufferPixelFormatTypeKey] as? NSNumber)?.uint32Value ?? kCVPixelFormatType_32BGRA
    poolOut = CVPixelBufferPool(width: width, height: height, pixelFormatType: pixelFormat)
    return kCVReturnSuccess
}

public func CVPixelBufferPoolCreatePixelBuffer(
    _ allocator: Any?,
    _ pixelBufferPool: CVPixelBufferPool,
    _ pixelBufferOut: inout CVPixelBuffer?
) -> CVReturn {
    _ = allocator
    pixelBufferOut = CVPixelBuffer(width: pixelBufferPool.width, height: pixelBufferPool.height, pixelFormatType: pixelBufferPool.pixelFormatType)
    return kCVReturnSuccess
}

public func CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
    _ allocator: Any?,
    _ pixelBufferPool: CVPixelBufferPool,
    _ auxAttributes: Any?,
    _ pixelBufferOut: inout CVPixelBuffer?
) -> CVReturn {
    _ = auxAttributes
    return CVPixelBufferPoolCreatePixelBuffer(allocator, pixelBufferPool, &pixelBufferOut)
}

public final class CVMetalTextureCache: @unchecked Sendable {
    fileprivate let device: MTLDevice

    fileprivate init(device: MTLDevice) {
        self.device = device
    }
}

public final class CVMetalTexture: @unchecked Sendable {
    fileprivate let texture: MTLTexture

    fileprivate init(texture: MTLTexture) {
        self.texture = texture
    }
}

public func CVMetalTextureCacheCreate(
    _ allocator: Any?,
    _ cacheAttributes: Any?,
    _ metalDevice: MTLDevice,
    _ textureAttributes: Any?,
    _ cacheOut: inout CVMetalTextureCache?
) -> CVReturn {
    _ = (allocator, cacheAttributes, textureAttributes)
    cacheOut = CVMetalTextureCache(device: metalDevice)
    return kCVReturnSuccess
}

public func CVMetalTextureCacheCreateTextureFromImage(
    _ allocator: Any?,
    _ textureCache: CVMetalTextureCache,
    _ sourceImage: CVPixelBuffer,
    _ textureAttributes: Any?,
    _ pixelFormat: MTLPixelFormat,
    _ width: Int,
    _ height: Int,
    _ planeIndex: Int,
    _ textureOut: inout CVMetalTexture?
) -> CVReturn {
    _ = (allocator, sourceImage, textureAttributes, planeIndex)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: max(1, width), height: max(1, height), mipmapped: false)
    let texture = textureCache.device.makeTexture(descriptor: descriptor) ?? QuillMTLTexture(descriptor: descriptor)
    textureOut = CVMetalTexture(texture: texture)
    return kCVReturnSuccess
}

public func CVMetalTextureGetTexture(_ image: CVMetalTexture) -> MTLTexture? {
    image.texture
}

public func CVMetalTextureCacheFlush(_ textureCache: CVMetalTextureCache, _ options: CVOptionFlags) {
    _ = (textureCache, options)
}
