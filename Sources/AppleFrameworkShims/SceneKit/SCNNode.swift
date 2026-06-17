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

    /// Actions started via `runAction`. They are retained as interpretable
    /// data so the shim can advance them deterministically.
    public private(set) var runningActions: [SCNAction] = []
    private var runningActionStates: [SCNActionRuntime.State] = []
    private var runningActionKeys: [String?] = []

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
        appendAction(action, key: nil)
    }

    public func runAction(_ action: SCNAction, forKey key: String?) {
        if let key {
            removeAction(forKey: key)
        }
        appendAction(action, key: key)
    }

    public func action(forKey key: String) -> SCNAction? {
        for index in runningActions.indices where runningActionKeys.indices.contains(index) {
            if runningActionKeys[index] == key {
                return runningActions[index]
            }
        }
        return nil
    }

    public var hasActions: Bool {
        !runningActions.isEmpty
    }

    public func removeAction(forKey key: String) {
        for index in runningActions.indices.reversed() where runningActionKeys.indices.contains(index) {
            if runningActionKeys[index] == key {
                runningActions.remove(at: index)
                runningActionStates.remove(at: index)
                runningActionKeys.remove(at: index)
            }
        }
    }

    public func removeAllActions() {
        runningActions.removeAll()
        runningActionStates.removeAll()
        runningActionKeys.removeAll()
    }

    public func quillStepActions(by deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime >= 0 else { return }
        stepOwnActions(by: deltaTime)
        for child in childNodes {
            child.quillStepActions(by: deltaTime)
        }
    }

    /// Orients the node so its local -Z axis points at `worldTarget`, +Y up.
    public func look(at worldTarget: SCNVector3) {
        let dx = worldTarget.x - position.x
        let dy = worldTarget.y - position.y
        let dz = worldTarget.z - position.z
        let horizontal = (dx * dx + dz * dz).squareRoot()
        // With this shim's row-major transform math, yaw 0 leaves local -Z
        // aimed down world -Z.
        let yaw = atan2(-dx, -dz)
        let pitch = atan2(dy, horizontal)
        eulerAngles = SCNVector3(pitch, yaw, 0)
    }

    private func appendAction(_ action: SCNAction, key: String?) {
        runningActions.append(action)
        runningActionStates.append(SCNActionRuntime.State(baseline: SCNActionRuntime.Baseline(node: self)))
        runningActionKeys.append(key)
    }

    private func stepOwnActions(by deltaTime: TimeInterval) {
        guard !runningActions.isEmpty else { return }
        synchronizeActionRuntimeStorage()

        var nextActions: [SCNAction] = []
        var nextStates: [SCNActionRuntime.State] = []
        var nextKeys: [String?] = []

        for index in runningActions.indices {
            let action = runningActions[index]
            var state = runningActionStates[index]
            state.elapsed += deltaTime

            let sample = SCNActionRuntime.sample(action, elapsed: state.elapsed, baseline: state.baseline)
            sample.apply(to: self)

            if !SCNActionRuntime.isComplete(action, after: state.elapsed) {
                nextActions.append(action)
                nextStates.append(state)
                nextKeys.append(runningActionKeys[index])
            }
        }

        runningActions = nextActions
        runningActionStates = nextStates
        runningActionKeys = nextKeys
    }

    private func synchronizeActionRuntimeStorage() {
        guard runningActionStates.count != runningActions.count || runningActionKeys.count != runningActions.count else {
            return
        }
        runningActionStates = runningActions.map { _ in
            SCNActionRuntime.State(baseline: SCNActionRuntime.Baseline(node: self))
        }
        runningActionKeys = Array(repeating: nil, count: runningActions.count)
    }
}
