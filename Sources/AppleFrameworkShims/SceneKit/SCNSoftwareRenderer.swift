// SceneKit shim — deterministic software rasterizer.
//
// This is intentionally small and CPU-only. It walks the retained SceneKit
// graph, projects simple primitives and SCNGeometry source/element meshes, and
// returns a CGImage backed by QuillFoundation BGRA pixels. GTK/AppKit hosts can
// draw that image through the existing CGContext bridge.
import Foundation
import QuillFoundation

enum QuillSceneKitRenderSupport {
    static func pixelCount(_ value: Int) -> Int {
        max(1, value)
    }

    static func pixelCount(_ value: CGFloat) -> Int {
        max(1, Int(value.rounded(.toNearestOrAwayFromZero)))
    }

    static func image(width: Int, height: Int, bgraPixels: [UInt8]) -> CGImage {
        let width = pixelCount(width)
        let height = pixelCount(height)
        let image = CGImage()
        image.width = width
        image.height = height
        image.quillBytesPerRow = width * 4
        image.quillBGRAPixels = bgraPixels
        return image
    }

    static func solidImage(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8, a: UInt8 = 255) -> CGImage {
        let width = pixelCount(width)
        let height = pixelCount(height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = b
            pixels[offset + 1] = g
            pixels[offset + 2] = r
            pixels[offset + 3] = a
        }
        return image(width: width, height: height, bgraPixels: pixels)
    }
}

public extension SCNScene {
    /// Render the scene into a BGRA-backed CGImage using QuillOS' software
    /// SceneKit fallback. This is the rung-3/4 deterministic render surface:
    /// fixture views call it for GTK pixels, and tests can inspect the image
    /// without launching a full app.
    func quillRenderImage(
        width: Int,
        height: Int,
        pointOfView: SCNNode? = nil
    ) -> CGImage {
        SCNSoftwareRenderer(scene: self, pointOfView: pointOfView)
            .render(width: width, height: height)
    }

    #if canImport(UIKit)
    /// Projected hit testing for QuillOS' software SceneKit fallback. Results
    /// are ordered nearest-first, matching SceneKit's practical selection
    /// behavior for the app code in this lane.
    func quillHitTest(
        _ point: CGPoint,
        width: Int,
        height: Int,
        pointOfView: SCNNode? = nil,
        searchMode: SCNHitTestSearchMode = .closest,
        categoryBitMask: Int? = nil,
        rootNode: SCNNode? = nil
    ) -> [SCNHitTestResult] {
        SCNSoftwareRenderer(scene: self, pointOfView: pointOfView)
            .hitTest(
                point: point,
                width: width,
                height: height,
                searchMode: searchMode,
                categoryBitMask: categoryBitMask,
                rootNode: rootNode
            )
    }
    #endif

    func quillProjectPoint(
        _ point: SCNVector3,
        width: Int,
        height: Int,
        pointOfView: SCNNode? = nil
    ) -> SCNVector3? {
        SCNSoftwareRenderer(scene: self, pointOfView: pointOfView)
            .projectPoint(point, width: width, height: height)
    }

    func quillUnprojectPoint(
        _ point: SCNVector3,
        width: Int,
        height: Int,
        pointOfView: SCNNode? = nil
    ) -> SCNVector3? {
        SCNSoftwareRenderer(scene: self, pointOfView: pointOfView)
            .unprojectPoint(point, width: width, height: height)
    }
}

public struct SCNSoftwareRenderer {
    public let scene: SCNScene
    public let pointOfView: SCNNode?

    public init(scene: SCNScene, pointOfView: SCNNode? = nil) {
        self.scene = scene
        self.pointOfView = pointOfView
    }

    public func render(width: Int, height: Int) -> CGImage {
        let width = QuillSceneKitRenderSupport.pixelCount(width)
        let height = QuillSceneKitRenderSupport.pixelCount(height)
        var surface = PixelSurface(width: width, height: height, background: color(from: scene.background.contents) ?? .black)
        for primitive in projectedPrimitives(width: width, height: height).sorted(by: Self.renderOrder) {
            primitive.draw(into: &surface)
        }

        return QuillSceneKitRenderSupport.image(width: width, height: height, bgraPixels: surface.pixels)
    }

    #if canImport(UIKit)
    public func hitTest(
        point: CGPoint,
        width: Int,
        height: Int,
        searchMode: SCNHitTestSearchMode = .closest,
        categoryBitMask: Int? = nil,
        rootNode: SCNNode? = nil
    ) -> [SCNHitTestResult] {
        let hits = projectedPrimitives(width: max(1, width), height: max(1, height))
            .filter { primitive in
                guard categoryBitMask.map({ primitive.node.categoryBitMask & $0 != 0 }) ?? true else {
                    return false
                }
                guard rootNode.map({ primitive.node.quillIsDescendantOrSelf(of: $0) }) ?? true else {
                    return false
                }
                return true
            }
            .filter { $0.contains(point) }
            .sorted { $0.depth < $1.depth }
            .map { SCNHitTestResult(node: $0.node, geometryIndex: $0.geometryIndex) }

        switch searchMode {
        case .closest:
            return Array(hits.prefix(1))
        case .all:
            return hits
        }
    }
    #endif

    public func projectPoint(_ point: SCNVector3, width: Int, height: Int) -> SCNVector3? {
        projectionContext(width: width, height: height).camera.projectWorldPoint(Vector3(point))
    }

    public func unprojectPoint(_ point: SCNVector3, width: Int, height: Int) -> SCNVector3? {
        projectionContext(width: width, height: height).camera.unprojectScreenPoint(point)
    }

    private func projectedPrimitives(width: Int, height: Int) -> [ProjectedPrimitive] {
        let context = projectionContext(width: width, height: height)
        return context.collector.primitives.flatMap { $0.projected(using: context.camera) }
    }

    private static func renderOrder(_ lhs: ProjectedPrimitive, _ rhs: ProjectedPrimitive) -> Bool {
        if lhs.renderingOrder != rhs.renderingOrder {
            return lhs.renderingOrder < rhs.renderingOrder
        }
        return lhs.depth > rhs.depth
    }

    private func projectionContext(width: Int, height: Int) -> ProjectionContext {
        let rootTransform = Matrix4.identity
        var collector = RenderCollector()
        collector.collect(node: scene.rootNode, parent: rootTransform, inheritedOpacity: 1)

        let bounds = collector.bounds ?? Bounds(min: Vector3(-1, -1, -1), max: Vector3(1, 1, 1))
        let cameraNode = pointOfView ?? collector.cameraNode
        let cameraWorld = pointOfView.map(Matrix4.worldTransform) ?? collector.cameraWorldTransform
        let camera = CameraProjection(
            cameraNode: cameraNode,
            cameraWorld: cameraWorld,
            bounds: bounds,
            width: max(1, width),
            height: max(1, height)
        )

        return ProjectionContext(collector: collector, camera: camera)
    }
}

private struct ProjectionContext {
    var collector: RenderCollector
    var camera: CameraProjection
}

private extension SCNNode {
    func quillIsDescendantOrSelf(of root: SCNNode) -> Bool {
        var node: SCNNode? = self
        while let current = node {
            if current === root {
                return true
            }
            node = current.parent
        }
        return false
    }
}

// MARK: - Scene collection

private struct RenderCollector {
    var primitives: [WorldPrimitive] = []
    var bounds: Bounds?
    var cameraNode: SCNNode?
    var cameraWorldTransform: Matrix4?

    mutating func collect(node: SCNNode, parent: Matrix4, inheritedOpacity: CGFloat) {
        let opacity = inheritedOpacity * max(0, min(1, node.opacity))
        guard !node.isHidden, opacity > 0 else { return }
        let world = parent * Matrix4.localTransform(for: node)
        if node.camera != nil, cameraNode == nil {
            cameraNode = node
            cameraWorldTransform = world
        }
        if let geometry = node.geometry {
            collect(geometry: geometry, node: node, world: world, opacity: opacity)
        }
        for child in node.childNodes {
            collect(node: child, parent: world, inheritedOpacity: opacity)
        }
    }

    private mutating func include(_ point: Vector3) {
        if var existing = bounds {
            existing.include(point)
            bounds = existing
        } else {
            bounds = Bounds(min: point, max: point)
        }
    }

    private mutating func collect(geometry: SCNGeometry, node: SCNNode, world: Matrix4, opacity: CGFloat) {
        let baseColor = color(for: geometry, elementIndex: 0).withAlphaMultiplier(opacity)

        switch geometry {
        case let sphere as SCNSphere:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let center = world.transformPoint(.zero)
            let radius = max(0.001, world.approximateScale * sphere.radius)
            include(center - Vector3(radius, radius, radius))
            include(center + Vector3(radius, radius, radius))
            primitives.append(.sphere(center: center, radius: radius, color: baseColor, owner: owner))
            return

        case let cylinder as SCNCylinder:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let a = world.transformPoint(Vector3(0, -cylinder.height / 2, 0))
            let b = world.transformPoint(Vector3(0, cylinder.height / 2, 0))
            let radius = max(0.001, world.approximateScale * cylinder.radius)
            include(a - Vector3(radius, radius, radius))
            include(a + Vector3(radius, radius, radius))
            include(b - Vector3(radius, radius, radius))
            include(b + Vector3(radius, radius, radius))
            primitives.append(.line(a: a, b: b, radius: radius, color: baseColor, owner: owner))
            return

        case let cone as SCNCone:
            appendFrustumSurface(
                bottomRadius: cone.bottomRadius,
                topRadius: cone.topRadius,
                height: cone.height,
                world: world,
                color: baseColor,
                owner: PrimitiveOwner(node: node, geometryIndex: 0)
            )
            return

        case let capsule as SCNCapsule:
            appendCapsule(
                capRadius: capsule.capRadius,
                height: capsule.height,
                world: world,
                color: baseColor,
                owner: PrimitiveOwner(node: node, geometryIndex: 0)
            )
            return

        case let tube as SCNTube:
            appendTubeSurface(
                innerRadius: tube.innerRadius,
                outerRadius: tube.outerRadius,
                height: tube.height,
                world: world,
                color: baseColor,
                owner: PrimitiveOwner(node: node, geometryIndex: 0)
            )
            return

        case let torus as SCNTorus:
            appendTorusSurface(
                ringRadius: torus.ringRadius,
                pipeRadius: torus.pipeRadius,
                world: world,
                color: baseColor,
                owner: PrimitiveOwner(node: node, geometryIndex: 0)
            )
            return

        case let box as SCNBox:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let hx = box.width / 2
            let hy = box.height / 2
            let hz = box.length / 2
            appendSurface(
                localVertices: [
                    Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
                    Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
                    Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
                    Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
                ],
                faces: [
                    (0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6),
                    (0, 4, 5), (0, 5, 1), (1, 5, 6), (1, 6, 2),
                    (2, 6, 7), (2, 7, 3), (3, 7, 4), (3, 4, 0),
                ],
                world: world,
                color: baseColor,
                owner: owner
            )
            return

        case let plane as SCNPlane:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let hx = plane.width / 2
            let hy = plane.height / 2
            appendSurface(
                localVertices: [
                    Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0),
                    Vector3(hx, hy, 0), Vector3(-hx, hy, 0),
                ],
                faces: [(0, 1, 2), (0, 2, 3)],
                world: world,
                color: baseColor,
                owner: owner
            )
            return

        case let pyramid as SCNPyramid:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let hx = pyramid.width / 2
            let hy = pyramid.height / 2
            let hz = pyramid.length / 2
            appendSurface(
                localVertices: [
                    Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
                    Vector3(hx, -hy, hz), Vector3(-hx, -hy, hz),
                    Vector3(0, hy, 0),
                ],
                faces: [
                    (0, 2, 1), (0, 3, 2),
                    (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4),
                ],
                world: world,
                color: baseColor,
                owner: owner
            )
            return

        default:
            break
        }

        collectBufferedGeometry(geometry, node: node, world: world, opacity: opacity)
    }

    private mutating func appendCapsule(
        capRadius: CGFloat,
        height: CGFloat,
        world: Matrix4,
        color: RGBA,
        owner: PrimitiveOwner
    ) {
        let capRadius = max(0, capRadius)
        let height = max(0, height)
        let radius = max(0.001, world.approximateScale * capRadius)
        let halfCylinder = max(0, height / 2 - capRadius)
        let a = world.transformPoint(Vector3(0, -halfCylinder, 0))
        let b = world.transformPoint(Vector3(0, halfCylinder, 0))
        include(a - Vector3(radius, radius, radius))
        include(a + Vector3(radius, radius, radius))
        include(b - Vector3(radius, radius, radius))
        include(b + Vector3(radius, radius, radius))
        if halfCylinder <= 0.0001 {
            primitives.append(.sphere(center: world.transformPoint(.zero), radius: radius, color: color, owner: owner))
        } else {
            primitives.append(.line(a: a, b: b, radius: radius, color: color, owner: owner))
        }
    }

    private mutating func appendFrustumSurface(
        bottomRadius: CGFloat,
        topRadius: CGFloat,
        height: CGFloat,
        world: Matrix4,
        color: RGBA,
        owner: PrimitiveOwner
    ) {
        let bottomRadius = max(0, bottomRadius)
        let topRadius = max(0, topRadius)
        let height = max(0.001, height)
        guard bottomRadius > 0 || topRadius > 0 else { return }

        let segmentCount = 32
        let bottomY = -height / 2
        let topY = height / 2
        var vertices: [Vector3] = []
        var faces: [(Int, Int, Int)] = []

        func appendVertex(_ vertex: Vector3) -> Int {
            vertices.append(vertex)
            return vertices.count - 1
        }

        func appendRing(radius: CGFloat, y: CGFloat) -> [Int] {
            (0..<segmentCount).map { segment in
                let angle = CGFloat(segment) * 2 * .pi / CGFloat(segmentCount)
                return appendVertex(Vector3(cos(angle) * radius, y, sin(angle) * radius))
            }
        }

        let bottomRing = bottomRadius > 0 ? appendRing(radius: bottomRadius, y: bottomY) : []
        let topRing = topRadius > 0 ? appendRing(radius: topRadius, y: topY) : []
        let bottomApex = bottomRing.isEmpty ? appendVertex(Vector3(0, bottomY, 0)) : nil
        let topApex = topRing.isEmpty ? appendVertex(Vector3(0, topY, 0)) : nil

        for segment in 0..<segmentCount {
            let next = (segment + 1) % segmentCount
            switch (bottomRing.isEmpty, topRing.isEmpty) {
            case (false, false):
                faces.append((bottomRing[segment], bottomRing[next], topRing[next]))
                faces.append((bottomRing[segment], topRing[next], topRing[segment]))
            case (false, true):
                if let topApex {
                    faces.append((bottomRing[segment], bottomRing[next], topApex))
                }
            case (true, false):
                if let bottomApex {
                    faces.append((bottomApex, topRing[next], topRing[segment]))
                }
            case (true, true):
                break
            }
        }

        if !bottomRing.isEmpty {
            let center = appendVertex(Vector3(0, bottomY, 0))
            for segment in 0..<segmentCount {
                faces.append((center, bottomRing[(segment + 1) % segmentCount], bottomRing[segment]))
            }
        }
        if !topRing.isEmpty {
            let center = appendVertex(Vector3(0, topY, 0))
            for segment in 0..<segmentCount {
                faces.append((center, topRing[segment], topRing[(segment + 1) % segmentCount]))
            }
        }

        appendSurface(localVertices: vertices, faces: faces, world: world, color: color, owner: owner)
    }

    private mutating func appendTubeSurface(
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        height: CGFloat,
        world: Matrix4,
        color: RGBA,
        owner: PrimitiveOwner
    ) {
        let outerRadius = max(0, outerRadius)
        guard outerRadius > 0 else { return }
        let innerRadius = max(0, min(innerRadius, outerRadius * 0.95))
        let height = max(0.001, height)
        guard innerRadius > 0 else {
            appendFrustumSurface(
                bottomRadius: outerRadius,
                topRadius: outerRadius,
                height: height,
                world: world,
                color: color,
                owner: owner
            )
            return
        }

        let segmentCount = 32
        let bottomY = -height / 2
        let topY = height / 2
        var vertices: [Vector3] = []
        var faces: [(Int, Int, Int)] = []

        func appendRing(radius: CGFloat, y: CGFloat) -> [Int] {
            (0..<segmentCount).map { segment in
                let angle = CGFloat(segment) * 2 * .pi / CGFloat(segmentCount)
                vertices.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
                return vertices.count - 1
            }
        }

        let outerBottom = appendRing(radius: outerRadius, y: bottomY)
        let outerTop = appendRing(radius: outerRadius, y: topY)
        let innerBottom = appendRing(radius: innerRadius, y: bottomY)
        let innerTop = appendRing(radius: innerRadius, y: topY)

        for segment in 0..<segmentCount {
            let next = (segment + 1) % segmentCount
            faces.append((outerBottom[segment], outerBottom[next], outerTop[next]))
            faces.append((outerBottom[segment], outerTop[next], outerTop[segment]))
            faces.append((innerBottom[segment], innerTop[next], innerBottom[next]))
            faces.append((innerBottom[segment], innerTop[segment], innerTop[next]))
            faces.append((outerTop[segment], outerTop[next], innerTop[next]))
            faces.append((outerTop[segment], innerTop[next], innerTop[segment]))
            faces.append((outerBottom[next], outerBottom[segment], innerBottom[segment]))
            faces.append((outerBottom[next], innerBottom[segment], innerBottom[next]))
        }

        appendSurface(localVertices: vertices, faces: faces, world: world, color: color, owner: owner)
    }

    private mutating func appendTorusSurface(
        ringRadius: CGFloat,
        pipeRadius: CGFloat,
        world: Matrix4,
        color: RGBA,
        owner: PrimitiveOwner
    ) {
        let ringRadius = max(0, ringRadius)
        let pipeRadius = max(0, pipeRadius)
        guard ringRadius > 0, pipeRadius > 0 else { return }

        let ringSegments = 32
        let pipeSegments = 16
        var vertices: [Vector3] = []
        var faces: [(Int, Int, Int)] = []

        func vertexIndex(ring: Int, pipe: Int) -> Int {
            ring * pipeSegments + pipe
        }

        for ring in 0..<ringSegments {
            let ringAngle = CGFloat(ring) * 2 * .pi / CGFloat(ringSegments)
            let radialX = cos(ringAngle)
            let radialY = sin(ringAngle)
            for pipe in 0..<pipeSegments {
                let pipeAngle = CGFloat(pipe) * 2 * .pi / CGFloat(pipeSegments)
                let radialDistance = ringRadius + pipeRadius * cos(pipeAngle)
                vertices.append(Vector3(
                    radialX * radialDistance,
                    radialY * radialDistance,
                    pipeRadius * sin(pipeAngle)
                ))
            }
        }

        for ring in 0..<ringSegments {
            let nextRing = (ring + 1) % ringSegments
            for pipe in 0..<pipeSegments {
                let nextPipe = (pipe + 1) % pipeSegments
                let a = vertexIndex(ring: ring, pipe: pipe)
                let b = vertexIndex(ring: nextRing, pipe: pipe)
                let c = vertexIndex(ring: nextRing, pipe: nextPipe)
                let d = vertexIndex(ring: ring, pipe: nextPipe)
                faces.append((a, b, c))
                faces.append((a, c, d))
            }
        }

        appendSurface(localVertices: vertices, faces: faces, world: world, color: color, owner: owner)
    }

    private mutating func appendSurface(
        localVertices: [Vector3],
        faces: [(Int, Int, Int)],
        world: Matrix4,
        color: RGBA,
        owner: PrimitiveOwner
    ) {
        let vertices = localVertices.map(world.transformPoint)
        for vertex in vertices { include(vertex) }
        for (i0, i1, i2) in faces {
            appendTriangle(i0, i1, i2, vertices: vertices, color: color, owner: owner)
        }
    }

    private mutating func collectBufferedGeometry(_ geometry: SCNGeometry, node: SCNNode, world: Matrix4, opacity: CGFloat) {
        guard let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }) else { return }
        let vertices = vertexSource.quillVector3Values().map(Vector3.init)
        guard !vertices.isEmpty else { return }
        let worldVertices = vertices.map(world.transformPoint)
        let vertexColors = geometry.sources.first(where: { $0.semantic == .color })?.quillColorValues()
        for vertex in worldVertices { include(vertex) }

        for (elementIndex, element) in geometry.elements.enumerated() {
            let owner = PrimitiveOwner(node: node, geometryIndex: elementIndex)
            let primitiveColor = color(for: geometry, elementIndex: elementIndex).withAlphaMultiplier(opacity)
            let indices = element.quillIndices()
            switch element.primitiveType {
            case .triangles:
                var i = 0
                while i + 2 < indices.count {
                    appendTriangle(indices[i], indices[i + 1], indices[i + 2], vertices: worldVertices, color: primitiveColor, vertexColors: vertexColors, owner: owner)
                    i += 3
                }
            case .triangleStrip:
                guard indices.count >= 3 else { continue }
                for i in 0..<(indices.count - 2) {
                    if i.isMultiple(of: 2) {
                        appendTriangle(indices[i], indices[i + 1], indices[i + 2], vertices: worldVertices, color: primitiveColor, vertexColors: vertexColors, owner: owner)
                    } else {
                        appendTriangle(indices[i + 1], indices[i], indices[i + 2], vertices: worldVertices, color: primitiveColor, vertexColors: vertexColors, owner: owner)
                    }
                }
            case .line:
                var i = 0
                while i + 1 < indices.count {
                    appendLine(indices[i], indices[i + 1], vertices: worldVertices, color: primitiveColor, vertexColors: vertexColors, owner: owner)
                    i += 2
                }
            case .point:
                for index in indices where worldVertices.indices.contains(index) {
                    let p = worldVertices[index]
                    primitives.append(.sphere(center: p, radius: 0.025 * world.approximateScale, color: vertexColor(vertexColors, at: index, fallback: primitiveColor), owner: owner))
                }
            case .polygon:
                appendPolygons(from: element, vertices: worldVertices, color: primitiveColor, vertexColors: vertexColors, owner: owner)
            }
        }
    }

    private mutating func appendTriangle(
        _ i0: Int,
        _ i1: Int,
        _ i2: Int,
        vertices: [Vector3],
        color: RGBA,
        vertexColors: [RGBA]? = nil,
        owner: PrimitiveOwner
    ) {
        guard vertices.indices.contains(i0), vertices.indices.contains(i1), vertices.indices.contains(i2) else { return }
        primitives.append(.triangle(
            a: WorldVertex(position: vertices[i0], color: vertexColor(vertexColors, at: i0, fallback: color)),
            b: WorldVertex(position: vertices[i1], color: vertexColor(vertexColors, at: i1, fallback: color)),
            c: WorldVertex(position: vertices[i2], color: vertexColor(vertexColors, at: i2, fallback: color)),
            owner: owner
        ))
    }

    private mutating func appendLine(_ i0: Int, _ i1: Int, vertices: [Vector3], color: RGBA, vertexColors: [RGBA]? = nil, owner: PrimitiveOwner) {
        guard vertices.indices.contains(i0), vertices.indices.contains(i1) else { return }
        let color = RGBA.average(
            vertexColor(vertexColors, at: i0, fallback: color),
            vertexColor(vertexColors, at: i1, fallback: color)
        )
        primitives.append(.line(a: vertices[i0], b: vertices[i1], radius: 0.012, color: color, owner: owner))
    }

    private mutating func appendPolygons(from element: SCNGeometryElement, vertices: [Vector3], color: RGBA, vertexColors: [RGBA]? = nil, owner: PrimitiveOwner) {
        let raw = element.quillIndices()
        guard element.primitiveCount > 0, raw.count >= element.primitiveCount else { return }
        let counts = Array(raw.prefix(element.primitiveCount))
        var offset = element.primitiveCount
        for count in counts {
            guard offset + count <= raw.count else { return }
            let polygon = Array(raw[offset..<(offset + count)])
            offset += count
            guard count >= 3 else { continue }
            for index in 1..<(polygon.count - 1) {
                appendTriangle(polygon[0], polygon[index], polygon[index + 1], vertices: vertices, color: color, vertexColors: vertexColors, owner: owner)
            }
        }
    }

    private func vertexColor(_ vertexColors: [RGBA]?, at index: Int, fallback: RGBA) -> RGBA {
        guard let vertexColors, vertexColors.indices.contains(index) else {
            return fallback
        }
        return vertexColors[index].modulated(by: fallback)
    }
}

// MARK: - Projection and primitives

private struct PrimitiveOwner {
    let node: SCNNode
    let geometryIndex: Int
    let renderingOrder: Int
    let readsFromDepthBuffer: Bool
    let writesToDepthBuffer: Bool

    init(node: SCNNode, geometryIndex: Int) {
        self.node = node
        self.geometryIndex = geometryIndex
        self.renderingOrder = node.renderingOrder
        let resolvedMaterial: SCNMaterial?
        if let geometry = node.geometry {
            resolvedMaterial = material(for: geometry, elementIndex: geometryIndex)
        } else {
            resolvedMaterial = nil
        }
        self.readsFromDepthBuffer = resolvedMaterial?.readsFromDepthBuffer ?? true
        self.writesToDepthBuffer = resolvedMaterial?.writesToDepthBuffer ?? true
    }
}

private struct WorldVertex {
    var position: Vector3
    var color: RGBA
}

private enum WorldPrimitive {
    case sphere(center: Vector3, radius: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case line(a: Vector3, b: Vector3, radius: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case triangle(a: WorldVertex, b: WorldVertex, c: WorldVertex, owner: PrimitiveOwner)

    func projected(using camera: CameraProjection) -> [ProjectedPrimitive] {
        switch self {
        case let .sphere(center, radius, color, owner):
            guard let projectedCenter = camera.project(center) else { return [] }
            let projectedRadius = max(1.5, camera.projectedLength(radius, atDepth: projectedCenter.depth))
            return [.sphere(center: projectedCenter.point, radius: projectedRadius, depth: projectedCenter.depth, color: color, owner: owner)]
        case let .line(a, b, radius, color, owner):
            return camera.projectedLine(a: a, b: b, radius: radius, color: color, owner: owner)
        case let .triangle(a, b, c, owner):
            return camera.projectedTriangles(a: a, b: b, c: c, owner: owner)
        }
    }
}

private enum ProjectedPrimitive {
    case sphere(center: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case line(a: CGPoint, b: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case triangle(
        a: CGPoint,
        b: CGPoint,
        c: CGPoint,
        depthA: CGFloat,
        depthB: CGFloat,
        depthC: CGFloat,
        depth: CGFloat,
        colorA: RGBA,
        colorB: RGBA,
        colorC: RGBA,
        owner: PrimitiveOwner
    )

    var depth: CGFloat {
        switch self {
        case let .sphere(_, _, depth, _, _), let .line(_, _, _, depth, _, _), let .triangle(_, _, _, _, _, _, depth, _, _, _, _):
            return depth
        }
    }

    var renderingOrder: Int { owner.renderingOrder }

    private var owner: PrimitiveOwner {
        switch self {
        case let .sphere(_, _, _, _, owner), let .line(_, _, _, _, _, owner), let .triangle(_, _, _, _, _, _, _, _, _, _, owner):
            return owner
        }
    }

    var node: SCNNode { owner.node }

    var geometryIndex: Int {
        owner.geometryIndex
    }

    func draw(into surface: inout PixelSurface) {
        switch self {
        case let .sphere(center, radius, depth, color, owner):
            surface.fillCircle(center: center, radius: radius, depth: depth, color: color, owner: owner)
        case let .line(a, b, radius, depth, color, owner):
            surface.strokeCapsule(from: a, to: b, radius: radius, depth: depth, color: color, owner: owner)
        case let .triangle(a, b, c, depthA, depthB, depthC, _, colorA, colorB, colorC, owner):
            surface.fillTriangle(a, b, c, depths: (depthA, depthB, depthC), colors: (colorA, colorB, colorC), owner: owner)
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        switch self {
        case let .sphere(center, radius, _, _, _):
            let dx = point.x - center.x
            let dy = point.y - center.y
            let hitRadius = max(4, radius)
            return dx * dx + dy * dy <= hitRadius * hitRadius

        case let .line(a, b, radius, _, _, _):
            return squaredDistance(from: point, toSegmentFrom: a, to: b) <= pow(max(4, radius + 2), 2)

        case let .triangle(a, b, c, _, _, _, _, _, _, _, _):
            let area = edge(a, b, c)
            guard abs(area) > 0.0001 else { return false }
            let w0 = edge(b, c, point)
            let w1 = edge(c, a, point)
            let w2 = edge(a, b, point)
            return area > 0
                ? w0 >= -0.001 && w1 >= -0.001 && w2 >= -0.001
                : w0 <= 0.001 && w1 <= 0.001 && w2 <= 0.001
        }
    }

    private func edge(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
    }

    private func squaredDistance(from p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ab2 = ab.x * ab.x + ab.y * ab.y
        let t: CGFloat
        if ab2 <= 0.0001 {
            t = 0
        } else {
            t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / ab2))
        }
        let q = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        let dx = p.x - q.x
        let dy = p.y - q.y
        return dx * dx + dy * dy
    }
}

private struct CameraProjection {
    let width: Int
    let height: Int
    let position: Vector3
    let right: Vector3
    let up: Vector3
    let forward: Vector3
    let focalLength: CGFloat
    let orthographicScale: CGFloat?
    let zNear: CGFloat
    let zFar: CGFloat

    init(cameraNode: SCNNode?, cameraWorld: Matrix4?, bounds: Bounds, width: Int, height: Int) {
        self.width = width
        self.height = height
        let center = bounds.center
        let radius = max(1, bounds.radius)

        let cameraPosition = cameraWorld?.transformPoint(.zero) ?? Vector3(center.x, center.y, center.z + radius * 3)
        let fallbackForward = (center - cameraPosition).normalized(fallback: Vector3(0, 0, -1))
        let worldUp = abs(fallbackForward.y) > 0.95 ? Vector3(0, 0, 1) : Vector3(0, 1, 0)
        let forward: Vector3
        let right: Vector3
        let up: Vector3
        if let cameraWorld {
            forward = cameraWorld.transformDirection(Vector3(0, 0, -1)).normalized(fallback: fallbackForward)
            let rawUp = cameraWorld.transformDirection(Vector3(0, 1, 0)).normalized(fallback: worldUp)
            right = forward.cross(rawUp).normalized(fallback: forward.cross(worldUp).normalized(fallback: Vector3(1, 0, 0)))
            up = right.cross(forward).normalized(fallback: rawUp)
        } else {
            forward = fallbackForward
            right = forward.cross(worldUp).normalized(fallback: Vector3(1, 0, 0))
            up = right.cross(forward).normalized(fallback: Vector3(0, 1, 0))
        }

        let camera = cameraNode?.camera
        let fov = max(5, min(120, camera?.fieldOfView ?? 60))
        let focal = CGFloat(height) / 2 / tan((fov * .pi / 180) / 2)
        let ortho = camera?.usesOrthographicProjection == true
            ? CGFloat(max(0.001, camera?.orthographicScale ?? Double(radius * 2.4)))
            : nil
        let clipping = CameraClipping(camera: camera)

        self.position = cameraPosition
        self.forward = forward
        self.right = right
        self.up = up
        self.focalLength = focal
        self.orthographicScale = ortho
        self.zNear = clipping.near
        self.zFar = clipping.far
    }

    func project(_ point: Vector3) -> (point: CGPoint, depth: CGFloat)? {
        guard let projected = project(cameraSpaceVertex(for: point)) else {
            return nil
        }
        return (projected.point, projected.depth)
    }

    func projectWorldPoint(_ point: Vector3) -> SCNVector3? {
        guard let projected = project(point) else {
            return nil
        }

        return SCNVector3(
            projected.point.x,
            projected.point.y,
            normalizedDepth(for: projected.depth)
        )
    }

    func unprojectScreenPoint(_ point: SCNVector3) -> SCNVector3? {
        let depth = cameraDepth(forNormalizedDepth: point.z)
        guard depth.isFinite, depth > 0 else {
            return nil
        }

        let scale: CGFloat
        if let orthographicScale {
            scale = CGFloat(height) / orthographicScale
        } else {
            scale = focalLength / depth
        }
        guard scale.isFinite, abs(scale) > 0.000001 else {
            return nil
        }

        let cameraX = (point.x - CGFloat(width) / 2) / scale
        let cameraY = (CGFloat(height) / 2 - point.y) / scale
        let world = position + right * cameraX + up * cameraY + forward * depth
        return SCNVector3(world.x, world.y, world.z)
    }

    func projectedLine(a: Vector3, b: Vector3, radius: CGFloat, color: RGBA, owner: PrimitiveOwner) -> [ProjectedPrimitive] {
        var start = cameraSpaceVertex(for: a, color: color)
        var end = cameraSpaceVertex(for: b, color: color)
        guard clipSegment(&start, &end, atDepth: zNear, keeping: { $0.depth >= zNear }) else { return [] }
        if zFar < .greatestFiniteMagnitude / 2 {
            guard clipSegment(&start, &end, atDepth: zFar, keeping: { $0.depth <= zFar }) else { return [] }
        }
        guard let projectedStart = project(start), let projectedEnd = project(end) else { return [] }
        let depth = (projectedStart.depth + projectedEnd.depth) / 2
        let projectedRadius = max(1, projectedLength(radius, atDepth: depth))
        return [.line(
            a: projectedStart.point,
            b: projectedEnd.point,
            radius: projectedRadius,
            depth: depth,
            color: color,
            owner: owner
        )]
    }

    func projectedTriangles(a: WorldVertex, b: WorldVertex, c: WorldVertex, owner: PrimitiveOwner) -> [ProjectedPrimitive] {
        var polygon = [
            cameraSpaceVertex(for: a.position, color: a.color),
            cameraSpaceVertex(for: b.position, color: b.color),
            cameraSpaceVertex(for: c.position, color: c.color),
        ]
        polygon = clipped(polygon, atDepth: zNear, keeping: { $0.depth >= zNear })
        if zFar < .greatestFiniteMagnitude / 2 {
            polygon = clipped(polygon, atDepth: zFar, keeping: { $0.depth <= zFar })
        }
        guard polygon.count >= 3 else { return [] }

        let projected = polygon.compactMap(project)
        guard projected.count == polygon.count else { return [] }

        var triangles: [ProjectedPrimitive] = []
        triangles.reserveCapacity(projected.count - 2)
        for index in 1..<(projected.count - 1) {
            let pa = projected[0]
            let pb = projected[index]
            let pc = projected[index + 1]
            let depth = (pa.depth + pb.depth + pc.depth) / 3
            triangles.append(.triangle(
                a: pa.point,
                b: pb.point,
                c: pc.point,
                depthA: pa.depth,
                depthB: pb.depth,
                depthC: pc.depth,
                depth: depth,
                colorA: pa.color,
                colorB: pb.color,
                colorC: pc.color,
                owner: owner
            ))
        }
        return triangles
    }

    private func cameraSpaceVertex(for point: Vector3, color: RGBA = .neutral) -> CameraSpaceVertex {
        let relative = point - position
        return CameraSpaceVertex(
            x: relative.dot(right),
            y: relative.dot(up),
            depth: relative.dot(forward),
            color: color
        )
    }

    private func project(_ vertex: CameraSpaceVertex) -> (point: CGPoint, depth: CGFloat, color: RGBA)? {
        guard vertex.depth >= zNear, vertex.depth <= zFar else { return nil }
        let scale: CGFloat
        if let orthographicScale {
            scale = CGFloat(height) / orthographicScale
        } else {
            scale = focalLength / vertex.depth
        }
        return (
            CGPoint(
                x: CGFloat(width) / 2 + vertex.x * scale,
                y: CGFloat(height) / 2 - vertex.y * scale
            ),
            vertex.depth,
            vertex.color
        )
    }

    private func clipped(
        _ input: [CameraSpaceVertex],
        atDepth boundaryDepth: CGFloat,
        keeping isInside: (CameraSpaceVertex) -> Bool
    ) -> [CameraSpaceVertex] {
        guard let last = input.last else { return [] }
        var output: [CameraSpaceVertex] = []
        output.reserveCapacity(input.count + 1)

        var previous = last
        var previousInside = isInside(previous)
        for current in input {
            let currentInside = isInside(current)
            if currentInside {
                if !previousInside {
                    output.append(previous.interpolated(to: current, atDepth: boundaryDepth))
                }
                output.append(current)
            } else if previousInside {
                output.append(previous.interpolated(to: current, atDepth: boundaryDepth))
            }
            previous = current
            previousInside = currentInside
        }
        return output
    }

    private func clipSegment(
        _ start: inout CameraSpaceVertex,
        _ end: inout CameraSpaceVertex,
        atDepth boundaryDepth: CGFloat,
        keeping isInside: (CameraSpaceVertex) -> Bool
    ) -> Bool {
        let startInside = isInside(start)
        let endInside = isInside(end)
        switch (startInside, endInside) {
        case (true, true):
            return true
        case (false, false):
            return false
        case (true, false):
            end = start.interpolated(to: end, atDepth: boundaryDepth)
            return true
        case (false, true):
            start = start.interpolated(to: end, atDepth: boundaryDepth)
            return true
        }
    }

    func projectedLength(_ length: CGFloat, atDepth depth: CGFloat) -> CGFloat {
        if let orthographicScale {
            return length * CGFloat(height) / orthographicScale
        }
        return length * focalLength / max(0.001, depth)
    }

    private func normalizedDepth(for depth: CGFloat) -> CGFloat {
        guard zFar < .greatestFiniteMagnitude / 2 else {
            return depth
        }
        return (depth - zNear) / max(0.001, zFar - zNear)
    }

    private func cameraDepth(forNormalizedDepth depth: CGFloat) -> CGFloat {
        guard zFar < .greatestFiniteMagnitude / 2 else {
            return depth
        }
        return zNear + depth * max(0.001, zFar - zNear)
    }
}

private struct CameraSpaceVertex {
    var x: CGFloat
    var y: CGFloat
    var depth: CGFloat
    var color: RGBA

    func interpolated(to other: CameraSpaceVertex, atDepth targetDepth: CGFloat) -> CameraSpaceVertex {
        let delta = other.depth - depth
        let t = abs(delta) <= 0.000001 ? 0 : (targetDepth - depth) / delta
        return CameraSpaceVertex(
            x: x + (other.x - x) * t,
            y: y + (other.y - y) * t,
            depth: targetDepth,
            color: color.interpolated(to: other.color, amount: t)
        )
    }
}

private struct CameraClipping {
    let near: CGFloat
    let far: CGFloat

    init(camera: SCNCamera?) {
        guard let camera, !camera.automaticallyAdjustsZRange else {
            self.near = 0.001
            self.far = .greatestFiniteMagnitude
            return
        }

        let near = max(0.001, CGFloat(camera.zNear))
        self.near = near
        self.far = max(near + 0.001, CGFloat(camera.zFar))
    }
}

// MARK: - Pixel surface

private struct PixelSurface {
    private static let depthTolerance: CGFloat = 0.0001

    let width: Int
    let height: Int
    var pixels: [UInt8]
    var depthBuffer: [CGFloat]

    init(width: Int, height: Int, background: RGBA) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
        self.depthBuffer = [CGFloat](repeating: .greatestFiniteMagnitude, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                writeOpaque(x: x, y: y, color: background)
            }
        }
    }

    mutating func fillCircle(center: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner) {
        let minX = max(0, Int(floor(center.x - radius)))
        let maxX = min(width - 1, Int(ceil(center.x + radius)))
        let minY = max(0, Int(floor(center.y - radius)))
        let maxY = min(height - 1, Int(ceil(center.y + radius)))
        guard minX <= maxX, minY <= maxY else { return }
        let r2 = radius * radius
        for y in minY...maxY {
            for x in minX...maxX {
                let dx = CGFloat(x) + 0.5 - center.x
                let dy = CGFloat(y) + 0.5 - center.y
                let d2 = dx * dx + dy * dy
                guard d2 <= r2 else { continue }
                let normalized = min(1, d2 / max(1, r2))
                let highlight = 1.05 - 0.35 * normalized + 0.12 * max(0, (-dx - dy) / max(1, radius * 2))
                blend(x: x, y: y, depth: depth, color: color.scaled(highlight), owner: owner)
            }
        }
    }

    mutating func strokeCapsule(from a: CGPoint, to b: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner) {
        let minX = max(0, Int(floor(min(a.x, b.x) - radius)))
        let maxX = min(width - 1, Int(ceil(max(a.x, b.x) + radius)))
        let minY = max(0, Int(floor(min(a.y, b.y) - radius)))
        let maxY = min(height - 1, Int(ceil(max(a.y, b.y) + radius)))
        guard minX <= maxX, minY <= maxY else { return }
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let ab2 = ab.x * ab.x + ab.y * ab.y
        let r2 = radius * radius
        for y in minY...maxY {
            for x in minX...maxX {
                let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let t: CGFloat
                if ab2 <= 0.0001 {
                    t = 0
                } else {
                    t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / ab2))
                }
                let q = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
                let dx = p.x - q.x
                let dy = p.y - q.y
                if dx * dx + dy * dy <= r2 {
                    blend(x: x, y: y, depth: depth, color: color, owner: owner)
                }
            }
        }
    }

    mutating func fillTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, depths: (CGFloat, CGFloat, CGFloat), colors: (RGBA, RGBA, RGBA), owner: PrimitiveOwner) {
        let minX = max(0, Int(floor(min(a.x, min(b.x, c.x)))))
        let maxX = min(width - 1, Int(ceil(max(a.x, max(b.x, c.x)))))
        let minY = max(0, Int(floor(min(a.y, min(b.y, c.y)))))
        let maxY = min(height - 1, Int(ceil(max(a.y, max(b.y, c.y)))))
        guard minX <= maxX, minY <= maxY else { return }
        let area = edge(a, b, c)
        guard abs(area) > 0.0001 else { return }
        for y in minY...maxY {
            for x in minX...maxX {
                let p = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
                let w0 = edge(b, c, p)
                let w1 = edge(c, a, p)
                let w2 = edge(a, b, p)
                if (w0 >= 0 && w1 >= 0 && w2 >= 0) || (w0 <= 0 && w1 <= 0 && w2 <= 0) {
                    let barycentricScale = 1 / area
                    let weightA = w0 * barycentricScale
                    let weightB = w1 * barycentricScale
                    let weightC = w2 * barycentricScale
                    let depth = depths.0 * w0 * barycentricScale
                        + depths.1 * w1 * barycentricScale
                        + depths.2 * w2 * barycentricScale
                    let color = RGBA.interpolate(colors.0, colors.1, colors.2, weights: (weightA, weightB, weightC))
                    blend(x: x, y: y, depth: depth, color: color.scaled(0.9), owner: owner)
                }
            }
        }
    }

    private func edge(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x)
    }

    private mutating func writeOpaque(x: Int, y: Int, color: RGBA) {
        let index = (y * width + x) * 4
        pixels[index] = color.b
        pixels[index + 1] = color.g
        pixels[index + 2] = color.r
        pixels[index + 3] = color.a
    }

    private mutating func blend(x: Int, y: Int, depth: CGFloat, color: RGBA, owner: PrimitiveOwner) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let pixelIndex = y * width + x
        if owner.readsFromDepthBuffer {
            guard depth <= depthBuffer[pixelIndex] + Self.depthTolerance else { return }
        }
        if owner.writesToDepthBuffer {
            depthBuffer[pixelIndex] = depth
        }
        let index = pixelIndex * 4
        let alpha = CGFloat(color.a) / 255
        let inv = 1 - alpha
        pixels[index] = UInt8(clamping: Int(CGFloat(color.b) * alpha + CGFloat(pixels[index]) * inv))
        pixels[index + 1] = UInt8(clamping: Int(CGFloat(color.g) * alpha + CGFloat(pixels[index + 1]) * inv))
        pixels[index + 2] = UInt8(clamping: Int(CGFloat(color.r) * alpha + CGFloat(pixels[index + 2]) * inv))
        pixels[index + 3] = 255
    }
}

// MARK: - Geometry decoding

private extension SCNGeometryElement {
    func quillIndices() -> [Int] {
        guard [1, 2, 4, 8].contains(bytesPerIndex), !data.isEmpty else { return [] }
        let count = data.count / bytesPerIndex
        return data.withUnsafeBytes { raw in
            (0..<count).compactMap { i in
                let offset = i * bytesPerIndex
                switch bytesPerIndex {
                case 1:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case 2:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                case 4:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                case 8:
                    let value = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
                    return value <= UInt64(Int.max) ? Int(value) : nil
                default:
                    return nil
                }
            }
        }
    }
}

private extension SCNGeometrySource {
    func quillColorValues() -> [RGBA] {
        guard let stride = quillValidatedColorStride() else { return [] }
        return data.withUnsafeBytes { raw in
            (0..<vectorCount).compactMap { i in
                let base = dataOffset + i * stride
                guard let r = colorComponent(at: base, in: raw) else { return nil }
                let g = componentsPerVector > 1 ? colorComponent(at: base + bytesPerComponent, in: raw) ?? r : r
                let b = componentsPerVector > 2 ? colorComponent(at: base + 2 * bytesPerComponent, in: raw) ?? r : r
                let a = componentsPerVector > 3 ? colorComponent(at: base + 3 * bytesPerComponent, in: raw) ?? 1 : 1
                return RGBA(normalizedRed: r, green: g, blue: b, alpha: a)
            }
        }
    }

    private func quillValidatedColorStride() -> Int? {
        guard semantic == .color,
              vectorCount > 0,
              componentsPerVector > 0,
              dataOffset >= 0,
              [1, 2, 4, 8].contains(bytesPerComponent) else {
            return nil
        }

        if usesFloatComponents {
            guard bytesPerComponent == MemoryLayout<Float>.size || bytesPerComponent == MemoryLayout<Double>.size else {
                return nil
            }
        }

        let requiredBytesResult = componentsPerVector.multipliedReportingOverflow(by: bytesPerComponent)
        guard !requiredBytesResult.overflow, requiredBytesResult.partialValue > 0 else { return nil }
        let requiredBytes = requiredBytesResult.partialValue
        let stride = dataStride > 0 ? dataStride : requiredBytes
        guard stride >= requiredBytes else { return nil }

        let lastIndex = vectorCount - 1
        let lastStrideResult = lastIndex.multipliedReportingOverflow(by: stride)
        guard !lastStrideResult.overflow else { return nil }
        let lastBaseResult = dataOffset.addingReportingOverflow(lastStrideResult.partialValue)
        guard !lastBaseResult.overflow else { return nil }
        let lastEndResult = lastBaseResult.partialValue.addingReportingOverflow(requiredBytes)
        guard !lastEndResult.overflow, lastEndResult.partialValue <= data.count else { return nil }
        return stride
    }

    private func colorComponent(at offset: Int, in raw: UnsafeRawBufferPointer) -> CGFloat? {
        guard offset >= 0, offset + bytesPerComponent <= raw.count else { return nil }
        if usesFloatComponents {
            switch bytesPerComponent {
            case MemoryLayout<Float>.size:
                return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: Float.self))
            case MemoryLayout<Double>.size:
                return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: Double.self))
            default:
                return nil
            }
        }

        switch bytesPerComponent {
        case 1:
            return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self)) / CGFloat(UInt8.max)
        case 2:
            return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) / CGFloat(UInt16.max)
        case 4:
            return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) / CGFloat(UInt32.max)
        case 8:
            return CGFloat(raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) / CGFloat(UInt64.max)
        default:
            return nil
        }
    }
}

// MARK: - Math

private struct Bounds {
    var min: Vector3
    var max: Vector3

    var center: Vector3 { (min + max) * 0.5 }
    var radius: CGFloat { Swift.max(0.5, (max - min).length * 0.5) }

    mutating func include(_ p: Vector3) {
        min = Vector3(Swift.min(min.x, p.x), Swift.min(min.y, p.y), Swift.min(min.z, p.z))
        max = Vector3(Swift.max(max.x, p.x), Swift.max(max.y, p.y), Swift.max(max.z, p.z))
    }
}

struct Vector3: Equatable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static let zero = Vector3(0, 0, 0)

    init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ v: SCNVector3) {
        self.init(v.x, v.y, v.z)
    }

    var length: CGFloat { (x * x + y * y + z * z).squareRoot() }

    func dot(_ other: Vector3) -> CGFloat {
        x * other.x + y * other.y + z * other.z
    }

    func cross(_ other: Vector3) -> Vector3 {
        Vector3(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    func normalized(fallback: Vector3) -> Vector3 {
        let len = length
        guard len > 0.000001 else { return fallback }
        return self * (1 / len)
    }

    static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    static func * (lhs: Vector3, rhs: CGFloat) -> Vector3 {
        Vector3(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }
}

struct Matrix4 {
    var m: [CGFloat]

    static let identity = Matrix4([
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    ])

    init(_ m: [CGFloat]) {
        self.m = m
    }

    init(_ matrix: SCNMatrix4) {
        self = Self.matrix(matrix)
    }

    static func localTransform(for node: SCNNode) -> Matrix4 {
        matrix(node.transform)
    }

    static func worldTransform(for node: SCNNode) -> Matrix4 {
        var chain: [SCNNode] = []
        var current: SCNNode? = node
        while let node = current {
            chain.append(node)
            current = node.parent
        }
        return chain.reversed().reduce(.identity) { world, node in
            world * localTransform(for: node)
        }
    }

    var approximateScale: CGFloat {
        let sx = Vector3(m[0], m[4], m[8]).length
        let sy = Vector3(m[1], m[5], m[9]).length
        let sz = Vector3(m[2], m[6], m[10]).length
        return max(0.001, (sx + sy + sz) / 3)
    }

    func transformPoint(_ v: Vector3) -> Vector3 {
        Vector3(
            m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3],
            m[4] * v.x + m[5] * v.y + m[6] * v.z + m[7],
            m[8] * v.x + m[9] * v.y + m[10] * v.z + m[11]
        )
    }

    func transformDirection(_ v: Vector3) -> Vector3 {
        Vector3(
            m[0] * v.x + m[1] * v.y + m[2] * v.z,
            m[4] * v.x + m[5] * v.y + m[6] * v.z,
            m[8] * v.x + m[9] * v.y + m[10] * v.z
        )
    }

    func inverted() -> Matrix4 {
        Matrix4(SCNMatrix4Invert(scnMatrix))
    }

    static func * (lhs: Matrix4, rhs: Matrix4) -> Matrix4 {
        var out = [CGFloat](repeating: 0, count: 16)
        for row in 0..<4 {
            for col in 0..<4 {
                var value: CGFloat = 0
                for k in 0..<4 {
                    value += lhs.m[row * 4 + k] * rhs.m[k * 4 + col]
                }
                out[row * 4 + col] = value
            }
        }
        return Matrix4(out)
    }

    var scnMatrix: SCNMatrix4 {
        SCNMatrix4(
            m11: m[0], m12: m[4], m13: m[8], m14: m[12],
            m21: m[1], m22: m[5], m23: m[9], m24: m[13],
            m31: m[2], m32: m[6], m33: m[10], m34: m[14],
            m41: m[3], m42: m[7], m43: m[11], m44: m[15]
        )
    }

    private static func matrix(_ m: SCNMatrix4) -> Matrix4 {
        Matrix4([
            m.m11, m.m21, m.m31, m.m41,
            m.m12, m.m22, m.m32, m.m42,
            m.m13, m.m23, m.m33, m.m43,
            m.m14, m.m24, m.m34, m.m44,
        ])
    }
}
