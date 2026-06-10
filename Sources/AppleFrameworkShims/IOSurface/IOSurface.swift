import Foundation
@_exported import CoreVideo
@_exported import QuillFoundation

public final class IOSurface: @unchecked Sendable {
    public let properties: [String: Any]

    public init(properties: [String: Any]) {
        self.properties = properties
    }
}

public let kIOSurfaceWidth = "IOSurfaceWidth"
public let kIOSurfaceHeight = "IOSurfaceHeight"
public let kIOSurfaceBytesPerElement = "IOSurfaceBytesPerElement"
public let kIOSurfacePixelFormat = "IOSurfacePixelFormat"

public func IOSurfaceCreate(_ properties: [String: Any]) -> IOSurface? {
    IOSurface(properties: properties)
}
