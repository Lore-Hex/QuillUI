// QuillSolarSystem — in-repo SceneKit conformance fixture #1.
//
// A small solar-system viewer written as a faithful macOS SwiftUI+SceneKit
// app (it should compile unmodified against the real Apple SDKs). It pins
// down the first SCN surface the conformance campaign must make real:
// SCNScene/SCNNode graphs, SCNSphere geometry, materials (diffuse/emission),
// omni + ambient lights, a camera, repeating SCNActions, and SwiftUI's
// SceneView. See docs/scenekit-conformance.md.
import SceneKit
import SwiftUI

@main
struct SolarSystemApp: App {
    var body: some Scene {
        WindowGroup("Solar System") {
            ContentView()
        }
        .defaultSize(width: 900, height: 620)
    }
}
