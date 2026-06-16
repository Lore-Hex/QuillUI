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
private final class SceneKitRenderView: NSView {
    var scene: SCNScene?
    var options: SceneView.Options = []

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let pixelWidth = max(1, Int(bounds.width.rounded()))
        let pixelHeight = max(1, Int(bounds.height.rounded()))
        let image = scene?.quillRenderImage(width: pixelWidth, height: pixelHeight)
            ?? blackImage(width: pixelWidth, height: pixelHeight)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)
    }

    private func blackImage(width: Int, height: Int) -> CGImage {
        let image = CGImage()
        image.width = width
        image.height = height
        image.quillBytesPerRow = width * 4
        image.quillBGRAPixels = [UInt8](repeating: 0, count: width * height * 4)
        return image
    }
}
#endif
