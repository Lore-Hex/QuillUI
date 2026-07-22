#if canImport(UIKit)
import AppKit
import Foundation
import QuillFoundation
import UIKit

let quillSceneKitOrbitRadiansPerPoint: CGFloat = 0.01
let quillSceneKitDollyDistanceScalePerPoint: CGFloat = 0.01

@MainActor
final class QuillSceneKitCameraControlState {
    private weak var controlledCameraNode: SCNNode?
    private var orbitDragLocation: CGPoint?
    private var panDragLocation: CGPoint?

    func resetControlledCamera() {
        controlledCameraNode = nil
    }

    func pointOfViewDidChange(to pointOfView: SCNNode?) {
        if pointOfView !== controlledCameraNode {
            controlledCameraNode = nil
        }
    }

    func sync(controller: SCNCameraController, scene: SCNScene?, pointOfView: SCNNode?) {
        controller.attach(pointOfView: activeCameraNode(scene: scene, pointOfView: pointOfView))
    }

    func activeCameraNode(scene: SCNScene?, pointOfView: SCNNode?) -> SCNNode? {
        pointOfView ?? quillFirstSceneKitCameraNode(in: scene?.rootNode)
    }

    @discardableResult
    func ensureControlledCamera(scene: SCNScene?, pointOfView: inout SCNNode?) -> SCNNode? {
        if let controlledCameraNode {
            pointOfView = controlledCameraNode
            return controlledCameraNode
        }

        let source = pointOfView ?? quillFirstSceneKitCameraNode(in: scene?.rootNode)
        let cameraNode = quillCloneSceneKitCameraNode(from: source)
        scene?.rootNode.addChildNode(cameraNode)
        controlledCameraNode = cameraNode
        pointOfView = cameraNode
        return cameraNode
    }

    func beginOrbitDrag(at location: CGPoint) {
        orbitDragLocation = location
    }

    func beginPanDrag(at location: CGPoint) {
        panDragLocation = location
    }

    func clearOrbitDrag() {
        orbitDragLocation = nil
    }

    func clearPanDrag() {
        panDragLocation = nil
    }

    func clearDrags() {
        orbitDragLocation = nil
        panDragLocation = nil
    }

    func orbitDelta(to location: CGPoint) -> (deltaX: CGFloat, deltaY: CGFloat)? {
        defer { orbitDragLocation = location }
        guard let previous = orbitDragLocation else { return nil }
        return (
            deltaX: (location.x - previous.x) * quillSceneKitOrbitRadiansPerPoint,
            deltaY: (location.y - previous.y) * quillSceneKitOrbitRadiansPerPoint
        )
    }

    func panDelta(to location: CGPoint, unitsPerPoint: CGFloat) -> (deltaX: CGFloat, deltaY: CGFloat)? {
        defer { panDragLocation = location }
        guard let previous = panDragLocation else { return nil }
        return (
            deltaX: (location.x - previous.x) * unitsPerPoint,
            deltaY: -(location.y - previous.y) * unitsPerPoint
        )
    }

    func panUnitsPerPoint(boundsSize: CGSize, scene: SCNScene?, pointOfView: SCNNode?, target: SCNVector3) -> CGFloat {
        quillSceneKitPanUnitsPerPoint(
            boundsSize: boundsSize,
            pointOfView: activeCameraNode(scene: scene, pointOfView: pointOfView),
            target: target
        )
    }
}

func quillFirstSceneKitCameraNode(in node: SCNNode?) -> SCNNode? {
    guard let node else { return nil }
    if node.camera != nil { return node }
    for child in node.childNodes {
        if let found = quillFirstSceneKitCameraNode(in: child) {
            return found
        }
    }
    return nil
}

func quillCloneSceneKitCameraNode(from source: SCNNode?) -> SCNNode {
    let node = SCNNode()
    node.name = source?.name.map { "\($0).quillCameraControl" } ?? "quillCameraControl"
    node.position = source?.position ?? SCNVector3(0, 0, 4)
    node.eulerAngles = source?.eulerAngles ?? SCNVector3(0, 0, 0)
    node.scale = source?.scale ?? SCNVector3(1, 1, 1)
    node.orientation = source?.orientation ?? SCNQuaternion(0, 0, 0, 1)
    node.transform = source?.transform ?? SCNMatrix4Identity
    node.pivot = source?.pivot ?? SCNMatrix4Identity
    node.camera = quillCloneSceneKitCamera(source?.camera) ?? SCNCamera()
    return node
}

func quillSceneKitCameraDistance(pointOfView: SCNNode?, target: SCNVector3) -> CGFloat {
    guard let pointOfView else { return 4 }
    let offset = Vector3(pointOfView.position) - Vector3(target)
    return Swift.max(0.1, offset.length)
}

func quillSceneKitPanUnitsPerPoint(boundsSize: CGSize, pointOfView: SCNNode?, target: SCNVector3) -> CGFloat {
    let maximumDimension = Swift.max(boundsSize.width, boundsSize.height)
    guard maximumDimension > 0 else { return 0.01 }
    return quillSceneKitCameraDistance(pointOfView: pointOfView, target: target) / maximumDimension
}

func quillSceneKitScrollDelta(from event: NSEvent) -> CGFloat {
    if event.scrollingDeltaY != 0 { return event.scrollingDeltaY }
    if event.deltaY != 0 { return event.deltaY }
    return event.deltaZ
}

private func quillCloneSceneKitCamera(_ source: SCNCamera?) -> SCNCamera? {
    guard let source else { return nil }
    let camera = SCNCamera()
    camera.name = source.name
    camera.zNear = source.zNear
    camera.zFar = source.zFar
    camera.fieldOfView = source.fieldOfView
    camera.usesOrthographicProjection = source.usesOrthographicProjection
    camera.orthographicScale = source.orthographicScale
    camera.automaticallyAdjustsZRange = source.automaticallyAdjustsZRange
    return camera
}
#endif
