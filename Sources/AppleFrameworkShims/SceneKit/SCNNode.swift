// SceneKit shim — the scene-graph node.
import Foundation
import QuillFoundation

public final class SCNNode: Equatable, @unchecked Sendable {
    public static func == (lhs: SCNNode, rhs: SCNNode) -> Bool {
        lhs === rhs
    }

    public var name: String?
    public var position = SCNVector3(0, 0, 0) { didSet { invalidateExplicitTransform() } }
    public var eulerAngles = SCNVector3(0, 0, 0) { didSet { invalidateExplicitTransform() } }
    public var scale = SCNVector3(1, 1, 1) { didSet { invalidateExplicitTransform() } }
    public var orientation = SCNQuaternion(0, 0, 0, 1) { didSet { invalidateExplicitTransform() } }
    public var transform: SCNMatrix4 {
        get { explicitTransform ?? quillComposedTransform() }
        set {
            explicitTransform = newValue
            applyTransformComponents(newValue)
        }
    }
    public var worldPosition: SCNVector3 {
        get {
            SCNVector3(Matrix4.worldTransform(for: self).transformPoint(.zero))
        }
        set {
            let parentWorld = parent.map(Matrix4.worldTransform) ?? .identity
            position = SCNVector3(parentWorld.inverted().transformPoint(Vector3(newValue)))
        }
    }
    public var worldOrientation: SCNQuaternion {
        get {
            let transform = Matrix4.worldTransform(for: self).scnMatrix
            return transform.quillOrientation(scale: transform.quillScale)
        }
        set {
            let parentTransform = parent.map(Matrix4.worldTransform)?.scnMatrix ?? SCNMatrix4Identity
            let parentOrientation = parentTransform.quillOrientation(scale: parentTransform.quillScale)
            let localOrientation = SCNMatrix4Mult(
                SCNMatrix4Invert(SCNMatrix4(quillQuaternion: parentOrientation)),
                SCNMatrix4(quillQuaternion: newValue)
            )
            orientation = localOrientation.quillOrientation(scale: localOrientation.quillScale)
            eulerAngles = SCNVector3(0, 0, 0)
        }
    }
    public var worldTransform: SCNMatrix4 {
        get { Matrix4.worldTransform(for: self).scnMatrix }
        set {
            let parentWorld = parent.map(Matrix4.worldTransform) ?? .identity
            transform = (parentWorld.inverted() * Matrix4(newValue)).scnMatrix
        }
    }
    public var pivot = SCNMatrix4Identity
    public var geometry: SCNGeometry?
    public var light: SCNLight?
    public var camera: SCNCamera?
    public var isHidden = false
    public var opacity: CGFloat = 1
    public var categoryBitMask: Int = 1
    public var renderingOrder: Int = 0

    public private(set) weak var parent: SCNNode?
    public private(set) var childNodes: [SCNNode] = []

    public var boundingBox: (min: SCNVector3, max: SCNVector3) {
        get { quillResolvedBoundingBox() ?? (SCNVector3(), SCNVector3()) }
        set { _ = newValue }
    }

    /// Actions started via `runAction`. They are retained as interpretable
    /// data so the shim can advance them deterministically.
    public private(set) var runningActions: [SCNAction] = []
    private var runningActionStates: [SCNActionRuntime.State] = []
    private var runningActionKeys: [String?] = []
    private var runningActionCompletions: [(() -> Void)?] = []
    private var explicitTransform: SCNMatrix4?
    private var isApplyingTransform = false

    public init() {}

    public init(geometry: SCNGeometry?) {
        self.geometry = geometry
    }

    public func addChildNode(_ child: SCNNode) {
        guard canAdopt(child) else { return }
        child.removeFromParentNode()
        child.parent = self
        childNodes.append(child)
    }

    public func insertChildNode(_ child: SCNNode, at index: Int) {
        guard canAdopt(child) else { return }
        child.removeFromParentNode()
        child.parent = self
        childNodes.insert(child, at: Swift.max(0, Swift.min(index, childNodes.count)))
    }

    public func removeFromParentNode() {
        guard let parent else { return }
        parent.childNodes.removeAll { $0 === self }
        self.parent = nil
    }

    public func removeAllChildNodes() {
        for child in childNodes {
            child.parent = nil
        }
        childNodes.removeAll()
    }

    public func replaceChildNode(_ oldChild: SCNNode, with newChild: SCNNode) {
        guard oldChild !== newChild,
              let index = childNodes.firstIndex(where: { $0 === oldChild }),
              canAdopt(newChild)
        else {
            return
        }

        newChild.removeFromParentNode()
        oldChild.parent = nil
        newChild.parent = self
        childNodes[index] = newChild
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

    public func getBoundingBoxMin(_ min: UnsafeMutablePointer<SCNVector3>?, max: UnsafeMutablePointer<SCNVector3>?) -> Bool {
        guard let box = quillResolvedBoundingBox() else {
            return false
        }

        min?.pointee = box.min
        max?.pointee = box.max
        return true
    }

    public func childNodes(passingTest predicate: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Bool) -> [SCNNode] {
        var matches: [SCNNode] = []
        var stop = ObjCBool(false)
        quillEnumerateDescendants(stop: &stop) { node, stopPointer in
            if predicate(node, stopPointer) {
                matches.append(node)
            }
        }
        return matches
    }

    public func enumerateChildNodes(_ block: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        quillEnumerateDescendants(stop: &stop, block)
    }

    public func enumerateHierarchy(_ block: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        block(self, &stop)
        guard !stop.boolValue else { return }
        quillEnumerateDescendants(stop: &stop, block)
    }

    public func clone() -> SCNNode {
        let node = SCNNode()
        quillCopyProperties(to: node)
        for child in childNodes {
            node.addChildNode(child.clone())
        }
        return node
    }

    public func flattenedClone() -> SCNNode {
        clone()
    }

    public func copy() -> Any {
        clone()
    }

    public func runAction(_ action: SCNAction) {
        appendAction(action, key: nil, completionHandler: nil)
    }

    public func runAction(_ action: SCNAction, completionHandler block: @escaping () -> Void) {
        appendAction(action, key: nil, completionHandler: block)
    }

    public func runAction(_ action: SCNAction, forKey key: String?) {
        runAction(action, forKey: key, completionHandler: nil)
    }

    public func runAction(_ action: SCNAction, forKey key: String?, completionHandler block: (() -> Void)?) {
        if let key {
            removeAction(forKey: key)
        }
        appendAction(action, key: key, completionHandler: block)
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
                runningActionCompletions.remove(at: index)
            }
        }
    }

    public func removeAllActions() {
        runningActions.removeAll()
        runningActionStates.removeAll()
        runningActionKeys.removeAll()
        runningActionCompletions.removeAll()
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

    public func convertPosition(_ position: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let worldPosition = Matrix4.worldTransform(for: self).transformPoint(Vector3(position))
        let destination = Self.quillWorldTransform(for: node).inverted()
        return SCNVector3(destination.transformPoint(worldPosition))
    }

    public func convertPosition(_ position: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let worldPosition = Self.quillWorldTransform(for: node).transformPoint(Vector3(position))
        let local = Matrix4.worldTransform(for: self).inverted()
        return SCNVector3(local.transformPoint(worldPosition))
    }

    public func convertVector(_ vector: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let worldVector = Matrix4.worldTransform(for: self).transformDirection(Vector3(vector))
        let destination = Self.quillWorldTransform(for: node).inverted()
        return SCNVector3(destination.transformDirection(worldVector))
    }

    public func convertVector(_ vector: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let worldVector = Self.quillWorldTransform(for: node).transformDirection(Vector3(vector))
        let local = Matrix4.worldTransform(for: self).inverted()
        return SCNVector3(local.transformDirection(worldVector))
    }

    private func appendAction(_ action: SCNAction, key: String?, completionHandler: (() -> Void)?) {
        runningActions.append(action)
        runningActionStates.append(SCNActionRuntime.State(baseline: SCNActionRuntime.Baseline(node: self)))
        runningActionKeys.append(key)
        runningActionCompletions.append(completionHandler)
    }

    private func canAdopt(_ child: SCNNode) -> Bool {
        guard child !== self else { return false }

        var ancestor = parent
        while let node = ancestor {
            if node === child { return false }
            ancestor = node.parent
        }

        return true
    }

    private func quillEnumerateDescendants(
        stop: inout ObjCBool,
        _ block: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {
        for child in childNodes {
            guard !stop.boolValue else { return }
            block(child, &stop)
            guard !stop.boolValue else { return }
            child.quillEnumerateDescendants(stop: &stop, block)
        }
    }

    private func quillCopyProperties(to node: SCNNode) {
        node.name = name
        node.position = position
        node.eulerAngles = eulerAngles
        node.scale = scale
        node.orientation = orientation
        node.explicitTransform = explicitTransform
        node.pivot = pivot
        node.geometry = geometry
        node.light = light
        node.camera = camera
        node.isHidden = isHidden
        node.opacity = opacity
        node.categoryBitMask = categoryBitMask
        node.renderingOrder = renderingOrder
    }

    private func quillResolvedBoundingBox() -> (min: SCNVector3, max: SCNVector3)? {
        var accumulator = QuillNodeBoundingBox()
        quillAccumulateBoundingBox(into: &accumulator, transform: .identity)
        return accumulator.result
    }

    private func quillAccumulateBoundingBox(into accumulator: inout QuillNodeBoundingBox, transform: Matrix4) {
        if let geometry {
            accumulator.include(geometry.boundingBox, transform: transform)
        }

        for child in childNodes {
            child.quillAccumulateBoundingBox(
                into: &accumulator,
                transform: transform * Matrix4.localTransform(for: child)
            )
        }
    }

    private func invalidateExplicitTransform() {
        if !isApplyingTransform {
            explicitTransform = nil
        }
    }

    private static func quillWorldTransform(for node: SCNNode?) -> Matrix4 {
        node.map(Matrix4.worldTransform) ?? .identity
    }

    private func applyTransformComponents(_ transform: SCNMatrix4) {
        isApplyingTransform = true
        defer { isApplyingTransform = false }

        position = SCNVector3(transform.m41, transform.m42, transform.m43)
        scale = transform.quillScale
        orientation = transform.quillOrientation(scale: scale)
        eulerAngles = SCNVector3(0, 0, 0)
    }

    private func quillComposedTransform() -> SCNMatrix4 {
        let scaled = SCNMatrix4MakeScale(scale.x, scale.y, scale.z)
        let oriented = SCNMatrix4Mult(scaled, SCNMatrix4(quillQuaternion: orientation))
        let pitched = SCNMatrix4Mult(oriented, SCNMatrix4MakeRotation(eulerAngles.x, 1, 0, 0))
        let yawed = SCNMatrix4Mult(pitched, SCNMatrix4MakeRotation(eulerAngles.y, 0, 1, 0))
        let rolled = SCNMatrix4Mult(yawed, SCNMatrix4MakeRotation(eulerAngles.z, 0, 0, 1))
        return SCNMatrix4Mult(rolled, SCNMatrix4MakeTranslation(position.x, position.y, position.z))
    }

    private func stepOwnActions(by deltaTime: TimeInterval) {
        guard !runningActions.isEmpty else { return }
        synchronizeActionRuntimeStorage()

        var nextActions: [SCNAction] = []
        var nextStates: [SCNActionRuntime.State] = []
        var nextKeys: [String?] = []
        var nextCompletions: [(() -> Void)?] = []
        var completions: [() -> Void] = []

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
                nextCompletions.append(runningActionCompletions[index])
            } else if let completion = runningActionCompletions[index] {
                completions.append(completion)
            }
        }

        runningActions = nextActions
        runningActionStates = nextStates
        runningActionKeys = nextKeys
        runningActionCompletions = nextCompletions

        for completion in completions {
            completion()
        }
    }

    private func synchronizeActionRuntimeStorage() {
        guard runningActionStates.count != runningActions.count ||
                runningActionKeys.count != runningActions.count ||
                runningActionCompletions.count != runningActions.count else {
            return
        }
        runningActionStates = runningActions.map { _ in
            SCNActionRuntime.State(baseline: SCNActionRuntime.Baseline(node: self))
        }
        runningActionKeys = Array(repeating: nil, count: runningActions.count)
        runningActionCompletions = Array(repeating: nil, count: runningActions.count)
    }
}

private struct QuillNodeBoundingBox {
    private(set) var hasBounds = false
    private(set) var min = Vector3(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
    private(set) var max = Vector3(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)

    var result: (min: SCNVector3, max: SCNVector3)? {
        guard hasBounds else { return nil }
        return (SCNVector3(min), SCNVector3(max))
    }

    mutating func include(_ box: (min: SCNVector3, max: SCNVector3), transform: Matrix4) {
        let min = box.min
        let max = box.max
        include(Vector3(min.x, min.y, min.z), transform: transform)
        include(Vector3(max.x, min.y, min.z), transform: transform)
        include(Vector3(min.x, max.y, min.z), transform: transform)
        include(Vector3(max.x, max.y, min.z), transform: transform)
        include(Vector3(min.x, min.y, max.z), transform: transform)
        include(Vector3(max.x, min.y, max.z), transform: transform)
        include(Vector3(min.x, max.y, max.z), transform: transform)
        include(Vector3(max.x, max.y, max.z), transform: transform)
    }

    private mutating func include(_ point: Vector3, transform: Matrix4) {
        let transformed = transform.transformPoint(point)
        guard transformed.x.isFinite, transformed.y.isFinite, transformed.z.isFinite else {
            return
        }

        hasBounds = true
        min = Vector3(
            Swift.min(min.x, transformed.x),
            Swift.min(min.y, transformed.y),
            Swift.min(min.z, transformed.z)
        )
        max = Vector3(
            Swift.max(max.x, transformed.x),
            Swift.max(max.y, transformed.y),
            Swift.max(max.z, transformed.z)
        )
    }
}

private extension SCNMatrix4 {
    init(quillQuaternion q: SCNQuaternion) {
        let length = (q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w).squareRoot()
        guard length > 0 else {
            self = SCNMatrix4Identity
            return
        }

        let x = q.x / length
        let y = q.y / length
        let z = q.z / length
        let w = q.w / length
        let xx = x * x
        let yy = y * y
        let zz = z * z
        let xy = x * y
        let xz = x * z
        let yz = y * z
        let wx = w * x
        let wy = w * y
        let wz = w * z

        self.init(
            m11: 1 - 2 * (yy + zz),
            m12: 2 * (xy + wz),
            m13: 2 * (xz - wy),
            m14: 0,
            m21: 2 * (xy - wz),
            m22: 1 - 2 * (xx + zz),
            m23: 2 * (yz + wx),
            m24: 0,
            m31: 2 * (xz + wy),
            m32: 2 * (yz - wx),
            m33: 1 - 2 * (xx + yy),
            m34: 0,
            m41: 0,
            m42: 0,
            m43: 0,
            m44: 1
        )
    }

    var quillScale: SCNVector3 {
        SCNVector3(
            (m11 * m11 + m12 * m12 + m13 * m13).squareRoot(),
            (m21 * m21 + m22 * m22 + m23 * m23).squareRoot(),
            (m31 * m31 + m32 * m32 + m33 * m33).squareRoot()
        )
    }

    func quillOrientation(scale: SCNVector3) -> SCNQuaternion {
        let sx = max(scale.x, 0.000001)
        let sy = max(scale.y, 0.000001)
        let sz = max(scale.z, 0.000001)

        let r00 = m11 / sx
        let r01 = m21 / sy
        let r02 = m31 / sz
        let r10 = m12 / sx
        let r11 = m22 / sy
        let r12 = m32 / sz
        let r20 = m13 / sx
        let r21 = m23 / sy
        let r22 = m33 / sz

        let trace = r00 + r11 + r22
        let x: CGFloat
        let y: CGFloat
        let z: CGFloat
        let w: CGFloat
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            w = 0.25 * s
            x = (r21 - r12) / s
            y = (r02 - r20) / s
            z = (r10 - r01) / s
        } else if r00 > r11, r00 > r22 {
            let s = (1 + r00 - r11 - r22).squareRoot() * 2
            w = (r21 - r12) / s
            x = 0.25 * s
            y = (r01 + r10) / s
            z = (r02 + r20) / s
        } else if r11 > r22 {
            let s = (1 + r11 - r00 - r22).squareRoot() * 2
            w = (r02 - r20) / s
            x = (r01 + r10) / s
            y = 0.25 * s
            z = (r12 + r21) / s
        } else {
            let s = (1 + r22 - r00 - r11).squareRoot() * 2
            w = (r10 - r01) / s
            x = (r02 + r20) / s
            y = (r12 + r21) / s
            z = 0.25 * s
        }

        return SCNQuaternion(x, y, z, w)
    }
}

private extension SCNVector3 {
    init(_ vector: Vector3) {
        self.init(vector.x, vector.y, vector.z)
    }
}
