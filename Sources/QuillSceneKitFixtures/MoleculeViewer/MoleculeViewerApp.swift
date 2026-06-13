// QuillMoleculeViewer — in-repo SceneKit conformance fixture #2.
//
// Ball-and-stick molecule viewer written as a faithful macOS SwiftUI+SceneKit
// app. Beyond the solar-system fixture's surface it adds SCNCylinder,
// specular materials, directional lights, node pivots oriented with
// look(at:), and swapping a SceneView's scene from SwiftUI state.
// See docs/scenekit-conformance.md.
import SceneKit
import SwiftUI

@main
struct MoleculeViewerApp: App {
    var body: some Scene {
        WindowGroup("Molecules") {
            ContentView()
        }
        .defaultSize(width: 760, height: 560)
    }
}
