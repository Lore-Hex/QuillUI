// SceneKit shim — private Quill scene archive support.
import Foundation
import QuillFoundation

enum QuillSceneArchiveCodec {
    static func data(for scene: SCNScene) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(QuillSceneArchive(scene))
    }

    static func scene(from data: Data, sourceURL: URL = URL(fileURLWithPath: "scene")) throws -> SCNScene {
        let scene = SCNScene()
        try load(data, sourceURL: sourceURL, into: scene)
        return scene
    }

    static func load(_ data: Data, sourceURL: URL, into scene: SCNScene) throws {
        let archive = try JSONDecoder().decode(QuillSceneArchive.self, from: data)
        guard archive.magic == QuillSceneArchive.magic, archive.version == QuillSceneArchive.version else {
            throw SCNSceneShimError.loadingUnsupported(sourceURL)
        }
        archive.apply(to: scene)
    }
}

private struct QuillSceneArchive: Codable {
    static let magic = "quill.scenekit.scene"
    static let version = 1

    var magic = Self.magic
    var version = Self.version
    var background: QuillSceneColor?
    var lightingEnvironment: QuillSceneMaterialProperty
    var fogColor: QuillSceneColor?
    var fogStartDistance: CGFloat
    var fogEndDistance: CGFloat
    var isPaused: Bool
    var rootNode: QuillSceneNodeArchive

    init(_ scene: SCNScene) {
        background = QuillSceneColor(scene.background.contents)
        lightingEnvironment = QuillSceneMaterialProperty(scene.lightingEnvironment)
        fogColor = QuillSceneColor(scene.fogColor)
        fogStartDistance = scene.fogStartDistance
        fogEndDistance = scene.fogEndDistance
        isPaused = scene.isPaused
        rootNode = QuillSceneNodeArchive(scene.rootNode)
    }

    func apply(to scene: SCNScene) {
        scene.background.contents = background?.cgColor
        lightingEnvironment.apply(to: scene.lightingEnvironment)
        scene.fogColor = fogColor?.cgColor
        scene.fogStartDistance = fogStartDistance
        scene.fogEndDistance = fogEndDistance
        scene.isPaused = isPaused
        rootNode.apply(to: scene.rootNode)
    }
}

private struct QuillSceneNodeArchive: Codable {
    var name: String?
    var position: QuillSceneVector3
    var eulerAngles: QuillSceneVector3
    var scale: QuillSceneVector3
    var orientation: QuillSceneVector4
    var transform: QuillSceneMatrix4
    var pivot: QuillSceneMatrix4
    var geometry: QuillSceneGeometryArchive?
    var light: QuillSceneLightArchive?
    var camera: QuillSceneCameraArchive?
    var isHidden: Bool
    var opacity: CGFloat
    var categoryBitMask: Int
    var renderingOrder: Int
    var childNodes: [QuillSceneNodeArchive]

    init(_ node: SCNNode) {
        name = node.name
        position = QuillSceneVector3(node.position)
        eulerAngles = QuillSceneVector3(node.eulerAngles)
        scale = QuillSceneVector3(node.scale)
        orientation = QuillSceneVector4(node.orientation)
        transform = QuillSceneMatrix4(node.transform)
        pivot = QuillSceneMatrix4(node.pivot)
        geometry = node.geometry.map(QuillSceneGeometryArchive.init)
        light = node.light.map(QuillSceneLightArchive.init)
        camera = node.camera.map(QuillSceneCameraArchive.init)
        isHidden = node.isHidden
        opacity = node.opacity
        categoryBitMask = node.categoryBitMask
        renderingOrder = node.renderingOrder
        childNodes = node.childNodes.map(QuillSceneNodeArchive.init)
    }

    func makeNode() -> SCNNode {
        let node = SCNNode()
        apply(to: node)
        return node
    }

    func apply(to node: SCNNode) {
        for child in node.childNodes {
            child.removeFromParentNode()
        }

        node.name = name
        node.position = position.scnVector
        node.eulerAngles = eulerAngles.scnVector
        node.scale = scale.scnVector
        node.orientation = orientation.scnVector
        node.pivot = pivot.scnMatrix
        if !node.transform.quillApproximatelyEquals(transform.scnMatrix) {
            node.transform = transform.scnMatrix
        }
        node.geometry = geometry?.makeGeometry()
        node.light = light?.makeLight()
        node.camera = camera?.makeCamera()
        node.isHidden = isHidden
        node.opacity = opacity
        node.categoryBitMask = categoryBitMask
        node.renderingOrder = renderingOrder

        for child in childNodes {
            node.addChildNode(child.makeNode())
        }
    }
}

private struct QuillSceneGeometryArchive: Codable {
    enum Kind: String, Codable {
        case geometry
        case sphere
        case box
        case cylinder
        case cone
        case capsule
        case tube
        case torus
        case plane
        case pyramid
        case text
        case shape
    }

    var kind: Kind
    var name: String?
    var materials: [QuillSceneMaterialArchive]
    var geometrySourceChannels: [Int]?
    var sources: [QuillSceneGeometrySourceArchive]
    var elements: [QuillSceneGeometryElementArchive]
    var radius: CGFloat?
    var width: CGFloat?
    var height: CGFloat?
    var length: CGFloat?
    var chamferRadius: CGFloat?
    var topRadius: CGFloat?
    var bottomRadius: CGFloat?
    var capRadius: CGFloat?
    var innerRadius: CGFloat?
    var outerRadius: CGFloat?
    var ringRadius: CGFloat?
    var pipeRadius: CGFloat?
    var isGeodesic: Bool?
    var segmentCount: Int?
    var string: String?
    var extrusionDepth: CGFloat?
    var flatness: CGFloat?

    init(_ geometry: SCNGeometry) {
        name = geometry.name
        materials = geometry.materials.map(QuillSceneMaterialArchive.init)
        geometrySourceChannels = geometry.geometrySourceChannels?.map(\.intValue)
        sources = geometry.sources.map(QuillSceneGeometrySourceArchive.init)
        elements = geometry.elements.map(QuillSceneGeometryElementArchive.init)

        switch geometry {
        case let geometry as SCNSphere:
            kind = .sphere
            radius = geometry.radius
            isGeodesic = geometry.isGeodesic
            segmentCount = geometry.segmentCount
        case let geometry as SCNBox:
            kind = .box
            width = geometry.width
            height = geometry.height
            length = geometry.length
            chamferRadius = geometry.chamferRadius
        case let geometry as SCNCylinder:
            kind = .cylinder
            radius = geometry.radius
            height = geometry.height
        case let geometry as SCNCone:
            kind = .cone
            topRadius = geometry.topRadius
            bottomRadius = geometry.bottomRadius
            height = geometry.height
        case let geometry as SCNCapsule:
            kind = .capsule
            capRadius = geometry.capRadius
            height = geometry.height
        case let geometry as SCNTube:
            kind = .tube
            innerRadius = geometry.innerRadius
            outerRadius = geometry.outerRadius
            height = geometry.height
        case let geometry as SCNTorus:
            kind = .torus
            ringRadius = geometry.ringRadius
            pipeRadius = geometry.pipeRadius
        case let geometry as SCNPlane:
            kind = .plane
            width = geometry.width
            height = geometry.height
        case let geometry as SCNPyramid:
            kind = .pyramid
            width = geometry.width
            height = geometry.height
            length = geometry.length
        case let geometry as SCNText:
            kind = .text
            string = geometry.string as? String
            extrusionDepth = geometry.extrusionDepth
            flatness = geometry.flatness
            chamferRadius = geometry.chamferRadius
        case let geometry as SCNShape:
            kind = .shape
            extrusionDepth = geometry.extrusionDepth
            chamferRadius = geometry.chamferRadius
        default:
            kind = .geometry
        }
    }

    func makeGeometry() -> SCNGeometry {
        let geometry: SCNGeometry
        switch kind {
        case .geometry:
            geometry = SCNGeometry(sources: sources.map(\.source), elements: elements.map(\.element))
        case .sphere:
            let sphere = SCNSphere(radius: radius ?? 0)
            sphere.isGeodesic = isGeodesic ?? false
            sphere.segmentCount = segmentCount ?? 48
            geometry = sphere
        case .box:
            geometry = SCNBox(
                width: width ?? 0,
                height: height ?? 0,
                length: length ?? 0,
                chamferRadius: chamferRadius ?? 0
            )
        case .cylinder:
            geometry = SCNCylinder(radius: radius ?? 0, height: height ?? 0)
        case .cone:
            geometry = SCNCone(topRadius: topRadius ?? 0, bottomRadius: bottomRadius ?? 0, height: height ?? 0)
        case .capsule:
            geometry = SCNCapsule(capRadius: capRadius ?? 0, height: height ?? 0)
        case .tube:
            geometry = SCNTube(innerRadius: innerRadius ?? 0, outerRadius: outerRadius ?? 0, height: height ?? 0)
        case .torus:
            geometry = SCNTorus(ringRadius: ringRadius ?? 0, pipeRadius: pipeRadius ?? 0)
        case .plane:
            geometry = SCNPlane(width: width ?? 0, height: height ?? 0)
        case .pyramid:
            geometry = SCNPyramid(width: width ?? 0, height: height ?? 0, length: length ?? 0)
        case .text:
            let text = SCNText(string: string, extrusionDepth: extrusionDepth ?? 0)
            text.flatness = flatness ?? 0.6
            text.chamferRadius = chamferRadius ?? 0
            geometry = text
        case .shape:
            let shape = SCNShape(path: nil, extrusionDepth: extrusionDepth ?? 0)
            shape.chamferRadius = chamferRadius ?? 0
            geometry = shape
        }

        geometry.name = name
        geometry.materials = materials.map(\.material)
        geometry.geometrySourceChannels = geometrySourceChannels?.map { NSNumber(value: $0) }
        return geometry
    }
}

private struct QuillSceneGeometrySourceArchive: Codable {
    var data: Data
    var semantic: String
    var vectorCount: Int
    var usesFloatComponents: Bool
    var componentsPerVector: Int
    var bytesPerComponent: Int
    var dataOffset: Int
    var dataStride: Int

    init(_ source: SCNGeometrySource) {
        data = source.data
        semantic = source.semantic.rawValue
        vectorCount = source.vectorCount
        usesFloatComponents = source.usesFloatComponents
        componentsPerVector = source.componentsPerVector
        bytesPerComponent = source.bytesPerComponent
        dataOffset = source.dataOffset
        dataStride = source.dataStride
    }

    var source: SCNGeometrySource {
        SCNGeometrySource(
            data: data,
            semantic: SCNGeometrySourceSemantic(rawValue: semantic) ?? .vertex,
            vectorCount: vectorCount,
            usesFloatComponents: usesFloatComponents,
            componentsPerVector: componentsPerVector,
            bytesPerComponent: bytesPerComponent,
            dataOffset: dataOffset,
            dataStride: dataStride
        )
    }
}

private struct QuillSceneGeometryElementArchive: Codable {
    var data: Data
    var primitiveType: Int
    var primitiveCount: Int
    var bytesPerIndex: Int
    var indicesChannelCount: Int
    var hasInterleavedIndicesChannels: Bool

    init(_ element: SCNGeometryElement) {
        data = element.data
        primitiveType = element.primitiveType.rawValue
        primitiveCount = element.primitiveCount
        bytesPerIndex = element.bytesPerIndex
        indicesChannelCount = element.indicesChannelCount
        hasInterleavedIndicesChannels = element.hasInterleavedIndicesChannels
    }

    var element: SCNGeometryElement {
        let element = SCNGeometryElement(
            data: data,
            primitiveType: SCNGeometryPrimitiveType(rawValue: primitiveType) ?? .triangles,
            primitiveCount: primitiveCount,
            bytesPerIndex: bytesPerIndex
        )
        element.indicesChannelCount = indicesChannelCount
        element.hasInterleavedIndicesChannels = hasInterleavedIndicesChannels
        return element
    }
}

private struct QuillSceneMaterialArchive: Codable {
    var name: String?
    var diffuse: QuillSceneMaterialProperty
    var ambient: QuillSceneMaterialProperty
    var specular: QuillSceneMaterialProperty
    var emission: QuillSceneMaterialProperty
    var normal: QuillSceneMaterialProperty
    var metalness: QuillSceneMaterialProperty
    var roughness: QuillSceneMaterialProperty
    var multiply: QuillSceneMaterialProperty
    var transparent: QuillSceneMaterialProperty
    var transparency: CGFloat
    var transparencyMode: Int
    var readsFromDepthBuffer: Bool
    var writesToDepthBuffer: Bool
    var lightingModel: String
    var isDoubleSided: Bool
    var shininess: CGFloat

    init(_ material: SCNMaterial) {
        name = material.name
        diffuse = QuillSceneMaterialProperty(material.diffuse)
        ambient = QuillSceneMaterialProperty(material.ambient)
        specular = QuillSceneMaterialProperty(material.specular)
        emission = QuillSceneMaterialProperty(material.emission)
        normal = QuillSceneMaterialProperty(material.normal)
        metalness = QuillSceneMaterialProperty(material.metalness)
        roughness = QuillSceneMaterialProperty(material.roughness)
        multiply = QuillSceneMaterialProperty(material.multiply)
        transparent = QuillSceneMaterialProperty(material.transparent)
        transparency = material.transparency
        transparencyMode = material.transparencyMode.rawValue
        readsFromDepthBuffer = material.readsFromDepthBuffer
        writesToDepthBuffer = material.writesToDepthBuffer
        lightingModel = material.lightingModel.rawValue
        isDoubleSided = material.isDoubleSided
        shininess = material.shininess
    }

    var material: SCNMaterial {
        let material = SCNMaterial()
        material.name = name
        diffuse.apply(to: material.diffuse)
        ambient.apply(to: material.ambient)
        specular.apply(to: material.specular)
        emission.apply(to: material.emission)
        normal.apply(to: material.normal)
        metalness.apply(to: material.metalness)
        roughness.apply(to: material.roughness)
        multiply.apply(to: material.multiply)
        transparent.apply(to: material.transparent)
        material.transparency = transparency
        material.transparencyMode = SCNTransparencyMode(rawValue: transparencyMode) ?? .aOne
        material.readsFromDepthBuffer = readsFromDepthBuffer
        material.writesToDepthBuffer = writesToDepthBuffer
        material.lightingModel = SCNLightingModel(rawValue: lightingModel) ?? .blinn
        material.isDoubleSided = isDoubleSided
        material.shininess = shininess
        return material
    }
}

private struct QuillSceneMaterialProperty: Codable {
    var color: QuillSceneColor?
    var intensity: CGFloat
    var wrapS: Int
    var wrapT: Int
    var magnificationFilter: Int
    var minificationFilter: Int
    var mipFilter: Int

    init(_ property: SCNMaterialProperty) {
        color = QuillSceneColor(property.contents)
        intensity = property.intensity
        wrapS = property.wrapS.rawValue
        wrapT = property.wrapT.rawValue
        magnificationFilter = property.magnificationFilter.rawValue
        minificationFilter = property.minificationFilter.rawValue
        mipFilter = property.mipFilter.rawValue
    }

    func apply(to property: SCNMaterialProperty) {
        property.contents = color?.cgColor
        property.intensity = intensity
        property.wrapS = SCNWrapMode(rawValue: wrapS) ?? .clamp
        property.wrapT = SCNWrapMode(rawValue: wrapT) ?? .clamp
        property.magnificationFilter = SCNFilterMode(rawValue: magnificationFilter) ?? .linear
        property.minificationFilter = SCNFilterMode(rawValue: minificationFilter) ?? .linear
        property.mipFilter = SCNFilterMode(rawValue: mipFilter) ?? .nearest
    }
}

private struct QuillSceneLightArchive: Codable {
    var type: String
    var color: QuillSceneColor?
    var shadowColor: QuillSceneColor?
    var intensity: CGFloat
    var temperature: CGFloat
    var castsShadow: Bool
    var name: String?
    var spotInnerAngle: CGFloat
    var spotOuterAngle: CGFloat
    var attenuationStartDistance: CGFloat
    var attenuationEndDistance: CGFloat

    init(_ light: SCNLight) {
        type = light.type.rawValue
        color = QuillSceneColor(light.color)
        shadowColor = QuillSceneColor(light.shadowColor)
        intensity = light.intensity
        temperature = light.temperature
        castsShadow = light.castsShadow
        name = light.name
        spotInnerAngle = light.spotInnerAngle
        spotOuterAngle = light.spotOuterAngle
        attenuationStartDistance = light.attenuationStartDistance
        attenuationEndDistance = light.attenuationEndDistance
    }

    func makeLight() -> SCNLight {
        let light = SCNLight()
        light.type = SCNLight.LightType(rawValue: type) ?? .omni
        light.color = color?.cgColor
        light.shadowColor = shadowColor?.cgColor
        light.intensity = intensity
        light.temperature = temperature
        light.castsShadow = castsShadow
        light.name = name
        light.spotInnerAngle = spotInnerAngle
        light.spotOuterAngle = spotOuterAngle
        light.attenuationStartDistance = attenuationStartDistance
        light.attenuationEndDistance = attenuationEndDistance
        return light
    }
}

private struct QuillSceneCameraArchive: Codable {
    var name: String?
    var zNear: Double
    var zFar: Double
    var fieldOfView: CGFloat
    var usesOrthographicProjection: Bool
    var orthographicScale: Double
    var automaticallyAdjustsZRange: Bool

    init(_ camera: SCNCamera) {
        name = camera.name
        zNear = camera.zNear
        zFar = camera.zFar
        fieldOfView = camera.fieldOfView
        usesOrthographicProjection = camera.usesOrthographicProjection
        orthographicScale = camera.orthographicScale
        automaticallyAdjustsZRange = camera.automaticallyAdjustsZRange
    }

    func makeCamera() -> SCNCamera {
        let camera = SCNCamera()
        camera.name = name
        camera.zNear = zNear
        camera.zFar = zFar
        camera.fieldOfView = fieldOfView
        camera.usesOrthographicProjection = usesOrthographicProjection
        camera.orthographicScale = orthographicScale
        camera.automaticallyAdjustsZRange = automaticallyAdjustsZRange
        return camera
    }
}

private struct QuillSceneColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init?(_ contents: Any?) {
        let components: [CGFloat]?
        switch contents {
        case let color as RSColor:
            components = color.components
        case let color as RSCGColor:
            components = color.components
        default:
            return nil
        }
        guard let components, !components.isEmpty else { return nil }
        if components.count == 2 {
            red = components[0]
            green = components[0]
            blue = components[0]
            alpha = components[1]
        } else {
            red = components[0]
            green = components.count > 1 ? components[1] : components[0]
            blue = components.count > 2 ? components[2] : components[0]
            alpha = components.count > 3 ? components[3] : 1
        }
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

private struct QuillSceneVector3: Codable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    init(_ vector: SCNVector3) {
        x = vector.x
        y = vector.y
        z = vector.z
    }

    var scnVector: SCNVector3 {
        SCNVector3(x, y, z)
    }
}

private struct QuillSceneVector4: Codable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
    var w: CGFloat

    init(_ vector: SCNVector4) {
        x = vector.x
        y = vector.y
        z = vector.z
        w = vector.w
    }

    var scnVector: SCNVector4 {
        SCNVector4(x, y, z, w)
    }
}

private struct QuillSceneMatrix4: Codable {
    var m11: CGFloat
    var m12: CGFloat
    var m13: CGFloat
    var m14: CGFloat
    var m21: CGFloat
    var m22: CGFloat
    var m23: CGFloat
    var m24: CGFloat
    var m31: CGFloat
    var m32: CGFloat
    var m33: CGFloat
    var m34: CGFloat
    var m41: CGFloat
    var m42: CGFloat
    var m43: CGFloat
    var m44: CGFloat

    init(_ matrix: SCNMatrix4) {
        m11 = matrix.m11; m12 = matrix.m12; m13 = matrix.m13; m14 = matrix.m14
        m21 = matrix.m21; m22 = matrix.m22; m23 = matrix.m23; m24 = matrix.m24
        m31 = matrix.m31; m32 = matrix.m32; m33 = matrix.m33; m34 = matrix.m34
        m41 = matrix.m41; m42 = matrix.m42; m43 = matrix.m43; m44 = matrix.m44
    }

    var scnMatrix: SCNMatrix4 {
        SCNMatrix4(
            m11: m11, m12: m12, m13: m13, m14: m14,
            m21: m21, m22: m22, m23: m23, m24: m24,
            m31: m31, m32: m32, m33: m33, m34: m34,
            m41: m41, m42: m42, m43: m43, m44: m44
        )
    }
}

private extension SCNMatrix4 {
    func quillApproximatelyEquals(_ other: SCNMatrix4, tolerance: CGFloat = 0.000001) -> Bool {
        abs(m11 - other.m11) <= tolerance &&
            abs(m12 - other.m12) <= tolerance &&
            abs(m13 - other.m13) <= tolerance &&
            abs(m14 - other.m14) <= tolerance &&
            abs(m21 - other.m21) <= tolerance &&
            abs(m22 - other.m22) <= tolerance &&
            abs(m23 - other.m23) <= tolerance &&
            abs(m24 - other.m24) <= tolerance &&
            abs(m31 - other.m31) <= tolerance &&
            abs(m32 - other.m32) <= tolerance &&
            abs(m33 - other.m33) <= tolerance &&
            abs(m34 - other.m34) <= tolerance &&
            abs(m41 - other.m41) <= tolerance &&
            abs(m42 - other.m42) <= tolerance &&
            abs(m43 - other.m43) <= tolerance &&
            abs(m44 - other.m44) <= tolerance
    }
}
