// SceneKit shim — actions.
//
// Actions are modeled as a small interpretable tree (`kind`) rather than
// opaque blocks, so a later animation step can advance them (rotate a node,
// loop forever, run a sequence) without re-deriving intent.
import Foundation
import QuillFoundation

public enum SCNActionTimingMode: Int, Sendable {
    case linear = 0
    case easeIn = 1
    case easeOut = 2
    case easeInEaseOut = 3
}

public final class SCNAction: @unchecked Sendable {
    public indirect enum Kind: Sendable {
        case rotateBy(x: CGFloat, y: CGFloat, z: CGFloat)
        case rotateTo(x: CGFloat, y: CGFloat, z: CGFloat)
        case moveBy(x: CGFloat, y: CGFloat, z: CGFloat)
        case scaleBy(CGFloat)
        case fadeOpacity(to: CGFloat)
        case wait
        case repeatForever(SCNAction)
        case repeatCount(SCNAction, count: Int)
        case sequence([SCNAction])
        case group([SCNAction])
    }

    public let kind: Kind
    public var duration: TimeInterval
    public var timingMode: SCNActionTimingMode = .linear
    public var speed: CGFloat = 1

    init(kind: Kind, duration: TimeInterval) {
        self.kind = kind
        self.duration = duration
    }

    public static func rotateBy(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .rotateBy(x: x, y: y, z: z), duration: duration)
    }

    public static func rotateTo(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .rotateTo(x: x, y: y, z: z), duration: duration)
    }

    public static func move(by delta: SCNVector3, duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .moveBy(x: delta.x, y: delta.y, z: delta.z), duration: duration)
    }

    public static func scale(by scale: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .scaleBy(scale), duration: duration)
    }

    public static func fadeOpacity(to opacity: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .fadeOpacity(to: opacity), duration: duration)
    }

    public static func wait(duration: TimeInterval) -> SCNAction {
        SCNAction(kind: .wait, duration: duration)
    }

    public static func repeatForever(_ action: SCNAction) -> SCNAction {
        SCNAction(kind: .repeatForever(action), duration: action.duration)
    }

    public static func `repeat`(_ action: SCNAction, count: Int) -> SCNAction {
        let count = max(0, count)
        return SCNAction(kind: .repeatCount(action, count: count), duration: action.duration * Double(count))
    }

    public static func sequence(_ actions: [SCNAction]) -> SCNAction {
        SCNAction(kind: .sequence(actions), duration: actions.reduce(0) { $0 + $1.duration })
    }

    public static func group(_ actions: [SCNAction]) -> SCNAction {
        SCNAction(kind: .group(actions), duration: actions.map(\.duration).max() ?? 0)
    }
}
