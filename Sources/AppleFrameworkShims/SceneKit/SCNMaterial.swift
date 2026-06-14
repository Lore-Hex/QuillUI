// SceneKit shim — materials.
import Foundation
import QuillFoundation

public enum SCNWrapMode: Int, Sendable {
    case clamp = 1
    case `repeat` = 2
    case clampToBorder = 3
    case mirror = 4
}

public enum SCNFilterMode: Int, Sendable {
    case none = 0
    case nearest = 1
    case linear = 2
}

public enum SCNLightingModel: String, Sendable {
    case phong
    case blinn
    case lambert
    case constant
    case physicallyBased
}

/// A single shading channel (diffuse, emission, specular, …). `contents`
/// holds an `NSColor` / `CGColor` / `CGImage` / image just like macOS.
public final class SCNMaterialProperty: @unchecked Sendable {
    public var contents: Any?
    public var intensity: CGFloat = 1
    public var wrapS: SCNWrapMode = .clamp
    public var wrapT: SCNWrapMode = .clamp
    public var magnificationFilter: SCNFilterMode = .linear
    public var minificationFilter: SCNFilterMode = .linear
    public var mipFilter: SCNFilterMode = .nearest

    public init() {}

    public init(contents: Any?) {
        self.contents = contents
    }
}

public final class SCNMaterial: @unchecked Sendable {
    public var name: String?
    public let diffuse = SCNMaterialProperty()
    public let ambient = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let normal = SCNMaterialProperty()
    public let metalness = SCNMaterialProperty()
    public let roughness = SCNMaterialProperty()
    public let transparent = SCNMaterialProperty()
    public var transparency: CGFloat = 1
    public var lightingModel: SCNLightingModel = .blinn
    public var isDoubleSided: Bool = false
    public var shininess: CGFloat = 1

    public init() {}
}
