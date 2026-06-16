import Euclid
import Foundation
import QuillFoundation
import SceneKit
import UIKit

enum EuclidSmokeFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case let .assertion(message): return message
        }
    }
}

@main
struct QuillEuclidRenderSmoke {
    static func main() throws {
        let mesh = Mesh.cube(size: 1.2, material: UIColor(red: 0.9, green: 0.1, blue: 0.15, alpha: 1))
        let geometry = SCNGeometry(mesh)
        let node = SCNNode(geometry: geometry)

        let scene = SCNScene()
        scene.background.contents = CGColor.black
        scene.rootNode.addChildNode(node)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(cameraNode)

        let image = scene.quillRenderImage(width: 180, height: 140)
        let stats = PixelStats(image)
        try require(stats.nonBlackPixels > 1_000, "Euclid mesh render stayed mostly black: \(stats)")
        try require(stats.redDominantPixels > 900, "Euclid mesh render did not preserve material color: \(stats)")

        print("Euclid SceneKit render smoke passed")
        print("pixels:", stats)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw EuclidSmokeFailure.assertion(message) }
    }
}

private struct PixelStats: CustomStringConvertible {
    var nonBlackPixels = 0
    var redDominantPixels = 0

    var description: String {
        "nonBlack=\(nonBlackPixels) red=\(redDominantPixels)"
    }

    init(_ image: CGImage) {
        guard let pixels = image.quillBGRAPixels else { return }
        let stride = image.quillBytesPerRow > 0 ? image.quillBytesPerRow : image.width * 4
        guard image.width > 0, image.height > 0, stride >= image.width * 4 else { return }

        for y in 0..<image.height {
            let row = y * stride
            for x in 0..<image.width {
                let offset = row + x * 4
                guard offset + 3 < pixels.count else { return }
                let b = Int(pixels[offset])
                let g = Int(pixels[offset + 1])
                let r = Int(pixels[offset + 2])
                let a = Int(pixels[offset + 3])
                if a > 0, r + g + b > 8 {
                    nonBlackPixels += 1
                }
                if r > g * 2, r > b * 2 {
                    redDominantPixels += 1
                }
            }
        }
    }
}
