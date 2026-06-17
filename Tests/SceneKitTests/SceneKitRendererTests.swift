import AppKit
import Testing
@testable import SceneKit
import QuillFoundation
import UIKit

@Suite("SceneKit renderer", .serialized)
struct SceneKitRendererTests {
    @Test("Scene graph parenting rejects cycles")
    func sceneGraphParentingRejectsCycles() {
        let root = SCNNode()
        let child = SCNNode()
        let grandchild = SCNNode()
        root.addChildNode(child)
        child.addChildNode(grandchild)

        root.addChildNode(root)
        #expect(root.parent == nil)
        #expect(root.childNodes == [child])

        grandchild.addChildNode(root)
        #expect(root.parent == nil)
        #expect(child.parent === root)
        #expect(grandchild.parent === child)
        #expect(grandchild.childNodes.isEmpty)

        grandchild.insertChildNode(child, at: 0)
        #expect(child.parent === root)
        #expect(grandchild.childNodes.isEmpty)
    }

    @Test("SCNGeometry copy preserves primitive subtype parameters and metadata")
    func geometryCopyPreservesPrimitiveSubtypeParametersAndMetadata() throws {
        let material = SCNMaterial()
        material.name = "shared"

        let sphere = SCNSphere(radius: 2.5)
        sphere.name = "planet"
        sphere.materials = [material]
        sphere.geometrySourceChannels = [3, 5]
        sphere.isGeodesic = true
        sphere.segmentCount = 24

        let sphereCopy = try #require(sphere.copy() as? SCNSphere)
        #expect(sphereCopy !== sphere)
        #expect(sphereCopy.radius == 2.5)
        #expect(sphereCopy.isGeodesic)
        #expect(sphereCopy.segmentCount == 24)
        #expect(sphereCopy.name == "planet")
        #expect(sphereCopy.materials.first === material)
        #expect(sphereCopy.geometrySourceChannels?.map(\.intValue) == [3, 5])

        let text = SCNText(string: "Quill", extrusionDepth: 0.4)
        text.flatness = 0.2
        text.chamferRadius = 0.1
        let textCopy = try #require(text.copy() as? SCNText)
        #expect(textCopy.string as? String == "Quill")
        #expect(textCopy.extrusionDepth == 0.4)
        #expect(textCopy.flatness == 0.2)
        #expect(textCopy.chamferRadius == 0.1)
    }

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

    @Test("SCNGeometrySource decoder rejects unsupported or malformed vertex layouts")
    func geometrySourceDecoderRejectsMalformedLayouts() {
        let floats: [Float] = [1, 2, 3]
        let data = Data(bytes: floats, count: floats.count * MemoryLayout<Float>.size)

        let integerSource = SCNGeometrySource(
            data: data,
            semantic: .vertex,
            vectorCount: 1,
            usesFloatComponents: false,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: 0
        )
        #expect(integerSource.quillVector3Values().isEmpty)

        let negativeOffsetSource = SCNGeometrySource(
            data: data,
            semantic: .vertex,
            vectorCount: 1,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: -1,
            dataStride: 0
        )
        #expect(negativeOffsetSource.quillVector3Values().isEmpty)

        let shortStrideSource = SCNGeometrySource(
            data: data,
            semantic: .vertex,
            vectorCount: 1,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 2
        )
        #expect(shortStrideSource.quillVector3Values().isEmpty)

        let overflowingSource = SCNGeometrySource(
            data: data,
            semantic: .vertex,
            vectorCount: Int.max,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: Int.max
        )
        #expect(overflowingSource.quillVector3Values().isEmpty)
    }

    @Test("Software renderer applies material intensity and transparency")
    func rendererAppliesMaterialIntensityAndTransparency() {
        let zeroIntensity = SCNSphere(radius: 1)
        zeroIntensity.firstMaterial?.diffuse.intensity = 0
        #expect(PixelStats(renderParametricGeometry(zeroIntensity)).nonBlackPixels == 0)

        let transparent = SCNSphere(radius: 1)
        transparent.firstMaterial?.transparency = 0
        #expect(PixelStats(renderParametricGeometry(transparent)).nonBlackPixels == 0)

        let zeroEmission = SCNSphere(radius: 1)
        zeroEmission.firstMaterial?.emission.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        zeroEmission.firstMaterial?.emission.intensity = 0
        let stats = PixelStats(renderParametricGeometry(zeroEmission))
        #expect(stats.redDominantPixels > 900)
        #expect(stats.greenDominantPixels == 0)
    }

    @Test("Software renderer draws parametric planes")
    func rendersParametricPlaneGeometry() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let plane = SCNPlane(width: 2.0, height: 1.2)
        plane.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        let planeNode = SCNNode(geometry: plane)
        scene.rootNode.addChildNode(planeNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.greenDominantPixels > 900)
        #expect(scene.quillHitTest(
            CGPoint(x: 80, y: 60),
            width: 160,
            height: 120,
            pointOfView: cameraNode
        ).first?.node === planeNode)
    }

    @Test("Software renderer draws parametric pyramids")
    func rendersParametricPyramidGeometry() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let pyramid = SCNPyramid(width: 2.0, height: 1.8, length: 1.4)
        pyramid.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        let pyramidNode = SCNNode(geometry: pyramid)
        pyramidNode.eulerAngles = SCNVector3(-0.2, 0.35, 0)
        scene.rootNode.addChildNode(pyramidNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 700)
        #expect(stats.redDominantPixels > 650)
        #expect(scene.quillHitTest(
            CGPoint(x: 80, y: 60),
            width: 160,
            height: 120,
            pointOfView: cameraNode
        ).first?.node === pyramidNode)
    }

    @Test("Software renderer draws additional parametric primitives")
    func rendersAdditionalParametricGeometry() {
        let coneStats = PixelStats(renderParametricGeometry(SCNCone(topRadius: 0.15, bottomRadius: 0.9, height: 1.7)))
        #expect(coneStats.nonBlackPixels > 550)
        #expect(coneStats.redDominantPixels > 500)

        let capsuleStats = PixelStats(renderParametricGeometry(SCNCapsule(capRadius: 0.45, height: 1.8)))
        #expect(capsuleStats.nonBlackPixels > 500)
        #expect(capsuleStats.redDominantPixels > 450)

        let tubeStats = PixelStats(renderParametricGeometry(SCNTube(innerRadius: 0.35, outerRadius: 0.8, height: 1.5)))
        #expect(tubeStats.nonBlackPixels > 450)
        #expect(tubeStats.redDominantPixels > 400)

        let torusStats = PixelStats(renderParametricGeometry(SCNTorus(ringRadius: 0.65, pipeRadius: 0.25)))
        #expect(torusStats.nonBlackPixels > 600)
        #expect(torusStats.redDominantPixels > 550)
    }

    @Test("Polygon primitives advance past degenerate entries")
    func polygonPrimitiveDecoderAdvancesPastDegenerateEntries() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let vertices = [
            SCNVector3(-1.1, -0.9, 0),
            SCNVector3(1.1, -0.9, 0),
            SCNVector3(0, 0.95, 0),
        ]
        let rawIndices: [UInt32] = [
            2, 3,
            0, 1,
            0, 1, 2,
        ]
        let element = SCNGeometryElement(
            data: Data(bytes: rawIndices, count: rawIndices.count * MemoryLayout<UInt32>.size),
            primitiveType: .polygon,
            primitiveCount: 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [element]
        )
        geometry.firstMaterial?.diffuse.contents = RSColor(red: 0, green: 1, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: geometry))

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let stats = PixelStats(scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode))
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.greenDominantPixels > 900)
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

    @Test("Software renderer respects explicit camera clipping planes")
    func cameraClippingPlanesCullRenderAndHitTest() {
        let scene = SCNScene()
        scene.background.contents = CGColor.black

        let sphere = SCNSphere(radius: 1)
        sphere.firstMaterial?.diffuse.contents = RSColor(red: 1, green: 0, blue: 0, alpha: 1)
        scene.rootNode.addChildNode(SCNNode(geometry: sphere))

        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        var stats = PixelStats(scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode))
        #expect(stats.nonBlackPixels > 1_000)
        #expect(!scene.quillHitTest(CGPoint(x: 80, y: 60), width: 160, height: 120, pointOfView: cameraNode).isEmpty)

        camera.zNear = 4.5
        stats = PixelStats(scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode))
        #expect(stats.nonBlackPixels == 0)
        #expect(scene.quillHitTest(CGPoint(x: 80, y: 60), width: 160, height: 120, pointOfView: cameraNode).isEmpty)

        camera.zNear = 0.1
        camera.zFar = 3
        stats = PixelStats(scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode))
        #expect(stats.nonBlackPixels == 0)

        camera.zFar = 10
        stats = PixelStats(scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode))
        #expect(stats.nonBlackPixels > 1_000)
    }

    @Test("Software renderer clips partially visible triangles")
    func partiallyClippedTrianglesRemainVisible() {
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

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 1_000)
        #expect(stats.greenDominantPixels > 900)
        #expect(!scene.quillHitTest(CGPoint(x: 80, y: 80), width: 160, height: 120, pointOfView: cameraNode).isEmpty)
    }

    @Test("Software renderer clips partially visible line primitives")
    func partiallyClippedLinesRemainVisible() {
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

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.nonBlackPixels > 40)
        #expect(stats.greenDominantPixels > 40)
        #expect(!scene.quillHitTest(CGPoint(x: 80, y: 60), width: 160, height: 120, pointOfView: cameraNode).isEmpty)
    }

    @Test("Software renderer resolves intersecting triangles with per-pixel depth")
    func intersectingTrianglesUseZBuffer() {
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

        let image = scene.quillRenderImage(width: 160, height: 120, pointOfView: cameraNode)
        let stats = PixelStats(image)
        #expect(stats.redDominantPixels > 400)
        #expect(stats.greenDominantPixels > 400)
        #expect(PixelStats.dominantColor(atX: 80, y: 88, in: image) == .red)
        #expect(PixelStats.dominantColor(atX: 80, y: 42, in: image) == .green)
    }

    @Test("Software renderer stays inside Apple SceneKit golden envelopes")
    func softwareRendererMatchesAppleGoldenEnvelopes() {
        let (sphereScene, sphereCamera) = makeCameraControlScene()
        expect(
            PixelStats(sphereScene.quillRenderImage(width: 160, height: 120, pointOfView: sphereCamera)),
            matches: .sphere
        )

        let (triangleScene, triangleCamera) = makeTriangleGeometryScene()
        expect(
            PixelStats(triangleScene.quillRenderImage(width: 180, height: 140, pointOfView: triangleCamera)),
            matches: .triangle
        )

        let (sideScene, _) = makeCameraControlScene()
        let sideCamera = SCNNode()
        sideCamera.camera = SCNCamera()
        sideCamera.position = SCNVector3(4, 0, 0)
        sideCamera.look(at: SCNVector3(0, 0, 0))
        sideScene.rootNode.addChildNode(sideCamera)
        expect(
            PixelStats(sideScene.quillRenderImage(width: 160, height: 120, pointOfView: sideCamera)),
            matches: .sphere
        )
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

    @MainActor
    @Test("NSApplication dispatch drives SceneView camera controls")
    func applicationDispatchDrivesSceneViewCameraControls() {
        let (scene, cameraNode) = makeCameraControlScene()
        let view = SceneKitRenderView(frame: CGRect(x: 0, y: 0, width: 160, height: 120))
        view.scene = scene
        view.options = [.allowsCameraControl]
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3(0, 0, 0)

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 120),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        #expect(window.makeFirstResponder(view))

        let app = NSApplication.shared
        let previousWindows = app.windows
        let previousKeyWindow = app.keyWindow
        let previousMainWindow = app.mainWindow
        let previousCurrentEvent = app.currentEvent
        defer {
            app.windows = previousWindows
            app.keyWindow = previousKeyWindow
            app.mainWindow = previousMainWindow
            app.currentEvent = previousCurrentEvent
        }
        app.windows = [window]
        app.keyWindow = window
        app.mainWindow = window

        app.sendEvent(makeEvent(.leftMouseDown, window: window, location: CGPoint(x: 20, y: 20)))
        app.sendEvent(makeEvent(.leftMouseDragged, window: window, location: CGPoint(x: 120, y: 60)))

        #expect(view.pointOfView !== cameraNode)
        #expect(abs(view.pointOfView?.position.x ?? 0) > 0.25)

        let distanceBeforeMagnify = distanceFromOrigin(view.pointOfView?.position ?? SCNVector3(0, 0, 0))
        let magnify = makeEvent(.magnify, window: window, location: CGPoint(x: 80, y: 60))
        magnify.magnification = 0.25
        app.sendEvent(magnify)
        let distanceAfterMagnify = distanceFromOrigin(view.pointOfView?.position ?? SCNVector3(0, 0, 0))

        #expect(distanceAfterMagnify < distanceBeforeMagnify)
        #expect(app.currentEvent === magnify)
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

    @Test("SCNAction stepping advances primitives and clears completed actions")
    func actionSteppingAdvancesPrimitiveActions() {
        let node = SCNNode()
        var completions = 0
        node.runAction(.rotateBy(x: 0, y: .pi, z: 0, duration: 2)) {
            completions += 1
        }

        node.quillStepActions(by: 1)
        #expect(abs(node.eulerAngles.y - .pi / 2) < 0.0001)
        #expect(node.hasActions)
        #expect(completions == 0)

        node.quillStepActions(by: 1)
        #expect(abs(node.eulerAngles.y - .pi) < 0.0001)
        #expect(!node.hasActions)
        #expect(completions == 1)

        node.quillStepActions(by: 1)
        #expect(completions == 1)
    }

    @Test("Scene action stepping respects scene pause")
    func sceneActionSteppingRespectsPause() {
        let scene = SCNScene()
        let node = SCNNode()
        scene.rootNode.addChildNode(node)
        node.runAction(.move(by: SCNVector3(4, 0, 0), duration: 2))

        scene.isPaused = true
        scene.quillStepActions(by: 1)
        #expect(node.position.x == 0)
        #expect(node.hasActions)

        scene.isPaused = false
        scene.quillStepActions(by: 1)
        #expect(abs(node.position.x - 2) < 0.0001)
        #expect(node.hasActions)
    }

    @Test("SCNAction repeatForever keeps running and keyed actions replace prior actions")
    func repeatingActionsAdvanceAndKeyedActionsReplace() {
        let node = SCNNode()
        node.runAction(.repeatForever(.rotateBy(x: 0, y: .pi, z: 0, duration: 2)), forKey: "spin")

        node.quillStepActions(by: 1)
        #expect(abs(node.eulerAngles.y - .pi / 2) < 0.0001)
        node.quillStepActions(by: 2)
        #expect(abs(node.eulerAngles.y - .pi * 1.5) < 0.0001)
        #expect(node.hasActions)

        var replacedCompletionRan = false
        node.runAction(.wait(duration: 1), forKey: "spin") {
            replacedCompletionRan = true
        }

        let move = SCNAction.move(by: SCNVector3(4, 0, 0), duration: 2)
        node.runAction(move, forKey: "spin")
        #expect(node.runningActions.count == 1)
        #expect(node.action(forKey: "spin") === move)
        #expect(!replacedCompletionRan)

        node.quillStepActions(by: 1)
        #expect(abs(node.position.x - 2) < 0.0001)
        #expect(abs(node.eulerAngles.y - .pi * 1.5) < 0.0001)

        node.removeAction(forKey: "spin")
        #expect(!node.hasActions)

        let finite = SCNNode()
        finite.runAction(SCNAction.repeat(.move(by: SCNVector3(2, 0, 0), duration: 1), count: 2))
        finite.quillStepActions(by: 3)
        #expect(abs(finite.position.x - 4) < 0.0001)
        #expect(!finite.hasActions)
    }

    @Test("SCNAction sequence, group, and long composite repeats sample deterministically")
    func compositeActionsSampleDeterministically() {
        let sequenceNode = SCNNode()
        sequenceNode.runAction(.sequence([
            .move(by: SCNVector3(1, 0, 0), duration: 1),
            .rotateBy(x: 0, y: .pi, z: 0, duration: 1),
            .scale(by: 2, duration: 1),
        ]))

        sequenceNode.quillStepActions(by: 1.5)
        #expect(abs(sequenceNode.position.x - 1) < 0.0001)
        #expect(abs(sequenceNode.eulerAngles.y - .pi / 2) < 0.0001)
        #expect(sequenceNode.scale == SCNVector3(1, 1, 1))
        #expect(sequenceNode.hasActions)

        sequenceNode.quillStepActions(by: 1.5)
        #expect(abs(sequenceNode.eulerAngles.y - .pi) < 0.0001)
        #expect(sequenceNode.scale == SCNVector3(2, 2, 2))
        #expect(!sequenceNode.hasActions)

        let groupNode = SCNNode()
        groupNode.runAction(.group([
            .move(by: SCNVector3(4, 0, 0), duration: 2),
            .fadeOpacity(to: 0.25, duration: 1),
        ]))

        groupNode.quillStepActions(by: 1)
        #expect(abs(groupNode.position.x - 2) < 0.0001)
        #expect(abs(groupNode.opacity - 0.25) < 0.0001)
        #expect(groupNode.hasActions)

        let repeated = SCNNode()
        let pattern = SCNAction.sequence([
            .move(by: SCNVector3(1, 0, 0), duration: 0.01),
            .rotateBy(x: 0, y: 0.5, z: 0, duration: 0.01),
        ])
        repeated.runAction(SCNAction.repeat(pattern, count: 300))
        repeated.quillStepActions(by: pattern.duration * 300)
        #expect(abs(repeated.position.x - 300) < 0.0001)
        #expect(abs(repeated.eulerAngles.y - 150) < 0.0001)
        #expect(!repeated.hasActions)
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

    private func makeTriangleGeometryScene() -> (scene: SCNScene, cameraNode: SCNNode) {
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
        return (scene, cameraNode)
    }

    private func renderParametricGeometry(_ geometry: SCNGeometry) -> CGImage {
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

    private func makeEvent(_ type: NSEvent.EventType, window: NSWindow, location: CGPoint) -> NSEvent {
        let event = NSEvent()
        event.type = type
        event.window = window
        event.locationInWindow = location
        return event
    }

    private func expect(_ stats: PixelStats, matches reference: AppleSceneKitGoldenEnvelope) {
        // Captured from native macOS `SCNRenderer.snapshot` on this branch's
        // canonical scenes. The envelope allows small CPU/software projection
        // differences while still pinning area, color, and screen placement.
        #expect(abs(stats.nonBlackPixels - reference.nonBlackPixels) <= 180)
        #expect(abs(stats.dominantPixels(for: reference.dominantColor) - reference.dominantPixels) <= 180)
        #expect(abs(stats.bounds.minX - reference.bounds.minX) <= 8)
        #expect(abs(stats.bounds.minY - reference.bounds.minY) <= 8)
        #expect(abs(stats.bounds.maxX - reference.bounds.maxX) <= 8)
        #expect(abs(stats.bounds.maxY - reference.bounds.maxY) <= 8)
    }
}

private struct PixelStats {
    var nonBlackPixels = 0
    var redDominantPixels = 0
    var greenDominantPixels = 0
    var bounds = PixelBounds.empty

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
            }
        }
    }

    func dominantPixels(for color: DominantPixelColor) -> Int {
        switch color {
        case .red: redDominantPixels
        case .green: greenDominantPixels
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
}

private struct PixelBounds {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    static let empty = PixelBounds(minX: Int.max, minY: Int.max, maxX: Int.min, maxY: Int.min)

    mutating func include(x: Int, y: Int) {
        minX = min(minX, x)
        minY = min(minY, y)
        maxX = max(maxX, x)
        maxY = max(maxY, y)
    }
}
