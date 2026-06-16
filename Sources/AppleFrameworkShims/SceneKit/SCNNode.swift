// SceneKit shim — the scene-graph node.
import Foundation
import QuillFoundation

public final class SCNNode: Equatable, @unchecked Sendable {
    public static func == (lhs: SCNNode, rhs: SCNNode) -> Bool {
        lhs === rhs
    }

    public var name: String?
    public var position = SCNVector3(0, 0, 0)
    public var eulerAngles = SCNVector3(0, 0, 0)
    public var scale = SCNVector3(1, 1, 1)
    public var orientation = SCNQuaternion(0, 0, 0, 1)
    public var transform = SCNMatrix4Identity
    public var pivot = SCNMatrix4Identity
    public var geometry: SCNGeometry?
    public var light: SCNLight?
    public var camera: SCNCamera?
    public var isHidden = false
    public var opacity: CGFloat = 1
    public var categoryBitMask: Int = 1

    public private(set) weak var parent: SCNNode?
    public private(set) var childNodes: [SCNNode] = []

    /// Actions started via `runAction`. The renderer (rung 3) advances these;
    /// holding them keeps the scene graph self-describing in the meantime.
    public private(set) var runningActions: [SCNAction] = []

    public init() {}

    public init(geometry: SCNGeometry?) {
        self.geometry = geometry
    }

    public func addChildNode(_ child: SCNNode) {
        child.removeFromParentNode()
        child.parent = self
        childNodes.append(child)
    }

    public func insertChildNode(_ child: SCNNode, at index: Int) {
        child.removeFromParentNode()
        child.parent = self
        childNodes.insert(child, at: Swift.max(0, Swift.min(index, childNodes.count)))
    }

    public func removeFromParentNode() {
        guard let parent else { return }
        parent.childNodes.removeAll { $0 === self }
        self.parent = nil
    }

    public func childNode(withName name: String, recursively: Bool) -> SCNNode? {
        for child in childNodes {
            if child.name == name { return child }
            if recursively, let found = child.childNode(withName: name, recursively: true) {
                return found
            }
        }
        return nil
    }

    public func runAction(_ action: SCNAction) {
        runningActions.append(action)
    }

    public func runAction(_ action: SCNAction, forKey key: String?) {
        runningActions.append(action)
    }

    public func removeAllActions() {
        runningActions.removeAll()
    }

    /// Orients the node so its local -Z axis points at `worldTarget`, +Y up —
    /// the same contract as `SCNNode.look(at:)`. Encoded as Euler angles
    /// (yaw about Y, pitch about X); refined when the renderer lands.
    public func look(at worldTarget: SCNVector3) {
        let dx = worldTarget.x - position.x
        let dy = worldTarget.y - position.y
        let dz = worldTarget.z - position.z
        let horizontal = (dx * dx + dz * dz).squareRoot()
        // -Z forward: yaw rotates the -Z axis toward (dx, dz).
        let yaw = atan2(dx, dz)
        let pitch = atan2(dy, horizontal)
        eulerAngles = SCNVector3(pitch, yaw, 0)
    }
}
