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

    public func quillRenderImage(width: Int? = nil, height: Int? = nil) -> CGImage? {
        guard let scene else { return nil }
        let resolvedWidth = width ?? max(1, Int(bounds.width.rounded()))
        let resolvedHeight = height ?? max(1, Int(bounds.height.rounded()))
        return scene.quillRenderImage(width: resolvedWidth, height: resolvedHeight, pointOfView: pointOfView)
    }

    open override func draw(_ rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = quillRenderImage(
                width: max(1, Int(rect.width.rounded())),
                height: max(1, Int(rect.height.rounded()))
              ) else {
            return
        }
        context.interpolationQuality = .none
        context.draw(image, in: rect)
    }

    public func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]? = nil) -> [SCNHitTestResult] {
        guard let scene else { return [] }
        let rawSearchMode = options?[.searchMode] as? Int
        let searchMode = rawSearchMode.flatMap(SCNHitTestSearchMode.init(rawValue:)) ?? .closest
        return scene.quillHitTest(
            point,
            width: max(1, Int(bounds.width.rounded())),
            height: max(1, Int(bounds.height.rounded())),
            pointOfView: pointOfView,
            searchMode: searchMode
        )
    }
}
#endif
