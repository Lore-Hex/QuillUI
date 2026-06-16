import Foundation
import Combine
import UIKit

// RealityKit shim (Euclid Example's RealityKitViewController); inert on QuillOS.

public extension SIMD3 where Scalar == Float {
    static var one: SIMD3<Float> { SIMD3<Float>(repeating: 1) }
    init(_ value: Any) {
        _ = value
        self.init(repeating: 0)
    }
}

public struct simd_quatf: Sendable {
    public init() {}
    public init(_ rotation: Any) { _ = rotation }
}

public struct Transform: Sendable {
    public var scale: SIMD3<Float>
    public var rotation: simd_quatf
    public var translation: SIMD3<Float>

    public init(
        scale: SIMD3<Float> = .one,
        rotation: simd_quatf = simd_quatf(),
        translation: SIMD3<Float> = .zero
    ) {
        self.scale = scale
        self.rotation = rotation
        self.translation = translation
    }
}

@MainActor open class Entity: NSObject {
    public var transform = Transform()
    public private(set) var children: [Entity] = []

    public func addChild(_ child: Entity) {
        children.append(child)
    }
}

@MainActor public final class ModelEntity: Entity {
    public convenience init<T>(_ mesh: T) throws {
        self.init()
        _ = mesh
    }
}

@MainActor public final class AnchorEntity: Entity {
    public init(world: SIMD3<Float>) {
        _ = world
        super.init()
    }
}

public struct PerspectiveCameraComponent: Sendable {
    public var fieldOfViewInDegrees: Float = 60
    public init() {}
}

@MainActor public final class PerspectiveCamera: Entity {
    public var camera = PerspectiveCameraComponent()
}

public enum SceneEvents {
    public struct Update: Sendable {
        public init() {}
    }
}

@MainActor public final class Scene {
    public var anchors: [AnchorEntity] = []

    public func addAnchor(_ anchor: AnchorEntity) {
        anchors.append(anchor)
    }

    public func subscribe<Event>(
        to eventType: Event.Type,
        _ handler: @escaping (Event) -> Void
    ) -> AnyCancellable {
        _ = eventType
        _ = handler
        return AnyCancellable {}
    }
}

@MainActor public struct ARViewEnvironment {
    public enum Background {
        case color(UIColor)
    }

    public var background: Background?
    public init() {}
}

@MainActor open class ARView: UIView {
    public enum CameraMode {
        case nonAR
    }

    public var environment = ARViewEnvironment()
    public var scene = Scene()

    public override init() {
        super.init()
    }

    public init(
        frame: CGRect,
        cameraMode: CameraMode,
        automaticallyConfigureSession: Bool
    ) {
        _ = cameraMode
        _ = automaticallyConfigureSession
        super.init(frame: frame)
    }
}
