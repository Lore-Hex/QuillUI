import Foundation
@_exported import QuillFoundation

public enum MTLPixelFormat: UInt, Sendable {
    case invalid = 0
    case r8Unorm = 10
    case rg8Unorm = 30
    case rgba8Unorm = 70
    case bgra8Unorm = 80
}

public enum MTLStorageMode: UInt, Sendable {
    case shared = 0
    case managed = 1
    case `private` = 2
    case memoryless = 3
}

public enum MTLTextureType: UInt, Sendable {
    case type1D = 0
    case type2D = 2
    case type3D = 3
}

public struct MTLTextureUsage: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let unknown = MTLTextureUsage([])
    public static let shaderRead = MTLTextureUsage(rawValue: 1 << 0)
    public static let shaderWrite = MTLTextureUsage(rawValue: 1 << 1)
    public static let renderTarget = MTLTextureUsage(rawValue: 1 << 2)
}

public struct MTLResourceOptions: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let storageModeShared = MTLResourceOptions(rawValue: 0 << 4)
    public static let storageModeManaged = MTLResourceOptions(rawValue: 1 << 4)
    public static let storageModePrivate = MTLResourceOptions(rawValue: 2 << 4)
}

public struct MTLOrigin: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var z: Int

    public init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct MTLSize: Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var depth: Int

    public init(width: Int, height: Int, depth: Int) {
        self.width = width
        self.height = height
        self.depth = depth
    }
}

public struct MTLRegion: Sendable, Equatable {
    public var origin: MTLOrigin
    public var size: MTLSize

    public init(origin: MTLOrigin, size: MTLSize) {
        self.origin = origin
        self.size = size
    }
}

public func MTLRegionMake2D(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> MTLRegion {
    MTLRegion(origin: MTLOrigin(x: x, y: y, z: 0), size: MTLSize(width: width, height: height, depth: 1))
}

public struct MTLScissorRect: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct MTLClearColor: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public enum MTLPrimitiveType: UInt, Sendable {
    case triangle = 3
}

public enum MTLLoadAction: UInt, Sendable {
    case dontCare = 0
    case load = 1
    case clear = 2
}

public enum MTLStoreAction: UInt, Sendable {
    case dontCare = 0
    case store = 1
}

public enum MTLBlendOperation: UInt, Sendable {
    case add = 0
}

public enum MTLBlendFactor: UInt, Sendable {
    case zero = 0
    case one = 1
    case sourceAlpha = 4
    case oneMinusSourceAlpha = 5
}

public enum MTLSamplerMinMagFilter: UInt, Sendable {
    case nearest = 0
    case linear = 1
}

public enum MTLSamplerMipFilter: UInt, Sendable {
    case notMipmapped = 0
    case nearest = 1
    case linear = 2
}

public enum MTLSamplerAddressMode: UInt, Sendable {
    case clampToEdge = 0
    case mirrorClampToEdge = 1
    case `repeat` = 2
    case mirrorRepeat = 3
    case clampToZero = 4
}

public final class MTLTextureDescriptor {
    public var textureType: MTLTextureType = .type2D
    public var pixelFormat: MTLPixelFormat = .invalid
    public var width: Int = 1
    public var height: Int = 1
    public var depth: Int = 1
    public var mipmapLevelCount: Int = 1
    public var sampleCount: Int = 1
    public var arrayLength: Int = 1
    public var storageMode: MTLStorageMode = .shared
    public var usage: MTLTextureUsage = []

    public init() {}

    public static func texture2DDescriptor(pixelFormat: MTLPixelFormat, width: Int, height: Int, mipmapped: Bool) -> MTLTextureDescriptor {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = mipmapped ? 2 : 1
        return descriptor
    }
}

public protocol MTLResource: AnyObject {}

public protocol MTLTexture: MTLResource {
    var width: Int { get }
    var height: Int { get }
    var pixelFormat: MTLPixelFormat { get }

    func replace(region: MTLRegion, mipmapLevel: Int, withBytes: UnsafeRawPointer, bytesPerRow: Int)
}

public final class QuillMTLTexture: MTLTexture {
    public let width: Int
    public let height: Int
    public let pixelFormat: MTLPixelFormat

    public init(width: Int, height: Int, pixelFormat: MTLPixelFormat = .invalid) {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
    }

    public convenience init(descriptor: MTLTextureDescriptor) {
        self.init(width: descriptor.width, height: descriptor.height, pixelFormat: descriptor.pixelFormat)
    }

    public func replace(region: MTLRegion, mipmapLevel: Int, withBytes: UnsafeRawPointer, bytesPerRow: Int) {
        _ = (region, mipmapLevel, withBytes, bytesPerRow)
    }
}

public protocol MTLBuffer: MTLResource {
    var length: Int { get }

    func contents() -> UnsafeMutableRawPointer
}

public final class QuillMTLBuffer: MTLBuffer {
    public let length: Int
    private let storage: UnsafeMutableRawPointer

    public init(length: Int) {
        self.length = length
        self.storage = UnsafeMutableRawPointer.allocate(byteCount: max(length, 1), alignment: MemoryLayout<UInt8>.alignment)
        self.storage.initializeMemory(as: UInt8.self, repeating: 0, count: max(length, 1))
    }

    public convenience init(bytes: UnsafeRawPointer, length: Int) {
        self.init(length: length)
        self.storage.copyMemory(from: bytes, byteCount: length)
    }

    deinit {
        storage.deallocate()
    }

    public func contents() -> UnsafeMutableRawPointer {
        storage
    }
}

public protocol MTLFunction: AnyObject {
    var name: String { get }
}

public final class QuillMTLFunction: MTLFunction {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public protocol MTLLibrary: AnyObject {
    func makeFunction(name: String) -> MTLFunction?
}

public final class QuillMTLLibrary: MTLLibrary {
    public init() {}

    public func makeFunction(name: String) -> MTLFunction? {
        QuillMTLFunction(name: name)
    }
}

public protocol MTLRenderPipelineState: AnyObject {}
public final class QuillMTLRenderPipelineState: MTLRenderPipelineState {
    public init() {}
}

public protocol MTLComputePipelineState: AnyObject {
    var threadExecutionWidth: Int { get }
    var maxTotalThreadsPerThreadgroup: Int { get }
}
public final class QuillMTLComputePipelineState: MTLComputePipelineState {
    // MODEL HONESTY: there are no GPU threads on Linux. 1 keeps upstream
    // threadgroup arithmetic (SpoilerParticleView divides and ceil()s by
    // these) finite and division-by-zero free.
    public let threadExecutionWidth = 1
    public let maxTotalThreadsPerThreadgroup = 1
    public init() {}
}

public final class MTLRenderPipelineColorAttachmentDescriptor {
    public var pixelFormat: MTLPixelFormat = .invalid
    public var isBlendingEnabled: Bool = false
    public var rgbBlendOperation: MTLBlendOperation = .add
    public var alphaBlendOperation: MTLBlendOperation = .add
    public var sourceRGBBlendFactor: MTLBlendFactor = .one
    public var sourceAlphaBlendFactor: MTLBlendFactor = .one
    public var destinationRGBBlendFactor: MTLBlendFactor = .zero
    public var destinationAlphaBlendFactor: MTLBlendFactor = .zero

    public init() {}
}

public final class MTLRenderPipelineColorAttachmentDescriptorArray {
    private var attachments: [Int: MTLRenderPipelineColorAttachmentDescriptor] = [:]

    public subscript(index: Int) -> MTLRenderPipelineColorAttachmentDescriptor {
        if let attachment = attachments[index] {
            return attachment
        }
        let attachment = MTLRenderPipelineColorAttachmentDescriptor()
        attachments[index] = attachment
        return attachment
    }
}

public final class MTLRenderPipelineDescriptor {
    public var vertexFunction: MTLFunction?
    public var fragmentFunction: MTLFunction?
    public let colorAttachments = MTLRenderPipelineColorAttachmentDescriptorArray()

    public init() {}
}

public final class MTLSamplerDescriptor {
    public var minFilter: MTLSamplerMinMagFilter = .nearest
    public var magFilter: MTLSamplerMinMagFilter = .nearest
    public var mipFilter: MTLSamplerMipFilter = .notMipmapped
    public var maxAnisotropy: Int = 1
    public var sAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var tAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var rAddressMode: MTLSamplerAddressMode = .clampToEdge
    public var normalizedCoordinates: Bool = true
    public var lodMinClamp: Float = 0
    public var lodMaxClamp: Float = .greatestFiniteMagnitude

    public init() {}
}

public protocol MTLSamplerState: AnyObject {}
public final class QuillMTLSamplerState: MTLSamplerState {
    public init() {}
}

public final class MTLRenderPassColorAttachmentDescriptor {
    public var texture: MTLTexture?
    public var loadAction: MTLLoadAction = .dontCare
    public var storeAction: MTLStoreAction = .dontCare
    public var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

    public init() {}
}

public final class MTLRenderPassColorAttachmentDescriptorArray {
    private var attachments: [Int: MTLRenderPassColorAttachmentDescriptor] = [:]

    public subscript(index: Int) -> MTLRenderPassColorAttachmentDescriptor {
        if let attachment = attachments[index] {
            return attachment
        }
        let attachment = MTLRenderPassColorAttachmentDescriptor()
        attachments[index] = attachment
        return attachment
    }
}

public final class MTLRenderPassDescriptor {
    public let colorAttachments = MTLRenderPassColorAttachmentDescriptorArray()

    public init() {}
}

public protocol MTLRenderCommandEncoder: AnyObject {
    func setRenderPipelineState(_ pipelineState: MTLRenderPipelineState)
    func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int)
    func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setVertexBytes<T>(_ bytes: [T], length: Int, index: Int)
    func setFragmentTexture(_ texture: MTLTexture?, index: Int)
    func setFragmentSamplerState(_ sampler: MTLSamplerState?, index: Int)
    func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func setScissorRect(_ rect: MTLScissorRect)
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int)
    func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int)
    func endEncoding()
}

public final class QuillMTLRenderCommandEncoder: MTLRenderCommandEncoder {
    public init() {}

    public func setRenderPipelineState(_ pipelineState: MTLRenderPipelineState) { _ = pipelineState }
    public func setVertexBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) { _ = (buffer, offset, index) }
    public func setVertexBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { _ = (bytes, length, index) }
    public func setVertexBytes<T>(_ bytes: [T], length: Int, index: Int) { _ = (bytes, length, index) }
    public func setFragmentTexture(_ texture: MTLTexture?, index: Int) { _ = (texture, index) }
    public func setFragmentSamplerState(_ sampler: MTLSamplerState?, index: Int) { _ = (sampler, index) }
    public func setFragmentBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { _ = (bytes, length, index) }
    public func setScissorRect(_ rect: MTLScissorRect) { _ = rect }
    public func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int) { _ = (type, vertexStart, vertexCount) }
    public func drawPrimitives(type: MTLPrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int) { _ = (type, vertexStart, vertexCount, instanceCount) }
    public func endEncoding() {}
}

public protocol MTLComputeCommandEncoder: AnyObject {
    func setComputePipelineState(_ state: MTLComputePipelineState)
    func setTexture(_ texture: MTLTexture?, index: Int)
    func setBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int)
    func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int)
    func dispatchThreadgroups(_ threadgroupsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)
    func dispatchThreads(_ threadsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize)
    func endEncoding()
}

public final class QuillMTLComputeCommandEncoder: MTLComputeCommandEncoder {
    public init() {}

    public func setComputePipelineState(_ state: MTLComputePipelineState) { _ = state }
    public func setTexture(_ texture: MTLTexture?, index: Int) { _ = (texture, index) }
    public func setBuffer(_ buffer: MTLBuffer?, offset: Int, index: Int) { _ = (buffer, offset, index) }
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, index: Int) { _ = (bytes, length, index) }
    public func dispatchThreadgroups(_ threadgroupsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize) { _ = (threadgroupsPerGrid, threadsPerThreadgroup) }
    public func dispatchThreads(_ threadsPerGrid: MTLSize, threadsPerThreadgroup: MTLSize) { _ = (threadsPerGrid, threadsPerThreadgroup) }
    public func endEncoding() {}
}

public protocol MTLDrawable: AnyObject {
    func present()
}

public protocol CAMetalDrawable: MTLDrawable {
    var texture: MTLTexture { get }
}

public final class QuillMetalDrawable: CAMetalDrawable {
    public let texture: MTLTexture

    public init(texture: MTLTexture) {
        self.texture = texture
    }

    public func present() {}
}

public protocol MTLCommandBuffer: AnyObject {
    func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder?
    func makeComputeCommandEncoder() -> MTLComputeCommandEncoder?
    func addScheduledHandler(_ block: @escaping (MTLCommandBuffer) -> Void)
    func addCompletedHandler(_ block: @escaping (MTLCommandBuffer) -> Void)
    func present(_ drawable: MTLDrawable)
    func commit()
    func waitUntilScheduled()
    func waitUntilCompleted()
}

public final class QuillMTLCommandBuffer: MTLCommandBuffer {
    private var scheduledHandlers: [(MTLCommandBuffer) -> Void] = []
    private var completedHandlers: [(MTLCommandBuffer) -> Void] = []

    public init() {}

    public func makeRenderCommandEncoder(descriptor: MTLRenderPassDescriptor) -> MTLRenderCommandEncoder? {
        _ = descriptor
        return QuillMTLRenderCommandEncoder()
    }

    public func makeComputeCommandEncoder() -> MTLComputeCommandEncoder? {
        QuillMTLComputeCommandEncoder()
    }

    public func addScheduledHandler(_ block: @escaping (MTLCommandBuffer) -> Void) {
        scheduledHandlers.append(block)
    }

    public func addCompletedHandler(_ block: @escaping (MTLCommandBuffer) -> Void) {
        completedHandlers.append(block)
    }

    public func present(_ drawable: MTLDrawable) {
        drawable.present()
    }

    public func commit() {
        scheduledHandlers.forEach { $0(self) }
        completedHandlers.forEach { $0(self) }
        scheduledHandlers.removeAll()
        completedHandlers.removeAll()
    }

    public func waitUntilScheduled() {}
    public func waitUntilCompleted() {}
}

public protocol MTLCommandQueue: AnyObject {
    func makeCommandBuffer() -> MTLCommandBuffer?
}

public final class QuillMTLCommandQueue: MTLCommandQueue {
    public init() {}

    public func makeCommandBuffer() -> MTLCommandBuffer? {
        QuillMTLCommandBuffer()
    }
}

// Apple shape: raw values from Metal/MTLDevice.h MTLGPUFamily.
// SpoilerMetalConfiguration probes .common3/.apple3–8/.mac2/.metal3.
public enum MTLGPUFamily: Int, Sendable {
    case apple1 = 1001
    case apple2 = 1002
    case apple3 = 1003
    case apple4 = 1004
    case apple5 = 1005
    case apple6 = 1006
    case apple7 = 1007
    case apple8 = 1008
    case apple9 = 1009
    case mac1 = 2001
    case mac2 = 2002
    case common1 = 3001
    case common2 = 3002
    case common3 = 3003
    case macCatalyst1 = 4001
    case macCatalyst2 = 4002
    case metal3 = 5001
}

public protocol MTLDevice: AnyObject {
    func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool
    func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture?
    func makeTexture(descriptor: MTLTextureDescriptor, iosurface: Any, plane: Int) -> MTLTexture?
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeBuffer(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeBuffer<T>(bytes: [T], length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeCommandQueue() -> MTLCommandQueue?
    func makeDefaultLibrary() -> MTLLibrary?
    func makeDefaultLibrary(bundle: Bundle) throws -> MTLLibrary
    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState
    func makeComputePipelineState(function: MTLFunction) throws -> MTLComputePipelineState
    func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState?
}

public final class QuillMTLDevice: MTLDevice {
    public init() {}

    public func supportsFamily(_ gpuFamily: MTLGPUFamily) -> Bool {
        // MODEL HONESTY: no GPU exists on Linux; claiming membership in no
        // family steers upstream (SpoilerMetalConfiguration) onto its
        // conservative uniform-threadgroup / smallest-texture code paths.
        _ = gpuFamily
        return false
    }

    public func makeTexture(descriptor: MTLTextureDescriptor) -> MTLTexture? {
        QuillMTLTexture(descriptor: descriptor)
    }

    public func makeTexture(descriptor: MTLTextureDescriptor, iosurface: Any, plane: Int) -> MTLTexture? {
        _ = (iosurface, plane)
        return QuillMTLTexture(descriptor: descriptor)
    }

    public func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        _ = options
        return QuillMTLBuffer(length: length)
    }

    public func makeBuffer(bytes: UnsafeRawPointer, length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        _ = options
        return QuillMTLBuffer(bytes: bytes, length: length)
    }

    public func makeBuffer<T>(bytes: [T], length: Int, options: MTLResourceOptions) -> MTLBuffer? {
        _ = options
        return bytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return QuillMTLBuffer(length: length)
            }
            return QuillMTLBuffer(bytes: baseAddress, length: min(length, rawBuffer.count))
        }
    }

    public func makeCommandQueue() -> MTLCommandQueue? {
        QuillMTLCommandQueue()
    }

    public func makeDefaultLibrary() -> MTLLibrary? {
        QuillMTLLibrary()
    }

    public func makeDefaultLibrary(bundle: Bundle) throws -> MTLLibrary {
        _ = bundle
        return QuillMTLLibrary()
    }

    public func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        _ = descriptor
        return QuillMTLRenderPipelineState()
    }

    public func makeComputePipelineState(function: MTLFunction) throws -> MTLComputePipelineState {
        _ = function
        return QuillMTLComputePipelineState()
    }

    public func makeSamplerState(descriptor: MTLSamplerDescriptor) -> MTLSamplerState? {
        _ = descriptor
        return QuillMTLSamplerState()
    }
}

public func MTLCreateSystemDefaultDevice() -> MTLDevice? {
    QuillMTLDevice()
}

public typealias CGDirectDisplayID = UInt32

public func CGDirectDisplayCopyCurrentMetalDevice(_ display: CGDirectDisplayID) -> MTLDevice? {
    _ = display
    return MTLCreateSystemDefaultDevice()
}
