// SceneKit shim — SwiftUI `SceneView`.
//
// Rung 3 routes the retained SceneKit graph through the software renderer and
// the existing NSViewRepresentable/AppKit custom-draw GTK bridge.
import Foundation
import AppKit
import QuillFoundation
import SwiftUI

public struct SceneView: View {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let allowsCameraControl = Options(rawValue: 1 << 0)
        public static let autoenablesDefaultLighting = Options(rawValue: 1 << 1)
        public static let jitteringEnabled = Options(rawValue: 1 << 2)
        public static let temporalAntialiasingEnabled = Options(rawValue: 1 << 3)
        public static let rendersContinuously = Options(rawValue: 1 << 4)
    }

    private let scene: SCNScene?
    private let options: Options

    public init(scene: SCNScene? = nil, options: Options = []) {
        self.scene = scene
        self.options = options
    }

    public var body: some View {
        #if os(Linux)
        SceneKitRenderRepresentable(scene: scene, options: options)
        #else
        Color.black
        #endif
    }
}

#if os(Linux)
@MainActor
private struct SceneKitRenderRepresentable: NSViewRepresentable {
    let scene: SCNScene?
    let options: SceneView.Options

    func makeNSView(context: Context) -> SceneKitRenderView {
        let view = SceneKitRenderView()
        view.scene = scene
        view.options = options
        return view
    }

    func updateNSView(_ nsView: SceneKitRenderView, context: Context) {
        nsView.scene = scene
        nsView.options = options
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

@MainActor
final class SceneKitRenderView: NSView {
    var scene: SCNScene? {
        didSet {
            guard scene !== oldValue else { return }
            controlledCameraNode = nil
            pointOfView = nil
            syncDefaultCameraController()
            setNeedsDisplay(bounds)
        }
    }
    var options: SceneView.Options = [] {
        didSet {
            syncDefaultCameraController()
            setNeedsDisplay(bounds)
        }
    }
    var pointOfView: SCNNode? {
        didSet {
            if pointOfView !== controlledCameraNode {
                controlledCameraNode = nil
            }
            syncDefaultCameraController()
            setNeedsDisplay(bounds)
        }
    }
    var defaultCameraController = SCNCameraController() {
        didSet {
            syncDefaultCameraController()
        }
    }
    private weak var controlledCameraNode: SCNNode?
    private var orbitDragLocation: CGPoint?
    private var panDragLocation: CGPoint?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 0 ? bounds.width : 180
        let height = bounds.height > 0 ? bounds.height : 140
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let pixelWidth = QuillSceneKitRenderSupport.pixelCount(bounds.width)
        let pixelHeight = QuillSceneKitRenderSupport.pixelCount(bounds.height)
        let image = scene?.quillRenderImage(width: pixelWidth, height: pixelHeight, pointOfView: pointOfView)
            ?? QuillSceneKitRenderSupport.solidImage(width: pixelWidth, height: pixelHeight, b: 0, g: 0, r: 0)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        orbitDragLocation = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        handleOrbitDrag(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        _ = event
        orbitDragLocation = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        panDragLocation = event.locationInWindow
    }

    override func rightMouseDragged(with event: NSEvent) {
        handlePanDrag(to: event.locationInWindow)
    }

    override func rightMouseUp(with event: NSEvent) {
        _ = event
        panDragLocation = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let scroll = quillSceneKitScrollDelta(from: event)
        guard scroll != 0 else { return }
        quillDollyCamera(delta: scroll * quillSceneKitCameraDistance(
            pointOfView: activeCameraNode,
            target: defaultCameraController.target
        ) * quillSceneKitDollyDistanceScalePerPoint)
    }

    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
        quillDollyCamera(delta: event.magnification * quillSceneKitCameraDistance(
            pointOfView: activeCameraNode,
            target: defaultCameraController.target
        ))
    }

    func quillOrbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        guard options.contains(.allowsCameraControl), ensureControlledCamera() != nil else { return }
        defaultCameraController.rotateBy(x: deltaX, y: deltaY)
        setNeedsDisplay(bounds)
    }

    func quillPanCamera(deltaX: CGFloat, deltaY: CGFloat) {
        guard options.contains(.allowsCameraControl), ensureControlledCamera() != nil else { return }
        defaultCameraController.translateInCameraSpaceBy(x: deltaX, y: deltaY, z: 0)
        setNeedsDisplay(bounds)
    }

    func quillDollyCamera(delta: CGFloat) {
        guard options.contains(.allowsCameraControl), ensureControlledCamera() != nil else { return }
        defaultCameraController.dolly(by: delta)
        setNeedsDisplay(bounds)
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
        quillOrbitCamera(
            deltaX: (location.x - previous.x) * quillSceneKitOrbitRadiansPerPoint,
            deltaY: (location.y - previous.y) * quillSceneKitOrbitRadiansPerPoint
        )
    }

    private func handlePanDrag(to location: CGPoint) {
        guard let previous = panDragLocation else {
            panDragLocation = location
            return
        }
        panDragLocation = location
        quillPanCamera(
            deltaX: (location.x - previous.x) * panUnitsPerPoint,
            deltaY: -(location.y - previous.y) * panUnitsPerPoint
        )
    }
}
#endif
