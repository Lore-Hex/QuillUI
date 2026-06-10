import Foundation
import AppKit

public enum WebPImageType: UInt, Sendable {
    case unknown = 0
    case webP = 1
}

public let WebPImageTypeUnknown = WebPImageType.unknown
public let WebPImageTypeWebP = WebPImageType.webP

public enum WebPImageDisposeMethod: UInt, Sendable {
    case none = 0
    case background = 1
    case previous = 2
}

public let WebPImageDisposeNone = WebPImageDisposeMethod.none
public let WebPImageDisposeBackground = WebPImageDisposeMethod.background
public let WebPImageDisposePrevious = WebPImageDisposeMethod.previous

public enum WebPImageBlendOperation: UInt, Sendable {
    case none = 0
    case over = 1
}

public let WebPImageBlendNone = WebPImageBlendOperation.none
public let WebPImageBlendOver = WebPImageBlendOperation.over

open class WebPImageFrame: NSObject, NSCopying {
    open var index: UInt = 0
    open var width: UInt = 0
    open var height: UInt = 0
    open var offsetX: UInt = 0
    open var offsetY: UInt = 0
    open var duration: TimeInterval = 0
    open var dispose: WebPImageDisposeMethod = .none
    open var blend: WebPImageBlendOperation = .none
    open var image: NSImage?

    public override init() {
        super.init()
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = WebPImageFrame()
        copy.index = index
        copy.width = width
        copy.height = height
        copy.offsetX = offsetX
        copy.offsetY = offsetY
        copy.duration = duration
        copy.dispose = dispose
        copy.blend = blend
        copy.image = image
        return copy
    }
}

open class WebPImageDecoder: NSObject {
    open private(set) var data: Data?
    open private(set) var type: WebPImageType = .unknown
    public let scale: CGFloat
    open private(set) var frameCount: UInt = 0
    open private(set) var loopCount: UInt = 0
    open private(set) var width: UInt = 0
    open private(set) var height: UInt = 0
    open private(set) var isFinalized: Bool = false

    public init(scale: CGFloat) {
        self.scale = scale
        super.init()
    }

    public convenience init?(data: Data, scale: CGFloat) {
        self.init(scale: scale)
        guard updateData(data, final: true) else {
            return nil
        }
    }

    open class func decoder(data: Data, scale: CGFloat) -> WebPImageDecoder? {
        WebPImageDecoder(data: data, scale: scale)
    }

    public required override init() {
        self.scale = 1
        super.init()
    }

    open func updateData(_ data: Data?, final: Bool) -> Bool {
        self.data = data
        self.isFinalized = final
        self.type = data?.isEmpty == false ? .webP : .unknown
        self.frameCount = data?.isEmpty == false ? 1 : 0
        return data != nil
    }

    open func frame(at index: UInt, decodeForDisplay: Bool) -> WebPImageFrame? {
        _ = decodeForDisplay
        guard index < frameCount else {
            return nil
        }
        let frame = WebPImageFrame()
        frame.index = index
        frame.width = width
        frame.height = height
        frame.duration = frameDuration(at: index)
        return frame
    }

    open func frameDuration(at index: UInt) -> TimeInterval {
        _ = index
        return 1.0 / 30.0
    }
}

public func WebPCGImageCreateDecodedCopy(_ imageRef: CGImage, _ decodeForDisplay: Bool) -> CGImage? {
    _ = decodeForDisplay
    return imageRef
}
