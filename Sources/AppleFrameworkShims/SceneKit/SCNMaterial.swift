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

public enum SCNTransparencyMode: Int, Sendable {
    case aOne
    case rgbZero
    case singleLayer
    case dualLayer
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

    fileprivate func copySettings(to other: SCNMaterialProperty) {
        other.contents = contents
        other.intensity = intensity
        other.wrapS = wrapS
        other.wrapT = wrapT
        other.magnificationFilter = magnificationFilter
        other.minificationFilter = minificationFilter
        other.mipFilter = mipFilter
    }
}

public final class SCNMaterial: Hashable, @unchecked Sendable {
    // Identity-based Hashable: Euclid stores SCNMaterial as its `Material`
    // (an AnyHashable) when round-tripping SCNGeometry -> Mesh, so the type
    // must be Hashable (NSObject provides this on macOS).
    public static func == (lhs: SCNMaterial, rhs: SCNMaterial) -> Bool {
        lhs === rhs
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public var name: String?
    public let diffuse = SCNMaterialProperty()
    public let ambient = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let normal = SCNMaterialProperty()
    public let metalness = SCNMaterialProperty()
    public let roughness = SCNMaterialProperty()
    public let multiply = SCNMaterialProperty()
    public let transparent = SCNMaterialProperty()
    public var transparency: CGFloat = 1
    public var transparencyMode: SCNTransparencyMode = .aOne
    public var readsFromDepthBuffer: Bool = true
    public var writesToDepthBuffer: Bool = true
    public var lightingModel: SCNLightingModel = .blinn
    public var isDoubleSided: Bool = false
    public var shininess: CGFloat = 1

    public init() {}

    public func copy() -> Any {
        let material = SCNMaterial()
        material.name = name
        diffuse.copySettings(to: material.diffuse)
        ambient.copySettings(to: material.ambient)
        specular.copySettings(to: material.specular)
        emission.copySettings(to: material.emission)
        normal.copySettings(to: material.normal)
        metalness.copySettings(to: material.metalness)
        roughness.copySettings(to: material.roughness)
        multiply.copySettings(to: material.multiply)
        transparent.copySettings(to: material.transparent)
        material.transparency = transparency
        material.transparencyMode = transparencyMode
        material.readsFromDepthBuffer = readsFromDepthBuffer
        material.writesToDepthBuffer = writesToDepthBuffer
        material.lightingModel = lightingModel
        material.isDoubleSided = isDoubleSided
        material.shininess = shininess
        return material
    }
}
