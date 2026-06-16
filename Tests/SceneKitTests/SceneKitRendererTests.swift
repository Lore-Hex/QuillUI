import AppKit
import Testing
@testable import SceneKit
import QuillFoundation
import UIKit

struct SceneKitRendererTests {
    @Test("Software renderer draws colored sphere pixels")
    func rendersSpherePixels() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        let sphereNode = SCNNode(geometry: sphere)
        scene.rootNode.addChildNode(sphereNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 160, height: 120)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.redDominantPixels > 900)
    }

    @Test("Software renderer draws SCNGeometry source/element triangles")
    func rendersBufferedTriangleGeometry() {
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

        let image = scene.quillRenderImage(width: 180, height: 140)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_500)
        #expect(stats.greenDominantPixels > 1_400)
    }

    @Test("Software renderer resolves point-of-view camera transforms through parent nodes")
    func rendersWithNestedPointOfViewCamera() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let cameraParent = SCNNode()
        cameraParent.position = SCNVector3(0, 0, 4)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraParent.addChildNode(cameraNode)
        scene.rootNode.addChildNode(cameraParent)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.redDominantPixels > 900)
    }

    @Test("Software renderer respects camera orientation from look(at:)")
    func rendersWithSideCameraLookingAtTarget() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(4, 0, 0)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.redDominantPixels > 900)
    }

    @Test("Software renderer culls geometry behind the camera orientation")
    func cameraLookingAwayDoesNotRenderTarget() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        cameraNode.eulerAngles = SCNVector3(0, .pi, 0)
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels == 0)
    }

    @MainActor
    @Test("SCNView camera controls create a moved point-of-view camera")
    func scnViewCameraControlsCreateMovedCamera() {
        let (scene, cameraNode) = makeCameraControlScene()
        let view = makeCameraControlView(scene: scene, cameraNode: cameraNode)

        view.quillOrbitCamera(deltaX: .pi / 4, deltaY: .pi / 12)

        let movedCamera = view.pointOfView
        #expect(movedCamera !== cameraNode)
        #expect(abs(movedCamera?.position.x ?? 0) > 0.5)
        #expect(movedCamera?.camera !== cameraNode.camera)

        let image = view.quillRenderImage(width: 160, height: 120)
        #expect(image != nil)
        if let image {
            let stats = PixelStats(image)
            #expect(stats.nonBlackPixels > 500)
            #expect(stats.redDominantPixels > 400)
        }
    }

    @MainActor
    @Test("SCNView AppKit events drive camera control")
    func scnViewAppKitEventsDriveCameraControl() {
        let (scene, cameraNode) = makeCameraControlScene()
        let view = makeCameraControlView(scene: scene, cameraNode: cameraNode)

        let mouseDown = NSEvent()
        mouseDown.locationInWindow = CGPoint(x: 40, y: 40)
        let mouseDrag = NSEvent()
        mouseDrag.locationInWindow = CGPoint(x: 120, y: 70)

        view.mouseDown(with: mouseDown)
        view.mouseDragged(with: mouseDrag)

        let movedCamera = view.pointOfView
        #expect(movedCamera !== cameraNode)
        #expect(abs(movedCamera?.position.x ?? 0) > 0.25)

        let distanceBeforeScroll = distanceFromOrigin(movedCamera?.position ?? SCNVector3(0, 0, 0))
        let scroll = NSEvent()
        scroll.scrollingDeltaY = 20
        view.scrollWheel(with: scroll)
        let distanceAfterScroll = distanceFromOrigin(view.pointOfView?.position ?? SCNVector3(0, 0, 0))
        #expect(distanceAfterScroll < distanceBeforeScroll)
    }

    @MainActor
    @Test("SCNView UIKit touch movement drives camera control")
    func scnViewTouchEventsDriveCameraControl() {
        let (scene, cameraNode) = makeCameraControlScene()
        let view = makeCameraControlView(scene: scene, cameraNode: cameraNode)

        let touch = UITouch()
        touch.view = view
        touch.quillPreviousLocation = CGPoint(x: 40, y: 40)
        touch.quillLocation = CGPoint(x: 110, y: 70)

        view.touchesMoved([touch], with: UIEvent())

        let movedCamera = view.pointOfView
        #expect(movedCamera !== cameraNode)
        #expect(abs(movedCamera?.position.x ?? 0) > 0.25)
    }

    #if os(Linux)
    @MainActor
    @Test("SwiftUI SceneView backing view handles camera events")
    func sceneViewBackingViewHandlesCameraEvents() {
        let (scene, cameraNode) = makeCameraControlScene()
        let view = SceneKitRenderView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        view.scene = scene
        view.options = [.allowsCameraControl]
        view.defaultCameraController.target = SCNVector3(0, 0, 0)

        let mouseDown = NSEvent()
        mouseDown.locationInWindow = CGPoint(x: 20, y: 20)
        let mouseDrag = NSEvent()
        mouseDrag.locationInWindow = CGPoint(x: 120, y: 60)

        view.mouseDown(with: mouseDown)
        view.mouseDragged(with: mouseDrag)

        #expect(view.pointOfView !== cameraNode)
        #expect(abs(view.pointOfView?.position.x ?? 0) > 0.25)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: view.pointOfView)
        #expect(PixelStats(image).nonBlackPixels > 500)
    }
    #endif

    @Test("Software renderer hit testing returns nearest projected nodes")
    func hitTestsProjectedGeometryNearestFirst() {
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
        #expect(hits.first?.node === frontNode)
        #expect(hits.contains { $0.node === backNode })

        let miss = scene.quillHitTest(
            CGPoint(x: 4, y: 4),
            width: 160,
            height: 120,
            pointOfView: cameraNode,
            searchMode: .all
        )
        #expect(miss.isEmpty)
    }

    private func makeCameraControlScene() -> (scene: SCNScene, cameraNode: SCNNode) {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let cameraNode = SCNNode()
        cameraNode.name = "resetCamera"
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)
        return (scene, cameraNode)
    }

    @MainActor
    private func makeCameraControlView(scene: SCNScene, cameraNode: SCNNode) -> SCNView {
        let view = SCNView()
        view.bounds = CGRect(x: 0, y: 0, width: 160, height: 120)
        view.scene = scene
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(0, 0, 0)
        view.allowsCameraControl = true
        return view
    }

    private func distanceFromOrigin(_ point: SCNVector3) -> CGFloat {
        (point.x * point.x + point.y * point.y + point.z * point.z).squareRoot()
    }
}

private struct PixelStats {
    var nonBlackPixels = 0
    var redDominantPixels = 0
    var greenDominantPixels = 0

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
