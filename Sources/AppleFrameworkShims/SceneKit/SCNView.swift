#if canImport(UIKit)
import Foundation
import AppKit
import UIKit

public enum SCNAntialiasingMode: Int, Sendable {
    case none
    case multisampling2X
    case multisampling4X
}

public struct SCNHitTestOption: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let searchMode = SCNHitTestOption(rawValue: "SCNHitTestSearchMode")
}

public enum SCNHitTestSearchMode: Int, Sendable {
    case closest = 0
    case all = 1
}

public final class SCNHitTestResult: @unchecked Sendable {
    public let node: SCNNode
    public let geometryIndex: Int

    public init(node: SCNNode, geometryIndex: Int = 0) {
        self.node = node
        self.geometryIndex = geometryIndex
    }
}

@MainActor public protocol SCNCameraControllerDelegate: AnyObject {
    func cameraInertiaWillStart(for cameraController: SCNCameraController)
    func cameraInertiaDidEnd(for cameraController: SCNCameraController)
}

public extension SCNCameraControllerDelegate {
    func cameraInertiaWillStart(for cameraController: SCNCameraController) {
        _ = cameraController
    }

    func cameraInertiaDidEnd(for cameraController: SCNCameraController) {
        _ = cameraController
    }
}

@MainActor public final class SCNCameraController: @unchecked Sendable {
    public var target = SCNVector3(0, 0, 0)
    public weak var delegate: (any SCNCameraControllerDelegate)?
    public private(set) weak var pointOfView: SCNNode?

    func attach(pointOfView: SCNNode?) {
        self.pointOfView = pointOfView
    }

    public func rotateBy(x deltaX: CGFloat, y deltaY: CGFloat) {
        guard let pointOfView else { return }
        performInteraction {
            let center = Vector3(target)
            let current = Vector3(pointOfView.position)
            var offset = current - center
            if offset.length <= 0.0001 {
                offset = Vector3(0, 0, 1)
            }

            let distance = max(0.001, offset.length)
            var yaw = atan2(offset.x, offset.z)
            var pitch = asin(max(-0.999, min(0.999, offset.y / distance)))
            yaw += deltaX
            pitch = max(-(.pi / 2) + 0.001, min((.pi / 2) - 0.001, pitch + deltaY))

            let horizontal = cos(pitch) * distance
            let next = center + Vector3(
                sin(yaw) * horizontal,
                sin(pitch) * distance,
                cos(yaw) * horizontal
            )
            pointOfView.position = SCNVector3(next)
            pointOfView.look(at: target)
        }
    }

    public func translateInCameraSpaceBy(x deltaX: CGFloat, y deltaY: CGFloat, z deltaZ: CGFloat) {
        guard let pointOfView else { return }
        performInteraction {
            let cameraWorld = Matrix4.worldTransform(for: pointOfView)
            let right = cameraWorld.transformDirection(Vector3(1, 0, 0)).normalized(fallback: Vector3(1, 0, 0))
            let up = cameraWorld.transformDirection(Vector3(0, 1, 0)).normalized(fallback: Vector3(0, 1, 0))
            let forward = cameraWorld.transformDirection(Vector3(0, 0, -1)).normalized(fallback: Vector3(0, 0, -1))
            let delta = right * deltaX + up * deltaY + forward * deltaZ
            pointOfView.position = SCNVector3(Vector3(pointOfView.position) + delta)
            target = SCNVector3(Vector3(target) + delta)
        }
    }

    public func dolly(by delta: CGFloat) {
        guard let pointOfView else { return }
        performInteraction {
            let position = Vector3(pointOfView.position)
            let center = Vector3(target)
            let toTarget = center - position
            let distance = max(0.001, toTarget.length)
            let fallback = Matrix4.worldTransform(for: pointOfView)
                .transformDirection(Vector3(0, 0, -1))
                .normalized(fallback: Vector3(0, 0, -1))
            let direction = toTarget.normalized(fallback: fallback)
            let clampedDelta = max(-distance * 4, min(distance - 0.001, delta))
            pointOfView.position = SCNVector3(position + direction * clampedDelta)
            pointOfView.look(at: target)
        }
    }

    private func performInteraction(_ update: () -> Void) {
        delegate?.cameraInertiaWillStart(for: self)
        update()
        delegate?.cameraInertiaDidEnd(for: self)
    }
}

@MainActor open class SCNView: UIView {
    public var scene: SCNScene? {
        didSet {
            controlledCameraNode = nil
            syncDefaultCameraController()
            setNeedsDisplay()
        }
    }

    public var pointOfView: SCNNode? {
        didSet {
            if pointOfView !== controlledCameraNode {
                controlledCameraNode = nil
            }
            syncDefaultCameraController()
            setNeedsDisplay()
        }
    }

    public var allowsCameraControl: Bool = false {
        didSet {
            syncDefaultCameraController()
        }
    }

    public var autoenablesDefaultLighting: Bool = false
    public var rendersContinuously: Bool = false
    public var preferredFramesPerSecond: Int = 60
    public var isPlaying: Bool = false
    public var showsStatistics: Bool = false
    public var wantsLayer: Bool = false
    public var contentScaleFactor: CGFloat = 1
    public var defaultCameraController = SCNCameraController() {
        didSet {
            syncDefaultCameraController()
        }
    }
    public var antialiasingMode: SCNAntialiasingMode = .none
    public private(set) var appKitGestureRecognizers: [NSGestureRecognizer] = []
    private weak var controlledCameraNode: SCNNode?
    private var orbitDragLocation: CGPoint?
    private var panDragLocation: CGPoint?

    open func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        appKitGestureRecognizers.append(gestureRecognizer)
    }

    public func quillOrbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        guard allowsCameraControl, ensureControlledCamera() != nil else { return }
        defaultCameraController.rotateBy(x: deltaX, y: deltaY)
        setNeedsDisplay()
    }

    public func quillPanCamera(deltaX: CGFloat, deltaY: CGFloat) {
        guard allowsCameraControl, ensureControlledCamera() != nil else { return }
        defaultCameraController.translateInCameraSpaceBy(x: deltaX, y: deltaY, z: 0)
        setNeedsDisplay()
    }

    public func quillDollyCamera(delta: CGFloat) {
        guard allowsCameraControl, ensureControlledCamera() != nil else { return }
        defaultCameraController.dolly(by: delta)
        setNeedsDisplay()
    }

    open func mouseDown(with event: NSEvent) {
        orbitDragLocation = event.locationInWindow
    }

    open func mouseDragged(with event: NSEvent) {
        handleOrbitDrag(to: event.locationInWindow)
    }

    open func mouseUp(with event: NSEvent) {
        _ = event
        orbitDragLocation = nil
    }

    open func rightMouseDown(with event: NSEvent) {
        panDragLocation = event.locationInWindow
    }

    open func rightMouseDragged(with event: NSEvent) {
        handlePanDrag(to: event.locationInWindow)
    }

    open func rightMouseUp(with event: NSEvent) {
        _ = event
        panDragLocation = nil
    }

    open func scrollWheel(with event: NSEvent) {
        let scroll = quillSceneKitScrollDelta(from: event)
        guard scroll != 0 else { return }
        quillDollyCamera(delta: scroll * quillSceneKitCameraDistance(
            pointOfView: activeCameraNode,
            target: defaultCameraController.target
        ) * quillSceneKitDollyDistanceScalePerPoint)
    }

    open func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        quillDollyCamera(delta: event.magnification * quillSceneKitCameraDistance(
            pointOfView: activeCameraNode,
            target: defaultCameraController.target
        ))
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        orbitDragLocation = touches.first?.location(in: self)
        super.touchesBegan(touches, with: event)
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard allowsCameraControl, let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: self)
        let previous = touch.previousLocation(in: self)
        if touches.count > 1 {
            panCamera(from: previous, to: location)
        } else {
            orbitCamera(from: previous, to: location)
        }
        orbitDragLocation = location
        super.touchesMoved(touches, with: event)
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        orbitDragLocation = nil
        panDragLocation = nil
        super.touchesEnded(touches, with: event)
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        _ = touches
        orbitDragLocation = nil
        panDragLocation = nil
        super.touchesCancelled(touches, with: event)
    }

    public func quillRenderImage(width: Int? = nil, height: Int? = nil) -> CGImage? {
        guard let scene else { return nil }
        let resolvedWidth = width.map(QuillSceneKitRenderSupport.pixelCount)
            ?? QuillSceneKitRenderSupport.pixelCount(bounds.width)
        let resolvedHeight = height.map(QuillSceneKitRenderSupport.pixelCount)
            ?? QuillSceneKitRenderSupport.pixelCount(bounds.height)
        return scene.quillRenderImage(width: resolvedWidth, height: resolvedHeight, pointOfView: pointOfView)
    }

    public func snapshot() -> UIImage {
        guard let image = quillRenderImage() else {
            return UIImage(size: bounds.size)
        }
        return UIImage(cgImage: image, size: bounds.size)
    }

    open override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = quillRenderImage(
                width: QuillSceneKitRenderSupport.pixelCount(rect.width),
                height: QuillSceneKitRenderSupport.pixelCount(rect.height)
              ) else {
            return
        }
        context.interpolationQuality = .none
        context.draw(image, in: rect)
    }

    public func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]? = nil) -> [SCNHitTestResult] {
        guard let scene else { return [] }
        let searchMode = SCNHitTestSearchMode(optionValue: options?[.searchMode]) ?? .closest
        return scene.quillHitTest(
            point,
            width: QuillSceneKitRenderSupport.pixelCount(bounds.width),
            height: QuillSceneKitRenderSupport.pixelCount(bounds.height),
            pointOfView: pointOfView,
            searchMode: searchMode
        )
    }

    public func projectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let scene,
              let projected = scene.quillProjectPoint(
                point,
                width: QuillSceneKitRenderSupport.pixelCount(bounds.width),
                height: QuillSceneKitRenderSupport.pixelCount(bounds.height),
                pointOfView: pointOfView
              )
        else {
            return SCNVector3()
        }
        return projected
    }

    public func unprojectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let scene,
              let unprojected = scene.quillUnprojectPoint(
                point,
                width: QuillSceneKitRenderSupport.pixelCount(bounds.width),
                height: QuillSceneKitRenderSupport.pixelCount(bounds.height),
                pointOfView: pointOfView
              )
        else {
            return SCNVector3()
        }
        return unprojected
    }

    private func syncDefaultCameraController() {
        defaultCameraController.attach(pointOfView: activeCameraNode)
    }

    @discardableResult
    private func ensureControlledCamera() -> SCNNode? {
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

    private var activeCameraNode: SCNNode? {
        pointOfView ?? quillFirstSceneKitCameraNode(in: scene?.rootNode)
    }

    private var panUnitsPerPoint: CGFloat {
        quillSceneKitPanUnitsPerPoint(
            boundsSize: bounds.size,
            pointOfView: activeCameraNode,
            target: defaultCameraController.target
        )
    }

    private func handleOrbitDrag(to location: CGPoint) {
        guard let previous = orbitDragLocation else {
            orbitDragLocation = location
            return
        }
        orbitDragLocation = location
        orbitCamera(from: previous, to: location)
    }

    private func handlePanDrag(to location: CGPoint) {
        guard let previous = panDragLocation else {
            panDragLocation = location
            return
        }
        panDragLocation = location
        panCamera(from: previous, to: location)
    }

    private func orbitCamera(from previous: CGPoint, to location: CGPoint) {
        quillOrbitCamera(
            deltaX: (location.x - previous.x) * quillSceneKitOrbitRadiansPerPoint,
            deltaY: (location.y - previous.y) * quillSceneKitOrbitRadiansPerPoint
        )
    }

    private func panCamera(from previous: CGPoint, to location: CGPoint) {
        quillPanCamera(
            deltaX: (location.x - previous.x) * panUnitsPerPoint,
            deltaY: -(location.y - previous.y) * panUnitsPerPoint
        )
    }
}

let quillSceneKitOrbitRadiansPerPoint: CGFloat = 0.01
let quillSceneKitDollyDistanceScalePerPoint: CGFloat = 0.01

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

private extension SCNVector3 {
    init(_ vector: Vector3) {
        self.init(vector.x, vector.y, vector.z)
    }
}

private extension SCNHitTestSearchMode {
    init?(optionValue: Any?) {
        switch optionValue {
        case let value as SCNHitTestSearchMode:
            self = value
        case let value as Int:
            self.init(rawValue: value)
        case let value as NSNumber:
            self.init(rawValue: value.intValue)
        default:
            return nil
        }
    }
}
#endif
