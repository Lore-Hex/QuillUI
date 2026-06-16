// SceneKit shim — lights and cameras.
import Foundation
import QuillFoundation

public final class SCNLight: @unchecked Sendable {
    public enum LightType: String, Sendable {
        case ambient
        case omni
        case directional
        case spot
        case area
        case probe
        case IES
    }

    public var type: LightType = .omni
    /// NSColor / CGColor, as on macOS.
    public var color: Any? = nil
    public var shadowColor: Any? = nil
    public var intensity: CGFloat = 1000
    public var temperature: CGFloat = 6500
    public var castsShadow: Bool = false
    public var name: String?
    public var spotInnerAngle: CGFloat = 0
    public var spotOuterAngle: CGFloat = 45
    public var attenuationStartDistance: CGFloat = 0
    public var attenuationEndDistance: CGFloat = 0

    public init() {}
}

public final class SCNCamera: @unchecked Sendable {
    public var name: String?
    public var zNear: Double = 1
    public var zFar: Double = 100
    public var fieldOfView: CGFloat = 60
    public var usesOrthographicProjection: Bool = false
    public var orthographicScale: Double = 1
    public var automaticallyAdjustsZRange: Bool = false

    public init() {}
}
