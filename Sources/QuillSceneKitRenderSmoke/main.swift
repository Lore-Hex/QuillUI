import Foundation
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

        let triangleStats = PixelStats(renderTriangleScene())
        try require(triangleStats.nonBlackPixels > 1_500, "triangle render stayed mostly black: \(triangleStats)")
        try require(triangleStats.greenDominantPixels > 1_400, "triangle render did not produce green pixels: \(triangleStats)")

        let nestedCameraStats = PixelStats(renderNestedCameraScene())
        try require(nestedCameraStats.nonBlackPixels > 1_000, "nested-camera render stayed mostly black: \(nestedCameraStats)")
        try require(nestedCameraStats.redDominantPixels > 900, "nested-camera render did not produce red pixels: \(nestedCameraStats)")

        try runHitTestSmoke()

        log("SceneKit render smoke passed")
        log("sphere: \(sphereStats)")
        log("triangle: \(triangleStats)")
        log("nested camera: \(nestedCameraStats)")

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

    @MainActor
    private static func runGTKSceneViewSmoke() throws {
        log("GTK SceneView smoke starting")
        quillInstallGTKImageRendererBackend()
        log("GTK image renderer backend installed")
        let sceneView = SceneView(scene: makeSphereScene())
            .frame(width: 180, height: 140)
        log("rendering SceneView")
        guard let rendered = quillRenderViewToImage(sceneView, width: 180, height: 140) else {
            throw SmokeFailure.assertion("GTK SceneView render returned nil")
        }
        log("rendering black reference")
        guard let black = quillRenderViewToImage(Color.black.frame(width: 180, height: 140), width: 180, height: 140) else {
            throw SmokeFailure.assertion("GTK black reference render returned nil")
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

    var description: String {
        "nonBlack=\(nonBlackPixels) red=\(redDominantPixels) green=\(greenDominantPixels)"
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
                }
                if r > g * 2, r > b * 2 {
                    redDominantPixels += 1
                }
                if g > r * 2, g > b * 2 {
                    greenDominantPixels += 1
                }
            }
        }
    }
}
