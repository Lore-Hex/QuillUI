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
        searchMode: SCNHitTestSearchMode = .closest
    ) -> [SCNHitTestResult] {
        SCNSoftwareRenderer(scene: self, pointOfView: pointOfView)
            .hitTest(point: point, width: width, height: height, searchMode: searchMode)
    }
    #endif
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
        for primitive in projectedPrimitives(width: width, height: height).sorted(by: { $0.depth > $1.depth }) {
            primitive.draw(into: &surface)
        }

        return QuillSceneKitRenderSupport.image(width: width, height: height, bgraPixels: surface.pixels)
    }

    #if canImport(UIKit)
    public func hitTest(
        point: CGPoint,
        width: Int,
        height: Int,
        searchMode: SCNHitTestSearchMode = .closest
    ) -> [SCNHitTestResult] {
        let hits = projectedPrimitives(width: max(1, width), height: max(1, height))
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

    private func projectedPrimitives(width: Int, height: Int) -> [ProjectedPrimitive] {
        let rootTransform = Matrix4.identity
        var collector = RenderCollector()
        collector.collect(node: scene.rootNode, parent: rootTransform)

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

        return collector.primitives.compactMap { $0.projected(using: camera) }
    }
}

// MARK: - Scene collection

private struct RenderCollector {
    var primitives: [WorldPrimitive] = []
    var bounds: Bounds?
    var cameraNode: SCNNode?
    var cameraWorldTransform: Matrix4?

    mutating func collect(node: SCNNode, parent: Matrix4) {
        guard !node.isHidden, node.opacity > 0 else { return }
        let world = parent * Matrix4.localTransform(for: node)
        if node.camera != nil, cameraNode == nil {
            cameraNode = node
            cameraWorldTransform = world
        }
        if let geometry = node.geometry {
            collect(geometry: geometry, node: node, world: world)
        }
        for child in node.childNodes {
            collect(node: child, parent: world)
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

    private mutating func collect(geometry: SCNGeometry, node: SCNNode, world: Matrix4) {
        let opacity = max(0, min(1, node.opacity))
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

        case let box as SCNBox:
            let owner = PrimitiveOwner(node: node, geometryIndex: 0)
            let hx = box.width / 2
            let hy = box.height / 2
            let hz = box.length / 2
            let corners = [
                Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz),
                Vector3(hx, hy, -hz), Vector3(-hx, hy, -hz),
                Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz),
                Vector3(hx, hy, hz), Vector3(-hx, hy, hz),
            ].map(world.transformPoint)
            for corner in corners { include(corner) }
            let faces = [
                (0, 1, 2), (0, 2, 3), (4, 6, 5), (4, 7, 6),
                (0, 4, 5), (0, 5, 1), (1, 5, 6), (1, 6, 2),
                (2, 6, 7), (2, 7, 3), (3, 7, 4), (3, 4, 0),
            ]
            for (i0, i1, i2) in faces {
                primitives.append(.triangle(a: corners[i0], b: corners[i1], c: corners[i2], color: baseColor, owner: owner))
            }
            return

        default:
            break
        }

        collectBufferedGeometry(geometry, node: node, world: world, opacity: opacity)
    }

    private mutating func collectBufferedGeometry(_ geometry: SCNGeometry, node: SCNNode, world: Matrix4, opacity: CGFloat) {
        guard let vertexSource = geometry.sources.first(where: { $0.semantic == .vertex }) else { return }
        let vertices = vertexSource.quillVector3Values().map(Vector3.init)
        guard !vertices.isEmpty else { return }
        let worldVertices = vertices.map(world.transformPoint)
        for vertex in worldVertices { include(vertex) }

        for (elementIndex, element) in geometry.elements.enumerated() {
            let owner = PrimitiveOwner(node: node, geometryIndex: elementIndex)
            let primitiveColor = color(for: geometry, elementIndex: elementIndex).withAlphaMultiplier(opacity)
            let indices = element.quillIndices()
            switch element.primitiveType {
            case .triangles:
                var i = 0
                while i + 2 < indices.count {
                    appendTriangle(indices[i], indices[i + 1], indices[i + 2], vertices: worldVertices, color: primitiveColor, owner: owner)
                    i += 3
                }
            case .triangleStrip:
                guard indices.count >= 3 else { continue }
                for i in 0..<(indices.count - 2) {
                    if i.isMultiple(of: 2) {
                        appendTriangle(indices[i], indices[i + 1], indices[i + 2], vertices: worldVertices, color: primitiveColor, owner: owner)
                    } else {
                        appendTriangle(indices[i + 1], indices[i], indices[i + 2], vertices: worldVertices, color: primitiveColor, owner: owner)
                    }
                }
            case .line:
                var i = 0
                while i + 1 < indices.count {
                    appendLine(indices[i], indices[i + 1], vertices: worldVertices, color: primitiveColor, owner: owner)
                    i += 2
                }
            case .point:
                for index in indices where worldVertices.indices.contains(index) {
                    let p = worldVertices[index]
                    primitives.append(.sphere(center: p, radius: 0.025 * world.approximateScale, color: primitiveColor, owner: owner))
                }
            case .polygon:
                appendPolygons(from: element, vertices: worldVertices, color: primitiveColor, owner: owner)
            }
        }
    }

    private mutating func appendTriangle(_ i0: Int, _ i1: Int, _ i2: Int, vertices: [Vector3], color: RGBA, owner: PrimitiveOwner) {
        guard vertices.indices.contains(i0), vertices.indices.contains(i1), vertices.indices.contains(i2) else { return }
        primitives.append(.triangle(a: vertices[i0], b: vertices[i1], c: vertices[i2], color: color, owner: owner))
    }

    private mutating func appendLine(_ i0: Int, _ i1: Int, vertices: [Vector3], color: RGBA, owner: PrimitiveOwner) {
        guard vertices.indices.contains(i0), vertices.indices.contains(i1) else { return }
        primitives.append(.line(a: vertices[i0], b: vertices[i1], radius: 0.012, color: color, owner: owner))
    }

    private mutating func appendPolygons(from element: SCNGeometryElement, vertices: [Vector3], color: RGBA, owner: PrimitiveOwner) {
        let raw = element.quillIndices()
        guard element.primitiveCount > 0, raw.count >= element.primitiveCount else { return }
        let counts = Array(raw.prefix(element.primitiveCount))
        var offset = element.primitiveCount
        for count in counts where count >= 3 {
            guard offset + count <= raw.count else { return }
            let polygon = Array(raw[offset..<(offset + count)])
            offset += count
            for i in 1..<(polygon.count - 1) {
                appendTriangle(polygon[0], polygon[i], polygon[i + 1], vertices: vertices, color: color, owner: owner)
            }
        }
    }
}

// MARK: - Projection and primitives

private struct PrimitiveOwner {
    let node: SCNNode
    let geometryIndex: Int
}

private enum WorldPrimitive {
    case sphere(center: Vector3, radius: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case line(a: Vector3, b: Vector3, radius: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case triangle(a: Vector3, b: Vector3, c: Vector3, color: RGBA, owner: PrimitiveOwner)

    func projected(using camera: CameraProjection) -> ProjectedPrimitive? {
        switch self {
        case let .sphere(center, radius, color, owner):
            guard let projectedCenter = camera.project(center) else { return nil }
            let projectedRadius = max(1.5, camera.projectedLength(radius, atDepth: projectedCenter.depth))
            return .sphere(center: projectedCenter.point, radius: projectedRadius, depth: projectedCenter.depth, color: color, owner: owner)
        case let .line(a, b, radius, color, owner):
            guard let pa = camera.project(a), let pb = camera.project(b) else { return nil }
            let depth = (pa.depth + pb.depth) / 2
            let projectedRadius = max(1, camera.projectedLength(radius, atDepth: depth))
            return .line(a: pa.point, b: pb.point, radius: projectedRadius, depth: depth, color: color, owner: owner)
        case let .triangle(a, b, c, color, owner):
            guard let pa = camera.project(a), let pb = camera.project(b), let pc = camera.project(c) else { return nil }
            let depth = (pa.depth + pb.depth + pc.depth) / 3
            return .triangle(a: pa.point, b: pb.point, c: pc.point, depth: depth, color: color, owner: owner)
        }
    }
}

private enum ProjectedPrimitive {
    case sphere(center: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case line(a: CGPoint, b: CGPoint, radius: CGFloat, depth: CGFloat, color: RGBA, owner: PrimitiveOwner)
    case triangle(a: CGPoint, b: CGPoint, c: CGPoint, depth: CGFloat, color: RGBA, owner: PrimitiveOwner)

    var depth: CGFloat {
        switch self {
        case let .sphere(_, _, depth, _, _), let .line(_, _, _, depth, _, _), let .triangle(_, _, _, depth, _, _):
            return depth
        }
    }

    private var owner: PrimitiveOwner {
        switch self {
        case let .sphere(_, _, _, _, owner), let .line(_, _, _, _, _, owner), let .triangle(_, _, _, _, _, owner):
            return owner
        }
    }

    var node: SCNNode { owner.node }

    var geometryIndex: Int {
        owner.geometryIndex
    }

    func draw(into surface: inout PixelSurface) {
        switch self {
        case let .sphere(center, radius, _, color, _):
            surface.fillCircle(center: center, radius: radius, color: color)
        case let .line(a, b, radius, _, color, _):
            surface.strokeCapsule(from: a, to: b, radius: radius, color: color)
        case let .triangle(a, b, c, _, color, _):
            surface.fillTriangle(a, b, c, color: color)
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

        case let .triangle(a, b, c, _, _, _):
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

        self.position = cameraPosition
        self.forward = forward
        self.right = right
        self.up = up
        self.focalLength = focal
        self.orthographicScale = ortho
    }

    func project(_ point: Vector3) -> (point: CGPoint, depth: CGFloat)? {
        let relative = point - position
        let depth = relative.dot(forward)
        guard depth > 0.001 else { return nil }
        let cameraX = relative.dot(right)
        let cameraY = relative.dot(up)
        let scale: CGFloat
        if let orthographicScale {
            scale = CGFloat(height) / orthographicScale
        } else {
            scale = focalLength / depth
        }
        return (
            CGPoint(
                x: CGFloat(width) / 2 + cameraX * scale,
                y: CGFloat(height) / 2 - cameraY * scale
            ),
            depth
        )
    }

    func projectedLength(_ length: CGFloat, atDepth depth: CGFloat) -> CGFloat {
        if let orthographicScale {
            return length * CGFloat(height) / orthographicScale
        }
        return length * focalLength / max(0.001, depth)
    }
}

// MARK: - Pixel surface

private struct PixelSurface {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, background: RGBA) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                writeOpaque(x: x, y: y, color: background)
            }
        }
    }

    mutating func fillCircle(center: CGPoint, radius: CGFloat, color: RGBA) {
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
                blend(x: x, y: y, color: color.scaled(highlight))
            }
        }
    }

    mutating func strokeCapsule(from a: CGPoint, to b: CGPoint, radius: CGFloat, color: RGBA) {
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
                    blend(x: x, y: y, color: color)
                }
            }
        }
    }

    mutating func fillTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, color: RGBA) {
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
                    blend(x: x, y: y, color: color.scaled(0.9))
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

    private mutating func blend(x: Int, y: Int, color: RGBA) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let index = (y * width + x) * 4
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
        guard bytesPerIndex > 0, !data.isEmpty else { return [] }
        let count = data.count / bytesPerIndex
        return data.withUnsafeBytes { raw in
            (0..<count).map { i in
                let offset = i * bytesPerIndex
                switch bytesPerIndex {
                case 1:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case 2:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                case 4:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                case 8:
                    return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
                default:
                    return 0
                }
            }
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

    static func localTransform(for node: SCNNode) -> Matrix4 {
        let s = scale(node.scale)
        let q = quaternion(node.orientation)
        let r = rotation(euler: node.eulerAngles)
        let t = translation(node.position)
        let raw = matrix(node.transform)
        let local = t * r * q * s
        return SCNMatrix4IsIdentity(node.transform) ? local : raw * local
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

    private static func translation(_ v: SCNVector3) -> Matrix4 {
        Matrix4([
            1, 0, 0, v.x,
            0, 1, 0, v.y,
            0, 0, 1, v.z,
            0, 0, 0, 1,
        ])
    }

    private static func scale(_ v: SCNVector3) -> Matrix4 {
        Matrix4([
            v.x, 0, 0, 0,
            0, v.y, 0, 0,
            0, 0, v.z, 0,
            0, 0, 0, 1,
        ])
    }

    private static func rotation(euler: SCNVector3) -> Matrix4 {
        rotationY(euler.y) * rotationX(euler.x) * rotationZ(euler.z)
    }

    private static func rotationX(_ a: CGFloat) -> Matrix4 {
        let c = cos(a), s = sin(a)
        return Matrix4([
            1, 0, 0, 0,
            0, c, -s, 0,
            0, s, c, 0,
            0, 0, 0, 1,
        ])
    }

    private static func rotationY(_ a: CGFloat) -> Matrix4 {
        let c = cos(a), s = sin(a)
        return Matrix4([
            c, 0, s, 0,
            0, 1, 0, 0,
            -s, 0, c, 0,
            0, 0, 0, 1,
        ])
    }

    private static func rotationZ(_ a: CGFloat) -> Matrix4 {
        let c = cos(a), s = sin(a)
        return Matrix4([
            c, -s, 0, 0,
            s, c, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    private static func quaternion(_ q: SCNQuaternion) -> Matrix4 {
        let x = q.x, y = q.y, z = q.z, w = q.w
        let xx = x * x, yy = y * y, zz = z * z
        let xy = x * y, xz = x * z, yz = y * z
        let wx = w * x, wy = w * y, wz = w * z
        return Matrix4([
            1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), 0,
            2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), 0,
            2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), 0,
            0, 0, 0, 1,
        ])
    }

    private static func matrix(_ m: SCNMatrix4) -> Matrix4 {
        Matrix4([
            m.m11, m.m12, m.m13, m.m14,
            m.m21, m.m22, m.m23, m.m24,
            m.m31, m.m32, m.m33, m.m34,
            m.m41, m.m42, m.m43, m.m44,
        ])
    }
}

// MARK: - Color

private struct RGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)
    static let neutral = RGBA(r: 185, g: 190, b: 198, a: 255)

    func withAlphaMultiplier(_ opacity: CGFloat) -> RGBA {
        RGBA(r: r, g: g, b: b, a: UInt8(clamping: Int(CGFloat(a) * max(0, min(1, opacity)))))
    }

    func scaled(_ factor: CGFloat) -> RGBA {
        RGBA(
            r: UInt8(clamping: Int(CGFloat(r) * factor)),
            g: UInt8(clamping: Int(CGFloat(g) * factor)),
            b: UInt8(clamping: Int(CGFloat(b) * factor)),
            a: a
        )
    }
}

private func color(for geometry: SCNGeometry, elementIndex: Int) -> RGBA {
    let material: SCNMaterial?
    if geometry.materials.indices.contains(elementIndex) {
        material = geometry.materials[elementIndex]
    } else {
        material = geometry.firstMaterial
    }
    if let emission = color(from: material?.emission.contents), emission != .black {
        return emission
    }
    return color(from: material?.diffuse.contents) ?? .neutral
}

private func color(from contents: Any?) -> RGBA? {
    switch contents {
    case let color as RSColor:
        return rgba(components: color.components)
    case let color as RSCGColor:
        return rgba(components: color.components)
    case is CGImage:
        return RGBA(r: 210, g: 214, b: 218, a: 255)
    default:
        return nil
    }
}

private func rgba(components: [CGFloat]?) -> RGBA? {
    guard let components, !components.isEmpty else { return nil }
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
    if components.count == 2 {
        r = components[0]; g = components[0]; b = components[0]; a = components[1]
    } else {
        r = components[0]
        g = components.count > 1 ? components[1] : components[0]
        b = components.count > 2 ? components[2] : components[0]
        a = components.count > 3 ? components[3] : 1
    }
    return RGBA(
        r: UInt8(clamping: Int(max(0, min(1, r)) * 255)),
        g: UInt8(clamping: Int(max(0, min(1, g)) * 255)),
        b: UInt8(clamping: Int(max(0, min(1, b)) * 255)),
        a: UInt8(clamping: Int(max(0, min(1, a)) * 255))
    )
}
