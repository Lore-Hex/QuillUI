// SceneKit shim — geometry: the base class, the parametric primitives the
// apps instantiate, and the source/element buffer types Euclid's interop uses.
import Foundation
import QuillFoundation

public enum SCNGeometryPrimitiveType: Int, Sendable {
    case triangles = 0
    case triangleStrip = 1
    case line = 2
    case point = 3
    case polygon = 4
}

public enum SCNGeometrySourceSemantic: String, Sendable {
    case vertex
    case normal
    case color
    case texcoord
    case tangent
    case vertexCrease
    case edgeCrease
    case boneWeights
    case boneIndices
}

/// A typed vertex-attribute buffer (positions / normals / texcoords).
/// The data layout fields mirror SceneKit so Euclid can both build sources
/// from meshes and read them back.
public final class SCNGeometrySource: @unchecked Sendable {
    public let data: Data
    public let semantic: SCNGeometrySourceSemantic
    public let vectorCount: Int
    public let usesFloatComponents: Bool
    public let componentsPerVector: Int
    public let bytesPerComponent: Int
    public let dataOffset: Int
    public let dataStride: Int

    public init(
        data: Data,
        semantic: SCNGeometrySourceSemantic,
        vectorCount: Int,
        usesFloatComponents: Bool,
        componentsPerVector: Int,
        bytesPerComponent: Int,
        dataOffset: Int,
        dataStride: Int
    ) {
        self.data = data
        self.semantic = semantic
        self.vectorCount = vectorCount
        self.usesFloatComponents = usesFloatComponents
        self.componentsPerVector = componentsPerVector
        self.bytesPerComponent = bytesPerComponent
        self.dataOffset = dataOffset
        self.dataStride = dataStride
    }
}

/// An index buffer describing how source vertices form primitives.
public final class SCNGeometryElement: @unchecked Sendable {
    public let data: Data
    public let primitiveType: SCNGeometryPrimitiveType
    public let primitiveCount: Int
    public let bytesPerIndex: Int

    public init(
        data: Data,
        primitiveType: SCNGeometryPrimitiveType,
        primitiveCount: Int,
        bytesPerIndex: Int
    ) {
        self.data = data
        self.primitiveType = primitiveType
        self.primitiveCount = primitiveCount
        self.bytesPerIndex = bytesPerIndex
    }
}

public class SCNGeometry: @unchecked Sendable {
    public var name: String?
    public var materials: [SCNMaterial] = []
    public internal(set) var sources: [SCNGeometrySource] = []
    public internal(set) var elements: [SCNGeometryElement] = []

    public var firstMaterial: SCNMaterial? {
        get { materials.first }
        set {
            if let newValue {
                if materials.isEmpty { materials = [newValue] }
                else { materials[0] = newValue }
            } else {
                materials = []
            }
        }
    }

    public init() {
        firstMaterial = SCNMaterial()
    }

    public init(sources: [SCNGeometrySource], elements: [SCNGeometryElement]) {
        self.sources = sources
        self.elements = elements
        firstMaterial = SCNMaterial()
    }

    public func sources(for semantic: SCNGeometrySourceSemantic) -> [SCNGeometrySource] {
        sources.filter { $0.semantic == semantic }
    }
}

// MARK: - Parametric primitives
//
// Each exposes the parameters the apps set; rendering reads them at rung 3.

public final class SCNSphere: SCNGeometry, @unchecked Sendable {
    public var radius: CGFloat
    public var isGeodesic: Bool = false
    public var segmentCount: Int = 48

    public init(radius: CGFloat) {
        self.radius = radius
        super.init()
    }
}

public final class SCNBox: SCNGeometry, @unchecked Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var length: CGFloat
    public var chamferRadius: CGFloat

    public init(width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat) {
        self.width = width
        self.height = height
        self.length = length
        self.chamferRadius = chamferRadius
        super.init()
    }
}

public final class SCNCylinder: SCNGeometry, @unchecked Sendable {
    public var radius: CGFloat
    public var height: CGFloat

    public init(radius: CGFloat, height: CGFloat) {
        self.radius = radius
        self.height = height
        super.init()
    }
}

public final class SCNCone: SCNGeometry, @unchecked Sendable {
    public var topRadius: CGFloat
    public var bottomRadius: CGFloat
    public var height: CGFloat

    public init(topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.height = height
        super.init()
    }
}

public final class SCNCapsule: SCNGeometry, @unchecked Sendable {
    public var capRadius: CGFloat
    public var height: CGFloat

    public init(capRadius: CGFloat, height: CGFloat) {
        self.capRadius = capRadius
        self.height = height
        super.init()
    }
}

public final class SCNTube: SCNGeometry, @unchecked Sendable {
    public var innerRadius: CGFloat
    public var outerRadius: CGFloat
    public var height: CGFloat

    public init(innerRadius: CGFloat, outerRadius: CGFloat, height: CGFloat) {
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
        self.height = height
        super.init()
    }
}

public final class SCNTorus: SCNGeometry, @unchecked Sendable {
    public var ringRadius: CGFloat
    public var pipeRadius: CGFloat

    public init(ringRadius: CGFloat, pipeRadius: CGFloat) {
        self.ringRadius = ringRadius
        self.pipeRadius = pipeRadius
        super.init()
    }
}

public final class SCNPlane: SCNGeometry, @unchecked Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
        super.init()
    }
}

public final class SCNPyramid: SCNGeometry, @unchecked Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public var length: CGFloat

    public init(width: CGFloat, height: CGFloat, length: CGFloat) {
        self.width = width
        self.height = height
        self.length = length
        super.init()
    }
}
