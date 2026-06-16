// SceneKit shim — SwiftUI `SceneView`.
//
// Rung 2 provides the type + API so SwiftUI+SceneKit apps compile; the body
// is an inert placeholder. Rung 3 replaces the body with a software rasteriser
// that walks `scene.rootNode` and projects the primitives through the Cairo
// CGContext path.
import Foundation
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
        // Inert until rung 3. Black mirrors SceneKit's default backdrop.
        Color.black
    }
}
