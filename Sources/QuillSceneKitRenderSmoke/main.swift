import Foundation
import AppKit
import SceneKit
import QuillFoundation
import SwiftUI
@_spi(QuillTesting) import QuillUI

enum SmokeFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): return message
        }
    }
}

@main
struct QuillSceneKitRenderSmoke {
    @MainActor
    static func main() throws {
        log("direct renderer smoke starting")
        let sphereStats = PixelStats(renderSphereScene())
        try require(sphereStats.nonBlackPixels > 1_000, "sphere render stayed mostly black: \(sphereStats)")
        try require(sphereStats.redDominantPixels > 900, "sphere render did not produce red pixels: \(sphereStats)")
        try requireMatchesAppleEnvelope(
            sphereStats,
            .sphere,
            label: "sphere"
        )

        let triangleStats = PixelStats(renderTriangleScene())
        try require(triangleStats.nonBlackPixels > 1_500, "triangle render stayed mostly black: \(triangleStats)")
        try require(triangleStats.greenDominantPixels > 1_400, "triangle render did not produce green pixels: \(triangleStats)")
        try requireMatchesAppleEnvelope(
            triangleStats,
            .triangle,
            label: "triangle"
        )

        let vertexColorTriangleImage = renderVertexColorTriangleScene()
        let vertexColorTriangleStats = PixelStats(vertexColorTriangleImage)
        try require(
            vertexColorTriangleStats.redDominantPixels > 600,
            "vertex-color triangle lost red pixels: \(vertexColorTriangleStats)"
        )
        try require(
            vertexColorTriangleStats.greenDominantPixels > 600,
            "vertex-color triangle lost green pixels: \(vertexColorTriangleStats)"
        )
        try require(
            vertexColorTriangleStats.blueDominantPixels > 600,
            "vertex-color triangle lost blue pixels: \(vertexColorTriangleStats)"
        )
        try require(
            PixelStats.dominantColor(atX: 50, y: 140, in: vertexColorTriangleImage) == .red,
            "vertex-color triangle did not preserve red near the left vertex: \(vertexColorTriangleStats)"
        )
        try require(
            PixelStats.dominantColor(atX: 170, y: 140, in: vertexColorTriangleImage) == .green,
            "vertex-color triangle did not preserve green near the right vertex: \(vertexColorTriangleStats)"
        )
        try require(
            PixelStats.dominantColor(atX: 110, y: 35, in: vertexColorTriangleImage) == .blue,
            "vertex-color triangle did not preserve blue near the top vertex: \(vertexColorTriangleStats)"
        )

        let nestedCameraStats = PixelStats(renderNestedCameraScene())
        try require(nestedCameraStats.nonBlackPixels > 1_000, "nested-camera render stayed mostly black: \(nestedCameraStats)")
        try require(nestedCameraStats.redDominantPixels > 900, "nested-camera render did not produce red pixels: \(nestedCameraStats)")

        let sideCameraStats = PixelStats(renderSideCameraScene())
        try require(sideCameraStats.nonBlackPixels > 1_000, "side-camera render stayed mostly black: \(sideCameraStats)")
        try require(sideCameraStats.redDominantPixels > 900, "side-camera render did not produce red pixels: \(sideCameraStats)")
        try requireMatchesAppleEnvelope(
            sideCameraStats,
            .sphere,
            label: "side camera"
        )

        let awayCameraStats = PixelStats(renderAwayCameraScene())
        try require(awayCameraStats.nonBlackPixels == 0, "away-camera render unexpectedly produced pixels: \(awayCameraStats)")

        let clippedCameraStats = PixelStats(renderClippedCameraScene())
        try require(clippedCameraStats.nonBlackPixels == 0, "clipped-camera render unexpectedly produced pixels: \(clippedCameraStats)")

        let nearClippedTriangleStats = PixelStats(renderNearClippedTriangleScene())
        try require(
            nearClippedTriangleStats.greenDominantPixels > 900,
            "near-clipped triangle did not render visible green pixels: \(nearClippedTriangleStats)"
        )

        let nearClippedLineStats = PixelStats(renderNearClippedLineScene())
        try require(
            nearClippedLineStats.greenDominantPixels > 40,
            "near-clipped line did not render visible green pixels: \(nearClippedLineStats)"
        )

        let intersectingTriangleImage = renderIntersectingTriangleScene()
        let intersectingTriangleStats = PixelStats(intersectingTriangleImage)
        try require(intersectingTriangleStats.redDominantPixels > 400, "z-buffer scene lost near red pixels: \(intersectingTriangleStats)")
        try require(intersectingTriangleStats.greenDominantPixels > 400, "z-buffer scene lost near green pixels: \(intersectingTriangleStats)")
        try require(
            PixelStats.dominantColor(atX: 80, y: 88, in: intersectingTriangleImage) == .red,
            "z-buffer scene did not draw near red triangle below intersection: \(intersectingTriangleStats)"
        )
        try require(
            PixelStats.dominantColor(atX: 80, y: 42, in: intersectingTriangleImage) == .green,
            "z-buffer scene did not keep green triangle in front above intersection: \(intersectingTriangleStats)"
        )

        try runPublicMatrixTransformSmoke()
        try runParametricPrimitiveSmoke()
        try runMaterialSmoke()
        try runCameraControlSmoke()
        try runHitTestSmoke()
        try runActionSmoke()

        log("SceneKit render smoke passed")
        log("sphere: \(sphereStats)")
        log("triangle: \(triangleStats)")
        log("vertex-color triangle: \(vertexColorTriangleStats)")
        log("nested camera: \(nestedCameraStats)")
        log("side camera: \(sideCameraStats)")
        log("away camera: \(awayCameraStats)")
        log("clipped camera: \(clippedCameraStats)")
        log("near-clipped triangle: \(nearClippedTriangleStats)")
        log("near-clipped line: \(nearClippedLineStats)")
        log("intersecting triangles: \(intersectingTriangleStats)")

        if ProcessInfo.processInfo.environment["QUILLUI_SCENEKIT_GTK_SMOKE"] == "1" {
            try runGTKSceneViewSmoke()
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw SmokeFailure.assertion(message) }
    }

    private static func requireMatchesAppleEnvelope(
        _ stats: PixelStats,
        _ reference: AppleSceneKitGoldenEnvelope,
        label: String
    ) throws {
        try require(abs(stats.nonBlackPixels - reference.nonBlackPixels) <= 180, "\(label) area drifted from Apple envelope: \(stats)")
        try require(
            abs(stats.dominantPixels(for: reference.dominantColor) - reference.dominantPixels) <= 180,
            "\(label) dominant color drifted from Apple envelope: \(stats)"
        )
        try require(abs(stats.bounds.minX - reference.bounds.minX) <= 8, "\(label) minX drifted from Apple envelope: \(stats)")
        try require(abs(stats.bounds.minY - reference.bounds.minY) <= 8, "\(label) minY drifted from Apple envelope: \(stats)")
        try require(abs(stats.bounds.maxX - reference.bounds.maxX) <= 8, "\(label) maxX drifted from Apple envelope: \(stats)")
        try require(abs(stats.bounds.maxY - reference.bounds.maxY) <= 8, "\(label) maxY drifted from Apple envelope: \(stats)")
    }

    private static func renderSphereScene() -> CGImage {
        makeSphereScene().quillRenderImage(width: 160, height: 120)
    }

    private static func makeSphereScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    private static func renderTriangleScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let vertices = [
            SCNVector3(-1.2, -0.9, 0),
            SCNVector3(1.2, -0.9, 0),
            SCNVector3(0, 1.0, 0),
        ]
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1, 2], primitiveType: .triangles)]
        )
        geometry.firstMaterial?.diffuse.contents = RSColor(red: 0.1, green: 0.85, blue: 0.25, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 180, height: 140)
    }

    private static func renderVertexColorTriangleScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let vertices = [
            SCNVector3(-1.3, -1.1, 0),
            SCNVector3(1.3, -1.1, 0),
            SCNVector3(0, 1.25, 0),
        ]
        let colors: [Float] = [
            1, 0, 0, 1,
            0, 1, 0, 1,
            0, 0, 1, 1,
        ]
        let colorSource = SCNGeometrySource(
            data: Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size),
            semantic: .color,
            vectorCount: 3,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 4 * MemoryLayout<Float>.size
        )
        let geometry = SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                colorSource,
            ],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1, 2], primitiveType: .triangles)]
        )
        geometry.firstMaterial?.diffuse.contents = CGColor.white
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 3
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 220, height: 180, pointOfView: cameraNode)
    }

    private static func renderNestedCameraScene() -> CGImage {
        let scene = makeSphereScene()
        let cameraParent = SCNNode()
        cameraParent.position = SCNVector3(0, 0, 4)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraParent.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraParent)
        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderSideCameraScene() -> CGImage {
        let scene = makeSphereScene()
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(4, 0, 0)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)
        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderAwayCameraScene() -> CGImage {
        let scene = makeSphereScene()
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        cameraNode.eulerAngles = SCNVector3(0, .pi, 0)
        scene.rootNode.addChildNode(cameraNode)
        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderClippedCameraScene() -> CGImage {
        let scene = makeSphereScene()
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.zNear = 4.5
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)
        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderNearClippedTriangleScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: [
                SCNVector3(-1.2, -0.9, 0),
                SCNVector3(1.2, -0.9, 0),
                SCNVector3(0, 1.2, 3.5),
            ])],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1, 2], primitiveType: .triangles)]
        )
        geometry.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let camera = SCNCamera()
        camera.zNear = 1
        camera.zFar = 10
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderNearClippedLineScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: [
                SCNVector3(0, -1, 0),
                SCNVector3(0, 1, 3.5),
            ])],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1], primitiveType: .line)]
        )
        geometry.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let camera = SCNCamera()
        camera.zNear = 1
        camera.zFar = 10
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func renderIntersectingTriangleScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let redCrossing = SCNGeometry(
            sources: [SCNGeometrySource(vertices: [
                SCNVector3(-1.2, -1.0, 1.0),
                SCNVector3(1.2, -1.0, 1.0),
                SCNVector3(0, 1.0, -2.5),
            ])],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1, 2], primitiveType: .triangles)]
        )
        redCrossing.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: redCrossing))

        let greenFlat = SCNGeometry(
            sources: [SCNGeometrySource(vertices: [
                SCNVector3(-1.2, -1.0, 0),
                SCNVector3(1.2, -1.0, 0),
                SCNVector3(0, 1.0, 0),
            ])],
            elements: [SCNGeometryElement(indices: [UInt32(0), 1, 2], primitiveType: .triangles)]
        )
        greenFlat.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: greenFlat))

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 3.2
        camera.zFar = 10
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func runPublicMatrixTransformSmoke() throws {
        let translation = SCNMatrix4MakeTranslation(1, 2, 3)
        try require(translation.m14 == 0, "translation matrix used m14 instead of SceneKit m41 layout")
        try require(translation.m41 == 1 && translation.m42 == 2 && translation.m43 == 3, "translation matrix lost m41/m42/m43")

        let node = SCNNode()
        node.position = SCNVector3(1, 2, 3)
        node.scale = SCNVector3(2, 3, 4)
        try require(node.transform.m41 == 1 && node.transform.m42 == 2 && node.transform.m43 == 3, "component transform lost translation")
        try require(node.transform.m11 == 2 && node.transform.m22 == 3 && node.transform.m33 == 4, "component transform lost scale")

        node.transform = SCNMatrix4MakeTranslation(5, 6, 7)
        try require(node.position == SCNVector3(5, 6, 7), "assigned transform did not update node position")
        try require(node.scale == SCNVector3(1, 1, 1), "assigned translation transform changed node scale")

        node.transform = SCNMatrix4MakeRotation(.pi / 2, 0, 1, 0)
        let quarterTurn = CGFloat(2).squareRoot() / 2
        try require(abs(abs(node.orientation.y) - quarterTurn) < 0.0001, "assigned rotation transform did not update node orientation y")
        try require(abs(abs(node.orientation.w) - quarterTurn) < 0.0001, "assigned rotation transform did not update node orientation w")

        let inverse = SCNMatrix4Invert(translation)
        try require(abs(inverse.m41 + 1) < 0.0001, "translation inverse lost x offset")
        try require(abs(inverse.m42 + 2) < 0.0001, "translation inverse lost y offset")
        try require(abs(inverse.m43 + 3) < 0.0001, "translation inverse lost z offset")

        let image = renderPublicMatrixTransformScene()
        let stats = PixelStats(image)
        try require(stats.redDominantPixels > 200, "public node transform matrix render stayed mostly black: \(stats)")
        try require(stats.bounds.minX > 95, "public node transform matrix did not move the object right: \(stats)")
        try require(stats.bounds.maxX > 110, "public node transform matrix produced too-small shifted bounds: \(stats)")
        log("public matrix transform smoke passed \(stats)")
    }

    private static func renderPublicMatrixTransformScene() -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 0.35)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        let sphereNode = SCNNode(geometry: sphere)
        sphereNode.transform = SCNMatrix4MakeTranslation(1, 0, 0)
        scene.rootNode.addChildNode(sphereNode)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 4
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func runParametricPrimitiveSmoke() throws {
        try requireRedPixels(
            renderParametricGeometry(SCNCone(topRadius: 0.15, bottomRadius: 0.9, height: 1.7)),
            minimumPixels: 500,
            label: "cone"
        )
        try requireRedPixels(
            renderParametricGeometry(SCNCapsule(capRadius: 0.45, height: 1.8)),
            minimumPixels: 450,
            label: "capsule"
        )
        try requireRedPixels(
            renderParametricGeometry(SCNTube(innerRadius: 0.35, outerRadius: 0.8, height: 1.5)),
            minimumPixels: 400,
            label: "tube"
        )
        try requireRedPixels(
            renderParametricGeometry(SCNTorus(ringRadius: 0.65, pipeRadius: 0.25)),
            minimumPixels: 550,
            label: "torus"
        )
    }

    private static func renderParametricGeometry(_ geometry: SCNGeometry) -> CGImage {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        geometry.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        return scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
    }

    private static func requireRedPixels(
        _ image: CGImage,
        minimumPixels: Int,
        label: String
    ) throws {
        let stats = PixelStats(image)
        try require(stats.nonBlackPixels >= minimumPixels, "\(label) render stayed mostly black: \(stats)")
        try require(stats.redDominantPixels >= minimumPixels, "\(label) render did not produce red pixels: \(stats)")
    }

    private static func runMaterialSmoke() throws {
        let zeroIntensity = SCNSphere(radius: 1)
        zeroIntensity.firstMaterial?.diffuse.intensity = 0
        let zeroIntensityStats = PixelStats(renderParametricGeometry(zeroIntensity))
        try require(
            zeroIntensityStats.nonBlackPixels == 0,
            "zero diffuse intensity unexpectedly rendered pixels: \(zeroIntensityStats)"
        )

        let transparent = SCNSphere(radius: 1)
        transparent.firstMaterial?.transparency = 0
        let transparentStats = PixelStats(renderParametricGeometry(transparent))
        try require(
            transparentStats.nonBlackPixels == 0,
            "transparent material unexpectedly rendered pixels: \(transparentStats)"
        )
    }

    @MainActor
    private static func runCameraControlSmoke() throws {
        let scene = makeSphereScene()
        guard let resetCamera = scene.rootNode.childNodes.first(where: { $0.camera != nil }) else {
            throw SmokeFailure.assertion("camera-control scene had no camera")
        }
        let view = SCNView()
        view.bounds = CGRect(x: 0, y: 0, width: 160, height: 120)
        view.scene = scene
        view.pointOfView = resetCamera
        view.defaultCameraController.target = SCNVector3(0, 0, 0)
        view.allowsCameraControl = true

        let mouseDown = NSEvent()
        mouseDown.locationInWindow = CGPoint(x: 40, y: 40)
        let mouseDrag = NSEvent()
        mouseDrag.locationInWindow = CGPoint(x: 120, y: 70)
        view.mouseDown(with: mouseDown)
        view.mouseDragged(with: mouseDrag)

        try require(view.pointOfView !== resetCamera, "camera control did not create a moved point-of-view camera")
        try require(abs(view.pointOfView?.position.x ?? 0) > 0.5, "camera control did not orbit the camera")

        let distanceBeforeScroll = distanceFromOrigin(view.pointOfView?.position ?? SCNVector3(0, 0, 0))
        let scroll = NSEvent()
        scroll.scrollingDeltaY = 20
        view.scrollWheel(with: scroll)
        let distanceAfterScroll = distanceFromOrigin(view.pointOfView?.position ?? SCNVector3(0, 0, 0))
        try require(distanceAfterScroll < distanceBeforeScroll, "camera control did not dolly the camera")

        guard let image = view.quillRenderImage(width: 160, height: 120) else {
            throw SmokeFailure.assertion("camera-control render returned nil")
        }
        let stats = PixelStats(image)
        try require(stats.nonBlackPixels > 500, "camera-control render stayed mostly black: \(stats)")
        log("camera control smoke passed \(stats)")
    }

    private static func distanceFromOrigin(_ point: SCNVector3) -> CGFloat {
        (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
    }

    private static func runHitTestSmoke() throws {
        let scene = SCNScene()

        let back = SCNSphere(radius: 0.65)
        back.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 0, blue: 1, alpha: 1)
        let backNode = SCNNode(geometry: back)
        backNode.position = SCNVector3(0, 0, -0.8)
        scene.rootNode.addChildNode(backNode)

        let front = SCNSphere(radius: 0.65)
        front.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        let frontNode = SCNNode(geometry: front)
        scene.rootNode.addChildNode(frontNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let hits = scene.quillHitTest(
            CGPoint(x: 80, y: 60),
            width: 160,
            height: 120,
            pointOfView: cameraNode,
            searchMode: .all
        )
        try require(hits.first?.node === frontNode, "center hit did not return nearest node first")
        try require(hits.contains { $0.node === backNode }, "center hit did not include back node")

        let miss = scene.quillHitTest(
            CGPoint(x: 4, y: 4),
            width: 160,
            height: 120,
            pointOfView: cameraNode,
            searchMode: .all
        )
        try require(miss.isEmpty, "corner hit unexpectedly returned \(miss.count) node(s)")
        log("hitTest smoke passed hits=\(hits.count)")
    }

    private static func runActionSmoke() throws {
        let scene = SCNScene()
        let movingNode = SCNNode()
        scene.rootNode.addChildNode(movingNode)
        var sequenceCompletions = 0
        movingNode.runAction(.sequence([
            .move(by: SCNVector3(1, 0, 0), duration: 1),
            .rotateBy(x: 0, y: .pi, z: 0, duration: 1),
            .scale(by: 2, duration: 1),
        ])) {
            sequenceCompletions += 1
        }

        scene.quillStepActions(by: 1.5)
        try require(abs(movingNode.position.x - 1) < 0.0001, "sequence action lost completed move")
        try require(abs(movingNode.eulerAngles.y - .pi / 2) < 0.0001, "sequence action did not sample partial rotation")
        try require(movingNode.scale == SCNVector3(1, 1, 1), "sequence action scaled before reaching scale step")
        try require(sequenceCompletions == 0, "sequence action completed before its final step")

        scene.quillStepActions(by: 1.5)
        try require(abs(movingNode.eulerAngles.y - .pi) < 0.0001, "sequence action did not finish rotation")
        try require(movingNode.scale == SCNVector3(2, 2, 2), "sequence action did not finish scale")
        try require(!movingNode.hasActions, "sequence action did not clear when complete")
        try require(sequenceCompletions == 1, "sequence action completion did not fire once")

        let groupNode = SCNNode()
        groupNode.runAction(.group([
            .move(by: SCNVector3(4, 0, 0), duration: 2),
            .fadeOpacity(to: 0.25, duration: 1),
        ]))
        groupNode.quillStepActions(by: 1)
        try require(abs(groupNode.position.x - 2) < 0.0001, "group action did not sample partial move")
        try require(abs(groupNode.opacity - 0.25) < 0.0001, "group action did not complete short fade")
        try require(groupNode.hasActions, "group action cleared before longest child completed")

        let repeated = SCNNode()
        let pattern = SCNAction.sequence([
            .move(by: SCNVector3(1, 0, 0), duration: 0.01),
            .rotateBy(x: 0, y: 0.5, z: 0, duration: 0.01),
        ])
        repeated.runAction(SCNAction.repeat(pattern, count: 300))
        repeated.quillStepActions(by: pattern.duration * 300)
        try require(abs(repeated.position.x - 300) < 0.0001, "composite repeat did not apply all completed move cycles")
        try require(abs(repeated.eulerAngles.y - 150) < 0.0001, "composite repeat did not apply all completed rotate cycles")
        try require(!repeated.hasActions, "finite repeat did not clear when complete")
        log("action smoke passed")
    }

    @MainActor
    private static func runGTKSceneViewSmoke() throws {
        log("GTK SceneView smoke starting")
        quillInstallGTKImageRendererBackend()
        log("GTK image renderer backend installed")
        log("rendering black reference")
        guard let black = quillRenderViewToImage(Color.black.frame(width: 180, height: 140), width: 180, height: 140) else {
            throw SmokeFailure.assertion("GTK black reference render returned nil")
        }
        let sceneView = SceneView(scene: makeSphereScene())
            .frame(width: 180, height: 140)
        log("rendering SceneView")
        guard let rendered = quillRenderViewToImage(sceneView, width: 180, height: 140) else {
            throw SmokeFailure.assertion("GTK SceneView render returned nil")
        }
        try require(rendered != black, "GTK SceneView render matched solid black reference")
        try require(rendered.count > black.count, "GTK SceneView render did not add structured PNG data: scene=\(rendered.count) black=\(black.count)")
        log("GTK SceneView smoke passed bytes=\(rendered.count) black=\(black.count)")
    }
}

private struct PixelStats: CustomStringConvertible {
    var nonBlackPixels = 0
    var redDominantPixels = 0
    var greenDominantPixels = 0
    var blueDominantPixels = 0
    var bounds = PixelBounds.empty

    var description: String {
        "nonBlack=\(nonBlackPixels) red=\(redDominantPixels) green=\(greenDominantPixels) blue=\(blueDominantPixels) bounds=\(bounds)"
    }

    init(_ image: CGImage) {
        guard let pixels = image.quillBGRAPixels else { return }
        let stride = image.quillBytesPerRow > 0 ? image.quillBytesPerRow : image.width * 4
        guard image.width > 0, image.height > 0, stride >= image.width * 4 else { return }

        for y in 0..<image.height {
            let row = y * stride
            for x in 0..<image.width {
                let offset = row + x * 4
                guard offset + 3 < pixels.count else { return }
                let b = Int(pixels[offset])
                let g = Int(pixels[offset + 1])
                let r = Int(pixels[offset + 2])
                let a = Int(pixels[offset + 3])
                if a > 0, r + g + b > 8 {
                    nonBlackPixels += 1
                    bounds.include(x: x, y: y)
                }
                if r > g * 2, r > b * 2 {
                    redDominantPixels += 1
                }
                if g > r * 2, g > b * 2 {
                    greenDominantPixels += 1
                }
                if b > r * 2, b > g * 2 {
                    blueDominantPixels += 1
                }
            }
        }
    }

    func dominantPixels(for color: DominantPixelColor) -> Int {
        switch color {
        case .red: redDominantPixels
        case .green: greenDominantPixels
        case .blue: blueDominantPixels
        }
    }

    static func dominantColor(atX x: Int, y: Int, in image: CGImage) -> DominantPixelColor? {
        guard let pixels = image.quillBGRAPixels else { return nil }
        let stride = image.quillBytesPerRow > 0 ? image.quillBytesPerRow : image.width * 4
        guard x >= 0, x < image.width, y >= 0, y < image.height, stride >= image.width * 4 else {
            return nil
        }

        let offset = y * stride + x * 4
        guard offset + 3 < pixels.count else { return nil }
        let b = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let r = Int(pixels[offset + 2])
        if r > g * 2, r > b * 2 {
            return .red
        }
        if g > r * 2, g > b * 2 {
            return .green
        }
        if b > r * 2, b > g * 2 {
            return .blue
        }
        return nil
    }
}

private struct AppleSceneKitGoldenEnvelope {
    static let sphere = AppleSceneKitGoldenEnvelope(
        nonBlackPixels: 2_260,
        dominantPixels: 2_260,
        dominantColor: .red,
        bounds: PixelBounds(minX: 53, minY: 33, maxX: 106, maxY: 86)
    )

    static let triangle = AppleSceneKitGoldenEnvelope(
        nonBlackPixels: 2_076,
        dominantPixels: 2_076,
        dominantColor: .green,
        bounds: PixelBounds(minX: 54, minY: 40, maxX: 125, maxY: 96)
    )

    let nonBlackPixels: Int
    let dominantPixels: Int
    let dominantColor: DominantPixelColor
    let bounds: PixelBounds
}

private enum DominantPixelColor {
    case red
    case green
    case blue
}

private struct PixelBounds: CustomStringConvertible {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    static let empty = PixelBounds(minX: Int.max, minY: Int.max, maxX: Int.min, maxY: Int.min)

    var description: String {
        guard minX <= maxX, minY <= maxY else { return "empty" }
        return "(\(minX),\(minY))-(\(maxX),\(maxY))"
    }

    mutating func include(x: Int, y: Int) {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}
