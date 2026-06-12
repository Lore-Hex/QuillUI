import Foundation
@_exported import Metal

open class MPSKernel: NSObject {
    public let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
        super.init()
    }
}

public final class MPSImageBilinearScale: MPSKernel {
    public func encode(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, destinationTexture: MTLTexture) {
        _ = (commandBuffer, sourceTexture, destinationTexture)
    }
}
