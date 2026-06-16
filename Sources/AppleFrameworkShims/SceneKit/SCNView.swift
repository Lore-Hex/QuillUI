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

public final class SCNCameraController: @unchecked Sendable {
    public var target = SCNVector3(0, 0, 0)
}

@MainActor open class SCNView: UIView {
    public var scene: SCNScene?
    public var pointOfView: SCNNode?
    public var allowsCameraControl: Bool = false
    public var autoenablesDefaultLighting: Bool = false
    public var rendersContinuously: Bool = false
    public var preferredFramesPerSecond: Int = 60
    public var isPlaying: Bool = false
    public var showsStatistics: Bool = false
    public var wantsLayer: Bool = false
    public var contentScaleFactor: CGFloat = 1
    public var defaultCameraController = SCNCameraController()
    public var antialiasingMode: SCNAntialiasingMode = .none
    public private(set) var appKitGestureRecognizers: [NSGestureRecognizer] = []

    open func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        appKitGestureRecognizers.append(gestureRecognizer)
    }

    public func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]? = nil) -> [SCNHitTestResult] {
        _ = (point, options)
        return []
    }
}
#endif
