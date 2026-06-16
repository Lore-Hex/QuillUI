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
    public var indicesChannelCount: Int = 1
    public var hasInterleavedIndicesChannels: Bool = false

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
    public var geometrySourceChannels: [NSNumber]?

    /// Shallow copy (SCNGeometry is NSCopying on macOS). Euclid calls
    /// `geometry.copy() as! SCNGeometry` before reading sources/elements.
    public func copy() -> Any {
        let g = SCNGeometry(sources: sources, elements: elements)
        g.name = name
        g.materials = materials
        return g
    }

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

    /// Axis-aligned bounds (min, max) computed from the vertex source, matching
    /// `SCNGeometry.boundingBox`. Zero when there is no vertex data.
    public var boundingBox: (min: SCNVector3, max: SCNVector3) {
        get {
            guard let vertexSource = sources.first(where: { $0.semantic == .vertex }),
                  vertexSource.vectorCount > 0 else {
                return (SCNVector3(0, 0, 0), SCNVector3(0, 0, 0))
            }
            var lo = SCNVector3(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var hi = SCNVector3(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            let stride = vertexSource.dataStride
            vertexSource.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<vertexSource.vectorCount {
                    let base = vertexSource.dataOffset + i * stride
                    let v = raw.loadUnaligned(fromByteOffset: base, as: SCNVector3.self)
                    lo = SCNVector3(Swift.min(lo.x, v.x), Swift.min(lo.y, v.y), Swift.min(lo.z, v.z))
                    hi = SCNVector3(Swift.max(hi.x, v.x), Swift.max(hi.y, v.y), Swift.max(hi.z, v.z))
                }
            }
            return (lo, hi)
        }
        set { _ = newValue }
    }
}

// MARK: - Parametric primitives
//
// Each exposes the parameters the apps set; rendering reads them at rung 3.

// MARK: - Buffer-building convenience inits (Euclid's Mesh<->SCNGeometry path)

public extension SCNGeometrySource {
    /// Vertex positions. Components are CGFloat (Double on QuillOS) to match
    /// SCNVector3's storage; the rung-3 renderer reads the layout fields.
    convenience init(vertices: [SCNVector3]) {
        self.init(
            data: Data(bytes: vertices, count: vertices.count * MemoryLayout<SCNVector3>.stride),
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<CGFloat>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )
    }

    convenience init(normals: [SCNVector3]) {
        self.init(
            data: Data(bytes: normals, count: normals.count * MemoryLayout<SCNVector3>.stride),
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<CGFloat>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )
    }

    convenience init(textureCoordinates: [CGPoint]) {
        self.init(
            data: Data(bytes: textureCoordinates, count: textureCoordinates.count * MemoryLayout<CGPoint>.stride),
            semantic: .texcoord,
            vectorCount: textureCoordinates.count,
            usesFloatComponents: true,
            componentsPerVector: 2,
            bytesPerComponent: MemoryLayout<CGFloat>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<CGPoint>.stride
        )
    }
}

public extension SCNGeometryElement {
    /// Build an element from an index array; `primitiveCount` is derived from
    /// the primitive type, as on macOS.
    convenience init<IndexType: FixedWidthInteger>(
        indices: [IndexType],
        primitiveType: SCNGeometryPrimitiveType
    ) {
        let primitiveCount: Int
        switch primitiveType {
        case .triangles: primitiveCount = indices.count / 3
        case .triangleStrip: primitiveCount = max(0, indices.count - 2)
        case .line: primitiveCount = indices.count / 2
        case .point: primitiveCount = indices.count
        case .polygon: primitiveCount = 1
        }
        self.init(
            data: Data(bytes: indices, count: indices.count * MemoryLayout<IndexType>.size),
            primitiveType: primitiveType,
            primitiveCount: primitiveCount,
            bytesPerIndex: MemoryLayout<IndexType>.size
        )
    }
}

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

/// Extruded 2D text. Modeled enough for the type to exist (Euclid switches on
/// `is SCNText`); full glyph tessellation is a later rung.
public final class SCNText: SCNGeometry, @unchecked Sendable {
    public var string: Any?
    public var extrusionDepth: CGFloat
    public var font: Any?
    public var flatness: CGFloat = 0.6
    public var chamferRadius: CGFloat = 0

    public init(string: Any?, extrusionDepth: CGFloat) {
        self.string = string
        self.extrusionDepth = extrusionDepth
        super.init()
    }
}

/// Extruded 2D shape from a path.
public final class SCNShape: SCNGeometry, @unchecked Sendable {
    public var path: Any?
    public var extrusionDepth: CGFloat
    public var chamferRadius: CGFloat = 0

    public init(path: Any?, extrusionDepth: CGFloat) {
        self.path = path
        self.extrusionDepth = extrusionDepth
        super.init()
    }
}
